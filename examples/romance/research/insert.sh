#!/bin/sh
# usage: research/insert.sh FILE ID REGEX < block
# Insert the lines on stdin after the first line matching REGEX inside the
# top-level entry ID of FILE.
cd "$(dirname "$0")/.." || exit 1
block=$(cat)
awk -v id="$2" -v re="$3" -v block="$block" '
  /^- id: / { cur = $3; gsub(/"/, "", cur) }
  { print }
  cur == id && $0 ~ re && !done { print block; done = 1 }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
