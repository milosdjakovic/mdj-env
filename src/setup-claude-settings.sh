#!/bin/bash
set -e

# Wire the stowed Claude Code scripts into settings.json.
# settings.json is intentionally not tracked/stowed (Claude Code writes to it
# directly), so these keys must be merged in here rather than symlinked.
#
# Three things are merged. The statusLine command, the herdr agent pane hook, which
# reports a session to herdr on the way in and releases it on the way out, and the theme.
# The hook explains itself at dotfiles/claude/.claude/hooks/herdr-agent-pane.sh.
#
# The theme is `auto` because Claude Code paints its own hex colours per theme rather than
# palette slots, so a fixed `dark` keeps the dark half's slash command blue and yellow on a
# light terminal. `auto` is what makes it ask the terminal which half it is on, through herdr
# and through iris, which is the chain decisions/iris-appearance-theme.md exists for. A fresh
# install defaults to `dark`, so the second machine looked right in a dark terminal and wrong
# in a light one until this was set by hand. decisions/claude-code-theme.md has the record.
#
# This used to exit early when the statusLine key was already present, which made it a
# script that could only ever configure a machine once. Adding the hooks would then have
# reached every new machine and no existing one, which is the same trap setup-zshrc.sh still
# carries. So it builds the settings it wants, compares, and writes only on a difference.
# Running it twice changes nothing and says so.

SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_COMMAND="~/.claude/statusline-command.sh"
STATUSLINE_SCRIPT="$HOME/.claude/statusline-command.sh"
HOOK_COMMAND="~/.claude/hooks/herdr-agent-pane.sh"
HOOK_SCRIPT="$HOME/.claude/hooks/herdr-agent-pane.sh"

# Claude Code runs both of these as commands, so they must be executable or they fail with
# "permission denied", silently in the hook's case. The bit is tracked in git (100755), but
# ensure it here too in case it is ever lost. chmod follows the stow symlink to the repo file
# (idempotent).
[ -e "$STATUSLINE_SCRIPT" ] && chmod +x "$STATUSLINE_SCRIPT"
[ -e "$HOOK_SCRIPT" ] && chmod +x "$HOOK_SCRIPT"

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Any hook group of ours is dropped before ours is appended, matched on the script path, so
# re-running replaces rather than stacks. A group belonging to anything else is untouched,
# since Claude Code writes to this file and so does the person using it.
tmp="$(mktemp)"
jq \
    --arg statusline "$STATUSLINE_COMMAND" \
    --arg hook "$HOOK_COMMAND" '
      def prune($cmd):
        map(.hooks |= map(select((.command // "") | contains($cmd) | not)))
        | map(select((.hooks | length) > 0));

      def entry($cmd; $arg):
        { matcher: "*", hooks: [ { type: "command", command: ($cmd + " " + $arg), timeout: 5 } ] };

      .statusLine = { type: "command", command: $statusline }
      | .theme = "auto"
      | .hooks = (.hooks // {})
      | .hooks.SessionStart = ((.hooks.SessionStart // []) | prune($hook)) + [ entry($hook; "start") ]
      | .hooks.SessionEnd   = ((.hooks.SessionEnd   // []) | prune($hook)) + [ entry($hook; "end")   ]
    ' "$SETTINGS" > "$tmp"

if cmp -s "$tmp" "$SETTINGS"; then
    rm -f "$tmp"
    echo "Claude settings already configured"
    exit 0
fi

mv "$tmp" "$SETTINGS"
echo "Claude settings configured successfully"
