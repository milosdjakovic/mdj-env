#!/usr/bin/env bash
# shellcheck source=fzf-base.sh
. "$(dirname "$0")/fzf-base.sh"
# Keep-awake control popup, shown in the launcher (prefix+space) as "Keep awake".
#
# Mirrors the VPN popup (fzf-vpn.sh) in shape: a single fzf instance that never
# auto closes, a one-line status header, a state-aware bottom border, and a body
# list whose active row is marked. It exposes four actions:
#   Indefinite       keep the Mac awake with no timeout
#   For a duration   keep awake for N hours and minutes (type e.g. 1h30m, 45m)
#   Until a time     keep awake until an HH:MM within the next 24h (type 16:45)
#   Disable          stop any active keep-awake
#
# Unlike VPN there is no swappable adapter, because macOS has a single backend,
# the `caffeinate` binary. A keep-awake is one detached `caffeinate` process; a
# small state file records its pid, mode, and end time so status survives across
# popup opens. Timed modes pass `-t <seconds>` so caffeinate self-exits.
#
# Input is validated in two layers. The typed value is restricted per focused
# row (duration accepts digits, h, m; until accepts digits and colon) so stray
# keys like `y` never land. The full value is then checked for a valid format on
# apply, and a bad one shows an INVALID header instead of doing anything. A
# successful apply clears the input.
#
# Called from fzf-launcher.sh:
#   tmux display-popup -w 52 -h 11 -E "~/.tmux/scripts/fzf-caffeinate.sh"

SELF="$0"
CAFFEINATE="${CAFFEINATE:-/usr/bin/caffeinate}"
STATE_FILE="${TMPDIR:-/tmp}/tmux-caffeinate.state"
MSG_FILE="${TMPDIR:-/tmp}/tmux-caffeinate.msg"

# Bright white for the state word, red for an invalid value, matching the
# header emphasis used in fzf-vpn.sh. Dim gray (the palette label color from
# fzf-base.sh) for the format hints so they recede like the header label, and
# the fg+ dark (the palette highlight foreground) for the hint on the focused
# row so it reads as normal highlighted text on the green bar instead of staying
# gray. fzf keeps an ANSI foreground even on the current line, so the focused
# row is re-rendered with the dark hint on every focus change.
WHITE=$'\033[97m'
RED=$'\033[91m'
DIM=$'\033[38;2;148;148;148m'
FOCUSFG=$'\033[38;2;21;20;27m'
RESET=$'\033[0m'
# Trailing marker on the currently active mode row.
MARK=' <'

# Prevent display, idle, and system sleep. -s only holds on AC power, which is
# the desired "don't sleep while plugged in" behaviour.
CAFF_ARGS=(-d -i -s)

# --- mechanism, all the caffeinate specifics live below ---

# Prints "PID<TAB>MODE<TAB>END" when a keep-awake is live, nothing otherwise.
# END is the target epoch, or 0 for indefinite. A dead pid clears stale state.
_state() {
  [ -r "$STATE_FILE" ] || return 0
  local pid mode end
  IFS=$'\t' read -r pid mode end <"$STATE_FILE"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    printf '%s\t%s\t%s\n' "$pid" "$mode" "$end"
  else
    rm -f "$STATE_FILE"
  fi
}

# Stops any active keep-awake and clears state.
_disable() {
  local pid mode end
  [ -r "$STATE_FILE" ] || return 0
  IFS=$'\t' read -r pid mode end <"$STATE_FILE"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  rm -f "$STATE_FILE"
}

# Starts a detached caffeinate. $1 is the mode label, $2 the timeout in seconds
# (0 for indefinite). Any prior keep-awake is replaced.
_start() {
  local mode="$1" secs="$2" end=0 pid
  _disable
  local args=("${CAFF_ARGS[@]}")
  if [ "${secs:-0}" -gt 0 ] 2>/dev/null; then
    args+=(-t "$secs")
    end=$(( $(date +%s) + secs ))
  fi
  nohup "$CAFFEINATE" "${args[@]}" >/dev/null 2>&1 &
  pid=$!
  disown 2>/dev/null
  printf '%s\t%s\t%s\n' "$pid" "$mode" "$end" >"$STATE_FILE"
}

