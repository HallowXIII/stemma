-- | The HTTP API the browser UI (@ui/index.html@) uses. Builds run in this
-- process, and an edit is previewed by overlaying it on the project's
-- files in memory, so nothing is written until it is saved.
module Server.Api
  ( Env (..)
  , newEnv
  , app
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar, newMVar, withMVar)
import Control.Monad (forM, forM_, when)
import Data.Aeson (Value (..), encode, object, (.=))
import Data.Aeson qualified as A
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Pair)
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.ByteString.Lazy qualified as BL
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Scientific (floatingOrInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Text.IO qualified as TIO
import Network.HTTP.Types
import Network.Wai
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile)
import System.FilePath (makeRelative, takeDirectory, takeFileName, (</>))

import Stemma.Build
import Stemma.Engine (Engine (..))
import Stemma.Engine.Brassica (brassicaEngine)
import Stemma.Load
import Stemma.Output
import Stemma.Sources (Sources (..), overlay)

import Server.Files
import Server.StageRules

data Env = Env
  { envProject :: FilePath
  -- ^ Absolute, with symlinks resolved.
  , envIndex :: IO (Maybe ByteString)
  -- ^ The UI's page.
  , envLock :: MVar ()
  -- ^ Held while building or writing files.
  , envBaseline :: MVar (Maybe (Double, [Text]))
  -- ^ The current files' failed expectations, and the inputs' mtime they
  -- were computed for.
  }

newEnv :: FilePath -> IO (Maybe ByteString) -> IO Env
newEnv project index = Env project index <$> newMVar () <*> newMVar Nothing

app :: Env -> Application
app env req respond = respond =<< case (requestMethod req, pathInfo req) of
  ("GET", []) -> page
  ("GET", ["index.html"]) -> page
  ("GET", ["api", "lexicon"]) -> file (buildDir </> "lexicon.json") jsonType
  ("GET", ["api", "trace"]) -> file (buildDir </> "trace.json") jsonType
  ("GET", ["api", "diff"]) -> file (buildDir </> "diff.txt") "text/plain; charset=utf-8"
  ("GET", ["api", "rules"]) -> filesJson =<< rulesFiles project
  ("GET", ["api", "sources"]) -> filesJson =<< yamlFiles project
  ("GET", ["api", "status"]) -> status
  ("POST", ["api", "build"]) -> locked (json status200 . runJson "stemma-server: build" <$> buildProject env)
  ("POST", ["api", "outline"]) -> do
    o <- body
    let content = fromMaybe "" (text "content" o)
    pure (send status200 jsonType (BL.fromStrict (encodeUtf8 (outlineJson (engineOutline brassicaEngine content)))))
  ("POST", ["api", "preview"]) -> body >>= \o -> do
    p <- maybe (pure Nothing) (sourcePath project) (text "file" o)
    case p of
      Nothing -> pure (failure status400 "not a rules or YAML file in this project")
      Just path -> locked $ do
        let content = fromMaybe "" (text "content" o)
        r <- preview env (Map.singleton (relative path) (encodeUtf8 content)) []
        json status200 . object <$> previewJson env "stemma-server: preview" r
  ("POST", ["api", "changeset"]) -> body >>= locked . changeset env
  ("POST", ["api", "stage-rules"]) -> body >>= locked . stageRules env
  ("PUT", ["api", route]) | route `elem` ["rules", "source"] -> body >>= \o -> locked $ do
    p <- maybe (pure Nothing) ((if route == "rules" then rulesPath else sourcePath) project) (text "file" o)
    exists <- maybe (pure False) doesFileExist p
    case (p, text "content" o) of
      (Just path, Just content) | exists -> do
        B.writeFile path (encodeUtf8 content)
        pure (json status200 (object ["ok" .= True]))
      _ -> pure (failure status400 "not a file this server can edit")
  _ -> pure notFound
  where
    project = envProject env
    buildDir = project </> "build"
    relative = makeRelative project
    locked = withMVar (envLock env) . const
    body = do
      b <- strictRequestBody req
      pure (case A.decode b of Just (Object o) -> o; _ -> KM.empty)
    page = maybe (failure status404 "index.html not found; build first") (send status200 "text/html; charset=utf-8" . BL.fromStrict)
      <$> envIndex env
    file path ctype = do
      exists <- doesFileExist path
      if exists
        then send status200 ctype . BL.fromStrict <$> B.readFile path
        else pure (failure status404 (T.pack (takeFileName path) <> " not found; build first"))
    filesJson fs = do
      entries <- forM fs $ \f -> do
        content <- readText (project </> f)
        pure (object ["file" .= f, "content" .= content])
      pure (json status200 entries)
    status = do
      inputs <- inputsMtime project
      let lexicon = buildDir </> "lexicon.json"
      exists <- doesFileExist lexicon
      built <- if exists then Just <$> mtime lexicon else pure Nothing
      pure (json status200 (object ["project" .= project, "inputs" .= inputs, "built" .= built]))

