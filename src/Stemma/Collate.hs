-- | Sorting spelled forms by a stage's alphabet.
module Stemma.Collate
  ( sortKey
  ) where

import Data.Char (GeneralCategory (..), generalCategory, isLetter)
import Data.List (sortOn)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Text.Printf (printf)

-- | The key a spelled form sorts by, and the letters in it that the
-- alphabet lacks. Each letter of the alphabet is a list of graphemes that
-- are equal but for ties, which their order decides. The key compares
-- every letter first and the ties after, so @a ā@ as one letter puts
-- /dān/ before /daum/. Characters that are not letters, such as hyphens,
-- are skipped; a letter the alphabet lacks sorts after all the others.
sortKey :: [[Text]] -> Text -> (Text, [Text])
sortKey alphabet = go [] [] []
  where
    graphemes = sortOn (Down . T.length . fst)
      [(g, (i, j)) | (i, letter) <- zip [0 :: Int ..] alphabet, (j, g) <- zip [0 :: Int ..] letter]
    missing = length alphabet
    go primary ties unknown t = case T.uncons t of
      Nothing -> (T.pack (concat (reverse primary) <> " " <> concat (reverse ties)), reverse unknown)
      Just (c, rest) -> case [(g, p) | (g, p) <- graphemes, g `T.isPrefixOf` t] of
        (g, (i, j)) : _ -> go (printf "%03d" i : primary) (printf "%02d" j : ties) unknown (T.drop (T.length g) t)
        []
          | isLetter c || isMark c -> go (printf "%03d" missing : primary) ("00" : ties) (T.singleton c : unknown) rest
          | otherwise -> go primary ties unknown rest
    isMark c = generalCategory c `elem` [NonSpacingMark, SpacingCombiningMark, EnclosingMark]
