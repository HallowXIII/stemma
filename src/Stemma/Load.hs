-- | Reading a project directory and flattening it into items.
--
-- Every thing that has a form at some stage is an 'Item': roots, affixes,
-- derivatives and paradigm cells alike. Cells are named @entry.CELL@.
module Stemma.Load
  ( Project (..)
  , Item (..)
  , ItemKind (..)
  , Build (..)
  , loadProject
  , isAncestorOrSelf
  , ancestorsOrSelf
  , itemDeps
  ) where

import Control.Monad (forM, forM_, unless, when)
import Data.Foldable (toList)
import Data.List (isSuffixOf, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
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
  let stages = famStages family
      flat = concatMap (flattenEntry stages root (moParadigms morphology) KAffix Nothing root)
                       (Map.elems (moAffixes morphology))
          ++ concatMap (flattenEntry stages root (moParadigms morphology) KRoot Nothing root) entries
  items <- sequence flat
  let dupes = Map.keys (Map.filter (> 1) (Map.fromListWith (+) [(itId i, 1 :: Int) | i <- items]))
  unless (null dupes) $ Left ["duplicate id: " <> d | d <- dupes]
  let itemMap = Map.fromList [(itId i, i) | i <- items]
      proj = Project dir family root order itemMap (map itId items)
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
  :: Map StageId Stage -> StageId -> Map Text Paradigm
  -> ItemKind -> Maybe ItemId -> StageId -> Entry -> [Either [Text] Item]
flattenEntry stages root paradigms kind owner defStage e =
  self : cells ++ derivs
  where
    eid = enId e
    stage = fromMaybe defStage (enStage e)
    err msg = Left [eid <> ": " <> msg]

    self = do
      build <- case (enForm e, enSource e) of
        (Just f, Nothing) -> Right (BForm f)
        (Nothing, Just (SCell b c)) -> Right (BSource (SBase (b <> "." <> c)))
        (Nothing, Just s) -> Right (BSource s)
        (Nothing, Nothing) -> err "needs either `form` or `source`"
        (Just _, Just _) -> err "has both `form` and `source`"
      forM_ cellEvents $ \ev -> case paradigm of
        Nothing -> err ("event targets cell " <> cellOf ev <> " but the entry has no paradigm")
        Just p -> unless (cellOf ev `elem` map fst (pdCells p)) $
          err ("event targets unknown cell " <> cellOf ev)
      pure Item
        { itId = eid
        , itKind = kind
        , itOwner = owner
        , itStage = stage
        , itBuild = build
        , itBound = fromMaybe (kind == KAffix) (enBound e)
        , itGloss = enGloss e
        , itCategory = enCategory e
        , itNotes = enNotes e
        , itEvents = ownEvents
        , itFate = enFate e
        , itExpect = Map.mapMaybe exForm (enExpect e)
        , itCells = [eid <> "." <> c | (c, _) <- maybe [] pdCells paradigm]
        }

    (cellEvents, ownEvents) = partitionBy (\ev -> evCell ev /= Nothing) (enEvents e)
    cellOf ev = fromMaybe "" (evCell ev)

    paradigm = enParadigm e >>= (`Map.lookup` paradigms)

    cells = case enParadigm e of
      Nothing -> []
      Just pname -> case paradigm of
        Nothing -> [err ("unknown paradigm " <> pname)]
        Just p -> map (mkCell p) (pdCells p)

    mkCell p (c, parts) = do
      let pstage = fromMaybe root (pdStage p)
      cstage <-
        if isAncestorOrSelf stages pstage stage then Right stage
        else if isAncestorOrSelf stages stage pstage then Right pstage
        else err ("formed at " <> stage <> ", which is not on a line with paradigm stage " <> pstage)
      pure Item
        { itId = eid <> "." <> c
        , itKind = KCell
        , itOwner = Just eid
        , itStage = cstage
        , itBuild = BSource (SMorph eid parts)
        , itBound = False
        , itGloss = Nothing
        , itCategory = enCategory e
        , itNotes = Nothing
        , itEvents = [ev | ev <- cellEvents, evCell ev == Just c]
        , itFate = enFate e
        , itExpect = Map.mapMaybe (Map.lookup c . exCells) (enExpect e)
        , itCells = []
        }

    derivs = concatMap (flattenEntry stages root paradigms KDerivative (Just eid) stage) (enDerivatives e)

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
