-- | Resolving form references in prose notes.
--
-- > {magis}                     the form where the item was formed (starred if proto)
-- > {magis @ spanish}           the Spanish reflex, spelled
-- > {homo.ACC.SG @ old-spanish} a paradigm cell
-- > {magis @ spanish /}         phonemic rather than spelled
-- > {magis @ spanish !}         the regularly expected form, ignoring all events
--
-- Write @{{@ for a literal brace.
module Stemma.Notes
  ( Run (..)
  , renderNotes
  ) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T

import Stemma.Build
import Stemma.Load
import Stemma.Types (ItemId)

data Run
  = RText Text
  | RForm
      { rfText :: Text
      , rfRef :: Text
      , rfItem :: ItemId
      , rfStage :: Text
      , rfStar :: Bool
      }

renderNotes :: Built -> Text -> Either Text [Run]
renderNotes b = go
  where
    go t = case T.breakOn "{" t of
      (pre, "") -> Right [RText pre | not (T.null pre)]
      (pre, rest)
        | "{{" `T.isPrefixOf` rest -> (RText (pre <> "{") :) <$> go (T.drop 2 rest)
        | otherwise -> case T.breakOn "}" (T.drop 1 rest) of
            (_, "") -> Left ("unclosed { in notes: " <> T.take 30 rest)
            (ref, after) -> do
              r <- resolve b ref
              more <- go (T.drop 1 after)
              pure ([RText pre | not (T.null pre)] ++ r : more)

resolve :: Built -> Text -> Either Text Run
resolve b raw = do
  let stripped = T.strip raw
      body = T.dropWhileEnd (`elem` ("/! " :: String)) stripped
      flags = T.drop (T.length body) stripped
      phonemic = T.any (== '/') flags
      regular = T.any (== '!') flags
      (idPart, stagePart) = T.breakOn "@" body
      iid = T.strip idPart
      proj = bProject b
      root = prRootStage proj
  it <- maybe (Left ("unknown item in reference {" <> raw <> "}")) Right (Map.lookup iid (prItems proj))
  let stage = if T.null stagePart then itStage it else T.strip (T.drop 1 stagePart)
      results = if regular then bRegular b else bActual b
      phon = map (showForm proj) . rxForms <$> (Map.lookup stage results >>= Map.lookup iid)
      forms
        | phonemic || stage == root = phon
        | otherwise = spelledAt b regular stage iid
  fs <- case forms of
    Nothing | Map.member stage (bActual b) ->
      Left ("{" <> raw <> "}: " <> iid <> " has no reflex at " <> stage
            <> (if regular then "" else " (add ! for the would-be form)"))
    Nothing -> Left ("{" <> raw <> "}: unknown stage " <> stage)
    Just [] -> Left ("{" <> raw <> "}: " <> iid <> " was deleted by the rules at " <> stage)
    Just xs -> Right xs
  pure RForm
    { rfText = T.intercalate " ~ " fs
    , rfRef = T.strip raw
    , rfItem = iid
    , rfStage = stage
    , rfStar = stage == root
    }
