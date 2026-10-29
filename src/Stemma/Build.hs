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
-- use the forms entering the stage. Joined forms inherited by a stage also
-- go through its morphophonology, after its rules.
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
import Data.List (intercalate, isPrefixOf, nub, partition, tails)
import Data.Maybe (fromMaybe, listToMaybe, maybeToList)
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
  -- here, the joined form if it went through morphophonology, the donor's
  -- form if it is an adapted loan, and otherwise 'Nothing'.
  , rxRuleOutput :: [Form]
  -- ^ What the rules produced, before any @irregular@ override.
  , rxForms :: [Form]
  , rxSteps :: [Step]
  , rxEvents :: [Text]
  -- ^ Descriptions of the events applied at this stage, and of the
  -- allomorphs chosen in a form joined here.
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
        case inlineRules engine proj of
          Left errs -> pure (Left errs)
          Right inline -> do
            actual <- runMode engine proj rules inline order Actual
            regular <- runMode engine proj rules inline order Regular
            case (actual, regular) of
              (Left e, _) -> pure (Left e)
              (_, Left e) -> pure (Left e)
              (Right (a0, wa), Right (g0, _)) -> do
                let a = presentAllomorphs proj a0
                    g = presentAllomorphs proj g0
                spA <- spell proj rules a
                spG <- spell proj rules g
                let built = Built proj order a g spA spG []
                pure (Right built {bWarnings = boundaryWarnings proj rules ++ wa ++ redundantIrregulars built
                                                 ++ allomorphWarnings built ++ citeWarnings built ++ outputWarnings rules built})

-- | The rules that analogies give inline, each compiled once by the engine.
inlineRules :: Engine -> Project -> Either [Text] (Map Text (Form -> [Form]))
inlineRules engine proj = case (texts, engineInline engine) of
  ([], _) -> Right Map.empty
  (_, Nothing) -> Left [engineName engine <> " cannot apply an analogy's `rule`"]
  (_, Just compile) -> case partitionEithers [compiled compile t | t <- texts] of
    ([], rs) -> Right (Map.fromList rs)
    (errs, _) -> Left errs
  where
    texts = nub [t | it <- Map.elems (prItems proj), Event {evKind = Analogy (ByRule t) _} <- itEvents it]
    compiled compile t = either (\e -> Left ("analogy rule " <> T.strip t <> ": " <> e)) (Right . (t,)) (compile t)

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
               , BSource (SLoan d _ _) <- [itBuild it] ]
    go done _ [] = Right (reverse done)
    go done visiting (s : rest)
      | s `elem` done = go done visiting rest
      | Set.member s visiting = Left ("loans form a cycle through stage " <> s)
      | otherwise = case filter (`notElem` done) (deps s) of
          [] -> go (s : done) (Set.delete s visiting) rest
          ds -> go done (Set.insert s visiting) (ds ++ s : rest)

runMode
  :: Engine -> Project -> Map RulesRef Rules -> Map Text (Form -> [Form]) -> [StageId] -> Mode
  -> IO (Either [Text] (Map StageId StageResults, [Text]))
