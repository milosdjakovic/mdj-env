# Neovim lockfile pin

Status. `lazy-lock.json` is the pin, `bootstrap-nvim.sh` restores to it, updating is a
deliberate act performed here and committed.

## Now

`lazy-lock.json` names an exact commit per plugin. `src/bootstrap-nvim.sh` runs install, clean
and `restore`, lazy.nvim's own documented answer for a config used on more than one machine.
It reconciles rather than guesses, comparing every name and commit in the lockfile against disk
before and after, and fails with the list when something does not converge. When two machines
disagree, the fix is to capture the good one with
`nvim --headless -c 'lua require("lazy.manage.lock").update()' -c qa` and commit the result,
which is lazy.nvim's own writer so the format cannot drift.

## Rejected

- **`Lazy! sync` in the bootstrap.** 2026-05-03 to 2026-09-13, 743a43d until 2644ba2. Sync is
  install, clean and update, and update moves every plugin to its newest revision and rewrites
  the lockfile. So the second machine got whatever was newest that day rather than what this
  repository pins, and because `~/.config/nvim` is a symlink into the repo the rewrite landed on
  a tracked file.
- **Checking for one directory and calling the job done.** Same span. The old check looked for
  LazyVim's directory alone, so a first run that died partway was never retried.

## Log

### 2026-05-03 21:33

743a43d. The bootstrap arrives running `Lazy! sync`.

### 2026-09-13 19:23

2644ba2. The replication commit. Sync becomes restore, the bootstrap reconciles the lockfile
against disk, and the lockfile becomes the record of this machine. Verified rather than
assumed, both folded and unfolded, alongside the stow displacement and the Xcode command line
tools changes in the same commit.
