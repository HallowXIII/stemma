-- | Working backwards from a known form: the forms at a stage's parent
-- that the stage's rules take to it, and the shape they share.
module Stemma.Reconstruct
  ( Reconstruction (..)
  , reconstruct
  , Shape (..)
  , Slot (..)
  , shape
  , renderShape
  ) where

import Data.Bifunctor (first)
import Data.List (nub, sortOn, transpose)
import Data.Map.Strict qualified as Map
import Data.Maybe (maybeToList)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T

import Stemma.Build (forbidden)
import Stemma.Engine
import Stemma.Load
import Stemma.Sources (sourceFile)
import Stemma.Types

data Reconstruction = Reconstruction
  { rcCandidates :: [Form]
  , rcCategories :: [(Text, [Text])]
  -- ^ The categories of the rules undone, to name the slots of a shape.
  }

-- | The forms at a stage's parent that its rules take to the given form.
-- A form with spaces is taken as graphemes already; any other is
-- tokenised as one written at the stage. Candidates that the parent's
-- inventory or @forbid@ exclude are left out. Events and joins are not
-- undone: this is about the rules alone.
reconstruct :: Engine -> Project -> Int -> StageId -> Text -> Either Text Reconstruction
reconstruct engine proj limit s written = do
  st <- note ("unknown stage " <> s) (Map.lookup s stages)
  ref <- note (s <> " has no rules to undo") (stRules st)
  rules <- load ref
  undo <- note (engineName engine <> " cannot undo rules") (rulesUndo rules)
  children <- mapM load [r | c <- Map.elems stages, stParent c == Just s, Just r <- [stRules c]]
  let graphemes = famGraphemes fam ++ maybeToList (famBoundary fam)
        ++ rulesInventory rules ++ concatMap rulesGraphemes (rules : children)
  form <- if T.any (== ' ') written
    then Right (T.words written)
    else first (("cannot tokenise " <> written <> ": ") <>) (engineTokenise engine graphemes written)
  candidates <- undo limit form
  parent <- maybe (Right Nothing) (\p -> Just <$> note ("unknown stage " <> p) (Map.lookup p stages)) (stParent st)
  declared <- concatMap rulesInventory
    <$> mapM load [r | Just p <- [parent], Just r <- [stRules p, stMorphophonology p]]
  let known = Set.fromList (famGraphemes fam ++ maybeToList (famBoundary fam) ++ declared)
      allowed f = (null declared || all (`Set.member` known) f)
        && not (any (\fb -> forbidden fam fb f) (maybe [] stForbid parent))
  pure (Reconstruction (filter allowed candidates) (rulesCategories rules))
  where
    fam = prFamily proj
    stages = famStages fam
    note msg = maybe (Left msg) Right
    load ref = do
      bytes <- note (renderRulesRef ref <> ": no such rules file") (sourceFile (rrFile ref) (prSources proj))
      engineLoad engine ref bytes

-- | What a set of forms has in common.
data Shape = Shape
  { shSlots :: [Slot]
  , shGroups :: [[[Form]]]
  -- ^ For each group of linked slots, numbered from 1, the combinations
  -- its slots take, in the order of the slots.
  , shExact :: Bool
  -- ^ Whether the forms are exactly those of the shape. If not, the shape
  -- has others too.
  }
  deriving (Eq, Show)

data Slot
  = Fixed Form
  | Open (Maybe Int) [Form]
  -- ^ One of several stretches of graphemes, an empty one if the slot may
  -- be absent, and the group it is linked in, if what it holds depends on
  -- other slots.
  deriving (Eq, Show)

-- | The shape of a set of forms: the graphemes they all have, in order,
-- and a slot wherever they differ between two of those. Slots are linked
-- if not every combination of what they hold occurs.
shape :: [Form] -> Shape
shape [] = Shape [] [] True
shape forms = Shape slots [combos g | g <- linked] exact
  where
    -- Shortest first, so that a form the others only add to is the spine.
    spine = foldl1 lcs (sortOn length forms)
    columns = transpose (map (gaps spine) forms)
    open = [i | (i, c) <- zip [0 :: Int ..] columns, length (nub c) > 1]
    column i = columns !! i
    dependent i j =
      length (nub (zip (column i) (column j))) /= length (nub (column i)) * length (nub (column j))
    groups = foldl join [] open
    join gs i = case span (not . any (dependent i)) gs of
      (apart, []) -> apart ++ [[i]]
      (apart, g : rest) -> join' (apart ++ [g ++ [i]]) rest i
    -- A slot that depends on two groups makes them one.
    join' done rest i = case span (not . any (dependent i)) rest of
      (_, []) -> done ++ rest
      (apart, g : more) -> join' (init done ++ [last done ++ g]) (apart ++ more) i
    linked = [g | g <- groups, length g > 1]
    combos g = nub (transpose (map column g))
    exact = product (map (length . combos) groups) == length (nub forms)
    groupOf i = lookup i [(j, n) | (n, g) <- zip [1 ..] linked, j <- g]
    slots = merge (concat (zipWith (\i c -> gap i c ++ lit i) [0 ..] columns))
    lit i = [Fixed [g] | g <- take 1 (drop i spine)]
    gap i c = case nub c of
      [[]] -> []
      [f] -> [Fixed f]
      fs -> [Open (groupOf i) fs]
    merge (Fixed a : Fixed b : rest) = merge (Fixed (a ++ b) : rest)
    merge (x : rest) = x : merge rest
    merge [] = []

-- | What a form has between the graphemes of the spine, before the first
-- and after the last.
gaps :: Form -> Form -> [Form]
gaps [] rest = [rest]
gaps (g : gs) w = let (pre, post) = break (== g) w in pre : gaps gs (drop 1 post)

-- | A longest common subsequence.
lcs :: Eq a => [a] -> [a] -> [a]
lcs xs ys = concat (take 1 (foldr row (replicate (length ys + 1) []) xs))
  where
    -- prev holds the answer for the rest of xs and each tail of ys.
    row x prev = foldr step [[]] (zip3 ys prev (drop 1 prev))
      where
        step (y, same, diag) acc =
          (if x == y then x : diag else longest same (concat (take 1 acc))) : acc
    longest a b = if length a >= length b then a else b

-- | A shape on one line, then a line for each group of linked slots with
-- the combinations it takes. A slot is written as the category whose
-- graphemes it holds, if there is one, in parentheses if it may be absent,
-- and with its group's number.
renderShape :: [(Text, [Text])] -> Shape -> [Text]
renderShape cats Shape {..} =
  T.concat (map slot shSlots)
    : [ "  " <> superscript n <> " " <> T.intercalate ", " (map (T.unwords . map stretch) combos)
      | (n, combos) <- zip [1 ..] shGroups ]
    ++ ["  some forms of this shape are not candidates" | not shExact]
  where
    slot = \case
      Fixed f -> renderForm f
      Open g fs ->
        let rest = filter (not . null) fs
            body
              | all ((== 1) . length) rest = set (concat rest)
              | otherwise = "{" <> T.intercalate "|" (map renderForm rest) <> "}"
            mark = maybe "" superscript g
        in if any null fs then "(" <> body <> mark <> ")" else body <> mark
    set = \case
      [g] -> g
      gs -> case [name | (name, ms) <- cats, Set.fromList ms == Set.fromList gs] of
        name : _ -> name
        [] -> "[" <> T.unwords gs <> "]"
    stretch f = if null f then "∅" else renderForm f
    superscript :: Int -> Text
    superscript = T.map (\d -> maybe d id (lookup d (zip "0123456789" "⁰¹²³⁴⁵⁶⁷⁸⁹"))) . T.pack . show
