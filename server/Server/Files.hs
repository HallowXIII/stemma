-- | The project's files as the UI sees them: which ones it lists, which it
-- may edit, and when they last changed.
module Server.Files
  ( rulesFiles
  , yamlFiles
  , rulesPath
  , sourcePath
  , inputsMtime
  , mtime
  , readText
  ) where

import Control.Monad (filterM, forM)
import Data.ByteString qualified as B
import Data.List (isSuffixOf, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import System.Directory
  ( canonicalizePath, doesDirectoryExist, doesFileExist, getModificationTime, listDirectory
  , pathIsSymbolicLink )
import System.FilePath (makeRelative, splitDirectories, (</>))

import Stemma.Sources (isInputDir)

-- | Files under the project, outside @build/@ and dot-directories, relative
-- to it: a directory's own files (sorted) before its subdirectories'.
projectFiles :: FilePath -> IO [FilePath]
projectFiles project = go ""
  where
    go rel = do
      names <- sort <$> listDirectory (project </> rel)
      let paths = [if null rel then n else rel </> n | n <- names]
      dirs <- filterM isDir paths
      files <- filterM (doesFileExist . (project </>)) paths
      below <- forM [d | d <- dirs, isInputDir (last (splitDirectories d))] go
      pure (files ++ concat below)
    -- Symlinked directories are not followed.
    isDir p = do
      d <- doesDirectoryExist (project </> p)
      l <- pathIsSymbolicLink (project </> p)
      pure (d && not l)

rulesFiles :: FilePath -> IO [FilePath]
rulesFiles project = filter (".bsc" `isSuffixOf`) <$> projectFiles project

yamlFiles :: FilePath -> IO [FilePath]
yamlFiles project = filter (\f -> any (`isSuffixOf` f) [".yaml", ".yml"]) <$> projectFiles project

-- | A @.bsc@ file the UI may write: inside the project (after resolving
-- symlinks and @..@), and not under @build/@.
rulesPath :: FilePath -> Text -> IO (Maybe FilePath)
rulesPath = projectPath [".bsc"]

-- | A rules or YAML file the UI may write.
sourcePath :: FilePath -> Text -> IO (Maybe FilePath)
sourcePath = projectPath [".bsc", ".yaml", ".yml"]

projectPath :: [Text] -> FilePath -> Text -> IO (Maybe FilePath)
projectPath suffixes project rel
  | not (any (`T.isSuffixOf` rel) suffixes) = pure Nothing
  | otherwise = do
      root <- canonicalizePath project
      p <- canonicalizePath (root </> T.unpack rel)
      let inside = splitDirectories root == take (length (splitDirectories root)) (splitDirectories p)
          parts = splitDirectories (makeRelative root p)
      pure (if inside && p /= root && "build" `notElem` parts then Just p else Nothing)

-- | The newest modification time of the project's inputs, in seconds.
inputsMtime :: FilePath -> IO Double
inputsMtime project = do
  files <- filter isInput <$> projectFiles project
  maximum . (0 :) <$> mapM (mtime . (project </>)) files
  where
    isInput f = any (`isSuffixOf` f) [".yaml", ".yml", ".bsc"]

mtime :: FilePath -> IO Double
mtime f = realToFrac . utcTimeToPOSIXSeconds <$> getModificationTime f

-- | A file's text, with line endings normalised to @\\n@.
readText :: FilePath -> IO Text
readText f = T.replace "\r" "\n" . T.replace "\r\n" "\n" . decodeUtf8Lenient <$> B.readFile f
