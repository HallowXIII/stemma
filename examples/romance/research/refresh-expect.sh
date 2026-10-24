#!/bin/sh
# usage: research/refresh-expect.sh FILE...
# Regenerate the `expect:` block of every top-level entry in the given
# lexicon files from attested.tsv (see expect.sh). Other lines are kept.
cd "$(dirname "$0")/.." || exit 1
for f in "$@"; do
  awk -v gen="research/expect.sh" '
    /^- id: / { id = $3; gsub(/"/, "", id) }
    skip && /^    / { next }
    { skip = 0 }
    /^  expect:/ { while ((gen " " id | getline l) > 0) print l; close(gen " " id); skip = 1; next }
    { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
