#!/usr/bin/env bash
set -euo pipefail

# Sessions have names and no index of their own, so a number has to be assigned. One
# place decides which number a session holds, and every caller reads that one stored
# answer, the strip drawn on the second status row, the key that jumps, and the keys
# that move a session left or right. Deriving the order twice is how a strip ends up
# saying one thing while a key does another.
#
# The number is stored on the session itself as the @sidx option.
#
# The order itself is manual and persistent, the same shape tmux already uses for
# window indices. A session's position is seeded once, by name, and after that it only
# ever changes because a session appeared, a session disappeared, or the move keys were
# pressed. Renaming a session no longer touches its position, since a name is no longer
# what the order is derived from. --ensure runs on startup and on session-created, and
# only ever fills in a position that is missing, appending the new session after
# whatever the highest position already is, so an existing arrangement is never
# disturbed. --compact runs on session-closed and closes the hole a dead session leaves
# behind, renumbering the survivors to 1..N in their existing relative order. --move
# swaps a session's position with its immediate neighbour, the session-strip equivalent
# of swap-window.
#
# The strip itself has to be drawn by --render rather than by tmux's native `#{S:}`
# loop. `#{S:}` can only sort by index, name, or activity time, none of which is @sidx,
# and tmux has no swap-session to make a session's own native position moveable the way
# swap-window makes a window's. So the loop can show every session with its @sidx
# number, but it cannot ever show them arranged BY that number, only in whatever fixed
# order tmux itself iterates them in, which is name order and nothing else. A move key
# would then change the number beside a session without changing where it sits, which
# is a worse result than not having move at all. --render exists to make position
# actually follow @sidx, at the cost of a shell call the status line does have to make.
#
# Every list is read as tab separated fields, and never straight into `read -r a b`.
# Bash's read treats a tab in IFS as IFS whitespace, which means it silently strips a
# leading empty field, so a session with no position yet, whose line is a bare tab
# followed by its name, would read back as the name landing in the first field and the
# second field empty. Reading the whole line with IFS unset, then splitting by hand, is
# what keeps a missing position reading as missing instead of quietly corrupting the
# row after it.
split_idx_name() {
    idx=${1%%$'\t'*}
    name=${1#*$'\t'}
}

usage() {
    echo "usage, session-index.sh --ensure | --compact | --move left|right <session> |" \
         "--switch N [client] | --render <current> <last> <muted> <gen>" >&2
    exit 2
}

# Every write to @sidx bumps this, and --render is always called with it as a trailing
# argument it never reads. Its only job is to change the exact text of the shell command
# embedded in status-format[1], so tmux never has a reason to reuse a cached run of the
# render job from before the write. Without it, a move could sit behind tmux's own once
# a second throttle on re-running an unchanged #() job, and the strip would show the old
# order for up to a second after the key that was supposed to fix that.
bump_gen() {
    local gen
    gen=$(tmux show-option -gqv @sidx_gen)
    [ -n "$gen" ] || gen=0
    tmux set-option -g @sidx_gen "$((gen + 1))"
}

# Give a position to any session that does not have one yet, without touching anyone
# who already does. On the very first run, when nothing has a position at all, seed the
# whole list once in name order. After that, a missing position only ever belongs to a
# session that was just created, so it is appended after the current highest position.
ensure() {
    local max=0 has_any=0 idx name line

    while IFS= read -r line; do
        split_idx_name "$line"
        [ -n "$name" ] || continue
        if [ -n "$idx" ]; then
            has_any=1
            [ "$idx" -gt "$max" ] && max=$idx
        fi
    done < <(tmux list-sessions -F '#{@sidx}'$'\t''#{session_name}')

    if [ "$has_any" -eq 0 ]; then
        local i=1
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            tmux set-option -t "$name" @sidx "$i"
            i=$((i + 1))
        done < <(tmux list-sessions -F '#{session_name}' | LC_ALL=C sort)
    else
        while IFS= read -r line; do
            split_idx_name "$line"
            [ -n "$name" ] || continue
            if [ -z "$idx" ]; then
                max=$((max + 1))
                tmux set-option -t "$name" @sidx "$max"
            fi
        done < <(tmux list-sessions -F '#{@sidx}'$'\t''#{session_name}')
    fi

    bump_gen
    # Setting a session option changes nothing on screen by itself, so ask every
    # client to redraw its status line and pick the new numbers up.
    tmux refresh-client -S
}

# Close the hole a closed session leaves, renumbering the survivors to 1..N in whatever
# relative order they already had. This never resorts by name, it only removes the gap.
compact() {
    local i=1 idx name line
    while IFS= read -r line; do
        split_idx_name "$line"
        [ -n "$name" ] || continue
        tmux set-option -t "$name" @sidx "$i"
        i=$((i + 1))
    done < <(tmux list-sessions -F '#{@sidx}'$'\t''#{session_name}' | sort -t $'\t' -k1 -n)

    bump_gen
    tmux refresh-client -S
}

# Swap a session with whichever session sits one slot to its left or right. At either
# edge of the list there is no neighbour to trade with, and this does nothing, the same
# quiet no-op switch_to uses for a number nothing holds.
move() {
    local dir="$1" moved="$2" cur_idx target_idx idx name line

    cur_idx=$(tmux show-option -qv -t "$moved" @sidx)
    [ -n "$cur_idx" ] || return 0

    case "$dir" in
        left) target_idx=$((cur_idx - 1)) ;;
        right) target_idx=$((cur_idx + 1)) ;;
        *) usage ;;
    esac

    while IFS= read -r line; do
        split_idx_name "$line"
        if [ "$idx" = "$target_idx" ]; then
            tmux set-option -t "$moved" @sidx "$target_idx"
            tmux set-option -t "$name" @sidx "$cur_idx"
            bump_gen
            tmux refresh-client -S
            return 0
        fi
    done < <(tmux list-sessions -F '#{@sidx}'$'\t''#{session_name}')

    return 0
}

