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
-- A form joined from parts goes through the morphophonology of the stage
-- whose forms it is joined from: an item coined at a stage through that
-- stage's, and one rebuilt by an event through the parent's, since events
-- use the forms entering the stage.
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
  , showForm
  , checkExpectations
  ) where

import Control.Monad (foldM, forM)
import Data.Either (partitionEithers)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Map.Lazy qualified as LMap
import Data.List (intercalate, partition)
import Data.Maybe (fromMaybe, maybeToList)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T

import Stemma.Engine
import Stemma.Load
import Stemma.Sources (sourceFile)
import Stemma.Types

data Origin = Inherited | Coined | Borrowed
  deriving (Eq, Show)

data Reflex = Reflex
  { rxInput :: Maybe Form
  -- ^ What entered this stage's rules, after events. For items coined
  -- here, the joined form if it went through morphophonology, and
  -- otherwise 'Nothing'.
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
  let loaded =
        [ fmap (r,) $ case sourceFile (rrFile r) (prSources proj) of
            Nothing -> Left (renderRulesRef r <> ": no such rules file")
            Just bytes -> engineLoad engine r bytes
        | r <- Set.toList (projectRulesRefs proj) ]
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
            pure (Right built {bWarnings = boundaryWarnings proj rules ++ wa ++ redundantIrregulars built})

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
        ++ maybeToList (famBoundary (prFamily proj))
        ++ concat [ rulesGraphemes r
                  | c <- s : [c | (c, st) <- Map.toList stages, stParent st == Just s]
                  , Just ref <- [Map.lookup c stages >>= stRules]
                  , Just r <- [Map.lookup ref rules] ]
        ++ maybe [] rulesGraphemes (morphophonologyOf s)

    morphophonologyOf s = Map.lookup s stages >>= stMorphophonology >>= (`Map.lookup` rules)

    tokeniseAt s t
      | T.null (strip t) = Right []
      | otherwise = either (Left . (("cannot tokenise " <> t <> ": ") <>)) Right $
      engineTokenise engine (graphemesFor s) (strip t)
    -- `-` marks where a form attaches: a boundary, if the family has one.
    strip = case famBoundary (prFamily proj) of
      Nothing -> T.filter (`notElem` ("*-" :: String))
      Just b -> T.replace "-" b . T.filter (/= '*')

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
      Nothing -> coin results s Map.empty
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
        joined <- case partitionEithers [ (,) i <$> v | (i, v) <- LMap.toList inputs ] of
          (errs@(_ : _), _) -> pure (Left errs)
          ([], ok) -> rejoin p s ok
        case joined of
          Left errs -> pure (Left errs)
          Right ok -> do
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
                fmap (fmap (fmap ((noRules ++ ws) ++))) (coin results s res)

    inputEvents s it = [ev | ev <- eventsAt s it, not (isIrregular ev)]
    isIrregular ev = case evKind ev of Irregular {} -> True; _ -> False
    isRebuild ev = case evKind ev of Rebuild {} -> True; Reform -> True; _ -> False

    -- Items rebuilt from parts at s are joined from the forms entering s,
    -- so they go through the morphophonology of its parent p. A written
    -- root given a new stem is not joined from anything.
    rejoin p s ok = case morphophonologyOf p of
      Nothing -> pure (Right ok)
      Just r -> do
        let rebuilt i = let it = items Map.! i in
              any isRebuild (inputEvents s it) && case itBuild it of BSource _ -> True; BForm _ -> False
        evos <- rulesApply r [f | (i, (f, _, _)) <- ok, rebuilt i]
        pure $ case partitionEithers (attach rebuilt ok evos) of
          ([], ok') -> Right ok'
          (errs, _) -> Left errs
      where
        attach rebuilt ((i, (f, descs, origin)) : rest) (evo : evos)
          | rebuilt i = rejoined i f descs origin (evoOutputs evo) : attach rebuilt rest evos
        attach rebuilt (x : rest) evos = Right x : attach rebuilt rest evos
        attach _ [] _ = []
        rejoined i _ _ _ [] = Left (i <> ": the morphophonology of " <> p <> " deleted the rebuilt form")
        rejoined i f descs origin (f' : _)
          | f == f' = Right (i, (f, descs, origin))
          | otherwise = Right (i, (f', descs ++ ["morphophonology: " <> renderForm f <> " > " <> renderForm f'], origin))

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
          f' <- buildFrom (joinParts proj (itBound it)) (entering "reform") src
          pure (f', descs ++ ["re-formed"], origin)
        Rebuild stem base parts desc -> do
          baseForm <- maybe (entering "repattern" base) (tokeniseAt s) stem
          f' <- joinParts proj (itBound it) <$> forM parts (\case
            PBase -> Right baseForm
            PAffix a -> entering "repattern" a)
          pure (f', descs ++ [desc], origin)
        Repattern {} -> pure (f, descs, origin)
        Loan from _ _ -> do
          f' <- fromMaybe (Left "loan: missing donor") (Map.lookup (itId it, k) loanForms)
          pure (f', descs ++ ["borrowed from " <> from], Borrowed)
        Irregular {} -> pure (f, descs, origin)
      where
        -- Forms entering this stage, after their own events.
        entering what x = case LMap.lookup x inputs of
          Just v -> (\(g, _, _) -> g) <$> v
          Nothing -> Left (what <> ": " <> x <> " has no form at " <> s)

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

    -- Items coined at this stage, built from its final forms. They are
    -- built in rounds, each from the forms finished in the rounds before,
    -- so that an item built from another one coined here sees it after
    -- morphophonology.
    coin :: Map StageId StageResults -> StageId -> StageResults -> IO (Either [Text] (StageResults, [Text]))
    coin results s available = go available here
      where
        here = [it | it <- Map.elems items, itStage it == s]
        hereIds = Set.fromList (map itId here)
        ignored =
          [ itId it <> ": events at " <> s <> " are ignored, since it is formed there"
          | mode == Actual, it <- here, any ((== s) . evAt) (itEvents it) ]

        go done [] = pure (Right (done, ignored ++ joinWarnings done))
        go done todo = do
          let waiting it = any (\d -> Set.member d hereIds && not (Map.member d done)) (itemDeps it)
              (ready, rest) = partition (not . waiting) todo
          case partitionEithers [withItem (itId it) ((itId it,) <$> coinOne done it) | it <- ready] of
            (errs@(_ : _), _) -> pure (Left errs)
            ([], _) | null ready -> pure (Left [itId it <> ": cannot be formed at " <> s | it <- rest])
            ([], built) -> do
              rxs <- joinCoined built
              go (Map.union done (Map.fromList rxs)) rest

        lookupForm done x = case Map.lookup x done of
          Just rx -> maybe (Left (x <> " was deleted at " <> s)) Right (headMay (rxForms rx))
          Nothing -> Left (x <> " has no form at " <> s <> " (lost, or not yet formed?)")

        -- The form, its origin, and whether it was joined from parts.
        coinOne done it = case itBuild it of
          BForm t -> (,Coined,False) <$> tokeniseAt s t
          BSource (SLoan from x) ->
            case Map.lookup from results >>= Map.lookup x >>= headMay . rxForms of
              Just f -> Right (f, Borrowed, False)
              Nothing -> Left ("loan: " <> x <> " has no form at " <> from)
          BSource src -> (,Coined,True) <$> buildFrom (joinParts proj (itBound it)) (lookupForm done) src

        -- Joined forms go through the stage's morphophonology.
        joinCoined built = do
          evos <- case morphophonologyOf s of
            Nothing -> pure []
            Just r -> rulesApply r [f | (_, (f, _, True)) <- built]
          pure (attach built evos)
        attach ((i, (f, origin, True)) : rest) (evo : evos) =
          let outs = evoOutputs evo
          in (i, Reflex (Just f) outs outs (evoSteps evo) [] origin) : attach rest evos
        attach ((i, (f, origin, _)) : rest) evos = (i, Reflex Nothing [f] [f] [] [] origin) : attach rest evos
        attach [] _ = []

        joinWarnings done = concat
          [ [ i <> " at " <> s <> ": morphophonology gave several outputs ("
                <> T.intercalate ", " (map renderForm (rxForms rx)) <> "); using the first"
            | length (rxForms rx) > 1 ]
              ++ [ i <> " at " <> s <> ": deleted by the morphophonology" | null (rxForms rx) ]
          | mode == Actual, it <- here, let i = itId it
          , Just rx <- [Map.lookup i done], Just _ <- [rxInput rx] ]

buildFrom :: ([Form] -> Form) -> (ItemId -> Either Text Form) -> Source -> Either Text Form
buildFrom join look = \case
  SBase b -> join . pure <$> look b
  SMorph b ps -> join <$> traverse (look . part) ps
    where part = \case PBase -> b; PAffix a -> a
  SCell b c -> join . pure <$> look (b <> "." <> c)
  SCompound xs -> join <$> traverse look xs
  SLoan _ _ -> Left "a loan source cannot be rebuilt"

-- | Concatenate the parts of a built form. With a boundary symbol, the
-- parts are joined with exactly one boundary between them, empty parts
-- (zero affixes) are skipped, and the boundaries at the outer edges are
-- kept only if the result is itself bound.
joinParts :: Project -> Bool -> [Form] -> Form
joinParts proj bound parts = case famBoundary (prFamily proj) of
  Nothing -> concat parts
  Just b ->
    let split = [x | x@(_, core, _) <- map (edges b) parts, not (null core)]
        lead = case split of (l, _, _) : _ | l -> [b]; _ -> []
        trail = case reverse split of (_, _, t) : _ | t -> [b]; _ -> []
        inner = intercalate [b] [core | (_, core, _) <- split]
    in if bound then lead ++ inner ++ trail else inner

-- | Split off boundaries at the edges: whether there were any at the
-- start, the rest, and whether there were any at the end.
edges :: Text -> Form -> (Bool, Form, Bool)
edges b f =
  let (pre, rest) = span (== b) f
      (post, core) = span (== b) (reverse rest)
  in (not (null pre), reverse core, not (null post))

-- | A form for display: boundaries inside the word are dropped, and those
-- at its edges are shown as @-@, as in a citation form (/ber-/).
showForm :: Project -> Form -> Text
showForm proj f = case famBoundary (prFamily proj) of
  Nothing -> renderForm f
  Just b -> let (l, core, t) = edges b f in hyphenate l t (renderForm (filter (/= b) core))

hyphenate :: Bool -> Bool -> Text -> Text
hyphenate l t x = (if l then "-" else "") <> x <> (if t then "-" else "")

headMay :: [a] -> Maybe a
headMay (x : _) = Just x
headMay [] = Nothing

-- | Apply each stage's orthography, if it has one.
spell :: Project -> Map RulesRef Rules -> Map StageId StageResults -> IO (Map StageId (Map ItemId [Text]))
spell proj rules results = Map.traverseWithKey spellStage results
  where
    stages = famStages (prFamily proj)
    -- The orthography never sees boundaries: those inside the word are
    -- dropped, and those at the edges come back as hyphens.
    unbound f = case famBoundary (prFamily proj) of
      Nothing -> (False, f, False)
      Just b -> let (l, core, t) = edges b f in (l, filter (/= b) core, t)
    spellStage s res = case Map.lookup s stages >>= stOrthography >>= (`Map.lookup` rules) of
      Nothing -> pure (map (showForm proj) . rxForms <$> res)
      Just r -> do
        let keyed = [(i, unbound f) | (i, rx) <- Map.toList res, f <- rxForms rx]
        evos <- rulesApply r [core | (_, (_, core, _)) <- keyed]
        let spelled = zipWith (\(i, (l, _, t)) evo -> (i, map (hyphenate l t . renderForm) (take 1 (evoOutputs evo))))
                              keyed evos
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

-- | Problems that make a boundary symbol misbehave: Brassica replaces
-- undeclared graphemes with U+FFFD, and a bound item without a @-@ is
-- evolved as if it were a whole word.
boundaryWarnings :: Project -> Map RulesRef Rules -> [Text]
boundaryWarnings proj rules = case famBoundary (prFamily proj) of
  Nothing -> []
  Just b ->
    [ s <> ": the boundary " <> b <> " is not declared in " <> renderRulesRef ref
        <> "; Brassica will replace it with U+FFFD"
    | (s, st) <- Map.toList (famStages (prFamily proj))
    , Just ref <- [stRules st, stMorphophonology st], Just r <- [Map.lookup ref rules]
    , let gs = rulesGraphemes r, not (null gs), b `notElem` gs ]
      ++
    [ itId it <> ": bound, but its form has no - to mark where it attaches"
    | it <- Map.elems (prItems proj), itBound it
    , BForm t <- [itBuild it]
    , not (T.null (T.filter (/= '*') t)), not ("-" `T.isInfixOf` t) ]
