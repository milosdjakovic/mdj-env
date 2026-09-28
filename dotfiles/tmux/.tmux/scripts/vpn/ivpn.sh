#!/usr/bin/env bash
# IVPN adapter for fzf-vpn.sh. This is the only file that knows the ivpn CLI. Each function
# returns values normalized to the TUI contract, and a function may run several CLI commands
# to produce one normalized answer.
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
#
# The display wording is the interface's, not this backend's. A row reads Country (City) here
# because that is what the other adapter already prints and the list is meant to read the same
# whichever backend is behind it. This file spells its own vocabulary only into the ID, which
# the interface treats as opaque and hands back untouched.
#
# Named rather than pathed, so this module stays ignorant of where anything is installed and
# works the same on either architecture. Still overridable, which is how the contract above can
# be exercised against a stub.
IVPN="${IVPN:-ivpn}"

vpn_name() { printf 'IVPN\n'; }

# This backend publishes no selection while the tunnel is down, so LOCATION and TARGET_ID are
# empty then and the list simply marks no active row. That is the honest answer rather than a
# guessed one. The daemon holds last used parameters that a bare connect acts on, and exposes
# no reader for them, so anything printed there would be invented. Connected, the state line is
# followed by one naming the server as gateway [host], City (CC), Country, which carries the
# place and the id together and is why this reads a whole status rather than asking twice.
vpn_status() {
  local raw word state relay target location info city country
  raw="$("$IVPN" status 2>/dev/null)"
  word="$(printf '%s\n' "$raw" | sed -n 's/^[[:space:]]*VPN[[:space:]]*:[[:space:]]*\([A-Z]*\).*/\1/p' | head -1)"
  if [ "$word" = "CONNECTED" ]; then
    state=connected
  else
    state=disconnected
  fi

  relay=""
  target=""
  location=""
  if [ "$state" = connected ]; then
    info="$(printf '%s\n' "$raw" | sed -n 's/^[[:space:]]*\([A-Za-z0-9.-]*\)[[:space:]]*\[\(.*\)\],[[:space:]]*\(.*\)[[:space:]]*(\([A-Za-z][A-Za-z]\)),[[:space:]]*\(.*\)$/\1\t\2\t\3\t\5/p' | head -1)"
    target="$(printf '%s' "$info" | cut -f1)"
    relay="$(printf '%s' "$info" | cut -f2)"
    city="$(printf '%s' "$info" | cut -f3)"
    # The capture ahead of the country code is greedy and takes the space before it with the
    # name, so the tail is trimmed here rather than fought for in the expression.
    city="${city%"${city##*[![:space:]]}"}"
    country="$(printf '%s' "$info" | cut -f4)"
    [ -n "$country" ] && [ -n "$city" ] && location="$country ($city)"
  fi

  printf '%s\t%s\t%s\t%s\n' "$state" "$location" "$relay" "$target"
}

vpn_connect() {
  "$IVPN" connect -last >/dev/null 2>&1
  _vpn_wait_connected
}

vpn_disconnect() {
  "$IVPN" disconnect >/dev/null 2>&1
}

# The listing prints one padded table with pipe separated columns, protocol, location, city,
# country, ISP, and tunnel address family, under one header row. Only the WireGuard rows are
# kept. Every location appears once per protocol, so reading both would list all of them twice,
# and the protocol is not a choice this list offers. The header row and the per host detail
# rows carry no protocol of their own and fall out through the same test.
#
# The id is the gateway hostname, which is stable, unique, and the same thing the connect
# filter takes. The city column carries the country code in parentheses and the city name
# itself may contain a comma, Los Angeles, CA being the ordinary case, so the code is stripped
# from the end rather than the cell being split on a comma.
vpn_locations() {
  "$IVPN" servers 2>/dev/null | awk -F'|' '
    {
      proto = $1; gsub(/^[ \t]+|[ \t]+$/, "", proto)
      if (proto != "WireGuard") next
      gw   = $2; gsub(/^[ \t]+|[ \t]+$/, "", gw)
      city = $3; gsub(/^[ \t]+|[ \t]+$/, "", city)
      ctry = $4; gsub(/^[ \t]+|[ \t]+$/, "", ctry)
      sub(/[ \t]*\([A-Za-z][A-Za-z]\)$/, "", city)
      if (gw == "" || city == "" || ctry == "") next
      printf "%s (%s)\t%s\n", ctry, city, gw
    }'
}

vpn_set_location() {
  # $1 is the opaque ID from vpn_locations, a full gateway hostname. Unlike the other backend
  # there is no separate constraint to set before connecting, connect takes the location
  # directly and switching an already connected tunnel is the same command. The flag says which
  # field to match the positional value against, and the hostname is matched rather than a city
  # or a country because those are ambiguous in this CLI's vocabulary and a hostname is not.
  "$IVPN" connect -l "$1" >/dev/null 2>&1
  _vpn_wait_connected
}

# --- helpers, not part of the contract ---

# Waits briefly so status reads accurately right after a connect, since the tunnel is
# established asynchronously.
_vpn_wait_connected() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    "$IVPN" status 2>/dev/null | grep -qE '^[[:space:]]*VPN[[:space:]]*:[[:space:]]*CONNECTED' && return 0
    sleep 0.4
  done
}
