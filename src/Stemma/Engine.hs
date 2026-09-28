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

data Engine = Engine
  { engineName :: Text
  , engineLoad :: FilePath -> RulesRef -> IO (Either Text Rules)
  -- ^ Load a rules reference, relative to the given project directory.
  , engineTokenise :: [Text] -> Text -> Either Text Form
  -- ^ Split a written form into graphemes, given the known multigraphs.
  }
