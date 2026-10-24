-- | Build products: @build/lexicon.json@ for Typst, and @build/forms.tsv@,
-- a flat listing whose changes between builds become @build/diff.txt@.
--
-- @lexicon.json@ is kept small, since it holds every cell at every stage.
-- A reflex leaves out @spelled@, @regular@ and @regular_spelled@ when they
-- repeat its forms (see 'reflexJson'), and a stage is left out altogether
-- when its reflex is the same as at the parent stage.
module Stemma.Output
  ( writeBuild
  , formsTsv
  , Change (..)
  , ChangeKind (..)
  , diffForms
  , renderChange
  , diffSummary
  , buildReport
  , lexiconJson
  , traceJson
  , outlineJson
  ) where

import Control.Monad (forM)
import Data.Aeson (ToJSON, Value, encode, object, toJSON, (.=))
import Data.Aeson.Encode.Pretty qualified as P
import Data.Aeson.Key (Key)
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (Pair)
import Data.ByteString.Lazy qualified as BL
import Data.Either (partitionEithers)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Encoding qualified as TLE
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))

import Stemma.Build
import Stemma.Engine
import Stemma.Load
import Stemma.Notes
import Stemma.Query (categoryAt)
import Stemma.Types

-- | Write the build products and return the diff against the previous
-- build ('Nothing' on the first build).
writeBuild :: FilePath -> Built -> IO (Either [Text] (Maybe [Change]))
writeBuild outDir b = case lexiconJson b of
  Left errs -> pure (Left errs)
  Right json -> do
    createDirectoryIfMissing True outDir
    let tsvFile = outDir </> "forms.tsv"
        new = formsTsv b
    hadOld <- doesFileExist tsvFile
    old <- if hadOld then TIO.readFile tsvFile else pure new
    let diff = diffForms old new
    BL.writeFile (outDir </> "lexicon.json") (encode json)
    BL.writeFile (outDir </> "trace.json") (encode (traceJson b))
    TIO.writeFile tsvFile new
    TIO.writeFile (outDir </> "diff.txt") (T.unlines (map renderChange diff))
    pure (Right (if hadOld then Just diff else Nothing))

-- | Events, rule inputs, traces and origins, for the UI. They are kept out
-- of @lexicon.json@, which Typst loads whole. A stage with none of them is
-- left out, and so is an item with no stages left.
traceJson :: Built -> Value
traceJson b = object
  [ Key.fromText i .= object [Key.fromText s .= object ps | (s, ps) <- stages]
  | i <- prItemOrder (bProject b)
  , let stages =
          [ (s, ps)
          | s <- bStageOrder b
          , Just rx <- [Map.lookup s (bActual b) >>= Map.lookup i]
          , let ps = reflexTrace rx
          , not (null ps) ]
  , not (null stages) ]
  where
    reflexTrace rx = catMaybes
      [ "origin" .=? (if rxOrigin rx == Inherited then Nothing else Just (T.toLower (T.pack (show (rxOrigin rx)))))
      , "events" .=? nonEmpty (rxEvents rx)
      , "input" .=? (renderForm <$> rxInput rx)
      , "trace" .=? nonEmpty (map stepJson (rxSteps rx))
      ]
    stepJson st = object
      [ "rule" .= stepRule st, "result" .= fmap renderForm (stepResult st) ]

lexiconJson :: Built -> Either [Text] Value
lexiconJson b = do
  let proj = bProject b
      fam = prFamily proj
      stages = famStages fam
  items <- collect
    [ itemJson b it | i <- prItemOrder proj, let it = prItems proj Map.! i ]
  pure $ object
    [ "family" .= famName fam
    , "root" .= prRootStage proj
    , "stages" .= [ object
                      [ "id" .= s, "name" .= stName st, "abbr" .= stAbbr st
                      , "parent" .= stParent st, "current" .= stCurrent st
                      , "rules" .= fmap renderRulesRef (stRules st)
                      , "morphophonology" .= fmap renderRulesRef (stMorphophonology st)
                      , "orthography" .= fmap renderRulesRef (stOrthography st) ]
                  | s <- bStageOrder b, let st = stages Map.! s ]
    , "items" .= object [Key.fromText (itId it) .= v | (it, v) <- items]
    , "paradigms" .= Map.map paradigmJson (prParadigms proj)
    , "order" .= prItemOrder proj
    , "warnings" .= bWarnings b
    ]
  where
    collect xs = case partitionEithers xs of
      ([], ok) -> Right ok
      (errs, _) -> Left (concat errs)

