# stemma schema

All files are YAML. IDs are short slugs, unique across the whole project.

> **Quoting.** YAML reads a bare `N`, `Y`, `no`, `off` and so on as booleans.
> Quote category tags and ids like these: `is: "N"`, `id: "on"`. stemma
> reports an error if you forget.

The examples come from two families. Where it has a real case,
[`examples/romance`](../examples/romance/) is used: Latin to Spanish and
French. Features it doesn't need are shown with **Echo**, a constructed
family: Proto-Echo, with daughters Azal (through Old Azal) and Wiyan, and
demonstratives such as *ir-* "this".

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
  internal-boundaries: false   # none between joined parts (optional; §2)

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

`examples/romance/family.yaml` has nine stages on the same pattern: below
Western Romance, each line has one rules file in three segments.

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
Once a split an affix went through is no longer phonology, it can be
declared as allomorphs (below).

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

The Romance future stacks two suffixes, the infinitive and the reduced
*habeō*: `FUT.1SG: [~, INF.A, FUT.1SG]` (*cantāre* + *\*ajo* >
*chanterai*).

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

Romance lists its fused Latin endings as cells, but uses `extends` for the
Western Romance paradigms: `noun-a-wr` extends `noun-a` and changes only
its nominative plural to *-ās*.

**Loss on one line.** `exclude` removes a cell everywhere. `lost` removes it
from a stage on, so other lines of descent keep it. Cell names may use `*`,
and a cell's variants are lost with it. Every entry with the paradigm gets
the cell fate `lost` at that stage (§5), so would-be forms are still
computed. `lost` is inherited and merged like `exclude`.

A loss changes the paradigm itself, not just the entries that have it at
the time. An entry takes its paradigm as it is at the stage where it gets
it: an entry formed at or below a loss, or changing to the paradigm there
(`becomes`, `repattern`), never has the lost cells, and the paradigm's
re-formings (`at:`) and `events` skip them. An entry that changes to another
paradigm follows the losses of the one in force at each stage.

```yaml
  noun-o:
    lost:
      western-romance: ["GEN.*"]         # the genitive goes everywhere
```

Where a category is lost by merging cells rather than by losing some of
them, as case is in Spanish and French, the paradigm `becomes` one whose
cells continue the old ones (below).

**Change on one line.** `becomes` names stages where every entry with the
paradigm changes to another one, as if each had a `repattern` event
there (§4): cells are rebuilt from the new paradigm's templates, cells it
lacks are lost, and cells only it has are joined there. Other lines of
descent keep the paradigm. An entry with its own `repattern` at that stage
keeps it instead. The new paradigm's own `becomes` follows in turn, below
that stage. So does that of a paradigm an entry repatterns to, below the
repattern, and an entry's repattern ends the `becomes` of the paradigm it
leaves. A cell that an earlier paradigm lost and a later one has again is
joined again where that one comes into force. Nothing is changed or joined
at or below a stage where the entry itself is lost or replaced (§5).
`becomes` is not inherited, since a paradigm that extends the one it
replaces would otherwise become itself.

```yaml
  noun-a:
    cells: ...
    becomes: { western-romance: noun-a-wr }   # nominative plural in -ās
```

**Continuing cells.** Where an entry changes to a paradigm, a cell of the
new one can continue a cell of the old one instead of being rebuilt:
`continues` names the old cell, whose form entering the stage the new
cell takes as it is, and then goes through the stage's rules. This is how
a paradigm loses a category, such as case, by merging its cells: the
Romance nouns become number-only nouns, whose singular continues the
accusative singular.

```yaml
  noun-o:
    cells: ...
    becomes: { old-spanish: noun-rom, french: noun-rom }
  noun-rom:
    cite: SG
    cells:
      - SG: { continues: ACC.SG }
      - PL: [O.ACC.PL, { continues: ACC.PL }]
```

The old cells are lost there, if the new paradigm lacks them, so their
would-be forms are still computed (a continuation is not an event: it
applies to the regularly expected forms too), and `trace` says what each cell
continues. An entry can continue another cell instead (§3). Where an
entry is formed with the paradigm, a continuing cell is formed from its
template, or as the bare base if it has none. A cell continues at most
one cell, and its re-formings (`at:`) may go in the same list. It is an
error for an entry that changes to the paradigm not to have the cell
continued.

