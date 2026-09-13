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
# version in the lockfile. Nothing here updates anything, so the lockfile is read and never
# written and updating stays a deliberate act performed in one place.
SYNC=(nvim --headless "+Lazy! install" "+Lazy! clean" "+Lazy! restore" +qa)

# What the lockfile names against what is on disk, by name and by revision.
#
# The old check looked for one directory, LazyVim's, and called the whole job done. A first
# run that died partway through, on a flaky network say, was therefore never retried, and the
# plugins it never fetched stayed missing on every run after it. Checking the revision too is
# what makes this a reconciler rather than a presence test, so a plugin left behind by an
# interrupted update is brought back to the pinned commit instead of being accepted.
# It reports on stdout, a line per plugin, rather than filling an array through a nameref,
# because macOS ships bash 3.2 at /bin/bash and namerefs arrived in 4.3.
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
            echo "$name is at ${head:0:7}, the lockfile says ${commit:0:7}"
        fi
    done < <(jq -r 'to_entries[] | "\(.key)\t\(.value.commit)"' "$LOCKFILE")
}

count_lines() {
    printf '%s\n' "$1" | grep -c . || true
}

BEFORE="$(drift)"

if [[ -z "$BEFORE" ]]; then
    echo "Neovim plugins already match the lockfile"
    exit 0
fi

echo "Bootstrapping Neovim plugins, $(count_lines "$BEFORE") of them off the lockfile..."
printf '%s\n' "$BEFORE" | head -5 | sed 's/^/    /'
[[ "$(count_lines "$BEFORE")" -gt 5 ]] && echo "    and more"

"${SYNC[@]}"

# Verified rather than assumed. A headless nvim exits zero whether or not every clone
# succeeded, which is how a partial install could survive unnoticed for as long as it did.
AFTER="$(drift)"

if [[ -n "$AFTER" ]]; then
    {
        echo ""
        echo "Error: $(count_lines "$AFTER") plugin(s) still do not match the lockfile after syncing"
        printf '%s\n' "$AFTER" | sed 's/^/    /'
        echo ""
        echo "    A plugin that stays missing usually means the lockfile names something the"
        echo "    config no longer loads, which is a repository defect rather than a machine one."
    } >&2
    exit 1
fi

echo "Neovim plugins bootstrapped successfully, $(count_lines "$BEFORE") reconciled"
