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

# A collector says which of two things went wrong by its exit status, and this layer needs the
# distinction rather than one undifferentiated failure. Status 2 means it cannot run on THIS
# machine, a tool of its own is absent, which is a machine fact and so a warning here. Any other
# nonzero status means the declarations it read are wrong, which is a repository defect and
# identical on every machine, so an error.
#
# Its own diagnostics are shown rather than discarded. They used to go to /dev/null, which was
# nearly harmless while a collector could only fail by being unreadable, and became a real loss
# once one of them started reporting which plugin and which field is wrong. A failure that names
# nothing is a failure somebody has to reproduce by hand.
CANNOT_RUN_HERE=2

say "==> Refreshing module manifests"
stale=0
unchecked=0
while IFS= read -r collector; do
    module_dir="$(dirname "$collector")"
    module="$(basename "$module_dir")"
    manifest="$module_dir/DEPENDENCIES"
    before="$(mktemp)"
    complaint="$(mktemp)"
    [[ -f "$manifest" ]] && cp "$manifest" "$before"
    "$collector" >/dev/null 2>"$complaint"
    status=$?
    if [[ $status -eq $CANNOT_RUN_HERE ]]; then
        warn "$module, its manifest could not be regenerated on this machine, so a stale one would not be caught here"
        while IFS= read -r line; do say "         $line"; done <"$complaint"
        unchecked=$((unchecked + 1))
    elif [[ $status -ne 0 ]]; then
        err "$module, its dependencies-collect failed to run"
        while IFS= read -r line; do say "         $line"; done <"$complaint"
    elif [[ -s "$before" ]] && ! cmp -s "$before" "$manifest"; then
        err "$module, its DEPENDENCIES was stale and has been regenerated, review and commit it"
        stale=$((stale + 1))
    fi
    rm -f "$before" "$complaint"
done < <(find "$DOTFILES" -maxdepth 2 -name dependencies-collect -type f | sort)
# Only claimed when every module was actually regenerated. A module that could not be checked has
# no business being counted as current, which is the difference between a check and a reassurance.
[[ $stale -eq 0 && $unchecked -eq 0 ]] && say "  all module manifests current"

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

#-------------------------------------------------------------------------------
# Check one and a half, a declaration that states its own origin and disagrees
#-------------------------------------------------------------------------------

# A declaration may state where its tool comes from, in the two trailing columns of a module
# manifest, because a plugin that travels to another machine has to carry that answer with it
# and cannot rely on this repository's map existing at all. So the same answer is written in
# two places on purpose, and the only thing that makes that safe is proving they agree.
#
# The origin kind is compared always. The detail is compared only for the three package manager
# origins, where it names a formula, a cask, or a tap and a difference is a real defect. For the
# rest it is a sentence a person wrote for a person, so macOS and the system are the same answer
# said twice and comparing them would report a defect that is not one.
say ""
say "==> Declared origins against the map"
stated_names=()
stated_origins=()
stated_where=()
for line in "${declared_lines[@]}"; do
    stated_origin="$(field "$line" 8)"
    [[ -z "$stated_origin" ]] && continue
    stated_names+=("$(field "$line" 2)")
    stated_origins+=("$stated_origin|$(field "$line" 9)")
    stated_where+=("$(field "$line" 1)/$(field "$line" 6)")
done

