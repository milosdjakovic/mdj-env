#!/usr/bin/env bash
# shellcheck source=fzf-base.sh
. "$(dirname "$0")/fzf-base.sh"
# shellcheck source=fzf-cache.sh
. "$(dirname "$0")/fzf-cache.sh"
# Repository and worktree picker. Scans `.git` directories under
# REPOS_ROOT and groups each repo with its auxiliary worktrees right
# below it. Filtering is parent/child aware:
#   - matching a worktree always keeps its parent repo visible
#   - matching a repo always keeps all of its worktrees visible
# fzf runs in `--disabled` mode so a small filter script can narrow
# the cached row set on every keystroke. The same script is invoked
# via `change:reload` and from the background scanner's POST to
# fzf's listen port.
#
# Open is instant. The picker seeds itself from a persistent cache
# under ~/.cache/fzf-tmux/repos.tsv and refreshes the visible list as
# the background scan produces fresh rows.
#
# Selection actions:
#   <enter>  open in lazygit (90% popup, matches prefix+g)
#   ^p       copy path to clipboard
#   ^b       copy current branch to clipboard
#   ^n       copy repo or worktree name to clipboard
# Invoked via `run-shell -b` so fzf manages its own small popup and the
# follow-up lazygit popup opens after fzf exits.

set -euo pipefail

# Root directory to scan. Defaults to $HOME, override via env var.
ROOT="${REPOS_ROOT:-$HOME}"
# Depth cap keeps deep vendored or submodule trees from stalling the scan.
MAX_DEPTH="${REPOS_MAX_DEPTH:-8}"

# Directory names to skip. Same philosophy as fzf-files.sh, minus .git
# itself since that is what we are searching for.
EXCLUDE=(
  node_modules .next .nuxt .turbo
  __pycache__ .venv venv .mypy_cache .pytest_cache .ruff_cache .tox
  target dist build out
  .direnv .cache .idea
  coverage .terraform .parcel-cache .svelte-kit .angular .serverless
  Library .Trash Trash
  .cargo .rustup .gradle .m2
  .npm .yarn .pnpm-store .bun .deno
  .nvm .pyenv .rbenv .sdkman .android
)

ICON_REPO=$(printf '\xee\xac\x96')      # nf-cod-repo
ICON_WORKTREE=$(printf '\xee\xa9\xa8')  # nf-cod-git_branch
COL_DIM=$'\033[38;5;246m'
COL_RESET=$'\033[0m'

# Cache locations. PERSIST_CACHE survives across invocations and is
# what makes the popup feel instant on every open after the first.
PERSIST_CACHE="$(fzf_cache_dir)/repos.tsv"
WORK_CACHE=$(mktemp -t fzf-repos-cache.XXXXXX)
FILTER=$(mktemp -t fzf-repos-filter.XXXXXX)
LISTEN_SOCK=$(fzf_cache_socket)
trap 'rm -f "$WORK_CACHE" "$WORK_CACHE.swap" "$FILTER" "$LISTEN_SOCK"' EXIT

FD_ARGS=(--type d --hidden --max-depth "$MAX_DEPTH")
for pat in "${EXCLUDE[@]}"; do
  FD_ARGS+=(--exclude "$pat")
done

resolve_branch() {
  local p="$1" b
  if b=$(git -C "$p" symbolic-ref --short HEAD 2>/dev/null); then
    printf '%s' "$b"
  elif b=$(git -C "$p" rev-parse --short HEAD 2>/dev/null); then
    printf '%s' "$b"
  else
    printf '?'
  fi
}

# Row schema (tab-separated):
#   1=kind  2=path  3=name  4=branch  5=display
emit_row() {
  local kind="$1" path="$2" name="$3" branch="$4"
  local display
  if [ "$kind" = "repo" ]; then
    display=$(printf ' %s  %s %s(%s)%s' "$ICON_REPO" "$name" "$COL_DIM" "$branch" "$COL_RESET")
  else
    display=$(printf '   └─ %s  %s %s(%s)%s' "$ICON_WORKTREE" "$name" "$COL_DIM" "$branch" "$COL_RESET")
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$path" "$name" "$branch" "$display"
}