**Re-forming on one line.** A cell can be re-formed at a later stage for
every entry with the paradigm, as an entry's `at:` cell is (§3): it is
joined again at that stage, from the forms entering it, and only the
lines below that stage have the new form. Write the cell as a list of its
template and the re-formings, or, for a cell the paradigm joins only at a
later stage, as the re-forming alone:

```yaml
  verb-a:
    cells:
      - PRS.1PL: [PRS.1PL.A, { at: old-french, morph: [~, PRS.1PL.O] }]
      - FUT.1SG: { at: western-romance, morph: [~, INF.A, FUT.1SG] }
```

A template longer than one affix is written as a list inside the list.
A re-forming takes `at` and `morph`; `base` and `stem` belong to an
entry. An entry's own `at:` for a cell replaces the paradigm's re-forming
of that cell at the same stage (so a verb can keep an older form there,
by re-forming to it), and the paradigm's other re-formings still apply. The
re-formings of the entry's paradigm and of any it changes to apply.
They are inherited through `extends` with their cell, and replaced with
it.

**Events on a paradigm.** A paradigm can list `events` (§4), usually with
`cell:`, which every entry with the paradigm gets before its own. This
suits an analogy that reaches a whole conjugation but only one cell, and
that a re-forming from bare parts would get wrong because the stem has
changed on the way (Spanish 2pl *podéis*, from *podedes*):

```yaml
  verb-e:
    events:
      - analogy: { at: spanish, cell: PRS.2PL, rule: "d e s / j s / [á é] _ #" }
```

They are inherited through `extends`, after the parent's. The events of
any paradigm the entry changes to apply as well.

**Citation.** In a dictionary, an entry with a paradigm is cited by one of
its cells: by default its first, or the cell its paradigm's `cite` names.
`cite` is one cell, `~` for the bare form (the stem, which suits verbs
with large paradigms), or a map from stages to either, each in force from
its stage down:

```yaml
  noun-o:
    cite: { latin: NOM.SG, western-romance: ACC.SG }
```

Where an entry changes paradigm (`becomes`, `repattern`), the citation
follows the paradigm in force. An entry's own `cite` (§3) takes precedence
over its paradigm's. `cite` is inherited through `extends`. Typst's `entry`
and `ui/` show the cited cell as the headword, with its own etymology
(*ómbre* < OSp. *ómne* < Lat. *\*hominem*), which goes on through the
cell a continuing cell continues (French *eau* < OF *eaue* < Lat.
*\*aquam*, from SG through ACC.SG). On an entry's page, `ui/` shows the
cited cell at each stage. The build warns
where an entry is cited by a cell that has no form, such as a lost
nominative; the dictionary then falls back to the bare form. The bare
form always evolves too, and is what `{homo @ spanish}` refers to.

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
(§3). In `lexicon.json` a variant has `variant_of` and `variant`, and a
continuing cell has `continues`, the cell it continues at each stage
where it is joined; Typst's
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

Where boundaries only matter at the edges, as when they keep a bare affix
from being stressed as a word, set `internal-boundaries: false`. Parts are
then joined with no boundary between them, and any inside the parts are
dropped, so the rules and the morphophonology see a joined form as one
word. The boundaries at the edges of a bound result are kept, and a written
form keeps any `-` written inside it until it is joined into something.
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

Every form joined from parts goes through the morphophonology of each
stage it has a form at:

- An item formed at stage S is built from S's final forms, and then goes
  through S's morphophonology. That form is its form at S. Items built from
  other items formed at S see them after morphophonology.
- An item inherited by S goes through S's rules and then S's
  morphophonology. So a stage can have morphophonology of its own for
  cells built at an earlier stage: the cells of a paradigm built at
  Proto-Echo go through Old Azal's when they reach Old Azal, while the
  roots they are built from do not.
- An item rebuilt by `reform` or `repattern` at S is joined from the forms
  entering S, which are those of S's parent, so it goes through the parent's
  morphophonology, then S's rules and S's morphophonology. A `repattern`
  stem given to the entry itself is written, not joined, so it does not.

An `irregular` form replaces the result, morphophonology included. A stage
without `morphophonology` passes joined forms on unchanged; it is not
inherited, so a stage whose morphophonology is still in force names the same
file. The file declares the boundary like any rules file. `trace` shows the
morphophonology's steps after the rules' (for a form formed at the stage,
after the joined form as its input), or, for a rebuild through the
parent's, a `morphophonology:` event.

