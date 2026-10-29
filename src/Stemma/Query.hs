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
  , shBase :: Maybe ItemId
  -- ^ Where the first category is the base's, the base.
  }

-- | Every adjacent pair of categories, on the line to each current stage,
-- that matches the two patterns. A derivative with no affix (conversion,
-- or a form in a new role) starts from its base's category where it was
-- formed; with an affix, the change is the affix's doing, not a shift.
findShifts :: Project -> Text -> Text -> [Shift]
findShifts proj fromPat toPat =
  [ Shift (itId it) leaf (ta, sa) (tc, sc) base
  | it <- map (prItems proj Map.!) (prItemOrder proj)
  , leaf <- leaves
  , let path = dropWhile (/= itStage it) (reverse (ancestorsOrSelf stages leaf))
  , isAncestorOrSelf stages (itStage it) leaf
  , ((ta, sa, base), (tc, sc, _)) <- pairs (collapse (fromBase it ++ [(t, s, Nothing) | s <- path, Just t <- [categoryAt proj it s]]))
  , globMatch fromPat ta, globMatch toPat tc ]
  where
    stages = famStages (prFamily proj)
    leaves = [s | (s, st) <- Map.toList stages, stCurrent st]
    fromBase it = case itBuild it of
      BSource (SBase b) -> baseAt it [b]
      BSource (SCell b c) -> baseAt it [b <> "." <> c, b]
      _ -> []
    baseAt it bs = take 1
      [ (t, itStage it, Just b)
      | b <- bs, Just bi <- [Map.lookup b (prItems proj)], Just t <- [categoryAt proj bi (itStage it)] ]
    -- Where the derivative keeps its base's category, the derivative's own
    -- is the one shown.
    collapse (x@(tx, _, bx) : y@(ty, _, _) : rest)
      | tx == ty = collapse ((if bx == Nothing then x else y) : rest)
      | otherwise = x : collapse (y : rest)
    collapse xs = xs
    pairs xs = zip xs (drop 1 xs)
