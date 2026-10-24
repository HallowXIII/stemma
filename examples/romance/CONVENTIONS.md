# Conventions for the Romance example

These fix the dates, the notation and the format of the attested data, so
that forms researched separately can be compared, and so that the rules
have one target. They follow the choices made in the spike
(`research/pilot-notes.md`).

## Stages and dates

| stage | what | date |
|---|---|---|
| `latin` | Classical Latin, with vowel length | |
| `vulgar-latin` | spoken Latin; not attested, no expectations | |
| `western-romance` | reconstructed; no expectations | |
| `old-spanish` | Castilian, as in the *Cantar de mio Cid* | c. 1200 |
| `spanish` | peninsular standard | today |
| `old-french` | Francien | c. 1150 |
| `french` | standard | today |

A form is expected at a stage only if it is attested at about that date in
that variety. A form from a neighbouring dialect or a later century is a
note, not an expectation.

## Notation

Broad phonemic IPA, one form per cell. Spelling goes in its own column.

**Spanish and Old Spanish**
- An acute on the stressed vowel of every stressed word, monosyllables
  included: *kantáɾ*, *é* (he), *pán*. Clitics (articles, object pronouns,
  *que*) have none: *el*, *la*, *me*.
- Tap ɾ and trill r; diphthongs written j, w: *tjéra*, *bwéno*.
- Old Spanish: sibilants ts dz s z ʃ ʒ; /b/ (from Latin -p-) apart from /β/
  (from -b-, -v-); f- kept where the Cid writes f (*fijo*), h- where it
  writes h; tʃ, ʎ, ɲ.
- Spanish: /θ/, /x/; /ʎ/ kept apart from /ʝ/; b d g without allophones.

**Old French** (c. 1150)
- No stress marks; ə for unstressed e.
- Diphthongs: *ie* as je, *ue* (< ŏ) as wɛ, *ai* as aj, *ei* as ej
  (and oj where it has become *oi*: *avojr*, but *plejn* before a nasal),
  *ou*/*eu* (< ō, ŭ) as ow. Falling glides are j and w: *aj*, *oj*, *aw*,
  *ow*, *ɛaw* (*chasteaus*).
- Affricates tʃ dʒ ts dz still affricates (*chantez* /tʃantets/).
- Nasalisation before a nasal consonant is allophonic: not marked.
- θ and ð are gone, and so is a final -t that was after a vowel at the
  time of syncope (*chante* /tʃantə/, *a*); one that was after a consonant
  stays (*dit* < *dicit*, *vit* < *vīdit*).
- e before a nasal consonant has become a (*tans*, *dant*, *vandrə*).
- Final -s is pronounced. Geminate rr is kept (*tɛrrə*); other geminates
  are single.

**French**
- Standard IPA as in the major dictionaries: ʁ; e/ɛ and o/ɔ as listed;
  a and ɑ merged as a; ɛ̃ apart from œ̃ (*un* /œ̃/); ə where the dictionary
  has it (*petit* /pəti/).
- No liaison consonants: the citation form alone.

## Cells

The `cell` column uses stemma's cell names, so that `expect:` blocks can
be generated from the table.

- **Nouns:** Old French NOM.SG, ACC.SG, NOM.PL, ACC.PL (the cas régime is
  ACC). Spanish and French ACC.SG, ACC.PL.
- **Adjectives:** Old French M.NOM.SG, M.ACC.SG, M.NOM.PL, M.ACC.PL,
  F.ACC.SG, F.ACC.PL (and F.NOM.SG, F.NOM.PL where they differ from the
  ACC). Spanish and French M.ACC.SG, M.ACC.PL, F.ACC.SG, F.ACC.PL.
- **Verbs:** INF; PRS.1SG, PRS.2SG, PRS.3SG, PRS.1PL, PRS.2PL, PRS.3PL;
  FUT.1SG, FUT.3SG; PRET.3SG (Spanish preterite, French passé simple);
  PTCP (the past participle, masculine singular; Old French oblique).
- **Pronouns and other function words:** see the research brief for each
  word. Where no cell fits, use `-` (the word's own form).
- **Doublets and derivatives** (learned borrowings, a case form that
  became a word) get their own row with a `kind` of `learned`, `derived`
  or `replaced`, and the stemma id in `id` if one is proposed.

## Attested data

All of it is in `attested.tsv`; `research/` has the notes of each batch.
Columns, tab-separated, with a header row:

```
id  latin  cell  stage  kind  spelling  ipa  confidence  source  note
```

- `id`: the stemma entry id (the Latin citation in lower case, without
  length marks: `murus`, `facere`, `ille`).
- `latin`: the Latin etymon as cited, with length marks; for a word not
  from the citation form, the actual etymon (*\*potēre*, *\*homini*).
- `kind`: `inherited`, `learned`, `semi-learned`, `derived`, `replaced`
  (the slot is filled by another word: Spanish *hermano* for *frater*),
  `suppletive` (the cell continues another verb: Spanish *fue*, *sido* for
  *ire*, *esse*) or
  `analogical` (the form is not the regular reflex; say of what in `note`).
- `confidence`: `high`, `medium` or `low`.
- `source`: a URL, or a book with section. Every row needs one.
- `note`: dating, variants, and where sources disagree.

Rows are wanted for every cell and stage above where the word is attested.
A cell with no attested form gets no row. A cell whose form the stage
lacks altogether (Spanish has no nominative) also gets no row.