runMode engine proj rules inline order mode = foldM stepStage (Right (Map.empty, [])) order
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

    -- The regular run ignores events, but not continuations: a cell that
    -- continues another is the same word, under a new paradigm.
    eventsAt s it = [ev | ev <- itEvents it, evAt ev == s, mode == Actual || isContinue ev]

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
              [ (i, it, f, Inherited) | (i, rx) <- Map.toList prev, f : _ <- [rxForms rx]
                        , Just it <- [Map.lookup i items], not (lostAt s it) ]
                ++ [ (itId it, it, [], Coined) | it <- Map.elems items, joinedEntering s it || returning prev s it ]
        loanForms <- donorForms results s [(i, it) | (i, it, _, _) <- survivors]
        let inputs :: LMap.Map ItemId (Either Text (Form, [Text], Origin))
            inputs = LMap.fromList
              [ (i, withItem i (foldl' (applyEvent s it loanForms inputs prev) (Right (f, [], origin))
                                       (zip [0 ..] (inputEvents s it))))
              | (i, it, f, origin) <- survivors ]
        joined <- case partitionEithers [ (,) i <$> v | (i, v) <- LMap.toList inputs ] of
          (errs@(_ : _), _) -> pure (Left errs)
          ([], ok) -> rejoin p s ok
        case joined of
          Left errs -> pure (Left errs)
          Right ok -> do
            evos <- case Map.lookup s stages >>= stRules >>= (`Map.lookup` rules) of
              Nothing -> pure [Evolution [f] [] | (_, (f, _, _)) <- ok]
              Just r -> rulesApply r [f | (_, (f, _, _)) <- ok]
            evos' <- remorph s ok evos
            let inherited = zipWith (inheritedReflex s) ok evos'
            case partitionEithers inherited of
              (errs@(_ : _), _) -> pure (Left errs)
              ([], rxs) -> do
                let res = Map.fromList [(i, rx) | (i, rx, _) <- rxs]
                    ws = concat [w | (_, _, w) <- rxs]
                    noRules = [ s <> ": no rules; forms are copied unchanged from " <> p
                              | mode == Actual, Nothing <- [Map.lookup s stages >>= stRules] ]
                fmap (fmap (fmap ((noRules ++ ws) ++))) (coin results s res)

    inputEvents s it = [ev | ev <- eventsAt s it, not (isIrregular ev)]
    -- An item formed at s that a rebuild there joins from the forms
    -- entering s (a cell that a later paradigm adds), rather than one
    -- coined from s's final forms. Only in the actual run: without events,
    -- it is coined.
    joinedEntering s it =
      itStage it == s && any (\ev -> isRebuild ev || isContinue ev) (eventsAt s it)
        && maybe False (const True) (Map.lookup s stages >>= stParent)
    isIrregular ev = case evKind ev of Irregular {} -> True; _ -> False
    -- A cell lost above, joined again here because the paradigm in force
    -- has it, or joined here on another line than where it is formed.
    returning prev s it =
      itStage it /= s && (itKind it == KCell || isAncestorOrSelf stages (itStage it) s)
        && not (Map.member (itId it) prev)
        && any (\ev -> isRebuild ev || isContinue ev) (eventsAt s it) && not (lostAt s it)
    isRebuild ev = case evKind ev of Rebuild {} -> True; Reform -> True; _ -> False
    isContinue ev = case evKind ev of Continue {} -> True; _ -> False

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

    -- Inherited forms joined from parts go through the stage's
    -- morphophonology after its rules, as forms coined here do.
    remorph s ok evos = case morphophonologyOf s of
      Nothing -> pure evos
      Just r -> do
        let flagged = [(isJoined i origin, evo) | ((i, (_, _, origin)), evo) <- zip ok evos]
        mevos <- rulesApply r (concat [evoOutputs evo | (True, evo) <- flagged])
        pure (attach flagged mevos)
      where
        attach ((True, evo) : rest) mevos =
          let (mine, others) = splitAt (length (evoOutputs evo)) mevos
          in Evolution (concatMap evoOutputs mine) (evoSteps evo ++ concatMap evoSteps (take 1 mine))
               : attach rest others
        attach ((False, evo) : rest) mevos = evo : attach rest mevos
        attach [] _ = []
        isJoined i origin = origin /= Borrowed && case itBuild (items Map.! i) of
          BSource SLoan {} -> False
          BSource _ -> True
          BForm _ -> False

    withItem i = either (Left . ((i <> ": ") <>)) Right

    -- A source joined from the forms of stage s, choosing allomorphs; also
    -- the choices made.
    joinFrom s bound look src = do
      ids <- sourceParts src
      forms <- traverse look ids
      (forms', chosen) <- chooseAllomorphs proj s look (zip (map Just ids) forms)
      pure (joinParts proj bound forms', chosen)

    -- Donor forms for loan events at this stage, adapted if requested.
    donorForms results s survivors = fmap Map.fromList $ fmap concat $
      forM survivors $ \(i, it) -> forM [ (k, ev) | (k, ev) <- zip [0 :: Int ..] (inputEvents s it) ] $ \(k, ev) ->
        case evKind ev of
          Loan from donorId adapt -> ((i, k),) . fmap snd3 <$> borrow results from (fromMaybe i donorId) adapt
          _ -> pure ((i, k), Right [])

    -- A donor's form at the end of a stage, run through the adaptation
    -- rules if given: the donor's form, the result, and the adaptation's
    -- steps.
    borrow results from did adapt = do
      let donor = Map.lookup from results >>= Map.lookup did >>= headMay . rxForms
      case (donor, adapt >>= (`Map.lookup` rules)) of
        (Nothing, _) -> pure (Left ("loan: " <> did <> " has no form at " <> from))
        (Just f, Nothing) -> pure (Right (f, f, []))
        (Just f, Just r) -> do
          evo <- rulesApply r [f]
          pure $ case evo of
            Evolution (f' : _) steps : _ -> Right (f, f', steps)
            _ -> Left "loan: adaptation deleted the word"
    snd3 (_, b, _) = b

    applyEvent s it loanForms inputs prev acc (k, ev) = do
      (f, descs, origin) <- acc
      case evKind ev of
        Analogy (ByRule t) model -> case Map.lookup t inline of
          Nothing -> Left ("analogy: rule not compiled: " <> T.strip t)
          Just apply -> case apply f of
            [] -> Left ("analogy: the rule " <> T.strip t <> " deleted the form")
            f' : _ -> pure (f', descs ++ ["analogy (" <> T.strip t <> ")" <> maybe "" (" after " <>) model], origin)
        Analogy (Replace repl) model -> do
          -- A replacement may be written with spaces between its graphemes.
          table <- forM repl $ \(from, to) -> do
            g <- tokeniseAt s from
            case g of
              [x] -> (x,) . concat <$> traverse (tokeniseAt s) (T.words to)
              _ -> Left ("analogy: " <> from <> " is not one grapheme at " <> s
                         <> "; replace maps single graphemes")
          let f' = concatMap (\g -> fromMaybe [g] (lookup g table)) f
          pure (f', descs ++ ["analogy" <> maybe "" (" after " <>) model], origin)
        Reform -> do
          src <- case itBuild it of
            BSource src -> Right src
            BForm _ -> Left "reform: item has no source to rebuild from"
          (f', chosen) <- joinFrom parent (itBound it) (entering "reform") src
          pure (f', descs ++ ["re-formed"] ++ chosen, origin)
        Rebuild stem base parts desc -> do
          baseForm <- maybe (entering "repattern" base) (tokeniseAt s) stem
          slots <- forM parts (\case
            PBase -> Right (maybe (Just base) (const Nothing) stem, baseForm)
            PAffix a -> (Just a,) <$> entering "repattern" a)
          (fs, chosen) <- chooseAllomorphs proj parent (entering "repattern") slots
          pure (joinParts proj (itBound it) fs, descs ++ [desc] ++ chosen, origin)
        -- The form carries over as it is: it was joined, and went through
        -- morphophonology, as the cell it continues.
        Continue from -> do
          g <- entering "continues" from
          pure (g, descs ++ ["continues " <> from], origin)
        Repattern {} -> pure (f, descs, origin)
        Loan from _ _ -> do
          f' <- fromMaybe (Left "loan: missing donor") (Map.lookup (itId it, k) loanForms)
          pure (f', descs ++ ["borrowed from " <> from], Borrowed)
        Irregular {} -> pure (f, descs, origin)
      where
        -- Events join from the forms entering this stage, which are the
        -- parent's, so the parent's allomorphs are in force.
        parent = fromMaybe s (Map.lookup s stages >>= stParent)
        -- Forms entering this stage, after their own events. An item lost
        -- here still enters with its form at the end of the parent.
        entering what x = case LMap.lookup x inputs of
          Just v -> (\(g, _, _) -> g) <$> v
          Nothing -> case Map.lookup x prev >>= listToMaybe . rxForms of
            Just g -> Right g
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
    coin results s available = do
      loans <- Map.fromList <$> sequence
        [ (itId it,) <$> borrow results from x adapt | it <- here, BSource (SLoan from x adapt) <- [itBuild it] ]
      go loans available here
      where
        here = [it | it <- Map.elems items, itStage it == s, not (joinedEntering s it)]
        hereIds = Set.fromList (map itId here)
        ignored =
          [ itId it <> ": events at " <> s <> " are ignored, since it is formed there"
          | mode == Actual, it <- here, any ((== s) . evAt) (itEvents it) ]

        go _ done [] = pure (Right (done, ignored ++ joinWarnings done))
        go loans done todo = do
          let waiting it = any (\d -> Set.member d hereIds && not (Map.member d done)) (coinDeps it)
              (ready, rest) = partition (not . waiting) todo
          case partitionEithers [withItem (itId it) ((itId it,) <$> coinOne loans done it) | it <- ready] of
            (errs@(_ : _), _) -> pure (Left errs)
            ([], _) | null ready -> pure (Left [itId it <> ": cannot be formed at " <> s | it <- rest])
            ([], built) -> do
              rxs <- joinCoined loans built
              go loans (Map.union done (Map.fromList rxs)) rest

        -- An item also waits for the allomorphs of the affixes it is
        -- built from.
        coinDeps it = itemDeps it ++ concat [allomorphItems dep | d <- itemDeps it, Just dep <- [Map.lookup d items]]

        lookupForm done x = case Map.lookup x done of
          Just rx -> maybe (Left (x <> " was deleted at " <> s)) Right (headMay (rxForms rx))
          Nothing -> Left (x <> " has no form at " <> s <> " (lost, or not yet formed?)")

        -- The form, the allomorphs chosen (or the adaptation applied), its
        -- origin, and whether it was joined from parts.
        coinOne loans done it = case itBuild it of
          BForm t -> (,[],Coined,False) <$> tokeniseAt s t
          BSource (SLoan _ _ adapt) -> do
            (_, f, _) <- fromMaybe (Left "loan: missing donor") (Map.lookup (itId it) loans)
            Right (f, ["adapted by " <> renderRulesRef r | Just r <- [adapt]], Borrowed, False)
          BSource src -> (\(f, chosen) -> (f, chosen, Coined, True)) <$> joinFrom s (itBound it) (lookupForm done) src

        -- Joined forms go through the stage's morphophonology.
        joinCoined loans built = do
          evos <- case morphophonologyOf s of
            Nothing -> pure []
            Just r -> rulesApply r [f | (_, (f, _, _, True)) <- built]
          pure (attach loans built evos)
        attach loans ((i, (f, chosen, origin, True)) : rest) (evo : evos) =
          let outs = evoOutputs evo
          in (i, Reflex (Just f) outs outs (evoSteps evo) chosen origin) : attach loans rest evos
        -- An adapted loan shows the donor's form as its input, and the
        -- adaptation's steps.
        attach loans ((i, (f, chosen, origin, _)) : rest) evos =
          let adapted = case (itBuild (items Map.! i), Map.lookup i loans) of
                (BSource (SLoan _ _ (Just _)), Just (Right (d, _, steps))) -> Reflex (Just d) [f] [f] steps
                _ -> Reflex Nothing [f] [f] []
          in (i, adapted chosen origin) : attach loans rest evos
        attach _ [] _ = []

        joinWarnings done = concat
          [ [ i <> " at " <> s <> ": morphophonology gave several outputs ("
                <> T.intercalate ", " (map renderForm (rxForms rx)) <> "); using the first"
            | length (rxForms rx) > 1 ]
              ++ [ i <> " at " <> s <> ": deleted by the morphophonology" | null (rxForms rx) ]
          | mode == Actual, it <- here, let i = itId it
          , Just rx <- [Map.lookup i done], Just _ <- [rxInput rx] ]

-- | The items a source is joined from, in order.
sourceParts :: Source -> Either Text [ItemId]
sourceParts = \case
  SBase b -> Right [b]
  SMorph b ps -> Right [case p of PBase -> b; PAffix a -> a | p <- ps]
  SCell b c -> Right [b <> "." <> c]
  SCompound xs -> Right xs
  SLoan {} -> Left "a loan source cannot be rebuilt"

-- | The allomorphs of an item in force in a form joined from the forms of
-- a stage: those given at the nearest stage on the path back to the root.
allomorphsFor :: Project -> StageId -> Item -> Maybe (StageId, [(Maybe Condition, ItemId)])
allomorphsFor proj s it = listToMaybe
  [ (d, als)
  | d <- ancestorsOrSelf (famStages (prFamily proj)) s
  , Just als <- [Map.lookup d (itAllomorphs it)] ]

-- | Replace the form of each part that has allomorphs in force at stage s
-- (the stage whose forms are joined) by the first allomorph whose
-- condition fits. Parts with @after@ conditions are chosen first, from left
-- to right, each seeing the parts before it as chosen so far; then parts
-- with @before@ conditions, from right to left, seeing everything after
-- them as chosen. Empty parts and boundaries are skipped, as 'joinParts'
-- skips them. Also returns a description of each choice.
chooseAllomorphs
  :: Project -> StageId -> (ItemId -> Either Text Form) -> [(Maybe ItemId, Form)]
  -> Either Text ([Form], [Text])
chooseAllomorphs proj s look parts = do
  let sets = [(k, it, set) | (k, (Just i, _)) <- zip [0 :: Int ..] parts, Just it <- [Map.lookup i (prItems proj)]
                           , Just set <- [allomorphsFor proj s it]]
      (befores, afters) = partition (\(_, _, (_, als)) -> any (isBefore . fst) als) sets
  (fs, chosenA) <- foldM (choose False) (map snd parts, []) afters
  (fs', chosenB) <- foldM (choose True) (fs, []) (reverse befores)
  pure (fs', chosenA ++ reverse chosenB)
  where
    isBefore = \case Just (Before _) -> True; _ -> False
    segments = filter ((/= famBoundary (prFamily proj)) . Just) . concat
    choose before (fs, chosen) (k, it, (d, als)) = do
      let neighbour
            | before = headMay (segments (drop (k + 1) fs))
            | otherwise = headMay (reverse (segments (take k fs)))
      case [(c, x) | (c, x) <- als, fits c neighbour] of
        (c, x) : _ -> do
          f <- look x
          let side = if before then "before " else "after "
              why = case c of
                Just _ -> maybe "" (side <>) neighbour
                Nothing -> "elsewhere" <> maybe "" ((", " <>) . (side <>)) neighbour
          pure ( [if j == k then f else g | (j, g) <- zip [0 ..] fs]
               , chosen ++ [itId it <> ": " <> showForm proj f <> " (" <> why <> ")"] )
        [] -> Left (itId it <> ": none of the allomorphs given at " <> d <> " fits "
                    <> maybe ("with nothing " <> (if before then "after" else "before") <> " it")
                             ((if before then "before " else "after ") <>) neighbour
                    <> ", and there is no elsewhere case")
    fits Nothing _ = True
    fits (Just (After gs)) (Just g) = g `elem` gs
    fits (Just (Before gs)) (Just g) = g `elem` gs
    fits _ Nothing = False

-- | Wherever an affix has allomorphs in force, its own reflex lists them:
-- its form evolved on its own never occurs. The internal items, which
-- carry the allomorphs and the stems given to cells, are then dropped.
presentAllomorphs :: Project -> Map StageId StageResults -> Map StageId StageResults
presentAllomorphs proj = Map.mapWithKey $ \s res ->
  let listed i rx = case Map.lookup i (prItems proj) >>= allomorphsFor proj s of
        Just (_, als)
          | fs@(_ : _) <- nub (concat [rxForms a | (_, x) <- als, Just a <- [Map.lookup x res]]) ->
              rx {rxForms = fs}
        _ -> rx
  in Map.filterWithKey (\i _ -> not (maybe False itInternal (Map.lookup i (prItems proj)))) (Map.mapWithKey listed res)

-- | Entries cited by a cell that has no form at a stage where they have one.
citeWarnings :: Built -> [Text]
citeWarnings b =
  [ itId it <> " at " <> s <> ": cited by " <> c <> ", which has no form there; give the entry or its paradigm a `cite`"
  | (s, res) <- Map.toList (bActual b)
  , it <- Map.elems (prItems (bProject b)), not (null (itCells it)), Map.member (itId it) res
  , let c = citedAt (bProject b) it s
  , c /= itId it, maybe True (null . rxForms) (Map.lookup c res) ]

-- | Allomorph lists without an elsewhere case, and conditions that can never
-- fit at a stage the affix is joined from, since no form there has the
-- grapheme.
allomorphWarnings :: Built -> [Text]
allomorphWarnings b =
  [ itId it <> ": the allomorphs at " <> d <> " have no elsewhere case"
  | it <- affixes, (d, als) <- Map.toList (itAllomorphs it), all ((/= Nothing) . fst) als ]
    ++
  [ itId it <> ": no form at " <> s <> " has " <> g <> ", so the condition on it in the allomorphs at "
      <> d <> " never fits there"
  | it <- affixes
  , s <- bStageOrder b
  , itId it `elem` Map.findWithDefault [] s joinedFrom
  , Just (d, als) <- [allomorphsFor proj s it]
  , g <- nub [g | (Just c, _) <- als, g <- case c of After gs -> gs; Before gs -> gs]
  , not (Set.member g (inventory s)) ]
  where
    proj = bProject b
    items = Map.elems (prItems proj)
    affixes = [it | it <- items, not (Map.null (itAllomorphs it))]
    parentOf s = Map.lookup s (famStages (prFamily proj)) >>= stParent
    sourceOf it = [ps | BSource src <- [itBuild it], Right ps <- [sourceParts src]]
    -- The items joined from each stage's forms: by items formed there, and
    -- by events at the stages below it.
    joinedFrom = Map.fromListWith (++) $
      [(itStage it, ps) | it <- items, ps <- sourceOf it]
        ++ [ (p, ps)
           | it <- items, Event {evAt, evKind} <- itEvents it, Just p <- [parentOf evAt]
           , ps <- case evKind of
               Reform -> sourceOf it
               Rebuild _ _ parts _ -> [[a | PAffix a <- parts]]
               _ -> [] ]
    inventory s = Set.fromList (concat [concat (rxForms rx) | rx <-maybe [] Map.elems (Map.lookup s (bActual b))])

-- | Concatenate the parts of a built form. With a boundary symbol, the
-- parts are joined with exactly one boundary between them, empty parts
-- (zero affixes) are skipped, and the boundaries at the outer edges are
-- kept only if the result is itself bound. With @internal-boundaries: false@
-- there are none inside the result, not even those inside the parts.
joinParts :: Project -> Bool -> [Form] -> Form
joinParts proj bound parts = case famBoundary (prFamily proj) of
  Nothing -> concat parts
  Just b ->
    let split = [x | x@(_, core, _) <- map (edges b) parts, not (null core)]
        lead = case split of (l, _, _) : _ | l -> [b]; _ -> []
        trail = case reverse split of (_, _, t) : _ | t -> [b]; _ -> []
        inner
          | famInternalBoundaries (prFamily proj) = intercalate [b] [core | (_, core, _) <- split]
          | otherwise = filter (/= b) (concat [core | (_, core, _) <- split])
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

-- | Problems in the forms a stage gives: U+FFFD, which Brassica puts in
-- place of a grapheme a categories block doesn't declare; graphemes the
-- stage's rules never declare, such as a multigraph made by a rule written
-- without spaces (@x r / xx@); and the sequences the stage forbids.
outputWarnings :: Map RulesRef Rules -> Built -> [Text]
outputWarnings rules b = concat
  [ [ s <> ": U+FFFD, in place of a grapheme a categories block doesn't declare, in " <> few bad
    | let bad = [(i, f) | (i, f) <- forms, "\xFFFD" `T.isInfixOf` f], not (null bad) ]
      ++ [ s <> ": U+FFFD in the spelling of " <> few bad
         | let bad = [ (i, t) | (i, ts) <- maybe [] Map.toList (Map.lookup s (bSpelled b))
                              , t <- ts, "\xFFFD" `T.isInfixOf` t ]
         , not (null bad) ]
      ++ [ s <> ": " <> g <> " is not declared in the rules, but is in " <> few bad
         | not (null (inventoryOf stRules))
         , g <- nub (concat (concatMap rxForms (Map.elems res)))
         , g /= "\xFFFD", not (Set.member g declared)
         , let bad = [(i, renderForm f) | (i, rx) <- Map.toList res, f <- rxForms rx, g `elem` f] ]
      ++ [ s <> ": " <> fbText fb <> " is forbidden, but is in " <> few bad
         | fb <- maybe [] stForbid (Map.lookup s stages)
         , let bad = [(i, renderForm f) | (i, rx) <- Map.toList res, f <- rxForms rx, forbidden fb f]
         , not (null bad) ]
  | (s, res) <- Map.toList (bActual b)
  , let forms = [(i, renderForm f) | (i, rx) <- Map.toList res, f <- rxForms rx]
        -- A stage is checked only if its rules declare their graphemes.
        inventoryOf field = concat [ rulesInventory r
                                   | Just ref <- [Map.lookup s stages >>= field]
                                   , Just r <- [Map.lookup ref rules] ]
        declared = Set.fromList $
          famGraphemes fam ++ maybeToList (famBoundary fam)
            ++ inventoryOf stRules ++ inventoryOf stMorphophonology ]
  where
    fam = prFamily (bProject b)
    stages = famStages fam
    few bad = T.intercalate ", " [f <> " (" <> i <> ")" | (i, f) <- take 5 bad]
      <> (if length bad > 5 then ", and " <> T.pack (show (length bad - 5)) <> " more" else "")
    -- Boundaries are ignored, so that a sequence is found across a
    -- morpheme boundary, but # doesn't match where a bound form attaches.
    forbidden Forbid {..} f =
      any fits (if fbStart then [core | not (open (listToMaybe f))] else tails core)
      where
        isBoundary g = Just g == famBoundary fam
        open = maybe False isBoundary
        core = filter (not . isBoundary) f
        fits xs = fbGraphemes `isPrefixOf` xs
          && (not fbEnd || (length xs == length fbGraphemes && not (open (listToMaybe (reverse f)))))

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
