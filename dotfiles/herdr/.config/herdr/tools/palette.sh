#!/usr/bin/env bash
# One searchable list of everything herdr can be asked to do from here. Every agent, space,
# tab and session, every action herdr has, every custom command in config.toml and every
# action another plugin offers, each row showing the key that does the same thing, and enter
# does it.
#
# Each row carries a kind and a target in two hidden fields, and one dispatch at the bottom
# hands each kind to its handler. The actions themselves are data in palette-actions beside
# this file, so this engine names no herdr action anywhere.
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
CONFIG="${HERDR_CONFIG_PATH:-$TOOLS/../config.toml}"
ACTIONS="$TOOLS/palette-actions"

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
KEYS=$(shortcuts)

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
    | {blocked: 0, done: 1, working: 2, idle: 3} as $want
    | ( $s.agents
        | map(. + {w: $ws_by[.workspace_id], t: $tabs[.tab_id],
                   topic: (((.terminal_title_stripped // "") | sub("^[^@ ]+@[^: ]+:"; "")) as $t
                           | if $t != "" then $t else .agent end)})
        | sort_by($want[.agent_status] // 4, .w.number, .t.number) | .[]
        | {kind: "agent", target: .pane_id, group: "agent", state: .agent_status,
           title: (($pane_by[.pane_id] | named) // .topic),
           detail: (if ($pane_by[.pane_id].label // "") != "" then .topic else "" end),
           status: (.agent_status // ""),
           right: "\(.w.label)/\(.t.label)", here: (.pane_id == $pane)} ),
      ( $s.workspaces | sort_by(.number) | .[]
        | {kind: "space", target: .workspace_id, group: "space", state: .agent_status,
           title: .label, right: "\(.tab_count) tabs", here: (.workspace_id == $ws)} ),
      ( $s.tabs
        | map(. + {w: $ws_by[.workspace_id], p: ($panes_in[.tab_id] // [])})
        | sort_by(.w.number, .number) | .[]
        | {kind: "tab", target: .tab_id, group: "tab", state: .agent_status, title: .label,
           detail: (if (.p | length) == 1 and .p[0].agent == null
                    then .p[0] | ((named | . + "  ") // "") + shown else "" end),
           right: .w.label, here: (.tab_id == $tab)} ),
      ( $s.panes
        | map(select(.agent == null and (($panes_in[.tab_id] // []) | length) > 1)
              | . + {w: $ws_by[.workspace_id], t: $tabs[.tab_id]})
        | sort_by(.w.number, .t.number) | .[]
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

# The last fifty rows picked, most recent first, one kind and target per line. It lives beside
# herdr's own state in the home directory, since the script's folder resolves into this
# checkout through the plugin link.
RECENT="$HOME/.config/herdr/palette-recent"

remember() {
  local line="$1"$'\t'"$2"
  { printf '%s\n' "$line"; grep -vxF "$line" "$RECENT" 2>/dev/null; } | head -n 50 > "$RECENT.tmp" \
    && mv "$RECENT.tmp" "$RECENT"
}

# Runs one herdr command and reports a failure, since a herdr error is JSON on stderr and the
# popup is about to close, which leaves the notification as the only place it can appear.
run() {
  local err
  err=$("$HERDR" "$@" 2>&1 >/dev/null) && return 0
  notify "$(jq -r '.error.message // empty' <<<"$err" 2>/dev/null | grep . || printf '%s' "${err%%$'\n'*}")"
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
    *"{pane}"*) printf 'pane %s' "$(jq -r --arg p "$HERE_PANE" '.panes[] | select(.pane_id == $p) | .label // .terminal_title_stripped // .pane_id' <<<"$SNAP")" ;;
    *"{tab}"*) printf 'tab %s' "$(label_of "$1")" ;;
    *"{workspace}"*) printf 'space %s' "$(label_of "$1")" ;;
  esac
}

# The current name of the thing a command acts on, empty for a pane nobody has named.
label_of() {
  case "$1" in
    *"{pane}"*) jq -r --arg p "$HERE_PANE" '.panes[] | select(.pane_id == $p) | .label // empty' <<<"$SNAP" ;;
    *"{tab}"*) jq -r --arg t "$HERE_TAB" '.tabs[] | select(.tab_id == $t) | .label' <<<"$SNAP" ;;
    *"{workspace}"*) jq -r --arg w "$HERE_WS" '.workspaces[] | select(.workspace_id == $w) | .label' <<<"$SNAP" ;;
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
  list=$("$HERDR" worktree list --workspace "$HERE_WS" 2>&1)
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

# The template's words, each placeholder replaced by exactly one argument. {worktree} asks for
# its value when it is reached, so a template names what it needs and the list comes up then.
expand_and_run() {
  local word words choice out=()
  read -ra words <<<"$1"
  for word in "${words[@]}"; do
    case "$word" in
      "{pane}") out+=("$HERE_PANE") ;;
      "{tab}") out+=("$HERE_TAB") ;;
      "{workspace}") out+=("$HERE_WS") ;;
      "{cwd}") out+=("$HERE_CWD") ;;
      "{input}" | "{label}") out+=("$INPUT") ;;
      "{worktree}") choice=$(choose_worktree) || return 0; out+=("$choice") ;;
      *) out+=("$word") ;;
    esac
  done
  run "${out[@]}"
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

# The next or previous space, tab or agent, in the order the sidebar numbers them, wrapping
# at either end.
step() {
  local kind="$1" delta="${2#+}" target
  target=$(jq -r --arg kind "$kind" --argjson d "$delta" \
    --arg pane "$HERE_PANE" --arg tab "$HERE_TAB" --arg ws "$HERE_WS" '
    . as $s
    | ($s.workspaces | map({key: .workspace_id, value: .number}) | from_entries) as $wn
    | ($s.tabs | map({key: .tab_id, value: .number}) | from_entries) as $tn
    | ( if $kind == "workspace" then [[$s.workspaces | sort_by(.number)[] | .workspace_id], $ws]
        elif $kind == "tab" then [[$s.tabs | map(select(.workspace_id == $ws)) | sort_by(.number)[] | .tab_id], $tab]
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

action() {
  local id mode title command what prefill
  IFS='|' read -r id mode title command < <(grep -E "^$1[[:space:]]*\|" "$ACTIONS" | head -n 1)
  mode=$(trim "$mode") title=$(trim "$title") command=$(trim "$command")
  case "$mode" in
    run) expand_and_run "$command" ;;
    ask)
      what=$(describe "$command")
      case "$command" in *"{label}"*) prefill=$(label_of "$command") ;; *) prefill="" ;; esac
      INPUT=$(ask "$(tr '[:upper:]' '[:lower:]' <<<"$title")" "$what" "$prefill") || return 0
      [ -n "$INPUT" ] && expand_and_run "$command"
      ;;
    confirm)
      what=$(describe "$command")
      confirm "$title $what" "$what" && expand_and_run "$command"
      ;;
    step) step $command ;;
    key) notify "$title is $(press "$(jq -r --arg id "$1" '.[$id] // empty' <<<"$KEYS")")" ;;
  esac
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

pick=$(rows | format | fzf \
  --reverse \
  --ansi \
  --delimiter '\t' \
  --with-nth 3 \
  --no-hscroll \
  --prompt "herdr " \
  --footer "enter run, type a group to narrow") || exit 0

IFS=$'\t' read -r kind target _ <<<"$pick"
remember "$kind" "$target"
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
