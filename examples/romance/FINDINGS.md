# Romance spike: findings

What came up while modelling ten Latin words down to Old Spanish, Spanish,
Old French and French. Each finding says what was needed, what the spike
does instead, and what stemma could do about it.

## stemma

1. **A cell can't be given a written stem.** Latin third-declension nouns
   have a nominative stem and an oblique one (*homō*, *homin-em*). The spike
   adds the oblique stem as an item of its own (`homin`) and points every
   cell but NOM.SG at it with `cells: { base: homin }`. A `stem:` on a cell
   override would do. Relatedly, the entry's bare form (*homō*) keeps
   evolving as a word on lines where its cell is lost (Spanish *wémo*).

2. **Affixes on their own have no stress, so their reflexes can't be
   joined later.** Latin stress depends on the whole word, so a bare affix
   evolves unstressed (INF *-āre* gives Old French *-ar*, not *-er*). This
   is harmless for cells joined in Latin, but `repattern`, `becomes` after
   the first stage and `at:` cells all join from the affixes' own reflexes.
   It worked for the French 1sg *chante*, which needs only the unstressed
   3sg *-ət*, but not for anything with a stressed ending. Allomorphs could
   supply each affix's later shape by hand. Better would be taking an
   affix's shape at a stage from a model cell (*-er* is whatever
   `cantare.INF` has after its stem).

3. **Internal boundaries have to be removed in every segment.** The rules
   drop `+` inside a word, keeping the edge boundaries so that bound stems
   and affixes aren't stressed as words. A cell joined at stage S enters S's
   rules with fresh internal boundaries, so every segment starts with the
   same deletion rule. A `notation` option to drop internal boundaries when
   joining would remove the need.

4. **`analogy` replaces every occurrence of a grapheme.** *aimerai* for OF
   *amerai* needs the stem's *a* changed but not the ending's, which
   `replace` can't express (left unfixed: the build gives *amʁe*). Also,
   `replace: { a: a i }` silently had no effect, while `{ a: aj }` works.
   A replacement containing a space should be an error, or be read as
   space-separated graphemes.

5. **An ending replaced by another ending is awkward.** The OF 1pl *-ons*
   (after *sumus*) is done as `replace: { á: ó }` on the WR form. It's
   really a cell re-formed with a different affix at Old French, which runs
   into finding 2.

6. **The future is built from separate affixes, not from *habēre*.**
   *cantare habeo* > *chanterai* is written with affixes FUT.1SG *-ájo* and
   FUT.3SG *-át* (Vulgar Latin, pre-stressed), with category history
   AUX > FUT. A template can't name another entry's cell, and the reduced
   *ajo* exists only from Western Romance on (an `irregular` on
   `habere.PRS.1SG`), while cells join from the forms entering a stage.
   This works, but the link to `habere` is only in prose.

7. **`on` is a boolean.** An item id `on` fails with "expected String,
   but encountered Boolean". stemma already explains this for category
   tags; ids need the same message.

8. **Some analogies are invisible in phonemic forms.** French 1sg *chante*
   (for OF *chant*) is re-formed at French, but both give /ʃɑ̃t/. Only the
   spelling shows it, which ties into French orthography by fiat.

9. **Learned words can't be modelled yet.** French *fragile* (1370) beside
   inherited *frêle*, and Spanish *frágil*, are borrowings from Latin that
   need adapting. A loan `source` can't take `adapt` (a known limitation),
   and a `loan` event would replace the inherited word instead of adding a
   doublet. Learned doublets are common enough in Romance that this needs
   fixing before the full example.

## Data

`attested.tsv` has the forms the build must reproduce, and their sources.
`attested-notes.md` lists where sources disagree. All 138 expected
forms are reproduced. The main judgement calls:

- **Sources.** The research couldn't reach Pope, Penny, Lloyd or Einhorn.
  It used Nyrop, Bourciez, Darmesteter, Menéndez Pidal (*Manual*, *Cid*)
  and Wiktionary. The full example needs a pass with the standard
  handbooks.
- **Dating.** Old French at 1150 sits on several changes: *ei* > *oi* (taken
  as done: *avojr*), *ai* > *ɛ* (taken as not yet: *aj*), and the loss of 3sg
  *-t* (taken as gone: *tʃantə*).
- **Rules.** Old French *om*, *ome* without a diphthong is done by blocking
  the diphthongisation of *ɔ́* before nasals, which is right for *homo* but
  needs checking against *bonum* and *comes*. Castilian *omne* is done with
  an event instead, since Spanish diphthongises before nasals (*puente*).
- ***aimerai*** is left without an expectation: the build gives *amʁe*
  (finding 4).

## Brassica

- In Brassica 1.0, `a / b / env1 / env2` gives two environments; an
  exception needs `//`. A single `/` before an exception silently adds the
  exception as an environment, which first stressed every final vowel.
- A deletion needs an environment: `h / / _`, not `h / /`.

## What worked without trouble

- Latin stress, assigned by rules on stressed-vowel graphemes after
  joining, including suffixes that keep their own stress.
- `becomes` at the first daughter stage (first-declension nominative plural
  in *-ās*), and `lost` with wildcards per line (genitive in Western
  Romance, nominative in Spanish and later in French).
- The Old French two-case system falling out of plain sound change
  (*murs*, *mur*, *mur*, *murs*).
- A derivative from a case form (*on* < *homo* NOM.SG) that outlives the
  case.
