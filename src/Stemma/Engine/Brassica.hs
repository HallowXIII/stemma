{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

-- | Brassica, linked as a library.
module Stemma.Engine.Brassica (brassicaEngine) where

import Control.Monad (foldM, forM, when)
import Data.ByteString qualified as B
import Data.List (nub, stripPrefix)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8')
import Text.Read (readMaybe)

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
  , engineOutline = outline
  , engineInline = Just inline
  }

type Statements = SoundChanges Expanded GraphemeList

load :: RulesRef -> B.ByteString -> Either T.Text Rules
load ref bytes = do
  text <- either (const (Left (here "not valid UTF-8"))) Right (decodeUtf8' bytes)
  parsed <- either (Left . here . T.pack . errorBundlePretty) Right
    (parseSoundChanges (T.unpack text))
  expanded <- either (Left . here . expandError) Right (expandSoundChanges parsed)
  (before, statements) <- selectSegment (rrSegment ref) expanded
  pure Rules
    { rulesGraphemes = map T.pack (activeGraphemes before statements)
    , rulesInventory = map T.pack (inventory before statements)
    , rulesApply = pure . map (evolve statements)
    , rulesCategories = categories parsed
    , rulesUndo = Just (undo statements)
    }
  where
    here msg = renderRulesRef ref <> ": " <> msg

    selectSegment Nothing scs = Right ([], scs)
    selectSegment (Just n) scs =
      let segs = splitReports scs
      in if n <= length segs
           then Right (concat (take (n - 1) segs), segs !! (n - 1))
           else Left (here ("has only " <> T.pack (show (length segs)) <> " segment(s)"))

-- | A rule given inline: parsed and expanded once, then applied to forms.
-- Without a categories block of its own it sees the graphemes as they are.
inline :: T.Text -> Either T.Text (Form -> [Form])
inline text = do
  parsed <- either (Left . T.pack . errorBundlePretty) Right (parseSoundChanges (T.unpack text))
  statements <- either (Left . expandError) Right (expandSoundChanges parsed)
  pure (evoOutputs . evolve statements)

outline :: T.Text -> Either OutlineError [[RuleStatement]]
outline text = do
  parsed <- either (parseError . errorBundlePretty) Right (parseSoundChanges (T.unpack text))
  _ <- either (\e -> Left (OutlineError (expandError e) Nothing)) Right (expandSoundChanges parsed)
  pure (map (map describe) (splitReports parsed))
  where
    describe st = case st of
      RuleS _ -> RuleStatement "rule" (Just (T.pack (plaintext' st)))
      FilterS _ -> RuleStatement "filter" (Just (T.pack (plaintext' st)))
      _ -> RuleStatement "declaration" Nothing
    -- megaparsec's message starts with "line:column:".
    parseError msg = Left . OutlineError (T.pack msg) $
      case T.splitOn ":" (T.pack (takeWhile (/= '\n') msg)) of
        l : c : _ | Just l' <- readMaybe (T.unpack l), Just c' <- readMaybe (T.unpack c) -> Just (l', c')
        _ -> Nothing

-- | Split at @report@ statements (which are dropped).
splitReports :: SoundChanges c d -> [SoundChanges c d]
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

-- | Every grapheme declared in a segment: by the categories block in force
-- at its start and by its own. Only a block without @noreplace@ has to
-- declare every grapheme, so without one the list says nothing.
inventory :: Statements -> Statements -> [String]
inventory before seg
  | all fst lists = []
  | otherwise = nub (concatMap snd lists)
  where
    lists = take 1 (reverse [(nr, gs) | DeclS (GraphemeList nr gs) <- before])
      ++ [(nr, gs) | DeclS (GraphemeList nr gs) <- seg]

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

-- | The categories a rules file defines that hold only graphemes, as they
-- stand at its end.
categories :: SoundChanges CategorySpec Directive -> [(T.Text, [T.Text])]
categories parsed =
  [ (T.pack name, map T.pack gs)
  | (name, Left (FromElements es)) <- Map.toList defined
  , Just gs <- [mapM grapheme es] ]
  where
    defined = foldl (\cs d -> either (const cs) id (extendCategories cs d)) Map.empty
      [(new, defs) | DeclS (Categories new _ defs) <- parsed]
    grapheme = \case
      [Grapheme g] -> Just g
      _ -> Nothing

-- | Every word a segment takes to the given one. The statements are undone
-- last to first. Undoing one proposes words, and keeps those that the
-- statement itself takes to the word in hand, so a rule is never inverted,
-- only applied. A categories block or a filter proposes the word alone,
-- and so drops it if it has an undeclared grapheme or is filtered out.
undo :: Statements -> Int -> Form -> Either T.Text [Form]
undo statements limit form =
  map (map T.pack) . Set.toList
    <$> foldM back (Set.singleton (map T.unpack form)) (reverse statements)
  where
    back ws st = do
      propose <- either (Left . at st) Right (proposals st)
      found <- fmap Set.unions . forM (Set.toList ws) $ \w -> do
        let raw = take (limit + 1) (propose w)
        when (length raw > limit) (tooMany st)
        pure (Set.fromList (filter (elem w . applyStatementStr st) raw))
      when (Set.size found > limit) (tooMany st)
      pure found
    tooMany st = Left (at st ("more than " <> T.pack (show limit) <> " candidates"))
    at st msg = T.pack (plaintext' st) <> ": " <> msg

-- | The words a statement may have changed into a given one: more than it
-- really does, since the environment is not looked at here.
proposals :: Statement Expanded GraphemeList -> Either T.Text (PWord -> [PWord])
proposals = \case
  RuleS r -> do
    ts <- instances (target r)
    -- What the rule makes of each word its target matches, wherever it is.
    let bare = r {environment = [([], [])], exception = Nothing}
    pure . unapply $ nub
      [ (t', out)
      | t <- ts, let t' = filter (/= "#") t
      , out <- applyRuleStr bare t, out /= t' ]
  _ -> Right pure

-- | A word, with any of the places that are the second of a pair replaced
-- by the first. A pair with nothing second is a loss: its first is put
-- back at most once between two graphemes.
unapply :: [(PWord, PWord)] -> PWord -> [PWord]
unapply pairs = go True
  where
    lost = [t | (t, []) <- pairs]
    go gap w = here ++ [t ++ rest | gap, t <- lost, rest <- go False w]
      where
        here = case w of
          [] -> [[]]
          g : gs -> map (g :) (go True gs)
            ++ [ t ++ rest
               | (t, out@(_ : _)) <- pairs
               , Just after <- [stripPrefix out w], rest <- go True after ]

-- | The words a rule's target matches. A repeated lexeme is tried up to
-- twice.
instances :: [Lexeme Expanded 'Matched] -> Either T.Text [PWord]
instances = foldM (\ps l -> concat <$> mapM (\p -> map (p ++) <$> lexeme p l) ps) [[]]
  where
    lexeme p = \case
      Grapheme g -> Right [[g]]
      Category c -> category c
      GreedyCategory c -> category c
      Optional ls -> ([] :) <$> instances ls
      GreedyOptional ls -> ([] :) <$> instances ls
      Geminate -> Right [take 1 (reverse p)]
      Kleene l -> do
        one <- lexeme p l
        pure ([] : one ++ [a ++ b | a <- one, b <- one])
      Backreference _ c -> category c
      Autosegment _ _ gs -> Right (map pure gs)
      Wildcard _ -> Left "a wildcard in the target can't be undone"
      Feature {} -> Left "a feature in the target can't be undone"
    category (FromElements es) = concat <$> mapM instances es

expandError :: ExpandError -> T.Text
expandError = \case
  NotFound s -> "could not find category: " <> T.pack s
  InvalidBaseValue -> "invalid value used as base grapheme in feature definition"
  InvalidDerivedValue -> "invalid value used as derived grapheme in autosegment"
  MismatchedLengths -> "mismatched lengths in feature definition"
