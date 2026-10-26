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

   **Answer (partial).** Much less of a problem than it looked. The Latin
   stress rules only look at the end of the word, so a bare ending whose
   first syllable is heavy is stressed on its own: INF.A gives WR *-áre*
   and Old French *-er*. Monosyllabic and light disyllabic endings are
   never stressed. So for Latin, whether an ending carries the stress
   is fixed by the ending, and its bare reflex is right in most later
   joins. Where it isn't, the allomorphs feature written for Echo covers
   it: INF.A has `{ before: [a], form: "-ər" }` at Old French for the
   pretonic infinitive inside the future (*aimerai*, finding 4). An
   ending that only exists later (OF *-ons*, finding 5) is written as an
   affix formed at the stage, already stressed.

   What remains is stress alternation in stems. A scratch run with a
   paradigm-wide `becomes` at Old French (rebuilding every verb cell
   from WR forms) got the endings right except the future's infinitive,
   which a WR allomorph `{ before: [á], form: "-are" }` would fix, but
   lost the apophony of *aim* ~ *amons*: the bare stem evolves
   unstressed. Allomorphs are for affixes only, and their conditions are
   graphemes, which can't say "before an unstressed ending" (2SG *-əs*
   and the future's *-ər-* both start with *ə*). Today the only way is a
   `stem:` per stem-stressed cell, per entry. Re-forming single cells
   with `at:` avoids the issue, so the spike does that.

   Making boundaries transparent to Brassica would help here too, since
   a joined form could keep its morphemes apart through the rules. Brassica
   1.0 has nothing built in. stemma could rewrite each parsed rule to
   allow an optional boundary between the segments it matches; the limits
   are coalescence (where the boundary should go is a policy choice),
   metathesis, and gemination and features, which read the last matched
   grapheme. A native `transparent` declaration in Brassica would be about
   150-250 lines upstream. Worth prototyping the rewrite in stemma first.

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

   *Second pass:* done as the better model after all. *aimerai* is
   `amare.FUT.1SG` re-formed at French on the stem *ajm-* (finding 1), with
   INF.A's Old French allomorph *-ər* before the future ending (finding 2).
   This found a bug: `at:` on a cell that only a later paradigm has (here
   FUT.1SG, from `becomes`) was silently ignored. It now re-forms such a
   cell, and re-forming above where the cell is joined is an error. The
   French rules also had schwa loss before *ai* > *e*, the wrong way round;
   reordered, the build gives *emʁe*, now expected and in `attested.tsv`.
   No inline-rule analogy was needed.

5. **An ending replaced by another ending is awkward.** The OF 1pl *-ons*
   (after *sumus*) is done as `replace: { á: ó }` on the WR form. It's
   really a cell re-formed with a different affix at Old French, which runs
   into finding 2.

   **Answer.** Done as a re-forming: PRS.1PL.O is an affix formed at
   Western Romance as *-ómos*, written stressed since *\*-umus* would not
   be by the Latin rule, and `cantare` and `amare` re-form PRS.1PL with it
   at Old French. The `á: ó` analogies are gone.

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

## Scaling up

Found while building the full word list, batch by batch.

10. **Cells two repatterns add were joined at the wrong one.** *corpus*
    `becomes` invariable at Western Romance (OF *cors* in every cell) and
    is remade as an o-stem by its own `repattern` at Old Spanish
    (*cuerpo*). The plural cells, which both add, were joined at Old
    Spanish, since the entry's own repatterns came first, so French had
    none.

    **Fixed** (`190e29e`): repatterns are taken nearest the root first.

11. **An analogy without `cell:` changed only the bare entry.** The schema
    implied it would change every cell, which is what a word-wide analogy
    wants (OF *pueple*, *escole*; French *loup*, *roue*).

    **Fixed** (`9567c98`): it now reaches every cell.

12. **A `repattern` brings back cells lost earlier.** Remaking *corpus* as
    `noun-o` at Old Spanish joined its genitive and nominative cells
    there, although `noun-o` loses them at Western Romance and Old
    Spanish. The example uses a Romance paradigm with only the accusative
    cells (`noun-o-rom`). Whether a repattern should honour `lost` above
    its stage is a design question.

13. **`replace` can't change one of two equal graphemes.** OF *estoile*
    needs *\*stēla* with a single *l*, from WR *estélla*; deleting one *l*
    isn't expressible, so the four Old French cells are `irregular`. The
    inline-rule analogy from finding 4 would do it in one event.

    **Done** (`954d17f`): an analogy can take `rule:`. *estoile* is one
    analogy at Gallo-Romance, `l l / l / _`.

14. **A cell couldn't be re-formed on one its stage loses.** French *prêtre*
    continues the cas sujet, so the oblique cells are re-formed at French
    on `presbyter.NOM.SG`, which French loses. The rebuild failed with
    "has no form at french".

    **Fixed** (`6e62d53`): a lost item enters the stage with its form at
    the end of the parent.

