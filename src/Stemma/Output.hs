-- | Build products: @build/lexicon.json@ for Typst, and @build/forms.tsv@,
-- a flat listing whose changes between builds become @build/diff.txt@.
module Stemma.Output
  ( writeBuild
  , formsTsv
  , diffForms
  , outlineJson
  ) where

import Control.Monad (forM)
import Data.Aeson (Value, object, toJSON, (.=))
import Data.Aeson.Encode.Pretty qualified as P
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as BL
import Data.Either (partitionEithers)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
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
-- build (empty on the first build).
writeBuild :: FilePath -> Built -> IO (Either [Text] [Text])
writeBuild outDir b = case lexiconJson b of
  Left errs -> pure (Left errs)
  Right json -> do
    createDirectoryIfMissing True outDir
    let tsvFile = outDir </> "forms.tsv"
        new = formsTsv b
    hadOld <- doesFileExist tsvFile
    old <- if hadOld then TIO.readFile tsvFile else pure new
    let diff = diffForms old new
    BL.writeFile (outDir </> "lexicon.json") (P.encodePretty' prettyConfig json)
    TIO.writeFile tsvFile new
    TIO.writeFile (outDir </> "diff.txt") (T.unlines diff)
    pure (Right diff)
  where
    prettyConfig = P.defConfig {P.confIndent = P.Spaces 2, P.confCompare = compare}

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
  pure . (it,) $ object
    [ "id" .= itId it
    , "kind" .= kindName (itKind it)
    , "bound" .= itBound it
    , "owner" .= itOwner it
    , "gloss" .= itGloss it
    , "formed" .= itStage it
    , "source" .= sourceText it
    , "cells" .= itCells it
    , "paradigm" .= itParadigm it
    , "repatterns" .= [object ["at" .= s, "paradigm" .= p] | (s, p) <- itRepatterns it]
    , "variant_of" .= fmap fst variant
    , "variant" .= fmap snd variant
    , "notes" .= notes
    , "category" .= [object ["at" .= csAt c, "is" .= csIs c] | c <- itCategory it]
    , "fate" .= Map.map fateJson (itFate it)
    , "reflexes" .= object
        [ Key.fromText s .= reflexJson s
        | s <- bStageOrder b
        , Map.member (itId it) (regularAt s) ]
    ]
  where
    -- A cell named CELL~label: its main cell and label.
    variant = case (itKind it, itOwner it) of
      (KCell, Just o) -> case splitVariant (T.drop (T.length o + 1) (itId it)) of
        (main, Just l) -> Just (o <> "." <> main, l)
        _ -> Nothing
      _ -> Nothing
    proj = bProject b
    regularAt s = fromMaybe Map.empty (Map.lookup s (bRegular b))
    reflexJson s =
      let actual = Map.lookup s (bActual b) >>= Map.lookup (itId it)
          regular = Map.lookup s (bRegular b) >>= Map.lookup (itId it)
      in object
        [ "forms" .= fmap (map (showForm proj) . rxForms) actual
        , "spelled" .= spelledAt b False s (itId it)
        , "regular" .= fmap (map (showForm proj) . rxForms) regular
        , "regular_spelled" .= spelledAt b True s (itId it)
        , "category" .= categoryAt proj it s
        , "origin" .= fmap (T.toLower . T.pack . show . rxOrigin) actual
        , "events" .= maybe [] rxEvents actual
        , "input" .= (renderForm <$> (actual >>= rxInput))
        , "trace" .= maybe [] (map stepJson . rxSteps) actual
        ]
    stepJson st = object
      [ "rule" .= stepRule st, "result" .= fmap renderForm (stepResult st) ]
    fateJson = \case
      Lost -> toJSON ("lost" :: Text)
      ReplacedBy x -> object ["replaced-by" .= x]

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

diffForms :: Text -> Text -> [Text]
diffForms old new =
  [ s <> "  " <> i <> ": " <> describe (Map.lookup k o) (Map.lookup k n)
  | k@(s, i) <- Map.keys (Map.union o n)
  , Map.lookup k o /= Map.lookup k n ]
  where
    parse t = Map.fromList
      [ ((s, i), (sp, ph)) | l <- T.lines t, [i, s, sp, ph] <- [T.splitOn "\t" l] ]
    o = parse old
    n = parse new
    describe (Just (a, pa)) (Just (c, pc))
      | a == c = "/" <> pa <> "/ → /" <> pc <> "/"
      | otherwise = a <> " → " <> c
    describe Nothing (Just (c, _)) = "new: " <> c
    describe (Just (a, _)) Nothing = "gone (was " <> a <> ")"
    describe Nothing Nothing = ""
