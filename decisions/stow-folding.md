# Stow folding, and the directories a program writes into

Status. A module declares in a `NO-FOLD` file at its own package root any home directory that
must stay a real directory, and `src/setup-stow-dotfiles.sh` makes it real before linking and
unfolds a machine where it is already a symlink into this checkout.

## Now

Stow folds a whole directory into one symlink when the path does not exist yet in the home
directory and a single package supplies it. That is wanted everywhere else here, because a new
config file or a new spoon file then appears without restowing anything. It is wrong for a
directory the configured program also writes into, since the fold points the program's own
state at this checkout and its sockets, logs and caches land in the repository rather than in
the home directory.

Which directories those are is a module fact, so each module names its own, as
`path | reason` with the path written relative to the home directory. The stow step finds
every `NO-FOLD` by name, the way the reconciler finds a `dependencies-collect` or a
`grants-probe`, and names no module itself. Two modules declare one today, herdr for
`.config/herdr` and claude for `.claude/skills`.

The guard is a `mkdir -p` per declared path before stow runs, and it does nothing where the
directory already exists. The repair is for a machine that folded before any of this existed.
It fires only where the home path is a symlink resolving to that package's own directory,
takes the link off, makes the real directory in its place, and moves every file the repository
does not track out of the package and into it. Tracked is the test because which files a
program writes is that program's own detail and a list of them here would go stale. Nothing is
deleted and every move is printed. After stowing, every declared path is checked and the run
fails if one is a symlink again.

`~/.hammerspoon/config` is deliberately left folding. The display profiles store writes there
and a display arrangement is configuration a person edits and commits, so the fold is the
feature. That is why declaring is opt in per module rather than a rule applied to every
directory a program writes into.

## Rejected

- **A longer `.gitignore`.** 2026-09-17. It hides the leak rather than ending it. The
  repository checkout still holds a running server's sockets and logs, the checkout path stays
  load bearing for a program that has nothing to do with it, and the ignore list has to be
  extended every time the program starts writing a new file. Three lines were ignored for
  herdr and the machine that folded had nine files in the tree, which is the list already
  losing the race.
- **`stow --no-folding` for every package.** 2026-09-17. It solves this by taking away the
  behaviour every other directory here relies on, that a file added inside an already linked
  package appears without restowing.
- **A one off repair script, or written instructions to run by hand.** 2026-09-17. It fixes
  one machine and leaves the class open, and a procedure somebody has to remember is the thing
  this repository puts into `setup.sh` instead.
- **A hardcoded `mkdir -p` per module in the stow script.** 2026-09-17, which is what existed
  from the start for `.claude/skills` and is where this began. A module fact sitting in the
  module agnostic layer, so the one directory somebody thought of was guarded and the next one
  was not.

## Log

- **2026-09-16 23:13.** A second machine pulled this repository and reported that
  `~/.config/herdr` was one stow symlink into the checkout, so herdr's sockets, logs,
  `session.json`, `sessions/`, `release-notes.json`, `plugins/` and `plugins.json` were all
  sitting untracked in the working tree. This machine did not have it, because
  `~/.config/herdr` already existed as a real directory here when stow first ran and stow
  unfolded instead. The two machines differed by nothing but which reached the path first.
- **2026-09-17 00:05.** Surveyed every stowed directory here. `~/.config/nvim`,
  `~/.config/lf` and `~/.hammerspoon/config` are folded symlinks and the first two are
  harmless, since neither tool writes state beside its config. `~/.hammerspoon/config` is
  folded on purpose for the display profiles store. Found `workspaces.json` sitting untracked
  in that directory, left over from before workspaces moved to `~/.olm/data/workspaces`, and
  deleted it in this change.
- **2026-09-17 00:13.** Built the guard, the repair and the check, and proved all four cases
  against a synthetic package in a throwaway repository. A folded machine unfolds and the
  untracked state moves home while the tracked files stay put, a second run is a no op, a
  fresh empty home gets a real directory with the two links inside it, and a plain file in the
  way is displaced into the backup directory rather than deleted. Ran it on this machine, where
  it is a no op and the stow result is unchanged.
- **2026-09-17 00:29.** Added a shape check ahead of everything the step touches. A declared path has to
  be a directory the package actually supplies, which is the only kind stow can fold. Without
  it a typo made a real directory nobody asked for, passed the check after stowing because that
  directory was real, and left the one that was meant folded anyway. Proved by misspelling a
  declaration in the throwaway repository, where the run fails and touches nothing.
- **2026-09-17 00:35.** The repair says to restart. A program running through the old link
  keeps whatever it opened there, so a socket or a log it goes on writing is a path nothing answers on, and
  the unfold was silent about it. The line names the directory rather than the program, since
  which program writes there is the module's own fact and this step names no module.
- **2026-09-17 00:53.** The ownership test was wrong for a name outside ASCII, found by asking whether it
  was rather than by assuming it was fine. Plain `git ls-files` quotes such a path and returns
  it with a leading quote, so the prefix strip missed, the name never matched anything, and a
  tracked file would have been carried out of the repository as though nothing owned it. Both
  sides are null delimited now and neither quotes. Names with spaces were always fine. Proved
  by putting an accented tracked file and an accented untracked one in the same directory in
  the throwaway repository, where the first stays and is linked and only the second moves.

