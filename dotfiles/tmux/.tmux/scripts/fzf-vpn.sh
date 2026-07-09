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

# The fixed top block, rebuilt from normalized adapter data on every action.
status_header() {
  local state location relay line
  IFS=$'\t' read -r state location relay < <(vpn_status)
  if [ "$state" = "connected" ]; then
    line="● CONNECTED"
    [ -n "$location" ] && line="$line   $location"
    [ -n "$relay" ] && line="$line   $relay"
    printf 'VPN · %s\n%s\n^space disconnect\n' "$(vpn_name)" "$line"
  else
    printf 'VPN · %s\n○ DISCONNECTED\n^space connect\n' "$(vpn_name)"
  fi
}

# State-aware single action bound to ctrl-space.
toggle() {
  local state
  IFS=$'\t' read -r state _ _ < <(vpn_status)
  if [ "$state" = "connected" ]; then vpn_disconnect; else vpn_connect; fi
}

# Internal subcommands invoked by the fzf key bindings and by the launcher.
case "$1" in
  --name)   vpn_name; exit 0;;
  --header) status_header; exit 0;;
  --list)   vpn_locations; exit 0;;
  --toggle) toggle; exit 0;;
  --set)    vpn_set_location "$2"; exit 0;;
esac

vpn_locations | fzf "${FZF_BASE_OPTS[@]}" \
  --delimiter=$'\t' \
  --with-nth=1 \
  --nth=1 \
  --header-first \
  --header="$(status_header)" \
  --border-label="$(fzf_label "↵ switch here" "^space connect/disconnect" "q / ^c / ^d close")" \
  --prompt='search> ' \
  --bind "enter:execute-silent($SELF --set {2})+transform-header($SELF --header)" \
  --bind "ctrl-space:execute-silent($SELF --toggle)+transform-header($SELF --header)" \
  --bind "q:abort" \
  --bind "ctrl-d:abort"
