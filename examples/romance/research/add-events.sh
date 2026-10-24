#!/bin/sh
# usage: research/add-events.sh FILE ID < block
# Insert the YAML on stdin (an `events:` block, indented for a top-level
# entry) before the `expect:` of entry ID in FILE.
cd "$(dirname "$0")/.." || exit 1
block=$(cat)
awk -v id="$2" -v block="$block" '
  /^- id: / { cur = $3; gsub(/"/, "", cur) }
  cur == id && /^  expect:/ && !done { print block; done = 1 }
  { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
