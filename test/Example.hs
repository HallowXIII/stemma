-- | Build the Echo example and check it reproduces the forms in the Azal
-- grammar (recorded as `expect` in the lexicon), then do the same for the
-- fixtures, which each test one feature.
module Main (main) where

import Control.Monad (forM_, unless)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Exit (exitFailure)

import Stemma.Build
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output (writeBuild)
import Stemma.View

projects :: [FilePath]
projects = ["examples/echo", "test/fixtures/boundary", "test/fixtures/paradigms", "test/fixtures/cells", "test/fixtures/repattern", "test/fixtures/lost"]

main :: IO ()
main = do
  ok <- mapM check projects
  unless (and ok) exitFailure

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
  | otherwise = []
  where
    respelled = b {bSpelled = Map.adjust (Map.insert "valyk.SG.DIR" ["written"]) "azal" (bSpelled b)}
    ordered mainCell variant xs = case (findIndex mainCell xs, findIndex variant xs) of
      (Just a, Just c) -> c == a + 1
      _ -> False
    findIndex needle xs = lookup needle
      (zip (map (T.takeWhile (/= ' ') . T.stripStart) (drop 1 xs)) [0 :: Int ..])
