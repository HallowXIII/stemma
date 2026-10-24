-- | Build the Echo example and check it reproduces the forms in the Azal
-- grammar (recorded as `expect` in the lexicon), then do the same for the
-- fixtures, which each test one feature.
module Main (main) where

import Control.Monad (forM_, unless)
import Data.ByteString qualified as B
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Directory (createDirectoryIfMissing)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)

import Stemma.Build
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output (formsTsv, writeBuild)
import Stemma.Sources
import Stemma.Typst
import Stemma.View

import Server.StageRules (addStageRules)

projects :: [FilePath]
projects = ["examples/echo", "examples/romance", "test/fixtures/boundary", "test/fixtures/paradigms", "test/fixtures/cells", "test/fixtures/repattern", "test/fixtures/lost", "test/fixtures/morphophonology", "test/fixtures/allomorphs", "test/fixtures/becomes"]

main :: IO ()
main = do
  ok <- mapM check projects
  overlaid <- checkOverlay
  stageRules <- checkStageRules
  typst <- checkTypst
  inputs <- checkInputs
  unless (and ok && overlaid && stageRules && typst && inputs) exitFailure

-- | @stemma typst@ writes the repository's stemma.typ, and a dictionary
-- that finds the lexicon from wherever it is written.
checkTypst :: IO Bool
checkTypst = do
  source <- B.readFile "typst/stemma.typ"
  proj <- loadProject "examples/echo"
  let dict = either (const "") (\p -> dictionaryTyp p "azal" "build/lexicon.json") proj
      failures =
        [ "the embedded stemma.typ should be typst/stemma.typ" | not (source `B.isSuffixOf` stemmaTyp) ]
          ++ [ "the dictionary should read the given lexicon and list the stage"
             | not (all (`T.isInfixOf` dict) ["json(\"build/lexicon.json\")", "#heading(\"Azal\")", "#dictionary(\"azal\")"]) ]
          ++ [ "relative paths should go up where needed: " <> T.pack (show paths)
             | let paths = [relativePath "/p/docs" "/p/echo/build/lexicon.json", relativePath "/p/echo" "/p/echo/build/lexicon.json"]
             , paths /= ["../echo/build/lexicon.json", "build/lexicon.json"] ]
  forM_ failures $ \f -> TIO.putStrLn ("typst: " <> f)
  TIO.putStrLn (if null failures then "typst: stemma.typ embedded, dictionary written" else "typst: FAILED")
  pure (null failures)

-- | An edit overlaid in memory builds the same forms as a copy of the
-- project with the edit on disk, and a file deleted in memory stays
-- deleted.
checkOverlay :: IO Bool
checkOverlay = withSystemTempDirectory "stemma-test" $ \tmp -> do
  src <- readSources "examples/echo"
  forM_ (Map.toList (srcFiles src)) $ \(f, b) -> do
    createDirectoryIfMissing True (takeDirectory (tmp </> f))
    B.writeFile (tmp </> f) b
  let rules = "rules/pe-to-azal.bsc"
      edited = maybe "" (<> "\na / o\n") (sourceFile rules src)
  B.writeFile (tmp </> rules) edited
  original <- forms =<< loadProject "examples/echo"
  onDisk <- forms =<< loadProject tmp
  inMemory <- forms =<< loadProjectWith (overlay (Map.singleton rules edited) []) "examples/echo"
  deleted <- forms =<< loadProjectWith (overlay Map.empty [rules]) "examples/echo"
  let failures =
        [ "the edit should change some forms" | onDisk == original ]
          ++ [ "an overlaid edit should build like the same edit on disk" | inMemory /= onDisk ]
          ++ [ "a rules file deleted in memory should be missing"
             | either (not . any ("no such rules file" `T.isInfixOf`)) (const True) deleted ]
  forM_ failures $ \f -> TIO.putStrLn ("overlay: " <> f)
  TIO.putStrLn (if null failures then "overlay: in-memory edits build like edits on disk" else "overlay: FAILED")
  pure (null failures)
  where
    forms = either (pure . Left) (fmap (fmap formsTsv) . build brassicaEngine)

