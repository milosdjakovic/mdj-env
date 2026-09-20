# fut Configuration

Configuration lives in `dotfiles/fut/.config/fut/config.toml`. This package is **not** in the
stow list in `src/setup-stow-dotfiles.sh`, so nothing here reaches the home directory. fut is
installed on every machine because this module declares it, and the config sits ready for the
day it is tried properly. herdr remains the multiplexer in use and nothing here changes that.

Read `decisions/fut-vs-herdr.md` before proposing anything in this area, the Rejected section
first. It carries what was measured against fut 0.24, what herdr does that fut cannot, and the
conditions under which each of those stops being true.

## Why it is here at all

fut names agent state by having the agent report it, through a real Claude Code plugin calling
`fut agent report`. herdr infers it by listing the foreground process group of the pane's own
terminal, which is why a program that owns the terminal and runs the shell somewhere else
hides the agent completely. That failure and its whole history is `decisions/iris.md`, and it
is the one thing fut is structurally immune to.

The worry that goes with a reported state is that it sticks. It does not here. A terminal
registered as working and then killed with no `exited` report left the agents list within two
seconds, because existence follows the pty and only the semantic state comes from the report.

## The prefix, which is the blocker

fut's key grammar takes one printable character, or `ctrl` and a letter, or one of a few named
keys. There is no alt or meta modifier in it, so `alt+z` and `alt-z` are both refused with
`ui.prefix must be one character or a named key such as ctrl-a`. herdr and tmux share `alt+z`
deliberately, one prefix in the fingers, and fut cannot join that. `ctrl-z` is what this config
uses. Adopting fut for real means moving tmux too, which is a decision rather than a config
change.

## Colour needs no generator here, and that is the point

Every colour in the config is a palette slot, an ANSI name or `index:N`, and never a hex value.
Ghostty paints all 256 slots and repaints them on a theme switch, so these follow the
appearance with no map, no emitter, no generated tables and no entry in `src/check-theme.sh`.
Slots 16 to 19 are the four declared per half in `dotfiles/ghostty/theme-map`, already read by
fzf, tmux and the Claude statusline.

This is the one place fut is plainly better than herdr. herdr's eighteen themes are compiled
into its binary, so its config carries two generated tables written by `theme-emit` from
`theme-map`, and a colour change means running the checker and committing what it regenerated.
None of that exists here. fut also gives every style role `remove_modifiers`, which answers the
faint agent line that no herdr token value could ever level.

Writing a hex value into this file is the drift `src/check-theme.sh` catches, and the fix is a
slot rather than an exemption.

## Popups are config, not a plugin

`[trusted_commands.NAME]` takes `title`, `binding`, `program`, `args`, `size` and
`activate_opened`. It opens a dashed frame carrying the title, inherits the calling pane's live
working directory, sends it normal terminal input, and restores the previous layout when the
process exits. The prefix does not work inside it, so a second popup cannot be opened from the
first, which is herdr's rule and means fzf's `become` is still the answer for a tool that
restarts in place.

The herdr module's three tools are a linked plugin called `mdj-tools` for exactly one reason, a
herdr keybinding popup carries no title and only a plugin pane does. A trusted command carries
its own title, so that reason is gone and the registration step goes with it.

`program` is an executable and `args` is a list. fut never inserts a shell, so the inline
command strings the herdr bindings use have no equivalent and every binding needs a file.

## What the scripts would cost, and why they are not here yet

The config names three tools under `~/.config/fut/tools/` that this package does not ship.
lazygit and lf port unchanged, since both need only the working directory a popup already
inherits. The finder does not, and the reason is not the pane id.

A trusted command popup receives no `FUT_*` values at all, only the inherited directory, where
herdr hands a keybinding popup `HERDR_ACTIVE_PANE_ID` and `HERDR_ACTIVE_PANE_CWD`. An extension
command does receive the full chain plus `FUT_BIN` and `FUT_SOCKET`, but it lands in the
workspace root rather than the pane's directory, so the pane's live cwd takes two more daemon
calls to recover, `get` for the uuid and then `list`, because `get` returns a trimmed pane
object without one.

Neither route recovers the busy check. `activity.state` reports only for integrated agents and
stays `idle` while an ordinary shell runs something, and no foreground process or pid is
exposed anywhere in the daemon state. There is also no way for a script to raise a
notification, since the only notify verb takes a `codex` payload. So the finder's ending, which
writes `cd` into a free pane and falls back to a new tab with a message when it is busy, has no
equivalent at all. `decisions/fut-vs-herdr.md` holds the measurements.

## Before this is ever stowed

Two things are unanswered and both belong to the stow step rather than to fut.

Whether `~/.config/fut` needs a `NO-FOLD` declaration. fut keeps its extension store under
`$XDG_DATA_HOME/fut` and its sockets in a runtime directory, so on the face of it nothing is
written beside the config and the fold is safe. That was reasoned rather than watched, and the
way to settle it is to run fut with the config stowed and see what appears. herdr needed the
declaration for exactly this and `decisions/stow-folding.md` has the shape of the problem.

And whether `fzf`, `fd`, `lazygit`, `lf`, `nvim` and `jq` should be declared here. They should,
in the same change that ports the scripts, and not before, since a declaration says this module
breaks without the tool and that is not true while the scripts are absent.

## Reloading

`prefix` then `Shift-R` reloads the invoking client's configuration. The reload is staged
rather than all or nothing, valid global bindings and layout commit first, and a failing
project step leaves those global changes in place and reports the partial success. There is no
server side reload command, so an edit reaches a running client only through that key.
