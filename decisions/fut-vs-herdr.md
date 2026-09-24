# fut beside herdr

Status. fut was dropped on 2026-09-24, its module, map line and Brewfile lines removed, since
nothing ran it. herdr stays the multiplexer in use. The config lives on in git history.
Three things herdr does have no equivalent in fut 0.24 and
each one is recorded below with the test that proves it, so a later version can be rechecked
rather than re-argued.

## Now

Setup no longer installs fut. Until 2026-09-24 `dotfiles/fut` declared it,
`DEPENDENCIES.map` mapped it to a tap, and the package carried a config that was never stowed.
The module guidance and the config are in git history before that date, and what follows is
still the case for bringing it back.

fut is worth carrying for one reason. It learns agent state from the agent, which reports it by
calling `fut agent report` through a real Claude Code plugin. herdr infers it by listing the
foreground process group of the pane's own terminal, which is why a program that owns the
terminal and runs the shell elsewhere hides the agent entirely, the defect recorded in
`iris.md`. fut cannot have that defect.

Two more things it does better. Colour is a flat set of fifteen style roles taking ANSI names
or `index:N`, so a config written in palette slots follows the appearance through Ghostty with
no map, no emitter and no generated tables, where herdr needs all three. And every role takes
`remove_modifiers`, which answers the faint agent line that no herdr token value could level.

What stops it being adopted is the prefix, the busy pane check and notifications. All three are
in Rejected with their measurements.

## Rejected

**Switching to fut now, 2026-09-18.** Three things herdr does have no equivalent, and two of
them cost behaviour rather than habit. The prefix cannot be `alt+z`, so the prefix shared with
tmux breaks. There is no way to ask whether a pane is busy. There is no way for a script to
raise a notification. Each is its own entry below. Reopen when any of them changes upstream.

**`alt+z` as the fut prefix, 2026-09-18.** Refused by fut with `ui.prefix must be one character
or a named key such as ctrl-a`. Both `alt+z` and `alt-z` were tried. The published schema's key
grammar is one printable character, `ctrl` and a letter, or `space`, `enter`, `tab`, `escape`,
`up`, `down`, with no alt or meta modifier anywhere in it. Nothing in the config can work
around a grammar. Reopen if fut's key grammar gains a modifier.

**Reproducing the never type into a busy pane rule, 2026-09-18.** Cannot be done. `sleep 30`
was run in a pane and `activity.state` stayed `idle` for its whole duration, because fut
reports activity only for terminals that have reported agent lifecycle and an ordinary shell
never does. No foreground process, process group or pid appears anywhere in the daemon state,
and the tab name stayed `zsh` rather than following the running command. herdr answers this in
one call, `pane process-info` returning `foreground_process_group_id` and `shell_pid`. Reopen
if fut exposes a pane's foreground process.

Worth stating fairly, since the direction matters. The accident that produced the rule, a path
typed into a coding agent and taken as a prompt, is handled better by fut, because an
integrated agent answers `agent read` with real availability and `agent prompt` is the correct
API. It is vim, a REPL, a running build and anything else unintegrated that fut would type into
and herdr would not.

**Probing the pane's foreground process from a tool instead, 2026-09-18.** Rejected without
building it. fut exposes no pid and no process name for a pane, so a tool would have to find
the pty's child itself through `ps` or `lsof` without being told where to look. That is the
module probing for something rather than asking for it, which the dependency layer forbids for
its own reasons, and it rebuilds badly what herdr answers in one call.

**Porting the finder's pane writing ending through an extension, 2026-09-18.** Rejected because
it solves the smaller half. An extension command does receive the full identity chain,
`FUT_PANE_ID`, `FUT_TERMINAL_ID`, `FUT_SESSION_ID`, `FUT_TAB_ID`, `FUT_WORKSPACE_ID`, plus
`FUT_BIN` and `FUT_SOCKET`, where a trusted command popup receives no `FUT_*` values at all.
But it lands in the workspace root rather than the calling pane's directory, so the live cwd
takes two further daemon calls to recover, and neither the busy check nor the notification
exists either way. So the cost is a manifest, a package and an install step, and the ending
still cannot be rebuilt. Reopen when the busy check exists.

**A `theme-map` and `theme-emit` for the fut module, 2026-09-18.** Rejected as ceremony that
earns nothing. fut's colours accept `index:N`, Ghostty paints all 256 slots per half and
repaints them on a theme switch, and slots 16 to 19 are already declared per half in
`dotfiles/ghostty/theme-map` for fzf, tmux and the Claude statusline. A config written in slots
needs no generator and no committed output. This is the first stowed-shaped module where the
palette contract is satisfied by naming slots rather than by generating a file, and
`theme/CLAUDE.md` should stay the place that says when each applies.

**Declaring `fzf`, `fd`, `lazygit`, `lf`, `nvim` and `jq` in the fut manifest now,
2026-09-18.** Rejected until the scripts exist. A declaration states that this module breaks
without the tool, and with no tool scripts shipped that is false for every one of them. They go
in the same change that ports the scripts.