-- * Builds

-- | A build as the CLI would run it: what it would print, whether it would
-- succeed, and for a preview its products (lexicon, traces, diff).
data Run = Run
  { runOut :: [Text]
  , runErr :: [Text]
  , runOk :: Bool
  , runProducts :: Maybe (Value, Value, [Change])
  }

failedRun :: [Text] -> Run
failedRun errs = Run [] (map ("error: " <>) errs) False Nothing

reportRun :: Built -> Maybe [Change] -> Maybe (Value, Value, [Change]) -> Run
reportRun b diff products =
  let (out, err) = buildReport b diff
  in Run out err (null (checkExpectations b)) products

-- | Build the project and write @build/@, as @stemma build@ does.
buildProject :: Env -> IO Run
buildProject env = do
  built <- either (pure . Left) (build brassicaEngine) =<< loadProject (envProject env)
  case built of
    Left errs -> pure (failedRun errs)
    Right b -> either failedRun (\diff -> reportRun b diff Nothing)
      <$> writeBuild (envProject env </> "build") b

-- | Build the project with some files written and others deleted, in
-- memory. The diff is against the current @build/forms.tsv@.
preview :: Env -> Map.Map FilePath ByteString -> [FilePath] -> IO Run
preview env writes deletes = do
  -- Name files relative to the project in messages.
  let change src = overlay writes deletes src {srcDir = ""}
  built <- either (pure . Left) (build brassicaEngine) =<< loadProjectWith change (envProject env)
  case built of
    Left errs -> pure (failedRun errs)
    Right b -> case lexiconJson b of
      Left errs -> pure (failedRun errs)
      Right lexicon -> do
        let tsv = envProject env </> "build" </> "forms.tsv"
            new = formsTsv b
        hadOld <- doesFileExist tsv
        old <- if hadOld then TIO.readFile tsv else pure new
        let diff = diffForms old new
        pure (reportRun b (if hadOld then Just diff else Nothing) (Just (lexicon, traceJson b, diff)))

-- | The failed expectations of the files as they are on disk, cached until
-- they change.
baseline :: Env -> IO [Text]
baseline env = do
  now <- inputsMtime (envProject env)
  modifyMVar (envBaseline env) $ \case
    cached@(Just (t, ms)) | t == now -> pure (cached, ms)
    _ -> do
      built <- either (pure . Left) (build brassicaEngine) =<< loadProject (envProject env)
      let ms = case built of
            Right b | Right _ <- lexiconJson b -> checkExpectations b
            _ -> []
      pure (Just (now, ms), ms)

runJson :: Text -> Run -> Value
runJson command = object . runFields command

runFields :: Text -> Run -> [Pair]
runFields command Run {..} =
  [ "ok" .= runOk
  , "code" .= (if runOk then 0 else 1 :: Int)
  , "command" .= command
  , "stdout" .= T.unlines runOut
  , "stderr" .= T.unlines runErr
  ]

previewJson :: Env -> Text -> Run -> IO [Pair]
previewJson env command r = do
  ms <- baseline env
  pure $ runFields command r ++
    [ "lexicon" .= fmap (\(l, _, _) -> l) (runProducts r)
    , "traces" .= fmap (\(_, t, _) -> t) (runProducts r)
    , "diff" .= fmap (\(_, _, d) -> map renderChange d) (runProducts r)
    , "baseline_mismatches" .= ms
    ]

-- * Editing files