15. **An event can't come after a sound change in the same segment.**
    Semi-learned OF *pueple* keeps the *p* that Old French voicing would
    make *b*. An analogy at Old French applies on entry, before the
    voicing, so the four cells are `irregular`. A Gallo-Romance stage
    between Western Romance and Old French, after the voicing, would let
    one `analogy` do it, and probably *estoile* (finding 13) too. Worth
    adding once more such words show up.

    **Done**: `gallo-romance` and `ibero-romance` now sit above Old French
    and Old Spanish, ending after the voicing of *p t k* and after *pl-*,
    *kl-* > *ʎ-*. *pueple* and Spanish *claro* are one analogy each.
    *estoile* is not helped: it needs one of two *l*s removed, which
    `replace` can't say at any stage (finding 13).

16. **Lexical diffusion needs `irregular`.** *mn* > *mbr* had reached
    *nombre* by 1200 but not *omne*, so the rule is in both Spanish
    segments and *omne* is two `irregular`s. That is honest, but the
    build can't tell a conservative form from an unexplained one; a
    reason category on `irregular` (conservative, semi-learned, ...)
    would make the count meaningful.

17. **Clitics need a marker.** Articles and object pronouns are
    unstressed, but the Latin stress rules would stress *illum*, *mē*. The
    example writes clitic affixes and stems with `°`, which keeps the
    stress rules off them as an edge boundary does, and Western Romance
    drops it. It works, but it is notation for what is a property of the
    item: a `clitic: true` on an entry, affix or cell could add the mark
    itself.

18. **A cell can't have a stem and also be re-formed on one line.** One
    override per cell, so where a cell continues different etyma on the
    two lines (*mihi* > Spanish *mí*, *mē* > OF *moi*; *ille* > Spanish
    *el*, *illum* > OF *le*), one of them has to be the entry's form or
    the paradigm's template. *nomen* (finding 12) and *ego* are shaped
    by this. Overrides keyed by line, or a list of `at:` re-formings per
    cell, would lift it.

    **Done** (`095dc46`): an entry's cell can take a list of changes, as
    a paradigm's can. *esse* and *ire* need it (Spanish *sido* from
    *sedēre* beside OF *esté* from *stātum*), and it replaced four
    `replace` analogies in the verbs.

19. **Plurals remade on the singular repeat.** French *chefs*, *secs*,
    *neufs* are each an `at: french` re-form of the plural on the
    singular cell, per entry. With the verbs' *-ons* and *-e* still to
    come, a paradigm-level `at:` cell (or a `becomes` that re-forms only
    named cells) looks worth having.

    **Done** (`e6fef74`): a paradigm cell can carry `at:` re-formings, for
    every entry with the paradigm. Lexical cases like *chefs* stay on the
    entry.

    Of the 24 `irregular`s after batch 3, 12 were three semi-learned or
    dialectal words (*estoile*, *pueple*, *claro*); with the intermediate
    stages there are 16, four of them *estoile*.

