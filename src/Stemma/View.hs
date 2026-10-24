-- | Human-readable CLI views of paradigms and individual form histories.
module Stemma.View
  ( paradigmView
  , historyView
  , traceView
  ) where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T

import Stemma.Build
import Stemma.Engine (renderForm, Step (..))
import Stemma.Load
import Stemma.Types

-- | The cells of the paradigm in force at a stage, including entry-specific
-- cells. Variants follow their main cell.
paradigmView :: Built -> ItemId -> StageId -> Either [Text] [Text]
paradigmView b i s = do
  (it, _) <- selected b i s
  pname <- maybe (Left [i <> " has no paradigm"]) Right (itParadigm it)
  unlessPresent b i s
  let proj = bProject b
      active = fromMaybe pname (paradigmAt proj it s)
  pd <- maybe (Left ["unknown paradigm " <> active]) Right (Map.lookup active (prParadigms proj))
  let defined = map fst (pfCells pd)
      extra = [c | cid <- itCells it
                 , let c = T.drop (T.length i + 1) cid
                 , c `notElem` defined
                 , hasReflex b s cid]
      names = defined ++ extra
      mains = [c | c <- names, snd (splitVariant c) == Nothing]
      ordered = concatMap (\c -> c : [v | v <- names, fst (splitVariant v) == c, v /= c]) mains
      line c =
        let cid = i <> "." <> c
            indent = if snd (splitVariant c) == Nothing then "" else "  "
        in indent <> cid <> "  " <> formAt b s cid
  pure $ (i <> " @ " <> s <> " (" <> active <> ")") : map line ordered

-- | One concise line per stage on the path to a destination.
historyView :: Built -> ItemId -> StageId -> Either [Text] [Text]
historyView b i s = do
  (it, path) <- selected b i s
  pure (concatMap (stageHistory b it) path)

-- | The detailed rule trace. Omitting the destination preserves the old
-- full-tree traversal, including branches.
traceView :: Built -> ItemId -> Maybe StageId -> Either [Text] [Text]
traceView b i dest = do
  (it, stages) <- case dest of
    Just s -> selected b i s
    Nothing -> (,bStageOrder b) <$> item b i
  pure (concatMap (stageTrace b it) stages)

item :: Built -> ItemId -> Either [Text] Item
item b i = maybe (Left ["unknown item " <> i]) Right (Map.lookup i (prItems (bProject b)))

selected :: Built -> ItemId -> StageId -> Either [Text] (Item, [StageId])
selected b i s = do
  it <- item b i
  let stages = famStages (prFamily (bProject b))
  if not (Map.member s stages) then Left ["unknown stage " <> s] else do
    let path = reverse (ancestorsOrSelf stages s)
    if itStage it `elem` path
      then Right (it, dropWhile (/= itStage it) path)
      else Left [i <> " has not formed on the path to " <> s]

unlessPresent :: Built -> ItemId -> StageId -> Either [Text] ()
unlessPresent b i s =
  if hasReflex b s i then Right ()
  else Left [i <> " has no form at " <> s]

hasReflex :: Built -> StageId -> ItemId -> Bool
hasReflex b s i = maybe False (Map.member i) (Map.lookup s (bActual b))

reflexAt :: Built -> StageId -> ItemId -> Maybe Reflex
reflexAt b s i = Map.lookup s (bActual b) >>= Map.lookup i

formAt :: Built -> StageId -> ItemId -> Text
formAt b s i = case reflexAt b s i of
  Nothing -> "—"
  Just rx | null (rxForms rx) -> "(deleted)"
  Just rx ->
    let phonemic = map (showForm (bProject b)) (rxForms rx)
        spelled = fromMaybe phonemic (spelledAt b False s i)
        joined = T.intercalate " ~ "
    in joined spelled <> if spelled == phonemic then "" else "  /" <> joined phonemic <> "/"

stageName :: Built -> StageId -> Text
stageName b s = maybe s stName (Map.lookup s (famStages (prFamily (bProject b))))

-- | A missing reflex immediately after a present one is a loss. Later
-- absent stages need no further row.
lossAt :: Built -> Item -> StageId -> Maybe Text
lossAt b it s = do
  p <- Map.lookup s (famStages (prFamily (bProject b))) >>= stParent
  previous <- reflexAt b p (itId it)
  if null (rxForms previous) then Nothing else
    if hasReflex b s (itId it) then Nothing else
      Just $ case Map.lookup s (itFate it) of
        Just Lost -> "(lost)"
        Just (ReplacedBy x) -> "(replaced by " <> x <> ")"
        Nothing -> "(absent)"

stageHistory :: Built -> Item -> StageId -> [Text]
stageHistory b it s = case reflexAt b s i of
  Just rx -> [stageName b s <> " [" <> s <> "]: " <> formAt b s i
              <> events (rxEvents rx)]
  Nothing -> maybe [] (\loss -> [stageName b s <> " [" <> s <> "]: " <> loss]) (lossAt b it s)
  where
    i = itId it
    events [] = ""
    events xs = "  [" <> T.intercalate "; " xs <> "]"

stageTrace :: Built -> Item -> StageId -> [Text]
stageTrace b it s = case reflexAt b s i of
  Nothing -> maybe [] (\loss -> [stageName b s <> ": " <> loss]) (lossAt b it s)
  Just rx ->
    (stageName b s <> ": "
      <> (if null (rxForms rx) then "(deleted)" else T.intercalate " ~ " (map renderForm (rxForms rx)))
      <> maybe "" (\f -> "   (from " <> renderForm f <> ")") (rxInput rx))
    : map ("  event: " <>) (rxEvents rx)
      ++ ["  " <> maybe "(deleted)" renderForm (stepResult st) <> "   " <> stepRule st
         | st <- rxSteps rx]
  where i = itId it
