#!/bin/sh
# usage: research/pivot.sh ID... : attested forms as a table, one row per cell
cd "$(dirname "$0")/.." || exit 1
awk -F'\t' -v only="$*" '
BEGIN { n = split(only, w, " "); for (i = 1; i <= n; i++) want[w[i]] = 1 }
FNR == 1 || !($1 in want) { next }
{ k = $1 " " $3 ($5 == "inherited" ? "" : " [" substr($5,1,4) "]"); if (!(k in seen)) { seen[k] = 1; order[++m] = k; lat[k] = $2 }
  v[k, $4] = $7 }
END { printf "%-26s %-14s %-14s %-14s %-14s %s\n", "", "OF", "Fr", "OSp", "Sp", "Latin"
  for (i = 1; i <= m; i++) { k = order[i]
    printf "%-26s %-14s %-14s %-14s %-14s %s\n", k, v[k,"old-french"], v[k,"french"], v[k,"old-spanish"], v[k,"spanish"], lat[k] } }' attested.tsv
