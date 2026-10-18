-- | The project format, as read from YAML. See docs/schema.md.
module Stemma.Types
  ( StageId
  , ItemId
  , RulesRef (..)
  , Family (..)
  , Stage (..)
  , Morphology (..)
  , Paradigm (..)
  , Dimension (..)
  , Part (..)
  , templateParts
  , Entry (..)
  , Source (..)
  , Event (..)
  , EventKind (..)
  , Fate (..)
  , Expect (..)
  , CatShift (..)
  , parseRulesRef
  , renderRulesRef
  , eventKindName
  ) where

import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Parser)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Text.Read (readMaybe)

type StageId = Text
type ItemId = Text

-- | A rules file, optionally restricted to one segment. Segments are the
-- stretches between Brassica @report@ statements, numbered from 1:
-- @rules/azal.bsc#2@ is everything between the first and second @report@.
data RulesRef = RulesRef
  { rrFile :: FilePath
  , rrSegment :: Maybe Int
  }
  deriving (Eq, Ord, Show)

parseRulesRef :: Text -> Either String RulesRef
parseRulesRef t = case T.breakOnEnd "#" t of
  ("", _) -> Right (RulesRef (T.unpack t) Nothing)
  (pre, n) -> case readMaybe (T.unpack n) of
    Just i | i >= 1 -> Right (RulesRef (T.unpack (T.dropEnd 1 pre)) (Just i))
    _ -> Left ("bad segment number in rules reference: " <> T.unpack t)

renderRulesRef :: RulesRef -> Text
renderRulesRef (RulesRef f s) = T.pack f <> maybe "" (("#" <>) . T.pack . show) s

instance FromJSON RulesRef where
  parseJSON = withText "rules reference" (either fail pure . parseRulesRef)

------------------------------------------------------------------------
-- family.yaml

data Family = Family
  { famName :: Text
  , famGraphemes :: [Text]
  , famBoundary :: Maybe Text
  -- ^ The morpheme boundary symbol, if boundaries are passed to the rules.
  , famStages :: Map StageId Stage
  }
  deriving (Show)

data Stage = Stage
  { stName :: Text
  , stAbbr :: Maybe Text
  , stParent :: Maybe StageId
  , stRules :: Maybe RulesRef
  , stOrthography :: Maybe RulesRef
  , stCurrent :: Bool
  }
  deriving (Show)

instance FromJSON Family where
  parseJSON = withObject "family" $ \o -> do
    famName <- o .: "name"
    notation <- o .:? "notation"
    (famGraphemes, famBoundary) <- case notation of
      Nothing -> pure ([], Nothing)
      Just n -> flip (withObject "notation") n $ \no ->
        (,) <$> no .:? "graphemes" .!= [] <*> (no .:? "boundary" >>= traverse boundary)
    famStages <- o .: "stages"
    pure Family {..}
    where
      boundary t
        | T.null t = fail "notation.boundary must not be empty"
        | T.any (`elem` ("*-" :: String)) t = fail "notation.boundary may not contain * or -"
        | otherwise = pure t

instance FromJSON Stage where
  parseJSON = withObject "stage" $ \o -> do
    stName <- o .: "name"
    stAbbr <- o .:? "abbr"
    stParent <- o .:? "parent"
    stRules <- o .:? "rules"
    stOrthography <- o .:? "orthography"
    stCurrent <- o .:? "current" .!= False
    pure Stage {..}

------------------------------------------------------------------------
-- morphology.yaml

data Morphology = Morphology
  { moAffixes :: Map ItemId Entry
  , moParadigms :: Map Text Paradigm
  }
  deriving (Show)

-- | A paradigm as written. 'Stemma.Load' resolves @extends@ and expands
-- the dimensions into cells.
data Paradigm = Paradigm
  { pdStage :: Maybe StageId
  , pdExtends :: Maybe Text
  , pdDimensions :: [Dimension]
  , pdTemplate :: Maybe [Text]
  -- ^ Dimension names, affix IDs and @~@, in order.
  , pdCells :: [(Text, [Part])]
  -- ^ In the order written: each cell is a template of affixes around the
  -- base. See 'templateParts'. With dimensions, these override or add to
  -- the cells the dimensions give.
  , pdExclude :: [Text]
  }
  deriving (Show)

-- | One dimension of a paradigm, such as number: its members, in order,
-- each with the affixes it contributes (none for an unmarked member).
data Dimension = Dimension
  { dmName :: Text
  , dmMembers :: [(Text, [ItemId])]
  }
  deriving (Show)