**Stowing the fut package, 2026-09-18.** Rejected for now. herdr is the multiplexer in use, the
tool scripts are unwritten, and whether `~/.config/fut` needs a `NO-FOLD` declaration has been
reasoned but never watched. fut keeps its extension store under `$XDG_DATA_HOME/fut` and its
sockets in a runtime directory, so the fold looks safe, and `stow-folding.md` is the record of
what assuming that cost last time.

## Log

**2026-09-18 10:40.** Compared fut against herdr at fut 0.24.0, herdr 0.9.0. Every claim below came from the binary rather than from the docs, because the
docs page for configuration never mentions popups or a control interface and both exist.

Brew was dead on this machine before any of it. Every command failed with `You have not agreed
to the Xcode license`, because the selected developer directory is full Xcode and its licence
had never been accepted. `src/install-xcode-clt.sh` guards on `xcode-select -p`, which answers
with the Xcode path and so reports the toolchain satisfied, and the licence is a second gate
nothing in the setup layer checks. Not fixed here, recorded because it blocks the whole package
manager and the guard that should have caught it did not.

**2026-09-18 10:55.** Two beliefs taken from the documentation and both wrong, corrected by
reading the binary and then by running it. The docs describe no popup, overlay or floating
surface anywhere, and `[trusted_commands.NAME]` opens one, with `title`, `binding`, `program`,
`args`, `size` and `activate_opened`. The docs describe no send keys equivalent, and
`fut terminal` carries `send-text`, `send-keys`, `run`, `read` and `wait-output`, with an agent
layer above it holding `prompt`, `read` and `wait`. Read fut's binary or its published JSON
schema at `https://fut.sh/schemas/config.json` before believing its prose.

**2026-09-18 11:05.** Popup behaviour measured by driving a client inside a pty rather than on
screen. The frame is dashed, carries the title on its top edge and `temporary · returns when
command exits` on the bottom, and restores the previous layout when the process exits. fzf ran
inside it and escape closed it. Pressing the prefix and then a command key from inside an open
popup opened nothing and typed the character into fzf, so a popup is modal in the same sense
herdr's is and a tool that wants a second surface still has to restart in place.

One wrinkle. Every fzf escape raises a toast reading `command exited · status 130`, since fzf
aborts with 130. A wrapper exiting 0 would silence it.

**2026-09-18 11:15.** The reported state worry tested directly, because a reported state that
sticks is exactly what `iris.md` records. A terminal was registered as `working` and its process
then killed with `kill -9` and no `exited` report. It left `agent list` within two seconds.
Existence follows the pty and only the semantic state comes from the report, which is the
property the iris hook did not have.

**2026-09-18 11:30.** The context measurement, which is the one that decides what ports. A
trusted command popup was given a script that dumped its environment. It received no `FUT_*`
values at all and only the calling pane's live working directory. An ordinary pane, dumped the
same way, received the whole chain including `FUT_SOCKET`. So a popup knows where it is and not
what it was opened over.

**2026-09-18 11:40.** Extension route measured. A three file package validated first try with
`fut extension validate`. Its command received the full identity chain plus `FUT_BIN` and
`FUT_SOCKET`, and rendered in the same titled frame. Its working directory was the workspace
root rather than the pane's, proved by cd'ing the pane to this repository and running both
command types from it, where the trusted command landed here and the extension landed in the
workspace root. The daemon does track each pane's live cwd, in `list` and not in `get`, so an
extension recovers it with `get` for the uuid followed by `list`. That resolution was wired up
and printed the right directory from inside the popup.

**2026-09-18 11:50.** The two gaps with no route at all. `sleep 30` in a pane left
`activity.state` at `idle` and the tab name at `zsh`, and no process or pid is exposed anywhere,
so there is no busy check. The only notify verb is `fut agent notify`, which accepts a payload
from `codex` and exists to receive agent notifications rather than to post a message, so a tool
cannot raise one. herdr's finder uses `herdr notification show` twice, once to confirm the
`ctrl-y` clipboard copy and name the path it took, once to explain a fallback to a new tab, and
`herdr-finder-keys.md` records that the notification is the only confirmation the copy has.

**2026-09-18 11:55.** Decided to install and declare fut without stowing it, and to ship the
config without the tool scripts. The reasoning for each is in Rejected. Not tested at any point,
lazygit and lf actually running inside a fut popup, and whether herdr's agents sidebar layout,
`agent_panel_sort`, `show_agent_labels_on_pane_borders` and `status_indicators` have fut
equivalents.
- **2026-09-24 15:40.** Dropped fut, removing `dotfiles/fut`, its map line and the tap and
  formula in the Brewfile. Milos asked for it while slimming the Brewfile. Carrying it had a
  cost beyond disk, since the tap ships no bottle, so Homebrew runs its build from source checks
  on it and a machine whose toolchain lacked the running macOS's SDK failed the whole Homebrew
  step on fut. Nothing ran it, so nothing is lost but the record above, which stays.
