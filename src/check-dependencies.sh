#!/bin/bash
set -uo pipefail

# Reconcile what the modules declare against what this repository knows how to install and
# against what is actually on this machine.
#
# This script is deliberately dumb. It compares sets and reports, and it never guesses, never
# edits the Brewfile, and never installs anything. Deciding whether something is a real
# dependency, and how a name maps to an install, is judgment that belongs to a person or to
# Claude following the rules in CLAUDE.md. This half only makes the result impossible to drift
# without anyone noticing.
#
# It is module agnostic on purpose. It reads each module's generated manifest and knows no
# module by name, so a future config joins in by writing a manifest and needs no change here.
#
# Structural gaps are errors, because they are defects in the repository and identical on
# every machine. A tool being absent from this particular machine is only a warning, since an
# optional tool may legitimately not be wanted here, and failing on that would teach you to
# ignore the output.
#
# Exit codes. 0 clean, 1 at least one structural gap.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAP="$ROOT/DEPENDENCIES.map"
BREWFILE="$ROOT/Brewfile"
DOTFILES="$ROOT/dotfiles"

errors=0
warnings=0

say()  { printf '%s\n' "$1"; }
err()  { printf '  ERROR  %s\n' "$1"; errors=$((errors + 1)); }
warn() { printf '  WARN   %s\n' "$1"; warnings=$((warnings + 1)); }
info() { printf '  note   %s\n' "$1"; }

# Strip comments and blank lines, and trim each pipe separated field, so every reader below
# works on clean records.
records() {
    [[ -f "$1" ]] || return 0
    awk -F'|' '
        { sub(/^[ \t]+/, ""); }
        /^#/ || /^$/ { next }
        {
            out = "";
            for (i = 1; i <= NF; i++) {
                f = $i;
                gsub(/^[ \t]+|[ \t]+$/, "", f);
                out = out (i > 1 ? "|" : "") f;
            }
            print out;
        }
    ' "$1"
}

field() { echo "$1" | cut -d'|' -f"$2"; }

#-------------------------------------------------------------------------------
# Regenerate every module manifest, so a stale one cannot pass unnoticed
#-------------------------------------------------------------------------------

say "==> Refreshing module manifests"
stale=0
while IFS= read -r collector; do
    module_dir="$(dirname "$collector")"
    module="$(basename "$module_dir")"
    manifest="$module_dir/DEPENDENCIES"
    before="$(mktemp)"
    [[ -f "$manifest" ]] && cp "$manifest" "$before"
    if ! "$collector" >/dev/null 2>&1; then
        err "$module, its dependencies-collect failed to run"
    elif [[ -s "$before" ]] && ! cmp -s "$before" "$manifest"; then
        err "$module, its DEPENDENCIES was stale and has been regenerated, review and commit it"
        stale=$((stale + 1))
    fi
    rm -f "$before"
done < <(find "$DOTFILES" -maxdepth 2 -name dependencies-collect -type f | sort)
[[ $stale -eq 0 ]] && say "  all module manifests current"

#-------------------------------------------------------------------------------
# Read every module manifest into one declared set
#-------------------------------------------------------------------------------

# Every module manifest, plus this layer's own. This layer owns the map and the Brewfile, but
# the tools its setup scripts call are declared like anything else, otherwise they are the one
# category nothing checks. The module name falls out of the directory either way.
manifests=()
while IFS= read -r found_manifest; do
    manifests+=("$found_manifest")
done < <(find "$DOTFILES" -maxdepth 2 -name DEPENDENCIES -type f | sort)
[[ -f "$ROOT/src/DEPENDENCIES" ]] && manifests+=("$ROOT/src/DEPENDENCIES")

declared_names=()
declared_lines=()
for manifest in "${manifests[@]}"; do
    module="$(basename "$(dirname "$manifest")")"
    while IFS= read -r record; do
        [[ -z "$record" ]] && continue
        declared_names+=("$(field "$record" 1)")
        declared_lines+=("$module|$record")
    done < <(records "$manifest")
done

