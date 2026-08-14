#!/usr/bin/env bash
set -euo pipefail

# Sessions have names and no index of their own, so a number has to be assigned. One
# place decides which number a session holds, and both callers read that one answer,
# the strip drawn on the second status row and the key that jumps. Deriving the order
# twice is how a strip ends up saying one thing while the key does another.
#
# The number is stored on the session itself as the @sidx option. That choice is what
# keeps the status bar cheap, since a tmux format can read a session option directly
# and the strip never shells out on a redraw. It also makes the jump a lookup of the
# stored value rather than a second derivation of the same rule.
#
# Order is by name in byte order, which does not shift under a locale change. Numbers
# move when a session is created, killed, or renamed, so .tmux.conf renumbers on those
# hooks. That churn is the honest cost of numbering things that have no index, and it
# is the reason the fzf switcher on prefix+s stays the right tool for a session you
# reach rarely.

usage() {
    echo "usage, session-index.sh --renumber or --switch N [client]" >&2
    exit 2
}

# Stamp every session with its position, lowest name first.
renumber() {
    local i=1 name
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        tmux set-option -t "$name" @sidx "$i"
        i=$((i + 1))
    done < <(tmux list-sessions -F '#{session_name}' | LC_ALL=C sort)

    # Setting a session option changes nothing on screen by itself, so ask every
    # client to redraw its status line and pick the new numbers up.
    tmux refresh-client -S
}

# Jump to whichever session currently holds this number. The client is passed in by the
# binding rather than left for tmux to guess, because the binding runs in the background
# and a backgrounded switch-client with no client picks the most recently used one. With
# two terminals attached that would move the other one.
switch_to() {
    local want="$1" client="${2:-}" idx name
    while IFS=$'\t' read -r idx name; do
        if [ "$idx" = "$want" ]; then
            if [ -n "$client" ]; then
                tmux switch-client -c "$client" -t "$name"
            else
                tmux switch-client -t "$name"
            fi
            return 0
        fi
    done < <(tmux list-sessions -F '#{@sidx}'$'\t''#{session_name}')

    # Nothing holds that number, which happens when you press a slot past the end of
    # the list. Doing nothing quietly is right, an empty slot should feel like the key
    # was never pressed rather than like a failure.
    return 0
}

case "${1:-}" in
    --renumber) renumber ;;
    --switch)
        [ $# -ge 2 ] || usage
        switch_to "$2" "${3:-}"
        ;;
    *) usage ;;
esac
