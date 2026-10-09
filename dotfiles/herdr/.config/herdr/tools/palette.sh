#!/usr/bin/env bash
# One searchable list of everything herdr can be asked to do from here. Every agent, space,
# tab and session, every action herdr has, every custom command in config.toml and every
# action another plugin offers, each row showing the key that does the same thing, and enter
# does it.
#
# Each row carries a kind and a target in two hidden fields, and one dispatch at the bottom
# hands each kind to its handler. The actions themselves are data in palette-actions beside
# this file, and the keys that act on a selected row are data in palette-keys, so this engine
# names no herdr action anywhere.
#
# An action acts on a subject, the pane, tab and space its placeholders read. The subject is
# where the palette was opened, or the selected row when a row key was pressed, which is how
# the same rename and close reach a tab you are not in.
#
# The script also answers fzf and itself through a few flags at the top, the preview, the
# footer and the work that has to wait until the popup is gone. Those return before the
# snapshot and the rows are built, which is what keeps them fast enough to run on every move.
#
# There are no group headings. The group is a quiet first column instead, which reads as a
# heading while the list is in its own order and stays useful once fzf ranks it, and typing a
# group's name narrows to it. A row that is a thing, an agent, a space, a tab or a session, is
# grouped by what it is, and every row that does something is a command, since a tab column
# beside Rename tab read as the tab being renamed rather than the action.
set -u

HERDR="${HERDR_BIN_PATH:-herdr}"
# The custom commands in config.toml call herdr through this, and they run as children here.
export HERDR_BIN_PATH="$HERDR"
TOOLS="$(cd "$(dirname "$0")" && pwd)"
# A shell action reaches the scripts beside this one through this.
export PALETTE_TOOLS="$TOOLS"
CONFIG="${HERDR_CONFIG_PATH:-$TOOLS/../config.toml}"
ACTIONS="$TOOLS/palette-actions"
KEYMAP="$TOOLS/palette-keys"
SOCKET="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"

# The last fifty rows picked, most recent first, one kind and target per line, kept per session
# since ids belong to one server. herdr gives every plugin a state directory of its own, and
# the fallback is the same path for a run outside a plugin pane.
RECENT="${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr/plugins/mdj-tools}/recent-${HERDR_SESSION:-default}"

. "$TOOLS/context.sh"

# The glyph herdr's sidebar draws for each agent state, from whichever of its two indicator
# sets the config chooses, both as herdr's own settings preview lists them, and the ANSI slot
# the theme paints for it, the same yellow working and green idle the sidebar uses.
if grep -qE '^[[:space:]]*status_indicators[[:space:]]*=[[:space:]]*"symbols"' "$CONFIG" 2>/dev/null; then
  STATUS_GLYPHS='{"blocked":"×","working":"◐","done":"✓","idle":"○"}'
else
  STATUS_GLYPHS='{"blocked":"●","working":"●","done":"●","idle":"○"}'
fi
STATUS_COLOURS='{"blocked":"31","working":"33","done":"34","idle":"32"}'

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

notify() {
  "$HERDR" notification show "palette" --body "$1" >/dev/null 2>&1
}

# herdr's own message out of an error, which arrives as JSON, or the first line of whatever
# else came back.
error_text() {
  jq -r '.error.message // empty' <<<"$1" 2>/dev/null | grep . || printf '%s' "${1%%$'\n'*}"
}

# What the cursor's row shows under the list, the recent output of the pane it stands for. A tab
# and a space stand for the pane focused in them. Anything else has nothing to show, and the
# focus binding hides the preview for it.
#
# It reads five hundred lines rather than the height of the window, so there is history to
# scroll up through, and the preview window follows the end, so the latest line is what shows
# first. Carriage returns are dropped, since nearly every line from a pane ends in one and fzf
# draws them as space, and so are blank rows after the last line of output, since a full screen
# program leaves its unused rows blank and scrolling down would otherwise end in them.
#
# A full screen agent such as Claude keeps its conversation off herdr's scrollback, so its
# preview is its current screen. decisions/herdr-palette.md has why it is not more than that.
preview() {
  local pane
  case "$1" in
    agent | pane) pane="$2" ;;
    tab | space)
      pane=$("$HERDR" api snapshot 2>/dev/null | jq -r --arg kind "$1" --arg id "$2" '
        .result.snapshot as $s
        | (if $kind == "tab" then $id else ($s.workspaces[] | select(.workspace_id == $id) | .active_tab_id) end) as $tab
        | [$s.panes[] | select(.tab_id == $tab)] | (map(select(.focused)) + .) | first | .pane_id // empty')
      ;;
  esac
  [ -n "${pane:-}" ] || return 0
  "$HERDR" pane read "$pane" --source recent --lines 500 --format ansi 2>/dev/null | trim_output | shown
}

