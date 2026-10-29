{-# LANGUAGE TemplateHaskell #-}

-- | The Typst files @stemma typst@ writes: @stemma.typ@, built into the
-- binary so it matches the @lexicon.json@ this version writes, and a
-- starting document for a stage's dictionary.
module Stemma.Typst
  ( stemmaTyp
  , packageToml
  , packageImport
  , packageDirectory
  , dictionaryTyp
  , dictionaryFile
  , relativePath
  ) where

import Data.ByteString (ByteString)
import Data.FileEmbed (embedFile)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Version (showVersion)
import System.Directory (XdgDirectory (..), getHomeDirectory, getXdgDirectory)
import System.Environment (lookupEnv)
import System.FilePath (joinPath, splitDirectories, (</>))
import System.Info (os)

import Paths_stemma (version)
import Stemma.Load
import Stemma.Types

-- | @typst/stemma.typ@, with a note that it is generated.
stemmaTyp :: ByteString
stemmaTyp =
  "// Written by `stemma typst`, which replaces it each time it runs, so\n\
  \// don't edit it here.\n//\n"
    <> $(embedFile "typst/stemma.typ")

-- | The manifest that makes a directory with @stemma.typ@ a Typst package,
-- of this version of stemma.
packageToml :: ByteString
packageToml = encodeUtf8 $ T.unlines
  [ "[package]"
  , "name = \"stemma\""
  , "version = \"" <> T.pack (showVersion version) <> "\""
  , "entrypoint = \"stemma.typ\""
  , "description = \"Typst helpers for a stemma build\""
  ]

-- | How a document imports the package.
packageImport :: Text
packageImport = "@local/stemma:" <> T.pack (showVersion version)

-- | Where Typst looks for this version of the package: its local packages
-- directory, as Typst finds it (TYPST_PACKAGE_PATH, or else its data
-- directory).
packageDirectory :: IO FilePath
packageDirectory = do
  custom <- lookupEnv "TYPST_PACKAGE_PATH"
  packages <- case custom of
    Just p | not (null p) -> pure p
    _ | os == "darwin" -> (</> "Library" </> "Application Support" </> "typst" </> "packages") <$> getHomeDirectory
      | otherwise -> (</> "packages") <$> getXdgDirectory XdgData "typst"
  pure (packages </> "local" </> "stemma" </> showVersion version)

dictionaryFile :: StageId -> FilePath
dictionaryFile stage = "dictionary-" <> T.unpack stage <> ".typ"

-- | A document with a stage's dictionary, importing stemma.typ from the
-- given place (a path, or the package) and reading the lexicon from the
-- given path (relative to the document).
dictionaryTyp :: Project -> StageId -> Text -> FilePath -> Text
dictionaryTyp proj stage from lexicon = T.unlines
  [ "// The " <> name <> " dictionary, written by `stemma typst --stage " <> stage <> "`."
  , "// stemma won't overwrite it (without --force), so edit it freely."
  , "#import " <> str from <> ": stemma"
  , "#let (reflex, notes, entry, dictionary, paradigm) = stemma(json(" <> str (T.pack lexicon) <> "))"
  , ""
  , "#set document(title: " <> str (name <> " dictionary") <> ")"
  , "#heading(" <> str name <> ")"
  , ""
  , "#dictionary(" <> str stage <> ")"
  ]
  where
    name = maybe stage stName (Map.lookup stage (famStages (prFamily proj)))
    str t = "\"" <> T.concatMap (\c -> if c `elem` ['"', '\\'] then T.pack ['\\', c] else T.singleton c) t <> "\""

-- | The path from one directory to a file, both absolute, going up with
-- @..@ where needed.
relativePath :: FilePath -> FilePath -> FilePath
relativePath from to = joinPath (replicate (length fs - common) ".." ++ drop common ts)
  where
    fs = splitDirectories from
    ts = splitDirectories to
    common = length (takeWhile id (zipWith (==) fs ts))
