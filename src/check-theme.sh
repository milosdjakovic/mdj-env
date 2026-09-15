#!/bin/bash
set -uo pipefail

# Turn the one palette this repository declares into every tool's own theme file, and
# refuse to let any of those files drift from it.
#
# This is the composition root for colour, the same shape check-dependencies.sh is for
# tools. It reads theme/active.toml for which palette paints each half and whether the
# machine follows the system or is held, resolves every role in theme/VOCABULARY to a hex
# value for each half, then finds every theme-emit under dotfiles by name, hands each one its
# own map already resolved, and lets it write its own files. It knows no tool by name, so a
# new tool joins by adding a map and an emitter at its package root and nothing changes here.
#
# What it enforces, each as an error, because each is a repository defect and the same on
# every machine. A palette that does not answer a required role. A role that points at a
# colour the palette does not define. A map that names anything but a role. A hex value
# anywhere outside theme/palettes. And a generated file that came out different from what is
# on disk, which is reported exactly the way a stale DEPENDENCIES is, regenerated and named,
# so the person reviews it and commits it and the next run is clean.
#
# It has no dependency beyond bash and awk on purpose. The system Python on a fresh Mac is
# 3.9 and cannot read TOML, and every other reader is something Homebrew would have to
# install first, so a palette that needed one would be the one thing on the machine that
# could not be checked before setup had run. The subset of TOML this reads is small and is
# written down in theme/CLAUDE.md, and the reader refuses a line outside it rather than
# guessing.
#
# Exit codes. 0 clean, 1 at least one error.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
THEME="$ROOT/theme"
DOTFILES="$ROOT/dotfiles"
VOCABULARY="$THEME/VOCABULARY"
ACTIVE="$THEME/active.toml"
PALETTES="$THEME/palettes"

errors=0
warnings=0

say()  { printf '%s\n' "$1"; }
err()  { printf '  ERROR  %s\n' "$1"; errors=$((errors + 1)); }
warn() { printf '  WARN   %s\n' "$1"; warnings=$((warnings + 1)); }

# A generator says which of two things went wrong by its exit status, the same convention the
# dependency collectors use. 2 means it cannot run on this machine, a warning. Any other
# nonzero means what it was given is wrong, an error.
CANNOT_RUN_HERE=2

#-------------------------------------------------------------------------------
# Reading the files
#-------------------------------------------------------------------------------

# The TOML subset, flattened to one record per line, section TAB key TAB raw value. A
# comment is a hash preceded by the start of the line or by whitespace and not inside quotes,
# which matters because every colour in these files is a quoted string starting with a hash.
# Anything the subset does not cover is reported with its line number and the read fails,
# since a reader that guesses at a line it does not understand is how a colour goes missing
# without anyone being told.
toml_records() {
    awk '
        {
            # Strip a trailing comment, respecting quotes.
            line = $0; out = ""; inq = 0
            for (i = 1; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == "\"") inq = !inq
                if (c == "#" && !inq && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/)) break
                out = out c
            }
            line = out
            sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
            if (line == "") next
            if (line ~ /^\[[A-Za-z0-9_.-]+\]$/) {
                section = substr(line, 2, length(line) - 2)
                next
            }
            why = ""
            if (line !~ /^[A-Za-z0-9_.-]+[ \t]*=[ \t]*.+$/) {
                why = "not a key = value line"
            } else {
                key = line; sub(/[ \t]*=.*$/, "", key)
                val = line; sub(/^[^=]*=[ \t]*/, "", val)
                # An inline table may not hold another one. That is the edge of the subset and
                # the thing table_field cannot read, so it is refused here rather than misread there.
                if (val ~ /^\{.*\}$/ && val ~ /^\{.*\{/) {
                    why = "a nested inline table, which is outside the subset"
                } else if (val ~ /^"[^"]*"$/ || val ~ /^-?[0-9]+(\.[0-9]+)?$/ || val ~ /^\{.*\}$/ || val ~ /^[A-Za-z0-9_-]+$/) {
                    printf("%s\t%s\t%s\n", section, key, val)
                    next
                } else {
                    why = "a value outside the subset, quoted string, number, bare name, or inline table"
                }
            }
            printf("line %d, %s: %s\n", NR, why, $0) > "/dev/stderr"
            bad = 1
        }
        END { if (bad) exit 1 }
    ' "$1"
}

# One raw value out of a records stream, by section and key. Empty when absent.
lookup() {
    awk -F'\t' -v s="$2" -v k="$3" '$1 == s && $2 == k { print $3; exit }' "$1"
}