### Allomorphs

An affix's form at a stage is its written form run through the rules on
its own. In a cell joined early that doesn't matter, since the rules see
the whole word. But a form joined later, such as a derivative formed at a
later stage or a `repattern`, gets the affix's out-of-context reflex. When
sound change has split an affix into reflexes that its own rules can't
derive any more, declare them:

```yaml
affixes:
  INF.A:
    form: "*-āre"
    # pretonic in the future (chanterai), where the stress is on the ending
    allomorphs:
      old-french:                                    # from this stage on
        - { before: [a], form: "-ər" }
        - { form: "-er" }                            # elsewhere
```

- **Scope.** The allomorphs given at stage S are used in forms joined from
  the forms of S or of a stage below it: items formed there, and `reform`
  or `repattern` at a stage below S, since those join from the forms
  entering the stage. Cells joined before S keep their history, and other
  lines of descent use the ordinary reflex. A stage below S may give its own
  list, which replaces S's from there on.
- **Choice.** The first allomorph whose condition fits is used. `after:`
  lists the graphemes the parts before the affix may end with, and
  `before:` the graphemes the parts after it may start with. Empty parts
  and boundaries are skipped, so in `[PL, DAT]` the dative sees the end of
  the plural, not of the stem. An allomorph without a condition is the
  elsewhere case and must come last. If none fits, the build fails. One
  list may not mix `after:` and `before:`.
- **Order.** Affixes with `after:` lists are chosen first, from left to
  right, each seeing the allomorphs chosen before it. Then those with
  `before:` lists are chosen from right to left, seeing everything after
  them as chosen. So a suffix sees an earlier prefix's ordinary form, and a
  prefix sees every suffix as chosen.
- **Evolution.** Each allomorph is written as at S and evolves through the
  later stages' rules, like any affix form. A list's graphemes are compared
  as written, with the stage's multigraphs as one grapheme each, so a list
  inherited by a later stage may need giving again once sound changes alter
  the inventory. The build warns when a stage that the affix is joined from
  has no form with one of a list's graphemes. It also warns about a list
  without an elsewhere case.
- **The affix itself.** Wherever allomorphs are in force, the affix's own
  reflex lists them (*-ər ~ -er*), since its form evolved on its own never
  occurs. `trace` shows each choice as an event in the joined form, e.g.
  `INF.A: -ər (before a)`.

Each allomorph is carried by an internal item, `INF.A~old-french~1` and so on,
which never appears in the build products. So ids may not contain `~`.

---

## 3. `lexicon/*.yaml`: entries

Each file is a list of entries, and files are read in name order. An entry
has either a `form` (a root) or a `source` (a derivative).

```yaml
- id: homo
  form: "*homō"               # * is ignored; - marks a boundary (§2)
  stage: latin                # default: the root stage
  gloss: "man, person"
  category: [{ at: latin, is: "N" }]
  paradigm: noun-c
  events: [...]               # §4
  fate: {...}                 # §5
  expect:                     # §6
    old-french: { NOM.SG: ɔm, ACC.SG: ɔmə }
  notes: |
    Free prose, with form references: {homo.NOM.SG @ old-french}.   (§7)
  derivatives:
    - id: "on"
      source: { base: homo, cell: NOM.SG }
      gloss: "one (indefinite pronoun)"
```

### Sources

| shape | meaning |
|---|---|
| `{ base: X }` | zero derivation, conversion |
| `{ base: X, morph: A }` or `morph: [A, ~, B]` | X plus affixes, as a template (§2) |
| `{ base: X, cell: C }` | an inflected form that took on a life of its own (French *on* < *homo*) |
| `{ compound: [X, Y] }` | concatenation of the members' bare forms |
| `{ loan: { from: STAGE, id: X, adapt: FILE } }` | a new word borrowed from another line or an ancestor; `adapt` optional |

A derivative's `stage` defaults to its parent entry's stage. Without a `category`,
it takes the one its parent has at that stage. It is built
from the forms **at the end of** that stage, after that stage's rules.
Derivatives nest.

