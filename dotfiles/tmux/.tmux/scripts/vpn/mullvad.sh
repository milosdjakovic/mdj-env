#!/usr/bin/env bash
# Mullvad adapter for fzf-vpn.sh. This is the only file that knows the mullvad
# CLI. Each function returns values normalized to the TUI contract, and a
# function may run several CLI commands to produce one normalized answer.
#
# Contract expected by fzf-vpn.sh:
#   vpn_name          prints a human label
#   vpn_status        prints STATE<TAB>LOCATION<TAB>RELAY<TAB>TARGET_ID
#                     STATE is connected|disconnected. LOCATION is the human
#                     label of the target relay. RELAY is the server hostname
#                     when connected. TARGET_ID is the id of the target relay,
#                     used to mark the active row in the list.
#   vpn_connect       connects to the current or last relay
#   vpn_disconnect    disconnects
#   vpn_locations     prints DISPLAY<TAB>ID per line
#   vpn_set_location  selects the server for an ID and connects

# Named rather than pathed, so this module stays ignorant of where anything is installed and
# works the same on either architecture. Still overridable, which is how the contract above can
# be exercised against a stub.
MULLVAD="${MULLVAD:-mullvad}"

vpn_name() { printf 'Mullvad\n'; }

vpn_status() {
  local raw state relay target location
  raw="$("$MULLVAD" status 2>/dev/null)"
  if printf '%s' "$raw" | grep -q '^Connected'; then
    state=connected
    relay="$(printf '%s\n' "$raw" | sed -n 's/.*Relay:[[:space:]]*//p')"
  else
    state=disconnected
    relay=""
  fi
  target="$(_vpn_target_id)"
  location="$(_vpn_label_for_id "$target")"
  printf '%s\t%s\t%s\t%s\n' "$state" "$location" "$relay" "$target"
}

vpn_connect() {
  "$MULLVAD" connect >/dev/null 2>&1
  _vpn_wait_connected
}

vpn_disconnect() {
  "$MULLVAD" disconnect >/dev/null 2>&1
}

vpn_locations() {
  "$MULLVAD" relay list | awk '
    /^[A-Za-z]/ && /\([a-z][a-z]\)$/ {
      cc=$0; sub(/.*\(/,"",cc); sub(/\).*/,"",cc)
      cname=$0; sub(/ \([a-z][a-z]\)$/,"",cname); next
    }
    /^\t[A-Za-z]/ && /\([a-z][a-z][a-z]\) @/ {
      city=$0; sub(/^\t/,"",city)
      ccity=city; sub(/.*\(/,"",ccity); sub(/\).*/,"",ccity)
      cityname=city; sub(/ \(.*/,"",cityname)
      printf "%s (%s)\t%s %s\n", cname, cityname, cc, ccity
    }'
}

vpn_set_location() {
  # $1 is the opaque ID from vpn_locations, for example "us lax". It is split
  # on purpose into the country and city arguments mullvad expects.
  # shellcheck disable=SC2086
  "$MULLVAD" relay set location $1 >/dev/null 2>&1
  "$MULLVAD" connect >/dev/null 2>&1
  _vpn_wait_connected
}

# --- helpers, not part of the contract ---

# The id of the currently configured relay, readable in both states. mullvad
# prints the constraint as "city yyc, ca" or "country se", which we normalise
# to the same "country city" or "country" id the location list uses.
_vpn_target_id() {
  local loc city cc
  loc="$("$MULLVAD" relay get 2>/dev/null | sed -n 's/.*Location:[[:space:]]*//p' | head -1)"
  case "$loc" in
    city\ *)
      city="$(printf '%s' "$loc" | sed -E 's/^city ([a-z]+),.*/\1/')"
      cc="$(printf '%s' "$loc" | sed -E 's/^city [a-z]+, ([a-z]+).*/\1/')"
      printf '%s %s' "$cc" "$city"
      ;;
    country\ *)
      printf '%s' "$loc" | sed -E 's/^country ([a-z]+).*/\1/'
      ;;
  esac
}

# The human label for an id, resolved from the location list.
_vpn_label_for_id() {
  [ -z "$1" ] && return 0
  vpn_locations | awk -F'\t' -v id="$1" '$2==id{print $1; exit}'
}

# Waits briefly so status reads accurately right after a connect, since mullvad
# establishes the tunnel asynchronously.
_vpn_wait_connected() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    "$MULLVAD" status 2>/dev/null | grep -q '^Connected' && return 0
    sleep 0.4
  done
}
