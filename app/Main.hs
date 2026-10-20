module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Options.Applicative
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (stderr)

import Stemma.Build
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output (writeBuild)
import Stemma.Query
import Stemma.View

data Command
  = Build Bool
  | Shifts Text Text
  | Paradigm Text Text
  | History Text Text
  | Trace Text (Maybe Text)

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
    Paradigm i s -> mapM_ TIO.putStrLn =<< orDie (paradigmView built i s)
    History i s -> mapM_ TIO.putStrLn =<< orDie (historyView built i s)
    Trace i s -> mapM_ TIO.putStrLn =<< orDie (traceView built i s)
  where
    opts = Opts
      <$> strOption (long "dir" <> short 'd' <> metavar "DIR" <> value "." <> showDefault
                     <> help "Project directory")
      <*> hsubparser
        ( command "build" (info (Build <$> switch (long "strict" <> help "Fail on warnings too"))
                                (progDesc "Compute all forms; write build/lexicon.json, forms.tsv and diff.txt"))
       <> command "shifts" (info (Shifts <$> strArgument (metavar "FROM") <*> strArgument (metavar "TO"))
                                 (progDesc "List category shifts matching FROM > TO (* is a wildcard)"))
       <> command "paradigm" (info (Paradigm <$> strArgument (metavar "ROOT") <*> strArgument (metavar "STAGE"))
                                   (progDesc "Show a root's paradigm at a stage"))
       <> command "history" (info (History <$> strArgument (metavar "ID") <*> strArgument (metavar "STAGE"))
                                  (progDesc "Show a form's history along the path to a stage"))
       <> command "trace" (info (Trace <$> strArgument (metavar "ID") <*> optional (strArgument (metavar "STAGE")))
                                (progDesc "Show an item's rule trace, optionally along one stage path")) )

orDie :: Either [Text] a -> IO a
orDie = \case
  Right a -> pure a
  Left errs -> do
    forM_ errs $ \e -> TIO.hPutStrLn stderr ("error: " <> e)
    exitFailure
