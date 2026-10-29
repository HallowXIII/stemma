module Main (main) where

import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as B
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text.IO qualified as TIO
import Options.Applicative
import System.Directory (canonicalizePath, createDirectoryIfMissing, doesFileExist)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (stderr)

import Stemma.Build
import Stemma.Engine (Engine (..))
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output (buildReport, outlineJson, writeBuild)
import Stemma.Query
import Stemma.Types (Family (..))
import Stemma.Typst
import Stemma.View

data Command
  = Build Bool
  | Shifts Text Text
  | Paradigm Text Text
  | History Text Text
  | Trace Text (Maybe Text)
  | Outline FilePath
  | Typst (Maybe Text) (Maybe FilePath) Bool Bool

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
    -- Only loads the project; the documents read build/lexicon.json.
    Typst stage out force package -> do
      when package installPackage
      -- The package alone needs no project.
      unless (package && stage == Nothing) $ do
        proj <- loadProject optDir >>= orDie
        writeTypst optDir proj stage (fromMaybe optDir out) force package
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
                                (progDesc "Parse a rules file and print its segments and statements as JSON"))
       <> command "typst" (info (Typst
              <$> optional (strOption (long "stage" <> metavar "STAGE" <> help "Also write dictionary-STAGE.typ"))
              <*> optional (strOption (long "out" <> metavar "OUT" <> help "Where to write them (default: DIR)"))
              <*> switch (long "force" <> help "Overwrite an existing dictionary document")
              <*> switch (long "package" <> help "Install stemma.typ as the Typst package @local/stemma instead"))
                              (progDesc "Write stemma.typ (or install it as a package), and a dictionary document for a stage")) )

buildAnd :: FilePath -> Command -> IO ()
buildAnd dir cmd = do
  proj <- loadProject dir >>= orDie
  built <- build brassicaEngine proj >>= orDie
  case cmd of
    Build strict -> do
      diff <- writeBuild (dir </> "build") built >>= orDie
      let failed = checkExpectations built
          (out, err) = buildReport built diff
      mapM_ (TIO.hPutStrLn stderr) err
      mapM_ TIO.putStrLn out
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
    Typst {} -> pure ()

-- | Install stemma.typ as this version's Typst package, replacing it.
installPackage :: IO ()
installPackage = do
  pkg <- packageDirectory
  createDirectoryIfMissing True pkg
  B.writeFile (pkg </> "stemma.typ") stemmaTyp
  B.writeFile (pkg </> "typst.toml") packageToml
  putStrLn ("installed " <> pkg)
  TIO.putStrLn ("  import it with #import \"" <> packageImport <> "\": stemma")

-- | Write stemma.typ to a directory, unless it is used as the package, and
-- a dictionary document for a stage if one is given. The document is left
-- alone if it exists, unless forced.
writeTypst :: FilePath -> Project -> Maybe Text -> FilePath -> Bool -> Bool -> IO ()
writeTypst dir proj stage out force package = do
  forM_ stage $ \s -> unless (Map.member s (famStages (prFamily proj))) $
    orDie (Left ["unknown stage " <> s])
  createDirectoryIfMissing True out
  unless package $ do
    B.writeFile (out </> "stemma.typ") stemmaTyp
    putStrLn ("wrote " <> (out </> "stemma.typ"))
  forM_ stage $ \s -> do
    let file = out </> dictionaryFile s
    exists <- doesFileExist file
    if exists && not force
      then putStrLn ("kept " <> file <> " (--force replaces it)")
      else do
        from <- canonicalizePath out
        lexicon <- (</> "build" </> "lexicon.json") <$> canonicalizePath dir
        let path = relativePath from lexicon
        TIO.writeFile file (dictionaryTyp proj s (if package then packageImport else "stemma.typ") path)
        putStrLn ("wrote " <> file)
        -- Typst reads only files under the compiled file's directory unless
        -- given a --root.
        when (".." `isPrefixOf` path) $
          putStrLn ("  it reads " <> path <> ", so compile it with typst's --root set to a directory above both")
  built <- doesFileExist (dir </> "build" </> "lexicon.json")
  unless built $ putStrLn "note: the documents read build/lexicon.json; run `stemma build` to write it"

orDie :: Either [Text] a -> IO a
orDie = \case
  Right a -> pure a
  Left errs -> do
    forM_ errs $ \e -> TIO.hPutStrLn stderr ("error: " <> e)
    exitFailure
