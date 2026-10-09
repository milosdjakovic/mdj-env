#!/usr/bin/env bash
# Runs the palette against a herdr server of its own and checks what every kind of pick does.
#
# Nothing here touches the session you work in. It starts a headless named session, puts a
# scripted stand in for fzf first on the PATH and a wrapper around herdr that records
# notifications, and stops and deletes the session on the way out, whether the checks passed
# or not. Run it after changing the palette and after upgrading herdr, since the palette reads
# the shape of herdr's output and an upgrade can move it.
#
# Three things are left out. New agent starts a real coding agent, edit scrollback opens into a
# client, which a headless server does not have, and an agent's history needs a real agent for
# herdr to scroll. Each was tried by hand when written.
#
#   dotfiles/herdr/test/palette-test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PALETTE="$HERE/../.config/herdr/tools/palette.sh"
REAL_HERDR="$(command -v herdr)" || { echo "herdr is not on PATH"; exit 1; }
SESSION="palette-test-$$"
WORK="$(mktemp -d)"
PASS=0 FAIL=0

cleanup() {
  HERDR_SOCKET_PATH="$SOCK" "$REAL_HERDR" session stop "$SESSION" >/dev/null 2>&1
  sleep 0.3
  "$REAL_HERDR" session delete "$SESSION" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

check() {
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        wanted %s\n        got    %s\n' "$1" "$3" "$2"
  fi
}

# The stand in for fzf. The palette's own list either picks the row named by PICK, with KEY as
# the key it left on, or saves the rows it was given and leaves as escape does. A text prompt
# answers INPUT, or the prefilled query when INPUT is @query. A yes or no answers yes, and the
# worktree picker takes the line containing WT.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/fzf" <<'EOF'
#!/bin/bash
query="" prev=""
for a in "$@"; do [ "$prev" = --query ] && query="$a"; prev="$a"; done
case "$*" in
  *"--with-nth 3"*)
    if [ -z "${PICK:-}" ]; then cat > "$ROWS"; exit 130; fi
    line=$(awk -F'\t' -v p="$PICK" '($1 "\t" $2) == p' | head -n 1)
    [ -n "$line" ] || exit 1
    printf '%s\n%s\n' "${KEY:-}" "$line" ;;
  *"--prompt worktree"*) grep -F "$WT" | head -n 1 ;;
  *--no-input*) grep '^yes' ;;
  *) if [ "${INPUT:-}" = @query ]; then printf '%s\n' "$query"; else printf '%s\n' "${INPUT:-}"; fi ;;
esac
EOF
cat > "$WORK/bin/herdr" <<EOF
#!/bin/bash
if [ "\$1" = notification ]; then printf '%s\n' "\${*: -1}" >> "$WORK/notes"; exit 0; fi
exec "$REAL_HERDR" "\$@"
EOF
chmod +x "$WORK/bin/fzf" "$WORK/bin/herdr"

"$REAL_HERDR" --session "$SESSION" server >/dev/null 2>&1 &
SOCK="$HOME/.config/herdr/sessions/$SESSION/herdr.sock"
for _ in $(seq 50); do [ -S "$SOCK" ] && break; sleep 0.1; done
[ -S "$SOCK" ] || { echo "the test server did not start"; exit 1; }

export HERDR_SOCKET_PATH="$SOCK" HERDR_SESSION="$SESSION" HERDR_BIN_PATH="$WORK/bin/herdr"
export HERDR_PLUGIN_STATE_DIR="$WORK/state" ROWS="$WORK/rows" PATH="$WORK/bin:$PATH"
unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_ACTIVE_PANE_ID HERDR_ACTIVE_PANE_CWD
h() { "$REAL_HERDR" "$@"; }

