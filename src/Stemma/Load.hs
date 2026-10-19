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
  , categoryIn
  , isAncestorOrSelf
  , ancestorsOrSelf
  , itemDeps
  ) where

import Control.Applicative ((<|>))
import Control.Monad (forM, forM_, unless, when)
import Data.Foldable (toList)
import Data.List (isSuffixOf, nub, sort, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Ord (Down (..))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Yaml qualified as Y
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

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
  }
  deriving (Show)

loadProject :: FilePath -> IO (Either [Text] Project)
loadProject dir = do
  fam <- decodeYaml (dir </> "family.yaml")
  let morphFile = dir </> "morphology.yaml"
  hasMorph <- doesFileExist morphFile
  morph <- if hasMorph then decodeYaml morphFile else pure (Right (Morphology Map.empty Map.empty))
  let lexDir = dir </> "lexicon"
  hasLex <- doesDirectoryExist lexDir
  lexFiles <- if hasLex
    then map (lexDir </>) . sort . filter isYaml <$> listDirectory lexDir
    else pure []
  lexs <- forM lexFiles $ \f -> fmap (fromMaybe []) <$> decodeYaml f
  pure $ do
    family <- fam
    morphology <- morph
    entries <- concat <$> sequence lexs
    assemble dir family morphology entries
  where
    isYaml f = ".yaml" `isSuffixOf` f || ".yml" `isSuffixOf` f

decodeYaml :: Y.FromJSON a => FilePath -> IO (Either [Text] a)
decodeYaml f = Y.decodeFileEither f >>= \case
  Left e -> pure (Left [T.pack f <> ": " <> T.pack (Y.prettyPrintParseException e)])
  Right a -> pure (Right a)

