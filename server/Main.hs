{-# LANGUAGE TemplateHaskell #-}

-- | Serve the browser UI for one project, building it in this process.
module Main (main) where

import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.FileEmbed (embedFile)
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import Options.Applicative
import System.Directory (canonicalizePath, doesFileExist)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (hFlush, hPutStrLn, stderr, stdout)

import Server.Api

data Opts = Opts
  { optDir :: FilePath
  , optPort :: Int
  , optUi :: Maybe FilePath
  }

main :: IO ()
main = do
  setLocaleEncoding utf8
  Opts {..} <- execParser (info (opts <**> helper)
    (progDesc "Serve the stemma browser UI for a project, with rebuild-on-demand. Binds to localhost only."))
  project <- canonicalizePath optDir
  hasFamily <- doesFileExist (project </> "family.yaml")
  unless hasFamily $ do
    hPutStrLn stderr ("error: " <> project <> " has no family.yaml")
    exitFailure
  env <- newEnv project (maybe (pure (Just index)) readPage optUi)
  putStrLn ("stemma ui for " <> project)
  putStrLn ("  http://127.0.0.1:" <> show optPort <> "/")
  hFlush stdout
  runSettings (setHost "127.0.0.1" (setPort optPort defaultSettings)) (app env)
  where
    opts = Opts
      <$> strOption (long "dir" <> short 'd' <> metavar "DIR" <> value "." <> showDefault
                     <> help "Project directory")
      <*> option auto (long "port" <> short 'p' <> metavar "PORT" <> value 8737 <> showDefault)
      <*> optional (strOption (long "ui" <> metavar "FILE"
                     <> help "Serve this index.html instead of the built-in one (for working on the UI)"))
    readPage f = do
      exists <- doesFileExist f
      if exists then Just <$> B.readFile f else pure Nothing

-- | The UI, built into the binary.
index :: ByteString
index = $(embedFile "ui/index.html")
