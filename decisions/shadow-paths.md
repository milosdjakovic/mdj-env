# Shadow paths, the config a tool reads besides the one stow links

Status. A module declares in a `SHADOW-PATHS` file every path its tool reads besides the linked
config, the stow step asks before moving any it finds, and a module that can ask its tool for
the settings it resolved ships a `config-probe` the reconciler runs.

## Now

Some tools read more than one config file, and the last file to set a key wins. Stow only sees
paths inside a package, so a file left at one of the other locations from before this
repository is invisible to it, and the linked config looks correct while losing setting by
setting. Ghostty on macOS is the case that found it. It reads
`~/Library/Application Support/com.mitchellh.ghostty/config` after `~/.config/ghostty/config`.

Which paths a tool reads is a module fact, so each module names its own in `SHADOW-PATHS` at
its package root, as `path | reason` with the path relative to the home directory, found by
name the way `NO-FOLD` is. Only stowed packages are read. `src/setup-stow-dotfiles.sh --shadows`
lists what is present here. A shadow is never moved without an answer, unlike a stow conflict,
because it can hold settings nobody carried into this repository. `setup.sh` asks before its
first step, `MDJ_SHADOWS` answers for a run with no terminal, `move` or `keep`, Enter keeps,
and a kept file leaves a note that the closing block repeats. A moved one goes into the usual
backup directory.

Detection is separate and stronger. A module whose tool reports its resolved settings ships a
`config-probe`, which compares every key the linked file sets once against what the tool
actually runs with and prints each one that lost. That catches an override from anywhere,
including a path no declaration names yet. `check-dependencies.sh` runs every probe and lists
every present shadow, all as warnings since both are facts about one machine, and it errors
when a `NO-FOLD`, `SHADOW-PATHS` or `config-probe` is missing from its package's
`.stow-local-ignore`.

## Rejected

- **A theme check only, `ghostty +show-config | grep '^theme'` against one expected line.**
  2026-09-25. It catches the instance that was seen and nothing beside it. Comparing every key
  the linked file sets once costs the same and catches a stale font or padding too.
- **Failing the run on an override.** 2026-09-25. A leftover file is a fact about one machine,
  and this repository reserves errors for defects that are the same everywhere.
- **Moving a shadow without asking, the way a stow conflict is moved.** 2026-09-25. A stow
  conflict sits where this repository's own file belongs. A shadow may be the only copy of
  settings a person wants to carry over, so they see the list and answer first.
- **The Ghostty path written into the stow step or the checker.** 2026-09-25. The same leak
  `decisions/stow-folding.md` rejected for `mkdir -p`, a module fact in the module agnostic
  layer, so the one path somebody thought of is handled and the next is not.
- **Testing the probe under a fake `$HOME`.** 2026-09-25. Ghostty finds Application Support
  through macOS rather than through `$HOME`, so a fake home never reproduces the override. The
  probe was proved by appending to the real file and restoring it in the same command.

## Log

### 2026-09-25 15:59

Recorded now, the diagnosis on the other machine was earlier the same day at a time not known
here. A second machine that used
Ghostty before adopting these dotfiles had its terminal stuck on the dark half in light mode.
`ghostty +show-config | grep '^theme'` resolved to `Dark+`, from a May 2025 file in Application
Support, while the linked config said `light:mdj-light,dark:mdj-dark`. Everything painted from
Ghostty's slots followed it, so the visible symptom was a light herdr panel around a dark
terminal. Moving the file aside fixed it. This machine had the same path holding only the
comment template Ghostty writes on first launch, so the trap was present and unarmed.

### 2026-09-25 15:59, the build

Built `SHADOW-PATHS`, the question in `setup.sh` and the stow step, and the Ghostty
`config-probe` with its reconciler check. Proved on this machine by appending `theme = Dark+`
and `font-size = 12` to the Application Support file, where the probe named both, then
restoring the file byte for byte. Proved the sweep in a throwaway home for keep with no
terminal, move, an invalid answer, and the question answered yes under a pseudo terminal.
