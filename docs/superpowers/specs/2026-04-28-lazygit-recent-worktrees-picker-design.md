# Lazygit Recent Repos and Worktrees Picker

## Problem

`prefix+g` opens lazygit at the tmux pane's `pane_current_path`. When the user starts Claude Code from a repo root and uses Claude's `!cd` to move into a worktree, only Claude's internal cwd changes. The tmux pane's cwd remains the main repo, so `prefix+g` opens lazygit at the main repo even when the user is mentally working in a worktree.

The fix needs to give the user a way to pick a worktree (or any recent repo) without depending on the tmux pane's cwd, since tmux cannot see Claude's effective working directory.

## Solution

Add a new binding `prefix+G` that opens a fzf popup listing recent repos and worktrees. On selection, lazygit opens at the chosen path inside the same popup. Esc cancels cleanly.

`prefix+g` keeps its current behavior unchanged.

## Data sources

Primary source is lazygit's own state file at `~/Library/Application Support/lazygit/state.yml`. It maintains a `recentrepos` list in recency order and includes both main repos and worktrees as separate entries, since lazygit treats each as a distinct repo.

Augmentation source is `git worktree list --porcelain` run against each main repo in `recentrepos`. Any worktrees the user has not yet visited via lazygit get appended after the recency-ordered list. This makes a freshly-created worktree available before its first lazygit visit.

Resulting order is recentrepos as-is, then any newly-discovered worktrees appended.

## Display

Paths with `$HOME` collapsed to `~` for readability. fzf header reads `Recent repos & worktrees`.

Each entry is prefixed with a nerdfont icon to differentiate the kind of repo:

- Main repo (path has a `.git` directory):  (nf-cod-repo)
- Secondary worktree (path has a `.git` file):  (nf-cod-git_branch)

The detection uses `[ -d "$path/.git" ]` rather than parsing porcelain output, since lazygit's recentrepos contains both kinds and we need a per-path classifier.

The popup is sized `-w 60% -h 50%` so it stays smaller and more focused than the file/tag pickers (`-w 80% -h 70%`).

## Flow

1. User presses `prefix+G`.
2. tmux opens a popup running `~/.tmux/scripts/fzf-recent-repos.sh`.
3. Script parses `recentrepos` from `state.yml`, augments with missing worktrees, pipes to fzf.
4. User picks an entry. Script expands `~` back to `$HOME`, `cd`s to the path, and `exec lazygit` in the same popup. Esc exits the popup with no further action.

## Files

- New script: `dotfiles/tmux/.tmux/scripts/fzf-recent-repos.sh`.
- Edit `dotfiles/tmux/.tmux.conf`: add `bind G display-popup ...` next to the existing `prefix+g` line, with `-N "[p:8] Recent repos & worktrees lazygit"`.
- Edit `dotfiles/tmux/.tmux/scripts/fzf-launcher.sh`: add a `tools` entry so the new binding shows up in `prefix+Space`.
- Edit `dotfiles/tmux/CLAUDE.md`: add the new priority slot to the assignments list.

## Implementation notes

YAML parsing uses awk against the known shape of `state.yml`. The list items are 4-space-indented with `    - <path>` under the `recentrepos:` key. Fragile if lazygit ever changes the format, but acceptable given lazygit's stability and the small risk surface.

Paths can contain spaces. Quote everywhere. Use `printf %s\\n` over `echo` for safety.

Use `awk 'NF'` to drop blank lines from the merged list before passing to fzf.

The script must `exec lazygit` rather than running it as a subshell so the popup hands its terminal directly to lazygit and exits cleanly when lazygit exits.

## Out of scope

Auto-detecting Claude Code's working directory from outside Claude. Requires hooks or IPC and is a separate problem.

Heuristic auto-pick of a single worktree without a prompt. The user explicitly asked for a searchable list.

Replacing or removing the existing `prefix+g` behavior.
