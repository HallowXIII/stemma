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

   **Answer.** A cell override takes `stem:`, a stem as written in place
   of the entry's form: `ACC.SG: { stem: "*homin-" }`. Each distinct stem
   is an internal item (like an allomorph), formed with the paradigm's
   cells and evolving as a bound root, so it never appears in the build
   products; cells with the same stem share it. It survives a `repattern`
   or `becomes`, as a suppletive base does. On an `at:` cell the stem is
   written as entering that stage, like a `repattern` stem. `homin` is gone
   from the spike.

   The bare form keeps evolving: for a verb with a large paradigm the stem
   is often the better thing to cite. What was missing is a choice of
   citation cell, which `cite` now gives, on a paradigm or an entry: one
   cell, `~` for the bare form, or a map from stages (`cite: { latin:
   NOM.SG, western-romance: ACC.SG }`, as the spike's nouns and adjectives
   now have). An entry's own wins over its paradigm's, the citation
   follows `becomes` and `repattern`, and the default is the first cell, as
   Typst assumed before. It is resolved by stemma and written to
   `lexicon.json`, and Typst and `ui/` use it for the headword and its
   etymology: Spanish *ómbre* < OSp. *ómne* < Lat. *\*hominem*, not
   < OSp. *wémo*. The build warns where the cited cell has no form; before
   this, every Spanish and French noun here was headed by a lost
   nominative.

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

   **Answer.** Not tackled yet: it raises wider questions about affix
   forms, and is the next thing to look at.

3. **Internal boundaries have to be removed in every segment.** The rules
   drop `+` inside a word, keeping the edge boundaries so that bound stems
   and affixes aren't stressed as words. A cell joined at stage S enters S's
   rules with fresh internal boundaries, so every segment starts with the
   same deletion rule. A `notation` option to drop internal boundaries when
   joining would remove the need.

   **Answer.** `notation.internal-boundaries: false` joins parts with no
   boundary between them, and drops any inside the parts, so the rules and
   the morphophonology see a joined form as one word. The edges of a bound
   result keep theirs. The spike sets it, and the deletion rule is gone
   from all four segments.

4. **`analogy` replaces every occurrence of a grapheme.** *aimerai* for OF
   *amerai* needs the stem's *a* changed but not the ending's, which
   `replace` can't express (left unfixed: the build gives *amʁe*). Also,
   `replace: { a: a i }` silently had no effect, while `{ a: aj }` works.
   A replacement containing a space should be an error, or be read as
   space-separated graphemes.

   **Answer.** The space: Brassica's tokeniser read only the first word of
   `a i`, so `a` became `a`. A replacement is now split on spaces, so
   `{ a: a j }` works, and a key that is not one grapheme at the stage is
   an error instead of never matching. Replacing only some occurrences is
   left for a second pass, after finding 2. The likely shape is an analogy
   given as a single inline Brassica rule (`rule: "a / aj / # m _"`), which
   keeps the analogical form following later sound changes without a
   second matching language. *aimerai* stays without an expectation until
   then.

5. **An ending replaced by another ending is awkward.** The OF 1pl *-ons*
   (after *sumus*) is done as `replace: { á: ó }` on the WR form. It's
   really a cell re-formed with a different affix at Old French, which runs
   into finding 2.

   **Answer.** Left with finding 2, of which it is a case.

6. **The future is built from separate affixes, not from *habēre*.**
   *cantare habeo* > *chanterai* is written with affixes FUT.1SG *-ájo* and
   FUT.3SG *-át* (Vulgar Latin, pre-stressed), with category history
   AUX > FUT. A template can't name another entry's cell, and the reduced
   *ajo* exists only from Western Romance on (an `irregular` on
   `habere.PRS.1SG`), while cells join from the forms entering a stage.
   This works, but the link to `habere` is only in prose.

   **Answer.** No change to stemma was needed. A Vulgar Latin stage
   (`latin-to-wr.bsc#1`, the loss of *h*) now sits between Latin and
   Western Romance, and *habēre*'s reduced *ájo*, *át* are `irregular`
   there. FUT.1SG and FUT.3SG are affixes formed at Vulgar Latin with
   `source: { base: habere, cell: PRS.1SG }`, so they are built from
   *ájo* and keep the AUX > FUT history. The future cells, joined at Western
   Romance from the forms entering it, pick them up. Stress stays in the
   Western Romance segment, since the cells re-formed there by `becomes`
   are joined from Vulgar Latin forms and need stressing.

7. **`on` is a boolean.** An item id `on` fails with "expected String,
   but encountered Boolean". stemma already explains this for category
   tags; ids need the same message.

   **Answer.** Every id and name (entry ids, bases, compound members,
   template slots, loan and `replaced-by` ids, `cell:`, paradigm names) is
   read by one parser that reports a boolean with "quote it".

8. **Some analogies are invisible in phonemic forms.** French 1sg *chante*
   (for OF *chant*) is re-formed at French, but both give /ʃɑ̃t/. Only the
   spelling shows it, which ties into French orthography by fiat.

   **Answer.** Left for now: it is not a bug. The general fix would be an
   orthography that spells an ancestor stage's form (historical spelling),
   which would suit English too, but words coined after that stage have
   no form there. Better decided once the full example shows how often it
   matters.

9. **Learned words can't be modelled yet.** French *fragile* (1370) beside
   inherited *frêle*, and Spanish *frágil*, are borrowings from Latin that
   need adapting. A loan `source` can't take `adapt` (a known limitation),
   and a `loan` event would replace the inherited word instead of adding a
   doublet. Learned doublets are common enough in Romance that this needs
   fixing before the full example.

   **Answer.** A loan `source` already adds a word beside the inherited
   one; it is the `loan` event that replaces. What was missing was `adapt`
   on the source, which is now there: the donor's form, from the end of
   the `from` stage (an ancestor is fine), goes through the adaptation
   rules, and the result is the word's form at its own stage. `trace`
   shows the donor's form and the adaptation's steps. The spike has
   French *fragile* and Spanish *frágil* as derivatives of `fragilis`,
   with small adaptation files (`rules/learned-*.bsc`). The French one is
   put at French for now; a Middle French stage would let it go through
   later changes.

## Data

`attested.tsv` has the forms the build must reproduce, and their sources.
`attested-notes.md` lists where sources disagree. All 140 expected
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
  (finding 4, second pass).

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
