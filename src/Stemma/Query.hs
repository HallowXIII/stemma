-- | Category history: working out an item's category at a stage, and
-- finding shifts between categories along each line of descent.
module Stemma.Query
  ( categoryAt
  , Shift (..)
  , findShifts
  , globMatch
  ) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)

import Stemma.Load
import Stemma.Types

-- | The category in force at a stage: the tag set at the nearest stage
-- on the path back to the root (the last one written, if several share a
-- stage).
categoryAt :: Project -> Item -> StageId -> Maybe Text
categoryAt proj it s = categoryIn (famStages (prFamily proj)) (itCategory it) s

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