# Opens the palette over a pane, PICK, KEY and INPUT taken from the environment of the call.
palette() { HERDR_PLUGIN_CONTEXT_JSON="{\"focused_pane_id\":\"$1\"}" "$PALETTE"; }
rows() { PICK="" palette "$1"; sed 's/\x1b\[[0-9;]*m//g' "$ROWS" | cut -f3 | tr -s ' '; }
focused() { h api snapshot | jq -r '.result.snapshot.focused_pane_id'; }
label() { h tab get "$1" | jq -r '.result.tab.label'; }
tabs() { h tab list --workspace "$1" | jq -r '[.result.tabs[].label] | join(" ")'; }
last_note() { tail -n 1 "$WORK/notes" 2>/dev/null; }

# A space with three tabs. The first holds three panes, a shell and two reported agents, one
# blocked and one idle, and the other two hold one shell each. A second space sits beside it.
mkdir -p "$WORK/repo"
git -C "$WORK/repo" init -q && git -C "$WORK/repo" commit -q --allow-empty -m init
git -C "$WORK/repo" worktree add -q -b feature "$WORK/repo-feature"
h workspace create --cwd "$WORK/repo" --label alpha --focus >/dev/null
h pane split w1:p1 --direction right --no-focus >/dev/null
h pane split w1:p2 --direction down --no-focus >/dev/null
h pane report-agent w1:p2 --source test --agent claude --state blocked >/dev/null
h pane report-agent w1:p3 --source test --agent codex --state idle >/dev/null
h tab create --workspace w1 --cwd "$WORK" --label second >/dev/null
h tab create --workspace w1 --cwd "$WORK" --label third >/dev/null
h pane rename w1:p5 lonely >/dev/null
h workspace create --cwd "$WORK" --label beta --focus >/dev/null

echo "rows"
r=$(rows w1:p1)
check "a blocked agent comes before an idle one" "$(grep '^agent' <<<"$r" | head -n 1 | grep -c blocked)" 1
check "the pane the palette was opened over says here" "$(grep -c '^pane .*, here$' <<<"$r")" 1
check "a tab of one pane carries that pane's name" "$(grep -c '^tab third lonely' <<<"$r")" 1
check "a pane alone in its tab has no row of its own" "$(grep '^pane' <<<"$r" | grep -c lonely)" 0
check "the test session is listed and says here" "$(grep -c "^session $SESSION running, here" <<<"$r")" 1

echo "focus"
PICK=$'agent\tw1:p3' palette w2:p1; check "an agent row focuses the agent" "$(focused)" w1:p3
PICK=$'tab\tw1:t2' palette w1:p1; check "a tab row focuses the tab" "$(focused)" w1:p4
PICK=$'pane\tw1:p1' palette w2:p1; check "a pane row reaches a pane beside others" "$(focused)" w1:p1

echo "actions on the place the palette was opened over"
PICK=$'action\trename_tab' INPUT=@query palette w1:p4; check "rename starts from the current name" "$(label w1:t2)" second
PICK=$'action\trename_tab' INPUT="second tab" palette w1:p4; check "rename keeps spaces in a name" "$(label w1:t2)" "second tab"
PICK=$'action\tnext_tab' palette w1:p5; check "next tab wraps to the first" "$(focused)" w1:p1
PICK=$'action\topen_worktree' WT=feature palette w1:p1
check "open worktree opens the picked one as a space" "$(h api snapshot | jq -r '[.result.snapshot.workspaces[].label] | index("repo-feature") != null')" true
PICK=$'action\tnew_tab' palette w2:p1 >/dev/null
PICK=$'action\tclose_tab' palette w1:p4
check "close asks first and then closes" "$(tabs w1)" "1 third"
PICK=$'action\tremove_worktree' palette w2:p1
check "a herdr refusal reaches a notification" "$(last_note | grep -c 'not a Herdr-managed worktree')" 1

echo "keys on a selected row"
PICK=$'tab\tw1:t3' KEY=ctrl-r INPUT="renamed" palette w1:p1; check "ctrl-r renames the selected tab" "$(label w1:t3)" renamed
PICK=$'space\tw2' KEY=ctrl-r INPUT="gamma" palette w1:p1
check "ctrl-r renames the selected space" "$(h workspace get w2 | jq -r .result.workspace.label)" gamma
PICK=$'agent\tw1:p3' KEY=ctrl-r INPUT="reviewer" palette w1:p1
check "ctrl-r on an agent names its pane" "$(h pane get w1:p3 | jq -r .result.pane.label)" reviewer
before=$(focused)
PICK=$'pane\tw1:p1' KEY=ctrl-p palette w1:p1
check "a key a row does not take does nothing" "$(focused)" "$before"