itemJson :: Built -> Item -> Either [Text] (Item, Value)
itemJson b it = do
  notes <- forM (itNotes it) $ \n ->
    either (\e -> Left [itId it <> ": " <> e]) (Right . map runJson) (renderNotes b n)
  pure . (it,) $ sparse
    [ "kind" .=? Just (kindName (itKind it))
    , "bound" .=? (if itBound it then Just True else Nothing)
    , "owner" .=? itOwner it
    , "gloss" .=? itGloss it
    , "formed" .=? Just (itStage it)
    , "source" .=? sourceText it
    , "cells" .=? nonEmpty (itCells it)
    , "paradigm" .=? itParadigm it
    , "repatterns" .=? nonEmpty [object ["at" .= s, "paradigm" .= p] | (s, p) <- itRepatterns it]
    , "allomorphs" .=? allomorphs
    , "variant_of" .=? fmap fst variant
    , "variant" .=? fmap snd variant
    , "notes" .=? notes
    , "category" .=? nonEmpty [object ["at" .= csAt c, "is" .= csIs c] | c <- itCategory it]
    , "fate" .=? (if Map.null (itFate it) then Nothing else Just (Map.map fateJson (itFate it)))
    , "reflexes" .=? Just (object
        [ Key.fromText s .= r
        | (s, r) <- Map.toList reflexes
        , s == itStage it || (parentOf s >>= (`Map.lookup` reflexes)) /= Just r ])
    ]
  where
    -- Every stage where the item exists: the stage it was formed at and the
    -- stages below it.
    reflexes = Map.fromList
      [ (s, reflexJson s) | s <- bStageOrder b, Map.member (itId it) (regularAt s) ]
    parentOf s = Map.lookup s (famStages (prFamily proj)) >>= stParent
    -- A cell named CELL~label: its main cell and label.
    variant = case (itKind it, itOwner it) of
      (KCell, Just o) -> case splitVariant (T.drop (T.length o + 1) (itId it)) of
        (main, Just l) -> Just (o <> "." <> main, l)
        _ -> Nothing
      _ -> Nothing
    proj = bProject b
    -- The allomorphs as written, from each stage on. Their forms at each
    -- stage are the affix's own reflexes.
    allomorphs
      | Map.null (itAllomorphs it) = Nothing
      | otherwise = Just (object
        [ Key.fromText s .= [ sparse
            [ "after" .=? (case c of Just (After gs) -> Just gs; _ -> Nothing)
            , "before" .=? (case c of Just (Before gs) -> Just gs; _ -> Nothing)
            , "form" .=? (case itBuild (prItems proj Map.! x) of BForm t -> Just t; _ -> Nothing) ]
          | (c, x) <- als ]
        | (s, als) <- Map.toList (itAllomorphs it) ])
    regularAt s =fromMaybe Map.empty (Map.lookup s (bRegular b))
    -- A field is left out when it repeats its default: @spelled@ and
    -- @regular@ default to @forms@, and @regular_spelled@ to @spelled@ (to
    -- @regular@ when the reflex is lost).
    reflexJson s =
      let shown = fmap (map (showForm proj) . rxForms)
          forms = shown (Map.lookup s (bActual b) >>= Map.lookup (itId it))
          regular = shown (Map.lookup s (bRegular b) >>= Map.lookup (itId it))
          spelled = spelledAt b False s (itId it)
          regularSpelled = spelledAt b True s (itId it)
          differing def x = if x == def then Nothing else x
      in sparse
        [ "forms" .=? forms
        , "lost" .=? (if forms == Nothing then Just True else Nothing)
        , "spelled" .=? differing forms spelled
        , "regular" .=? (if forms == Nothing then regular else differing forms regular)
        , "regular_spelled" .=? differing (maybe regular Just spelled) regularSpelled
        , "category" .=? categoryAt proj it s
        ]
    fateJson = \case
      Lost -> toJSON ("lost" :: Text)
      ReplacedBy x -> object ["replaced-by" .= x]

-- | An object without the fields that are 'Nothing'.
sparse :: [Maybe Pair] -> Value
sparse = object . catMaybes

(.=?) :: ToJSON v => Key -> Maybe v -> Maybe Pair
k .=? v = (k .=) <$> v

nonEmpty :: [a] -> Maybe [a]
nonEmpty xs = if null xs then Nothing else Just xs

-- | The result of 'engineOutline' as JSON, for @stemma rules@.
outlineJson :: Either OutlineError [[RuleStatement]] -> Text
outlineJson = TL.toStrict . TLE.decodeUtf8 . P.encodePretty' P.defConfig {P.confIndent = P.Spaces 2} . \case
  Left OutlineError {..} -> object
    [ "ok" .= False, "error" .= oeMessage
    , "line" .= fmap fst oePosition, "column" .= fmap snd oePosition ]
  Right segs -> object
    [ "ok" .= True
    , "segments" .= [[object ["kind" .= rsKind r, "text" .= rsText r] | r <- seg] | seg <- segs] ]

paradigmJson :: ParadigmDef -> Value
paradigmJson pf = object
  [ "dimensions" .= [ object ["name" .= dmName d, "members" .= [m | (m, _) <- dmMembers d, (_, Nothing) <- [splitVariant m]]]
                    | d <- pfDimensions pf ]
  , "cells" .= map fst (pfCells pf)
  , "lost" .= pfLost pf
  ]

runJson :: Run -> Value
runJson = \case
  RText t -> object ["text" .= t]
  RForm {..} -> object ["form" .= rfText, "ref" .= rfRef, "stage" .= rfStage, "star" .= rfStar]

