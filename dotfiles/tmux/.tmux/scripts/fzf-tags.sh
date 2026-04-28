#!/usr/bin/env bash
# Search lf tags via fzf.
#   <enter> copies the path to the clipboard.
#   ^v     opens the tagged file or folder in nvim inline in the popup;
#          the popup closes when nvim exits.
#   alt-v  opens it in a new tmux window that auto-closes on nvim exit.
#
# Tag file format is `path:X` (one char). The sed strips the trailing `:X`.

result=$(sed 's/:.$//' ~/.local/share/lf/tags 2>/dev/null | \
  fzf --reverse --no-mouse \
      --header='Tags (flagged in lf) | <enter> copy | ^v nvim here | alt-v nvim in new window' \
      --header-first \
      --expect=ctrl-v,alt-v)

key=$(printf '%s' "$result" | head -n1)
sel=$(printf '%s' "$result" | tail -n +2)

[ -z "$sel" ] && exit 0

if [ -d "$sel" ]; then
  nvim_cwd="$sel"
else
  nvim_cwd="$(dirname "$sel")"
fi

case "$key" in
  ctrl-v)
    cd "$nvim_cwd" && exec nvim "$sel"
    ;;
  alt-v)
    tmux new-window -c "$nvim_cwd" nvim "$sel"
    ;;
  *)
    printf '%s' "$sel" | pbcopy
    ;;
esac