-- | Giving a stage a rules file edits family.yaml as ui/serve.py did; the
-- expected texts are what its add_stage_rules returned.
checkStageRules :: IO Bool
checkStageRules = do
  let failures =
        [ stage <> ": expected " <> T.pack (show want) <> ", got " <> T.pack (show got)
        | (stage, input, want) <- cases
        , let got = addStageRules input stage "rules/new.bsc"
        , got /= want ]
  forM_ failures $ \f -> TIO.putStrLn ("stage rules: " <> f)
  TIO.putStrLn (if null failures then "stage rules: family.yaml edited as before" else "stage rules: FAILED")
  pure (null failures)
  where
    family = T.unlines
      [ "name: Test", "stages:", "  proto:", "    name: Proto", ""
      , "  azal:", "    name: Azal", "    parent: proto   # a comment", "    # notes", "    abbr: Az"
      , "  'wiyan':", "    name: Wiyan", "    rules: \"rules/w.bsc\""
      , "  flow: {name: Flow}", "notation: {}" ]
    notFound s = "couldn't find stage " <> s <> " in family.yaml (stages written in flow style, { ... }, aren't supported)"
    cases =
      [ ("azal", family, Right (T.replace "    parent: proto   # a comment\n" "    parent: proto   # a comment\n    rules: \"rules/new.bsc\"\n" family))
      , ("proto", family, Right (T.replace "    name: Proto\n" "    name: Proto\n    rules: \"rules/new.bsc\"\n" family))
      , ("wiyan", family, Left "wiyan already has rules in family.yaml")
      , ("nope", family, Left (notFound "nope"))
      , ("flow", family, Left (notFound "flow"))
      , ("proto", "name: Test\n", Left "family.yaml has no top-level stages: block")
      ]

-- | Expectations must all hold. Warnings fail a fixture, but not the
-- example, whose Wiyan stage has no rules yet.
check :: FilePath -> IO Bool
check dir = do
  proj <- loadProject dir >>= either die' pure
  built <- build brassicaEngine proj >>= either die' pure
  _ <- writeBuild (dir <> "/build") built >>= either die' pure
  let failed = checkExpectations built
      warned = if dir == "examples/echo" then [] else bWarnings built
      views = viewFailures dir built
  forM_ failed $ \f -> TIO.putStrLn (T.pack dir <> ": " <> f)
  forM_ warned $ \w -> TIO.putStrLn (T.pack dir <> ": warning: " <> w)
  forM_ views $ \v -> TIO.putStrLn (T.pack dir <> ": " <> v)
  let good = null failed && null warned && null views
  TIO.putStrLn $ T.pack dir <> (if good then ": all expected forms reproduced" else ": FAILED")
  pure good
  where
    die' errs = mapM_ TIO.putStrLn errs >> exitFailure

viewFailures :: FilePath -> Built -> [T.Text]
viewFailures dir b
  | dir == "test/fixtures/repattern" =
      [ "Azal should use noun-o and omit PL.GEN"
      | not (case paradigmView b "valyk" "azal" of
          Right xs -> "valyk @ azal (noun-o)" `elem` xs
            && not (any ("valyk.PL.GEN" `T.isInfixOf`) xs)
          _ -> False) ]
      ++ [ "Wiyan should retain noun-c and PL.GEN"
         | not (case paradigmView b "valyk" "wiyan" of
             Right xs -> "valyk @ wiyan (noun-c)" `elem` xs
               && any ("valyk.PL.GEN" `T.isInfixOf`) xs
             _ -> False) ]
      ++ [ "history should show loss only on Azal's line"
         | not (case (historyView b "valyk.PL.GEN" "azal", historyView b "valyk.PL.GEN" "wiyan") of
             (Right a, Right w) -> any ("(lost)" `T.isInfixOf`) a
               && not (any ("(lost)" `T.isInfixOf`) w)
             _ -> False) ]
      ++ [ "detailed trace should report repattern and loss"
         | not (case (traceView b "valyk.SG.COM" (Just "azal"), traceView b "valyk.PL.GEN" (Just "azal")) of
             (Right a, Right g) -> any ("repatterned as noun-o" `T.isInfixOf`) a
               && any ("(lost)" `T.isInfixOf`) g
             _ -> False) ]
      ++ [ "unrestricted trace should retain both branches"
         | not (case traceView b "valyk.PL.GEN" Nothing of
             Right xs -> any ("Azal: (lost)" `T.isInfixOf`) xs
               && any ("Wiyan:" `T.isPrefixOf`) xs
             _ -> False) ]
      ++ [ "spelling should show phonemic form when different"
         | not (case paradigmView respelled "valyk" "azal" of
             Right xs -> any ("valyk.SG.DIR  written  /valykkō/" `T.isInfixOf`) xs
             _ -> False) ]
      ++ [ "unknown stages should be rejected"
         | not (case historyView b "valyk.SG.COM" "missing" of
             Left _ -> True
             _ -> False) ]
  | dir == "test/fixtures/cells" =
      [ "entry-specific cells and variants should be shown"
      | not (case (paradigmView b "ego" "proto", paradigmView b "bes" "proto") of
          (Right ego, Right bes) -> any ("ego.VOC" `T.isInfixOf`) ego
            && ordered "bes.NPST.1S" "bes.NPST.1S~archaic" bes
            && ordered "bes.PST.3P" "bes.PST.3P~dialectal" bes
          _ -> False) ]
      ++ [ "an entry should be cited by its first cell by default, or as it says"
         | [cite "ego" "proto", cite "bes" "proto"] /= ["ego.SG.DIR", "bes"] ]
      ++ [ "cells with the same stem should share one internal item"
         | [i | i <- Map.keys (prItems (bProject b)), "homo~" `T.isPrefixOf` i] /= ["homo~stem~1"]
             || any ("~stem" `T.isInfixOf`) (prItemOrder (bProject b))
             || any (any ("~stem" `T.isInfixOf`) . Map.keys) (Map.elems (bActual b)) ]
  | dir == "test/fixtures/becomes" =
      [ "the citation should follow the paradigm in force, unless the entry gives one: " <> T.pack (show cites)
      | cites /= ["see.PST.1S", "see.NPST.1S", "see.PST.1S", "go.PST.1S", "go"] ]
  | dir == "test/fixtures/allomorphs" =
      [ "the affix's own reflex should list the allomorphs in force"
      | [spelledAt b False s "DAT" | s <- ["mid", "late", "other"]]
          /= [Just ["-a", "-ka"], Just ["-we", "-ke"], Just ["-ha"]] ]
      ++ [ "the trace should report the allomorphs chosen"
         | not (case (traceView b "lo-pl-dat" (Just "mid"), traceView b "kel.DAT" (Just "late")) of
             (Right p, Right k) -> any ("DAT: -ka (elsewhere, after r)" `T.isInfixOf`) p
               && any ("DAT: -a (after a)" `T.isInfixOf`) k
             _ -> False) ]
      ++ [ "the items carrying the allomorphs should be internal"
         | any ("~" `T.isInfixOf`) (prItemOrder (bProject b))
             || any (any ("~" `T.isInfixOf`) . Map.keys) (Map.elems (bActual b)) ]
  | otherwise = []
  where
    cite i s = maybe "" (\it -> citedAt (bProject b) it s) (Map.lookup i (prItems (bProject b)))
    cites = [cite "see" "mid", cite "see" "late", cite "see" "other", cite "go" "mid", cite "go" "late"]
    respelled =b {bSpelled = Map.adjust (Map.insert "valyk.SG.DIR" ["written"]) "azal" (bSpelled b)}
    ordered mainCell variant xs = case (findIndex mainCell xs, findIndex variant xs) of
      (Just a, Just c) -> c == a + 1
      _ -> False
    findIndex needle xs = lookup needle
      (zip (map (T.takeWhile (/= ' ') . T.stripStart) (drop 1 xs)) [0 :: Int ..])

