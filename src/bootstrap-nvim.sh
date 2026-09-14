#!/bin/bash
set -e

# Install Neovim's plugins at the versions lazy-lock.json names, and prove it afterwards.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCKFILE="$SCRIPT_DIR/../dotfiles/nvim/.config/nvim/lazy-lock.json"
LAZY_ROOT="$HOME/.local/share/nvim/lazy"

if [[ ! -f "$LOCKFILE" ]]; then
    echo "Error: lazy-lock.json not found at $LOCKFILE"
    exit 1
fi

# Lazy! sync is the wrong command for replication and was the one being used. sync is install,
# clean and update, and update is documented as moving every plugin to its latest revision and
# then rewriting the lockfile. So the machine got whatever happened to be newest that day
# rather than what this repository pins, and since ~/.config/nvim is a symlink into the repo,
# the rewrite landed on a tracked file and left the working tree dirty.
#
# install fetches what is absent, clean removes what the config no longer asks for, and
# restore is lazy.nvim's own answer to this exact question. Its manual says, of using a config
# on more than one machine, that you run restore on the other one to bring every plugin to the
# version in the lockfile.
#
# Naming those three was necessary and was not sufficient, and the way it failed is worth
# writing down because the report said the opposite of what happened. install writes the
# lockfile too. It records what it just put on disk, which for a machine whose plugins have
# drifted is the drifted revisions, so by the time restore ran in the same invocation the file
# it reads had already been rewritten to agree with the disk. restore then had nothing to do,
# every plugin stayed where it was, the pins were gone from a tracked file, and the check at
# the end re-read that same rewritten file and found no disagreement. It printed 25 reconciled
# and had reconciled nothing. A verification that reads a file the tool being verified is free
# to rewrite is not a verification, it only proves the tool agrees with itself.
#
# So the pins are copied out before anything runs, every comparison below is made against that
# copy rather than against the file, and the file is put back whenever lazy has moved it. The
# copy is the intent and it is read only for the rest of this script. That also means the
# ordering no longer has to be lucky, since restore is handed the pins again immediately
# before it runs rather than inheriting whatever install left behind.
PINS="$(mktemp "${TMPDIR:-/tmp}/lazy-pins.XXXXXX")"
trap 'rm -f "$PINS"' EXIT
cp "$LOCKFILE" "$PINS"

# Put the pins back when lazy has rewritten them, and say so, since a silent repair would hide
# the thing this whole guard exists to catch. Answers 0 when it had to repair.
restore_pins() {
    cmp -s "$PINS" "$LOCKFILE" && return 1
    cp "$PINS" "$LOCKFILE"
    return 0
}

# What the lockfile names against what is on disk, by name and by revision.
#
# The old check looked for one directory, LazyVim's, and called the whole job done. A first
# run that died partway through, on a flaky network say, was therefore never retried, and the
# plugins it never fetched stayed missing on every run after it. Checking the revision too is
# what makes this a reconciler rather than a presence test, so a plugin left behind by an
# interrupted update is brought back to the pinned commit instead of being accepted.
# It reports on stdout, a line per plugin, rather than filling an array through a nameref,
# because macOS ships bash 3.2 at /bin/bash and namerefs arrived in 4.3.
#
# It reads PINS and never LOCKFILE, which is the whole correction. Reading the file lazy may
# have just rewritten is what let a run report success while every plugin stayed put.
drift() {
    local name commit directory head

    while IFS=$'\t' read -r name commit; do
        directory="$LAZY_ROOT/$name"
        if [[ ! -d "$directory" ]]; then
            echo "$name is not installed"
            continue
        fi
        head="$(git -C "$directory" rev-parse HEAD 2>/dev/null || echo unknown)"
        if [[ "$head" != "$commit" ]]; then
            echo "$name is at ${head:0:7}, the pinned revision is ${commit:0:7}"
        fi
    done < <(jq -r 'to_entries[] | "\(.key)\t\(.value.commit)"' "$PINS")
}

count_lines() {
    printf '%s\n' "$1" | grep -c . || true
}

BEFORE="$(drift)"

if [[ -z "$BEFORE" ]]; then
    echo "Neovim plugins already match the lockfile"
    exit 0
fi

echo "Bootstrapping Neovim plugins, $(count_lines "$BEFORE") of them off the pinned revisions..."
printf '%s\n' "$BEFORE" | head -5 | sed 's/^/    /'
[[ "$(count_lines "$BEFORE")" -gt 5 ]] && echo "    and more"

# Two invocations rather than one, because the pins have to be put back in between. install
# and clean are what fetch an absent plugin and drop one the config no longer loads, and
# either may leave the lockfile describing the disk. restore is then handed the pins again and
# run on its own, which is the state it needs and the only state in which it does anything.
nvim --headless "+Lazy! install" "+Lazy! clean" +qa

if restore_pins; then
    echo "    lazy rewrote lazy-lock.json during install, pins restored"
fi

nvim --headless "+Lazy! restore" +qa

if restore_pins; then
    echo "    lazy rewrote lazy-lock.json during restore, pins restored"
fi

# Verified rather than assumed. A headless nvim exits zero whether or not every clone
# succeeded, which is how a partial install could survive unnoticed for as long as it did.
AFTER="$(drift)"

if [[ -n "$AFTER" ]]; then
    {
        echo ""
        echo "Error: $(count_lines "$AFTER") plugin(s) still do not match the pinned revisions"
        printf '%s\n' "$AFTER" | sed 's/^/    /'
        echo ""
        echo "    A plugin that stays missing usually means the lockfile names something the"
        echo "    config no longer loads, which is a repository defect rather than a machine one."
    } >&2
    exit 1
fi

echo "Neovim plugins bootstrapped successfully, $(count_lines "$BEFORE") reconciled"
