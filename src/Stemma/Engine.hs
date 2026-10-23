-- | The interface between stemma and a sound-change engine.
--
-- stemma never looks inside a rules file. An engine only has to load a
-- rules reference and apply it to a batch of words, each already split into
-- graphemes. A backend for a CLI tool such as Lexurgy implements the same
-- record by shelling out.
module Stemma.Engine
  ( Form
  , Step (..)
  , Evolution (..)
  , Rules (..)
  , Engine (..)
  , RuleStatement (..)
  , OutlineError (..)
  , renderForm
  ) where

import Data.Text (Text)
import Data.Text qualified as T

import Stemma.Types (RulesRef)

-- | A word as a list of graphemes.
type Form = [Text]

renderForm :: Form -> Text
renderForm = T.concat

-- | One rule that changed the word, and the word afterwards
-- ('Nothing' if the rule deleted it).
data Step = Step
  { stepRule :: Text
  , stepResult :: Maybe Form
  }

data Evolution = Evolution
  { evoOutputs :: [Form]
  -- ^ Usually exactly one. Several if the rules are nondeterministic,
  -- none if the word was deleted.
  , evoSteps :: [Step]
  -- ^ The derivation of the first output.
  }

data Rules = Rules
  { rulesGraphemes :: [Text]
  -- ^ Multigraphs the rules declare, used to tokenise forms written at
  -- this stage.
  , rulesApply :: [Form] -> IO [Evolution]
  -- ^ Must return exactly one 'Evolution' per input, in order.
  }

-- | One statement of a rules file, for display: its kind (@rule@,
-- @filter@ or @declaration@) and, for rules and filters, the text as
-- written, which is also what 'stepRule' reports when it applies.
data RuleStatement = RuleStatement
  { rsKind :: Text
  , rsText :: Maybe Text
  }

-- | Why a rules file could not be read, with the line and column if the
-- engine knows them.
data OutlineError = OutlineError
  { oeMessage :: Text
  , oePosition :: Maybe (Int, Int)
  }

data Engine = Engine
  { engineName :: Text
  , engineLoad :: FilePath -> RulesRef -> IO (Either Text Rules)
  -- ^ Load a rules reference, relative to the given project directory.
  , engineTokenise :: [Text] -> Text -> Either Text Form
  -- ^ Split a written form into graphemes, given the known multigraphs.
  , engineOutline :: Text -> Either OutlineError [[RuleStatement]]
  -- ^ Parse the text of a rules file into its segments (see 'RulesRef'),
  -- each a list of statements, without applying it.
  }