kindName :: ItemKind -> Text
kindName = \case
  KRoot -> "root"
  KAffix -> "affix"
  KDerivative -> "derivative"
  KCell -> "cell"

sourceText :: Item -> Maybe Text
sourceText it = case itBuild it of
  BForm _ -> Nothing
  BSource s -> Just $ case s of
    SBase x -> x
    SMorph x ps -> T.intercalate " + " [case p of PBase -> x; PAffix a -> a | p <- ps]
    SCell x c -> x <> "." <> c
    SCompound xs -> T.intercalate " + " xs
    SLoan st x -> x <> " (loan from " <> st <> ")"

-- | One line per item and stage: @id, stage, spelled, phonemic@.
formsTsv :: Built -> Text
formsTsv b = T.unlines
  [ T.intercalate "\t" [i, s, T.intercalate " ~ " sp, T.intercalate " ~ " (map renderForm (rxForms rx))]
  | (s, res) <- Map.toList (bActual b)
  , (i, rx) <- Map.toList res
  , let sp = fromMaybe [] (spelledAt b False s i) ]

-- | A form that differs between two builds.
data Change = Change
  { chStage :: StageId
  , chItem :: ItemId
  , chKind :: ChangeKind
  }

data ChangeKind
  = Respelled Text Text
  | Rephonemicised Text Text  -- ^ the spelling is unchanged
  | New Text
  | Gone Text

diffForms :: Text -> Text -> [Change]
diffForms old new =
  [ Change s i kind
  | k@(s, i) <- Map.keys (Map.union o n)
  , Map.lookup k o /= Map.lookup k n
  , Just kind <- [describe (Map.lookup k o) (Map.lookup k n)] ]
  where
    parse t = Map.fromList
      [ ((s, i), (sp, ph)) | l <- T.lines t, [i, s, sp, ph] <- [T.splitOn "\t" l] ]
    o = parse old
    n = parse new
    describe (Just (a, pa)) (Just (c, pc))
      | a == c = Just (Rephonemicised pa pc)
      | otherwise = Just (Respelled a c)
    describe Nothing (Just (c, _)) = Just (New c)
    describe (Just (a, _)) Nothing = Just (Gone a)
    describe Nothing Nothing = Nothing

-- | A line of @diff.txt@.
renderChange :: Change -> Text
renderChange Change {..} = chStage <> "  " <> chItem <> ": " <> case chKind of
  Respelled a c -> a <> " → " <> c
  Rephonemicised a c -> "/" <> a <> "/ → /" <> c <> "/"
  New c -> "new: " <> c
  Gone a -> "gone (was " <> a <> ")"

-- | What @build@ prints about the diff. Up to 20 changes are listed; beyond
-- that, the counts per stage and the changes to forms the text depends on
-- (an @expect@, or a reference in notes).
diffSummary :: Built -> Maybe [Change] -> [Text]
diffSummary b = \case
  Nothing -> ["first build: " <> tshow (sum (Map.map Map.size (bActual b))) <> " forms"]
  Just [] -> ["no forms changed"]
  Just cs
    | length cs <= 20 -> "changed forms:" : map (("  " <>) . renderChange) cs
    | otherwise ->
        ("changed forms: " <> tshow (length cs))
          : [ "  " <> s <> ": " <> counts here
            | s <- bStageOrder b
            , let here = filter ((== s) . chStage) cs
            , not (null here) ]
          ++ (if null quoted then [] else "of which quoted or expected:" : map (("  " <>) . renderChange) quoted)
          ++ ["full list in build/diff.txt"]
      where
        pinned = pinnedForms b
        quoted = [c | c <- cs, Set.member (chStage c, chItem c) pinned]
  where
    counts here = T.intercalate ", "
      [ tshow k <> " " <> label
      | (label, p) <- [("changed", changed), ("new", isNew), ("gone", isGone)]
      , let k = length (filter (p . chKind) here)
      , k > 0 ]
    changed = \case Respelled {} -> True; Rephonemicised {} -> True; _ -> False
    isNew = \case New {} -> True; _ -> False
    isGone = \case Gone {} -> True; _ -> False
    tshow :: Show a => a -> Text
    tshow = T.pack . show

-- | What @build@ reports: the lines for stdout, and those for stderr
-- (warnings, and @expect@s the build doesn't reproduce).
buildReport :: Built -> Maybe [Change] -> ([Text], [Text])
buildReport b diff =
  ( diffSummary b diff
  , map ("warning: " <>) (bWarnings b) ++ map ("MISMATCH: " <>) (checkExpectations b) )

-- | The forms the text depends on: every @expect@, and every form quoted in
-- notes. Notes that fail to render are skipped; the build reports them.
pinnedForms :: Built -> Set (StageId, ItemId)
pinnedForms b = Set.fromList $
  [ (s, itId it) | it <- items, s <- Map.keys (itExpect it) ]
  ++ [ (rfStage, rfItem)
     | it <- items
     , Just n <- [itNotes it]
     , Right runs <- [renderNotes b n]
     , RForm {..} <- runs ]
  where
    items = Map.elems (prItems (bProject b))