# Parses a duration into seconds. A unit is required, so 1h30m, 45m, and 5h are
# accepted but a bare number is not. A colon or any other shape is rejected.
# Prints 0 when invalid.
_dur_secs() {
  local s="$1" h m
  if [ -n "$s" ] && printf '%s' "$s" | grep -Eq '^([0-9]+h)?([0-9]+m)?$'; then
    h=$(printf '%s' "$s" | grep -oE '[0-9]+h' | tr -dc '0-9'); h=${h:-0}
    m=$(printf '%s' "$s" | grep -oE '[0-9]+m' | tr -dc '0-9'); m=${m:-0}
  else
    printf '0\n'; return
  fi
  printf '%s\n' $(( h * 3600 + m * 60 ))
}

# Parses an HH:MM into seconds from now, rolling to tomorrow when the time has
# already passed today so the target is always within the next 24h. Prints 0
# when the input is not a valid HH:MM.
_until_secs() {
  local hhmm="$1" now target
  printf '%s' "$hhmm" | grep -Eq '^[0-9]{1,2}:[0-9]{2}$' || { printf '0\n'; return; }
  now=$(date +%s)
  target=$(date -j -f "%H:%M" "$hhmm" +%s 2>/dev/null) || { printf '0\n'; return; }
  [ -z "$target" ] && { printf '0\n'; return; }
  [ "$target" -le "$now" ] && target=$((target + 86400))
  printf '%s\n' $((target - now))
}

# Formats a seconds count as 1h23m or 45m.
_fmt_remain() {
  local s=$1 h m
  h=$((s / 3600)); m=$(((s % 3600) / 60))
  if [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"; else printf '%dm' "$m"; fi
}

# --- interface, the layout the fzf popup and the launcher consume ---

# One status line: label, state, and mode detail when active. A pending invalid
# message wins, so a rejected value reads clearly until the input changes.
status_line() {
  if [ -s "$MSG_FILE" ]; then
    printf 'Keep Awake   %sINVALID%s   %s\n' "$RED" "$RESET" "$(cat "$MSG_FILE")"
    return
  fi
  local st pid mode end now remain line
  st=$(_state)
  if [ -z "$st" ]; then
    printf 'Keep Awake   %sINACTIVE%s\n' "$WHITE" "$RESET"
    return
  fi
  IFS=$'\t' read -r pid mode end <<<"$st"
  line="Keep Awake   ${WHITE}ACTIVE${RESET}"
  if [ "$mode" = indefinite ] || [ "${end:-0}" = 0 ]; then
    line="$line   indefinite"
  else
    now=$(date +%s); remain=$((end - now))
    line="$line   until $(date -r "$end" +%H:%M)"
    [ "$remain" -gt 0 ] && line="$line   ($(_fmt_remain "$remain") left)"
  fi
  printf '%s\n' "$line"
}

# Short status for the launcher entry label. Empty when inactive.
summary() {
  local st pid mode end
  st=$(_state); [ -z "$st" ] && return 0
  IFS=$'\t' read -r pid mode end <<<"$st"
  if [ "$mode" = indefinite ] || [ "${end:-0}" = 0 ]; then
    printf 'ACTIVE, indefinite\n'
  else
    printf 'ACTIVE, until %s\n' "$(date -r "$end" +%H:%M)"
  fi
}

# Bottom border hints.
border_label() {
  fzf_label "↵ apply" "q close"
}

# The action list, DISPLAY<TAB>ID. The active mode row gets a trailing marker so
# it reads the same whether or not the cursor is on it. Disable is never marked.
# $1 is the currently focused row id, whose hint renders dark instead of gray.
render_list() {
  local cur focused="$1"
  cur=$(_state | cut -f2)
  _row "Indefinite"     ""                     indefinite "$cur" "$focused"
  _row "For a duration" "type e.g. 1h30m, 45m" duration   "$cur" "$focused"
  _row "Until a time"   "type e.g. 16:45"      until      "$cur" "$focused"
  _row "Disable"        ""                     disable    "$cur" "$focused"
}

_row() {
  local disp="$1" hint="$2" id="$3" cur="$4" focused="$5" label="$1" color="$DIM"
  [ "$id" = "$focused" ] && color="$FOCUSFG"
  [ -n "$hint" ] && label="$disp   ${color}($hint)${RESET}"
  if [ "$id" = "$cur" ] && [ "$id" != disable ]; then
    printf '%s%s\t%s\n' "$label" "$MARK" "$id"
  else
    printf '%s\t%s\n' "$label" "$id"
  fi
}

# Restricts a typed value to the charset the focused row can use, so invalid
# keys are dropped as they are typed. Also clears any pending invalid message,
# since editing the value means the user is fixing it. Prints the cleaned value,
# which fzf sets back as the query via transform-query.
sanitize() {
  local mode="$1" q="$2"
  rm -f "$MSG_FILE"
  case "$mode" in
    duration) printf '%s' "$q" | tr -cd '0-9hm';;
    until)    printf '%s' "$q" | tr -cd '0-9:';;
    *)        : ;;  # indefinite and disable take no input
  esac
}

