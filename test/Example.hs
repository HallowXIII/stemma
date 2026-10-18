-- | Build the Echo example and check it reproduces the forms in the Azal
-- grammar (recorded as `expect` in the lexicon), then do the same for the
-- fixtures, which each test one feature.
module Main (main) where

import Control.Monad (forM_, unless)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Exit (exitFailure)

import Stemma.Build
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output (writeBuild)

projects :: [FilePath]
projects = ["examples/echo", "test/fixtures/boundary"]

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
  forM_ failed $ \f -> TIO.putStrLn (T.pack dir <> ": " <> f)
  forM_ warned $ \w -> TIO.putStrLn (T.pack dir <> ": warning: " <> w)
  let good = null failed && null warned
  TIO.putStrLn $ T.pack dir <> (if good then ": all expected forms reproduced" else ": FAILED")
  pure good
  where
    die' errs = mapM_ TIO.putStrLn errs >> exitFailure
