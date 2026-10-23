# stemma schema

All files are YAML. IDs are short slugs, unique across the whole project.

> **Quoting.** YAML reads a bare `N`, `Y`, `no`, `off` and so on as booleans.
> Quote category tags like these: `is: "N"`. stemma reports an error if you
> forget.

---

## 1. `family.yaml`: languages and stages

A family is a tree of **stages**. Each stage names its parent and the rules
that turn the parent's forms into its own. A "language" is just a stage
marked `current`.

```yaml
name: Echo

notation:
  graphemes: [r₁, r₂]      # multigraphs in proto forms (optional)
  boundary: "+"            # morpheme boundary passed to the rules (optional; §2)

stages:
  proto-echo:
    name: Proto-Echo
    abbr: PE               # used in etymologies
    morphophonology: rules/pe-morph.bsc   # optional: for built forms (§2)

  old-azal:
    name: Old Azal
    parent: proto-echo
    rules: "rules/pe-to-azal.bsc#1"

  azal:
    name: Azal
    parent: old-azal
    rules: "rules/pe-to-azal.bsc#2"
    orthography: rules/azal-ortho.bsc   # optional: phonemic > spelling
    current: true

  wiyan:
    name: Wiyan
    parent: proto-echo
    current: true          # no rules yet: forms are copied, with a warning
```

### Stages are breakpoints in a rules file

`file.bsc#N` means the Nth **segment** of the file. Segments are the
stretches between Brassica `report` statements. So one file per line of
descent is usually enough: put a `report` wherever you want to be able to
insert events, and give each segment a stage. A reference without `#N` uses
the whole file.

Categories behave as they do when Brassica runs the file in one go: a
category block defined in segment 1 is still in force in segment 2.

Adding a stage later is cheap. Insert a `report`, renumber the segments in
`family.yaml`, and re-point any events that belong to the new stage.

---

## 2. `morphology.yaml`: affixes and paradigms

Morphology builds forms by concatenation. Allomorphy that arises from
sound change is left to the rules; what happens when the parts are put
together, such as epenthesis, can go in a stage's morphophonology (below).

```yaml
affixes:
  DIR.C: { form: "" }         # zero affix
  GEN:   { form: "*-i" }
  DAT:   { form: "*-xx" }

paradigms:
  demonstrative:
    stage: proto-echo         # optional; default: the root stage
    cells:                    # a list, so the order is kept
      - DIR: DIR.C
      - GEN: GEN
      - DAT: [DAT]            # a cell may stack several affixes
```

A cell is a **template**: affixes in order, with `~` for the base. Without
a `~` the base comes first, so `[GEN]` means `[~, GEN]`. A cell written as
just `~` is the bare base.

```yaml
affixes:
  SBJ.1S: { form: "*bi-" }    # a prefix
  PST:    { form: "*-va" }

paradigms:
  verb:
    cells:
      - INF: ~
      - 1S.PST: [SBJ.1S, ~, PST]
```

Affixes take the same fields as entries (§3) and default to the root
stage. They are items in their own right, so they can have category
history and notes, which is how you record things like a definite article
becoming a case ending.

