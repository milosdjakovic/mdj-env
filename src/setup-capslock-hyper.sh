#!/bin/bash

# The leader/Hyper key remap used to be installed here as a hidutil LaunchAgent.
# It now lives inside Hammerspoon (KeyRemap.spoon, driven by the leaderKeys
# catalog in config/keys.lua), so the remap is applied on launch and cleared on
# quit, from the same single source of truth as everything else. See the
# Hammerspoon section of CLAUDE.md.
#
# This script now only migrates older machines off the legacy LaunchAgent, so a
# stale login-time mapping cannot fight the Hammerspoon-owned one. It is safe to
# run repeatedly and does nothing on a machine that never had the agent.

set -e

LABEL="com.mdj.capslock-hyper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ -f "$PLIST" ] || launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "==> Removing legacy $LABEL LaunchAgent (Hammerspoon owns the remap now)..."
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "    Done. The old agent applied its mapping only at login, so the last"
  echo "    one lingers until Hammerspoon reapplies. Start or reload Hammerspoon"
  echo "    to apply the current remap, or log out to clear it."
else
  echo "==> No legacy remap LaunchAgent found; Hammerspoon owns the key remap."
fi