# Prints a preview and notes for scroll below how many lines it has, with none of them below the
# window yet, since the window follows the end. A run outside fzf has nowhere to note it.
shown() {
  local out
  out=$(cat)
  printf '%s\n' "$out"
  [ -n "${PALETTE_RUN:-}" ] || return 0
  printf '%s\n' "$out" | wc -l | tr -d ' ' > "$PALETTE_RUN/lines"
  echo 0 > "$PALETTE_RUN/below"
}

# fzf lets a preview scroll until its last line reaches the top of the window, which leaves the
# window empty beneath it, and it has no setting against that and does not say where the
# preview is scrolled to. So the wheel over the preview and shift with up and down come here,
# which counts the lines below the window, lets a scroll down through only while there are some
# and a scroll up only until the top line shows, and answers fzf with the action or nothing.
scroll() {
  local below lines max
  [ -n "${PALETTE_RUN:-}" ] || return 0
  below=$(cat "$PALETTE_RUN/below" 2>/dev/null || echo 0)
  lines=$(cat "$PALETTE_RUN/lines" 2>/dev/null || echo 0)
  max=$(( lines - ${FZF_PREVIEW_LINES:-0} ))
  [ "$max" -gt 0 ] || max=0
  case "$1" in
    down) [ "$below" -gt 0 ] && { echo $((below - 1)) > "$PALETTE_RUN/below"; printf preview-down; } ;;
    up) [ "$below" -lt "$max" ] && { echo $((below + 1)) > "$PALETTE_RUN/below"; printf preview-up; } ;;
  esac
  return 0
}

# Output shorter than the preview window is padded at the top, so it sits at the bottom the way
# a terminal shows it. Otherwise fzf draws it from the top and leaves the rest of the window
# empty below, which an agent's screen, often shorter than the window, always did.
trim_output() {
  tr -d '\r' | awk -v height="${FZF_PREVIEW_LINES:-0}" '
    { line[NR] = $0; plain = $0; gsub(/\033\[[0-9;?]*[A-Za-z]/, "", plain)
      if (plain ~ /[^[:space:]]/) last = NR }
    END { for (i = last; i < height; i++) print ""
          for (i = 1; i <= last; i++) print line[i] }'
}

# What fzf does as the cursor lands on a row of this kind, the footer listing the keys that
# work there and the preview shown or hidden. The keys come from palette-keys.
on_focus() {
  local verb keys
  case "$1" in
    agent | space | tab | pane) verb="enter go" ;;
    session) verb="enter switch" ;;
    *) verb="enter run" ;;
  esac
  keys=$(grep -vE '^[[:space:]]*(#|$)' "$KEYMAP" | awk -F'|' -v kind="$1" '
    { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $4)
      if ((" " $2 " ") ~ (" " kind " ")) printf ", %s %s", $1, $4 }')
  case "$1" in
    agent | space | tab | pane) printf 'change-footer(%s%s, ctrl-/ preview)+show-preview' "$verb" "$keys" ;;
    *) printf 'change-footer(%s%s)+hide-preview' "$verb" "$keys" ;;
  esac
}

# Sends one request to herdr's socket, for the methods its CLI does not have, and says why
# when herdr refuses. It runs after the popup has closed, since one of them opens its own.
api_send() {
  local reply
  reply=$(printf '%s\n' "$1" | nc -U -w 2 "$SOCKET" 2>/dev/null)
  [ -n "$reply" ] || { notify "herdr did not answer"; return; }
  jq -e '.error' <<<"$reply" >/dev/null 2>&1 && notify "$(error_text "$reply")"
}

# Runs a shell action after the popup has closed, since the slow ones would hold it open, and
# reports the herdr error that stopped it.
shell_run() {
  local err
  err=$(bash -c "$1" 2>&1 >/dev/null) || notify "$(error_text "$err")"
}

case "${1:-}" in
  --preview) preview "$2" "$3"; exit 0 ;;
  --scroll) scroll "$2"; exit 0 ;;
  --focus) on_focus "$2"; exit 0 ;;
  --after-api) api_send "$2"; exit 0 ;;
  --after-shell) shell_run "$2"; exit 0 ;;
esac

