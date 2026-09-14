#!/bin/bash
set -e

# Build iris from this account's fork, pinned to one commit.
#
# iris is the only tool here that does not arrive usable from a package manager, and it is
# two defects rather than one. Upstream expands a shell alias and then renders the expansion
# in its suggestions, so with cd aliased to zoxide and ls to eza every row reads "z /path" or
# "eza Brewfile" rather than the word that was typed, and ghost text disappears on those
# commands entirely, since it tests the suggestion against the literal buffer and a row
# beginning with z never has "cd " as a prefix. That is upstream issue 158. Separately, a
# theme is one flat set of colours with no idea what the terminal is painting behind it, so
# the selection bar cannot be a tint of its own page and is dark on a light one.
#
# The fork carries both fixes on their own branches, each one commit above upstream so either
# can be offered back later without being rewritten first. When upstream takes them, this
# script, the go dependency and the manual origin in DEPENDENCIES.map all go away and iris
# becomes an ordinary tap line again.
#
# Updating is deliberate, the way the Neovim lockfile is. Move IRIS_COMMIT, do not track a
# branch, so two machines running this repository build the same binary.
#
# The binary lands in ~/.local/bin because the Homebrew prefix belongs to Homebrew, and a
# hand built binary sitting there is one upgrade away from being silently replaced. For the
# same reason the iris module turns the updater's startup check off.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE="$HOME/.cache/mdj-env/iris-build"
DEST="$HOME/.local/bin/iris"

IRIS_REPO="https://github.com/milosdjakovic/IRIS.git"
IRIS_COMMIT="b8b7ac8bf801eb8a0ca47db2d1c93aa1337bc9b9"
IRIS_VERSION="0.7.0+mdj.${IRIS_COMMIT:0:7}"

echo "==> Building iris from the fork..."

if ! command -v go >/dev/null 2>&1; then
    echo "  go is not on PATH. It is declared in src/DEPENDENCIES and mapped in" >&2
    echo "  DEPENDENCIES.map, so src/install-homebrew-packages.sh is what provides it." >&2
    exit 1
fi

# Report and stop when the binary already matches, so a machine that has it does not spend a
# minute recompiling on every setup run.
if [[ -x "$DEST" ]] && [[ "$("$DEST" version 2>/dev/null)" == "iris $IRIS_VERSION" ]]; then
    echo "  iris $IRIS_VERSION already built"
    exit 0
fi

mkdir -p "$(dirname "$WORKTREE")" "$(dirname "$DEST")"

if [[ -d "$WORKTREE/.git" ]]; then
    git -C "$WORKTREE" remote set-url origin "$IRIS_REPO"
    git -C "$WORKTREE" fetch --quiet origin
else
    rm -rf "$WORKTREE"
    git clone --quiet "$IRIS_REPO" "$WORKTREE"
fi

# Hard reset rather than checkout, so anything left by an interrupted run cannot survive into
# this one and turn into a conflict nobody asked for.
git -C "$WORKTREE" reset --hard --quiet "$IRIS_COMMIT"
git -C "$WORKTREE" clean -fdq

echo "  compiling $IRIS_VERSION"
( cd "$WORKTREE" && go build -trimpath \
    -ldflags "-s -w -X github.com/versenilvis/iris/root.Version=$IRIS_VERSION" \
    -o "$DEST" ./cmd/iris )

# The two fixes are the whole reason this script exists, so prove they are in the binary
# rather than trusting that the build succeeded. Stock iris compiles just as cleanly.
echo "  checking both fixes are present"
( cd "$WORKTREE" && go test ./spec/... ./internal/config/... >/dev/null )

built="$("$DEST" version 2>/dev/null || true)"
if [[ "$built" != "iris $IRIS_VERSION" ]]; then
    echo "  built binary reports '$built', expected 'iris $IRIS_VERSION'" >&2
    exit 1
fi

# A package manager copy would win on PATH in some shells, so say when one is still sitting
# there rather than leaving two binaries and a coin toss. Removing it is not this script's
# business, since the Brewfile is what decides which packages exist and it no longer lists it.
if [[ -x /opt/homebrew/bin/iris || -x /usr/local/bin/iris ]]; then
    echo "  note, a package manager copy of iris is still present and is no longer declared."
    echo "        The Brewfile no longer lists it, so it can be removed with the package manager."
fi

echo "  iris $IRIS_VERSION -> $DEST"