if [[ ${#declared_names[@]} -eq 0 ]]; then
    say ""
    say "No module declares any dependency yet, nothing to reconcile."
    exit 0
fi

has() {
    local needle="$1"; shift
    local item
    for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
    return 1
}

mapped_names=()
while IFS= read -r record; do
    [[ -z "$record" ]] && continue
    mapped_names+=("$(field "$record" 1)")
done < <(records "$MAP")

# What the map says provides a name. Used by the package kind below, which cannot be proven by
# a filesystem probe and has to ask the package manager this layer owns.
map_detail() { records "$MAP" | awk -F'|' -v n="$1" '$1 == n { print $3; exit }'; }

#-------------------------------------------------------------------------------
# Check one, a declared tool with no entry in the install map
#-------------------------------------------------------------------------------

say ""
say "==> Declared tools without an install mapping"
missing_map=0
for name in "${declared_names[@]}"; do
    if ! has "$name" ${mapped_names[@]+"${mapped_names[@]}"}; then
        err "$name is declared by a module but DEPENDENCIES.map does not say where it comes from"
        missing_map=$((missing_map + 1))
    fi
done
[[ $missing_map -eq 0 ]] && say "  every declared tool is mapped"

#-------------------------------------------------------------------------------
# Check two, a mapped tool nothing declares any more
#-------------------------------------------------------------------------------

say ""
say "==> Mapped tools nothing declares"
orphans=0
for name in ${mapped_names[@]+"${mapped_names[@]}"}; do
    if ! has "$name" "${declared_names[@]}"; then
        err "$name is in DEPENDENCIES.map but no module declares it, remove the mapping or the tool"
        orphans=$((orphans + 1))
    fi
done
[[ $orphans -eq 0 ]] && say "  no orphaned mappings"

#-------------------------------------------------------------------------------
# Check three, Brewfile drift in both directions
#-------------------------------------------------------------------------------

say ""
say "==> Brewfile agreement"
brew_needed=()
cask_needed=()
tap_needed=()
while IFS= read -r record; do
    [[ -z "$record" ]] && continue
    name="$(field "$record" 1)"
    origin="$(field "$record" 2)"
    detail="$(field "$record" 3)"
    has "$name" "${declared_names[@]}" || continue
    case "$origin" in
        brew) has "$detail" ${brew_needed[@]+"${brew_needed[@]}"} || brew_needed+=("$detail") ;;
        cask) has "$detail" ${cask_needed[@]+"${cask_needed[@]}"} || cask_needed+=("$detail") ;;
        tap)  has "$detail" ${tap_needed[@]+"${tap_needed[@]}"}  || tap_needed+=("$detail") ;;
    esac
done < <(records "$MAP")

brewfile_has() {
    local kind="$1" name="$2"
    grep -qE "^[[:space:]]*${kind}[[:space:]]+\"${name//\//\\/}\"" "$BREWFILE" 2>/dev/null
}

drift=0
for f in ${brew_needed[@]+"${brew_needed[@]}"}; do
    brewfile_has brew "$f" || { err "the Brewfile has no brew \"$f\", which a declared tool needs"; drift=$((drift + 1)); }
done
for c in ${cask_needed[@]+"${cask_needed[@]}"}; do
    brewfile_has cask "$c" || { err "the Brewfile has no cask \"$c\", which a declared tool needs"; drift=$((drift + 1)); }
done
for t in ${tap_needed[@]+"${tap_needed[@]}"}; do
    brewfile_has brew "$t" || { err "the Brewfile has no brew \"$t\", which a declared tool needs"; drift=$((drift + 1)); }
done
[[ $drift -eq 0 ]] && say "  every mapped formula, cask, and tap has a Brewfile line"

