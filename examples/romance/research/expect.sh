#!/bin/sh
# usage: research/expect.sh ID [INDENT]
# Print an `expect:` block for ID from attested.tsv: its inherited,
# analogical and semi-learned forms (learned, derived and replaced ones
# belong to other items). INDENT is the number of spaces before `expect:`.
cd "$(dirname "$0")/.." || exit 1
awk -F'\t' -v id="$1" -v ind="${2:-2}" '
BEGIN { pad = sprintf("%" ind "s", ""); split("old-spanish spanish old-french french", st, " ") }
FNR == 1 || $1 != id || $5 == "learned" || $5 == "derived" || $5 == "replaced" { next }
{ cell = $3; if (!((cell, $4) in v)) { if (!(cell in seen)) { seen[cell] = 1; cells[++n] = cell } v[cell, $4] = $7 } }
END {
  print pad "expect:"
  for (i = 1; i <= 4; i++) {
    s = st[i]; line = ""; bare = ""
    for (j = 1; j <= n; j++) if ((cells[j], s) in v) {
      if (cells[j] == "-") bare = v[cells[j], s]
      else line = line (line == "" ? "" : ", ") cells[j] ": " v[cells[j], s]
    }
    if (bare != "" && line == "") printf "%s  %s: %s\n", pad, s, bare
    else if (line != "") printf "%s  %s: { %s%s }\n", pad, s, (bare != "" ? "form: " bare ", " : ""), line
  }
}' attested.tsv
