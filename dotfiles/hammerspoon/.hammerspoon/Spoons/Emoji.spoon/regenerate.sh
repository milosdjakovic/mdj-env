#!/usr/bin/env bash
#
# Regenerate the vendored picker dataset from two upstream sources.
#
# The picker searches offline, so the data is fetched once here and committed as
# data.json beside this script, rather than pulled at runtime. Rerun this only to
# refresh the set, for example when new Unicode emoji or symbols land. The output is
# deterministic for a given upstream revision and this machine's fonts, so a rerun
# with no change produces no diff.
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
# Symbols come from the official Unicode Character Database, a generous slice of the
# standard blocks the macOS Character Viewer shows, currency, punctuation, fractions
# and roman numerals, arrows and their supplements, every math block, technical and
# the Mac modifier keys, geometric shapes, box drawing, block elements, dingbats,
# braille, enclosed alphanumerics, and the smaller script blocks, Greek, Cyrillic,
# accented Latin, and kana. Two selection rules keep the set safe. Only real
# standalone glyphs are taken, whose Unicode general category is a letter, number,
# punctuation, or symbol, so combining marks, invisible format and control
# characters, and separators are left out, since those render as nothing or attach to
# other text. And the mass CJK ideograph and Hangul syllable blocks are excluded, tens
# of thousands of entries that are not keyword findable and would only slow the match.
# k folds the official name, a category word, and a small set of hand added synonyms,
# so euro finds the euro sign, arrow finds the arrows, and command finds the command
# key even though its official name is place of interest sign. Emoji come first in the
# list so the empty field browses emoji, symbols are reached by typing.
#
# A final filter drops anything that renders as a missing glyph box on this Mac. The
# only authority on what the system fonts can draw is the render itself, so
# filter-glyphs.lua renders every candidate through Hammerspoon and rejects the boxes.
# That is why this needs Hammerspoon running, and why the output depends on the
# machine's fonts as well as the upstream revision.

set -euo pipefail

EMOJI_SOURCE="https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json"
UCD_SOURCE="https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/data.json"
FILTER="$DIR/filter-glyphs.lua"

