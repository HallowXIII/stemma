#!/bin/sh
# usage: research/refresh-expect.sh FILE...
# Regenerate the `expect:` block of every top-level entry in the given
# lexicon files from attested.tsv (see expect.sh). Other lines are kept,
# and so is the block of an entry that attested.tsv has no forms for under
# its own id (a replacement such as perro, written by hand).
cd "$(dirname "$0")/.." || exit 1
for f in "$@"; do
  awk -v gen="research/expect.sh" '
    function flush() { if (held != "") { printf "%s", held; held = "" } }
    /^- id: / { id = $3; gsub(/"/, "", id) }
    skip && /^    / { if (keep) held = held $0 "\n"; next }
    skip { skip = 0; flush() }
    /^  expect:/ {
      n = 0; out = ""
      while ((gen " " id | getline l) > 0) { out = out l "\n"; n++ }
      close(gen " " id)
      if (n > 1) { printf "%s", out; keep = 0 } else { held = $0 "\n"; keep = 1 }
      skip = 1; next
    }
    { print }
    END { flush() }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