# Jump to whichever session currently holds this number. The client is passed in by the
# binding rather than left for tmux to guess, because the binding runs in the background
# and a backgrounded switch-client with no client picks the most recently used one. With
# two terminals attached that would move the other one.
switch_to() {
    local want="$1" client="${2:-}" idx name line
    while IFS= read -r line; do
        split_idx_name "$line"
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

# Draw the strip body, one session per @sidx position in ascending order, current
# session bracketed and green, the last-session dash next, everyone else plain. current,
# last, and muted are handed in already resolved (#{client_session}, #{client_last_session},
# #{E:@bar_muted}) since a client's own state is what decides the colour, and a shared
# job cached server side has no client of its own to read that state from. gen is never
# read, see bump_gen above for why it's still a required argument. A session with no
# @sidx yet (the instant between session-created firing and its --ensure hook landing)
# sorts last rather than first, so it does not jump the queue while it waits for a number.
render() {
    local current="$1" last="$2" muted="$3" line idx sid name plain fg
    local -a rows=()
    local i j tmp key

    plain="white"
    [ "$muted" = "1" ] && plain="black"

    # One fork is unavoidable, the tmux call that lists live sessions. The sort past
    # it does not need a second and third fork of its own. The list is only ever a
    # handful of sessions long, so a plain insertion sort in bash, no awk, no sort,
    # trims the render job down to the one process a status line redraw already has
    # to wait on.
    while IFS= read -r line; do
        idx=${line%%$'\t'*}
        [ -n "$idx" ] || idx=999999
        rows+=("$idx"$'\t'"${line#*$'\t'}")
    done < <(tmux list-sessions -F '#{@sidx}'$'\t''#{session_id}'$'\t''#{session_name}')

    for ((i = 1; i < ${#rows[@]}; i++)); do
        tmp=${rows[i]}
        key=${tmp%%$'\t'*}
        j=$((i - 1))
        while ((j >= 0)) && (( ${rows[j]%%$'\t'*} > key )); do
            rows[j + 1]=${rows[j]}
            j=$((j - 1))
        done
        rows[j + 1]=$tmp
    done

    for line in "${rows[@]}"; do
        idx=${line%%$'\t'*}; line=${line#*$'\t'}
        sid=${line%%$'\t'*}; name=${line#*$'\t'}
        [ -n "$name" ] || continue

        if [ "$name" = "$current" ]; then
            fg="green"
            [ "$muted" = "1" ] && fg="black"
            printf '#[range=session|%s]#[fg=%s]>%s:%s<#[default]#[norange] ' "$sid" "$fg" "$idx" "$name"
        elif [ "$name" = "$last" ]; then
            printf '#[range=session|%s]#[fg=%s]-%s:%s#[default]#[norange] ' "$sid" "$plain" "$idx" "$name"
        else
            printf '#[range=session|%s]#[fg=%s]%s:%s#[default]#[norange] ' "$sid" "$plain" "$idx" "$name"
        fi
    done
}

case "${1:-}" in
    --ensure) ensure ;;
    --compact) compact ;;
    --move)
        [ $# -ge 3 ] || usage
        move "$2" "$3"
        ;;
    --switch)
        [ $# -ge 2 ] || usage
        switch_to "$2" "${3:-}"
        ;;
    --render)
        [ $# -ge 5 ] || usage
        render "$2" "$3" "$4"
        ;;
    *) usage ;;
esac
