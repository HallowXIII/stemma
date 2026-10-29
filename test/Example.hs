-- | Build the Romance example and check it reproduces the attested forms
-- (recorded as `expect` in the lexicon), then do the same for the
-- fixtures, which each test one feature.
module Main (main) where

import Control.Monad (forM_, unless)
import Data.ByteString qualified as B
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Directory (createDirectoryIfMissing)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)

import Stemma.Build
import Stemma.Collate (sortKey)
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output (formsTsv, writeBuild)
import Stemma.Query (Shift (..), categoryAt, findShifts)
import Stemma.Sources
import Stemma.Typst
import Stemma.View

import Server.StageRules (addStageRules)

projects :: [FilePath]
projects = ["examples/romance","test/fixtures/boundary", "test/fixtures/paradigms", "test/fixtures/cells", "test/fixtures/repattern", "test/fixtures/lost", "test/fixtures/morphophonology", "test/fixtures/allomorphs", "test/fixtures/becomes", "test/fixtures/continues"]

main :: IO ()
main = do
  ok <- mapM check projects
  overlaid <- checkOverlay
  stageRules <- checkStageRules
  typst <- checkTypst
  inputs <- checkInputs
  noRules <- checkNoRules
  continued <- checkContinuesJson
  outputs <- checkOutputs
  collated <- checkCollation
  shifted <- checkShifts
  derived <- checkDerives
  unless (and ok && overlaid && stageRules && typst && inputs && noRules && continued && outputs && collated && shifted && derived) exitFailure

