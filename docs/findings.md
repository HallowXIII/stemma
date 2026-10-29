# Findings

From building the Romance example (`examples/romance`): 103 Latin words
traced through Vulgar Latin and Western Romance to Old Spanish, Spanish,
Old French and French, checked against 1968 attested forms. It began as a
ten-word spike (findings 1–9) and grew batch by batch (10–23). Each finding
says what was needed, what the example did instead, and what stemma did
about it. The linguistic side, from the handbooks, is in the example's
README.

## Still open

- Stress alternation in stems, and boundaries transparent to the rules
  (finding 2).
- Analogies that only the spelling shows (8), and a spelling layer for
  conservative written forms such as OSp *omne* (16).
- A reason category on `irregular` (16).
- A `clitic` property instead of the `°` notation (17).
- Events that apply after their stage's rules (22).

## The spike

1. **A cell can't be given a written stem.** Latin third-declension nouns
   have a nominative stem and an oblique one (*homō*, *homin-em*). The spike
   added the oblique stem as an item of its own (`homin`) and pointed every
   cell but NOM.SG at it with `cells: { base: homin }`. A `stem:` on a cell
   override would do. Relatedly, the entry's bare form (*homō*) keeps
   evolving as a word on lines where its cell is lost (Spanish *wémo*).

   **Answer.** A cell override takes `stem:`, a stem as written in place
   of the entry's form: `ACC.SG: { stem: "*homin-" }`. Each distinct stem
   is an internal item (like an allomorph), formed with the paradigm's
   cells and evolving as a bound root, so it never appears in the build
   products; cells with the same stem share it. It survives a `repattern`
   or `becomes`, as a suppletive base does. On an `at:` cell the stem is
   written as entering that stage, like a `repattern` stem.

   The bare form keeps evolving: for a verb with a large paradigm the stem
   is often the better thing to cite. What was missing is a choice of
   citation cell, which `cite` now gives, on a paradigm or an entry: one
   cell, `~` for the bare form, or a map from stages (`cite: { latin:
   NOM.SG, western-romance: ACC.SG }`, as the nouns and adjectives have).
   An entry's own wins over its paradigm's, the citation follows `becomes`
   and `repattern`, and the default is the first cell. It is resolved by
   stemma and written to `lexicon.json`, and Typst and `ui/` use it for the
   headword and its etymology: Spanish *ómbre* < OSp. *ómne* < Lat.
   *\*hominem*, not < OSp. *wémo*. The build warns where the cited cell has
   no form.

