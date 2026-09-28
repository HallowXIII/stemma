# Worked example: Azal and Wiyan

This example is taken from the Azal grammar (demonstratives, direct case)
and from `historical-notes.md`.

- `lexicon/demonstratives.yaml`: *ir-* / *yor-*. It has an analogy event
  restricted to the direct cell, and compounds formed before the analogy
  that keep the regular *r₁ reflexes.
- `lexicon/grammatical.yaml`: direct *-n*, DEF > SPEC > SG.DIR.
- `rules/pe-to-azal.bsc` is a **stub** with only the changes this example
  needs. Its `report` splits it into Old Azal and Azal.
- Wiyan has no rules yet, so its forms are copies of the proto forms.

The paradigm tables from the grammar are recorded as `expect`, and
`cabal test` checks that they are reproduced:

| id | DIR | GEN | DAT | LOC | COM | ABL |
|---|---|---|---|---|---|---|
| ir  | iš  | iri  | irā  | ire  | ilem  | iru  |
| yor | yoš | yori | yorā | yore | yolem | yoru |

To build it and render the demo dictionary:

```sh
cabal run stemma -- -d examples/echo build
typst compile --root . examples/echo/dictionary.typ
```
