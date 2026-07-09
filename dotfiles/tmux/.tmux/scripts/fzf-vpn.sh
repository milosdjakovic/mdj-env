#!/usr/bin/env bash
# shellcheck source=fzf-base.sh
. "$(dirname "$0")/fzf-base.sh"
# VPN control popup, shown in the launcher (prefix+space) as "VPN service".
#
# This file is the whole interface and it is deliberately rigid. It never talks
# to a VPN directly. It asks the active adapter for normalized values and lays
# them out the same way for any provider. All VPN specifics live in
# vpn/<adapter>.sh, which must define vpn_name, vpn_status, vpn_connect,
# vpn_disconnect, vpn_locations, and vpn_set_location. See vpn/_template.sh.
#
# Called from fzf-launcher.sh:
#   tmux display-popup -w 80% -h 80% -E "~/.tmux/scripts/fzf-vpn.sh"

DIR="$(dirname "$0")"
SELF="$0"
VPN_ADAPTER="${VPN_ADAPTER:-mullvad}"

if [ ! -r "$DIR/vpn/$VPN_ADAPTER.sh" ]; then
  echo "vpn adapter not found: $DIR/vpn/$VPN_ADAPTER.sh" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$DIR/vpn/$VPN_ADAPTER.sh"

# Bright white for the state word so it reads at a glance. Everything else in
# the header keeps fzf's default (dimmer) header color for hierarchy.
WHITE=$'\033[97m'
RESET=$'\033[0m'
# Trailing marker on the currently configured relay row.
MARK=' <'

# One status line: provider, state, location, and relay when connected.
status_line() {
  local state location relay target line
  IFS=$'\t' read -r state location relay target < <(vpn_status)
  if [ "$state" = "connected" ]; then
    line="$(vpn_name)   ${WHITE}CONNECTED${RESET}"
    [ -n "$location" ] && line="$line   $location"
    [ -n "$relay" ] && line="$line   $relay"
  else
    line="$(vpn_name)   ${WHITE}DISCONNECTED${RESET}"
    [ -n "$location" ] && line="$line   $location"
  fi
  printf '%s\n' "$line"
}

# Bottom border hints. The connect or disconnect verb follows the state.
border_label() {
  local state verb
  IFS=$'\t' read -r state _ _ _ < <(vpn_status)
  if [ "$state" = "connected" ]; then verb="disconnect"; else verb="connect"; fi
  fzf_label "↵ switch here" "^space $verb" "^c / ^d close"
}

# The searchable list, DISPLAY<TAB>ID. The currently configured relay gets a
# trailing marker so it reads the same whether or not the cursor is on it.
render_list() {
  local target disp id
  target="$(vpn_status | cut -f4)"
  vpn_locations | while IFS=$'\t' read -r disp id; do
    if [ "$id" = "$target" ]; then
      printf '%s%s\t%s\n' "$disp" "$MARK" "$id"
    else
      printf '%s\t%s\n' "$disp" "$id"
    fi
  done
}

# State-aware single action bound to ctrl-space.
toggle() {
  local state
  IFS=$'\t' read -r state _ _ _ < <(vpn_status)
  if [ "$state" = "connected" ]; then vpn_disconnect; else vpn_connect; fi
}

# Internal subcommands invoked by the fzf key bindings and by the launcher.
case "$1" in
  --name)   vpn_name; exit 0;;
  --header) status_line; exit 0;;
  --label)  border_label; exit 0;;
  --list)   render_list; exit 0;;
  --toggle) toggle; exit 0;;
  --set)    vpn_set_location "$2"; exit 0;;
esac

render_list | fzf "${FZF_BASE_OPTS[@]}" \
  --ansi \
  --delimiter=$'\t' \
  --with-nth=1 \
  --nth=1 \
  --header-first \
  --header="$(status_line)" \
  --border-label="$(border_label)" \
  --prompt='search> ' \
  --padding='0,1' \
  --bind "enter:execute-silent($SELF --set {2})+reload($SELF --list)+transform-header($SELF --header)+transform-border-label($SELF --label)" \
  --bind "ctrl-space:execute-silent($SELF --toggle)+reload($SELF --list)+transform-header($SELF --header)+transform-border-label($SELF --label)" \
  --bind "ctrl-d:abort"