# Emits the fzf actions to run after a successful apply: clear the input, rebuild
# the list, and refresh the header and border from fresh state.
_ok() {
  rm -f "$MSG_FILE"
  printf 'clear-query+reload(%s --list)+transform-header(%s --header)+transform-border-label(%s --label)' \
    "$SELF" "$SELF" "$SELF"
}

# Records an invalid message and emits the header refresh that surfaces it,
# leaving the bad input in place so the user can correct it.
_err() {
  printf '%s\n' "$1" >"$MSG_FILE"
  printf 'transform-header(%s --header)' "$SELF"
}

# Validates and runs one action, then prints the follow-up fzf actions. Bound to
# enter through fzf's transform action. $2 is the typed value.
apply() {
  local mode="$1" arg="$2" secs
  case "$mode" in
    indefinite) _start indefinite 0; _ok;;
    disable)    _disable; _ok;;
    duration)
      secs=$(_dur_secs "$arg")
      if [ "$secs" -gt 0 ]; then _start duration "$secs"; _ok
      else _err "use e.g. 1h30m or 45m"; fi;;
    until)
      secs=$(_until_secs "$arg")
      if [ "$secs" -gt 0 ]; then _start until "$secs"; _ok
      else _err "use HH:MM, next 24h"; fi;;
  esac
}

# Internal subcommands invoked by the fzf key bindings and by the launcher.
case "$1" in
  --name)     printf 'Keep Awake\n'; exit 0;;
  --summary)  summary; exit 0;;
  --header)   status_line; exit 0;;
  --label)    border_label; exit 0;;
  --list)     render_list "$2"; exit 0;;
  --sanitize) sanitize "$2" "$3"; exit 0;;
  --apply)    apply "$2" "$3"; exit 0;;
  # Re-render the list with $3 (focused id) as the dark row, then restore the
  # cursor to its index ($2 from fzf's {n}, zero-based), since reload resets it.
  --refocus)  printf 'reload(%s --list %s)+pos(%d)' "$SELF" "$3" "$(( ${2:-0} + 1 ))"; exit 0;;
esac

# Start clean so a stale message from a previous popup does not linger.
rm -f "$MSG_FILE"

# Search is disabled so typing feeds the value for the timed modes instead of
# filtering the four fixed rows. `change` restricts the charset as you type and
# `focus` resets the field when you move rows, since each mode wants a different
# format. `q` exits because the charset never needs it.
render_list | fzf "${FZF_BASE_OPTS[@]}" \
  --ansi \
  --disabled \
  --delimiter=$'\t' \
  --with-nth=1 \
  --header-first \
  --header="$(status_line)" \
  --border-label="$(border_label)" \
  --prompt='value> ' \
  --padding='0,1' \
  --bind "change:transform-query($SELF --sanitize {2} {q})+transform-header($SELF --header)" \
  --bind "focus:transform-query($SELF --sanitize {2})+transform-header($SELF --header)+transform($SELF --refocus {n} {2})" \
  --bind "enter:transform($SELF --apply {2} {q})" \
  --bind "q:abort" \
  --bind "ctrl-d:abort"