2. **Affixes on their own have no stress, so their reflexes can't be
   joined later.** Latin stress depends on the whole word, so a bare affix
   evolves unstressed (INF *-āre* gives Old French *-ar*, not *-er*). This
   is harmless for cells joined in Latin, but `repattern`, `becomes` after
   the first stage and `at:` cells all join from the affixes' own reflexes.

   **Answer (partial).** Much less of a problem than it looked. The Latin
   stress rules only look at the end of the word, so a bare ending whose
   first syllable is heavy is stressed on its own: INF.A gives WR *-áre*
   and Old French *-er*. Monosyllabic and light disyllabic endings are
   never stressed. So for Latin, whether an ending carries the stress is
   fixed by the ending, and its bare reflex is right in most later joins.
   Where it isn't, allomorphs cover it: INF.A has `{ before: [a], form:
   "-ər" }` at Old French for the pretonic infinitive inside the future
   (*aimerai*, finding 4). An ending that only exists later (OF *-ons*,
   finding 5) is written as an affix formed at the stage, already
   stressed.

   What remains is stress alternation in stems. A scratch run with a
   paradigm-wide `becomes` at Old French (rebuilding every verb cell from
   WR forms) got the endings right except the future's infinitive, but
   lost the apophony of *aim* ~ *amons*: the bare stem evolves unstressed.
   Allomorphs are for affixes only, and their conditions are graphemes,
   which can't say "before an unstressed ending". Today the only way is a
   `stem:` per stem-stressed cell, per entry. Re-forming single cells with
   `at:` avoids the issue, so the example does that.

   Making boundaries transparent to Brassica would help here too, since a
   joined form could keep its morphemes apart through the rules. Brassica
   1.0 has nothing built in. stemma could rewrite each parsed rule to
   allow an optional boundary between the segments it matches; the limits
   are coalescence (where the boundary should go is a policy choice),
   metathesis, and gemination and features, which read the last matched
   grapheme. A native `transparent` declaration in Brassica would be about
   150–250 lines upstream. Worth prototyping the rewrite in stemma first.

3. **Internal boundaries have to be removed in every segment.** The rules
   drop `+` inside a word, keeping the edge boundaries so that bound stems
   and affixes aren't stressed as words. A cell joined at stage S enters
   S's rules with fresh internal boundaries, so every segment started with
   the same deletion rule.

   **Answer.** `notation.internal-boundaries: false` joins parts with no
   boundary between them, and drops any inside the parts, so the rules and
   the morphophonology see a joined form as one word. The edges of a bound
   result keep theirs.

4. **`analogy` replaces every occurrence of a grapheme.** *aimerai* for OF
   *amerai* needs the stem's *a* changed but not the ending's, which
   `replace` can't express. Also, `replace: { a: a i }` silently had no
   effect, while `{ a: aj }` worked.

   **Answer.** Brassica's tokeniser read only the first word of `a i`. A
   replacement is now split on spaces, so `{ a: a j }` works, and a key
   that is not one grapheme at the stage is an error instead of never
   matching. *aimerai* turned out to be better modelled as `amare.FUT.1SG`
   re-formed at French on the stem *ajm-* (finding 1), with INF.A's Old
   French allomorph *-ər* before the future ending (finding 2). This found
   a bug: `at:` on a cell that only a later paradigm has (here FUT.1SG,
   from `becomes`) was silently ignored. It now re-forms such a cell, and
   re-forming above where the cell is joined is an error.

5. **An ending replaced by another ending is awkward.** The OF 1pl *-ons*
   (after *sumus*) was done as `replace: { á: ó }` on the WR form. It's
   really a cell re-formed with a different affix at Old French.

   **Answer.** Done as a re-forming: PRS.1PL.O is an affix formed at
   Western Romance as *-ómos*, written stressed since *\*-umus* would not
   be by the Latin rule, and the paradigms re-form PRS.1PL with it.

6. **The future is built from separate affixes, not from *habēre*.**
   *cantare habeo* > *chanterai* was written with affixes FUT.1SG *-ájo* and
   FUT.3SG *-át*. A template can't name another entry's cell, and the
   reduced *ajo* exists only from Vulgar Latin on, while cells join from
   the forms entering a stage.

   **Answer.** No change to stemma was needed. A Vulgar Latin stage now
   sits between Latin and Western Romance, and *habēre*'s reduced *ájo*,
   *át* are `irregular` there. FUT.1SG and FUT.3SG are affixes formed at
   Vulgar Latin with `source: { base: habere, cell: PRS.1SG }`, so they are
   built from *ájo* and keep the AUX > FUT history.

7. **`on` is a boolean.** An item id `on` failed with "expected String,
   but encountered Boolean".

   **Answer.** Every id and name (entry ids, bases, compound members,
   template slots, loan and `replaced-by` ids, `cell:`, paradigm names) is
   read by one parser that reports a boolean with "quote it".

8. **Some analogies are invisible in phonemic forms.** French 1sg *chante*
   (for OF *chant*) is re-formed at French, but both give /ʃɑ̃t/. Only the
   spelling shows it, which ties into French orthography by fiat.

   **Open.** Not a bug. The general fix would be an orthography that
   spells an ancestor stage's form (historical spelling), which would suit
   English too, but words coined after that stage have no form there.

9. **Learned words can't be modelled yet.** French *fragile* (1370) beside
   inherited *frêle*, and Spanish *frágil*, are borrowings from Latin that
   need adapting.

   **Answer.** A loan `source` already adds a word beside the inherited
   one; it is the `loan` event that replaces. What was missing was `adapt`
   on the source, which is now there: the donor's form, from the end of
   the `from` stage (an ancestor is fine), goes through the adaptation
   rules, and the result is the word's form at its own stage. `trace`
   shows the donor's form and the adaptation's steps. French *fragile* is
   put at French for now; a Middle French stage would let it go through
   later changes.

## Scaling up

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
    Spanish. The example used a Romance paradigm with only the accusative
    cells (`noun-o-rom`), now gone (finding 25).

    **Fixed:** a loss changes the paradigm, not just the entries that
    have it at the time. A repattern is an analogy to a more frequent
    paradigm, so the entry takes that paradigm as it is at that stage:
    the cells it has lost there or above are not joined, and are lost
    there. An entry formed below a loss gets the paradigm the same way
    (Spanish *perro*, formed at Old Spanish as an o-stem, has no
    nominative or genitive). A paradigm's `lost` also applies only where
    the paradigm is in force, so `noun-o`'s loss of the nominative at
    French no longer reaches an entry repatterned as `noun-o` on the
    Spanish line.

13. **`replace` can't change one of two equal graphemes.** OF *estoile*
    needs *\*stēla* with a single *l*, from WR *estélla*.

    **Done** (`954d17f`): an analogy can take `rule:`, an inline Brassica
    rule. *estoile* is one analogy at Gallo-Romance, `l l / l / _`.

14. **A cell couldn't be re-formed on one its stage loses.** French *prêtre*
    continues the cas sujet, so the oblique cells are re-formed at French
    on `presbyter.NOM.SG`, which French loses. The rebuild failed with
    "has no form at french".

    **Fixed** (`6e62d53`): a lost item enters the stage with its form at
    the end of the parent.

15. **An event can't come after a sound change in the same segment.**
    Semi-learned OF *pueple* keeps the *p* that Old French voicing would
    make *b*, but an analogy at Old French applies on entry, before the
    voicing.

    **Done:** `gallo-romance` and `ibero-romance` now sit above Old French
    and Old Spanish, ending after the voicing of *p t k* and after *pl-*,
    *kl-* > *ʎ-*. *pueple* and Spanish *claro* are one analogy each. See
    also finding 22.

16. **Lexical diffusion needs `irregular`.** *mn* > *mbr* had reached
    *nombre* by 1200 but not *omne*, so *omne* is two `irregular`s. That
    is honest, but the build can't tell a conservative form from an
    unexplained one.

    **Open.** A reason category on `irregular` (conservative,
    semi-learned, ...) would make the count meaningful. Lloyd has no
    phonological reason for the lag, and the likeliest one is spelling
    (*omne*, often abbreviated, as the old written form of a frequent
    word), so a spelling layer would be its proper place.

17. **Clitics need a marker.** Articles and object pronouns are
    unstressed, but the Latin stress rules would stress *illum*, *mē*. The
    example writes clitic affixes and stems with `°`, which keeps the
    stress rules off them as an edge boundary does, and Western Romance
    drops it.

    **Open.** It works, but it is notation for what is a property of the
    item: a `clitic: true` on an entry, affix or cell could add the mark
    itself.

18. **A cell can't have a stem and also be re-formed on one line.** One
    override per cell, so where a cell continues different etyma on the
    two lines (*mihi* > Spanish *mí*, *mē* > OF *moi*; *ille* > Spanish
    *el*, *illum* > OF *le*), one of them had to be the entry's form or
    the paradigm's template.

    **Done** (`095dc46`): an entry's cell can take a list of changes, as
    a paradigm's can. *esse* and *ire* need it (Spanish *sido* from
    *sedēre* beside OF *esté* from *stātum*).

19. **Plurals remade on the singular repeat.** French *chefs*, *secs*,
    *neufs* are each an `at: french` re-form of the plural on the
    singular cell, per entry, and the verbs' *-ons* and *-e* would repeat
    the same way.

    **Done** (`e6fef74`): a paradigm cell can carry `at:` re-formings, for
    every entry with the paradigm. Lexical cases like *chefs* stay on the
    entry.

20. **A cell re-formed from bare parts misses its stem's changes.** The
    Spanish 2pl *-áis* is a re-forming at Spanish, joined from the bare
    stem and a new ending. A bare stem never stood between vowels, so
    *pot-*, *vid-* stay as they are (*\*potéis*, *\*vidéis*).

    **Done** (`954d17f`): analogies can take `rule:`, and paradigms can
    list `events`. The Spanish 2pl is one event per conjugation,
    `d e s / j s / [á é] _ #`, and no verb needs its stem written out for
    it.

