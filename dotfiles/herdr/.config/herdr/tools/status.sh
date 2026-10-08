#!/usr/bin/env bash
# How an agent's state is drawn, shared by every picker that lists agents so a row there
# reads like the row in herdr's sidebar. The glyphs come from whichever of herdr's two
# indicator sets the config chooses, both as herdr's own settings preview lists them,
# blocked, working, done, idle. The colours are the ANSI slots the theme paints, the same
# yellow working and green idle the sidebar uses. Both are JSON so a jq filter can take them
# whole with --argjson.

herdr_status_style() {
  if grep -qE '^[[:space:]]*status_indicators[[:space:]]*=[[:space:]]*"symbols"' "$1" 2>/dev/null; then
    STATUS_GLYPHS='{"blocked":"×","working":"◐","done":"✓","idle":"○"}'
  else
    STATUS_GLYPHS='{"blocked":"●","working":"●","done":"●","idle":"○"}'
  fi
  STATUS_COLOURS='{"blocked":"31","working":"33","done":"34","idle":"32"}'
}
