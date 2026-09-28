-- | Brassica, linked as a library.
module Stemma.Engine.Brassica (brassicaEngine) where

import Data.ByteString qualified as B
import Data.List (nub)
import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8')

import Brassica.SoundChange

import Stemma.Engine
import Stemma.Types (RulesRef (..), renderRulesRef)

brassicaEngine :: Engine
brassicaEngine = Engine
  { engineName = "brassica"
  , engineLoad = load
  , engineTokenise = \gs t ->
      either (Left . T.pack . errorBundlePretty) (Right . map T.pack)
        (tokeniseWord (map T.unpack gs) (T.unpack t))
  }

type Statements = SoundChanges Expanded GraphemeList

load :: FilePath -> RulesRef -> IO (Either T.Text Rules)
load dir ref = do
  bytes <- B.readFile (dir <> "/" <> rrFile ref)
  pure $ do
    text <- either (const (Left (here "not valid UTF-8"))) Right (decodeUtf8' bytes)
    parsed <- either (Left . here . T.pack . errorBundlePretty) Right
      (parseSoundChanges (T.unpack text))
    expanded <- either (Left . here . expandError) Right (expandSoundChanges parsed)
    (before, statements) <- selectSegment (rrSegment ref) expanded
    pure Rules
      { rulesGraphemes = map T.pack (activeGraphemes before statements)
      , rulesApply = pure . map (evolve statements)
      }
  where
    here msg = renderRulesRef ref <> ": " <> msg

    selectSegment Nothing scs = Right ([], scs)
    selectSegment (Just n) scs =
      let segs = splitReports scs
      in if n <= length segs
           then Right (concat (take (n - 1) segs), segs !! (n - 1))
           else Left (here ("has only " <> T.pack (show (length segs)) <> " segment(s)"))

-- | Split at @report@ statements (which are dropped).
splitReports :: Statements -> [Statements]
splitReports = go []
  where
    go acc [] = [reverse acc]
    go acc (ReportS : rest) = reverse acc : go [] rest
    go acc (st : rest) = go (st : acc) rest

-- | The graphemes in force at the start of a segment: those of the last
-- categories block before it, or else its own first one.
activeGraphemes :: Statements -> Statements -> [String]
activeGraphemes before seg = case reverse [gs | DeclS (GraphemeList _ gs) <- before] of
  gs : _ -> gs
  [] -> findFirstCategoriesDecl seg

evolve :: Statements -> Form -> Evolution
evolve statements form = case applyChanges statements (map T.unpack form) of
  [] -> Evolution [form] []
  logs@(l : _) -> Evolution
    { evoOutputs = nub [map T.pack w | Just w <- map getOutput logs]
    , evoSteps = mapMaybe step (derivations l)
    }
  where
    step (ActionApplied st out) = Just (Step (T.pack (plaintext' st)) (map T.pack <$> out))
    step (ReportWord _) = Nothing

expandError :: ExpandError -> T.Text
expandError = \case
  NotFound s -> "could not find category: " <> T.pack s
  InvalidBaseValue -> "invalid value used as base grapheme in feature definition"
  InvalidDerivedValue -> "invalid value used as derived grapheme in autosegment"
  MismatchedLengths -> "mismatched lengths in feature definition"