# The other direction is a warning rather than an error, and it names what it finds. The
# Brewfile is also a person's package list, so an entry nothing declares is not automatically a
# defect, it may simply be wanted on this machine. Naming them is what makes the difference
# visible, since a bare count reads as noise and gets ignored.
unclaimed_names=()
while IFS= read -r line; do
    detail="$(echo "$line" | sed -E 's/^[[:space:]]*(brew|cask)[[:space:]]+"([^"]+)".*/\2/')"
    [[ -z "$detail" ]] && continue
    if ! has "$detail" ${brew_needed[@]+"${brew_needed[@]}"} ${cask_needed[@]+"${cask_needed[@]}"} ${tap_needed[@]+"${tap_needed[@]}"}; then
        unclaimed_names+=("$detail")
    fi
done < <(grep -E '^[[:space:]]*(brew|cask)[[:space:]]+"' "$BREWFILE" 2>/dev/null)
if [[ ${#unclaimed_names[@]} -gt 0 ]]; then
    warn "the Brewfile installs $(IFS=', '; echo "${unclaimed_names[*]}"), which nothing declares, so either something should declare it or the Brewfile should drop it"
fi

#-------------------------------------------------------------------------------
# Check four, code reaching around a module's declared door
#-------------------------------------------------------------------------------

say ""
say "==> Declared doors respected"
bypass=0

# A module's resolver is the one place allowed to probe, and it says so by carrying the
# dependency-resolver-door marker. Skipping marked files is what keeps this check module
# agnostic, since the alternative would be naming a spoon here and this layer must not know
# any module's internals.
is_door() { grep -q 'dependency-resolver-door' "$1" 2>/dev/null; }

while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    path="${hit%%:*}"
    is_door "$path" && continue
    # A hardcoded package manager prefix is always a bypass, since a resolved path is what
    # the door hands out and that path differs between Apple Silicon and Intel machines.
    locator="$(echo "$hit" | grep -oE '/(opt/homebrew|usr/local)/bin/[A-Za-z0-9._-]+' | head -1)"
    err "${path#"$ROOT"/} hardcodes $locator, name the tool and let PATH or a resolver find it"
    bypass=$((bypass + 1))
    # Matched anywhere in the line rather than only inside quotes, because a default such as
    # ${MULLVAD:-/usr/local/bin/mullvad} is the same leak and an earlier quote anchored version
    # of this pattern walked straight past one. Every configuration language here is covered,
    # not just the scripted ones, since a path in a conf file is no better.
done < <(grep -rnE '/(opt/homebrew|usr/local)/bin/[A-Za-z0-9._-]+' "$DOTFILES" \
    --include='*.lua' --include='*.sh' --include='*.conf' --include='lfrc' --include='.zshrc*' 2>/dev/null)

while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    path="${hit%%:*}"
    is_door "$path" && continue
    err "${path#"$ROOT"/} probes for a tool with command -v, which is its module's door's job"
    bypass=$((bypass + 1))
done < <(grep -rnE 'hs\.execute\("command -v' "$DOTFILES" --include='*.lua' 2>/dev/null)

# A module naming an install command is the leak this whole split exists to prevent, and it is
# worse than a hardcoded path because it also duplicates an answer this layer already holds
# exactly once, so the two drift apart in silence. Two real ones hid here for a long time, a
# spoon offering to copy a brew line and a generator script telling you to run one, and neither
# earlier check saw either. Both were help text rather than logic, which is why this matches
# every file type under dotfiles. A comment or a subtitle is the same duplicated answer as code.
#
# Only an install verb is matched. `brew --prefix` is a location read rather than an install,
# and two modules legitimately use it to find a file inside a package whose prefix they must
# not know, which tmux/CLAUDE.md records.
INSTALL_VERB='(brew|port) (install|tap )|npm install -g|pip3? install'
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    path="${hit%%:*}"
    content="${hit#*:}"; content="${content#*:}"
    # A backtick span is how prose names a command instead of telling anyone to run it, which
    # is what lets a module's own CLAUDE.md explain this rule by quoting it. Strip every span
    # and retest, so a mention passes and a bare instruction does not. Filtering here rather
    # than in the pattern keeps the pattern one readable list of verbs, and BSD grep has no
    # lookbehind to express it anyway.
    printf '%s' "$content" | sed 's/`[^`]*`//g' | grep -qE "$INSTALL_VERB" || continue
    err "${path#"$ROOT"/} names an install command, only DEPENDENCIES.map and the Brewfile may"
    bypass=$((bypass + 1))
done < <(grep -rnE "$INSTALL_VERB" "$DOTFILES" 2>/dev/null)
[[ $bypass -eq 0 ]] && say "  no code reaches around a declared door"

#-------------------------------------------------------------------------------
# Check five, is each declared tool actually here. A warning, not an error
#-------------------------------------------------------------------------------

say ""
say "==> Present on this machine"
absent=0
for line in "${declared_lines[@]}"; do
    module="$(field "$line" 1)"
    name="$(field "$line" 2)"
    kind="$(field "$line" 3)"
    locator="$(field "$line" 4)"
    policy="$(field "$line" 5)"
    consumer="$(field "$line" 6)"
    ok=1
    case "$kind" in
        path)   command -v "$locator" >/dev/null 2>&1 || ok=0 ;;
        system) [[ -x "$locator" ]] || ok=0 ;;
        app)    [[ -n "$(mdfind -count "kMDItemCFBundleIdentifier == '$locator'" 2>/dev/null | grep -v '^0$')" ]] || ok=0 ;;
        manual) [[ -e "${locator/#\~/$HOME}" ]] || ok=0 ;;
        # A package that ships files rather than a command on PATH, so a configuration loads it
        # by path from wherever the package manager put it. Its prefix differs by machine, and a
        # module must not know it, so presence is proven here by asking the package manager the
        # map names. The locator stays in the manifest to document which file is loaded.
        package)
            detail="$(map_detail "$name")"
            if [[ -z "$detail" ]]; then ok=0; else brew list "$detail" >/dev/null 2>&1 || ok=0; fi
            ;;
        *)      err "$name in $module declares unknown kind '$kind'" ;;
    esac
    if [[ $ok -eq 0 ]]; then
        warn "$name is not installed, $module/$consumer runs without it ($policy)"
        absent=$((absent + 1))
    fi
done
[[ $absent -eq 0 ]] && say "  every declared tool is installed"

#-------------------------------------------------------------------------------

say ""
if [[ $errors -gt 0 ]]; then
    say "Dependency check failed, $errors error(s) and $warnings warning(s)."
    say "Errors are repository defects and are the same on every machine. Warnings are only"
    say "about this machine and are safe to leave."
    exit 1
fi
say "Dependency check passed, $warnings warning(s)."
exit 0
