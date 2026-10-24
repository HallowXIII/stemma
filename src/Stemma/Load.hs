-- | Reading a project directory and flattening it into items.
--
-- Every thing that has a form at some stage is an 'Item': roots, affixes,
-- derivatives and paradigm cells alike. Cells are named @entry.CELL@.
module Stemma.Load
  ( Project (..)
  , Item (..)
  , ItemKind (..)
  , Build (..)
  , ParadigmDef (..)
  , loadProject
  , loadProjectWith
  , loadSources
  , projectRulesRefs
  , categoryIn
  , isAncestorOrSelf
  , ancestorsOrSelf
  , itemDeps
  , allomorphItems
  , paradigmAt
  , citedAt
  ) where

import Control.Applicative ((<|>))
import Control.Monad (forM_, unless, when)
import Data.ByteString (ByteString)
import Data.Foldable (toList)
import Data.List (elemIndex, nub, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe, maybeToList)
import Data.Ord (Down (..))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Yaml qualified as Y

import Stemma.Sources
import Stemma.Types

data Project = Project
  { prDir :: FilePath
  , prFamily :: Family
  , prRootStage :: StageId
  , prStageOrder :: [StageId]
  -- ^ Parents before children.
  , prItems :: Map ItemId Item
  , prItemOrder :: [ItemId]
  -- ^ The order items were written in.
  , prParadigms :: Map Text ParadigmDef
  , prSources :: Sources
  -- ^ The files the project was loaded from. Rules files are read from
  -- here when building.
  }

data ItemKind = KRoot | KAffix | KDerivative | KCell
  deriving (Eq, Show)

data Build = BForm Text | BSource Source
  deriving (Show)

data Item = Item
  { itId :: ItemId
  , itKind :: ItemKind
  , itOwner :: Maybe ItemId
  -- ^ The entry a derivative or cell belongs to.
  , itStage :: StageId
  -- ^ Where the item was formed.
  , itBuild :: Build
  , itBound :: Bool
  -- ^ Not a word on its own: an affix, a bound root or stem.
  , itGloss :: Maybe Text
  , itCategory :: [CatShift]
  , itNotes :: Maybe Text
  , itEvents :: [Event]
  , itFate :: Map StageId Fate
  , itExpect :: Map StageId Text
  , itCells :: [ItemId]
  , itParadigm :: Maybe Text
  , itRepatterns :: [(StageId, Text)]
  -- ^ Stages where the entry changes paradigm, and the new paradigm.
  , itAllomorphs :: Map StageId [(Maybe Condition, ItemId)]
  -- ^ For an affix: its allomorphs from each stage on, each with its
  -- condition and the internal item that carries its form there.
  , itInternal :: Bool
  -- ^ Built like any item, but left out of the item order and the build
  -- products: an allomorph, or a stem given to cells.
  , itCite :: Maybe Cite
  -- ^ The entry's own choice of the cell it is cited by.
  }
  deriving (Show)

-- | The internal items that carry an affix's allomorphs.
allomorphItems :: Item -> [ItemId]
allomorphItems it = [i | als <- Map.elems (itAllomorphs it), (_, i) <- als]

loadProject :: FilePath -> IO (Either [Text] Project)
loadProject = loadProjectWith id

