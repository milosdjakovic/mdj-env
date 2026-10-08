#!/usr/bin/env bash
# Every agent herdr knows about, one row each, and enter focuses it. goto shows the same
# agents inside a tree of spaces, tabs and panes, and the pane level is the one nobody
# picks by. So this is flat, ordered by space and then tab, the way the sidebar numbers
# them, with the state glyph first because that is what the list is read for, and the agent's
# own terminal title inline as the only thing that tells two agents in one tab apart.
set -u

HERDR="${HERDR_BIN_PATH:-herdr}"

# The glyph and colour per state are shared with the palette, so both read like the sidebar.
. "$(dirname "$0")/status.sh"
herdr_status_style "$(dirname "$0")/../config.toml"

# One snapshot answers everything, the agents and the labels of the spaces and tabs they
# sit in, so the rows cannot disagree with each other about a rename mid read. The pane id
# rides along as a hidden first field for the focus below. The location is padded here,
# since fzf's tab stops cannot line up labels of different lengths.
rows=$("$HERDR" api snapshot 2>/dev/null | jq -r --argjson glyph "$STATUS_GLYPHS" --argjson colour "$STATUS_COLOURS" '
  .result.snapshot as $s
  | ($s.workspaces | map({key: .workspace_id, value: .}) | from_entries) as $ws
  | ($s.tabs | map({key: .tab_id, value: .}) | from_entries) as $tabs
  | $s.agents
  | map(. + {w: $ws[.workspace_id], t: $tabs[.tab_id]})
  | map(. + {where: "\(.w.label)/\(.t.label)"})
  | sort_by(.w.number, .t.number)
  | (map(.where | length) | max) as $width
  | .[]
  | ($colour[.agent_status] // "90") as $c
  | ($glyph[.agent_status] // "·") as $g
  | "\(.pane_id)\t\u001b[\($c)m\($g)\u001b[0m \(.where + (" " * ($width - (.where | length))))  \u001b[90m\(.terminal_title_stripped // .agent)\u001b[0m"
') || exit 0

[ -n "$rows" ] || {
  "$HERDR" notification show "agents" --body "no agents running" >/dev/null 2>&1
  exit 0
}

pick=$(printf '%s\n' "$rows" | fzf \
  --reverse \
  --ansi \
  --delimiter '\t' \
  --with-nth 2 \
  --prompt "agent " \
  --footer "enter focus") || exit 0

pane="${pick%%$'\t'*}"
[ -n "$pane" ] && "$HERDR" agent focus "$pane" >/dev/null 2>&1
exit 0
