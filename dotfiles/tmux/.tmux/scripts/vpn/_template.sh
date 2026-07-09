#!/usr/bin/env bash
# Template VPN adapter for fzf-vpn.sh. Copy this to vpn/<name>.sh, implement
# every function, then set VPN_ADAPTER=<name> at the top of fzf-vpn.sh.
#
# The TUI is rigid. It only calls these functions and only understands the
# normalized values they emit, so the interface looks the same for any VPN.
# A function may run as many CLI commands as it needs to produce one
# normalized answer.

# Human label shown in the menu entry and the popup header, for example Surfshark.
vpn_name() { printf 'CHANGEME\n'; }

# One line: STATE<TAB>LOCATION<TAB>RELAY
# STATE must be exactly connected or disconnected. LOCATION and RELAY are free
# text for display and may be empty.
vpn_status() { printf 'disconnected\t\t\n'; }

# Connect to the current or last selected server.
vpn_connect() { :; }

# Disconnect.
vpn_disconnect() { :; }

# One row per selectable location: DISPLAY<TAB>ID
# DISPLAY is what the user searches and sees. ID is opaque to the TUI and is
# handed back verbatim to vpn_set_location.
vpn_locations() { :; }

# Select the server identified by $1 (an ID from vpn_locations) and connect.
vpn_set_location() { :; }
