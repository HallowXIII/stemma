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
cabal run stemma -- -d examples/echo trace ir.DIR
cabal run stemma -- -d examples/echo shifts '*' '*'
cabal test                                   # the Echo example must reproduce the grammar
```

Or use `nix build` to get `result/bin/stemma`.

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