# All three are declared in regenerate.dependencies beside this script. This is a plain shell
# script run by hand from the repository, so it cannot reach the shared resolver and checks for
# them itself. It names each tool and stops there. Where a tool comes from is the repository's
# answer, which src/check-dependencies.sh gives, and never this file's.
need() { echo "$1 is required to regenerate the dataset, $2" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || need jq "run src/check-dependencies.sh in the repository to see where it comes from"
command -v perl >/dev/null 2>&1 || need perl "it ships with macOS, so an absent one means the PATH is wrong"
command -v hs >/dev/null 2>&1 || need hs "the render filter drives Hammerspoon through it, and Hammerspoon must also be running"

TMP_EMOJI="$(mktemp)"
TMP_SYM="$(mktemp)"
TMP_REFS="$(mktemp)"
TMP_CAND="$(mktemp)"
trap 'rm -f "$TMP_EMOJI" "$TMP_SYM" "$TMP_REFS" "$TMP_CAND"' EXIT

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

# The symbol stage. perl parses the semicolon fields of UnicodeData.txt, since it reads
# hex codepoints natively and macOS awk lacks strtonum. Field 0 is the hex codepoint,
# field 1 the official name, and field 2 the general category. It does three things at
# once. It records every assigned codepoint, expanding the First and Last range markers
# the CJK and Hangul and private use blocks use, so the END block can list the
# unassigned holes as box references for the render filter. It emits a candidate row for
# each assigned codepoint that falls in a target block and is a real standalone glyph,
# a letter, number, punctuation, or symbol category. And it tags each with a category
# word and any hand added synonyms. The row carries the decimal codepoint so jq builds
# the glyph with implode, no glyph ever leaves perl, so no encoding to get wrong. The
# synonyms are keyed by codepoint so shift and caps lock get their words even though they
# sit inside the arrows block.
echo "Fetching $UCD_SOURCE"
curl -fsSL "$UCD_SOURCE" | REFS_OUT="$TMP_REFS" perl -ne '
  BEGIN {
    # target blocks, each [lo, hi, category word folded into the haystack]
    @ranges = (
      [0x00A1,0x00BF,"symbol punctuation"],
      [0x00C0,0x00FF,"latin letter accent"],
      [0x0100,0x024F,"latin letter accent"],
      [0x02B0,0x02FF,"modifier letter"],
      [0x0370,0x03FF,"greek letter"],
      [0x0400,0x04FF,"cyrillic letter"],
      [0x2000,0x206F,"punctuation"],
      [0x2070,0x209F,"superscript subscript number"],
      [0x20A0,0x20BF,"currency money"],
      [0x2100,0x214F,"letterlike symbol"],
      [0x2150,0x218F,"fraction roman numeral number"],
      [0x2190,0x21FF,"arrow"],
      [0x2200,0x22FF,"math"],
      [0x2300,0x23FF,"technical symbol"],
      [0x2460,0x24FF,"circled enclosed number letter"],
      [0x2500,0x257F,"box drawing line"],
      [0x2580,0x259F,"block shade"],
      [0x25A0,0x25FF,"geometric shape"],
      [0x2600,0x26FF,"symbol"],
      [0x2700,0x27BF,"dingbat symbol"],
      [0x27C0,0x27EF,"math"],
      [0x27F0,0x27FF,"arrow"],
      [0x2800,0x28FF,"braille"],
      [0x2900,0x297F,"arrow"],
      [0x2980,0x29FF,"math"],
      [0x2A00,0x2AFF,"math"],
      [0x2B00,0x2BFF,"symbol arrow shape"],
      [0x3000,0x303F,"cjk punctuation"],
      [0x3040,0x309F,"hiragana kana japanese"],
      [0x30A0,0x30FF,"katakana kana japanese"],
    );
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
    %assigned = ();
    $rangeStart = -1;
  }
  chomp;
  my @f = split /;/, $_, -1;
  my $name = $f[1];
  my $cp = hex($f[0]);
  # Expand the First and Last markers so the whole compressed range counts as assigned.
  if ($name =~ /, First>$/) { $rangeStart = $cp; next; }
  if ($name =~ /, Last>$/) {
    for (my $x = $rangeStart; $x <= $cp; $x++) { $assigned{$x} = 1 if $x <= 0xFFFF; }
    $rangeStart = -1;
    next;
  }
  $assigned{$cp} = 1 if $cp <= 0xFFFF;
  # Candidate selection. Skip control and marker names, keep only real standalone glyph
  # categories, then require a target block.
  next if $name =~ /^</;
  next unless $f[2] =~ /^[LNPS]/;
  my $cat = "";
  for my $r (@ranges) { if ($cp >= $r->[0] && $cp <= $r->[1]) { $cat = $r->[2]; last; } }
  next if $cat eq "";
  my $s = $syn{$cp} // "";
  print "$cp\t$cat\t$name\t$s\n";
  END {
    # The box references, every unassigned BMP codepoint above the control range, minus
    # the surrogates which are not renderable. The render filter samples these.
    if ($ENV{REFS_OUT}) {
      open(my $rf, ">", $ENV{REFS_OUT}) or die "cannot open REFS_OUT: $!";
      for (my $u = 0x21; $u <= 0xFFFF; $u++) {
        next if $u >= 0xD800 && $u <= 0xDFFF;
        print $rf "$u\n" unless $assigned{$u};
      }
      close($rf);
    }
  }
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

# Emoji first, then symbol candidates, into one list, then the render filter drops the
# boxes and writes the final data.json. Each row is tagged with its source, t is e for an
# emoji and s for a symbol, so the row stays self describing and the picker can rank every
# emoji above every symbol without guessing the kind at runtime. The filter carries whole
# rows through, so the tag survives into data.json.
#
# A codepoint can live in both sources at once, an emoji default glyph like the check mark
# or a zodiac sign also sits in a symbol block, which would list the same glyph twice. So
# after tagging, the list is deduplicated by glyph keeping the first occurrence. Emoji lead
# the list, so the emoji copy always wins and the redundant symbol copy is dropped, which
# also spares the render filter from drawing that glyph twice.
jq -s '
  ([.[0][] | . + {t:"e"}] + [.[1][] | . + {t:"s"}])
  | reduce .[] as $x ({seen:{}, out:[]};
      if .seen[$x.e] then . else .seen += {($x.e): true} | .out += [$x] end)
  | .out
' "$TMP_EMOJI" "$TMP_SYM" > "$TMP_CAND"
echo "Filtering unrenderable glyphs through Hammerspoon"
# The render pass over several thousand glyphs takes longer than the hs default
# receive timeout of four seconds, so raise it well past the worst case.
hs -t 120 -c "CANDIDATES='$TMP_CAND'; REFS='$TMP_REFS'; OUT='$OUT'; dofile('$FILTER')"

EMOJI_COUNT="$(jq 'length' "$TMP_EMOJI")"
SYM_COUNT="$(jq 'length' "$TMP_SYM")"
TOTAL="$(jq 'length' "$OUT")"
echo "Wrote $TOTAL rows to $OUT, from $EMOJI_COUNT emoji and $SYM_COUNT symbol candidates"