-- | A slot in a cell or morph template.
data Part = PBase | PAffix ItemId
  deriving (Eq, Show)

-- | Read a template: affix IDs, with @~@ for the base. Without a @~@,
-- the base comes first, so @[GEN]@ means @[~, GEN]@.
templateParts :: [Text] -> Either String [Part]
templateParts ts = case length (filter (== "~") ts) of
  0 -> Right (PBase : map PAffix ts)
  1 -> Right [if t == "~" then PBase else PAffix t | t <- ts]
  _ -> Left "a template may contain only one ~"

-- | YAML reads a bare @~@ as null, so null is the base as well.
template :: Value -> Parser [Part]
template v = do
  slots <- oneOrMany v
  either fail pure (templateParts (map (fromMaybe "~") slots))

instance FromJSON Morphology where
  parseJSON = withObject "morphology" $ \o -> do
    affixes <- o .:? "affixes" .!= KM.empty
    moAffixes <- Map.fromList <$> traverse affix (KM.toList affixes)
    moParadigms <- o .:? "paradigms" .!= Map.empty
    pure Morphology {..}
    where
      affix (k, v) = do
        e <- parseEntryBody (Key.toText k) v
        pure (Key.toText k, e)

instance FromJSON Paradigm where
  parseJSON = withObject "paradigm" $ \o -> do
    pdStage <- o .:? "stage"
    pdExtends <- o .:? "extends"
    pdDimensions <- traverse dimension =<< o .:? "dimensions" .!= []
    pdTemplate <- traverse (fmap (map (fromMaybe "~")) . oneOrMany) =<< o .:? "template"
    pdCells <- traverse cell =<< o .:? "cells" .!= []
    pdExclude <- o .:? "exclude" .!= []
    pure Paradigm {..}
    where
      dimension :: Value -> Parser Dimension
      dimension = single "paradigm dimension" "`NAME: [MEMBER: affix, ...]`" $ \k v ->
        Dimension k <$> (traverse member =<< parseJSON v)
      member :: Value -> Parser (Text, [ItemId])
      member = single "dimension member" "`MEMBER: affix`" $ \k v ->
        (k,) . catMaybes <$> oneOrMany v
      -- Cells are a list of single-key maps, so that their order survives.
      cell :: Value -> Parser (Text, [Part])
      cell = single "paradigm cell" "`NAME: affix`" $ \k v -> (k,) <$> template v

-- | Lists of single-key maps keep their order, unlike maps.
single :: String -> String -> (Text -> Value -> Parser a) -> Value -> Parser a
single what shape f = withObject what $ \o -> case KM.toList o of
  [(k, v)] -> f (Key.toText k) v
  _ -> fail ("each " <> what <> " must be a single " <> shape <> " pair")

oneOrMany :: FromJSON a => Value -> Parser [a]
oneOrMany v@(Array _) = parseJSON v
oneOrMany v = pure <$> parseJSON v

