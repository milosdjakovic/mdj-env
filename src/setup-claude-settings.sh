#!/bin/bash
set -e

# Wire the stowed Claude Code scripts into settings.json.
# settings.json is intentionally not tracked/stowed (Claude Code writes to it
# directly), so these keys must be merged in here rather than symlinked.
#
# Two things are merged, the statusLine command and the theme. A third, a SessionStart and
# SessionEnd hook that reported the session to herdr's agents panel, was removed on
# 2026-09-16 because a reported state becomes the pane's state authority in herdr and froze
# every session at idle. decisions/herdr-agent-detection.md has the record. Any copy of that
# hook still wired into settings.json on a machine is pruned here, so an outdated machine is
# repaired by the same run that configures a fresh one.
#
# The theme is `auto` because Claude Code paints its own hex colours per theme rather than
# palette slots, so a fixed `dark` keeps the dark half's slash command blue and yellow on a
# light terminal. `auto` is what makes it ask the terminal which half it is on, through herdr
# and through whatever else holds the terminal, a chain decisions/iris.md describes. A fresh
# install defaults to `dark`, so the second machine looked right in a dark terminal and wrong
# in a light one until this was set by hand. decisions/claude-code-theme.md has the record.
#
# This used to exit early when the statusLine key was already present, which made it a
# script that could only ever configure a machine once. Anything added later would then have
# reached every new machine and no existing one, which is the same trap setup-zshrc.sh still
# carries. So it builds the settings it wants, compares, and writes only on a difference.
# Running it twice changes nothing and says so.

SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_COMMAND="~/.claude/statusline-command.sh"
STATUSLINE_SCRIPT="$HOME/.claude/statusline-command.sh"
RETIRED_HOOK="herdr-agent-pane.sh"

# Claude Code runs the status line as a command, so it must be executable or it fails with
# "permission denied". The bit is tracked in git (100755), but ensure it here too in case it
# is ever lost. chmod follows the stow symlink to the repo file (idempotent).
[ -e "$STATUSLINE_SCRIPT" ] && chmod +x "$STATUSLINE_SCRIPT"

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# The retired hook is pruned from every event it was ever wired into, matched on the script
# name, and an event or a hooks table left empty by that is dropped rather than kept as an
# empty list. A group belonging to anything else is untouched, since Claude Code writes to
# this file and so does the person using it.
tmp="$(mktemp)"
jq \
    --arg statusline "$STATUSLINE_COMMAND" \
    --arg retired "$RETIRED_HOOK" '
      def prune($cmd):
        map(.hooks |= map(select((.command // "") | contains($cmd) | not)))
        | map(select((.hooks | length) > 0));

      .statusLine = { type: "command", command: $statusline }
      | .theme = "auto"
      | (if .hooks then
          .hooks |= (with_entries(.value |= prune($retired)) | with_entries(select((.value | length) > 0)))
          | (if (.hooks | length) == 0 then del(.hooks) else . end)
        else . end)
    ' "$SETTINGS" > "$tmp"

if cmp -s "$tmp" "$SETTINGS"; then
    rm -f "$tmp"
    echo "Claude settings already configured"
    exit 0
fi

mv "$tmp" "$SETTINGS"
echo "Claude settings configured successfully"
