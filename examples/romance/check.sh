#!/bin/sh
# Compare the last build with attested.tsv: every inherited, analogical,
# semi-learned or suppletive form whose item exists, by word. Learned, derived and
# replaced rows belong to other items and are left out.
#
#   ./check.sh            all words
#   ./check.sh murus ...  only these
#   ./check.sh -s         a count per word only
cd "$(dirname "$0")" || exit 1
summary=0
if [ "$1" = "-s" ]; then summary=1; shift; fi
awk -F'\t' -v only="$*" -v summary="$summary" '
BEGIN { n = split(only, w, " "); for (i = 1; i <= n; i++) want[w[i]] = 1 }
NR == FNR { form[$1 "\t" $2] = $3; seen[$1] = 1; next }
FNR == 1 { next }
$5 == "learned" || $5 == "derived" || $5 == "replaced" { next }
n && !($1 in want) { next }
{
  item = ($3 == "-" ? $1 : $1 "." $3)
  if (!(item in seen)) { missing[$1]++; next }
  total[$1]++
  got = form[item "\t" $4]
  if (got == $7) { ok[$1]++; next }
  bad[$1] = bad[$1] sprintf("  %-14s %-12s want %-14s got %s%s\n", $3, $4, $7, (got == "" ? "(none)" : got), ($5 == "inherited" ? "" : "  [" $5 "]"))
}
END {
  for (id in total) {
    printf "%-12s %3d/%-3d%s\n", id, ok[id], total[id], (missing[id] ? "  (" missing[id] " rows for items not built)" : "") | "sort"
  }
  close("sort")
  if (!summary) for (id in bad) printf "%s\n%s", id, bad[id]
  for (id in missing) if (!(id in total)) printf "%-12s not built (%d rows)\n", id, missing[id]
}' build/forms.tsv attested.tsv
