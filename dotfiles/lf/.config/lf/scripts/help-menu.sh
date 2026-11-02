#!/usr/bin/env bash
# Help screen for lf. Every key lf has in normal mode, its defaults and ours, searchable, and enter
# presses the chosen key.
# Args: $1 = lf id

LF_ID="$1"
LFRC=~/.config/lf/lfrc

# lf answers which keys it has, defaults included, as mode, key, an empty field and the command,
# tab separated after a header row. The descriptions are only ours, read from the comment on each
# map line in lfrc, so a key lf ships with shows the command it runs instead.
rows=$(awk -F'\t' '
  FNR == NR {
    if ($0 ~ /^map [^ ]+ .* # /) {
      key = $0; sub(/^map /, "", key); sub(/ .*/, "", key)
      desc = $0; sub(/^[^#]* # /, "", desc)
      ours[key] = desc
    }
    next
  }
  FNR == 1 || $1 !~ /n/ { next }
  {
    key = $2; cmd = $NF
    if (key in ours) printf "%-12s %s\n", key, ours[key]
    else printf "%-12s \033[2m%s\033[0m\n", key, cmd
  }
' "$LFRC" <(lf -remote "query $LF_ID maps"))

selected=$(printf '%s\n' "$rows" | fzf --reverse --no-mouse --ansi \
  --header='Every key, dim ones are lf defaults (enter presses it)' \
  --header-first \
  --bind 'esc:abort')

# push presses the key itself, so a sequence, a key with a count or a key that runs several
# commands behaves exactly as if it had been typed.
if [ -n "$selected" ] && [ -n "$LF_ID" ]; then
  key=$(printf '%s' "$selected" | awk '{print $1}')
  lf -remote "send $LF_ID push $key"
fi