# Every action's key, herdr's default overlaid by the [keys] table here. Both are flat lines
# of one name and one quoted value, the defaults commented out in herdr's own template, so a
# line match reads them without a TOML parser. The [keys] range ends at the first table
# header, which is the first [[keys.command]].
shortcuts() {
  {
    "$HERDR" --default-config 2>/dev/null \
      | sed -n '/^\[keys\]/,/^\[[a-z]/p' \
      | sed -nE 's/^# ([a-z_]+) = "([^"]*)".*/\1	\2/p'
    sed -n '/^\[keys\]/,/^\[/p' "$CONFIG" \
      | sed -nE 's/^([a-z_]+)[[:space:]]*=[[:space:]]*"([^"]*)".*/\1	\2/p'
  } | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

# The [[keys.command]] tables, one tab separated line each, key, type, description and
# command, with the escaped quotes in a command undone so it runs as written.
custom_commands() {
  awk '
    function val(s) { sub(/^[^=]*=[ \t]*"/, "", s); sub(/"[ \t]*$/, "", s); gsub(/\\"/, "\"", s); return s }
    function flush() { if (open) print k "\t" t "\t" d "\t" c; open = 0; k = t = d = c = "" }
    /^\[\[keys\.command\]\]/ { flush(); open = 1; next }
    /^\[/ { flush(); next }
    open && /^key[ \t]*=/ { k = val($0) }
    open && /^type[ \t]*=/ { t = val($0) }
    open && /^description[ \t]*=/ { d = val($0) }
    open && /^command[ \t]*=/ { c = val($0) }
    END { flush() }
  ' "$CONFIG"
}

# A key as a person presses it, the prefix spelled out as the key it is bound to.
press() {
  local prefix
  prefix=$(jq -r '.prefix // "ctrl+b"' <<<"$KEYS")
  case "$1" in
    prefix+*) printf '%s, then %s' "$prefix" "${1#prefix+}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# What the palette was opened over. The popup has no pane of its own, so the pane comes from
# the context herdr hands it, and its tab, space and directory from the snapshot, which is
# also what every row below is read from, so the two cannot disagree.
SNAP=$("$HERDR" api snapshot 2>/dev/null | jq -c '.result.snapshot') || exit 0
[ -n "$SNAP" ] && [ "$SNAP" != null ] || exit 0
HERE_PANE=$(herdr_pane_id)
[ -n "$HERE_PANE" ] || HERE_PANE=$(jq -r '.focused_pane_id // empty' <<<"$SNAP")
IFS=$'\t' read -r HERE_TAB HERE_WS HERE_CWD < <(jq -r --arg p "$HERE_PANE" '
  .panes[] | select(.pane_id == $p) | [.tab_id, .workspace_id, (.foreground_cwd // .cwd // "")] | @tsv
' <<<"$SNAP")
HERE_CWD="${HERE_CWD:-$HOME}"
SUBJ_PANE="$HERE_PANE" SUBJ_TAB="$HERE_TAB" SUBJ_WS="$HERE_WS" SUBJ_CWD="$HERE_CWD"
KEYS=$(shortcuts)

# Makes the selected row the subject. An agent or a pane brings its tab and space, a tab brings
# its space and its focused pane, and a space brings its active tab and that tab's pane.
subject_from_row() {
  IFS=$'\t' read -r SUBJ_PANE SUBJ_TAB SUBJ_WS SUBJ_CWD < <(jq -r --arg kind "$1" --arg id "$2" '
    . as $s
    | ( if $kind == "space" then ($s.workspaces[] | select(.workspace_id == $id) | .active_tab_id)
        elif $kind == "tab" then $id
        else ($s.panes[] | select(.pane_id == $id) | .tab_id) end ) as $tab
    | ( if $kind == "agent" or $kind == "pane" then ($s.panes[] | select(.pane_id == $id))
        else [$s.panes[] | select(.tab_id == $tab)] | (map(select(.focused)) + .) | first end ) as $p
    | [$p.pane_id, $tab, $p.workspace_id, ($p.foreground_cwd // $p.cwd // "")] | @tsv
  ' <<<"$SNAP")
  SUBJ_CWD="${SUBJ_CWD:-$HOME}"
}

# Rows as JSON objects, kind, target, group, state, title, detail, right and here, one source
# after another in the order they are listed when nothing is typed. here marks the space, tab,
# pane or agent the palette was opened over.
#
# Every row that stands for a pane reads the same way, whichever group it is in. The title is
# what you call it, the name you gave the pane, or the best name herdr has when there is none.
# The detail is what it is doing now, an agent's conversation topic or a shell's command or
# path. The right is where it is. An agent's state is a word in a column of its own, so typing
# it narrows to it, and the group says whether there is an agent inside, which is what decides
# the state and the order.
#
# Spaces and tabs keep the order of the snapshot, which is their order on screen. Their number
# is not, since a moved tab keeps the number it had.
#
# Agents come in the order they want you, blocked, then done, then working, then idle. A pane
# with an agent in it is listed once, as the agent. A tab with one pane is listed once too, as
# the tab, and its pane gets a row of its own only beside others. A shell's title is its
# prompt, user, host and path, and only the path tells two apart, so the rest is cut. herdr
# only reports a pane's label once the pane has been named.
rows() {
  jq -c --arg home "$HOME" --arg pane "$HERE_PANE" --arg tab "$HERE_TAB" --arg ws "$HERE_WS" '
    def shown: ((.terminal_title_stripped // "") | sub("^[^@ ]+@[^: ]+:"; "")) as $t
      | if $t != "" then $t else (.foreground_cwd // .cwd // .pane_id) | sub("^" + $home; "~") end;
    def named: (.label // "") | select(. != "");
    . as $s
    | ($s.panes | map({key: .pane_id, value: .}) | from_entries) as $pane_by
    | ($s.workspaces | map({key: .workspace_id, value: .}) | from_entries) as $ws_by
    | ($s.tabs | map({key: .tab_id, value: .}) | from_entries) as $tabs
    | ($s.panes | group_by(.tab_id) | map({key: .[0].tab_id, value: .}) | from_entries) as $panes_in
    | ($s.workspaces | to_entries | map({key: .value.workspace_id, value: .key}) | from_entries) as $wpos
    | ($s.tabs | to_entries | map({key: .value.tab_id, value: .key}) | from_entries) as $tpos
    | {blocked: 0, done: 1, working: 2, idle: 3} as $want
    | ( $s.agents
        | map(. + {w: $ws_by[.workspace_id], t: $tabs[.tab_id],
                   topic: (((.terminal_title_stripped // "") | sub("^[^@ ]+@[^: ]+:"; "")) as $t
                           | if $t != "" then $t else .agent end)})
        | sort_by($want[.agent_status] // 4, $wpos[.workspace_id], $tpos[.tab_id]) | .[]
        | {kind: "agent", target: .pane_id, group: "agent", state: .agent_status,
           title: (($pane_by[.pane_id] | named) // .topic),
           detail: (if ($pane_by[.pane_id].label // "") != "" then .topic else "" end),
           status: (.agent_status // ""),
           right: "\(.w.label)/\(.t.label)", here: (.pane_id == $pane)} ),
      ( $s.workspaces | .[]
        | {kind: "space", target: .workspace_id, group: "space", state: .agent_status,
           title: .label, right: "\(.tab_count) tabs", here: (.workspace_id == $ws)} ),
      ( $s.tabs
        | map(. + {w: $ws_by[.workspace_id], p: ($panes_in[.tab_id] // [])})
        | sort_by($wpos[.workspace_id]) | .[]
        | {kind: "tab", target: .tab_id, group: "tab", state: .agent_status, title: .label,
           detail: (if (.p | length) == 1 and .p[0].agent == null
                    then .p[0] | ((named | . + "  ") // "") + shown else "" end),
           right: .w.label, here: (.tab_id == $tab)} ),
      ( $s.panes
        | map(select(.agent == null and (($panes_in[.tab_id] // []) | length) > 1)
              | . + {w: $ws_by[.workspace_id], t: $tabs[.tab_id]})
        | sort_by($wpos[.workspace_id], $tpos[.tab_id]) | .[]
        | {kind: "pane", target: .pane_id, group: "pane", title: (named // shown),
           detail: (if (.label // "") != "" then shown else "" end),
           right: "\(.w.label)/\(.t.label)", here: (.pane_id == $pane)} )
  ' <<<"$SNAP"

  grep -vE '^[[:space:]]*(#|$)' "$ACTIONS" | jq -Rc --argjson keys "$KEYS" '
    split("|") | map(gsub("^\\s+|\\s+$"; ""))
    | ($keys[.[0]] // "") as $key
    | select(.[1] != "key" or $key != "")
    | {kind: "action", target: .[0], group: "command", title: .[2], right: $key}
  '

  # The row that opens this palette is left out, since choosing it would only open it again.
  custom_commands | jq -Rc '
    split("\t") | [., input_line_number] as [$f, $n]
    | select(($f[3] // "") | test("--entrypoint palette") | not)
    | {kind: "command", target: ($n | tostring), group: "command",
       title: (if ($f[2] // "") != "" then $f[2] else $f[3] end), right: $f[0]}
  '

  "$HERDR" plugin action list 2>/dev/null | jq -c '
    .result.actions[]?
    | {kind: "plugin", target: "\(.plugin_id) \(.action_id)", group: "command",
       title: .title, right: .plugin_id}
  '

  "$HERDR" session list --json 2>/dev/null | jq -c --arg sock "${HERDR_SOCKET_PATH:-}" '
    .sessions[]?
    | {kind: "session", target: .name, group: "session", title: .name,
       right: (if .running then "running" else "stopped" end),
       here: (if $sock != "" then .socket_path == $sock else .default end)}
  '
}

# One display line per row, after the kind and the target, the group quiet on the left, the
# state glyph, the title cut to leave its detail room, at most half the width, the detail
# quiet beside it, the state word in its own column when any row has one, and the key or the
# location quiet on the right, followed by here on the row the palette was opened over. A path
# is cut from the left, since its last folder is the part that says which one it is, and so is
# a location, whose tab and here say which one. Widths are measured in jq, which counts
# characters rather than bytes, so a title with a glyph in it still lines up.
#
# The last few rows picked come first, most recent at the top, which is where the next pick
# usually is. A row that is here is passed over, since the place you are in is never where you
# are going, and that leaves the place you came from at the top. Below them every source keeps
# its own order, and fzf's ranking keeps the same order between equal matches.
format() {
  local width recent
  # fzf takes two columns on the left for its pointer and gutter and keeps a margin on the
  # right, and a row any wider is cut at the end or scrolled sideways to show the match, both
  # drawn as two dots over the group or the location. The first width tried here left four and
  # was two short, so this leaves eight.
  width=$(( $(tput cols 2>/dev/null || echo 100) - 8 ))
  recent='[]'
  [ -r "$RECENT" ] && recent=$(jq -Rsc 'split("\n") | map(select(. != ""))' "$RECENT")
  jq -rs --argjson width "$width" --argjson recent "${recent:-[]}" \
    --argjson glyph "$STATUS_GLYPHS" --argjson colour "$STATUS_COLOURS" '
    def clean: tostring | gsub("[\t\n]"; " ");
    def cut($n): if length <= $n then .
      elif test("^[~/]") then "…" + .[(length - ([$n - 1, 0] | max)):]
      else .[0:([$n - 1, 0] | max)] + "…" end;
    def pad($n): . + (" " * ([$n - length, 0] | max));
    def lpad($n): (" " * ([$n - length, 0] | max)) + .;
    def lcut($n): if length <= $n then . else "…" + .[(length - ([$n - 1, 0] | max)):] end;
    def key: "\(.kind)\t\(.target)";
    def quiet: "\u001b[90m\(.)\u001b[0m";
    (map(select(.here | not) | key)) as $present
    | ([$recent[] | select(. as $k | $present | index([$k]))] | .[:5]) as $top
    | map(. + {right: ((.right // "" | clean) + (if .here then ", here" else "" end))})
    | ([.[].right | length] | max // 0 | [., 30] | min) as $rw
    | ([.[].status // "" | length] | max // 0) as $sw
    | (if $sw > 0 then $sw + 2 else 0 end) as $scol
    | ($width - 9 - 2 - 2 - $scol - $rw | [., 12] | max) as $tw
    | map(. + {rank: (key as $k | if .here then null else ($top | index([$k])) end // 1000)})
    | sort_by(.rank) | .[]
    | (if .state and $glyph[.state] then "\u001b[\($colour[.state])m\($glyph[.state])\u001b[0m" else " " end) as $g
    | (.detail // "" | clean) as $d
    | (if $d == "" then $tw else $tw - 2 - ([$d | length, ($tw / 2 | floor)] | min) end) as $tmax
    | (.title | clean | cut($tmax)) as $t
    | ($tw - ($t | length) - 2) as $room
    | (if $d == "" or $room < 1 then $t | pad($tw) else "\($t)  \($d | cut($room) | pad($room) | quiet)" end) as $body
    | (if $sw > 0 then (.status // "" | pad($sw) | quiet) + "  " else "" end) as $st
    | "\(key)\t\(.group | pad(8) | quiet) \($g) \($body)  \($st)\(.right | lcut($rw) | lpad($rw) | quiet)"
  '
}

remember() {
  local line="$1"$'\t'"$2"
  mkdir -p "$(dirname "$RECENT")"
  { printf '%s\n' "$line"; grep -vxF "$line" "$RECENT" 2>/dev/null; } | head -n 50 > "$RECENT.tmp" \
    && mv "$RECENT.tmp" "$RECENT"
}

# Runs one herdr command and reports a failure, since a herdr error is JSON on stderr and the
# popup is about to close, which leaves the notification as the only place it can appear.
run() {
  local err
  err=$("$HERDR" "$@" 2>&1 >/dev/null) && return 0
  notify "$(error_text "$err")"
  return 1
}

# Starts something that may open a popup of its own. herdr shows one popup at a time and
# refuses a second with ui_busy, so it runs detached and waits for this one to close first.
# Closing a popup ends its whole process group, which nohup does not survive, so job control
# is switched on for the one launch to give the child a process group of its own.
launch() {
  set -m
  nohup sh -c 'sleep 0.3; exec "$@"' sh "$@" >/dev/null 2>&1 &
  set +m
}

# Which thing a command acts on, named for the yes or no question and the text prompt, so a
# close says which tab it closes. Read from the placeholder the command uses.
describe() {
  case "$1" in
    *"{pane}"*) printf 'pane %s' "$(jq -r --arg p "$SUBJ_PANE" '.panes[] | select(.pane_id == $p) | .label // .terminal_title_stripped // .pane_id' <<<"$SNAP")" ;;
    *"{tab}"*) printf 'tab %s' "$(label_of "$1")" ;;
    *"{workspace}"*) printf 'space %s' "$(label_of "$1")" ;;
  esac
}

# The current name of the thing a command acts on, empty for a pane nobody has named.
label_of() {
  case "$1" in
    *"{pane}"*) jq -r --arg p "$SUBJ_PANE" '.panes[] | select(.pane_id == $p) | .label // empty' <<<"$SNAP" ;;
    *"{tab}"*) jq -r --arg t "$SUBJ_TAB" '.tabs[] | select(.tab_id == $t) | .label' <<<"$SNAP" ;;
    *"{workspace}"*) jq -r --arg w "$SUBJ_WS" '.workspaces[] | select(.workspace_id == $w) | .label' <<<"$SNAP" ;;
  esac
}

# One line of text, starting from the third argument, or a failure on escape. A picker with no
# rows is a text prompt, and accept-or-print-query hands back what was typed when there is
# nothing to accept. fzf says no match as it does so, so only its escape status counts as a
# cancel.
ask() {
  local out
  out=$(fzf --reverse --prompt "$1 " --header "$2" --query "${3:-}" --footer "enter confirm" \
    --bind 'enter:accept-or-print-query' </dev/null)
  [ $? -eq 130 ] && return 1
  printf '%s' "$out"
}

confirm() {
  local pick
  pick=$(printf '%s\n' "no, keep it" "yes, $(tr '[:upper:]' '[:lower:]' <<<"$1")" \
    | fzf --reverse --no-input --header "$2" --footer "enter choose") || return 1
  [ "${pick%%,*}" = yes ]
}

# Every worktree of the repository the space sits in, the path of the one chosen, or a failure
# on escape or when the space is not in a repository, which herdr's own message explains.
choose_worktree() {
  local list pick
  list=$("$HERDR" worktree list --workspace "$SUBJ_WS" 2>&1)
  if ! jq -e '.result.worktrees' <<<"$list" >/dev/null 2>&1; then
    notify "$(jq -r '.error.message // empty' <<<"$list" 2>/dev/null | grep . || printf 'no worktrees here')"
    return 1
  fi
  pick=$(jq -r --arg home "$HOME" '
    .result.worktrees[] | select(.is_bare | not)
    | [.path, (.branch // "detached"), (.path | sub("^" + $home; "~")),
       (if .open_workspace_id then "open" else "" end)] | @tsv
  ' <<<"$list" | fzf --reverse --ansi --delimiter '\t' --with-nth 2.. --prompt "worktree " \
    --footer "enter open") || return 1
  printf '%s' "${pick%%$'\t'*}"
}

# The value of one placeholder for the subject, or a failure when the person backed out of the
# prompt or the picker that supplies it. {input} and {label} ask for a line of text when they
# are reached, {label} starting from the current name of what the template acts on. TEMPLATE
# and TITLE are the action being expanded, for the prompt's wording.
value_of() {
  case "$1" in
    pane) printf '%s' "$SUBJ_PANE" ;;
    tab) printf '%s' "$SUBJ_TAB" ;;
    workspace) printf '%s' "$SUBJ_WS" ;;
    cwd) printf '%s' "$SUBJ_CWD" ;;
    input | label)
      local prefill="" text
      [ "$1" = label ] && prefill=$(label_of "$TEMPLATE")
      text=$(ask "$(tr '[:upper:]' '[:lower:]' <<<"$TITLE")" "$(describe "$TEMPLATE")" "$prefill") || return 1
      [ -n "$text" ] || return 1
      printf '%s' "$text"
      ;;
    worktree) choose_worktree ;;
    # tab.move takes the slot the tab is inserted before, counted before it is lifted out, so
    # one place left is its position less one and one place right is its position plus two,
    # held at either end.
    tab_slot_left | tab_slot_right)
      jq -r --arg t "$SUBJ_TAB" --arg w "$SUBJ_WS" --arg side "$1" '
        [.tabs[] | select(.workspace_id == $w) | .tab_id] as $l
        | ([$l | to_entries[] | select(.value == $t) | .key] | first) as $i
        | if $side == "tab_slot_left" then [$i - 1, 0] | max else [$i + 2, ($l | length)] | min end
      ' <<<"$SNAP"
      ;;
    *) return 1 ;;
  esac
}

# The template's words into OUT, each placeholder replaced by exactly one argument, so a name
# with spaces in it stays whole. A word may also be key={placeholder}, for a socket request.
expand() {
  local word words key val
  OUT=()
  read -ra words <<<"$1"
  for word in "${words[@]}"; do
    key="" val="$word"
    case "$word" in *=\{*\}) key="${word%%=*}=" val="${word#*=}" ;; esac
    case "$val" in
      \{*\}) val="${val#\{}"; val=$(value_of "${val%\}}") || return 1 ;;
    esac
    OUT+=("$key$val")
  done
}

# A socket request from method and key=value words, a number where the value is all digits.
api_json() {
  jq -nc --arg m "$1" '{id: "palette", method: $m,
    params: ($ARGS.positional | map(capture("^(?<k>[^=]+)=(?<v>.*)$")
      | {(.k): (if .v | test("^[0-9]+$") then .v | tonumber else .v end)}) | add // {})}' \
    --args "${@:2}"
}

# A shell template with each placeholder it names replaced by that value, quoted for bash.
shell_expand() {
  local cmd="$1" ph val
  for ph in pane tab workspace cwd input label; do
    case "$cmd" in *"{$ph}"*)
      val=$(value_of "$ph") || return 1
      cmd="${cmd//\{$ph\}/$(printf '%q' "$val")}"
    esac
  done
  printf '%s' "$cmd"
}

# herdr focuses a pane only by direction, from a pane beside it. So the pane's tab comes first,
# then a pane in that tab whose neighbour in some direction is the target takes one step that
# way, which leaves herdr to decide what beside means. A pane alone in its tab, or already the
# focused one there, needs only the tab.
focus_pane() {
  local target="$1" tab q d
  tab=$(jq -r --arg p "$target" '.panes[] | select(.pane_id == $p) | .tab_id' <<<"$SNAP")
  run tab focus "$tab" || return 0
  [ "$("$HERDR" pane layout --pane "$target" 2>/dev/null | jq -r '.result.layout.focused_pane_id')" = "$target" ] && return 0
  for q in $(jq -r --arg p "$target" --arg t "$tab" '.panes[] | select(.tab_id == $t and .pane_id != $p) | .pane_id' <<<"$SNAP"); do
    for d in left right up down; do
      if [ "$("$HERDR" pane neighbor --direction "$d" --pane "$q" 2>/dev/null | jq -r '.result.neighbor.neighbor_pane_id // empty')" = "$target" ]; then
        run pane focus --direction "$d" --pane "$q"
        return 0
      fi
    done
  done
}

# The next or previous space, tab or agent, in their order on screen, wrapping at either end.
step() {
  local kind="$1" delta="${2#+}" target
  target=$(jq -r --arg kind "$kind" --argjson d "$delta" \
    --arg pane "$SUBJ_PANE" --arg tab "$SUBJ_TAB" --arg ws "$SUBJ_WS" '
    . as $s
    | ($s.workspaces | to_entries | map({key: .value.workspace_id, value: .key}) | from_entries) as $wn
    | ($s.tabs | to_entries | map({key: .value.tab_id, value: .key}) | from_entries) as $tn
    | ( if $kind == "workspace" then [[$s.workspaces[] | .workspace_id], $ws]
        elif $kind == "tab" then [[$s.tabs[] | select(.workspace_id == $ws) | .tab_id], $tab]
        else [[$s.agents | sort_by($wn[.workspace_id], $tn[.tab_id])[] | .pane_id], $pane] end ) as [$list, $here]
    | ($list | length) as $n
    | if $n == 0 then empty else
        ([$list | to_entries[] | select(.value == $here) | .key] | first) as $i
        | if $i == null then $list[0] else $list[(($i + $d) % $n + $n) % $n] end
      end
  ' <<<"$SNAP")
  [ -n "$target" ] || return 0
  case "$kind" in
    workspace) run workspace focus "$target" ;;
    tab) run tab focus "$target" ;;
    agent) run agent focus "$target" ;;
  esac
}

# One line of palette-actions run against the subject. run is a herdr command, confirm is the
# same after a yes, api is a request to the socket, shell is a short bash script, step moves
# along the spaces, tabs or agents, and key names the key for what only herdr's window does.
# The command is everything after the third bar, so a shell action may use pipes.
action() {
  local id mode json
  IFS='|' read -r id mode TITLE TEMPLATE < <(grep -E "^$1[[:space:]]*\|" "$ACTIONS" | head -n 1)
  mode=$(trim "$mode") TITLE=$(trim "$TITLE") TEMPLATE=$(trim "$TEMPLATE")
  case "$mode" in
    run) expand "$TEMPLATE" && run "${OUT[@]}" ;;
    confirm)
      confirm "$TITLE $(describe "$TEMPLATE")" "$(describe "$TEMPLATE")" || return 0
      expand "$TEMPLATE" && run "${OUT[@]}"
      ;;
    api)
      expand "$TEMPLATE" || return 0
      json=$(api_json "${OUT[@]}") && launch "$0" --after-api "$json"
      ;;
    shell)
      json=$(shell_expand "$TEMPLATE") || return 0
      launch "$0" --after-shell "$json"
      ;;
    step) step $TEMPLATE ;;
    key) notify "$TITLE is $(press "$(jq -r --arg id "$1" '.[$id] // empty' <<<"$KEYS")")" ;;
  esac
}

# The action palette-keys gives this key on this kind of row, run with the row as the subject.
row_key() {
  local id
  id=$(grep -vE '^[[:space:]]*(#|$)' "$KEYMAP" | awk -F'|' -v key="$1" -v kind="$2" '
    { k = $1; gsub(/^[ \t]+|[ \t]+$/, "", k); a = $3; gsub(/^[ \t]+|[ \t]+$/, "", a)
      if (k == key && (" " $2 " ") ~ (" " kind " ")) { print a; exit } }')
  [ -n "$id" ] || return 0
  subject_from_row "$2" "$3"
  action "$id"
}

# A custom command runs the way its type says, a plugin action through herdr and anything
# else through the shell, both detached since either may open a popup.
custom_run() {
  local key type desc command
  IFS=$'\t' read -r key type desc command < <(custom_commands | sed -n "$1p")
  case "$type" in
    plugin_action) launch "$HERDR" plugin action invoke "$command" ;;
    *) launch sh -c "$command" ;;
  esac
}

# A client is attached to one session and herdr cannot move it to another from inside, so
# choosing a session says how to get there.
session() {
  if "$HERDR" session list --json 2>/dev/null | jq -e --arg n "$1" --arg sock "${HERDR_SOCKET_PATH:-}" '
      .sessions[] | select(.name == $n) | if $sock != "" then .socket_path == $sock else .default end
    ' >/dev/null; then
    notify "already on session $1"
  else
    notify "detach with $(press "$(jq -r '.detach // "prefix+q"' <<<"$KEYS")"), then run herdr --session $1"
  fi
}

# Where this run keeps the scroll count, removed when the palette closes.
PALETTE_RUN=$(mktemp -d)
export PALETTE_RUN
trap 'rm -rf "$PALETTE_RUN"' EXIT

# The keys a row answers besides enter, every key palette-keys names, for --expect.
ROW_KEYS=$(grep -vE '^[[:space:]]*(#|$)' "$KEYMAP" | awk -F'|' '{ gsub(/[ \t]/, "", $1); print $1 }' | sort -u | paste -sd, -)

# The preview sits under the list, so a row keeps the full width the format above measured.
# Moving the cursor rewrites the footer for that row and shows or hides the preview.
result=$(rows | format | fzf \
  --reverse \
  --ansi \
  --delimiter '\t' \
  --with-nth 3 \
  --no-hscroll \
  --prompt "herdr " \
  --footer "enter run, type a group to narrow" \
  --expect "$ROW_KEYS" \
  --preview "'$0' --preview {1} {2}" \
  --preview-window 'down,45%,border-top,follow' \
  --bind "focus,load:transform:'$0' --focus {1}" \
  --bind "preview-scroll-down,shift-down:transform:'$0' --scroll down" \
  --bind "preview-scroll-up,shift-up:transform:'$0' --scroll up" \
  --bind 'ctrl-/:toggle-preview') || exit 0

key=$(head -n 1 <<<"$result")
pick=$(sed -n 2p <<<"$result")
[ -n "$pick" ] || exit 0
IFS=$'\t' read -r kind target _ <<<"$pick"
remember "$kind" "$target"

if [ -n "$key" ]; then
  row_key "$key" "$kind" "$target"
  exit 0
fi

case "$kind" in
  agent) run agent focus "$target" ;;
  space) run workspace focus "$target" ;;
  tab) run tab focus "$target" ;;
  pane) focus_pane "$target" ;;
  action) action "$target" ;;
  command) custom_run "$target" ;;
  plugin) set -- $target; launch "$HERDR" plugin action invoke "$2" --plugin "$1" ;;
  session) session "$target" ;;
esac
exit 0