21. **Smaller things the verbs needed, fixed.** An entry's `at:` replaces
    the paradigm's re-forming at that stage only (`bba9a7c`); a cell the
    paradigm joins later is joined at its earliest `at:` and re-formed at
    the others (`d23d3f9`).

22. **An event sees the form entering its stage, not leaving it.** Most
    inline rules have to be written against the form before the stage's
    own rules: OSp *cadrá* inserts its *d* before *r* is a tap, OF
    *chierrai* rewrites *ka* before it is *tʃa*, *plaist* supplies the *j*
    that the stage's *ai* rule would have made.

    **Open.** It works, but the rule reads oddly; an event that applies
    after the stage's rules (`after: true`, say) would let it be written
    against the form it corrects.

23. **Some sound changes are lexical.** Spanish *veer* > *ver* but not
    *creer*; OF *plaist* but *fait*; French *mets*, *sais* /ɛ/ but *-ez*
    /e/; French *vais* takes the *ɛ* outcome of OF *oi* where most words
    have *wa*. Each is an inline-rule event on the words that have it
    rather than a rule, which is the honest model: the build can't tell
    them from regular change otherwise.

24. **A gloss was the same at every stage.** French *mais* showed as
    "more" in the French dictionary, and the example had worked around
    the single gloss with labels such as "stand; be (Spanish)" and "pot,
    shell; head (French)".

    **Done** (`8a3582a`): `gloss` can be a map from stages, in force down
    each line as a category is. *causa* is "thing", *caballus* "horse",
    *mittere* "put" from Western Romance on, and *caput* "end" in Spanish
    but "chief" in French.

