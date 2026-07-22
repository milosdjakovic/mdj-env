#!/usr/bin/env bash
#
# Regenerate the vendored picker dataset from two upstream sources.
#
# The picker searches offline, so the data is fetched once here and committed as
# data.json beside this script, rather than pulled at runtime. Rerun this only to
# refresh the set, for example when new Unicode emoji land upstream. The output is
# deterministic for a given upstream revision, so a rerun with no upstream change
# produces no diff.
#
# Two sources feed one flat list, both reduced to the same shape so the spoon loads
# one file and never learns which source a row came from. e is the glyph, n is the
# display name, a is the subtitle, and k is the lowercased search haystack. A query
# matches on any word in k.
#
# Emoji come from the GitHub gemoji project, which carries per emoji a name, the
# shortcode aliases, freeform tags, and a category. k folds all of those together,
# so a group word like food or animal or flag surfaces the whole group.
#
# Symbols come from the official Unicode Character Database, a curated slice of the
# standard blocks that macOS renders natively, currency and arrows and math
# operators and the Mac modifier keys. k folds the official Unicode name, a category
# word, and a small set of hand added synonyms, so euro finds the euro sign, arrow
# finds the arrows, sum finds summation, and command finds the command key even
# though its official name is place of interest sign. Emoji come first in the list
# so the empty field still browses emoji, symbols are reached by typing.

set -euo pipefail

EMOJI_SOURCE="https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json"
UCD_SOURCE="https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/data.json"

command -v jq >/dev/null 2>&1 || { echo "jq is required, install it with brew install jq" >&2; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "perl is required, it ships with macOS" >&2; exit 1; }

TMP_EMOJI="$(mktemp)"
TMP_SYM="$(mktemp)"
trap 'rm -f "$TMP_EMOJI" "$TMP_SYM"' EXIT

echo "Fetching $EMOJI_SOURCE"
curl -fsSL "$EMOJI_SOURCE" | jq '
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
' > "$TMP_EMOJI"

# The symbol stage. perl parses the semicolon fields of UnicodeData.txt, since it
# reads hex codepoints natively and macOS awk lacks strtonum. Field 0 is the hex
# codepoint and field 1 is the official name. Names beginning with a less than sign
# are control characters or range markers, skipped. Each kept codepoint is tagged
# with a category by which block it falls in, and a codepoint keyed synonym table
# adds the plain words the official names lack. The line carries the decimal
# codepoint so jq can build the glyph with implode, no glyph ever leaves perl, so no
# encoding to get wrong. The synonym for shift and caps lock applies even though
# both sit inside the arrows block, since the table is keyed by codepoint not block.
echo "Fetching $UCD_SOURCE"
curl -fsSL "$UCD_SOURCE" | perl -ne '
  BEGIN {
    %syn = (
      0x24   => "dollar buck usd",
      0xA2   => "cent",
      0xA3   => "pound sterling gbp",
      0xA5   => "yen jpy",
      0x20AC => "euro eur",
      0x20A9 => "won krw",
      0x20B9 => "rupee inr",
      0x20BD => "ruble rub",
      0x20BF => "bitcoin btc",
      0x2318 => "command cmd clover",
      0x2325 => "option alt",
      0x2303 => "control ctrl",
      0x21E7 => "shift",
      0x21EA => "caps lock capslock",
      0x238B => "escape esc",
      0x232B => "delete backspace erase",
      0x2326 => "forward delete",
      0x23CE => "return enter",
      0x21A9 => "return enter hook",
      0x23CF => "eject",
      0x2324 => "enter",
      0x2387 => "alternate option",
      0x2211 => "sum summation sigma",
      0x220F => "product",
      0x221A => "square root sqrt",
      0x221E => "infinity",
      0x2248 => "approximately approx",
      0x2260 => "not equal ne",
      0x2264 => "less than or equal le",
      0x2265 => "greater than or equal ge",
      0x222B => "integral",
      0xD7   => "times multiply",
      0xF7   => "divide division",
      0xB1   => "plus minus",
    );
  }
  chomp;
  my ($hex, $name) = split /;/;
  next if !defined $name || $name =~ /^</;
  my $cp = hex($hex);
  my $cat = "";
  if ($cp == 0x24 || ($cp >= 0xA2 && $cp <= 0xA5) || ($cp >= 0x20A0 && $cp <= 0x20BF)) {
    $cat = "currency money";
  } elsif ($cp >= 0x2190 && $cp <= 0x21FF) {
    $cat = "arrow";
  } elsif ($cp == 0xB1 || $cp == 0xD7 || $cp == 0xF7 || ($cp >= 0x2200 && $cp <= 0x22FF)) {
    $cat = "math";
  } elsif ($cp == 0x2303 || $cp == 0x2318 || $cp == 0x2324 || $cp == 0x2325 || $cp == 0x2326
        || $cp == 0x232B || $cp == 0x2387 || $cp == 0x238B || $cp == 0x23CE || $cp == 0x23CF) {
    $cat = "key modifier";
  } else {
    next;
  }
  my $s = $syn{$cp} // "";
  print "$cp\t$cat\t$name\t$s\n";
' | jq -Rn '
  [ inputs
    | split("\t")
    | { cp: (.[0] | tonumber), cat: .[1], name: .[2], syn: .[3] }
    | {
        e: ([.cp] | implode),
        n: (.name | ascii_downcase),
        a: (if .syn == "" then .cat else .syn end),
        k: ([.name, .cat, .syn] | join(" ") | ascii_downcase)
      }
  ]
' > "$TMP_SYM"

# Emoji first, then symbols, into one flat list.
jq -s '.[0] + .[1]' "$TMP_EMOJI" "$TMP_SYM" > "$OUT"

EMOJI_COUNT="$(jq 'length' "$TMP_EMOJI")"
SYM_COUNT="$(jq 'length' "$TMP_SYM")"
TOTAL="$(jq 'length' "$OUT")"
echo "Wrote $TOTAL rows to $OUT, $EMOJI_COUNT emoji and $SYM_COUNT symbols"