echo "socket actions"
last_pane=$(h tab create --workspace w1 --cwd "$WORK" --label fourth | jq -r .result.root_pane.pane_id)
PICK=$'action\tmove_tab_previous' palette "$last_pane"; sleep 0.8
check "move tab left goes one place left" "$(tabs w1)" "1 fourth renamed"
PICK=$'action\tmove_tab_next' palette "$last_pane"; sleep 0.8
check "move tab right goes one place right" "$(tabs w1)" "1 renamed fourth"
h pane run w1:p1 "echo palette-marker" >/dev/null; sleep 0.5
check "the marker is on screen before clearing" "$(h pane read w1:p1 --source visible | grep -c palette-marker)" 2
PICK=$'action\tclear_pane' palette w1:p1; sleep 0.8
check "clear pane empties the screen" "$(h pane read w1:p1 --source visible | grep -c palette-marker)" 0

echo "what fzf asks the script while the cursor moves"
f=$("$PALETTE" --focus agent)
check "an agent row lists rename, close and prompt" "$(grep -c 'ctrl-r rename, ctrl-x close, ctrl-p prompt' <<<"$f")" 1
check "an agent row shows the preview" "$(grep -c 'show-preview' <<<"$f")" 1
check "a command row hides the preview" "$("$PALETTE" --focus action | grep -c 'hide-preview')" 1
h pane run w1:p1 "echo preview-marker" >/dev/null; sleep 0.5
check "the preview shows the pane's screen" "$("$PALETTE" --preview pane w1:p1 | grep -c preview-marker)" 2
check "no carriage return reaches the preview" "$("$PALETTE" --preview pane w1:p1 | grep -c $'\r')" 0
check "the preview ends on output, not blank rows" "$("$PALETTE" --preview pane w1:p1 | tail -n 1 | grep -c '[^[:space:]]')" 1
check "short output fills the window from the bottom" "$(FZF_PREVIEW_LINES=200 "$PALETTE" --preview pane w1:p1 | wc -l | tr -d ' ')" 200
check "history on a plain pane is its preview" "$("$PALETTE" --history pane w1:p1 | md5)" "$("$PALETTE" --preview pane w1:p1 | md5)"
run_dir="$WORK/run"; mkdir -p "$run_dir"
PALETTE_RUN="$run_dir" "$PALETTE" --preview pane w1:p1 >/dev/null
check "a preview records its length for scrolling" "$(cat "$run_dir/below")" 0
scroll() { PALETTE_RUN="$run_dir" FZF_PREVIEW_LINES=5 "$PALETTE" --scroll "$1"; }
printf '12\n' > "$run_dir/lines"
check "scrolling down at the end does nothing" "$(scroll down)" ""
check "scrolling up from the end moves" "$(scroll up)" preview-up
for _ in 1 2 3 4 5 6 7 8; do scroll up >/dev/null; done
check "scrolling up stops once the first line shows" "$(cat "$run_dir/below")" 7
check "scrolling down comes back" "$(scroll down)" preview-down
check "an agent row offers its history" "$("$PALETTE" --focus agent | grep -c 'ctrl-o history')" 1

echo "recent picks"
PICK=$'tab\tw1:t3' palette w2:p1
PICK=$'action\tzoom' palette w2:p1
first=$(rows w2:p1 | head -n 2 | tr '\n' '|')
check "the last picks come first, newest at the top" "$(sed 's/ lonely .*|/|/' <<<"$first")" "command Zoom pane prefix+z|tab renamed|"
check "the history is kept for this session alone" "$(ls "$WORK/state")" "recent-$SESSION"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