assemble :: FilePath -> Family -> Morphology -> [Entry] -> Either [Text] Project
assemble dir family morphology entries = do
  (root, order) <- stageTree (famStages family)
  paradigms <- resolveParadigms (moParadigms morphology)
  let stages = famStages family
      flat = concatMap (flattenEntry stages root paradigms KAffix Nothing [] root)
                       (Map.elems (moAffixes morphology))
          ++ concatMap (flattenEntry stages root paradigms KRoot Nothing [] root) entries
      lostErrs = [ "paradigm " <> n <> ": lost at unknown stage " <> s
                 | (n, p) <- Map.toList paradigms, s <- Map.keys (pfLost p), not (Map.member s stages) ]
  unless (null lostErrs) $ Left lostErrs
  items <- sequence flat
  let dupes = Map.keys (Map.filter (> 1) (Map.fromListWith (+) [(itId i, 1 :: Int) | i <- items]))
  unless (null dupes) $ Left ["duplicate id: " <> d | d <- dupes]
  let itemMap = Map.fromList [(itId i, i) | i <- items]
      proj = Project dir family root order itemMap (map itId items) paradigms
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
  self : cells ++ derivs
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
      forM_ cellEvents $ \ev -> unless (cellOf ev `elem` map fst entryCells) $
        err ("event targets unknown cell " <> cellOf ev)
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
        , itCells = [eid <> "." <> c | (c, _) <- entryCells]
        , itParadigm = enParadigm e
        , itRepatterns = [(evAt ev, p) | ev@Event {evKind = Repattern p _} <- enEvents e]
        }

    (cellEvents, ownEvents) = partitionBy (\ev -> evCell ev /= Nothing) (enEvents e)
    cellOf ev = fromMaybe "" (evCell ev)

    paradigm = enParadigm e >>= (`Map.lookup` paradigms)

    -- A paradigm's cells with this entry's changes: name, base, template.
    cellsOf p = foldl' change [(c, (eid, ps)) | (c, ps) <- maybe [] pfCells p] (enCells e)
    entryCells = cellsOf paradigm
    change acc (c, ov) = case lookup c acc of
      Just (b, ps) ->
        [(k, if k == c then (fromMaybe b (coBase ov), fromMaybe ps (coMorph ov)) else v) | (k, v) <- acc]
      Nothing -> acc ++ [(c, (fromMaybe eid (coBase ov), fromMaybe [PBase] (coMorph ov)))]

    cells = case (enParadigm e, paradigm) of
      (Just pname, Nothing) -> [err ("unknown paradigm " <> pname)]
      _ -> repatternErrs ++ [ err ("variant " <> c <> " has no main cell " <> m)
           | (c, _) <- enCells e, (m, Just _) <- [splitVariant c], m `notElem` map fst entryCells ]
           ++ map mkCell entryCells

    mkCell (c, (base, parts)) = do
      let pstage = fromMaybe root (paradigm >>= pfStage)
      cstage <-
        if isAncestorOrSelf stages pstage stage then Right stage
        else if isAncestorOrSelf stages stage pstage then Right pstage
        else err ("formed at " <> stage <> ", which is not on a line with paradigm stage " <> pstage)
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
        , itEvents =
            [ Event s Nothing (Rebuild (if b == eid then stem else Nothing) b ps ("repatterned as " <> pname))
            | (s, pname, stem, new) <- repatterns, Just (b, ps) <- [lookup c new] ]
              ++ [ev | ev <- cellEvents, evCell ev == Just c]
        , itFate = Map.unions
            [ enFate e
            , Map.fromList [(s, Lost) | (s, _, _, new) <- repatterns, Nothing <- [lookup c new]]
            , Map.fromList [ (s, Lost) | p <- toList paradigm ++ repatternParadigms
                           , (s, pats) <- Map.toList (pfLost p), any (`lostBy` c) pats ]
            ]
        , itExpect = Map.mapMaybe (Map.lookup c . exCells) (enExpect e)
        , itCells = []
        , itParadigm = Nothing
        , itRepatterns = []
        }

    -- Each repattern: its stage, the new paradigm, the new stem, and the
    -- cells it gives.
    repatterns =
      [ (evAt ev, pname, stem, cellsOf (Just p))
      | ev@Event {evKind = Repattern pname stem} <- enEvents e
      , Just p <- [Map.lookup pname paradigms] ]
    repatternParadigms =
      [p | Event {evKind = Repattern pname _} <- enEvents e, Just p <- [Map.lookup pname paradigms]]
    repatternErrs = concat
      [ [ err ("repattern at " <> evAt ev <> ": unknown paradigm " <> pname)
        | Nothing <- [Map.lookup pname paradigms] ]
          ++ [ err ("repattern at " <> evAt ev <> " applies to every cell; it cannot have `cell:`")
             | Just _ <- [evCell ev] ]
          ++ [ err ("repattern at " <> evAt ev <> ": " <> pname <> " has cells that " <> eid
                    <> " lacks: " <> T.intercalate ", " extra)
             | Just p <- [Map.lookup pname paradigms]
             , let extra = [c | (c, _) <- cellsOf (Just p), c `notElem` map fst entryCells]
             , not (null extra) ]
      | ev@Event {evKind = Repattern pname _} <- enEvents e ]
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
    SLoan _ x -> [x]

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
          ++ [s | BSource (SLoan s _) <- [itBuild it]]
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
  , pfLost :: Map StageId [Text]
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
            [ (cellName combo, concatMap (slot (zip names combo)) slots)
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
      Right (ParadigmDef (pdStage p) dims kept (pdLost p))

-- | Does a @lost@ pattern cover this cell? A cell's variants go with it.
lostBy :: Text -> Text -> Bool
lostBy pat c = globMatch pat c || globMatch pat (fst (splitVariant c))

-- | Replace entries by name, keeping their position; add new ones at the end.
override :: [(Text, a)] -> [(Text, a)] -> [(Text, a)]
override = foldl' $ \acc (k, v) ->
  if k `elem` map fst acc
    then [(k', if k' == k then v else v') | (k', v') <- acc]
    else acc ++ [(k, v)]
