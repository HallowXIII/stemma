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

stages:
  proto-echo:
    name: Proto-Echo
    abbr: PE               # used in etymologies

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

Morphology builds forms by plain concatenation. It does no phonology.
Allomorphy that arises from sound change is left to the rules.

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

Affixes take the same fields as entries (§3) and default to the root
stage. They are items in their own right, so they can have category
history and notes, which is how you record things like a definite article
becoming a case ending.

An entry with `paradigm: demonstrative` gets one item per cell, named
`entry.CELL` (e.g. `ir.DIR`). Each cell is built at the paradigm's stage
(or at the entry's, if that is later) and then evolves on its own.

---

## 3. `lexicon/*.yaml`: entries

Each file is a list of entries, and files are read in name order. An entry
has either a `form` (a root) or a `source` (a derivative).

```yaml
- id: ir
  form: "*ir₁-"               # * and - are ignored when tokenising
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
| `{ base: X, morph: A }` or `morph: [A, B]` | X plus affixes |
| `{ base: X, cell: C }` | an inflected form that took on a life of its own (*päällä*) |
| `{ compound: [X, Y] }` | concatenation of the members' bare forms |
| `{ loan: { from: STAGE, id: X } }` | a new word borrowed from another line |

A derivative's `stage` defaults to its parent entry's stage. It is built
from the forms **at the end of** that stage, after that stage's rules.
Derivatives nest.

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

This rebuilds the item from its `source`, using the forms entering azal.

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
stemma -d DIR trace ID           an item's derivation, rule by rule, per stage
stemma -d DIR shifts FROM TO     category shifts (* is a wildcard)
```

`build` writes to `DIR/build/`:

- `lexicon.json` has every item, and for each stage: the forms, spelled
  forms, regular forms, category, events, and rule trace. Notes are
  pre-resolved into runs. Read it in Typst with `typst/stemma.typ`.
- `forms.tsv` has one line per item and stage.
- `diff.txt` lists what changed since the previous build (also printed).

---

## Known limitations

- Bare stems and affixes also run through the rules on their own, which
  gives meaningless forms (Azal *heh* for the bare dative *\*-xx*). These
  appear in `forms.tsv` but not in the Typst dictionary.
- Morpheme boundaries are not passed to the engine, so rules cannot yet
  refer to them.
- When the rules give several outputs, the first one is used to build
  derivatives, and a warning is issued.
- Loans by `source` cannot yet be adapted. Only loan events take `adapt`.