-- | Write and delete several files together, after building a copy with
-- the change: @{writes: {path: text}, deletes: [path], expect: {path: text},
-- apply: bool}@. With @apply@, the change is made only if the copy built
-- and every file in @expect@ still has the text the change was based on.
changeset :: Env -> A.Object -> IO Response
changeset env o = case (orEmpty "writes" (Object KM.empty), orEmpty "deletes" (Array mempty), orEmpty "expect" (Object KM.empty)) of
  (Object writes, Array deletes, Object expect) -> do
    let keys m = [String (Key.toText k) | k <- KM.keys m]
    bad <- firstM (fmap isNothing . valuePath) (keys writes ++ toList deletes ++ keys expect)
    case bad of
      Just rel -> pure (failure status400 (pyStr rel <> " is not a rules or YAML file in this project"))
      Nothing
        | any isFamily [s | String s <- toList deletes] ->
            pure (failure status400 "family.yaml can't be deleted")
        | not (all isString (KM.elems writes ++ KM.elems expect)) ->
            pure (failure status400 "bad changeset")
        | otherwise -> do
            stale <- firstM changed [(Key.toText k, t) | (k, String t) <- KM.toList expect]
            case stale of
              Just (rel, _) -> pure $ json status409 (object
                [ "error" .= (rel <> " changed on disk since this was prepared; reload and try again")
                , "conflict" .= rel ])
              Nothing -> do
                -- Every path was checked above.
                ws <- forM [(Key.toText k, t) | (k, String t) <- KM.toList writes] $ \(k, t) -> do
                  Just p <- sourcePath project k
                  pure (p, t)
                ds <- forM [s | String s <- toList deletes] $ \k -> do
                  Just p <- sourcePath project k
                  pure p
                r <- preview env (Map.fromList [(makeRelative project p, encodeUtf8 t) | (p, t) <- ws])
                       (map (makeRelative project) ds)
                -- The baseline is of the files before the change.
                fields <- previewJson env "stemma-server: changeset" r
                let apply = maybe False truthy (KM.lookup "apply" o) && isJust (runProducts r)
                when apply $ do
                  forM_ ws $ \(p, t) -> do
                    createDirectoryIfMissing True (takeDirectory p)
                    B.writeFile p (encodeUtf8 t)
                  forM_ ds $ \p -> do
                    exists <- doesFileExist p
                    when exists (removeFile p)
                pure (json status200 (object (fields ++ ["applied" .= apply])))
  _ -> pure (failure status400 "bad changeset")
  where
    project = envProject env
    orEmpty k def = case KM.lookup k o of
      Just v | truthy v -> v
      _ -> def
    valuePath = \case
      String s -> sourcePath project s
      _ -> pure Nothing
    isFamily s = takeFileName (T.unpack s) `elem` ["family.yaml", "family.yml"]
    isString = \case String _ -> True; _ -> False
    changed (rel, t) = do
      let p = project </> T.unpack rel
      exists <- doesFileExist p
      if exists then (/= t) <$> readText p else pure True

-- | Give a stage a new rules file: create it and point the stage at it in
-- @family.yaml@. The change is built in memory first, so a bad edit never
-- reaches the files.
stageRules :: Env -> A.Object -> IO Response
stageRules env o = do
  path <- maybe (pure Nothing) (rulesPath project) rel
  case (stage, rel, path, KM.lookup "content" o) of
    (Just s, Just r, Just p, content)
      | not (T.null s), Just c <- maybe (Just "") asText content -> do
          exists <- doesFileExist p
          if exists
            then pure (failure status400 (r <> " already exists; choose another name"))
            else do
              family <- readText (project </> "family.yaml")
              case addStageRules family s r of
                Left e -> pure (failure status400 e)
                Right newFamily -> do
                  run <- preview env
                    (Map.fromList [("family.yaml", encodeUtf8 newFamily), (makeRelative project p, encodeUtf8 c)]) []
                  case runProducts run of
                    Nothing -> pure (failure status400
                      ("the project wouldn't build with this change:\n" <> T.unlines (runErr run)))
                    Just _ -> do
                      createDirectoryIfMissing True (takeDirectory p)
                      B.writeFile p (encodeUtf8 c)
                      B.writeFile (project </> "family.yaml") (encodeUtf8 newFamily)
                      pure (json status200 (object ["ok" .= True, "file" .= r]))
    _ -> pure (failure status400 "need a stage and a .bsc path inside the project")
  where
    project = envProject env
    stage = text "stage" o
    rel = text "file" o
    asText = \case String t -> Just t; _ -> Nothing

-- * Responses

jsonType :: ByteString
jsonType = "application/json; charset=utf-8"

send :: Status -> ByteString -> BL.ByteString -> Response
send st ctype bytes = responseLBS st
  [ (hContentType, ctype)
  , (hContentLength, encodeUtf8 (T.pack (show (BL.length bytes))))
  , (hCacheControl, "no-store") ]
  bytes

json :: A.ToJSON a => Status -> a -> Response
json st = send st jsonType . encode

failure :: Status -> Text -> Response
failure st msg = json st (object ["error" .= msg])

notFound :: Response
notFound = failure status404 "not found"

-- * Request bodies

-- | A string field.
text :: Key.Key -> A.Object -> Maybe Text
text k o = case KM.lookup k o of
  Just (String t) -> Just t
  _ -> Nothing

-- | JSON values as Python's truthiness sees them, since the UI was written
-- against a Python server.
truthy :: Value -> Bool
truthy = \case
  Null -> False
  Bool b -> b
  Number n -> n /= 0
  String s -> not (T.null s)
  Array a -> not (null a)
  Object m -> not (KM.null m)

-- | A value in an error message, as Python's @str@ shows it.
pyStr :: Value -> Text
pyStr = \case
  String s -> s
  Null -> "None"
  Bool True -> "True"
  Bool False -> "False"
  Number n -> either (T.pack . show) (T.pack . show) (floatingOrInteger n :: Either Double Integer)
  v -> decodeUtf8Lenient (BL.toStrict (encode v))

firstM :: (a -> IO Bool) -> [a] -> IO (Maybe a)
firstM _ [] = pure Nothing
firstM p (x : xs) = p x >>= \found -> if found then pure (Just x) else firstM p xs
