-- | Giving a stage a rules file by editing @family.yaml@ as text, so its
-- comments and layout are kept.
module Server.StageRules (addStageRules) where

import Control.Monad (when)
import Data.Char (isSpace)
import Data.List (findIndex)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T

-- | @family.yaml@ with @rules: "REF"@ added to one stage, after its
-- @parent:@ line if it has one and otherwise at the end of its block. Only
-- stages written in block style are handled.
addStageRules :: Text -> Text -> Text -> Either Text Text
addStageRules yaml stage ref = do
  top <- maybe (Left "family.yaml has no top-level stages: block") Right
    (findIndex isStages ls)
  (atKey, indent) <- maybe (Left notFound) Right (findKey (drop (top + 1) (zip [0 ..] ls)))
  let block = blockLines indent (drop (atKey + 1) (zip [0 ..] ls))
      child = case block of
        (_, l) : _ -> Just (leading l)
        [] -> Nothing
      direct = [(k, l) | (k, l) <- block, Just (leading l) == child]
      parent = case [k | (k, l) <- direct, isKey "parent" l] of
        k : _ -> Just k
        [] -> Nothing
  when (any (isKey "rules" . snd) direct) $
    Left (stage <> " already has rules in family.yaml")
  let lastLine = maybe atKey fst (lastMay block)
      at = fromMaybe lastLine parent + 1
      new = T.replicate (fromMaybe (indent + 2) child) " " <> "rules: \"" <> ref <> "\""
  pure (T.intercalate "\n" (take at ls ++ [new] ++ drop at ls))
  where
    ls = T.splitOn "\n" yaml
    notFound = "couldn't find stage " <> stage
      <> " in family.yaml (stages written in flow style, { ... }, aren't supported)"

    -- ^stages\s*:\s*(#.*)?$
    isStages l = case T.stripPrefix "stages" l of
      Just rest -> afterColon rest
      Nothing -> False

    -- The stage's key, before the next top-level key: its line and indent.
    findKey [] = Nothing
    findKey ((k, l) : rest)
      | not (T.null (T.strip l)) && not (isSpace (T.head l)) && not ("#" `T.isPrefixOf` l) = Nothing
      | Just n <- keyIndent l = Just (k, n)
      | otherwise = findKey rest

    -- ^(\s+)(["']?)STAGE\2\s*:\s*(#.*)?$
    keyIndent l =
      let (lead, rest) = T.span isSpace l
          quoted q = maybe False afterColon (T.stripPrefix (q <> stage <> q) rest)
      in if not (T.null lead) && any quoted ["\"", "'", ""] then Just (T.length lead) else Nothing

    -- The lines of the stage's block, without blank lines and comments.
    blockLines indent = takeWhile ((> indent) . leading . snd) . filter (not . skipped . snd)
    skipped l = T.null (T.strip l) || "#" `T.isPrefixOf` T.stripStart l
    leading l = T.length l - T.length (T.stripStart l)

    -- ^\s*KEY\s*:
    isKey key l = case T.stripPrefix key (T.stripStart l) of
      Just rest -> ":" `T.isPrefixOf` T.stripStart rest
      Nothing -> False

    -- \s*:\s*(#.*)?$
    afterColon rest = case T.stripPrefix ":" (T.stripStart rest) of
      Just r -> let r' = T.stripStart r in T.null r' || "#" `T.isPrefixOf` r'
      Nothing -> False

    lastMay xs = if null xs then Nothing else Just (last xs)