20. **A cell re-formed from bare parts misses its stem's changes.** The
    Spanish 2pl *-áis* is a re-forming at Spanish, joined from the bare
    stem and a new ending. A bare stem never stood between vowels, so
    *pot-*, *vid-* stay as they are (*\*potéis*, *\*vidéis*), and the verbs
    whose stem changed need a re-forming of their own with the stem
    written out (*pod-*, *ve-*; also *sedere*'s *seð-*). What is wanted is
    a sound change confined to some cells: an analogy given as an inline
    Brassica rule (finding 4), which a paradigm could declare as well as
    an entry, would do the 2pl for every verb as `d e s / j s / _ #`, and
    *estoile* too.

    **Done** (`954d17f`): analogies can take `rule:`, and paradigms can
    list `events`. The Spanish 2pl is one event per conjugation, and no
    verb needs its stem written out for it. `irregular` count: 39.

21. **Smaller things the verbs needed, fixed.** An entry's `at:` replaces
    the paradigm's re-forming at that stage only (`bba9a7c`); a cell the
    paradigm joins later is joined at its earliest `at:` and re-formed at
    the others (`d23d3f9`).

    `irregular` count: 43. The verbs added 27, nearly all strong perfects
    (*tovo*, *tint*, *fist*, *estut*) and the allegro forms of *facere*,
    *dicere*, *esse* (*fémos*, *dimes*, *somes*), which the handbooks also
    treat word by word.

22. **An event sees the form entering its stage, not leaving it.** Most of
    the inline rules in batch 5 had to be written against the form before
    the stage's own rules: OSp *cadrá* inserts its *d* before *r* is a tap,
    OF *chierrai* rewrites *ka* before it is *tʃa*, *plaist* supplies the
    *j* that the stage's *ai* rule would have made. It works, but the rule
    reads oddly; an event that applies after the stage's rules (`after:
    true`, say) would let it be written against the form it corrects.

23. **Some sound changes are lexical.** Spanish *veer* > *ver* but not
    *creer*; *lees* lost its *j*, *reyes* didn't; OF *plaist* but *fait*;
    French *mets*, *sais* /ɛ/ but *-ez* /e/. Each is an inline-rule event on
    the words that have it rather than a rule, which is the honest model:
    the build can't tell them from regular change otherwise.

    `irregular` count after batch 5: 52. The 13 added are again strong
    perfects (*crut*, *but*, *lut*, *chut*, *sot*, *plot*) and a few forms
    of defective verbs.

    **Handbook pass, the u-perfects** (Pope): stem-stressed *hábuit*,
    *sápuit*, *plácuit*, *pótuit*, *\*crḗduit*, *\*bíbuit*, *\*lḗguit*
    are regular now. *u* in hiatus becomes *w* in Western Romance; C + *w*
    > *ww* in Gallo-Romance (Pope *awwet*, *krịwwịt*), close *ẹ* > *ị*
    before it, and *ịww* > *y*, *a*/*ǫ* + *ww* > *ɔ* in Old French (*crut*,
    *but*, *lut*; *ot*, *sot*, *plot*, *pot*); in Spanish the *w* moves
    into the stem (*ovo*, *sopo*, *plogo*). *morī* has the stress on the
    ending (*\*morū́it*), which kept its *u* (*morut*). *chut* and *estut*
    are re-formed after *crut*, *but*, and French *eut*, *sut*, *put*,
    *plut* remake Pope's type A on the other u-perfects: analogies, not
    `irregular`. The Old French rows without *-t* were normalised to it,
    since the *t* follows *ww*. *morut* stays */mory/*: its *t* followed a
    vowel, and Pope's paradigm has none for it where the other u-perfects
    have one. `irregular` count: 40.

    **Handbook pass, the allegro forms** (Pope): OF *faimes*, *dimes*,
    *faites*, *dites* are the regular reflexes of *facimus*, *dicimus*,
    *-itis*, the last survivors before *-ons* (from *sons* < *sumus*) and
    *-ez* spread; those two verbs now keep their Latin 1pl and 2pl in
    Gallo-Romance. *fist* and *tint* take the vowel of the 1sg, which has
    umlaut (*fēcī* > *fis*; *teneō* > *teniō*, *tēnī* > *tin*): analogies
    now. `irregular` count: 34.

    *esse* (Pope): *sumus* gives the regular *sons*, the source of *-ons*;
    *somes* is the alternative form, like *faimes*, and French settled on
    *-ons* but *sommes*. *estes* is regular, as *faites*, *dites*. French
    *es* continues the unstressed OF *ẹs*. *sui* stays `irregular`: Pope
    has it influenced by *fui* but not fully explained. `irregular` count:
    31.

    **Spanish strong perfects** (Penny): the *w* of *-uī* moves into the
    preceding syllable and *aŭ* > *o* (*habuī* > *ove*), as the rules
    already had it. *tovo* follows the pattern of *ove* rather than
    *tenuī*; *pudo* takes the *u* of 1sg *pude*, where *ō* was raised by
    the glide and *-ī* together; Spanish *estuvo* follows *tuve*,
    *anduve*. All three are analogies now. `irregular` count: 28.

## Data

`attested.tsv` has the forms the build must reproduce, and their sources.
`research/*-notes.md` list where sources disagree. All of its forms for
the words built so far are reproduced (`./check.sh`). The main judgement
calls:

- **Tooling.** `research/refresh-expect.sh` silently dropped hand-written
  `expect:` blocks of words whose forms are filed under another word
  (*perro*, *capitia*) from batch 2 on; it now keeps them, and they are
  restored. *esse* and *ire*'s suppletive cells have their own `kind`.

- **Sources.** The research couldn't reach Pope, Penny, Lloyd or Einhorn.
  It used Nyrop, Bourciez, Darmesteter, Menéndez Pidal (*Manual*, *Cid*)
  and Wiktionary. The full example needs a pass with the standard
  handbooks.
- **Dating.** Old French at 1150 sits on several changes: *ei* > *oi* (taken
  as done: *avojr*), *ai* > *ɛ* (taken as not yet: *aj*), and the loss of 3sg
  *-t* (taken as gone: *tʃantə*). Checked against Pope: final *t* was a
  dental fricative before the end of the first millennium and gone by 1150,
  and *ei* > *oi* belongs to the 11th century, so both choices stand.
  *ai* > *ɛ* is still unchecked.
- **Rules.** Old French diphthongises before nasals (*cuens* < *comes*), so
  *om*, *ome* and Castilian *omne* are an "unstressed use" analogy on
  *homo* (the spike blocked the diphthong instead, which *cuens* rules
  out). Old French has its syncope before the voicing of *p t k* (*conte*,
  *doit*, *cité*), Spanish after it (*conde*), so the voicing is in each
  branch, not Western Romance. Two rows were corrected for consistency:
  OF *doit* (with *t*, as *nuit*) and *prestre* (with *ɛ*, as *terre*).

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