An entry with `paradigm: demonstrative` gets one item per cell, named
`entry.CELL` (e.g. `ir.DIR`). Each cell is built at the paradigm's stage
(or at the entry's, if that is later) and then evolves on its own.

### Dimensions

Rather than listing every cell, a paradigm can give its **dimensions**.
Its cells are then every combination of their members, named by joining
the members with `.`. The first dimension varies slowest.

```yaml
paradigms:
  noun-v:
    dimensions:
      - number: [SG: ~, PL: PL]          # ~: the member adds nothing
      - case: [DIR: DIR.V, GEN: GEN, COM: COM]
    # cells: SG.DIR, SG.GEN, SG.COM, PL.DIR, PL.GEN, PL.COM
```

Each member adds its affixes (one, a list, or none) at its dimension's
place in the `template`. By default the template is the base followed by
the dimensions in order. A template names the dimensions, and can also
hold `~` and fixed affixes:

```yaml
  verb:
    dimensions:
      - person: [1S: SBJ.1S, 2S: SBJ.2S]
      - tense: [PRS: ~, PST: PST]
    template: [person, ~, tense]         # 1S.PST is SBJ.1S + base + PST
```

With dimensions, `cells` overrides cells by name, keeping their place, or
adds new ones at the end. `exclude` removes cells.

**Inheritance.** `extends: P` starts from paradigm P: its stage, dimensions,
template, cells and exclusions. A dimension with the same name as an
inherited one replaces or adds members. A new dimension is added after the
inherited ones. Cells and exclusions are added to the inherited ones.

```yaml
  noun-c:
    extends: noun-v
    dimensions:
      - case: [DIR: ~]                   # no direct -n
    cells:
      - PL.GEN: [~, PL, GEN.C]
    exclude: [PL.COM]
```

**Loss on one line.** `exclude` removes a cell everywhere. `lost` removes it
from a stage on, so other lines of descent keep it. Cell names may use `*`,
and a cell's variants are lost with it. Every entry with the paradigm gets
the cell fate `lost` at that stage (§5), so would-be forms are still
computed. `lost` is inherited and merged like `exclude`.

```yaml
  noun-v:
    lost:
      wiyan: ["*.GEN"]                   # Wiyan drops the genitive
```

The dimensions are written to `lexicon.json`. In Typst,
`paradigm(id, stage)` lays the cells out as a table, with one row per member
of the last dimension (or of `rows: "number"`) and a column for each
combination of the others.

### Variants

A cell named `CELL~label` is a variant of `CELL`: a second form for the
same slot, such as an archaic or dialectal one. It is an item of its own
(`ber.NPST.1S~archaic`) and evolves independently. Its main cell must
exist.

A dimension member can be a variant too. It then gives a variant of every
cell with the main member:

```yaml
  verb:
    dimensions:
      - tense: [NPST: NPST, NPST~archaic: NPST.ARCH, PST: PST]
      - person: [1S: SBJ.1S, 3P: SBJ.3P]
    # NPST.1S, NPST.3P, NPST.1S~archaic, NPST.3P~archaic, PST.1S, PST.3P
```

Variants can also be added through `cells`, in a paradigm or for one entry
(§3). In `lexicon.json` a variant has `variant_of` and `variant`; Typst's
`paradigm()` shows variants under their main cell.

### Morpheme boundaries

By default, parts are simply concatenated and a `-` in a written form is
ignored. Set `notation.boundary` in `family.yaml` to pass morpheme
boundaries to the rules instead:

- Every `-` in a written form becomes the boundary symbol. The affix
  `*-i` evolves as `+i`, and the bound root `*ber-` as `ber+`, so a rule
  conditioned on the end of the word (`_ #`) does not reach them.
- When a cell or derivative is built, its parts are joined with exactly one
  boundary between them, and zero affixes add nothing: `bi+`, `ber+` and
  `+va` give `bi+ber+va`. The boundaries at the outer edges are dropped,
  unless the result is itself `bound` (§3).
- The boundaries stay in the forms from stage to stage, so later rules can
  refer to them: `r / n / _ + i` changes *kar+i* but not *kari*.
- Displayed and spelled forms leave out the boundaries inside the word and
  show those at its edges as hyphens: *mibedva*, but *ber-* and *-va*.
  `trace` and `forms.tsv` show the raw forms. The orthography never sees
  boundaries.

The boundary must be declared as a grapheme in every rules file that has a
`categories` block, or Brassica replaces it with U+FFFD. stemma warns when
it is not. In a category, a leading `+` means intersection, so declare it
as a union: `B = &+`.

Rules that should apply across a boundary have to allow for it, for
example with an optional `(+)`.

### Morphophonology

A stage's `morphophonology` (in `family.yaml`) is a rules file for forms
**joined from parts**: cells and derivatives. Written forms, of roots and
affixes, never go through it. This is where an alternation that belongs to
the word rather than the root goes, such as an epenthetic vowel in the bare
form of a root ending in a cluster:

```yaml
- id: ash
  form: "*əčw"          # the root: ash.GEN is *əčw-i
  paradigm: noun-c      # ash.SG.DIR is *əčw, and then *əčəw
```

```
; rules/pe-morph.bsc
/ ə / C _ w #
```

A form goes through the morphophonology of the stage whose forms it is
joined from:

- An item formed at stage S is built from S's final forms, and then goes
  through S's morphophonology. That form is its form at S. Items built from
  other items formed at S see them after morphophonology.
- An item rebuilt by `reform` or `repattern` at S is joined from the forms
  entering S, which are those of S's parent, so it goes through the parent's
  morphophonology, and then S's rules. A `repattern` stem given to the entry
  itself is written, not joined, so it does not.

A stage without `morphophonology` joins forms unchanged; it is not
inherited, so a stage whose morphophonology is still in force names the same
file. The file declares the boundary like any rules file. `trace` shows the
joined form as the input and the morphophonology's steps, or, for a
rebuild, a `morphophonology:` event.

---

## 3. `lexicon/*.yaml`: entries

Each file is a list of entries, and files are read in name order. An entry
has either a `form` (a root) or a `source` (a derivative).

```yaml
- id: ir
  form: "*ir₁-"               # * is ignored; - marks a boundary (§2)
  stage: proto-echo           # default: the root stage
  gloss: "this (proximal)"
  category: [{ at: proto-echo, is: DEM }]
  paradigm: demonstrative
  events: [...]               # §4
  fate: {...}                 # §5
  expect:                     # §6
    azal: { DIR: iš, GEN: iri }
  notes: |
    Free prose, with form references: {ir.GEN @ azal}.   (§7)
  derivatives:
    - id: iryane
      source: { compound: [ir, yane] }
      gloss: "now"
```

### Sources

| shape | meaning |
|---|---|
| `{ base: X }` | zero derivation, conversion |
| `{ base: X, morph: A }` or `morph: [A, ~, B]` | X plus affixes, as a template (§2) |
| `{ base: X, cell: C }` | an inflected form that took on a life of its own (*päällä*) |
| `{ compound: [X, Y] }` | concatenation of the members' bare forms |
| `{ loan: { from: STAGE, id: X } }` | a new word borrowed from another line |

A derivative's `stage` defaults to its parent entry's stage. Without a `category`,
it takes the one its parent has at that stage. It is built
from the forms **at the end of** that stage, after that stage's rules.
Derivatives nest.

**Changing cells.** `cells` changes the paradigm's cells for one entry,
by name. A cell gets a different base (suppletion), different affixes, or
both, and new names add cells or variants for this entry only:

```yaml
- id: ego
  paradigm: noun
  cells:
    SG.DIR: { base: yen }          # suppletive: built on yen
    SG.GEN: [~, GEN.IRR]           # just a different template
    PST.3P~dialectal: [~, PST, 3P.Š]
```

A suppletive base is a real dependency, so it appears in the cell's
source and must exist where the cell is formed.

**Bound items.** `bound: true` marks an item that is not a word on its own:
a bound root or stem. Affixes are bound by default. With a boundary symbol
(§2), it keeps the boundaries at its edges (a written root keeps its `-`;
one built from parts keeps its outer boundaries), so it is cited as *ber-*. stemma warns about a bound item whose form has no `-`.
In Typst, `dictionary(stage, bound: false)` leaves bound entries out;
entries with a paradigm are always listed.

**Freezing.** A derivative is built once and after that undergoes only
sound change. Analogy that later affects its base does not reach it. To
make it follow its base, add a `reform` event.

### Category history

`category` is a list of `{ at: STAGE, is: TAG }`. At any stage, the tag in
force is the one set at the nearest stage on the path back to the root, so
a tag set at `azal` affects only the Azal line. Tags are free text, but a
fixed vocabulary makes queries useful:

```
stemma shifts 'N.*' POSTP     # case forms that became postpositions
stemma shifts DEF '*'         # everything a definite marker turned into
```

---

## 4. Events

Each event is written under the entry it affects, with `cell:` if it
affects only one paradigm cell. `at: S` means the event applies to the form
**entering** stage S's rules. The only exception is `irregular`, which
replaces S's output. So later sound laws still act on the result of an
analogy or a loan.

### `analogy`

```yaml
- analogy:
    at: azal
    cell: DIR
    replace: { r₁: r₂ }       # grapheme substitutions
    model: "the plural -r (< *r₂)"
```

This is preferred over writing the output form: if you change what word-final
*r₂ becomes, the analogical form follows.

### `reform`

```yaml
- reform: { at: azal }
```

This rebuilds the item from its `source`, using the forms entering azal,
and puts the result through the parent stage's morphophonology (§2).

### `repattern`

```yaml
- repattern: { at: azal, paradigm: noun-o, stem: "valykkō" }
```

The entry changes paradigm at this stage: every cell is rebuilt from the
new paradigm's template, using the stem and the affixes' forms entering
the stage, goes through the parent stage's morphophonology (§2), and then
through the stage's rules. `stem` is written as at
that stage and is optional; without it the entry's own form is used. With
it, the bare entry takes the new stem too. The entry's own `cells` changes
(§3) apply to the new paradigm as well, and a suppletive cell keeps its
base.

Cells that the new paradigm lacks are lost from this stage on. The new
paradigm may not have cells the old one lacks. A repattern applies to the
whole entry, so it takes no `cell:`. Other lines of descent keep the old
paradigm, and Typst's `paradigm()` uses the one in force at the stage.

### `loan`

```yaml
- loan:
    at: wiyan                  # replaces the inherited form here
    from: azal                 # donor stage
    id: other-item             # optional; default: the same item
    adapt: rules/azal-into-wiyan.bsc   # optional loan phonology
```

The donor's form is taken from the end of the `from` stage, then run
through `adapt` if given, and then through the recipient stage's rules.
Donor stages are always computed before recipients. Circular loans are an
error.

### `irregular` (last resort)

```yaml
- irregular: { at: azal, form: "iš", reason: "not yet worked out" }
```

This sets the output of the stage directly. The build warns when the rules
come to produce the same form on their own, because the event is then
redundant.

---

## 5. Fate

```yaml
fate:
  old-azal: lost                        # no reflex here or below
  wiyan: { replaced-by: other-item }
```

Lost words still get would-be reflexes (see `!` in §7).

---

## 6. Expectations

`expect` pins forms the build must reproduce, compared against spelled
output. They are assertions, not data: nothing is computed from them.

```yaml
expect:
  azal: iryane                 # the item's own form
  # or, for paradigm cells:    azal: { DIR: iš, GEN: iri }
  # or both:                   azal: { form: il, DIR: iš }
```

Record the forms your grammar already uses here, so that changing a rule
can't silently change a form the text depends on. `stemma build` exits
non-zero when any expectation fails.

---

## 7. References in prose

| syntax | renders as |
|---|---|
| `{ir}` | the form where the item was formed, starred if proto: *\*ir₁* |
| `{ir @ azal}` | the Azal reflex, spelled |
| `{ir.GEN @ azal}` | a paradigm cell |
| `{ir @ azal /}` | phonemic rather than spelled |
| `{ir @ azal !}` | the regularly expected form: the whole lexicon rebuilt with no events and no fates |
| `{{` | a literal `{` |

A reference that doesn't resolve is a build error.

---

## 8. Commands and output

```
stemma -d DIR build [--strict]   compute everything; --strict fails on warnings
stemma -d DIR paradigm ROOT STAGE  the paradigm in force at a stage
stemma -d DIR history ID STAGE     a form's history along one stage path
stemma -d DIR trace ID [STAGE]     an item's rule-by-rule derivation
stemma -d DIR shifts FROM TO     category shifts (* is a wildcard)
stemma -d DIR rules FILE         parse a rules file (- for stdin); print its
                                 segments and statements as JSON
stemma -d DIR typst [--stage STAGE] [--out OUT] [--force]
                                 write stemma.typ, and a dictionary document
                                 for STAGE, to OUT (default DIR)
```

`typst` writes the `stemma.typ` built into the binary, so it matches the
`lexicon.json` that version writes; it replaces the file each time. With
`--stage` it also writes `dictionary-STAGE.typ`, a document that imports
`stemma.typ`, reads `build/lexicon.json` and lists the stage's dictionary.
That one is yours to edit, so it is kept if it exists unless `--force` is
given. When `OUT` is outside the project, the document reads the lexicon
through `..`, and Typst then needs `--root` set to a directory above both.

`paradigm` prints cell IDs and forms in paradigm order, with variants under
their main cells. Cells lost through `repattern` are omitted. `history` and
`trace ID STAGE` follow the ancestry of `STAGE`, so a change on one branch
does not appear on another. Use a cell ID such as `valyk.PL.GEN` to follow
one form. `history` marks its loss or deletion; `trace` also shows each rule
step. With no stage, `trace` covers the whole stage tree as before. The
paradigm and history views show spelling and, where it differs, phonemic
form.

`rules` only parses the file (with Brassica), so it works even when the
project doesn't build. A rule's `text` is what traces report when the rule
applies. A parse error gives `ok: false` with the message, `line` and
`column`, and exits with status 1.

`build` writes to `DIR/build/`:

- `lexicon.json` has every item, and for each stage: the forms, spelled
  forms, regular forms and category. Notes are pre-resolved into runs.
  Each stage carries its `rules`, `morphophonology` and `orthography` references as written
  in `family.yaml`. Read it in Typst with `typst/stemma.typ`, or browse it
  with `ui/` (see the README).
- `trace.json` has, for each item and stage, the events, the input to the
  stage's rules, the rule trace and the origin, for `ui/`. Typst doesn't
  need it. A stage is left out when it has none of these, and so is an item
  with no stages left; `origin` is left out when it is `inherited`.
- `forms.tsv` has one line per item and stage.
- `diff.txt` lists what changed since the previous build.

`lexicon.json` holds every cell at every stage, so it leaves out whatever
can be inferred. Item fields that are null or empty are omitted, and
`bound` is written only when true. In a reflex, `spelled` and `regular`
are omitted when they equal `forms`, and `regular_spelled` when it equals
`spelled`. A lost reflex has `"lost": true` and no `forms`; its
`regular_spelled` defaults to `regular`. A stage whose reflex is the same
as at its parent stage is omitted, so the reflex at a stage is the one at
the nearest stage above it that has one, back to the stage where the item
was formed. `stemma.typ` fills all of this in.

`build` prints the changes when there are at most 20 of them. Otherwise it
prints how many changed at each stage, and in full only the changes to
forms that have an `expect` or are quoted in notes.

---

## Known limitations

- Without a boundary symbol (§2), bare stems and affixes run through the
  rules as if they were words, which gives meaningless forms (Azal *heh* for
  the bare dative *\*-xx*). They appear in `forms.tsv`, and in the Typst
  dictionary only if they are roots or derivatives.
- When the rules give several outputs, the first one is used to build
  derivatives, and a warning is issued.
- Loans by `source` cannot yet be adapted. Only loan events take `adapt`.