# Walk REPOS_ROOT for `.git` entries, emit each repo followed by its
# secondary worktrees. Order matters: the filter relies on a worktree
# always appearing after its parent repo in the cache.
emit_rows() {
  local gd repo_path repo_name repo_branch
  local wt_path wt_branch wt_name
  fd '^\.git$' "$ROOT" "${FD_ARGS[@]}" 2>/dev/null | while IFS= read -r gd; do
    [ -z "$gd" ] && continue
    # fd 10+ appends a trailing slash to directory entries.
    gd="${gd%/}"
    repo_path="${gd%/.git}"
    # Canonicalize so paths match `git worktree list` output (git resolves
    # symlinks, fd does not). Required for the main-worktree skip below.
    repo_path=$(cd "$repo_path" 2>/dev/null && pwd -P) || continue
    repo_name=$(basename "$repo_path")
    repo_branch=$(resolve_branch "$repo_path")
    emit_row "repo" "$repo_path" "$repo_name" "$repo_branch"

    # Parse `git worktree list --porcelain`: blank-line separated blocks
    # of `worktree <path>`, `HEAD <sha>`, and either `branch refs/heads/<br>`
    # or `detached`. Empty awk RS splits on blank lines.
    git -C "$repo_path" worktree list --porcelain 2>/dev/null | awk -v RS='' '
      {
        wt=""; br=""; detached=0
        n = split($0, lines, "\n")
        for (i = 1; i <= n; i++) {
          line = lines[i]
          if (sub(/^worktree /, "", line)) wt = line
          else if (sub(/^branch refs\/heads\//, "", line)) br = line
          else if (line == "detached") detached = 1
        }
        if (wt == "") next
        if (br == "" && detached) br = "detached"
        else if (br == "") br = "?"
        print wt "\t" br
      }
    ' | while IFS=$'\t' read -r wt_path wt_branch; do
      [ -z "$wt_path" ] && continue
      # Skip the main worktree, which is the repo path itself.
      [ "$wt_path" = "$repo_path" ] && continue
      wt_name=$(basename "$wt_path")
      emit_row "worktree" "$wt_path" "$wt_name" "$wt_branch"
    done
  done
}

# Parent/child aware filter, invoked by fzf on `change` and by the
# background scanner when it POSTs reload to the listen port.
#   1. fuzzy-match the query against name+branch via `fzf --filter`
#   2. expand the match set with parents (for worktree hits) and
#      children (for repo hits)
#   3. emit rows in cache order so each repo stays above its kids
cat > "$FILTER" <<'FILTER_EOF'
#!/usr/bin/env bash
set -euo pipefail
CACHE="$1"
QUERY="${2:-}"
[ -f "$CACHE" ] || exit 0
if [ -z "$QUERY" ]; then
  cat "$CACHE"
  exit 0
fi
matched=$(fzf --filter "$QUERY" --delimiter=$'\t' --nth=3,4 < "$CACHE" 2>/dev/null || true)
if [ -z "$matched" ]; then
  exit 0
fi
matched_paths=$(printf '%s\n' "$matched" | cut -f2)
awk -F'\t' '
  NR == FNR { mp[$0] = 1; next }
  {
    rows[FNR] = $0
    kind[FNR] = $1
    path[FNR] = $2
    if ($1 == "repo") current_repo = FNR
    parent[FNR] = ($1 == "worktree" ? current_repo : 0)
    total = FNR
  }
  END {
    for (r = 1; r <= total; r++) {
      if (!mp[path[r]]) continue
      keep[r] = 1
      if (kind[r] == "worktree" && parent[r] > 0) keep[parent[r]] = 1
      if (kind[r] == "repo") {
        for (c = r + 1; c <= total; c++) {
          if (kind[c] == "repo") break
          keep[c] = 1
        }
      }
    }
    for (r = 1; r <= total; r++) {
      if (keep[r]) print rows[r]
    }
  }
' <(printf '%s\n' "$matched_paths") "$CACHE"
FILTER_EOF
chmod +x "$FILTER"

# Seed the working cache from the persistent cache so fzf has rows to
# show on open. First-ever invocation starts with an empty list and
# fills as the scanner produces rows via `reload`.
if [ -f "$PERSIST_CACHE" ]; then
  cp "$PERSIST_CACHE" "$WORK_CACHE"
fi

# Background scanner. Streams emit_rows into the working cache with
# throttled reloads pushed to fzf, then persists the final result.
( emit_rows | fzf_cache_consume \
    "$LISTEN_SOCK" "$WORK_CACHE" "$PERSIST_CACHE" 20 \
    "reload($FILTER {{cache}} {q})" ) &

BORDER_LABEL=$(fzf_label "↵ lazygit" "^p path" "^b branch" "^n name")

# `--listen <sock>` opens a Unix domain socket so the background
# scanner can POST `reload(...)` without needing port discovery.
# `--disabled` lets the filter script own all match logic.
result=$(fzf --tmux center,70%,70%,border-native \
  "${FZF_BASE_OPTS[@]}" \
  --listen "$LISTEN_SOCK" \
  --header="Repos & worktrees in ${ROOT/#$HOME/~}" \
  --border-label="$BORDER_LABEL" \
  --delimiter=$'\t' \
  --with-nth=5 \
  --ansi \
  --no-sort \
  --disabled \
  --bind "change:reload($FILTER $WORK_CACHE {q})" \
  --bind "ctrl-j:down,ctrl-k:up" \
  --expect=ctrl-p,ctrl-b,ctrl-n \
  < "$WORK_CACHE" \
  || true)

[ -z "$result" ] && exit 0
key=$(printf '%s' "$result" | head -n1)
sel=$(printf '%s' "$result" | tail -n +2)
[ -z "$sel" ] && exit 0

path=$(printf '%s\n' "$sel" | cut -f2)
name=$(printf '%s\n' "$sel" | cut -f3)
branch=$(printf '%s\n' "$sel" | cut -f4)
[ -z "$path" ] && exit 0

case "$key" in
  ctrl-p)
    printf '%s' "$path" | pbcopy
    tmux display-message "copied path: $path"
    ;;
  ctrl-b)
    printf '%s' "$branch" | pbcopy
    tmux display-message "copied branch: $branch"
    ;;
  ctrl-n)
    printf '%s' "$name" | pbcopy
    tmux display-message "copied name: $name"
    ;;
  *)
    # Cached entries can outlive the underlying path. Validate before
    # handing off to lazygit so a stale pick fails loudly, not silently.
    if [ ! -d "$path" ]; then
      tmux display-message "path no longer exists: $path"
      exit 0
    fi
    tmux display-popup -d "$path" -w 90% -h 90% -E lazygit
    ;;
esac
