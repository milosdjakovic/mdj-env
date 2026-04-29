#!/usr/bin/env bash
# shellcheck source=fzf-base.sh
. "$(dirname "$0")/fzf-base.sh"
# Search lf tags via fzf.
#   <enter> copies the path to the clipboard.
#   ^v     opens the tagged file or folder in nvim inline in the popup;
#          the popup closes when nvim exits.
#   alt-v  opens it in a new tmux window that auto-closes on nvim exit.
#
# Tag file format is `path:X` (one char). The sed strips the trailing `:X`.

ICON_NVIM_WIN=$(printf '\xef\x82\x8e')  # nf-fa-external_link

result=$(sed 's/:.$//' ~/.local/share/lf/tags 2>/dev/null | \
  fzf "${FZF_BASE_OPTS[@]}" \
      --header='Tags' \
      --border-label="$(fzf_label "↵ copy" "^v nvim" "alt-v nvim ${ICON_NVIM_WIN}")" \
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
