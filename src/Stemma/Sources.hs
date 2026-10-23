-- | The input files of a project, read into memory.
--
-- A project is loaded from a 'Sources' rather than from the directory, so
-- an edit can be tried by overlaying it on the files, without writing
-- anything (see 'overlay').
module Stemma.Sources
  ( Sources (..)
  , readSources
  , readExtra
  , overlay
  , sourceFile
  , sourceFiles
  , sourcePath
  , isInputDir
  , isInputFile
  ) where

import Control.Monad (filterM, forM)
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.List (isPrefixOf, isSuffixOf, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (normalise, takeFileName, (</>))

data Sources = Sources
  { srcDir :: FilePath
  -- ^ Where the files came from. Only used to name them in messages, so
  -- it may be empty.
  , srcFiles :: Map FilePath ByteString
  -- ^ Keyed by path relative to the project, normalised.
  }

-- | Every input file under a directory: @.yaml@, @.yml@ and @.bsc@ files,
-- outside directories named @build@ or starting with a dot.
readSources :: FilePath -> IO Sources
readSources dir = do
  exists <- doesDirectoryExist dir
  rels <- if exists then walk "" else pure []
  files <- forM rels $ \rel -> (normalise rel,) <$> B.readFile (dir </> rel)
  pure (Sources dir (Map.fromList files))
  where
    walk rel = do
      names <- sort <$> listDirectory (dir </> rel)
      fmap concat . forM names $ \n -> do
        let r = if null rel then n else rel </> n
        isDir <- doesDirectoryExist (dir </> r)
        if isDir
          then if isInputDir n then walk r else pure []
          else pure [r | isInputFile n]

-- | Add files the walk didn't find, such as a rules file outside the
-- project, from disk. Files that don't exist are left out.
readExtra :: [FilePath] -> Sources -> IO Sources
readExtra rels src = do
  missing <- filterM (doesFileExist . (srcDir src </>))
    [r | r <- map normalise rels, not (Map.member r (srcFiles src))]
  extra <- forM missing $ \r -> (r,) <$> B.readFile (srcDir src </> r)
  pure src {srcFiles = Map.union (srcFiles src) (Map.fromList extra)}

-- | Write some files and delete others, in memory.
overlay :: Map FilePath ByteString -> [FilePath] -> Sources -> Sources
overlay writes deletes src = src
  { srcFiles = Map.union (Map.mapKeys normalise writes)
      (foldr (Map.delete . normalise) (srcFiles src) deletes) }

sourceFile :: FilePath -> Sources -> Maybe ByteString
sourceFile rel = Map.lookup (normalise rel) . srcFiles

-- | The files in a directory of the project (not below it), in order.
sourceFiles :: FilePath -> Sources -> [(FilePath, ByteString)]
sourceFiles dir src =
  [ (f, b) | (f, b) <- Map.toList (srcFiles src), (normalise dir ++ "/") `isPrefixOf` f
  , '/' `notElem` drop (length (normalise dir) + 1) f ]

-- | A file's path for messages: under 'srcDir' when there is one.
sourcePath :: Sources -> FilePath -> FilePath
sourcePath src rel = if null (srcDir src) then rel else srcDir src </> rel

isInputDir :: FilePath -> Bool
isInputDir n = n /= "build" && not ("." `isPrefixOf` n)

isInputFile :: FilePath -> Bool
isInputFile n = any (`isSuffixOf` takeFileName n) [".yaml", ".yml", ".bsc"]
