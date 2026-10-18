# Findings

From building this project: 6 nouns, 4 adjectives, 7 proper nouns, the
personal and copulative pronouns, the demonstratives, and 6 verbs: 771 items
in all, most of them paradigm cells. Every form the grammar quotes is an `expect`. The build
reproduces all of them. It also flagged two typos in the grammar's tables
(*daumāšti*, *niberši*), since corrected to *daumašti* and *nibešši*.

## 1. Missing in stemma, by how much it hurt

1. **Paradigm cells cannot take prefixes.** A cell is always
   `base ++ affixes`. Azal verbs (subject and object prefixes) and possessed
   nouns need prefixes, so every verb form is a hand-written compound
   derivative. `verbs.yaml` has 60 of them for six verbs. A cell template
   with a base slot would fix this, e.g. `[SBJ.1S, ~, S.1S]`, or a
   `prefix: true` on affixes.
2. **No paradigm dimensions or inheritance.** The noun paradigm is 25 cells
   listed by hand, twice: `noun-v` and `noun-c` differ in only 5 cells. A
   full Azal verb paradigm (person × object × mood × tense) would run to
   hundreds of cells. This calls for products of dimensions
   (`number × case`) with per-cell overrides, or `extends: noun-v` plus
   overrides.
3. **No morpheme boundaries.** I wrote `+` into every affix by hand. Hiatus,
   umlaut, r > n before /i/, and past -va > -u must apply only across a
   boundary, or they would hit root-internal sequences (*tennaira*'s
   /ai/, *yagištut*'s /a-gi/). stemma could insert a configurable boundary
   symbol at concatenation time.
4. **Bound roots are evolved as words.** Bare verb roots get word-final rules
   and become dictionary headwords: *beš* "see" (for *ber-*), *bolet*
   "become", *gišet* "hit", *gatet* "cause". Bare affixes give *ːn* and the
   like. Entries need a way to say they are bound (`bound: true`), or a
   citation form such as *ber-*.
5. **Undeclared graphemes are destroyed silently.** At a `categories` block,
   Brassica replaces every grapheme that is not declared with U+FFFD. My
   first `+` vanished this way, with no warning from stemma. stemma should
   warn when an output contains U+FFFD.
5a. **Unspaced replacements create invisible multigraphs.** In Brassica,
   `x r / xx` outputs one grapheme `xx`, not two `x`s, so a later `x x / h h`
   never matches. The form *looks* right (*azaxxassa*), and nothing warns.
   stemma could warn when a rule outputs a grapheme that isn't in the
   declared inventory.
6. **Inflected forms clutter the dictionary.** Because of (1), every verb form
   (*biberen*, *bibervan*, …) is a headword with no gloss or category.
   Derivatives also don't inherit their parent's category or stage, so every
   verb form repeats `stage: old-azal`.
7. **No rule includes or tables.** The hiatus table (100 cells) and the
   cluster grid (400 cells) are spliced into the `.bsc` between markers by
   `tools/gen-tables.py`. An `include`, or stemma-level table rules read from
   data, would make this unnecessary.
8. **No suppletion.** 1sg direct *yēni* comes from a different root, but the
   only way to record it is `irregular`. Something like
   `suppletive: {cell: DIR, from: ITEM}` would keep the link.
9. **No variants within a cell.** The archaic nonpast (*biberne*) is a
   separate set of derivatives. There's no way to say a cell has a modern and
   an archaic form, or that some speakers use -š for the 3pl.
10. **Expectations can't be marked as disputed.** A form the grammar quotes
    but which may be a typo keeps the build failing until it's resolved. An
    `xfail`/`disputed` marker on an expectation would help.
11. **No phonotactic checks.** The grid's ✗ cells can't be asserted. A
    `forbid:` list of patterns that warns when one appears in output would
    have caught *ešvyō* (§3).
12. **No paradigm change at a stage.** In Azal, the *-ō* of *-xax*
    derivatives (*-hō*) spreads through the paradigm, and they come to
    inflect like vowel stems but without the direct *-n*: a new stem class.
    A noun built as `noun-c` at Proto-Echo can't switch to that class at
    `azal`. An `analogy` only swaps single graphemes, an event without
    `cell:` doesn't reach the cells, and `reform` rebuilds from the same
    paradigm. An event such as `repattern: { at: azal, paradigm: noun-o,
    stem: "valykkō" }` would do it: rebuild every cell at that stage from a
    new stem and paradigm. Until then, *valykkōm* (`sharpness.SG.COM`)
    fails.

## 2. Smaller things

- `stemma.typ` has no paradigm-table helper. `demo.typ` builds one from the
  cell-naming convention.
- The dictionary sorts by code point: *dān* and *dāš* come after *daum*. This
  needs a collation order, e.g. an alphabet in `family.yaml`.
- Proper nouns can't be capitalised: *ešven* for *Ešven*.
- `stemma.typ` is not a Typst package. Importing it from another directory
  needs `--root ~`.
- `trace` prints phonemic forms run together, so *ny*+*j* shows as *nyj*. For
  generated rows it prints the whole row rather than the element that matched.
- The first build says "no forms changed" when there was no previous build.
- `shifts` doesn't see conversion. *might-be* (PROPN) is a derivative of
  *summery* (ADJ), so the change of category is invisible.