-- | Load a project with its files changed first, to try an edit without
-- writing it.
loadProjectWith :: (Sources -> Sources) -> FilePath -> IO (Either [Text] Project)
loadProjectWith change dir = do
  src <- change <$> readSources dir
  case loadSources src of
    Left errs -> pure (Left errs)
    -- A rules file outside the project isn't in the sources yet.
    Right proj -> do
      src' <- readExtra dir [rrFile r | r <- Set.toList (projectRulesRefs proj)] src
      pure (Right proj {prSources = src'})

-- | Load a project from files already in memory.
loadSources :: Sources -> Either [Text] Project
loadSources src = do
  family <- fromMaybe (Left [T.pack (sourcePath src "family.yaml") <> ": not found"])
    (decodeYaml "family.yaml")
  morphology <- fromMaybe (Right (Morphology Map.empty Map.empty)) (decodeYaml "morphology.yaml")
  entries <- concat <$> sequence
    [ fromMaybe [] <$> decodeYaml' f b | (f, b) <- sourceFiles "lexicon" src, isYaml f ]
  assemble src family morphology entries
  where
    isYaml f = any (`T.isSuffixOf` T.pack f) [".yaml", ".yml"]
    decodeYaml f = decodeYaml' f <$> sourceFile f src
    decodeYaml' :: Y.FromJSON a => FilePath -> ByteString -> Either [Text] a
    decodeYaml' f b = case Y.decodeEither' b of
      Left e -> Left [T.pack (sourcePath src f) <> ": " <> T.pack (Y.prettyPrintParseException e)]
      Right a -> Right a

-- | Every rules file the project refers to.
projectRulesRefs :: Project -> Set RulesRef
projectRulesRefs proj = Set.fromList $
  concat [ maybeToList (stRules st) ++ maybeToList (stMorphophonology st) ++ maybeToList (stOrthography st)
         | st <- Map.elems (famStages (prFamily proj)) ]
    ++ [r | it <- Map.elems (prItems proj), Event {evKind = Loan _ _ (Just r)} <- itEvents it]
    ++ [r | it <- Map.elems (prItems proj), BSource (SLoan _ _ (Just r)) <- [itBuild it]]

assemble :: Sources -> Family -> Morphology -> [Entry] -> Either [Text] Project
assemble src family morphology entries = do
  (root, order) <- stageTree (famStages family)
  paradigms <- resolveParadigms (moParadigms morphology)
  let stages = famStages family
      flat = concatMap (flattenEntry stages root paradigms KAffix Nothing [] root)
                       (Map.elems (moAffixes morphology))
          ++ concatMap (flattenEntry stages root paradigms KRoot Nothing [] root) entries
      lostErrs = [ "paradigm " <> n <> ": lost at unknown stage " <> s
                 | (n, p) <- Map.toList paradigms, s <- Map.keys (pfLost p), not (Map.member s stages) ]
          ++ [ "paradigm " <> n <> ": becomes " <> q <> " at unknown stage " <> s
             | (n, p) <- Map.toList paradigms, (s, q) <- Map.toList (pfBecomes p), not (Map.member s stages) ]
          ++ [ "paradigm " <> n <> ": becomes " <> q <> " at " <> s <> ", which is not below its stage " <> ps
             | (n, p) <- Map.toList paradigms, Just ps <- [pfStage p], (s, q) <- Map.toList (pfBecomes p)
             , Map.member s stages, not (isAncestorOrSelf stages ps s) || ps == s ]
  unless (null lostErrs) $ Left lostErrs
  items <- sequence flat
  let dupes = Map.keys (Map.filter (> 1) (Map.fromListWith (+) [(itId i, 1 :: Int) | i <- items]))
  unless (null dupes) $ Left ["duplicate id: " <> d | d <- dupes]
  let itemMap = Map.fromList [(itId i, i) | i <- items]
      itemOrder = [itId i | i <- items, not (itInternal i)]
      proj = Project (srcDir src) family root order itemMap itemOrder paradigms src
  validate proj
  pure proj

-- | Find the root stage and a parents-first ordering.
stageTree :: Map StageId Stage -> Either [Text] (StageId, [StageId])
stageTree stages = do
  let roots = Map.keys (Map.filter ((== Nothing) . stParent) stages)
      badParents =
        [ s <> ": unknown parent " <> p
        | (s, st) <- Map.toList stages, Just p <- [stParent st], not (Map.member p stages) ]
  unless (null badParents) $ Left badParents
  root <- case roots of
    [r] -> Right r
    [] -> Left ["no root stage (every stage has a parent)"]
    rs -> Left ["more than one root stage: " <> T.intercalate ", " rs]
  let children p = [s | (s, st) <- Map.toList stages, stParent st == Just p]
      go s = s : concatMap go (children s)
      order = go root
  when (length order /= Map.size stages) $
    Left ["stage tree has a cycle among: "
          <> T.intercalate ", " (Map.keys stages `minus` order)]
  pure (root, order)
  where
    minus xs ys = filter (`notElem` ys) xs

flattenEntry
  :: Map StageId Stage -> StageId -> Map Text ParadigmDef
  -> ItemKind -> Maybe ItemId -> [CatShift] -> StageId -> Entry -> [Either [Text] Item]
flattenEntry stages root paradigms kind owner ownerCat defStage e =
  self : allomorphs ++ stems ++ cells ++ derivs
  where
    eid = enId e
    stage = fromMaybe defStage (enStage e)
    -- Without a category of its own, a derivative takes the one its parent
    -- has where it is formed.
    category
      | null (enCategory e) = [CatShift stage t | Just t <- [categoryIn stages ownerCat stage]]
      | otherwise = enCategory e
    err msg = Left [eid <> ": " <> msg]

    self = do
      build <- case (enForm e, enSource e) of
        (Just f, Nothing) -> Right (BForm f)
        (Nothing, Just (SCell b c)) -> Right (BSource (SBase (b <> "." <> c)))
        (Nothing, Just s) -> Right (BSource s)
        (Nothing, Nothing) -> err "needs either `form` or `source`"
        (Just _, Just _) -> err "has both `form` and `source`"
      forM_ cellEvents $ \ev -> unless (cellOf ev `elem` cellNames) $
        err ("event targets unknown cell " <> cellOf ev)
      when (T.any (== '~') eid) $ err "ids may not contain ~ (it is reserved for variants and internal items)"
      unless (Map.null (enAllomorphs e) || (kind == KAffix && owner == Nothing)) $
        err "only affixes can have allomorphs"
      forM_ (Map.toList (enAllomorphs e)) $ \(s, als) -> do
        let at = "allomorphs at " <> s
            conds = map alCondition als
        unless (Map.member s stages) $ err (at <> ": unknown stage")
        unless (isAncestorOrSelf stages stage s) $
          err (at <> ": " <> s <> " is not at or below " <> stage <> ", where the affix is formed")
        when (null als) $ err (at <> ": the list is empty")
        when (any (== Nothing) (drop 1 (reverse conds))) $
          err (at <> ": only the last may have no condition (the elsewhere case)")
        when (any isAfter conds && any isBefore conds) $
          err (at <> ": `after` and `before` may not be mixed in one list")
      forM_ (citeCells (enCite e)) $ \c -> unless (c `elem` cellNames) $
        err ("cite names unknown cell " <> c)
      forM_ (citeStages (enCite e)) $ \s -> unless (Map.member s stages) $
        err ("cite at unknown stage " <> s)
      pure Item
        { itId = eid
        , itKind = kind
        , itOwner = owner
        , itStage = stage
        , itBuild = build
        , itBound = fromMaybe (kind == KAffix) (enBound e)
        , itGloss = enGloss e
        , itCategory = category
        , itNotes = enNotes e
        , itEvents = concatMap restem ownEvents
        , itFate = enFate e
        , itExpect = Map.mapMaybe exForm (enExpect e)
        , itCells = [eid <> "." <> c | c <- cellNames]
        , itParadigm = enParadigm e
        , itRepatterns = [(evAt ev, p) | ev@Event {evKind = Repattern p _} <- events]
        , itAllomorphs = Map.mapWithKey (\s als -> [(alCondition a, allomorphId s n) | (n, a) <- numbered als])
                                        (enAllomorphs e)
        , itInternal = False
        , itCite = enCite e
        }

    isAfter = \case Just (After _) -> True; _ -> False
    isBefore = \case Just (Before _) -> True; _ -> False

    -- Each allomorph is an item formed at its stage from its written form,
    -- so that it evolves like any affix. It goes where the affix goes.
    numbered = zip [1 :: Int ..]
    allomorphId s n = eid <> "~" <> s <> "~" <> T.pack (show n)
    allomorphs =
      [ Right Item
          { itId = allomorphId s n
          , itKind = KAffix
          , itOwner = Just eid
          , itStage = s
          , itBuild = BForm (alForm a)
          , itBound = True
          , itGloss = Nothing
          , itCategory = []
          , itNotes = Nothing
          , itEvents = []
          , itFate = enFate e
          , itExpect = Map.empty
          , itCells = []
          , itParadigm = Nothing
          , itRepatterns = []
          , itAllomorphs = Map.empty
          , itInternal = True
          , itCite = Nothing
          }
      | (s, als) <- Map.toList (enAllomorphs e), (n, a) <- numbered als ]

    -- Each stem written on a cell is an item of its own, formed with the
    -- paradigm's cells and used as their base, so that it evolves like a
    -- bound root. Cells with the same stem share it. Cells joined later
    -- (`at:`) take theirs as written instead, as a repattern stem.
    stemTexts = nub [t | (_, ov) <- enCells e, coAt ov == Nothing, Just t <- [coStem ov]]
    stemId t = eid <> "~stem~" <> T.pack (show (maybe 0 (+ 1) (elemIndex t stemTexts)))
    stems =
      [ Right Item
          { itId = stemId t
          , itKind = KRoot
          , itOwner = Just eid
          , itStage = either (const stage) id paradigmStage
          , itBuild = BForm t
          , itBound = True
          , itGloss = Nothing
          , itCategory = []
          , itNotes = Nothing
          , itEvents = []
          , itFate = enFate e
          , itExpect = Map.empty
          , itCells = []
          , itParadigm = Nothing
          , itRepatterns = []
          , itAllomorphs = Map.empty
          , itInternal = True
          , itCite = Nothing
          }
      | t <- stemTexts ]
    cellBase ov = coBase ov <|> (stemId <$> coStem ov)

    (cellEvents, ownEvents) = partitionBy (\ev -> evCell ev /= Nothing) events
    cellOf ev = fromMaybe "" (evCell ev)

    -- The entry's events, with a repattern for each stage where its
    -- paradigm `becomes` another (following that one's in turn), unless
    -- the entry repatterns there itself.
    events = enEvents e ++
      [ Event s Nothing (Repattern q Nothing)
      | (s, q) <- becomes [] (enParadigm e)
      , s `notElem` [evAt ev | ev@Event {evKind = Repattern {}} <- enEvents e] ]
    becomes seen = \case
      Just pname | pname `notElem` seen, Just p <- Map.lookup pname paradigms ->
        concat [(s, q) : becomes (pname : seen) (Just q) | (s, q) <- Map.toList (pfBecomes p)]
      _ -> []

    paradigm = enParadigm e >>= (`Map.lookup` paradigms)

    -- A paradigm's cells with this entry's changes: name, base, template.
    -- Cells with a stage of their own (`at:`) are not part of any paradigm.
    cellsOf p = foldl' change [(c, (eid, ps)) | (c, ps) <- maybe [] pfCells p]
                              [(c, ov) | (c, ov) <- enCells e, coAt ov == Nothing]
    entryCells = cellsOf paradigm
    change acc (c, ov) = case lookup c acc of
      Just (b, ps) ->
        [(k, if k == c then (fromMaybe b (cellBase ov), fromMaybe ps (coMorph ov)) else v) | (k, v) <- acc]
      Nothing -> acc ++ [(c, (fromMaybe eid (cellBase ov), fromMaybe [PBase] (coMorph ov)))]

    -- `at:` cells: the entry's own, then those of its paradigm and of any it
    -- changes to, except where the entry re-forms the same cell at the
    -- same stage itself.
    entryAts = [(c, s) | (c, ov) <- enCells e, Just s <- [coAt ov]]
    atCells = [(c, ov) | (c, ov) <- enCells e, Just _ <- [coAt ov]] ++
      [ (c, CellOverride Nothing Nothing (Just ps) (Just s))
      | (c, s, ps) <- nub [a | p <- toList paradigm ++ repatternParadigms, a <- pfAt p]
      , (c, s) `notElem` entryAts ]

    -- Cells joined later than the paradigm: those that a repattern's
    -- paradigm has and the entry's own lacks, at the first repattern that
    -- has them, and those given `at:`, unless the paradigm has them, at the
    -- `at:` nearest the root (the others re-form it). Each is joined from
    -- the forms entering its stage.
    later = foldl' (\acc x@(c, _, _) -> if c `elem` map fst3 acc then acc else acc ++ [x]) []
      ( [ (c, (b, ps), s) | (s, _, _, new) <- repatterns, (c, (b, ps)) <- new, c `notElem` map fst entryCells ]
          ++ sortOn (\(_, _, s) -> length (ancestorsOrSelf stages s))
             [ (c, (fromMaybe eid (coBase ov), fromMaybe [PBase] (coMorph ov)), s)
             | (c, ov) <- atCells, Just s <- [coAt ov], c `notElem` map fst entryCells ] )
    joinedAt c = listToMaybe [s | (c', _, s) <- later, c' == c]
    -- `at:` on a cell that the paradigm, or one the entry changes to, has
    -- re-forms it there, and so does any but the first on a cell joined
    -- later.
    paradigmCells = map fst entryCells ++ [c | (_, _, _, new) <- repatterns, (c, _) <- new]
    reformedAt c =
      [ Event s Nothing (Rebuild (coStem ov) (fromMaybe eid (coBase ov)) (fromMaybe [PBase] (coMorph ov)) ("re-formed at " <> s))
      | (c', ov) <- atCells, c' == c, Just s <- [coAt ov]
      , c `elem` paradigmCells || joinedAt c /= Just s ]
    fst3 (a, _, _) = a
    cellNames = map fst entryCells ++ map fst3 later

    cells = case (enParadigm e, paradigm) of
      (Just pname, Nothing) -> [err ("unknown paradigm " <> pname)]
      _ -> repatternErrs ++ [ err ("variant " <> c <> " has no main cell " <> m)
           | c <- cellNames, (m, Just _) <- [splitVariant c], m `notElem` cellNames ]
           ++ [ err ("cell " <> c <> " is joined at unknown stage " <> s) | (c, _, s) <- later, not (Map.member s stages) ]
           ++ map (mkCell Nothing) entryCells
           ++ [mkCell (Just s) (c, bp) | (c, bp, s) <- later, Map.member s stages]

    -- Where the paradigm's cells are formed.
    paradigmStage
      | isAncestorOrSelf stages pstage stage = Right stage
      | isAncestorOrSelf stages stage pstage = Right pstage
      | otherwise = err ("formed at " <> stage <> ", which is not on a line with paradigm stage " <> pstage)
      where pstage = fromMaybe root (paradigm >>= pfStage)
    atStem c s = listToMaybe [t | (c', ov) <- atCells, c' == c, coAt ov == Just s, Just t <- [coStem ov]]

    mkCell born (c, (base, parts)) = do
      cstage <- case born of
        Just s
          | isAncestorOrSelf stages stage s -> Right s
          | otherwise -> err ("cell " <> c <> " is joined at " <> s <> ", which is not below " <> stage <> ", where the entry is formed")
        Nothing -> paradigmStage
      -- A cell joined later than the paradigm enters its stage by a
      -- rebuild, unless that is the root stage, where it is simply formed.
      let birth = case born of
            Just s | Just _ <- Map.lookup s stages >>= stParent
                   , s `notElem` [s' | (s', _, _, new) <- repatterns, Just _ <- [lookup c new]] ->
                       [Event s Nothing (Rebuild (atStem c s) base parts ("joined at " <> s))]
            _ -> []
          -- Nothing about stages above where the cell is joined.
          applies s = maybe True (\b -> isAncestorOrSelf stages b s) born
      forM_ (reformedAt c) $ \ev -> unless (applies (evAt ev) && Just (evAt ev) /= born) $
        err ("cell " <> c <> " is re-formed at " <> evAt ev <> ", which is not below "
             <> fromMaybe cstage born <> ", where it is joined")
      pure Item
        { itId = eid <> "." <> c
        , itKind = KCell
        , itOwner = Just eid
        , itStage = cstage
        , itBuild = BSource (SMorph base parts)
        , itBound = False
        , itGloss = Nothing
        , itCategory = category
        , itNotes = Nothing
        , itEvents = birth ++
            [ Event s Nothing (Rebuild (if b == eid then stem else Nothing) b ps ("repatterned as " <> pname))
            | (s, pname, stem, new) <- repatterns, applies s, Just (b, ps) <- [lookup c new] ]
              ++ reformedAt c
              -- An analogy without `cell:` reaches every cell, after the
              -- cell's re-formings and before its own events.
              ++ [ev | ev@Event {evKind = Analogy {}} <- ownEvents, applies (evAt ev)]
              ++ [ev | ev <- cellEvents, evCell ev == Just c]
        , itFate = Map.filterWithKey (\s _ -> applies s && Just s /= born) $ Map.unions
            [ enFate e
            , Map.fromList [(s, Lost) | (s, _, _, new) <- repatterns, Nothing <- [lookup c new]]
            , Map.fromList [ (s, Lost) | p <- toList paradigm ++ repatternParadigms
                           , (s, pats) <- Map.toList (pfLost p), any (`lostBy` c) pats ]
            ]
        , itExpect = Map.mapMaybe (Map.lookup c . exCells) (enExpect e)
        , itCells = []
        , itParadigm = Nothing
        , itRepatterns = []
        , itAllomorphs = Map.empty
        , itInternal = False
        , itCite = Nothing
        }

    -- Each repattern: its stage, the new paradigm, the new stem, and the
    -- cells it gives. Nearest the root first, so that a cell two
    -- repatterns add is joined at the earlier one (a paradigm's `becomes`
    -- comes after the entry's own events in `events`).
    repatterns = sortOn (\(s, _, _, _) -> length (ancestorsOrSelf stages s))
      [ (evAt ev, pname, stem, cellsOf (Just p))
      | ev@Event {evKind = Repattern pname stem} <- events
      , Just p <- [Map.lookup pname paradigms] ]
    repatternParadigms =
      [p | Event {evKind = Repattern pname _} <- events, Just p <- [Map.lookup pname paradigms]]
    repatternErrs = concat
      [ [ err ("repattern at " <> evAt ev <> ": unknown paradigm " <> pname)
        | Nothing <- [Map.lookup pname paradigms] ]
          ++ [ err ("repattern at " <> evAt ev <> " applies to every cell; it cannot have `cell:`")
             | Just _ <- [evCell ev] ]
      | ev@Event {evKind = Repattern pname _} <- events ]
    -- On the entry itself, a repattern with a stem replaces its form.
    restem ev = case evKind ev of
      Repattern pname (Just stem) -> [ev {evKind = Rebuild (Just stem) eid [PBase] ("repatterned as " <> pname)}]
      Repattern {} -> []
      _ -> [ev]

    derivs = concatMap (flattenEntry stages root paradigms KDerivative (Just eid) category stage) (enDerivatives e)

partitionBy :: (a -> Bool) -> [a] -> ([a], [a])
partitionBy p xs = (filter p xs, filter (not . p) xs)

ancestorsOrSelf :: Map StageId Stage -> StageId -> [StageId]
ancestorsOrSelf stages s = s : maybe [] (ancestorsOrSelf stages) (Map.lookup s stages >>= stParent)

-- | @isAncestorOrSelf stages a b@: is @a@ on the path from the root to @b@?
isAncestorOrSelf :: Map StageId Stage -> StageId -> StageId -> Bool
isAncestorOrSelf stages a b = a `elem` ancestorsOrSelf stages b

-- | Items an item is built from.
itemDeps :: Item -> [ItemId]
itemDeps it = case itBuild it of
  BForm _ -> []
  BSource s -> case s of
    SBase b -> [b]
    SMorph b ps -> b : [a | PAffix a <- ps]
    SCell b c -> [b <> "." <> c]
    SCompound xs -> xs
    SLoan _ x _ -> [x]

validate :: Project -> Either [Text] ()
validate Project {..} = do
  let stages = famStages prFamily
      items = Map.elems prItems
      knownStage s = Map.member s stages
      stageRefs it =
        [itStage it]
          ++ map evAt (itEvents it)
          ++ [s | Event {evKind = Loan s _ _} <- itEvents it]
          ++ Map.keys (itFate it) ++ Map.keys (itExpect it)
          ++ map csAt (itCategory it)
          ++ [s | BSource (SLoan s _ _) <- [itBuild it]]
      itemRefs it =
        itemDeps it
          ++ [x | Event {evKind = Loan _ (Just x) _} <- itEvents it]
          ++ [x | ReplacedBy x <- toList (itFate it)]
      errs =
        [ itId it <> ": unknown stage " <> s | it <- items, s <- stageRefs it, not (knownStage s) ]
          ++ [ itId it <> ": unknown item " <> x | it <- items, x <- itemRefs it, not (Map.member x prItems) ]
  unless (null errs) $ Left errs
  -- Items must be built from things that exist where they are formed.
  let lineErrs =
        [ itId it <> ": formed at " <> itStage it <> " from " <> d
            <> ", which is only formed at " <> itStage dep
        | it <- items, BSource s <- [itBuild it], notLoan s
        , d <- itemDeps it, Just dep <- [Map.lookup d prItems]
        , not (isAncestorOrSelf stages (itStage dep) (itStage it)) ]
      notLoan = \case SLoan {} -> False; _ -> True
  unless (null lineErrs) $ Left lineErrs
  -- No item may be built from itself.
  let cyclic = mapMaybe (\it -> if reaches (itId it) Set.empty (itemDeps it) then Just (itId it) else Nothing) items
      reaches _ _ [] = False
      reaches target seen (x : xs)
        | x == target = True
        | Set.member x seen = reaches target seen xs
        | otherwise = reaches target (Set.insert x seen)
            (maybe [] itemDeps (Map.lookup x prItems) ++ xs)
  unless (null cyclic) $ Left ["item is built from itself: " <> c | c <- cyclic]

-- | The category in force at a stage: the tag set at the nearest stage
-- on the path back to the root (the last one written, if several share a
-- stage).
categoryIn :: Map StageId Stage -> [CatShift] -> StageId -> Maybe Text
categoryIn stages cats s =
  let path = ancestorsOrSelf stages s
      depth x = length (takeWhile (/= x) (reverse path))
      applicable = [ (depth (csAt c), n, csIs c)
                   | (n, c) <- zip [0 :: Int ..] cats, csAt c `elem` path ]
  in listToMaybe [t | (_, _, t) <- sortOn (\(d, n, _) -> (Down d, Down n)) applicable]

------------------------------------------------------------------------
-- Paradigms

-- | A paradigm with @extends@ resolved and its dimensions expanded.
data ParadigmDef = ParadigmDef
  { pfStage :: Maybe StageId
  , pfDimensions :: [Dimension]
  , pfCells :: [(Text, [Part])]
  -- ^ The cells formed with the paradigm.
  , pfAt :: [(Text, StageId, [Part])]
  -- ^ Cells re-formed at a later stage, or joined there if they are not
  -- in 'pfCells': the cell, the stage and the template.
  , pfLost :: Map StageId [Text]
  , pfBecomes :: Map StageId Text
  , pfCite :: Maybe Cite
  }

resolveParadigms :: Map Text Paradigm -> Either [Text] (Map Text ParadigmDef)
resolveParadigms raw = case [e | Left e <- Map.elems resolved] of
  [] -> Right (Map.mapMaybe (either (const Nothing) Just) resolved)
  errs -> Left errs
  where
    resolved = Map.mapWithKey
      (\n _ -> either (Left . (("paradigm " <> n <> ": ") <>)) Right (expand =<< inherit [n] n)) raw

    -- The paradigm with everything it inherits merged in.
    inherit seen n = do
      p <- maybe (Left ("unknown paradigm " <> n)) Right (Map.lookup n raw)
      checkUnique "dimension" (map dmName (pdDimensions p))
      forM_ (pdDimensions p) $ \d -> checkUnique ("member of " <> dmName d) (map fst (dmMembers d))
      checkUnique "cell" (map fst (pdCells p))
      case pdExtends p of
        Nothing -> Right p
        Just parent
          | parent `elem` seen ->
              Left ("extends forms a cycle: " <> T.intercalate " > " (reverse (parent : seen)))
          | otherwise -> do
              b <- inherit (parent : seen) parent
              Right Paradigm
                { pdStage = pdStage p <|> pdStage b
                , pdExtends = Nothing
                , pdDimensions = mergeDims (pdDimensions b) (pdDimensions p)
                , pdTemplate = pdTemplate p <|> pdTemplate b
                , pdCells = override (pdCells b) (pdCells p)
                , pdExclude = pdExclude b ++ pdExclude p
                , pdLost = Map.unionWith (++) (pdLost b) (pdLost p)
                -- Not inherited: a paradigm that extends the one it
                -- replaces would otherwise become itself.
                , pdBecomes = pdBecomes p
                , pdCite = pdCite p <|> pdCite b
                }

    checkUnique what xs = case nub [x | x <- xs, length (filter (== x) xs) > 1] of
      [] -> Right ()
      ds -> Left ("duplicate " <> what <> ": " <> T.intercalate ", " ds)

    -- A dimension of the same name merges its members into the inherited
    -- one; a new dimension is added after the inherited ones.
    mergeDims = foldl' $ \acc d ->
      if dmName d `elem` map dmName acc
        then [ if dmName a == dmName d then a {dmMembers = override (dmMembers a) (dmMembers d)} else a
             | a <- acc ]
        else acc ++ [d]

    expand p = do
      let dims = pdDimensions p
          names = map dmName dims
      slots <- case pdTemplate p of
        Nothing -> Right ("~" : names)
        Just _ | null dims -> Left "has a template but no dimensions"
        Just t -> Right (if "~" `elem` t then t else "~" : t)
      when (length (filter (== "~") slots) > 1) $ Left "a template may contain only one ~"
      forM_ names $ \d -> unless (length (filter (== d) slots) == 1) $
        Left ("dimension " <> d <> " must appear exactly once in the template")
      forM_ dims $ \d -> forM_ (map fst (dmMembers d)) $ \m -> case splitVariant m of
        (main, Just _) | main `notElem` map fst (dmMembers d) ->
          Left ("variant " <> m <> " of " <> dmName d <> " has no main member " <> main)
        _ -> Right ()
      -- The first dimension varies slowest: SG.DIR, SG.GEN, PL.DIR, ...
      -- Variant members name variant cells: NPST~archaic gives 1S.NPST~archaic.
      let cellName combo =
            T.intercalate "." [fst (splitVariant m) | (m, _) <- combo]
              <> T.concat ["~" <> l | (m, _) <- combo, (_, Just l) <- [splitVariant m]]
          combined =
            [ (cellName combo, CellDef (Just (concatMap (slot (zip names combo)) slots)) [])
            | not (null dims), combo <- mapM dmMembers dims ]
          slot chosen s
            | s == "~" = [PBase]
            | Just (_, affs) <- lookup s chosen = map PAffix affs
            | otherwise = [PAffix s]
          cells = override combined (pdCells p)
          unknown = [c | c <- pdExclude p, c `notElem` map fst cells]
      unless (null unknown) $ Left ("exclude names unknown cells: " <> T.intercalate ", " unknown)
      let kept = [c | c@(n, _) <- cells, n `notElem` pdExclude p]
      when (null kept) $ Left "has no cells"
      forM_ kept $ \(c, _) -> case splitVariant c of
        (main, Just _) | main `notElem` map fst kept -> Left ("variant " <> c <> " has no main cell " <> main)
        _ -> Right ()
      let unmatched = [pat | pats <- Map.elems (pdLost p), pat <- pats, not (any (lostBy pat . fst) kept)]
      unless (null unmatched) $ Left ("lost names no cells: " <> T.intercalate ", " unmatched)
      let unknownTargets = [q | q <- Map.elems (pdBecomes p), not (Map.member q raw)]
      unless (null unknownTargets) $ Left ("becomes unknown paradigm: " <> T.intercalate ", " unknownTargets)
      let uncited = [c | c <- citeCells (pdCite p), c `notElem` map fst kept]
      unless (null uncited) $ Left ("cite names unknown cells: " <> T.intercalate ", " uncited)
      Right ParadigmDef
        { pfStage = pdStage p
        , pfDimensions = dims
        , pfCells = [(c, ps) | (c, CellDef (Just ps) _) <- kept]
        , pfAt = [(c, s, ps) | (c, CellDef _ ats) <- kept, (s, ps) <- ats]
        , pfLost = pdLost p
        , pfBecomes = pdBecomes p
        , pfCite = pdCite p
        }

-- | Does a @lost@ pattern cover this cell? A cell's variants go with it.
lostBy :: Text -> Text -> Bool
lostBy pat c = globMatch pat c || globMatch pat (fst (splitVariant c))

-- | Replace entries by name, keeping their position; add new ones at the end.
override :: [(Text, a)] -> [(Text, a)] -> [(Text, a)]
override = foldl' $ \acc (k, v) ->
  if k `elem` map fst acc
    then [(k', if k' == k then v else v') | (k', v') <- acc]
    else acc ++ [(k, v)]

-- | The cells a citation names.
citeCells :: Maybe Cite -> [Text]
citeCells = \case
  Just (CiteAlways (Just c)) -> [c]
  Just (CiteFrom m) -> [c | Just c <- Map.elems m]
  _ -> []

citeStages :: Maybe Cite -> [StageId]
citeStages = \case
  Just (CiteFrom m) -> Map.keys m
  _ -> []

-- | The paradigm in force for an entry at a stage: the one given by the
-- nearest repattern on the path back to the root, or its own.
paradigmAt :: Project -> Item -> StageId -> Maybe Text
paradigmAt proj it s =
  listToMaybe [p | d <- ancestorsOrSelf (famStages (prFamily proj)) s, Just p <- [lookup d (itRepatterns it)]]
    <|> itParadigm it

-- | The item an entry is cited by at a stage, as a headword: the cell its
-- own @cite@ names, or else the one the paradigm in force there names, or
-- else its first cell. An entry without cells, or cited by its bare form,
-- is cited by itself.
citedAt :: Project -> Item -> StageId -> ItemId
citedAt proj it s = case itCells it of
  [] -> itId it
  first : _ -> maybe first (maybe (itId it) (\c -> itId it <> "." <> c)) (fromEntry <|> fromParadigm)
  where
    path = ancestorsOrSelf (famStages (prFamily proj)) s
    fromEntry = itCite it >>= (`citations` path)
    fromParadigm = paradigmAt proj it s >>= (`Map.lookup` prParadigms proj) >>= pfCite >>= (`citations` path)
