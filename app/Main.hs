module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.Text (Text)
import Data.Text.IO qualified as TIO
import Options.Applicative
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (stderr)

import Stemma.Build
import Stemma.Engine (Engine (..))
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output (diffSummary, outlineJson, writeBuild)
import Stemma.Query
import Stemma.View

data Command
  = Build Bool
  | Shifts Text Text
  | Paradigm Text Text
  | History Text Text
  | Trace Text (Maybe Text)
  | Outline FilePath

data Opts = Opts
  { optDir :: FilePath
  , optCommand :: Command
  }

main :: IO ()
main = do
  Opts {..} <- execParser (info (opts <**> helper) (progDesc "Computed etymological lexicons"))
  case optCommand of
    -- Only parses the file, so it works while the project doesn't build.
    Outline file -> do
      text <- if file == "-" then TIO.getContents else TIO.readFile (optDir </> file)
      let outline = engineOutline brassicaEngine text
      TIO.putStrLn (outlineJson outline)
      either (const exitFailure) (const (pure ())) outline
    cmd -> buildAnd optDir cmd
  where
    opts = Opts
      <$> strOption (long "dir" <> short 'd' <> metavar "DIR" <> value "." <> showDefault
                     <> help "Project directory")
      <*> hsubparser
        ( command "build" (info (Build <$> switch (long "strict" <> help "Fail on warnings too"))
                                (progDesc "Compute all forms; write build/lexicon.json, trace.json, forms.tsv and diff.txt"))
       <> command "shifts" (info (Shifts <$> strArgument (metavar "FROM") <*> strArgument (metavar "TO"))
                                 (progDesc "List category shifts matching FROM > TO (* is a wildcard)"))
       <> command "paradigm" (info (Paradigm <$> strArgument (metavar "ROOT") <*> strArgument (metavar "STAGE"))
                                   (progDesc "Show a root's paradigm at a stage"))
       <> command "history" (info (History <$> strArgument (metavar "ID") <*> strArgument (metavar "STAGE"))
                                  (progDesc "Show a form's history along the path to a stage"))
       <> command "trace" (info (Trace <$> strArgument (metavar "ID") <*> optional (strArgument (metavar "STAGE")))
                                (progDesc "Show an item's rule trace, optionally along one stage path"))
       <> command "rules" (info (Outline <$> strArgument (metavar "FILE" <> help "Relative to DIR; - for stdin"))
                                (progDesc "Parse a rules file and print its segments and statements as JSON")) )

buildAnd :: FilePath -> Command -> IO ()
buildAnd dir cmd = do
  proj <- loadProject dir >>= orDie
  built <- build brassicaEngine proj >>= orDie
  case cmd of
    Build strict -> do
      diff <- writeBuild (dir </> "build") built >>= orDie
      let failed = checkExpectations built
      forM_ (bWarnings built) $ \w -> TIO.hPutStrLn stderr ("warning: " <> w)
      forM_ failed $ \f -> TIO.hPutStrLn stderr ("MISMATCH: " <> f)
      mapM_ TIO.putStrLn (diffSummary built diff)
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
    Outline _ -> pure ()

orDie :: Either [Text] a -> IO a
orDie = \case
  Right a -> pure a
  Left errs -> do
    forM_ errs $ \e -> TIO.hPutStrLn stderr ("error: " <> e)
    exitFailure