# A quoted string with its quotes removed, or the bare value as it was.
unquote() {
    local v="$1"
    v="${v#\"}"; v="${v%\"}"
    printf '%s' "$v"
}

# One field out of an inline table, { color = "purple", alpha = 0.14 }, by key. Arrays come
# back as their items separated by spaces, so ["gray", "white"] reads as gray white.
table_field() {
    printf '%s' "$1" | awk -v k="$2" '
        {
            s = $0
            sub(/^\{[ \t]*/, "", s); sub(/[ \t]*\}$/, "", s)
            # Split on commas, then rejoin any array an inner comma cut in half.
            n = split(s, parts, ",")
            joined = ""; depth = 0; cur = ""
            for (i = 1; i <= n; i++) {
                cur = (cur == "" ? parts[i] : cur "," parts[i])
                o = gsub(/\[/, "[", cur); c = gsub(/\]/, "]", cur)
                if (o == c) { items[++m] = cur; cur = "" }
            }
            for (i = 1; i <= m; i++) {
                f = items[i]; sub(/^[ \t]+/, "", f); sub(/[ \t]+$/, "", f)
                name = f; sub(/[ \t]*=.*$/, "", name)
                if (name != k) continue
                v = f; sub(/^[^=]*=[ \t]*/, "", v)
                gsub(/[\[\]"]/, "", v); gsub(/,[ \t]*/, " ", v)
                print v; exit
            }
        }'
}

#-------------------------------------------------------------------------------
# Colour arithmetic
#-------------------------------------------------------------------------------

# a*top + (1-a)*under, per channel, which is compositing and is also mixing. Every operation
# below is this one line with different arguments, which is why alpha and mix are one thing.
blend() {
    awk -v top="$1" -v under="$2" -v a="$3" '
        # BSD awk has no strtonum, so a hex pair is read by position in the digit string.
        function ch(h, i,    d, hi, lo) {
            d = "0123456789abcdef"
            hi = index(d, substr(h, i, 1)) - 1
            lo = index(d, substr(h, i + 1, 1)) - 1
            return hi * 16 + lo
        }
        BEGIN {
            t = substr(top, 2); u = substr(under, 2)
            printf("#%02x%02x%02x\n",
                int(a * ch(t, 1) + (1 - a) * ch(u, 1) + 0.5),
                int(a * ch(t, 3) + (1 - a) * ch(u, 3) + 0.5),
                int(a * ch(t, 5) + (1 - a) * ch(u, 5) + 0.5))
        }'
}

#-------------------------------------------------------------------------------
# Resolving a half
#-------------------------------------------------------------------------------

# Every role in the vocabulary as role TAB hex, for one palette and one half. A role is
# answered under [roles.<half>] first and [roles] second, by a colour name or by a rule over
# colour names. Errors are named with the palette and the role so the fix is one line away.
resolve_half() {
    local records="$1" palette="$2" half="$3" out="$4"
    : >"$out"
    local role policy raw colour hex top under amount a b
    while read -r role policy _; do
        [[ -z "$role" || "$role" == \#* ]] && continue
        raw="$(lookup "$records" "roles.$half" "$role")"
        [[ -z "$raw" ]] && raw="$(lookup "$records" "roles" "$role")"
        if [[ -z "$raw" ]]; then
            [[ "$policy" == required ]] && err "$palette does not answer the required role $role"
            continue
        fi
        if [[ "$raw" == \{* ]]; then
            # darken and lighten are tested before alpha, because all three name a color and
            # only the first two carry their own amount. Tested the other way round, a darken
            # rule was read as alpha with no amount, and the branch was never reached.
            if [[ -n "$(table_field "$raw" darken)" || -n "$(table_field "$raw" lighten)" ]]; then
                colour="$(table_field "$raw" color)"
                under="$(unquote "$(lookup "$records" "colors.$half" "$colour")")"
                [[ -z "$under" ]] && { err "$palette, role $role names a colour $colour that [colors.$half] does not define"; continue; }
                if [[ -n "$(table_field "$raw" darken)" ]]; then
                    hex="$(blend "#000000" "$under" "$(table_field "$raw" darken)")"
                else
                    hex="$(blend "#ffffff" "$under" "$(table_field "$raw" lighten)")"
                fi
            elif [[ -n "$(table_field "$raw" color)" ]]; then
                colour="$(table_field "$raw" color)"
                amount="$(table_field "$raw" alpha)"
                top="$(unquote "$(lookup "$records" "colors.$half" "$colour")")"
                under="$(resolved_role "$out" background)"
                [[ -z "$top" ]] && { err "$palette, role $role names a colour $colour that [colors.$half] does not define"; continue; }
                [[ -z "$under" ]] && { err "$palette, role $role uses alpha but background is not resolved before it, list background earlier in the vocabulary"; continue; }
                [[ -z "$amount" ]] && { err "$palette, role $role names a colour and no alpha, darken or lighten amount"; continue; }
                hex="$(blend "$top" "$under" "$amount")"
            elif [[ -n "$(table_field "$raw" mix)" ]]; then
                read -r a b <<<"$(table_field "$raw" mix)"
                amount="$(table_field "$raw" amount)"
                top="$(unquote "$(lookup "$records" "colors.$half" "$b")")"
                under="$(unquote "$(lookup "$records" "colors.$half" "$a")")"
                [[ -z "$top" || -z "$under" ]] && { err "$palette, role $role mixes $a and $b and [colors.$half] does not define both"; continue; }
                hex="$(blend "$top" "$under" "$amount")"
            else
                err "$palette, role $role is a rule this reader does not know, it knows color with alpha, mix with amount, and darken or lighten"
                continue
            fi
        else
            colour="$(unquote "$raw")"
            hex="$(unquote "$(lookup "$records" "colors.$half" "$colour")")"
            [[ -z "$hex" ]] && { err "$palette, role $role points at $colour, which [colors.$half] does not define"; continue; }
        fi
        [[ "$hex" =~ ^#[0-9a-f]{6}$ ]] || { err "$palette, role $role resolved to $hex, which is not a six digit hex"; continue; }
        printf '%s\t%s\n' "$role" "$hex" >>"$out"
    done <"$VOCABULARY"
}

resolved_role() { awk -F'\t' -v r="$2" '$1 == r { print $2; exit }' "$1"; }

#-------------------------------------------------------------------------------
# The active selection
#-------------------------------------------------------------------------------

say "==> Reading the palette"
[[ -f "$VOCABULARY" ]] || { err "theme/VOCABULARY is missing"; exit 1; }
[[ -f "$ACTIVE" ]]     || { err "theme/active.toml is missing"; exit 1; }

active="$(mktemp)"
if ! toml_records "$ACTIVE" >"$active" 2>"$active.err"; then
    err "theme/active.toml has a line outside the subset this reader accepts"
    while IFS= read -r line; do say "         $line"; done <"$active.err"
    exit 1
fi
mode="$(unquote "$(lookup "$active" "" mode)")"
dark_name="$(unquote "$(lookup "$active" "" dark)")"
light_name="$(unquote "$(lookup "$active" "" light)")"
[[ -z "$mode" ]] && mode=system
case "$mode" in
    system|dark|light) ;;
    *) err "theme/active.toml, mode is $mode and must be system, dark or light"; exit 1 ;;
esac
[[ -z "$dark_name" ]]  && { err "theme/active.toml names no dark palette"; exit 1; }
[[ -z "$light_name" ]] && { err "theme/active.toml names no light palette"; exit 1; }

# mode is resolved here and nowhere else. Held to one half, both outputs are written from that
# palette's that half, so every tool keeps asking which half it is on and both answers agree.
case "$mode" in
    system) dark_src="$dark_name:dark";  light_src="$light_name:light" ;;
    dark)   dark_src="$dark_name:dark";  light_src="$dark_name:dark"   ;;
    light)  dark_src="$light_name:light"; light_src="$light_name:light" ;;
esac
say "  mode $mode, dark half from $dark_src, light half from $light_src"

load_palette() {
    local name="$1" out="$2"
    local file="$PALETTES/$name.toml"
    [[ -f "$file" ]] || { err "theme/active.toml names the palette $name and theme/palettes/$name.toml does not exist"; return 1; }
    if ! toml_records "$file" >"$out" 2>"$out.err"; then
        err "theme/palettes/$name.toml has a line outside the subset this reader accepts"
        while IFS= read -r line; do say "         $line"; done <"$out.err"
        return 1
    fi
    # The one place a hex value may live. Every colour under [colors.*] must be one, and
    # nothing else in the file may be, which keeps a rule from smuggling a literal in.
    local line
    while IFS= read -r line; do err "$line"; done < <(awk -F'\t' -v p="$name" '
        $1 ~ /^colors\./ && $3 !~ /^"#[0-9a-f]{6}"$/ { printf("theme/palettes/%s.toml, [%s] %s is %s, and a colour must be a lowercase six digit hex\n", p, $1, $2, $3) }
        $1 !~ /^colors\./ && $3 ~ /#[0-9a-fA-F]{3,6}/ { printf("theme/palettes/%s.toml, [%s] %s carries a hex value, and only [colors.*] may\n", p, $1, $2) }
    ' "$out")
    return 0
}

dark_pal="$(mktemp)"; light_pal="$(mktemp)"
load_palette "${dark_src%%:*}" "$dark_pal"   || exit 1
load_palette "${light_src%%:*}" "$light_pal" || exit 1

dark_roles="$(mktemp)"; light_roles="$(mktemp)"
resolve_half "$dark_pal"  "${dark_src%%:*}"  "${dark_src##*:}"  "$dark_roles"
resolve_half "$light_pal" "${light_src%%:*}" "${light_src##*:}" "$light_roles"
[[ $errors -gt 0 ]] && { say "Theme check failed, $errors error(s) reading the palette."; exit 1; }
say "  $(wc -l <"$dark_roles" | tr -d ' ') roles resolved for each half"

# --show prints what every role resolved to and stops, which is the answer to "what is
# primary right now" without reading a palette file and doing the arithmetic by hand.
if [[ "${1:-}" == "--show" ]]; then
    say ""
    printf '  %-12s %-9s %-9s\n' role dark light
    while IFS=$'\t' read -r role dhex; do
        printf '  %-12s %-9s %-9s\n' "$role" "$dhex" "$(resolved_role "$light_roles" "$role")"
    done <"$dark_roles"
    rm -f "$active" "$active.err" "$dark_pal" "$dark_pal.err" "$light_pal" "$light_pal.err" "$dark_roles" "$light_roles"
    exit 0
fi

#-------------------------------------------------------------------------------
# Every tool that paints
#-------------------------------------------------------------------------------

# A tool's map resolved to its own keys, key TAB hex, for one half. A map names roles and
# nothing else, and a key under [dark] or [light] answers only that half. The map may not
# carry a hex, a colour name, or anything that is not a role in the vocabulary, and each of
# those is named with the file and the key.
resolve_map() {
    local map="$1" half="$2" roles="$3" out="$4" pkg="$5"
    : >"$out"
    local rec; rec="$(mktemp)"
    if ! toml_records "$map" >"$rec" 2>"$rec.err"; then
        err "$pkg/theme-map has a line outside the subset this reader accepts"
        while IFS= read -r line; do say "         $line"; done <"$rec.err"
        rm -f "$rec" "$rec.err"; return 1
    fi
    # A key under the half's own section overrides the same key at top level, the way
    # [roles.light] overrides [roles] in a palette. A key written twice in one section is an
    # error rather than a silent pick, since which one won would depend on sort order.
    local dup
    dup="$(awk -F'\t' -v h="$half" '($1 == "" || $1 == h) { c[$1 "\t" $2]++ } END { for (k in c) if (c[k] > 1) { split(k, p, "\t"); print p[2] " under [" (p[1] == "" ? "top level" : p[1]) "]" } }' "$rec")"
    if [[ -n "$dup" ]]; then
        while IFS= read -r line; do err "$pkg/theme-map, $line is written twice"; done <<<"$dup"
        rm -f "$rec" "$rec.err"; return 1
    fi
    local key role hex
    while IFS=$'\t' read -r key role; do
        role="$(unquote "$role")"
        if [[ "$role" =~ ^# ]]; then
            err "$pkg/theme-map, $key is a hex value, and a map may only name a role"
            continue
        fi
        hex="$(resolved_role "$roles" "$role")"
        if [[ -z "$hex" ]]; then
            if grep -q "^$role[[:space:]]" "$VOCABULARY"; then
                err "$pkg/theme-map, $key names the role $role, which the active palette does not answer"
            else
                err "$pkg/theme-map, $key names $role, which is not a role in theme/VOCABULARY"
            fi
            continue
        fi
        printf '%s\t%s\n' "$key" "$hex" >>"$out"
    done < <(awk -F'\t' -v h="$half" '$1 == h { v[$2] = $3; seen[$2] = 1 } $1 == "" && !seen[$2] { v[$2] = $3 } END { for (k in v) print k "\t" v[k] }' "$rec" | sort)
    rm -f "$rec" "$rec.err"
}

say "==> Writing every tool's theme"
stale=0
unchecked=0
failed=0
count=0
while IFS= read -r emit; do
    pkg_dir="$(dirname "$emit")"
    pkg="$(basename "$pkg_dir")"
    map="$pkg_dir/theme-map"
    count=$((count + 1))
    [[ -f "$map" ]] || { err "$pkg has a theme-emit and no theme-map beside it"; continue; }
    [[ -x "$emit" ]] || { err "$pkg/theme-emit is not executable"; continue; }

    # The map's [dark] or [light] section follows the half the palette was read from, not the
    # slot being written. On a held mode both outputs come from one half, and a light slot
    # written from the dark palette has to read the dark section too, or ANSI black lands on
    # the ink because the map's light section said so. Found by holding the mode and
    # diffing the two Ghostty files, which should have been identical and were not.
    dmap="$(mktemp)"; lmap="$(mktemp)"
    resolve_map "$map" "${dark_src##*:}"  "$dark_roles"  "$dmap" "$pkg"
    resolve_map "$map" "${light_src##*:}" "$light_roles" "$lmap" "$pkg"

    # The emitter lists what it owns, the files are snapshotted, it writes, and any file that
    # came out different is stale, exactly how a regenerated DEPENDENCIES is reported.
    owned="$("$emit" --list 2>/dev/null)"
    [[ -z "$owned" ]] && { err "$pkg/theme-emit --list names no files"; rm -f "$dmap" "$lmap"; continue; }
    snap="$(mktemp -d)"
    i=0
    while IFS= read -r f; do
        i=$((i + 1)); [[ -f "$pkg_dir/$f" ]] && cp "$pkg_dir/$f" "$snap/$i"
    done <<<"$owned"

    complaint="$(mktemp)"
    (cd "$pkg_dir" && ./theme-emit "$dmap" "$lmap" "$mode") >/dev/null 2>"$complaint"
    status=$?
    if [[ $status -eq $CANNOT_RUN_HERE ]]; then
        warn "$pkg, its theme could not be regenerated on this machine, so a stale one would not be caught here"
        while IFS= read -r line; do say "         $line"; done <"$complaint"
        unchecked=$((unchecked + 1))
    elif [[ $status -ne 0 ]]; then
        err "$pkg, its theme-emit failed"
        failed=$((failed + 1))
        while IFS= read -r line; do say "         $line"; done <"$complaint"
    else
        i=0
        while IFS= read -r f; do
            i=$((i + 1))
            if [[ ! -f "$pkg_dir/$f" ]]; then
                err "$pkg/theme-emit lists $f and did not write it"
            elif [[ -f "$snap/$i" ]] && ! cmp -s "$snap/$i" "$pkg_dir/$f"; then
                err "$pkg, $f was stale and has been regenerated, review and commit it"
                stale=$((stale + 1))
            elif [[ ! -f "$snap/$i" ]]; then
                err "$pkg, $f is new and has been generated, review and commit it"
                stale=$((stale + 1))
            fi
            # The banner may sit anywhere in the file rather than in its first lines, because an
            # emitter that owns only a region of a hand written file, herdr's, puts the warning
            # at the region, which is where a person editing it would look. A file written whole
            # still opens with it.
            if ! grep -q "Generated by theme-emit" "$pkg_dir/$f"; then
                err "$pkg, $f does not carry the generated banner, so nothing warns a person off editing it"
            fi
        done <<<"$owned"
    fi
    rm -rf "$snap" "$dmap" "$lmap" "$complaint"
done < <(find "$DOTFILES" -maxdepth 2 -name theme-emit -type f | sort)
[[ $count -eq 0 ]] && warn "no theme-emit found under dotfiles, so no tool is painted from the palette yet"
[[ $stale -eq 0 && $unchecked -eq 0 && $failed -eq 0 && $count -gt 0 ]] && say "  every generated theme is current, $count tool(s)"

#-------------------------------------------------------------------------------
# Hex outside the palette
#-------------------------------------------------------------------------------

# A hex colour anywhere in a map or an emitter is a second owner of a value the palette
# already holds, which is the drift this whole layer exists to end. The generated files
# carry hex on purpose and are excluded by their banner.
say "==> Hex values outside the palette"
leaks=0
while IFS= read -r hit; do
    path="${hit%%:*}"
    err "${path#"$ROOT"/} carries a hex value, and only theme/palettes may"
    leaks=$((leaks + 1))
done < <(grep -rnE '#[0-9a-fA-F]{6}\b' "$DOTFILES"/*/theme-map "$DOTFILES"/*/theme-emit "$THEME/active.toml" "$VOCABULARY" 2>/dev/null)
[[ $leaks -eq 0 ]] && say "  none"

rm -f "$active" "$active.err" "$dark_pal" "$dark_pal.err" "$light_pal" "$light_pal.err" "$dark_roles" "$light_roles"

say ""
if [[ $errors -gt 0 ]]; then
    say "Theme check failed, $errors error(s), $warnings warning(s)."
    exit 1
fi
say "Theme check passed, $warnings warning(s)."
exit 0
