# stemma roadmap

Planned work, from the findings of the Azal/Wiyan grammar project
(`FINDINGS.md`; numbers below refer to its sections). Effort is a rough
estimate including tests and docs: **S** is two hours or less, **M** half
a day to a day, **L** one to three days.

Things caused by Brassica itself are out of scope, except where stemma can
cheaply detect them (§E).

---

## A. Cell templates and morpheme boundaries: L

**Done**; see `schema.md` §2 and `test/fixtures/boundary`.

Covers findings 1, 3 and 4, and the "bare affixes" known limitation in
`schema.md`.

A cell is always `base ++ affixes` today (`SMorph` in `buildFrom`). Instead,
a cell is an ordered template with a base slot:

```yaml
- 1S.PST: [SBJ.1S, ~, PST]
```

With no `~`, the base comes first, so existing paradigms are unchanged.
Derivatives' `morph:` takes the same template, so prefixing derivations work
too.

**Boundaries.** Authors already mark attachment with `-` (`*-i`, `*ir₁-`),
which is currently stripped. With an opt-in `notation.boundary: "+"` in
`family.yaml`, `-` becomes the boundary symbol instead:

- Affixes and bound roots evolve as `+i` and `ber+`, so word-final rules no
  longer reach them (no more *beš* for *ber-*, or *heh* for *\*-xx*).
- Concatenation puts a single boundary between parts. Boundaries at the
  edges are dropped unless the result is itself bound.
- Spelled forms and expectations have boundaries stripped. A citation form
  like *ber-* falls out of the edge boundary.

Rules that should apply across a boundary must allow for `+`, as they do now
with hand-written boundaries.

**Bound entries.** `bound: true` on an entry (implied for affixes), written to
`lexicon.json`. `dictionary()` gets an option to omit bound entries or cite
them with the hyphen.

## B. Paradigm dimensions and inheritance: L

**Done**; see `schema.md` §2 and `test/fixtures/paradigms`.

Covers finding 2, most of finding 6, and the Typst paradigm-table helper.

- `extends: noun-v` plus overriding cells.
- `dimensions:` builds cells as a product (`number × case` gives `SG.DIR`,
  ...), with per-cell overrides.
- Templates (§A) can name dimensions in order, e.g.
  `[subject, ~, object, tense]`, which keeps a full verb paradigm short.

All of this is expanded when the project loads. The build itself is
unchanged.

The dimension structure is written to `lexicon.json`, so a
`paradigm-table` helper in `stemma.typ` can lay out rows and columns without
relying on cell-naming conventions.

Finding 6 is largely solved once verb forms are cells: cells already
inherit their entry's category, and the paradigm's `stage:` replaces
repeating it per form. Separately (**S**): derivatives with no `category`
inherit their parent's.

## C. Per-entry cell overrides: M, after A and B

**Done**; see `schema.md` §2–3 and `test/fixtures/cells`.

Covers findings 8 and 9.

- **Suppletion:** `cells: { DIR: { base: yen } }` replaces the base for one
  cell. The link is a real dependency, so it appears in the etymology and is
  validated like any other.
- **Variants:** labelled extra cells such as `NPST~archaic`, marked as
  variants of `NPST`, each evolving independently. The core is **S**; most of
  the effort is displaying them in Typst.

## D. `repattern`: M, after B

**Done**; see `schema.md` §4 and `test/fixtures/repattern`.

Covers finding 12.

```yaml
- repattern: { at: azal, paradigm: noun-o, stem: "valykkō" }
```

This is `reform` for cells: at that stage every cell is rebuilt from the
stem and the new paradigm's affixes, taken from the forms entering the
stage (as `reform` already does). Cells the new paradigm lacks become lost.
The new paradigm may also add cells, which are joined at that stage.

## E. Stage output checks: M

**Done** except categories in `forbid:`; see `schema.md` §1, "Checks on
a stage's forms".

Covers findings 5, 5a and 11. The causes of 5 and 5a are in Brassica, but
stemma can detect them. One pass after each stage:

- warn on U+FFFD in any output (5);
- warn on output graphemes outside the stage's declared inventory (5a);
- warn on `forbid:` patterns (11), grapheme sequences with `#` for a word
  edge. A literal-sequence version is **S**; supporting Brassica categories
  (`[C] [C] [C]`) costs more;
- check that the boundary symbol (§A) is declared at every stage.

## F. Standalone items

