module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Options.Applicative
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (stderr)

import Stemma.Build
import Stemma.Engine
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output (writeBuild)
import Stemma.Query
import Stemma.Types (Family (..), Stage (..))

data Command
  = Build Bool
  | Shifts Text Text
  | Trace Text

data Opts = Opts
  { optDir :: FilePath
  , optCommand :: Command
  }

main :: IO ()
main = do
  Opts {..} <- execParser (info (opts <**> helper) (progDesc "Computed etymological lexicons"))
  proj <- loadProject optDir >>= orDie
  built <- build brassicaEngine proj >>= orDie
  case optCommand of
    Build strict -> do
      diff <- writeBuild (optDir </> "build") built >>= orDie
      let failed = checkExpectations built
      forM_ (bWarnings built) $ \w -> TIO.hPutStrLn stderr ("warning: " <> w)
      forM_ failed $ \f -> TIO.hPutStrLn stderr ("MISMATCH: " <> f)
      if null diff
        then TIO.putStrLn "no forms changed"
        else TIO.putStr (T.unlines ("changed forms:" : map ("  " <>) diff))
      when (strict && (not (null failed) || not (null (bWarnings built)))) exitFailure
      unless (null failed) exitFailure
    Shifts from to -> do
      let found = findShifts proj from to
      when (null found) $ TIO.putStrLn "no matching shifts"
      forM_ found $ \Shift {..} ->
        TIO.putStrLn $ shItem <> "  [" <> shLine <> "]  "
          <> fst shFrom <> " (" <> snd shFrom <> ") > " <> fst shTo <> " (" <> snd shTo <> ")"
    Trace i -> do
      unless (Map.member i (prItems proj)) $ orDie (Left ["unknown item " <> i])
      forM_ (bStageOrder built) $ \s -> case Map.lookup s (bActual built) >>= Map.lookup i of
        Nothing -> pure ()
        Just rx -> do
          let name = maybe s stName (Map.lookup s (famStages (prFamily proj)))
          TIO.putStrLn $ name <> ": " <> T.intercalate " ~ " (map renderForm (rxForms rx))
            <> maybe "" (\f -> "   (from " <> renderForm f <> ")") (rxInput rx)
          forM_ (rxEvents rx) $ \e -> TIO.putStrLn ("  event: " <> e)
          forM_ (rxSteps rx) $ \st ->
            TIO.putStrLn $ "  " <> maybe "(deleted)" renderForm (stepResult st) <> "   " <> stepRule st
  where
    opts = Opts
      <$> strOption (long "dir" <> short 'd' <> metavar "DIR" <> value "." <> showDefault
                     <> help "Project directory")
      <*> hsubparser
        ( command "build" (info (Build <$> switch (long "strict" <> help "Fail on warnings too"))
                                (progDesc "Compute all forms; write build/lexicon.json, forms.tsv and diff.txt"))
       <> command "shifts" (info (Shifts <$> strArgument (metavar "FROM") <*> strArgument (metavar "TO"))
                                 (progDesc "List category shifts matching FROM > TO (* is a wildcard)"))
       <> command "trace" (info (Trace <$> strArgument (metavar "ID"))
                                (progDesc "Show an item's derivation at every stage")) )

orDie :: Either [Text] a -> IO a
orDie = \case
  Right a -> pure a
  Left errs -> do
    forM_ errs $ \e -> TIO.hPutStrLn stderr ("error: " <> e)
    exitFailure