------------------------------------------------------------------------
-- lexicon/*.yaml

-- | An entry: a root, an affix, or a derivative. Exactly one of 'enForm'
-- and 'enSource' is set (checked in "Stemma.Load").
data Entry = Entry
  { enId :: ItemId
  , enForm :: Maybe Text
  , enSource :: Maybe Source
  , enStage :: Maybe StageId
  , enGloss :: Maybe Text
  , enCategory :: [CatShift]
  , enParadigm :: Maybe Text
  , enBound :: Maybe Bool
  -- ^ Not a word on its own. Defaults to true for affixes, false otherwise.
  , enNotes :: Maybe Text
  , enDerivatives :: [Entry]
  , enEvents :: [Event]
  , enFate :: Map StageId Fate
  , enExpect :: Map StageId Expect
  }
  deriving (Show)

data Source
  = SBase ItemId
  | SMorph ItemId [Part]
  -- ^ The base, and a template with exactly one 'PBase'.
  | SCell ItemId Text
  | SCompound [ItemId]
  | SLoan StageId ItemId
  deriving (Show)

data Event = Event
  { evAt :: StageId
  , evCell :: Maybe Text
  , evKind :: EventKind
  }
  deriving (Show)

data EventKind
  = Analogy [(Text, Text)] (Maybe Text)
  -- ^ Segment substitutions, and the model of the analogy.
  | Reform
  | Loan StageId (Maybe ItemId) (Maybe RulesRef)
  -- ^ Donor stage, donor item (default: the same item), adaptation rules.
  | Irregular Text (Maybe Text)
  -- ^ Form, reason.
  deriving (Show)

eventKindName :: EventKind -> Text
eventKindName = \case
  Analogy {} -> "analogy"
  Reform -> "reform"
  Loan {} -> "loan"
  Irregular {} -> "irregular"

data Fate = Lost | ReplacedBy ItemId
  deriving (Show)

-- | Forms the build must reproduce at a stage: either the bare form or, for
-- an entry with a paradigm, a map from cells to forms (or both).
data Expect = Expect
  { exForm :: Maybe Text
  , exCells :: Map Text Text
  }
  deriving (Show)

data CatShift = CatShift
  { csAt :: StageId
  , csIs :: Text
  }
  deriving (Show)

instance FromJSON Entry where
  parseJSON v = do
    i <- withObject "entry" (.: "id") v
    parseEntryBody i v

parseEntryBody :: ItemId -> Value -> Parser Entry
parseEntryBody enId = withObject "entry" $ \o -> do
  enForm <- o .:? "form"
  enSource <- o .:? "source"
  enStage <- o .:? "stage"
  enGloss <- o .:? "gloss"
  enCategory <- o .:? "category" .!= []
  enParadigm <- o .:? "paradigm"
  enBound <- o .:? "bound"
  enNotes <- o .:? "notes"
  enDerivatives <- o .:? "derivatives" .!= []
  enEvents <- o .:? "events" .!= []
  enFate <- o .:? "fate" .!= Map.empty
  enExpect <- o .:? "expect" .!= Map.empty
  pure Entry {..}

instance FromJSON Source where
  parseJSON = withObject "source" $ \o -> do
    base <- o .:? "base"
    morph <- o .:? "morph"
    cell <- o .:? "cell"
    compound <- o .:? "compound"
    loan <- o .:? "loan"
    case (base, morph, cell, compound, loan) of
      (Just b, Nothing, Nothing, Nothing, Nothing) -> pure (SBase b)
      (Just b, Just m, Nothing, Nothing, Nothing) -> SMorph b <$> template m
      (Just b, Nothing, Just c, Nothing, Nothing) -> pure (SCell b c)
      (Nothing, Nothing, Nothing, Just xs, Nothing) -> pure (SCompound xs)
      (Nothing, Nothing, Nothing, Nothing, Just l) ->
        withObject "loan source" (\lo -> SLoan <$> lo .: "from" <*> lo .: "id") l
      _ -> fail "source must be one of {base}, {base, morph}, {base, cell}, {compound}, {loan}"

instance FromJSON Event where
  parseJSON = withObject "event" $ \o -> case KM.toList o of
    [(k, body)] -> flip (withObject "event body") body $ \b -> do
      evAt <- b .: "at"
      evCell <- b .:? "cell"
      evKind <- case Key.toText k of
        "analogy" -> do
          repl <- b .: "replace"
          Analogy (Map.toList repl) <$> b .:? "model"
        "reform" -> pure Reform
        "loan" -> Loan <$> b .: "from" <*> b .:? "id" <*> b .:? "adapt"
        "irregular" -> Irregular <$> b .: "form" <*> b .:? "reason"
        other -> fail ("unknown event type: " <> T.unpack other)
      pure Event {..}
    _ -> fail "each event must be a single-key map such as `analogy: {...}`"

instance FromJSON Fate where
  parseJSON (String "lost") = pure Lost
  parseJSON v = withObject "fate" (\o -> ReplacedBy <$> o .: "replaced-by") v

instance FromJSON Expect where
  parseJSON (String t) = pure (Expect (Just t) Map.empty)
  parseJSON v = withObject "expected forms" (\o -> do
    let cells = KM.toList (KM.delete "form" o)
    exForm <- o .:? "form"
    exCells <- Map.fromList <$> traverse (\(k, c) -> (Key.toText k,) <$> parseJSON c) cells
    pure Expect {..}) v

instance FromJSON CatShift where
  parseJSON = withObject "category shift" $ \o ->
    CatShift <$> o .: "at" <*> (o .:? "is" >>= tag)
    where
      -- YAML 1.1 reads a bare N, Y, no, off, etc. as a boolean.
      tag = \case
        Nothing -> pure ""
        Just (String t) -> pure t
        Just (Bool _) -> fail "category tag was read as a boolean; quote it, e.g. is: \"N\""
        Just other -> fail ("category tag must be text, not " <> show other)