| finding | change | effort |
|---|---|---|
| §2 | `shifts` across derivation: a derivative with no affix (`source: { base }` or `{ base, cell }`) starts from its base's category where it was formed, so conversion (*might-be* ADJ > PROPN) and new roles of a form (*habēre* AUX > FUT) are found. Affixal derivation is not a shift. **Done**; see `schema.md` §3. | S |
| — | Category-assigning affixes: an affix's `category` is the default for derivatives formed with it, since most derivation changes category. A template's last such affix decides. **Done** as `derives`; see `schema.md` §2. | S |
| §2 | Collation: `alphabet:` per stage, with a sort key written to `lexicon.json`. **Done**; see `schema.md` §1. | S |
| §2 | `stemma.typ` as a Typst package. **Done** as `stemma typst --package`, which installs it where Typst looks for local packages; see `schema.md` §8. (A copy under the flake's `share/` would not be found: Typst reads only its own data directory, or `TYPST_PACKAGE_PATH` in its place.) | S |

**Declined.**

- Disputed expectations (10). A form that may be wrong in its source can
  be left out of `expect` and discussed in `notes`. A form that was written
  by hand and contradicts the build calls for fixing the grammar or the
  rules, not for silencing the mismatch.
- Grapheme separators in `trace` (§2). An invisible multigraph is caught on
  every build by the inventory check (§E), and a rule that merges
  graphemes already has its own step in the trace. A trace showing a whole
  generated row instead of the element that matched is a sign that the
  rule should be split into one line per change, as it would be by hand.
- Rule includes (7). Their use was to keep generated tables in a file of
  their own; such tables are better written as rules, one change per line,
  and `report` segments already divide a long file.

---

## Order

1. Quick wins: §E without categories.
2. §A, opt-in so the Echo example passes unchanged.
3. §B, then §C, rewriting the Azal `verbs.yaml` from derivatives into a
   paradigm as the real-world test.
4. §D, which makes *valykkōm* (`sharpness.SG.COM`) pass.
5. The rest of §F, in any order.

Bound roots are listed in the dictionary by default, cited as *ber-*;
`dictionary(stage, bound: false)` leaves them out.

---

## G. Orthography: an epic of its own

Not planned yet. Today an orthography is a rules file from a stage's
phonemic forms to its spelling. Anything beyond that raises the same
question, which needs a design before any one part is built: what a
spelling is derived from, if not the stage's own form.

- **Conservative spelling.** French *chante* and OSp *omne* (findings 8
  and 16) are spelled after an older stage. A spelling that follows an
  ancestor's form has no form to follow for words coined after it.
- **Scripts.** An in-world script raises the same problem. In the Azal and
  Wiyan abugida, Azal *dalgāye ōyil šaman* is written <dlgāye ōyŕ čmn>, and
  Wiyan *zalahaiči ūyir čama* is written <dlgāy ki ōyŕ čmn>: the spelling
  keeps a shape the sound changes have left behind, and is nearly the same
  in both languages.
- **Capitalisation** (Azal §2: *ešven* for *Ešven*). `capitalise: [PROPN]`
  by the category at each stage, capitalising a whole multigraph (*Ny*).
  It is small, but it belongs with the rest: whether a script has case at
  all, and on which form it applies, are spelling questions.

## Later

Ideas worth having eventually, but not needed by the Azal project yet.

**Suppletion across a slice of the paradigm.** Suppletion (§C) changes one
cell at a time, so a stem used in a whole slice of the paradigm (Latin
*ferō – tulī*: every perfect form on *tul-*) needs one override per cell.
Two designs:

1. Patterns in an entry's `cells`: `PST.*: { base: tul }` changes every
   matching cell, using the same `*` matching as `shifts`. **S**.
2. Stem slots, like principal parts: a dimension member names a stem
   (`PST: { stem: perfect, affixes: PST }`), and each entry supplies it
   (`stems: { perfect: tul }`), defaulting to the entry itself. Closer to
   how grammars describe such verbs, but more machinery. **M**.

Option 1 is the cheaper first step and doesn't rule out option 2 later.

**A separate compound boundary.** With `notation.boundary`, compound
members are joined with the same symbol as affixes. Rules that need to
tell the two apart would need a second symbol (`compound-boundary`).

**Stemma-level rule tables.** Generating rules such as the hiatus table
and cluster grid from data, instead of including a generated file (§F).