-- | A stage's alphabet orders spelled forms: letters first, then the ties
-- within a letter (a before ā), and non-letters are skipped. lexicon.json
-- gives the key, and a letter the alphabet lacks is warned about.
checkCollation :: IO Bool
checkCollation = do
  let alphabet = [["a", "ā"], ["d"], ["m"], ["n"], ["š"], ["u"]]
      key = fst . sortKey alphabet
      words' = ["daum", "dāš", "dā", "dān", "da"]
      ordered = map snd (sortOn fst [(key w, w) | w <- words'])
  proj <- loadProjectWith (overlay (Map.singleton "family.yaml" family) []) "test/fixtures/boundary"
  built <- either (pure . Left) (build brassicaEngine) proj
  json <- withSystemTempDirectory "stemma-sort" $ \tmp -> case built of
    Left _ -> pure ""
    Right b -> writeBuild tmp b >> T.filter (`notElem` (" \n" :: String)) <$> TIO.readFile (tmp </> "lexicon.json")
  let warned = either (const []) bWarnings built
      failures =
        [ "the alphabet should order letters first, ties after: " <> T.pack (show ordered)
        | ordered /= ["da", "dā", "dān", "dāš", "daum"] ]
          ++ [ "a hyphen should be skipped" | key "-da" /= key "da" ]
          ++ [ "a letter the alphabet lacks should come last" | not (key "dq" > key "du") ]
          ++ [ "the project should build: " <> T.intercalate "; " errs | Left errs <- [built] ]
          ++ [ "lexicon.json should give the sort key: " <> T.take 200 json
             | not ("\"sort\":\"" `T.isInfixOf` json) ]
          ++ [ "a letter the alphabet lacks should be warned about: " <> T.pack (show warned)
             | not (any ("modern: the alphabet has no letter k, which is in " `T.isPrefixOf`) warned) ]
  forM_ failures $ \f -> TIO.putStrLn ("collation: " <> f)
  TIO.putStrLn (if null failures then "collation: forms sort by the stage's alphabet" else "collation: FAILED")
  pure (null failures)
  where
    family = "name: Boundary\nnotation:\n  boundary: \"+\"\nstages:\n  proto:\n    name: Proto\n"
          <> "  modern:\n    name: Modern\n    parent: proto\n    rules: rules/proto-to-modern.bsc\n"
          <> "    alphabet: \"a, b, d, e, i, l, m, n, o, r, t, v\"\n"

-- | The checks on a stage's forms: U+FFFD, graphemes the rules don't
-- declare (here the multigraph xx, from a rule written without a space),
-- and forbidden sequences, which are found across a morpheme boundary but
-- not at the edge where a bound form attaches.
checkOutputs :: IO Bool
checkOutputs = do
  built <- withFamily "    forbid: [\"i b\", \"# i\", \"a l #\"]\n"
  misforbidden <- withFamily "    forbid: [\"a # b\"]\n"
  let warned = either (const []) bWarnings built
      has p = any p warned
      failures =
        [ "the project should build: " <> T.intercalate "; " errs | Left errs <- [built] ]
          ++ [ "an undeclared multigraph should be warned about: " <> T.pack (show warned)
             | not (has ("modern: xx is not declared in the rules, but is in oxx (ox)" ==)) ]
          ++ [ "U+FFFD should be warned about: " <> T.pack (show warned)
             | not (has (\w -> "modern: U+FFFD, in place of" `T.isPrefixOf` w && "(qa)" `T.isInfixOf` w)) ]
          ++ [ "a forbidden sequence across a boundary should be found: " <> T.pack (show warned)
             | not (has (\w -> "modern: i b is forbidden, but is in " `T.isPrefixOf` w && "(bed.1S)" `T.isInfixOf` w)) ]
          ++ [ "# should match the end of a word: " <> T.pack (show warned)
             | not (has ("modern: a l # is forbidden, but is in kal (kar.DIR)" ==)) ]
          ++ [ "# should not match where a bound form attaches: " <> T.pack (show warned)
             | has ("modern: # i is forbidden" `T.isPrefixOf`) ]
          ++ [ "# inside a forbidden sequence should be an error"
             | not (either (any ("# marks a word edge" `T.isInfixOf`)) (const False) misforbidden) ]
  forM_ failures $ \f -> TIO.putStrLn ("outputs: " <> f)
  TIO.putStrLn (if null failures then "outputs: U+FFFD, undeclared and forbidden graphemes are reported" else "outputs: FAILED")
  pure (null failures)
  where
    withFamily forbid = do
      let family = "name: Boundary\nnotation:\n  boundary: \"+\"\nstages:\n  proto:\n    name: Proto\n"
                <> "  modern:\n    name: Modern\n    parent: proto\n    rules: rules/proto-to-modern.bsc\n" <> forbid
          rules = "categories\nC = p t k b d g m n l r s v x\nV = a e i o u\nB = &+\nend\n"
               <> "x r / xx\nr / n / _ + i\nd / t / _ #\nr / l / _ #\n"
          entries = "- id: ox\n  form: \"*oxr\"\n- id: qa\n  form: \"*qa\"\n"
      proj <- loadProjectWith (overlay (Map.fromList [ ("family.yaml", family), ("rules/proto-to-modern.bsc", rules)
                                                     , ("lexicon/zz.yaml", entries) ]) [])
                "test/fixtures/boundary"
      either (pure . Left) (build brassicaEngine) proj

-- | lexicon.json gives a continued cell's reflexes on every line it is
-- joined on, and what it continues, so that the views can follow it back.
-- Its regular forms continue too. Read after `check` has written it.
checkContinuesJson :: IO Bool
checkContinuesJson = do
  json <- T.filter (`notElem` (" \n" :: String)) <$> TIO.readFile "test/fixtures/continues/build/lexicon.json"
  let (_, rest) = T.breakOn "\"tako.SG\":{" json
      cell = fst (T.breakOn "\"tako.SG.DIR\":" rest)
      failures =
        [ "a cell joined on two lines should have reflexes on both"
        | not (all (`T.isInfixOf` cell) ["\"azal\":{", "\"new-wiyan\":{"]) ]
          ++ [ "a continued cell should say what it continues"
             | not ("\"continues\":{\"azal\":\"tako.SG.OBL\",\"new-wiyan\":\"tako.SG.OBL\"}" `T.isInfixOf` cell) ]
          ++ [ "a continued cell's regular forms should continue too"
             | "\"regular\"" `T.isInfixOf` cell ]
  forM_ failures $ \f -> TIO.putStrLn ("lexicon.json: " <> f)
  TIO.putStrLn (if null failures then "lexicon.json: continued cells can be followed back" else "lexicon.json: FAILED")
  pure (null failures)

-- | A stage without rules copies its parent's forms, with a warning.
checkNoRules :: IO Bool
checkNoRules = do
  family <- B.readFile "examples/romance/family.yaml"
  let extended = family <> "\n  catalan:\n    name: Catalan\n    parent: western-romance\n"
  built <- either (pure . Left) (build brassicaEngine)
    =<< loadProjectWith (overlay (Map.singleton "family.yaml" extended) []) "examples/romance"
  let failures = case built of
        Left errs -> ["the project should build: " <> T.intercalate "; " errs]
        Right b ->
          [ "the stage should be warned about: " <> T.pack (show (bWarnings b))
          | not (any ("catalan: no rules" `T.isPrefixOf`) (bWarnings b)) ]
            ++ [ "its forms should be its parent's"
               | spelledAt b False "catalan" "magis" /= spelledAt b False "western-romance" "magis"
                   || spelledAt b False "catalan" "magis" == Nothing ]
  forM_ failures $ \f -> TIO.putStrLn ("no rules: " <> f)
  TIO.putStrLn (if null failures then "no rules: forms are copied, with a warning" else "no rules: FAILED")
  pure (null failures)

-- | @stemma typst@ writes the repository's stemma.typ, and a dictionary
-- that finds the lexicon from wherever it is written.
checkTypst :: IO Bool
checkTypst = do
  source <- B.readFile "typst/stemma.typ"
  proj <- loadProject "examples/romance"
  let dict from = either (const "") (\p -> dictionaryTyp p "old-french" from "build/lexicon.json") proj
      failures =
        [ "the embedded stemma.typ should be typst/stemma.typ" | not (source `B.isSuffixOf` stemmaTyp) ]
          ++ [ "the dictionary should read the given lexicon and list the stage"
             | not (all (`T.isInfixOf` dict "stemma.typ") ["#import \"stemma.typ\": stemma", "json(\"build/lexicon.json\")", "#heading(\"Old French\")", "#dictionary(\"old-french\")"]) ]
          ++ [ "a dictionary using the package should import it"
             | not (("#import \"" <> packageImport <> "\": stemma") `T.isInfixOf` dict packageImport) ]
          ++ [ "the package should be named stemma, with stemma.typ as its entry point"
             | not (all (`B.isInfixOf` packageToml) ["name = \"stemma\"", "entrypoint = \"stemma.typ\""]) ]
          ++ [ "relative paths should go up where needed: " <> T.pack (show paths)
             | let paths = [relativePath "/p/docs" "/p/romance/build/lexicon.json", relativePath "/p/romance" "/p/romance/build/lexicon.json"]
             , paths /= ["../romance/build/lexicon.json", "build/lexicon.json"] ]
  forM_ failures $ \f -> TIO.putStrLn ("typst: " <> f)
  TIO.putStrLn (if null failures then "typst: stemma.typ embedded, dictionary written" else "typst: FAILED")
  pure (null failures)

-- | An edit overlaid in memory builds the same forms as a copy of the
-- project with the edit on disk, and a file deleted in memory stays
-- deleted.
checkOverlay :: IO Bool
checkOverlay = withSystemTempDirectory "stemma-test" $ \tmp -> do
  src <- readSources "examples/romance"
  forM_ (Map.toList (srcFiles src)) $ \(f, b) -> do
    createDirectoryIfMissing True (takeDirectory (tmp </> f))
    B.writeFile (tmp </> f) b
  let rules = "rules/wr-to-french.bsc"
      edited = maybe "" (<> "\na / o\n") (sourceFile rules src)
  B.writeFile (tmp </> rules) edited
  original <- forms =<< loadProject "examples/romance"
  onDisk <- forms =<< loadProject tmp
  inMemory <- forms =<< loadProjectWith (overlay (Map.singleton rules edited) []) "examples/romance"
  deleted <- forms =<< loadProjectWith (overlay Map.empty [rules]) "examples/romance"
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

-- | Expectations must all hold, and warnings fail a project.
check :: FilePath -> IO Bool
check dir = do
  proj <- loadProject dir >>= either die' pure
  built <- build brassicaEngine proj >>= either die' pure
  _ <- writeBuild (dir <> "/build") built >>= either die' pure
  let failed = checkExpectations built
      warned = bWarnings built
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
  | dir == "examples/romance" =
      [ "properties should come from the paradigm in force, or the entry nearer: " <> T.pack (show genders)
      | genders /= [ ("dens", "latin", "m"), ("dens", "spanish", "m"), ("dens", "french", "f")
                   , ("mare", "latin", "n"), ("mare", "spanish", "m"), ("mare", "french", "f")
                   , ("ferrum", "latin", "n"), ("ferrum", "french", "m"), ("aqua", "french", "f") ] ]
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
  | dir == "test/fixtures/lost" =
      [ "a repattern should not join cells its paradigm lost above it"
      | any (`Map.member` prItems (bProject b)) ["sem.SG.GEN", "sem.PL.GEN"]
          || not (Map.member "sem.SG.COM" (prItems (bProject b))) ]
      ++ [ "an entry formed below a loss should not have the lost cells"
         | any (`Map.member` prItems (bProject b)) ["ren.SG.GEN", "ren.PL.GEN"] ]
  | dir == "test/fixtures/continues" =
      [ "a continued cell should say what it continues, and go through the stage's rules"
      | not (case traceView b "pero.SG" (Just "azal") of
          Right xs -> any ("continues pero.SG.DIR" `T.isInfixOf`) xs && any ("o / u" `T.isInfixOf`) xs
          _ -> False) ]
      ++ [ "the case cells should be lost where case is"
         | not (case (historyView b "tako.SG.OBL" "azal", historyView b "tako.SG.OBL" "wiyan") of
             (Right a, Right w) -> any ("(lost)" `T.isInfixOf`) a && not (any ("(lost)" `T.isInfixOf`) w)
             _ -> False) ]
      ++ [ "an entry's changes to its case cells should not add them to the new paradigm"
         | any (\st -> spelledAt b False st "homa.SG.OBL" /= Nothing) ["azal", "new-wiyan"] ]
      ++ [ "an entry should be cited by the cell its paradigm in force names"
         | [cite "tako" "proto", cite "tako" "azal"] /= ["tako.SG.DIR", "tako.SG"] ]
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
      ++ [ "becomes should follow the paradigm in force: " <> T.pack (show inForce)
         | inForce /= ["wood @ late (noun-new)", "wood @ other (noun-late)", "ash @ late (noun-late)"] ]
      ++ [ "a lost entry's cells should not come back, nor new ones be joined"
         | spelledAt b False "late" "elm.PL" /= Nothing || Map.member "oak.PL" (prItems (bProject b)) ]
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
    genders =
      [ (i, st, maybe "" (Map.findWithDefault "" "gender" . (\it -> propertiesAt (bProject b) it st)) (Map.lookup i (prItems (bProject b))))
      | (i, st) <- [ ("dens", "latin"), ("dens", "spanish"), ("dens", "french"), ("mare", "latin"), ("mare", "spanish")
                   , ("mare", "french"), ("ferrum", "latin"), ("ferrum", "french"), ("aqua", "french") ] ]
    cite i s = maybe "" (\it -> citedAt (bProject b) it s) (Map.lookup i (prItems (bProject b)))
    inForce = [x | (i, st) <- [("wood", "late"), ("wood", "other"), ("ash", "late")]
                 , Right (x : _) <- [paradigmView b i st]]
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
-- | A derivative with no affix starts from its base's category, so
-- conversion is a shift; one with an affix is not.
checkShifts :: IO Bool
checkShifts = do
  let entries = "- id: ka\n  form: \"*ka\"\n  category: [{ at: proto, is: \"N\" }]\n"
             <> "- id: kav\n  source: { base: ka }\n  stage: azal\n  category: [{ at: azal, is: V }]\n"
             <> "- id: kam\n  source: { base: ka, morph: COM }\n  category: [{ at: proto, is: ADJ }]\n"
  proj <- loadProjectWith (overlay (Map.singleton "lexicon/zz.yaml" entries) []) "test/fixtures/lost"
  let found = either (const []) (\p -> [(shItem s, shBase s, fst (shFrom s), fst (shTo s)) | s <- findShifts p "*" "*"]) proj
      failures =
        [ "the project should load: " <> T.intercalate "; " errs | Left errs <- [proj] ]
          ++ [ "conversion should be a shift from the base's category: " <> T.pack (show found)
             | found /= [("kav", Just "ka", "N", "V")] ]
  forM_ failures $ \f -> TIO.putStrLn ("shifts: " <> f)
  TIO.putStrLn (if null failures then "shifts: conversion is a shift, affixal derivation is not" else "shifts: FAILED")
  pure (null failures)

-- | An affix's @derives@ is the category of a derivative formed with it,
-- unless the derivative has its own; with several, the last decides, and
-- without one the derivative takes its parent's.
checkDerives :: IO Bool
checkDerives = do
  morphology <- B.readFile "test/fixtures/lost/morphology.yaml"
  let derived = B.concat
        [ before, "COM: { form: \"*-m\", derives: ADJ }\n  GEN: { form: \"*-i\", derives: \"N\" }"
        , B.drop (B.length "GEN: { form: \"*-i\" }\n  COM: { form: \"*-m\" }") after ]
        where (before, after) = B.breakSubstring "GEN: { form: \"*-i\" }" morphology
      entries = "- id: ka\n  form: \"*ka\"\n  category: [{ at: proto, is: V }]\n"
             <> "  derivatives:\n    - id: kara\n      source: { base: ka, morph: PL }\n"
             <> "- id: kam\n  source: { base: ka, morph: COM }\n"
             <> "- id: kami\n  source: { base: ka, morph: [~, COM, GEN] }\n"
             <> "- id: kamo\n  source: { base: ka, morph: COM }\n  category: [{ at: proto, is: ADV }]\n"
      load es = loadProjectWith (overlay (Map.fromList [("morphology.yaml", derived), ("lexicon/zz.yaml", es)]) []) "test/fixtures/lost"
  proj <- load entries
  misplaced <- load "- id: ka\n  form: \"*ka\"\n  derives: ADJ\n"
  let cats = either (const []) (\p -> [ (i, Map.lookup i (prItems p) >>= \it -> categoryAt p it "proto")
                                      | i <- ["kam", "kami", "kamo", "kara"] ]) proj
      failures =
        [ "the project should load: " <> T.intercalate "; " errs | Left errs <- [proj] ]
          ++ [ "derivatives should take their affixes' category: " <> T.pack (show cats)
             | cats /= [("kam", Just "ADJ"), ("kami", Just "N"), ("kamo", Just "ADV"), ("kara", Just "V")] ]
          ++ [ "derives on a word should be an error"
             | not (either (any ("only an affix derives a category" `T.isInfixOf`)) (const False) misplaced) ]
  forM_ failures $ \f -> TIO.putStrLn ("derives: " <> f)
  TIO.putStrLn (if null failures then "derives: affixes give their derivatives a category" else "derives: FAILED")
  pure (null failures)

checkInputs :: IO Bool
checkInputs = do
  onId <- buildWith "- id: on\n  form: \"*on\"\n"
  onBase <- buildWith "- id: ka\n  form: \"*ka\"\n  paradigm: noun\n  cells:\n    SG.DIR: { base: off }\n"
  spaced <- buildWith "- id: ka\n  form: \"*ka\"\n  events:\n    - analogy: { at: azal, replace: { a: a i } }\n"
  wide <- buildWith "- id: ka\n  form: \"*ka\"\n  events:\n    - analogy: { at: azal, replace: { ka: x } }\n"
  uncited <- buildWith "- id: ka\n  form: \"*ka\"\n  paradigm: noun\n  cite: NOPE\n"
  glossed <- buildWith "- id: ka\n  form: \"*ka\"\n  gloss: { proto: water, azal: river }\n"
  misglossed <- buildWith "- id: ka\n  form: \"*ka\"\n  gloss: { nowhere: water }\n"
  misnoted <- buildWith "- id: ka\n  form: \"*ka\"\n  notes: { nowhere: A note. }\n"
  boolProp <- buildWith "- id: ka\n  form: \"*ka\"\n  properties: { gender: n }\n"
  discontinued <- either (pure . Left) (build brassicaEngine) =<< loadProjectWith
    (overlay (Map.singleton "lexicon/zz.yaml" "- id: ka\n  form: \"*ka\"\n  paradigm: noun\n  cells:\n    SG: { continues: VOC }\n") [])
    "test/fixtures/continues"
  misplaced <- either (pure . Left) (build brassicaEngine) =<< loadProjectWith
    (overlay (Map.singleton "lexicon/zz.yaml" "- id: ka\n  form: \"*ka\"\n  paradigm: noun\n  cells:\n    SG: { at: wiyan, continues: SG.DIR }\n") [])
    "test/fixtures/continues"
  glossJson <- withSystemTempDirectory "stemma-gloss" $ \tmp -> case glossed of
    Left _ -> pure ""
    Right b -> writeBuild tmp b >> T.filter (/= ' ') <$> TIO.readFile (tmp </> "lexicon.json")
  let glosses = case glossed of
        Right b | Just it <- Map.lookup "ka" (prItems (bProject b)) ->
          [glossAt (bProject b) it s | s <- ["proto", "azal", "wiyan"]]
        _ -> []
  let failures =
        [ "an id read as a boolean should say so: " <> describe r
        | r <- [onId, onBase], not (failsWith "read as a boolean; quote it" r) ]
          ++ [ "a replacement with spaces should be split into graphemes: " <> describe spaced
             | either (const True) (\b -> spelledAt b False "azal" "ka" /= Just ["kai"]) spaced ]
          ++ [ "an analogy key of several graphemes should be an error: " <> describe wide
             | not (failsWith "is not one grapheme" wide) ]
          ++ [ "continuing a cell the entry lacks should be an error: " <> describe discontinued
             | not (failsWith "cell SG continues VOC, which ka does not have" discontinued) ]
          ++ [ "continuing at a stage without a change of paradigm should be an error: " <> describe misplaced
             | not (failsWith "cell SG continues SG.DIR at wiyan, but the entry doesn't change there" misplaced) ]
          ++ [ "a citation naming an unknown cell should be an error: " <> describe uncited
             | not (failsWith "cite names unknown cell NOPE" uncited) ]
          ++ [ "a gloss should hold from its stage down its own line: " <> T.pack (show glosses)
             | glosses /= [Just "water", Just "river", Just "water"] ]
          ++ [ "lexicon.json should give the gloss where it is formed, and a reflex's where it differs"
             | not (all (`T.isInfixOf` glossJson) ["\"gloss\":\"water\"", "\"gloss\":\"river\""]) ]
          ++ [ "a note at an unknown stage should be an error: " <> describe misnoted
             | not (failsWith "ka: unknown stage nowhere" misnoted) ]
          ++ [ "a property read as a boolean should say so: " <> describe boolProp
             | not (failsWith "read as a boolean; quote it" boolProp) ]
          ++ [ "a gloss at an unknown stage should be an error: " <> describe misglossed
             | not (failsWith "ka: unknown stage nowhere" misglossed) ]
  forM_ failures $ \f -> TIO.putStrLn ("inputs: " <> f)
  TIO.putStrLn (if null failures then "inputs: misread input is reported" else "inputs: FAILED")
  pure (null failures)
  where
    buildWith entries = do
      proj <- loadProjectWith (overlay (Map.singleton "lexicon/zz.yaml" entries) []) "test/fixtures/lost"
      either (pure . Left) (build brassicaEngine) proj
    describe = either (T.intercalate "; ") (\b -> "built, ka at azal is " <> T.pack (show (spelledAt b False "azal" "ka")))
    failsWith msg = either (any (msg `T.isInfixOf`)) (const False)