origin_conflicts=0
i=0
while [[ $i -lt ${#stated_names[@]} ]]; do
    name="${stated_names[$i]}"
    origin="${stated_origins[$i]%%|*}"
    detail="${stated_origins[$i]#*|}"
    where="${stated_where[$i]}"
    map_record="$(records "$MAP" | awk -F'|' -v n="$name" '$1 == n { print; exit }')"
    if [[ -n "$map_record" ]]; then
        map_origin="$(field "$map_record" 2)"
        map_value="$(field "$map_record" 3)"
        if [[ "$origin" != "$map_origin" ]]; then
            err "$where states $name comes from $origin but DEPENDENCIES.map says $map_origin, and one of the two is wrong"
            origin_conflicts=$((origin_conflicts + 1))
        elif [[ "$origin" == "brew" || "$origin" == "cask" || "$origin" == "tap" ]] \
            && [[ "$detail" != "$map_value" ]]; then
            err "$where states $name is $origin $detail but DEPENDENCIES.map says $map_value"
            origin_conflicts=$((origin_conflicts + 1))
        fi
    fi
    # And against every other declaration of the same tool, since two plugins needing one tool
    # each state its origin and nothing else would notice them drifting apart.
    j=$((i + 1))
    while [[ $j -lt ${#stated_names[@]} ]]; do
        if [[ "${stated_names[$j]}" == "$name" ]]; then
            other_origin="${stated_origins[$j]%%|*}"
            other_detail="${stated_origins[$j]#*|}"
            if [[ "$other_origin" != "$origin" ]]; then
                err "${stated_where[$j]} states $name comes from $other_origin but $where says $origin"
                origin_conflicts=$((origin_conflicts + 1))
            elif [[ "$origin" == "brew" || "$origin" == "cask" || "$origin" == "tap" ]] \
                && [[ "$other_detail" != "$detail" ]]; then
                err "${stated_where[$j]} states $name is $origin $other_detail but $where says $detail"
                origin_conflicts=$((origin_conflicts + 1))
            fi
        fi
        j=$((j + 1))
    done
    i=$((i + 1))
done
if [[ ${#stated_names[@]} -eq 0 ]]; then
    say "  no declaration states an origin of its own"
elif [[ $origin_conflicts -eq 0 ]]; then
    say "  every stated origin agrees with the map and with every other statement of it"
fi

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
reached=0

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

# Every tool a module actually runs, against what it declares. This is the check the two above
# were reaching for and kept missing, because a line that runs a tool looks like ordinary code
# and names no prefix and no installer. It found nine sites the first time it ran, three of them
# tools nothing in this repository had ever declared, which means the layer that guarantees a
# tool is present had never heard of them.
#
# The command word is taken from the call and reduced to a tool name, so this knows no module
# and no tool and asks two questions in order of how much they matter.
#
# An UNDECLARED tool is an error. Nothing above can guarantee it, nothing says what breaks
# without it, and it is invisible to the map and the Brewfile, which is the whole failure this
# layer exists to prevent.
#
# A declared tool reached at its own fixed path rather than through the door is a warning. It is
# a real discipline break, and worth naming, but a path under /usr/bin is the same on every
# machine, so unlike a Homebrew prefix it costs correctness nowhere. It costs the console line an
# absent tool would otherwise produce.
#
# A declared tool of kind path invoked as a bare word is an error again, because that resolves
# against whatever PATH the process happens to carry, and Hammerspoon's own carries none of the
# places a package manager installs into.
#
# What this cannot see, stated rather than left for somebody to discover. A call whose first
# argument is a variable is invisible, and that is the correct shape anyway, since a resolved path
# arrives in one. A call split across lines is invisible, because grep works a line at a time. And
# where two calls share one line only the last is read, since the pattern is greedy. The first two
# are acceptable, the third is a genuine hole and the reason it stays is that no line in this tree
# has two calls on it today. If one appears, this check goes quiet about the first of them.
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    path="${hit%%:*}"
    is_door "$path" && continue
    content="${hit#*:}"; content="${content#*:}"
    # A commented out call is not an invocation. Without this, an example in a comment is reported
    # as a defect, and a check that cries wolf gets ignored on the day it is right.
    [[ "$(printf '%s' "$content" | sed -E 's/^[[:space:]]+//')" == --* ]] && continue
    invoked="$(printf '%s' "$hit" | sed -E 's/.*(hs\.execute|hs\.task\.new)\("([^" ]+).*/\2/')"
    [[ -z "$invoked" || "$invoked" == "$hit" ]] && continue
    tool="${invoked##*/}"
    kind=""
    for line in "${declared_lines[@]}"; do
        if [[ "$(field "$line" 2)" == "$tool" ]]; then kind="$(field "$line" 3)"; break; fi
    done
    if [[ -z "$kind" ]]; then
        err "${path#"$ROOT"/} runs $tool, which no module declares, so nothing above knows it is needed"
        bypass=$((bypass + 1))
    elif [[ "$invoked" == /* ]]; then
        warn "${path#"$ROOT"/} runs $tool at its fixed path rather than asking the door for it"
        reached=$((reached + 1))
    elif [[ "$kind" == "path" ]]; then
        err "${path#"$ROOT"/} runs $tool as a bare word, which resolves against a PATH that holds no package manager prefix"
        bypass=$((bypass + 1))
    else
        warn "${path#"$ROOT"/} runs $tool by name rather than asking the door for it"
        reached=$((reached + 1))
    fi
done < <(grep -rnE '(hs\.execute|hs\.task\.new)\("[^"]' "$DOTFILES" --include='*.lua' 2>/dev/null)

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
[[ $bypass -eq 0 && $reached -eq 0 ]] && say "  no code reaches around a declared door"
[[ $bypass -eq 0 && $reached -gt 0 ]] && say "  every tool that is run is declared, and $reached of those runs reach around the door"

#-------------------------------------------------------------------------------
# Check five, a plugin reaching for the spoon that hosts it
#-------------------------------------------------------------------------------

# The one seam allowed to name Olm.spoon, since the boundary this check polices is that folder.
# Named once here so the rest of this script stays free of a hardcoded module path.
#
# There used to be a core kind of dependency, and two checks here that reconciled it, a plugin
# declaring a capability from its host spoon's own lib so the composition root would hand it
# over. That kind is retired. It policed plugins reaching into lib back when they were separate
# spoons that could not legitimately see each other, and everything is one bundled spoon now
# where a lib module arrives by injection through a plugin's own configure. So a capability is
# internal structure rather than a dependency, and the map above no longer answers for one.
#
# What survives is the boundary itself, which is the half that was never about installation. No
# file under the plugins folder may reference spoon.Olm at all. A plugin takes what it needs
# through its own configure and never reaches around that door, whatever the name involved.
OLM_SPOON="$DOTFILES/hammerspoon/.hammerspoon/Spoons/Olm.spoon"

say ""
say "==> The plugin boundary"
door_leak=0
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    path="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    err "${path#"$ROOT"/} line $lineno reaches for spoon.Olm directly, a plugin takes what it needs through its own configure and never opens that door itself"
    door_leak=$((door_leak + 1))
done < <(grep -rnE 'spoon\.Olm\b' "$OLM_SPOON/plugins" 2>/dev/null)
[[ $door_leak -eq 0 ]] && say "  no plugin file reaches for spoon.Olm on its own"

#-------------------------------------------------------------------------------
# Check six, is each declared tool actually here. A warning, not an error
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