25. **Case is lost by merging cells, not by losing some.** With `lost`,
    Spanish and French nouns kept the cells ACC.SG and ACC.PL after the
    loss of case, which is the etymology of most of their forms but not
    the shape of the paradigm, and French nouns that continue the
    nominative (*prêtre*, *sœur*, *on*) had to re-form their accusative
    cells on it.

    **Done:** a cell of a paradigm an entry changes to `continues` a
    cell of the old one, taking its form as it is; an entry can name
    another cell to continue (on one line, with `at:`), or add a variant
    continuing one. The example's nouns and adjectives become `noun-rom`
    and `adj-rom` in Spanish and French, *prêtre* continues the
    nominative, and the `noun-o-rom` and `noun-c-rom` workarounds are
    gone. Every form is the same as before; *corpus*, *tempus* and
    *nomen*, remade at Ibero-Romance, now have that stage's nominative
    too.

    Making this work needed a cell to be joined on each line where a
    paradigm gives it (the singular is new at Old Spanish and at French),
    `becomes` to follow the paradigm in force (an entry repatterned as
    `noun-o` gets its `becomes`), and an entry's changes to its old cells
    not to add them to the new paradigm.

## Brassica

- In Brassica 1.0, `a / b / env1 / env2` gives two environments; an
  exception needs `//`. A single `/` before an exception silently adds the
  exception as an environment, which first stressed every final vowel.
- A deletion needs an environment: `h / / _`, not `h / /`.
- At a `categories` block, graphemes not declared become U+FFFD. Latin
  forms written with *c* or *v* instead of *k*, *w* lost letters this way.
- Graphemes that only rules make (WR *ð*, Spanish *θ ʝ x*, French *ɥ*)
  were in no `categories` block, which the inventory check (roadmap §E)
  found. They are now declared in a category, `Made`, that no rule uses.
  Brassica's `extra` would be the natural way, but in a file with
  categories, 1.0 turns it into a grapheme list of its own: `noCategories`
  in `expandSoundChanges` is true when there *are* categories. stemma then
  tokenised with that list alone, which lost `+` and *ɛ́*.

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
