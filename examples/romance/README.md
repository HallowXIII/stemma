# Worked example: Latin to Spanish and French

103 Latin words traced through Vulgar Latin and Western Romance to Old
Spanish (c. 1200), Spanish, Old French (c. 1150) and French. They are
nouns of every declension, adjectives, pronouns and articles, and 27
verbs, regular and irregular. The build reproduces all 1968 attested
forms. 16 of them come from `irregular` events; every other form comes
from sound changes, analogies and paradigm changes that the handbooks
describe.

```sh
cabal run stemma -- -d examples/romance build
cabal run stemma -- -d examples/romance paradigm facere old-french
cabal run stemma -- -d examples/romance history stare.PRET.3SG spanish
cabal run stemma -- -d examples/romance trace habere.PRET.3SG old-french
examples/romance/check.sh -s       # attested forms reproduced, per word
```

## What's where

- `family.yaml`: nine stages. Vulgar Latin, Western Romance, Ibero-Romance
  and Gallo-Romance are reconstructed and have no expectations. The two
  intermediate stages exist so that an event can come after the voicing
  of *p t k* (Gallo-Romance) or *pl-*, *kl-* > *ʎ-* (Ibero-Romance).
- `morphology.yaml`: the affixes and the paradigms. Nouns lose their
  cases by `becomes` and `lost`. Verb paradigms re-form cells on one line
  (OF *-ons*, *-ez*; the Spanish 2pl) and carry events of their own.
- `lexicon/`: the entries, each with `expect` blocks generated from
  `attested.tsv`.
- `rules/`: Brassica sound changes. `latin-to-wr.bsc` covers Vulgar Latin
  and Western Romance. `wr-to-spanish.bsc` and `wr-to-french.bsc` each
  have three segments, for the intermediate stage, the old language and
  the modern one. The `learned-*.bsc` and `french-into-spanish.bsc` files
  adapt loans.
- `attested.tsv`: the attested forms, one row per form and stage, with a
  `kind` (inherited, analogical, semi-learned, learned, derived, replaced,
  suppletive), sources and notes. `CONVENTIONS.md` fixes the notation,
  the dates and the columns.
- `check.sh`: compares the last build with `attested.tsv`.
  `research/expect.sh ID` prints an entry's `expect` block, and
  `research/refresh-expect.sh FILE...` regenerates them in place.
  `research/SOURCES.md` lists the handbooks.

What came up for stemma itself is in [`docs/findings.md`](../../docs/findings.md).

## The handbook pass

The first build had 52 `irregular`s, nearly all strong perfects and the
short forms of frequent verbs. Pope, Penny, Lloyd and the DCECH turned
most of them into regular change or a named analogy.

**u-perfects** (Pope). Stem-stressed *hábuit*, *sápuit*, *plácuit*,
*pótuit*, *\*crḗduit*, *\*bíbuit*, *\*lḗguit* are regular:
- In Western Romance, *u* in hiatus becomes *w*.
- In Gallo-Romance, C + *w* > *ww* (Pope *awwet*, *krịwwịt*), and close
  *ẹ* becomes *ị* before it.
- In Old French, *ịww* > *y*, and *a* or *ǫ* + *ww* > *ɔ* (*crut*, *but*,
  *lut*; *ot*, *sot*, *plot*, *pot*).
- In Spanish the *w* moves into the stem and *aw* > *o* (*ove*, *sopo*,
  *plogo*; Penny).

