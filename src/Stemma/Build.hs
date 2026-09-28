-- | Computing every item's form at every stage.
--
-- Stages are processed parents first (and loan donors before recipients).
-- At each stage:
--
-- 1. Every item present at the parent stage (and not lost here) has the
--    events dated to this stage applied to its parent-stage form. This is
--    the stage's /input/.
-- 2. The stage's rules run on all inputs in one batch.
-- 3. @irregular@ events override the rule output.
-- 4. Items coined at this stage are built from the stage's final forms.
--
-- The build runs twice: once as written, and once with every event and
-- fate ignored. The second run gives the "regularly expected" forms that
-- notes can refer to with @!@.
module Stemma.Build
  ( Reflex (..)
  , Origin (..)
  , Built (..)
  , StageResults
  , build
  , spelledAt
  , checkExpectations
  ) where

import Control.Monad (foldM, forM)
import Data.Either (partitionEithers)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Map.Lazy qualified as LMap
import Data.Maybe (fromMaybe, maybeToList)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T

import Stemma.Engine
import Stemma.Load
import Stemma.Types

data Origin = Inherited | Coined | Borrowed
  deriving (Eq, Show)

data Reflex = Reflex
  { rxInput :: Maybe Form
  -- ^ What entered this stage's rules, after events. 'Nothing' for items
  -- coined here.
  , rxRuleOutput :: [Form]
  -- ^ What the rules produced, before any @irregular@ override.
  , rxForms :: [Form]
  , rxSteps :: [Step]
  , rxEvents :: [Text]
  -- ^ Descriptions of the events applied at this stage.
  , rxOrigin :: Origin
  }

type StageResults = Map ItemId Reflex

data Built = Built
  { bProject :: Project
  , bStageOrder :: [StageId]
  , bActual :: Map StageId StageResults
  , bRegular :: Map StageId StageResults
  , bSpelled :: Map StageId (Map ItemId [Text])
  , bRegularSpelled :: Map StageId (Map ItemId [Text])
  , bWarnings :: [Text]
  }

data Mode = Actual | Regular
  deriving (Eq)

build :: Engine -> Project -> IO (Either [Text] Built)
build engine proj = do
  loaded <- forM (Set.toList allRefs) $ \r ->
    fmap (r,) <$> engineLoad engine (prDir proj) r
  case partitionEithers loaded of
    (errs@(_ : _), _) -> pure (Left errs)
    ([], rs) -> case stageOrder proj of
      Left e -> pure (Left [e])
      Right order -> do
        let rules = Map.fromList rs
        actual <- runMode engine proj rules order Actual
        regular <- runMode engine proj rules order Regular
        case (actual, regular) of
          (Left e, _) -> pure (Left e)
          (_, Left e) -> pure (Left e)
          (Right (a, wa), Right (g, _)) -> do
            spA <- spell proj rules a
            spG <- spell proj rules g
            let built = Built proj order a g spA spG []
            pure (Right built {bWarnings = wa ++ redundantIrregulars built})
  where
    stages = famStages (prFamily proj)
    allRefs = Set.fromList $
      concat [maybeToList (stRules st) ++ maybeToList (stOrthography st) | st <- Map.elems stages]
        ++ [r | it <- Map.elems (prItems proj), Event {evKind = Loan _ _ (Just r)} <- itEvents it]

-- | Parents first, and loan donors before recipients.
stageOrder :: Project -> Either Text [StageId]
stageOrder proj = go [] Set.empty (prStageOrder proj)
  where
    stages = famStages (prFamily proj)
    deps s =
      maybeToList (Map.lookup s stages >>= stParent)
        ++ [ d | it <- Map.elems (prItems proj)
               , Event {evAt, evKind = Loan d _ _} <- itEvents it, evAt == s ]
        ++ [ d | it <- Map.elems (prItems proj), itStage it == s
               , BSource (SLoan d _) <- [itBuild it] ]
    go done _ [] = Right (reverse done)
    go done visiting (s : rest)
      | s `elem` done = go done visiting rest
      | Set.member s visiting = Left ("loans form a cycle through stage " <> s)
      | otherwise = case filter (`notElem` done) (deps s) of
          [] -> go (s : done) (Set.delete s visiting) rest
          ds -> go done (Set.insert s visiting) (ds ++ s : rest)

runMode
  :: Engine -> Project -> Map RulesRef Rules -> [StageId] -> Mode
  -> IO (Either [Text] (Map StageId StageResults, [Text]))
