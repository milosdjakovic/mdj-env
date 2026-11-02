# lf Configuration

Terminal file manager configuration in `dotfiles/lf/.config/lf/`. Stow symlinks to `~/.config/lf/`.

## Why lf instead of yazi

Yazi sends passthrough escape sequences at startup to detect terminal capabilities. tmux `display-popup` does not support `allow-passthrough` because popups have no real pane backing them. Yazi times out and crashes. lf does not do terminal capability detection so it works directly in a popup.

## Every interactive command is native to lf

Every interactive command, the bat preview, nvim, trash confirmation, both fzf
finds, both tag browsers and help, is a `${{ }}` shell command. That is lf's own way to run a
program in its terminal. lf pauses its UI, the program takes the whole screen, and lf redraws when
it exits. So this module works the same in Rex, herdr, tmux or a bare terminal, and names no
multiplexer at all.

The cost is that lf is not visible behind the picker while it is open, since the picker has the
whole screen rather than a popup over lf. That was the reason these commands used to be `&{{ }}`
commands opening `tmux display-popup`, and it was given up on 2026-11-02 so lf would stop
depending on tmux. `decisions/lf.md` has the rejected alternatives.

Results come back the same way as before. A picker writes its answer to a temp file or sends it
with `lf -remote`, and lf acts on it once it resumes.

## Copying to the clipboard, and finding a command by name

`copy-path`, `copy-name` and `copy-dir` are plain lf commands that run in the background, so
nothing takes the screen and lf echoes what it copied. With files marked, every marked path goes,
one per line. `copy-dir` copies the folder lf is in. They are mapped as two key sequences,
`cp`, `cn` and `cd`, and `c` alone is unmapped because a key that does something by itself cannot
also start a sequence. They replaced a copy menu script on 2026-11-02.

Any command can also be found by name. `:` opens lf's command line, and tab there is
`cmd-menu-complete`, so it shows every command matching what is typed as a menu, ours and lf's
own, and shift tab cycles back. Name a new command so it groups with its siblings, the way the
three copy commands all start with `copy`.

## Keybindings with descriptions

`?` lists every key lf has in normal mode, its defaults as well as ours, from `lf -remote "query $id maps"`. A key mapped here with a `# description` comment shows that description, and every other key shows the command it runs, dimmed. So give every new `map` line a description, or it reads as a bare command name. Enter on a row sends `push KEY` to lf, which presses the key itself, so a sequence or a key that runs several commands behaves exactly as if typed. `?` replaces lf's own default, a backward search, which is still on `N` after a `/` search.

## Tags

Tags persist across sessions and directories. `U` clears selections and cut/copy marks but preserves tags. Tag management lives in the `T` picker (tag-browser.sh) which supports removing individual tags with ctrl-d and removing all visible tags with ctrl-x (with confirmation). Tag removal is scope-aware, respecting the current dir / all filter.

## fzf find has two independent filters

The `F` binding opens fzf with two toggleable dimensions. Scope (current dir / global) and type (all / dirs / files). Each can be changed independently. The active option shows in brackets, inactive ones show their shortcut. Uses `become()` for state transitions, same pattern as the tmux scoped fzf switchers.

## Escape responsiveness in fzf pickers

fzf has a hardcoded ~100ms delay on Escape to distinguish it from escape sequences (arrow keys, etc). This is unavoidable. Inside tmux, its escape-time is set to 0 to prevent additional delay. Scripts send results directly to lf via `lf -remote` instead of writing temp files, eliminating post-processing overhead after the picker closes.

## Previous directory tracking

lf has no built-in previous directory feature. The `on-cd` hook saves the current directory to a temp file. The `-` binding navigates to the previous directory. Temp files use lf's instance id to avoid conflicts between multiple instances.

## Declared dependencies

This module needs tools on the machine and installs none of them. `DEPENDENCIES` at
the package root is the whole contract upward, and the repository root `AGENTS.md`
explains the format and who acts on it.

No multiplexer is a dependency. Every picker runs in lf's own terminal, so the module works
standalone in a bare terminal as well as inside any multiplexer.
