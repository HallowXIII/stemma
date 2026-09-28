-- | Category history: working out an item's category at a stage, and
-- finding shifts between categories along each line of descent.
module Stemma.Query
  ( categoryAt
  , Shift (..)
  , findShifts
  , globMatch
  ) where

import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T

import Stemma.Load
import Stemma.Types

-- | The category in force at a stage: the tag set at the nearest stage
-- on the path back to the root (the last one written, if several share a
-- stage).
categoryAt :: Project -> Item -> StageId -> Maybe Text
categoryAt proj it s =
  let path = ancestorsOrSelf (famStages (prFamily proj)) s
      depth x = length (takeWhile (/= x) (reverse path))
      applicable = [ (depth (csAt c), n, csIs c)
                   | (n, c) <- zip [0 :: Int ..] (itCategory it), csAt c `elem` path ]
  in listToMaybe [t | (_, _, t) <- sortOn (\(d, n, _) -> (Down d, Down n)) applicable]

data Shift = Shift
  { shItem :: ItemId
  , shLine :: StageId
  , shFrom :: (Text, StageId)
  , shTo :: (Text, StageId)
  }

-- | Every adjacent pair of categories, on the line to each current stage,
-- that matches the two patterns.
findShifts :: Project -> Text -> Text -> [Shift]
findShifts proj fromPat toPat =
  [ Shift (itId it) leaf a c
  | it <- map (prItems proj Map.!) (prItemOrder proj)
  , leaf <- leaves
  , let path = dropWhile (/= itStage it) (reverse (ancestorsOrSelf stages leaf))
  , isAncestorOrSelf stages (itStage it) leaf
  , (a, c) <- pairs (collapse [(t, s) | s <- path, Just t <- [categoryAt proj it s]])
  , globMatch fromPat (fst a), globMatch toPat (fst c) ]
  where
    stages = famStages (prFamily proj)
    leaves = [s | (s, st) <- Map.toList stages, stCurrent st]
    collapse (x : y : rest) | fst x == fst y = collapse (x : rest)
                            | otherwise = x : collapse (y : rest)
    collapse xs = xs
    pairs xs = zip xs (drop 1 xs)

-- | Shell-style matching with @*@ as the only wildcard.
globMatch :: Text -> Text -> Bool
globMatch pat t = go (T.splitOn "*" pat) t True
  where
    go [] rest _ = T.null rest
    go [p] rest anchored
      | anchored = p == rest
      | otherwise = p `T.isSuffixOf` rest
    go (p : ps) rest anchored
      | anchored = p `T.isPrefixOf` rest && go ps (T.drop (T.length p) rest) False
      | T.null p = go ps rest False
      | otherwise = case T.breakOn p rest of
          (_, "") -> False
          (_, found) -> go ps (T.drop (T.length p) found) False