**Loans.** A `loan` source makes a new word, beside anything inherited,
such as a learned borrowing from Latin (French *fragile* beside inherited
*frêle*). A `loan` event (§4) instead replaces the item's form. The donor's
form is taken from the end of the `from` stage, which may be an ancestor,
and run through `adapt` if given. The result is the word's form at its own
stage: unlike a loan event, it does not go through that stage's rules, so
the adaptation gives the stage's form. `trace` shows the donor's form and
the adaptation's steps.

**Changing cells.** `cells` changes the paradigm's cells for one entry,
by name. A cell gets a different base (suppletion) or stem, different
affixes, or both, and new names add cells or variants for this entry only:

```yaml
- id: ego
  paradigm: noun
  cells:
    SG.DIR: { base: yen }          # suppletive: built on yen
    SG.GEN: [~, GEN.IRR]           # just a different template
    PST.3P~dialectal: [~, PST, 3P.Š]
```

In Romance, *ire* takes its preterite from *esse* (Spanish *fue*) with
`PRET.3SG: { base: esse.PRET.3SG }`.

A suppletive base is a real dependency, so it appears in the cell's
source and must exist where the cell is formed.

**Stems.** `stem:` gives a cell a stem as written, in place of the entry's
form, such as the oblique stem of a Latin third-declension noun:

```yaml
- id: homo
  form: "*homō"
  paradigm: noun-c                 # NOM.SG is the bare base
  cells:
    ACC.SG: { stem: "*homin-" }
    NOM.PL: { stem: "*homin-" }
```

The stem is written as at the stage where the cells are formed, and
evolves from there like a bound root, but it is not an item you can refer
to: it never appears in the build products, and in `lexicon.json` the
cell's `source` shows it as written. Cells with the same stem share it. A
cell has `base` or `stem`, not both. With `at:` (below), the stem is
written as entering that stage, like a `repattern` stem (§4).

**Cells joined later.** With `at: S`, a cell is not part of the paradigm:
it is joined at S, from the forms entering S, as a `repattern` joins
(§4), and exists only from S on. This suits forms that belong to a later
arrangement of the paradigm, such as the Romance future, built from the
infinitive and *habēre* only in Western Romance. On a cell the paradigm
has, or one the entry changes to (`repattern`, `becomes`) has, `at:`
re-forms it there instead; that stage must be below where the cell is
joined.

```yaml
- id: ire
  paradigm: verb-x
  cells:
    FUT.1SG: { at: western-romance, stem: "*īr-", morph: [~, FUT.1SG] }
```

**Several changes to one cell.** A cell can be given a list: at most one
change without `at:` (its template, base or stem here) and any number of
re-formings, as on a paradigm. This is for a cell that continues one form
on one line and another elsewhere:

```yaml
- id: esse
  cells:
    PTCP: [{ base: stare.PTCP }, { at: ibero-romance, base: sedere.PTCP, morph: ~ }]
```

A template in the list stands for the change without `at:`; write a
longer one as a list inside the list.

**Continuing another cell.** `continues` on a cell picks which cell of
the previous paradigm it continues where the entry changes to a paradigm
with continuing cells (§2), over the paradigm's choice. French *prêtre*
continues the Latin nominative where most nouns continue the accusative:

```yaml
- id: presbyter
  cells:
    SG: { continues: NOM.SG }
    SG~obl: { continues: ACC.SG }    # a second form, as a variant
```

A cell the entry's own paradigm lacks is added only to the paradigm it
changes to, as a variant is here. `continues` can go with a template,
`base` or `stem`, which apply where the entry is formed with the paradigm.

With `at: S`, `continues` applies only where the entry changes paradigm at
S, so that one line can continue another cell. It takes nothing else, and
it is an error if the entry doesn't change at S to a paradigm with the
cell:

```yaml
    SG: { at: french, continues: NOM.SG }   # Old Spanish keeps the paradigm's
```

**Citation.** `cite`, as on a paradigm (§2), sets the cell this entry is
cited by, over its paradigm's: `cite: ~` cites a verb by its stem.

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
a tag set at `old-french` affects only the French line. Tags are free
text, but a fixed vocabulary makes queries useful:

```
stemma shifts AUX FUT         # forms of habēre that became future endings
stemma shifts DEM '*'         # everything a demonstrative turned into
```

### Gloss history

`gloss` is a string, or, where the meaning changes, a map from stages to
glosses. At any stage, the gloss in force is the one given at the nearest
stage on the path back to the root, as for categories:

