#!/usr/bin/env bash
# Which pane the popup was opened over, and where it sits. Herdr answers this two
# different ways depending on how the popup was opened, plain environment variables
# for a keybinding popup and one JSON blob for a plugin popup, and a popup never gets
# a pane of its own either way. Both tools and the browser need the answer, so it is
# resolved here once rather than three times.

herdr_pane_id() {
  if [ -n "${HERDR_ACTIVE_PANE_ID:-}" ]; then
    printf '%s' "$HERDR_ACTIVE_PANE_ID"
  elif [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
    printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '.focused_pane_id // empty' 2>/dev/null
  fi
}

herdr_pane_cwd() {
  local cwd=""
  if [ -n "${HERDR_ACTIVE_PANE_CWD:-}" ]; then
    cwd="$HERDR_ACTIVE_PANE_CWD"
  elif [ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]; then
    cwd=$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '.focused_pane_cwd // empty' 2>/dev/null)
  fi
  printf '%s' "${cwd:-$HOME}"
}
