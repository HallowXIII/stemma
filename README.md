# stemma

An etymological database for constructed language families, in which
**derived forms are computed rather than stored**.

You write down the proto-lexicon, the morphology used to build words, the
dated events that disturb regular development (analogy, borrowing,
re-formation, loss), and prose notes on meaning. A sound-change engine
(initially [Brassica](https://github.com/bradrn/brassica)) produces every
reflex at every stage. If you change a sound law and rebuild, the whole
lexicon updates, including forms quoted in your prose, and you get a diff
of what changed.

## Principles

1. **Store inputs and history, never outputs.** A surface form is written
   by hand only as a last resort (see `irregular` in the schema), and the
   tool flags every one of them.
2. **Irregularity is an event with a date.** Analogy and borrowing happen
   at a point in the relative chronology, and later sound laws still apply
   to their results.
3. **Derivatives are frozen by default.** A derived form is built once, at
   the stage where it was coined, and after that it only undergoes sound
   change. Analogical re-formation has to be recorded as an explicit event.
   This is how fossils arise, such as compounds that keep reflexes the
   paradigm has lost.
4. **Semantics is prose; category is data.** Meaning changes are too
   idiosyncratic to structure. Changes of part of speech or grammatical
   function (N.ADESS > POSTP, DEF > SG) are structured, so you can query
   grammaticalisation paths.
5. **Prose quotes forms by reference.** `{ir.DIR @ azal}` in a note is
   rendered with whatever the current rules produce.

## Layout of a project

```
family.yaml          stages, and the rules segment for each
morphology.yaml      affixes and paradigms
lexicon/*.yaml       entries
rules/*.bsc          Brassica sound changes; `report` marks stage breaks
```

## Usage

```sh
nix develop                                  # GHC, cabal, HLS; Brassica pinned
cabal run stemma -- -d examples/echo build   # compute; prints what changed
cabal run stemma -- -d examples/echo paradigm ir azal
cabal run stemma -- -d examples/echo history ir.DIR azal
cabal run stemma -- -d examples/echo trace ir.DIR
cabal run stemma -- -d examples/echo trace ir.DIR azal
cabal run stemma -- -d examples/echo shifts '*' '*'
cabal test                                   # the Echo example must reproduce the grammar
```

Or use `nix build` to get `result/bin/stemma`, or `nix run . -- -d examples/echo build`.

To install it, use `nix profile add github:HallowXIII/stemma` (`.` from a
clone; `nix profile install` on Nix older than 2.26), or add it to a NixOS
or home-manager flake:

```nix
inputs.stemma.url = "github:HallowXIII/stemma";
# or "git+https://github.com/HallowXIII/stemma.git"
# ...
nixpkgs.overlays = [ inputs.stemma.overlays.default ];
environment.systemPackages = [ pkgs.stemma ];  # home.packages for home-manager
```

The installed package holds only the executable, so the closure has no GHC
in it.

To browse a build, run the UI (needs Python 3, nothing else):

```sh
python3 ui/serve.py -d examples/echo         # http://127.0.0.1:8737
```

It shows each entry's reflexes at every stage, with the rule-by-rule trace
for each stage and the form the regular development would have given. It
also has paradigm tables, notes with linked form references, a dictionary
per stage, a category-shift query, and the warnings, expectation
mismatches and diff from the last build. **Rebuild** (⌘B) runs
`stemma build`; tick **auto** to rebuild whenever a `.yaml` or `.bsc`
file changes.

Entries can be edited too. On an entry's page, **Edit** changes its form
and gloss, and **YAML** edits its whole block (events, notes, categories,
derivatives). **Delete** removes the entry's block, along with any
derivatives nested in it, after a preview that shows what would go and
what still refers to it. **+ New entry** adds a word to a lexicon file. **Preview**
shows how the entry's reflexes would change at every stage, which other
forms would change, and which expectations would newly fail. Edits change
only the lines involved, so comments and layout are kept, and **Save**
refuses anything that would stop the project building.

The **Rules** tab edits the project's Brassica files, with a tab per
stage laid out like the family tree. The first row holds the root's
daughters, and choosing one opens a row for its own daughters, so each
branch has its own layer. A stage's tab edits just its segment of the rules
file (with a Spelling toggle if the stage has an orthography), and *Whole
file…* opens a complete file. A stage with no rules yet gets a form that
creates its `.bsc` file, seeded with an existing categories block, and adds
the `rules:` line to that stage in `family.yaml`. Only that line is added;
comments and layout are kept, and the change is test-built on a copy first.

**Delete stage…** removes a stage from `family.yaml`. Its daughters can be
reattached to its parent or deleted with it. Its rules can be kept, or
removed: a file of its own is deleted, and a segment of a shared file is cut
(keeping any `categories` blocks) with later `#N` references renumbered.
**Delete file…** deletes a rules file and unhooks the stages that use it.
Both show the exact edits and their effect on the lexicon first, and are
refused while entries still refer to a stage being removed. Brassica itself
checks the file as you type (via `stemma rules`). Beside each rule is the
number of forms it changed in the last build, and rules that never apply
are flagged; click a count to list the forms, before and after.
**Preview** (⌘↵) builds a temporary copy of the project with your edit and
shows which forms would change and which expectations would fail, without
touching your files. **Save** (⌘S) writes the file and rebuilds. It uses `stemma` from `PATH`, then `result/bin/stemma`, then
`cabal run` (override with `--stemma`). Without the server,
`ui/index.html` can open any `build/lexicon.json` read-only.

In Typst:

```typst
#import "stemma.typ": stemma
#let (reflex, notes, entry, dictionary) = stemma(json("build/lexicon.json"))
The direct form is #reflex("ir.DIR", "azal").
```

See [`docs/schema.md`](docs/schema.md) for the format,
[`examples/echo/`](examples/echo/) for a worked example, and
`examples/echo/dictionary.typ` for the Typst side.

## Engines

The engine is behind a small interface (`Stemma.Engine`): load a rules
reference, then apply it to a batch of grapheme-split words. Brassica is
linked as a library (`Stemma.Engine.Brassica`). Brassica 1.0.0 is marked
broken in nixpkgs because of stale version bounds, so the flake jailbreaks
it. A CLI engine such as Lexurgy would be another implementation of the
same record, calling the tool as a subprocess.
