#!/bin/bash
set -e

# Build every declared fork at its pinned commit and install it where the declaration says.
#
# This script knows git, a cache directory and a stamp file. It does not know what language any
# fork is written in, what its toolchain is called, or what its binary is named. Each fork
# ships a build executable at its own root and this finds it by name, the same way
# check-dependencies.sh finds a manifest without knowing the modules. Adding a fork is a
# directory under forks/ and no edit here.
#
# forks/CLAUDE.md carries the contract and the rule for when a fork can go.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE="$HOME/.cache/mdj-env"

fail=0

# A declaration is key | value, comments and blank lines ignored, and a key may repeat.
decl_first() {
    awk -F'|' -v key="$2" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        { k = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", k) }
        k == key { v = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit }
    ' "$1"
}

echo "==> Building carried forks..."

shopt -s nullglob
for declaration in "$REPO_ROOT"/forks/*/FORK; do
    dir="$(dirname "$declaration")"
    name="$(decl_first "$declaration" name)"
    fork_url="$(decl_first "$declaration" fork)"
    pin="$(decl_first "$declaration" pin)"
    dest_rel="$(decl_first "$declaration" dest)"

    if [[ -z "$name" || -z "$fork_url" || -z "$pin" || -z "$dest_rel" ]]; then
        echo "  ERROR ${dir#$REPO_ROOT/}/FORK is missing one of name, fork, pin, dest" >&2
        fail=1
        continue
    fi

    # A destination is written relative to the home directory, never absolute, so no
    # declaration carries a path that is only true on one machine.
    dest="$HOME/$dest_rel"
    build="$dir/build"
    if [[ ! -x "$build" ]]; then
        echo "  ERROR $name declares a fork but ships no executable build script" >&2
        fail=1
        continue
    fi

    worktree="$CACHE/$name-build"
    stamp="$CACHE/$name.stamp"

    # The stamp carries the pin and a checksum of what was installed, so a binary that
    # something else has replaced is rebuilt rather than trusted. herdr offers its own updates
    # and Homebrew owns a copy of the same name, and either one landing here would quietly undo
    # the patch, which is the whole reason the checksum is in the stamp and not just the pin.
    if [[ -x "$dest" && -f "$stamp" ]]; then
        read -r stamped_pin stamped_sum < "$stamp" || true
        current_sum="$(shasum -a 256 "$dest" | cut -d' ' -f1)"
        if [[ "$stamped_pin" == "$pin" && "$stamped_sum" == "$current_sum" ]]; then
            echo "  $name is already built at ${pin:0:7}"
            continue
        fi
        if [[ "$stamped_pin" == "$pin" ]]; then
            echo "  $name at ${pin:0:7} was replaced since it was built, building it again"
        fi
    fi

    mkdir -p "$(dirname "$worktree")"
    if [[ -d "$worktree/.git" ]]; then
        git -C "$worktree" remote set-url origin "$fork_url"
        git -C "$worktree" fetch --quiet origin
    else
        rm -rf "$worktree"
        git clone --quiet "$fork_url" "$worktree"
    fi

    # Hard reset rather than checkout, so nothing an interrupted run left behind survives into
    # this one and turns into a conflict nobody asked for.
    git -C "$worktree" reset --hard --quiet "$pin"
    git -C "$worktree" clean -fdq

    echo "  $name at ${pin:0:7}"
    if ! "$build" "$worktree" "$dest"; then
        echo "  ERROR $name failed to build" >&2
        fail=1
        continue
    fi

    if [[ ! -x "$dest" ]]; then
        echo "  ERROR $name built but nothing was installed at $dest_rel" >&2
        fail=1
        continue
    fi

    mkdir -p "$(dirname "$stamp")"
    printf '%s %s\n' "$pin" "$(shasum -a 256 "$dest" | cut -d' ' -f1)" > "$stamp"
    echo "  $name installed at $dest_rel"
done

exit "$fail"