*morī* has the stress on the ending (*\*morū́it*), which kept its *u* but
no *t* (*moru*, as in Pope's paradigm). *chut* and *estut* are re-formed
after *crut* and *but*. French *eut*, *sut*, *put*, *plut* remake Pope's
type A on the other u-perfects. Spanish *tovo* follows *ove*, *pudo*
takes the *u* of 1sg *pude*, and *estuvo* follows *tuve* and *anduve*.

**Other strong perfects.** *fist*, *tint* take the vowel of the 1sg, which
was raised by *-ī* (*fēcī* > *fis*, *tēnī* > *tin*; Pope). OSp *estido* is
*\*stetut*, with the weak ending *-ut* (from *-aut*) that gave strong
perfects their 3sg *-o*, and the *i* of 1sg *\*estide* (Penny).

**Allegro forms.** OF *faimes*, *dimes*, *faites*, *dites*, *estes* are the
regular reflexes of *facimus*, *dicimus*, *-itis*, *estis*: the last
survivors before *-ons* and *-ez* spread. *-ons* comes from *sons* <
*sumus*. *somes* is the alternative form, like *faimes*, and French
settled on *-ons* but *sommes*. French *es* continues the unstressed OF
*ẹs* (Pope).

**Old French presents** (Pope):
- *faz*, *plaz*: final *kj*, once *-o* is lost, gives *ts* without a glide.
- *font*, *ont*, *vont*, *estont*: from *\*faunt*, *\*aunt*, *\*vaunt*,
  *\*staunt*, one analogy. Taking *sunt* as its model is our assumption.
- *puis*: *\*possjo* for *possum*, perhaps after the subjunctives
  *\*monja*, *\*audja*; the yod then moves before *s* as it does before
  *r* (*muir*).
- *dui*: *\*duī*, after the second-declension plural, with *ó* raised by
  the final *ī*.
- French *fais*, *sais*, *meurs* take the 2sg. French *vais* takes the
  *ɛ* outcome of OF *oi* (*vǫis* > *vwęs* > *vę*), as *-ais* and
  *français* do.

**Spanish.**
- *sé* follows *he* (Penny, as Pidal): *sapiō* would give *\*sepo*.
- *no* is the sandhi form of *non*, generalised by the 15th century
  (DCECH).
- *mas* is contracted from *maes*, which the rules now give: *j* is lost
  between *a* and a front vowel, as in *maestro* (DCECH).
- OSp *fago* has no yod effect, after *digo*.

**French *yeux*.** OF *ueuz* > *ieus*, a regular dissimilation of the two
*w*, then *ɛw* > *ø*.

### Still `irregular` (16)

| form | why |
|---|---|
| VL *ájo*, *ás*, *át*, *ánt* | *habēre* reduced as an auxiliary, the source of the future |
| OSp *femos*, *feches* | early syncope (*fac'tis* > *feches*, as *fecho*), before the palatalisation the rules put first; they syncopate later, as in *diezmo* |
| OSp *omne*, *omnes* | beside *nombre* by 1200; likely a conservative spelling (Lloyd has no reason for the lag) |
| OF *lerre* | *rr* after *larron* |
| OF *sire* | reduced in address |
| OF *cui* | from *cui*, where the build has *quem* |
| OF *sai* | *\*sapiō* > *\*saipo* |
| OF *sui* | influenced by *fui*; not fully explained, Pope says |
| OF *vois* | irregular in Pope too, who supposes a form in *-sjo* |
| French *fils* /fis/ | a spelling pronunciation; *fiz* gives /fi/ |
| French *plaire* | after *faire* |

## Judgement calls

- **Dating.** Old French at 1150 sits on several changes:
  - *ei* > *oi* is taken as done (*avojr*);
  - *ai* > *ɛ* is taken as not yet (*aj*);
  - 3sg *-t* is taken as gone (*tʃantə*).

  Pope confirms the first and the last: final *t* was a fricative before
  1000 and gone by 1150, and *ei* > *oi* is 11th-century. *ai* > *ɛ* is
  unchecked.
- **Syncope and voicing.** Old French syncopates before voicing *p t k*
  (*conte*, *doit*, *cité*), and Spanish after it (*conde*). So the voicing
  is in each branch, not in Western Romance.
- **Diphthongs.** Old French diphthongises before nasals (*cuens* <
  *comes*). So *om*, *ome* and Castilian *omne* are an "unstressed use"
  analogy on *homo*.
- **Normalised rows.** A few rows were normalised so they agree with the
  rest:
  - OF *doit*, with *t* as in *nuit*;
  - *prestre*, with *ɛ* as in *terre*;
  - the u-perfects, with *-t* after *ww*;
  - *dui* /dyj/, read like *sui* and *muir*.
- **Spelling.** French spelling is not modelled. Where only the spelling
  shows an analogy (1sg *chante* for OF *chant*), the phonemic forms are
  the same.