-- | Input that would otherwise be silently misread: an id that YAML reads
-- as a boolean, and an analogy key that is not one grapheme. A replacement
-- may be written with spaces between its graphemes.
checkInputs :: IO Bool
checkInputs = do
  onId <- buildWith "- id: on\n  form: \"*on\"\n"
  onBase <- buildWith "- id: ka\n  form: \"*ka\"\n  paradigm: noun\n  cells:\n    SG.DIR: { base: off }\n"
  spaced <- buildWith "- id: ka\n  form: \"*ka\"\n  events:\n    - analogy: { at: azal, replace: { a: a i } }\n"
  wide <- buildWith "- id: ka\n  form: \"*ka\"\n  events:\n    - analogy: { at: azal, replace: { ka: x } }\n"
  uncited <- buildWith "- id: ka\n  form: \"*ka\"\n  paradigm: noun\n  cite: NOPE\n"
  let failures =
        [ "an id read as a boolean should say so: " <> describe r
        | r <- [onId, onBase], not (failsWith "read as a boolean; quote it" r) ]
          ++ [ "a replacement with spaces should be split into graphemes: " <> describe spaced
             | either (const True) (\b -> spelledAt b False "azal" "ka" /= Just ["kai"]) spaced ]
          ++ [ "an analogy key of several graphemes should be an error: " <> describe wide
             | not (failsWith "is not one grapheme" wide) ]
          ++ [ "a citation naming an unknown cell should be an error: " <> describe uncited
             | not (failsWith "cite names unknown cell NOPE" uncited) ]
  forM_ failures $ \f -> TIO.putStrLn ("inputs: " <> f)
  TIO.putStrLn (if null failures then "inputs: misread input is reported" else "inputs: FAILED")
  pure (null failures)
  where
    buildWith entries = do
      proj <- loadProjectWith (overlay (Map.singleton "lexicon/zz.yaml" entries) []) "test/fixtures/lost"
      either (pure . Left) (build brassicaEngine) proj
    describe = either (T.intercalate "; ") (\b -> "built, ka at azal is " <> T.pack (show (spelledAt b False "azal" "ka")))
    failsWith msg = either (any (msg `T.isInfixOf`)) (const False)