```yaml
- id: magis
  gloss: { latin: "more", old-french: "more; but", french: "but" }
```

The gloss says what the word means at a stage; how it came to mean that
belongs in `notes`. A stage with no gloss on its path has none. In
`lexicon.json`, an item's `gloss` is the one where it is formed, and a
reflex has its own `gloss` where that differs. Typst's `entry` and
`dictionary`, and `ui/`, show the gloss of the stage.

### Properties

`properties` records features such as gender, each by name. On a paradigm,
a property is one value. On an entry, it is a value for every stage or,
where it changes, a map from stages to values:

```yaml
paradigms:
  noun-a:
    properties: { gender: f }
  noun-o-n:
    properties: { gender: "n" }     # quoted: YAML reads n as false
    becomes: { western-romance: noun-o }   # m, as noun-o says

- id: dens
  paradigm: noun-c                  # gives no gender
  properties:
    gender: { latin: m, gallo-romance: f }   # French dent is feminine
```

At any stage, a property is the one declared nearest on the path back to
the root: by the entry, or by a paradigm where it comes into force for the
entry (where the entry is formed with it, or changes to it), the entry's
first at the same stage. A paradigm that doesn't give a property keeps the
one in force (Spanish and French `noun-rom` keep a noun's gender). An
entry's property given without stages holds everywhere. Paradigms inherit
properties through `extends`. In `lexicon.json`, an entry's `properties`
are given at the stages where they change, as its `cite` is.

### Notes

`notes` is prose, with references to forms (§7). It is a text for every
stage, or a map from stages to texts, each in force at that stage and
below it on its own line. A note about Spanish need not appear in the
French dictionary:

```yaml
- id: magis
  notes:
    old-spanish: |                  # Old Spanish and Spanish
      The regular Old Spanish form would be {magis @ old-spanish !}, ...
```

Unlike glosses, notes add up: at a stage, every note on the path back to
the root is in force. In `lexicon.json`, notes for every stage are a list
of runs, and notes by stage an object from stages to such lists. Typst's
`notes(id, stage: s)` and `dictionary(s)`, and `ui/`'s dictionary, show the
notes in force at `s`; `notes(id)` and an entry's page in `ui/` show them
all.

### Dictionary entries

Typst's `entry` and `dictionary` take `fields`: what an entry shows, in
order. By default it is `("head", "category", "properties", "gloss",
"etymology", "source", "notes")`. A field can also be the name of one
property, or a function of the entry's id and the stage. `stemma(...,
fields: ...)` sets it for every entry, and `property-style` how a
property's value is shown (in italics by default):

```typst
#dictionary("french", fields: ("head", "gender", "gloss", "etymology"))
```

---

## 4. Events

Each event is written under the entry it affects, with `cell:` if it
affects only one paradigm cell. An `analogy` without `cell:` affects the
entry and every cell (after any re-forming of the cell at that stage);
the other events without it affect the entry's own form. `at: S` means
the event applies to the form **entering** stage S's rules. The only
exception is `irregular`, which replaces S's output. So later sound laws
still act on the result of an analogy or a loan.

### `analogy`

```yaml
- analogy:
    at: spanish
    cell: PRS.1SG
    replace: { ó: ó j }       # grapheme substitutions: voy, after soy
    model: "soy"
