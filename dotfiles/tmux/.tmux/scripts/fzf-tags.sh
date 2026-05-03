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
ICON_SEARCH=$(printf '\xef\x80\x82')    # nf-fa-search

result=$(sed 's/:.$//' ~/.local/share/lf/tags 2>/dev/null | \
  fzf "${FZF_BASE_OPTS[@]}" \
      --header='Tags' \
      --border-label="$(fzf_label "↵ copy" "^v nvim" "alt-v nvim ${ICON_NVIM_WIN}" "^p ${ICON_SEARCH}")" \
      --expect=ctrl-v,alt-v \
      --preview='
        f={}
        if [ -d "$f" ]; then
          eza --tree --level=2 --color=always "$f"
        else
          mime=$(file --mime-type -b "$f" 2>/dev/null)
          if printf "%s" "$mime" | grep -q "^image/"; then
            chafa --format=symbols --size="${FZF_PREVIEW_COLUMNS:-80}x${FZF_PREVIEW_LINES:-40}" "$f"
          elif file --mime-encoding -b "$f" 2>/dev/null | grep -q "binary"; then
            printf "\033[2m%s\033[0m\n\n" "$mime"
            ls -lh "$f"
          else
            bat --color=always --style=numbers --line-range=:200 "$f" 2>/dev/null
          fi
        fi
      ' \
      --color='preview-border:#949494' \
      --preview-window='right:50%:hidden:border-left' \
      --bind 'ctrl-p:toggle-preview' \
      --bind "ctrl-j:down,ctrl-k:up" \
      --bind "alt-j:preview-half-page-down,alt-k:preview-half-page-up")

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