runMode engine proj rules order mode = foldM stepStage (Right (Map.empty, [])) order
  where
    stages = famStages (prFamily proj)
    items = prItems proj
    graphemesFor s =
      famGraphemes (prFamily proj)
        ++ concat [ rulesGraphemes r
                  | c <- s : [c | (c, st) <- Map.toList stages, stParent st == Just s]
                  , Just ref <- [Map.lookup c stages >>= stRules]
                  , Just r <- [Map.lookup ref rules] ]

    tokeniseAt s t
      | T.null (strip t) = Right []
      | otherwise = either (Left . (("cannot tokenise " <> t <> ": ") <>)) Right $
      engineTokenise engine (graphemesFor s) (strip t)
    strip = T.filter (`notElem` ("*-" :: String))

    eventsAt s it = if mode == Actual then [ev | ev <- itEvents it, evAt ev == s] else []

    lostAt s it = mode == Actual && Map.member s (itFate it)

    stepStage (Left e) _ = pure (Left e)
    stepStage (Right (results, warns)) s = do
      r <- stage results s
      pure $ case r of
        Left e -> Left e
        Right (res, w) -> Right (Map.insert s res results, warns ++ w)

    stage :: Map StageId StageResults -> StageId -> IO (Either [Text] (StageResults, [Text]))
    stage results s = case Map.lookup s stages >>= stParent of
      Nothing -> pure (coin results s Map.empty)
      Just p -> do
        let prev = fromMaybe Map.empty (Map.lookup p results)
            survivors =
              [ (i, it, f) | (i, rx) <- Map.toList prev, f : _ <- [rxForms rx]
                        , Just it <- [Map.lookup i items], not (lostAt s it) ]
        loanForms <- donorForms results s [(i, it) | (i, it, _) <- survivors]
        let inputs :: LMap.Map ItemId (Either Text (Form, [Text], Origin))
            inputs = LMap.fromList
              [ (i, withItem i (foldl' (applyEvent s it loanForms inputs) (Right (f, [], Inherited))
                                       (zip [0 ..] (inputEvents s it))))
              | (i, it, f) <- survivors ]
        case partitionEithers [ (,) i <$> v | (i, v) <- LMap.toList inputs ] of
          (errs@(_ : _), _) -> pure (Left errs)
          ([], ok) -> do
            evos <- case Map.lookup s stages >>= stRules >>= (`Map.lookup` rules) of
              Nothing -> pure [Evolution [f] [] | (_, (f, _, _)) <- ok]
              Just r -> rulesApply r [f | (_, (f, _, _)) <- ok]
            let inherited = zipWith (inheritedReflex s) ok evos
            case partitionEithers inherited of
              (errs@(_ : _), _) -> pure (Left errs)
              ([], rxs) -> do
                let res = Map.fromList [(i, rx) | (i, rx, _) <- rxs]
                    ws = concat [w | (_, _, w) <- rxs]
                    noRules = [ s <> ": no rules; forms are copied unchanged from " <> p
                              | mode == Actual, Nothing <- [Map.lookup s stages >>= stRules] ]
                pure $ fmap (fmap ((noRules ++ ws) ++)) (coin results s res)

    inputEvents s it = [ev | ev <- eventsAt s it, not (isIrregular ev)]
    isIrregular ev = case evKind ev of Irregular {} -> True; _ -> False

    withItem i = either (Left . ((i <> ": ") <>)) Right

    -- Donor forms for loan events at this stage, adapted if requested.
    donorForms results s survivors = fmap Map.fromList $ fmap concat $
      forM survivors $ \(i, it) -> forM [ (k, ev) | (k, ev) <- zip [0 :: Int ..] (inputEvents s it) ] $ \(k, ev) ->
        case evKind ev of
          Loan from donorId adapt -> do
            let did = fromMaybe i donorId
                donor = Map.lookup from results >>= Map.lookup did >>= headMay . rxForms
            case (donor, adapt >>= (`Map.lookup` rules)) of
              (Nothing, _) -> pure ((i, k), Left ("loan: " <> did <> " has no form at " <> from))
              (Just f, Nothing) -> pure ((i, k), Right f)
              (Just f, Just r) -> do
                evo <- rulesApply r [f]
                pure ((i, k), maybe (Left "loan: adaptation deleted the word") Right
                                    (headMay (concatMap evoOutputs evo)))
          _ -> pure ((i, k), Right [])

    applyEvent s it loanForms inputs acc (k, ev) = do
      (f, descs, origin) <- acc
      case evKind ev of
        Analogy repl model -> do
          table <- forM repl $ \(from, to) -> (from,) <$> tokeniseAt s to
          let f' = concatMap (\g -> fromMaybe [g] (lookup g table)) f
          pure (f', descs ++ ["analogy" <> maybe "" (" after " <>) model], origin)
        Reform -> do
          src <- case itBuild it of
            BSource src -> Right src
            BForm _ -> Left "reform: item has no source to rebuild from"
          f' <- buildFrom (\x -> case LMap.lookup x inputs of
                            Just v -> (\(g, _, _) -> g) <$> v
                            Nothing -> Left ("reform: " <> x <> " has no form at " <> s)) src
          pure (f', descs ++ ["re-formed"], origin)
        Loan from _ _ -> do
          f' <- fromMaybe (Left "loan: missing donor") (Map.lookup (itId it, k) loanForms)
          pure (f', descs ++ ["borrowed from " <> from], Borrowed)
        Irregular {} -> pure (f, descs, origin)

    inheritedReflex s (i, (inp, descs, origin)) evo = do
      let it = items Map.! i
          irregulars = [(form, reason) | Event {evKind = Irregular form reason} <- eventsAt s it]
          outs = evoOutputs evo
      (forms, descs') <- case irregulars of
        [] -> Right (outs, descs)
        (form, reason) : _ -> do
          f <- withItem i (tokeniseAt s form)
          Right ([f], descs ++ ["irregular" <> maybe "" (": " <>) reason])
      let warns =
            [ i <> " at " <> s <> ": rules gave several outputs ("
                <> T.intercalate ", " (map renderForm outs) <> "); using the first"
            | mode == Actual, length outs > 1 ]
              ++ [ i <> " at " <> s <> ": deleted by the rules" | mode == Actual, null forms ]
      pure (i, Reflex (Just inp) outs forms (evoSteps evo) descs' origin, warns)

    -- Items coined at this stage, built from its final forms.
    coin :: Map StageId StageResults -> StageId -> StageResults -> Either [Text] (StageResults, [Text])
    coin results s available =
      let here = [it | it <- Map.elems items, itStage it == s]
          coined :: LMap.Map ItemId (Either Text Reflex)
          coined = LMap.fromList [(itId it, withItem (itId it) (coinOne it)) | it <- here]
          lookupForm x = case Map.lookup x available of
            Just rx -> maybe (Left (x <> " was deleted by the rules at " <> s)) Right (headMay (rxForms rx))
            Nothing -> case LMap.lookup x coined of
              Just v -> v >>= maybe (Left (x <> " has no form")) Right . headMay . rxForms
              Nothing -> Left (x <> " has no form at " <> s <> " (lost, or not yet formed?)")
          coinOne it = do
            (f, origin) <- case itBuild it of
              BForm t -> (,Coined) <$> tokeniseAt s t
              BSource (SLoan from x) ->
                case Map.lookup from results >>= Map.lookup x >>= headMay . rxForms of
                  Just f -> Right (f, Borrowed)
                  Nothing -> Left ("loan: " <> x <> " has no form at " <> from)
              BSource src -> (,Coined) <$> buildFrom lookupForm src
            pure (Reflex Nothing [f] [f] [] [] origin)
          ignored =
            [ itId it <> ": events at " <> s <> " are ignored, since it is formed there"
            | mode == Actual, it <- here, any ((== s) . evAt) (itEvents it) ]
          (errs, ok) = partitionEithers [(,) i <$> v | (i, v) <- LMap.toList coined]
      in if null errs
           then Right (Map.union available (Map.fromList ok), ignored)
           else Left errs

buildFrom :: (ItemId -> Either Text Form) -> Source -> Either Text Form
buildFrom look = \case
  SBase b -> look b
  SMorph b as -> concat <$> traverse look (b : as)
  SCell b c -> look (b <> "." <> c)
  SCompound xs -> concat <$> traverse look xs
  SLoan _ _ -> Left "a loan source cannot be rebuilt"

headMay :: [a] -> Maybe a
headMay (x : _) = Just x
headMay [] = Nothing

-- | Apply each stage's orthography, if it has one.
spell :: Project -> Map RulesRef Rules -> Map StageId StageResults -> IO (Map StageId (Map ItemId [Text]))
spell proj rules results = Map.traverseWithKey spellStage results
  where
    stages = famStages (prFamily proj)
    spellStage s res = case Map.lookup s stages >>= stOrthography >>= (`Map.lookup` rules) of
      Nothing -> pure (map renderForm . rxForms <$> res)
      Just r -> do
        let keyed = [(i, f) | (i, rx) <- Map.toList res, f <- rxForms rx]
        evos <- rulesApply r (map snd keyed)
        let spelled = zipWith (\(i, _) evo -> (i, map renderForm (take 1 (evoOutputs evo)))) keyed evos
        pure (Map.union (Map.fromListWith (flip (++)) spelled) (const [] <$> res))

spelledAt :: Built -> Bool -> StageId -> ItemId -> Maybe [Text]
spelledAt b regular s i =
  Map.lookup s (if regular then bRegularSpelled b else bSpelled b) >>= Map.lookup i

-- | Every @expect@ that the build fails to reproduce.
checkExpectations :: Built -> [Text]
checkExpectations b =
  [ i <> " at " <> s <> ": expected " <> want <> ", got "
      <> maybe "nothing (no reflex)" (T.intercalate " ~ ") got
  | it <- Map.elems (prItems (bProject b))
  , let i = itId it
  , (s, want) <- Map.toList (itExpect it)
  , let got = spelledAt b False s i
  , maybe True (want `notElem`) got ]

-- | @irregular@ events whose form the rules now produce anyway.
redundantIrregulars :: Built -> [Text]
redundantIrregulars b =
  [ i <> " at " <> s <> ": the irregular form is now produced regularly; the event can go"
  | (s, res) <- Map.toList (bActual b)
  , (i, rx) <- Map.toList res
  , any ("irregular" `T.isPrefixOf`) (rxEvents rx)
  , rxRuleOutput rx == rxForms rx ]
