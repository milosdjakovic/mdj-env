#!/usr/bin/env bash
#
# Regenerate the vendored emoji dataset from the GitHub gemoji project.
#
# The picker searches offline, so the data is fetched once here and committed as
# data.json beside this script, rather than pulled at runtime. Rerun this only to
# refresh the set, for example when new Unicode emoji land upstream. The output is
# deterministic for a given upstream revision, so a rerun with no upstream change
# produces no diff.
#
# Each entry is reduced to what the picker needs. e is the glyph, n is the display
# name, a is the shortcode aliases shown as the row subtitle, and k is the
# lowercased search haystack. k folds the description, the aliases, the tags, and
# the category into one string, so a query matches on any of them. Folding the
# category in is what lets a group word like food or animal or flag surface the
# whole group without an exact name.

set -euo pipefail

SOURCE="https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/data.json"

command -v jq >/dev/null 2>&1 || { echo "jq is required, install it with brew install jq" >&2; exit 1; }

echo "Fetching $SOURCE"
curl -fsSL "$SOURCE" | jq '
  [ .[]
    | select(.emoji != null)
    | {
        e: .emoji,
        n: .description,
        a: ((.aliases // []) | join(" ")),
        k: (([.description] + (.aliases // []) + (.tags // []) + [.category])
             | join(" ") | ascii_downcase)
      }
  ]
' > "$OUT"

COUNT="$(jq 'length' "$OUT")"
echo "Wrote $COUNT emoji to $OUT"
