#!/usr/bin/env bash
# shellcheck source=fzf-base.sh
. "$(dirname "$0")/fzf-base.sh"

# Passed from the binding since #{pane_current_path} does not resolve in a popup.
pane_path="${PANE_PATH:-$HOME}"

# Text entry as an fzf input box: the query is the typed value (search disabled),
# `initial` pre-fills it, Esc/ctrl-c abort. fzf, unlike the shell's `read`, can
# distinguish Enter from Alt-Enter, so callers learn which was pressed.
# Sets ENTRY_VALUE and ENTRY_KEY (empty for Enter, "alt-enter" for Alt-Enter).
# Returns non-zero when the user aborts or leaves the value blank.
entry() {
  local prompt="$1" initial="$2" label="$3" out code
  out=$(fzf "${FZF_BASE_OPTS[@]}" \
      --print-query --disabled --info=hidden \
      --expect=alt-enter \
      --query="$initial" \
      --prompt="$prompt" \
      --border-label="$label" </dev/null)
  code=$?
  # 130 is Esc/ctrl-c/ctrl-g. Code 1 (no match) is expected: the list is empty,
  # so any typed name "does not match" yet is still a valid new name.
  [ "$code" -eq 130 ] && return 1
  ENTRY_VALUE=$(printf '%s\n' "$out" | sed -n 1p)
  ENTRY_KEY=$(printf '%s\n' "$out" | sed -n 2p)
  [ -z "$ENTRY_VALUE" ] && return 1
  return 0
}

# The popup stays open across delete, rename, and plain create so several
# actions can be chained. Only switching to a session or aborting leaves it.
while true; do
  clear
  current_session=$(tmux display-message -p '#S')

  out=$(tmux list-sessions -F '#{session_last_attached} #{session_name}' | \
    sort -r | cut -d' ' -f2- | \
    grep -v "^${current_session}\$" | \
    fzf "${FZF_BASE_OPTS[@]}" \
        --expect=ctrl-x,ctrl-r,ctrl-n \
        --header="current: ${current_session}" \
        --border-label="$(fzf_label "↵ switch" "^n new" "^r rename" "^x del")")

  key=$(printf '%s\n' "$out" | sed -n 1p)
  selected=$(printf '%s\n' "$out" | sed -n 2p)

  case "$key" in
    ctrl-n)
      # Enter creates and stays in the picker; Alt-Enter creates and switches.
      entry "New session: " "" "$(fzf_label "↵ create" "⌥↵ create+go")" || continue
      tmux new-session -d -s "$ENTRY_VALUE" -c "$pane_path"
      if [ "$ENTRY_KEY" = alt-enter ]; then
        tmux switch-client -t "$ENTRY_VALUE"
        exit 0
      fi
      ;;
    ctrl-r)
      [ -z "$selected" ] && continue
      entry "Rename to: " "$selected" "$(fzf_label "↵ rename")" || continue
      tmux rename-session -t "$selected" "$ENTRY_VALUE"
      ;;
    ctrl-x)
      [ -z "$selected" ] && continue
      clear
      # -n 1 so a single key decides; anything but y/Y (including Esc) cancels.
      read -r -n 1 -p "Delete session '$selected'? [y/N] " confirm
      case "$confirm" in
        y | Y) tmux kill-session -t "$selected" ;;
      esac
      ;;
    *)
      # Enter (empty key) or abort. Switch only if something was selected.
      [ -n "$selected" ] && tmux switch-client -t "$selected"
      exit 0
      ;;
  esac
done