```

Each key is one grapheme, and every occurrence of it is replaced. A
replacement of several graphemes may be written with spaces between them
(`{ a: a j }`), and an empty one deletes. A key that is not one grapheme at
the stage is an error.

Where the change is confined to a context, or must not touch every
occurrence, give a `rule` instead of `replace`: one statement in the rules
engine's syntax (Brassica's), applied to the form entering the stage.

```yaml
- analogy: { at: spanish, cell: PRS.2PL, rule: "d e s / j s / [á é] _ #", model: "the 2pl in -áis" }
```

The rule sees the form's graphemes as they are: it doesn't know the
stage's categories, so name graphemes or write categories inline
(`[a e i]`). A rule that changes nothing leaves the form as it was. `trace`
shows the rule with the event.

This is preferred over writing the output form: later sound changes still
act on the analogical form, so if you change them, it follows.

### `reform`

```yaml
- reform: { at: azal }
```

This rebuilds the item from its `source`, using the forms entering azal,
and puts the result through the parent stage's morphophonology (§2). Since
those are the parent's forms, the allomorphs in force at the parent are
chosen (§2).

### `repattern`

```yaml
- repattern: { at: ibero-romance, paradigm: noun-o, stem: "kɔ́rp-" }   # corpus > cuerpo
```

The entry changes paradigm at this stage: every cell is rebuilt from the
new paradigm's template, using the stem and the affixes' forms entering
the stage (choosing the parent stage's allomorphs, §2), goes through the
parent stage's morphophonology (§2), and then
through the stage's rules and morphophonology. `stem` is written as at
that stage and is optional; without it the entry's own form is used. With
it, the bare entry takes the new stem too. The entry's own `cells` changes
(§3) apply to the cells of the new paradigm they name as well (a change
to a cell only an earlier paradigm has, such as an oblique `stem:`, does
not add it), and a suppletive cell keeps its
base, as a cell with its own `stem` keeps its stem.

The entry takes the new paradigm as it is at this stage, as an entry that
always had it would: cells the new paradigm has lost (§2) at this stage or
above count as lacking. Cells that the new paradigm lacks are lost from
this stage on. Cells that it has and the old one lacks are joined at this
stage, the same way, and exist only from here on. Where such a cell is
given on more than one line (Spanish and French each lose case), it is
joined on each. An entry's `at:` on the cell at this stage re-forms it
after it is given. A repattern applies to the
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
- irregular: { at: old-french, cell: PRS.1SG, form: "syj", reason: "influenced by fui, not fully explained (Pope)" }
```

This sets the output of the stage directly. The build warns when the rules
come to produce the same form on their own, because the event is then
redundant.

---

## 5. Fate

```yaml
- id: capitia                            # Spanish cabeza
  fate: { old-french: lost }              # no reflex here or below
- id: frater
  fate: { spanish: { replaced-by: germanus } }   # hermano
```

Lost words still get would-be reflexes (see `!` in §7).

---

## 6. Expectations

`expect` pins forms the build must reproduce, compared against spelled
output. They are assertions, not data: nothing is computed from them.

```yaml
expect:
  spanish: más                 # the item's own form
  # or, for paradigm cells:    old-spanish: { SG: ómne, PL: ómnes }
  # or both:                   old-french: { form: ɔm, NOM.SG: ɔm }
```

Record the forms your grammar or sources already attest here, so that changing a rule
can't silently change a form the text depends on. `stemma build` exits
non-zero when any expectation fails.

---

## 7. References in prose

| syntax | renders as |
|---|---|
| `{magis}` | the form where the item was formed, starred if reconstructed: *\*magis* |
| `{magis @ spanish}` | the Spanish reflex, spelled |
| `{homo.SG @ old-spanish}` | a paradigm cell |
| `{magis @ spanish /}` | phonemic rather than spelled |
| `{magis @ spanish !}` | the regularly expected form: the whole lexicon rebuilt with no events and no fates (but with continuations, §2) |
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
does not appear on another. Use a cell ID such as `homo.NOM.SG` to follow
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
  forms, regular forms and category, and the gloss where it changes. Notes are pre-resolved into runs.
  Each stage carries its `rules`, `morphophonology` and `orthography` references as written
  in `family.yaml`. An affix with allomorphs has them as written, under
  `allomorphs`, by stage. An entry with cells has `cite`: the item it is
  cited by, at the stages where that changes, as for reflexes. Read it in Typst with `typst/stemma.typ`, or browse it
  with `ui/` (see the README).
- `trace.json` has, for each item and stage, the events (and allomorph
  choices), the input to the
  stage's rules, the rule trace and the origin, for `ui/`. Typst doesn't
  need it. A stage is left out when it has none of these, and so is an item
  with no stages left; `origin` is left out when it is `inherited`.
- `forms.tsv` has one line per item and stage.
- `diff.txt` lists what changed since the previous build.

`lexicon.json` holds every cell at every stage, so it leaves out whatever
can be inferred. Item fields that are null or empty are omitted, and
`bound` is written only when true. In a reflex, `spelled` and `regular`
are omitted when they equal `forms`, and `regular_spelled` when it equals
`spelled`, and `gloss` when it equals the item's. A lost reflex has `"lost": true` and no `forms`; its
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
