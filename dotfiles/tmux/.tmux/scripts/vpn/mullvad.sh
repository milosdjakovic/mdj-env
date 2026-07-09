#!/usr/bin/env bash
# Mullvad adapter for fzf-vpn.sh. This is the only file that knows the mullvad
# CLI. Each function returns values normalized to the TUI contract, and a
# function may run several CLI commands to produce one normalized answer.
#
# Contract expected by fzf-vpn.sh:
#   vpn_name          prints a human label
#   vpn_status        prints STATE<TAB>LOCATION<TAB>RELAY (STATE connected|disconnected)
#   vpn_connect       connects to the current or last relay
#   vpn_disconnect    disconnects
#   vpn_locations     prints DISPLAY<TAB>ID per line
#   vpn_set_location  selects the server for an ID and connects

MULLVAD="${MULLVAD:-/usr/local/bin/mullvad}"

vpn_name() { printf 'Mullvad\n'; }

vpn_status() {
  local raw state relay location
  raw="$("$MULLVAD" status 2>/dev/null)"
  if printf '%s' "$raw" | grep -q '^Connected'; then
    state=connected
  else
    state=disconnected
  fi
  relay="$(printf '%s\n' "$raw" | sed -n 's/.*Relay:[[:space:]]*//p')"
  location="$(printf '%s\n' "$raw" | sed -n 's/.*Visible location:[[:space:]]*//p' | sed 's/\. IPv4.*//')"
  printf '%s\t%s\t%s\n' "$state" "$location" "$relay"
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
      printf "%s / %s\t%s %s\n", cname, cityname, cc, ccity
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

# Not part of the contract. Waits briefly so status reads accurately right
# after a connect, since mullvad establishes the tunnel asynchronously.
_vpn_wait_connected() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    "$MULLVAD" status 2>/dev/null | grep -q '^Connected' && return 0
    sleep 0.4
  done
}
