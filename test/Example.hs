-- | Build the Echo example and check it reproduces the forms in the Azal
-- grammar (recorded as `expect` in the lexicon).
module Main (main) where

import Control.Monad (forM_, unless)
import Data.Text.IO qualified as TIO
import System.Exit (exitFailure)

import Stemma.Build
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output (writeBuild)

main :: IO ()
main = do
  let dir = "examples/echo"
  proj <- loadProject dir >>= either die' pure
  built <- build brassicaEngine proj >>= either die' pure
  _ <- writeBuild (dir <> "/build") built >>= either die' pure
  let failed = checkExpectations built
  forM_ failed TIO.putStrLn
  unless (null failed) exitFailure
  TIO.putStrLn "example: all expected forms reproduced"
  where
    die' errs = mapM_ TIO.putStrLn errs >> exitFailure
