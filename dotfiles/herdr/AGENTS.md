# Herdr Configuration

Configuration lives in `dotfiles/herdr/.config/herdr/config.toml` and the tools it opens live
beside it in `.config/herdr/tools/`. Stow symlinks both into `~/.config/herdr/`.

Prefix is `Alt-z`, the same as tmux, because both run on this machine and one prefix in the
fingers is worth more than avoiding the overlap. tmux is never modified to suit herdr.

Every change to `config.toml` needs `herdr server reload-config`. The running client does not
notice an edit on its own.

## A session behind a pty proxy is invisible, and that is upstream's

herdr names the agent in a pane by listing one process group, the foreground group of the
pane's own terminal. A program that owns that terminal and runs the shell on a second one in
a session of its own, a shell front end, a tmux started inside the pane, anything of that
shape, leaves the agent in a group herdr never lists, and the pane never appears in the agents
panel. Nothing in the config here changes that, and a hook that announced the pane was tried
and made things worse. The whole record, the herdr version it was measured at, the upstream
pull request that was closed unread, and how to recheck it after an upgrade, is
`decisions/iris.md`. Read it before touching detection or before adding anything to the shell
that holds the terminal.

## The popup surface, and its one rule

A popup is session modal. It takes every key including escape, it does not disturb the tiled
layout, and it closes when its command exits. Only one can be open at a time, so anything that
would open a second from inside the first has to restart in place instead. fzf's `become` is
the tool for that, and it is what the finder's two toggles use.

The rule that everything else follows from is that a popup is one window, so it gets one frame
and one name.

## Naming, and why these are a plugin

A keybinding popup carries no title. It takes a key, a type, a command, a description and two
sizes, and nothing else, and the description only ever appears in the help panel on `prefix+?`.
So herdr labels the border with the literal word popup and there is nothing to change.

A plugin pane requires a title. That is the only reason the tools are a linked plugin
called `mdj-tools` rather than keybinding popups. The titles are what the borders read.

The consequence for anything new is direct. Do not draw a border inside a popup and do not
label one. The frame is already there and it already carries the name, so a second one is the
same name twice around the same window. This was written the wrong way first, with fzf's
`--border-label` naming the picker back when a command popup had no title to give it, and the
two frames survived the conversion until the nesting was visible on screen.

The same applies to text that repeats the title. A header line inside the picker earns its
place when it says something the title cannot, such as which way the toggles are set, and not
when it says the tool's own name again.

## Escape closes everything

Escape closes every popup here, and a new one joins that or it does not ship. Uniformity is the
whole point, since a surface where one window out of three needs a different key to leave is a
surface you have to think about.

fzf exits on escape by itself. lazygit does not. Escape there means go back one level and does
nothing at the top, so lazygit alone needed `q`. It has `quitOnTopLevelReturn` for exactly this
and it is off by default.

Turn it on for the herdr popup alone, never globally. `tools/lazygit-popup.yml` holds the single
line and `tools/lazygit.sh` loads it through `LG_CONFIG_FILE` with the real config first and the
overlay second, so everything in the real config survives and lazygit in tmux and in a plain
terminal keeps its own behaviour. A later file in that list wins.

## Never type into a busy pane

A popup has no pane of its own, so a tool that wants to leave something behind acts on the pane
the popup was opened over. Typing into that pane is only safe when the shell itself is what is
waiting for input. Otherwise the text lands inside whatever is running, and a path typed into a
coding agent is submitted to it as a prompt, which is how this was found.

Herdr reports a free pane by giving the foreground process group the same id as the shell, so
`pane process-info` answers the question and that comparison gates every write. A busy pane is
left alone and the work opens as a new tab instead, with a notification saying why.

## Where a notification actually appears

`[ui.toast] delivery` decides that, and the tools here depend on the answer rather than being
indifferent to it. herdr's own default config names four values, `off` disables pop ups,
`herdr` draws an in app toast, `terminal` asks the outer terminal for a desktop notification,
and `system` asks the OS notification service directly.

It is `herdr` here, so a notification is drawn inside the terminal by herdr itself. That is the
value the tools are written for. The finder's `ctrl-y` ending copies a path and says so, and
its busy pane fallback explains why the work opened in a new tab, and in both cases the popup
is already gone by the time the message arrives, so the toast is the only confirmation there
is. A desktop notification would work too and would arrive outside the window the work happened
in, and `off` would silently remove the only feedback those two endings have.

## Context arrives two different ways

A keybinding popup is handed `HERDR_ACTIVE_PANE_ID` and `HERDR_ACTIVE_PANE_CWD` as environment
variables. A plugin popup is handed one JSON blob in `HERDR_PLUGIN_CONTEXT_JSON` instead, and
gets neither variable. `tools/context.sh` resolves both and every tool sources it, so a tool
works the same whichever way it is opened and the binding style stays a free choice.

## Registration is not stow's job

Stow puts the plugin files in the home directory. Herdr keeps the registration in its own global
state, so a fresh machine has the manifest, the scripts and the keybindings and no plugin, and
every key fails silently. `src/setup-herdr-plugins.sh` links it after stow and is idempotent by
asking herdr what is registered.

Link, never install. Install is for GitHub sources and copies the files into a herdr managed
checkout, which forks them away from this repository and makes every later edit a reinstall.

Linking used to have one consequence worth knowing, and it is now handled rather than
described. `~/.config/herdr` was a single stow symlink into this package on a machine where
the directory did not exist before stow ran, so everything herdr wrote beside its config, the
sockets, the logs, the session state and the registration, was written into the repository.
This module declares that directory in its `NO-FOLD` file now, and the stow step makes it a
real directory before linking and unfolds a machine where it is already a symlink, so herdr's
state stays in the home directory and only `config.toml` and `tools` are links back here.

Registration still produces `plugins.json`, and it still records the absolute path of this
checkout, which is why `src/setup-herdr-plugins.sh` regenerates it on each machine rather than
the repository carrying it. It simply lands beside the sockets in the home directory now. The
three `.gitignore` lines that covered the leak are gone, since the directory they guarded can
no longer be written. `decisions/stow-folding.md` has the whole of it.

## Reading a reload

`herdr server reload-config` reports diagnostics and they are the proof, not decoration. A key
that two things want reports `prefix+X: kept keys.Y, disabled keys.command[N].key` and a status
of partial, and herdr resolves it in favour of the built in action rather than the custom
command.

That makes the empty diagnostics list a test rather than a formality. Binding a custom command
to a key on purpose and watching whether the conflict appears is how to tell whether a built in
action really holds that key.

Two things that look obvious and are not. An empty string genuinely unbinds a built in action,
including one the reference does not mark optional. And deleting that empty line does not hand
the key back, so a default you want has to be written out in full. Both were found the same way,
with the probe above.

## Do not walk the home directory

The finder starts at `$HOME`. A plain walk from there reports a hundred and sixty three thousand
folders and takes seven and a half seconds, which is not a picker. `tools/find.sh` cuts the
machine chatter and answers in about a quarter of a second.

What it cuts and what it reaches back into lives in `tools/find-scope`, not in the script, because
that answer differs between machines while the logic does not. Two verbs, `exclude` and `include`,
everything after the first space is the path so a space needs no quoting, and an `include` that
does not exist here is skipped rather than refused, which is what lets one file serve every
machine. That file carries the reasoning for each line.

**Never traverse cloud provider storage.** macOS puts all of it under exactly two fixed roots,
`Library/CloudStorage` for every third party provider through the File Provider API and
`Library/Mobile Documents` for iCloud. They are the same on every Mac and independent of which
accounts exist, so excluding the pair is a rule rather than a patch. Only the first was here
once, and the missing twin is what made this picker unusable: evicted files are dataless
placeholders and enumerating one blocks on the network, so with Optimize Mac Storage on the walk
never finished and the first two thousand rows alone took a minute and a half at zero percent CPU.

That is not one machine's bad luck, which is the reason it is written down. Eviction follows disk
pressure, so a machine where everything is downloaded today starts blocking months later and the
picker looks like it broke by itself.

Do not try to detect it, it was checked and it cannot be done. Evicted files sit on the same
device and the same filesystem as everything else, so `--one-file-system`, mount type tests and
any "is this remote" predicate are blind to them. A deadline fails too, since fd buffers when its
output is a pipe and the blocked threads starve the stream. Spotlight does answer without
blocking, because it reads its own index, and it is ten times slower and returns everything, so it
needs this same list anyway.

The Obsidian vault is the one thing reached back out of iCloud, one container out of a hundred and
ninety four, which costs 0.025s rather than the whole tree. Its own files are evicted too and it
is quick only because the walk reads directories and those are still materialised, so if that ever
changes this is the line that will block.

Anything new that scans broadly owes the same measurement before it ships.

## The palette

`prefix+space` opens `tools/palette.sh`, one list of every agent, space, tab, pane and session,
every herdr action with its key, every custom command here and every action another plugin
offers. `decisions/herdr-palette.md` has why it was written here rather than installed, the
four published palettes it was compared against, and everything turned down since.

**Rows.** A pane with an agent in it is listed once, as the agent. A tab with one pane is
listed once too, as the tab with that pane's command or path quiet beside its name, and a pane
only gets a row of its own beside other panes. Every row that stands for a pane reads the same
way, whichever group it is in. The title is what you call it, the middle is what it is doing
now, an agent's conversation topic or a shell's command or path, and the right is where it is,
with an agent's state as a word in a column of its own before it. The group says whether there
is an agent inside, which is what decides the state and the order, so `agent` and `pane` stay
apart. A pane you name goes by that name in all three places. herdr reports `label` on a pane
only once it has been named, so a snapshot of unnamed panes shows no such field, which reads
as panes having no names at all.

**Order.** Agents come in the order they want you, blocked, done, working, idle. Spaces and
tabs keep the snapshot's order, which is their order on screen, and never their `number`,
since a moved tab keeps the number it had. The last five rows picked come first when nothing
is typed, skipping the one you are in, which leaves the place you came from on top. The row
the palette was opened over says here.

**The history** is `recent-<session>` in the state directory herdr hands every plugin,
`HERDR_PLUGIN_STATE_DIR`, one file per session since ids belong to one server. It cannot live
beside the script, since herdr runs the script through the plugin link, so its folder is this
checkout.

**Actions are data.** `tools/palette-actions` holds one line per action and its header says how
a line reads, the modes, run, confirm, api, shell, step and key, and the placeholders. Adding an
action is one line there and no change to the script. The key shown on a row is read from
herdr's defaults overlaid by `[keys]` here, so a rebinding shows up on the next open.

**The subject.** An action acts on the pane, tab and space its placeholders read, which is where
the palette was opened, or the selected row when a key from `tools/palette-keys` was pressed.
That file says which key does which action on which kind of row, `ctrl-r` rename, `ctrl-x`
close and `ctrl-p` prompt an agent, and the footer is built from it as the cursor moves, so it
only ever lists the keys that work on that row. Placeholders ask for their value when they are
reached, `{input}` and `{label}` a line of text, `{label}` starting from the current name, and
`{worktree}` a pick from the space's repository.

**The preview** under the list shows the recent output of the pane a row stands for, an agent,
a pane, or the focused pane of a tab or space, five hundred lines read with `herdr pane read`
in under ten milliseconds, following the end, with carriage returns and trailing blank rows
dropped, and output shorter than the window padded at the top so it sits at the bottom, since
fzf otherwise draws it from the top and leaves the window empty below, which an agent's screen,
often shorter than the window, always showed. fzf also lets a preview scroll until its last line
reaches the top, leaving the window empty beneath it, and neither offers a setting against it
nor says where the preview is scrolled to. So the wheel over the preview and shift with up and
down go through `palette.sh --scroll`, which counts the lines below the window in a directory
the run removes on exit and stops a scroll at either end. Other rows hide the preview, and
`ctrl-/` hides it by hand. A full screen agent such as Claude keeps its conversation off herdr's
scrollback and draws for its own pane's size, so its preview is that screen, cut or padded to
the window, and nothing more. The script answers fzf through flags at its top, `--preview`,
`--focus` and `--scroll`, which return before the snapshot and the rows are built, and that is
what keeps them fast.

**What herdr's CLI lacks** goes to its socket. Moving a tab, clearing a pane and editing
scrollback are API methods with no command, so the `api` mode writes one JSON line to
`HERDR_SOCKET_PATH` with `nc` and reports a refusal. `tab.move` takes the slot the tab is
inserted before, counted before it is lifted out, which `{tab_slot_left}` and
`{tab_slot_right}` work out.

**What only herdr's window does** stays a key hint. Help, settings, detach, the space picker,
go to, resize mode, last pane and cycling panes exist only in the client, and `command.invoke`
only takes ids herdr hands its own client through a channel the public schema never shows. The
rule is that this module drives herdr through herdr's CLI and socket alone and never through
another program pressing keys, so a rename is our prompt and these rows say which key to press.

**Work that outlives the popup.** A custom command, a plugin action, a socket request and a
shell action all start detached and give the palette 0.3 seconds to close first, since herdr
refuses a second popup with `ui_busy` and a slow action would hold this one open. Detached
means a process group of its own, through `set -m`, because closing a popup ends its whole
process group and a child that only ignores hangups dies with it. A new agent goes through
`tools/new-agent.sh`, which splits and then retries the start, since a pane split a moment ago
is not yet the available shell `agent start` requires.

**Pane focus.** herdr cannot focus a pane by its id, only step to a neighbour by direction. So a
pane row focuses the pane's tab and then asks `pane neighbor` which pane in that tab has the
target beside it, and steps once from there, which leaves herdr's own idea of beside in charge.

**Testing.** `test/palette-test.sh` runs every kind of pick against a headless server of its
own, with a scripted fzf and a wrapper that records notifications, and removes the session on
the way out. Run it after changing the palette and after upgrading herdr, since the palette
reads the shape of herdr's output. It leaves out new agent, which starts a real agent, and edit
scrollback, which needs a client to open into. A popup opens in a headless session too, so
anything that has to happen as a popup closes can be probed by linking a throwaway plugin whose
pane does just that, then unlinking it.

## Current keys

`space` the palette, whose agent rows replaced the flat agent picker that was on `a`. `g` the built in session navigator, herdr's `goto`. `t` is `last_pane`, back and forth across tabs and spaces. `alt+1..9` is `focus_agent`, which is unset by default and so looked broken. `ctrl+1..9` is `switch_workspace`, also unset by default, so a bare digit is a tab, alt an agent and ctrl a space. `decisions/herdr-navigation-keys.md` has the reasons. `alt+g` lazygit, in the repository the pane
sits in, falling back to the recent list lazygit keeps for itself. `f` the fuzzy search. `alt+f`
lf, viewing only, since every interactive key lf binds opens a tmux popup and there is no tmux
session inside a herdr popup to open one into.

Inside the fuzzy search, enter opens the chosen place and `ctrl-y` leaves with its absolute path
on the clipboard instead. It is `--expect` rather than a binding that copies in place, because a
picker that has answered should close, and fzf then prints the key it left on first and the
selection after, so both endings share one parse. The key itself is the one fzf allows. Shift and
enter reads more naturally and fzf rejects the name outright, and `ctrl-c` is how fzf aborts, so
taking it would cost an exit. Nothing on screen says a copy happened once the popup is gone, so
the notification is the only confirmation there is and it names the path it took.

The keys and the toggle states are a `--footer`, so they sit pinned to the bottom edge rather
than riding above the list where a header puts them. fzf rules the footer off with the same
horizontal line it already draws under the match counter, which leaves the window ruled at both
ends and is a separator rather than a second frame, so the one border rule above still holds. A
line that explains why a picker appeared at all is different and stays a header, which is where
the lazygit fallback keeps its own, since that is read before anything else rather than referred
back to while picking.

## The picker colours come from one file fzf rereads

The colours in these pickers come from `~/.config/fzf/fzfrc`, the one options file every fzf
on the machine reads at launch through `FZF_DEFAULT_OPTS_FILE`, which the zsh package exports
and the tmux config sets in its server. A popup command is a child of the herdr server rather
than of a login shell, so it inherits the environment the server froze when it started, and
that used to matter, because the colours were a string in that environment and an edit reached
these popups only after the server itself was restarted. What is frozen now is a path that
never changes, and fzf reads the file behind it every time it starts, so an edit to the file
reaches the next popup with no restart. The server does have to have started with the path in
its environment at all, which is a one time restart on a machine that predates the file.

One consequence caught the footer. fzf gives `footer` its own colour name and its own default of
cube index 109, a pale blue green outside the sixteen slots a theme paints, and it does not
follow `header`, so the line drew in fzf's colour until `footer:4` was named alongside it.

## The selection bar is a declared slot

Everything in these pickers is a palette slot, including the selection bar, which for a while
could not be one. A bar has to be a tint of the page under it, and no slot among the sixteen is
dark on the dark palette and light on the light one, because each is claimed by a role that
differs by half. It is the same wall the iris menu hit while it was here, and the reason that grew appearance
aware tables there.

Ghostty paints all 256 slots, so slot 16, the first one no ANSI name claims, is declared in
Ghostty's `theme-map` per half, the grey of this module's border on dark and the grey of its
focused row on light, and the options file names `bg+:16` like every other colour.
Slot 17 is the grey of the secondary line here, which the footer reads. A theme switch
repaints it with everything else and nothing watches anything. `find.sh` resolved the bar from
this module's `config.toml` at draw time for a while, asking the system which half it was on,
and that code is gone. `decisions/fzf-appearance-colour.md` holds every approach that was tried
before this one.

## Where the colours come from, and how to reload them

The two `[theme.custom.*]` tables in `config.toml` are generated and must not be edited by hand.
The colours live in `theme/palettes` at the repository root, and `theme-map` at this package
root says which herdr token takes which role, with the reason beside each one that is not
obvious. `theme-emit` beside it rewrites the span from the `[theme.custom.dark]` header to the
`[keys]` header in place and copies every other byte of the config through, because herdr has
no include and the tables have to sit inside a file that is otherwise hand written. Run
`src/check-theme.sh` after changing a colour or a role, review the regenerated tables, and
commit them. `theme/AGENTS.md` has the whole contract.

Three roles exist because of this module and every palette answers them. `highlight` is
`selection_bg`, the navigate cursor row, and it is what the iris menu bar read too while iris was here, purple on
the dark half and a neutral grey on the light one because a tinted bar on the light page reads
as a lilac slab. fzf's bar is a neutral on both halves instead, slot 16 in Ghostty's map. `subtext` is `subtext0`, the ink stepped back for a row that
is not selected. `fill` is `accent`, the primary purple on dark and that purple darkened on
light, because the chip carries a label painted in `panel_bg` and a block wants more room than
a letter. `active_row_bg` takes `selection` on dark and `surface` on light, which is the same
purple against neutral split, and the map says so beside it.

The theme is client local, so `herdr server reload-config` reports applied and repaints
nothing. A theme change needs a detach and reattach, `prefix+q` then `herdr`, which keeps every
pane since panes live in the server. The full explanation is at the end of the dim section
below, and reading an applied status as proof of a theme change is the mistake it exists to
stop.

## Which theme token paints what

The config reference lists nineteen colour tokens and writes a real description for three of
them. The other sixteen get the same sentence about accepting hex, and none mentions the tab
bar at all. So this map came from three rounds of probe, each one setting a handful of tokens
to unmistakable colours and reading the result off the screen, after several rounds of
guessing at values had produced nothing.

Surfaces. `accent` is the active tab background. `surface0` is the inactive tab background,
and `reset` there gives it the terminal background so it reads as no fill. `surface_dim` is
the borders, the left edge and the divider between agents and spaces. `active_row_bg` is the
active space and focused agent row. `selection_bg` is the Navigate-mode cursor row.

Text. `text` is the selected sidebar row's label. `subtext0` is the primary label on
unselected space and agent rows. `mauve` is the secondary line, and only on a highlighted
space, not on an agent. `overlay0` is the muted headings, the words new, menu, agents,
grouped and spaces, and it is also the secondary line on a space that is not highlighted.
`overlay1` is the plus and the label of an unfocused tab, but only one that has been
renamed.

Status. `green` is the idle agent's empty circle and `yellow` is the working agent's.

`panel_bg` is two things, and this is the one that governs the whole design. It is the panel
background, it backs the popup border, and it is also the active tab's label. So no token
sets that text. It is the background colour painted onto the accent fill, which means a fill
close to the background hides its own label, and the way to make the active tab readable is
to push the fill away from the background rather than to look for a text token. That is why
the active tab is an inverted chip here, dark under a light theme and light under a dark one,
and why the focused sidebar row follows it rather than staying a quiet lift.

`surface1` painted nothing visible in either of the two layouts it has been probed against,
and `blue`, `red` and `peach` likewise, so those four are free.

## Dim is not a colour, and it is not herdr's either

Three separate complaints about text being too light turned out to be one thing. herdr is a
ratatui program, its binary carries crossterm's literal `\x1b[2m`, and a row entry marked
`dim` is drawn in its ordinary token colour with the terminal's faint attribute set. Ghostty
then renders that at `faint-opacity`, which defaults to 0.5, so the text is the right colour
blended halfway into the background. No value assigned to any token can level it, because
both halves of the pair already hold the same value.

The light half proves this on its own without a probe. `overlay0` and `overlay1` both take
the `overlay` role there, so any two pieces of chrome that differ in lightness under the light
theme differ by attribute and not by colour.

Two entries in the default agent layout carry the flag, the agent name on the second row and
the tab name on the first. Both are levelled through `ui.sidebar.agents.rows`, where an entry
may be a bare token name or a style table of `token`, `fg`, `bold`, `dim` and `rules`, so
`"agent"` becomes `{ token = "agent", dim = false }` and likewise for `"tab"`.
`ui.sidebar.spaces.rows` is the matching key for the other section, and leaving it alone is
what keeps the line being matched to untouched.

Which entry on that first row was the faded one came from `herdr api snapshot` rather than
from looking at it. The row is `state_icon, machine, workspace, tab`, `machine` renders empty
for a local agent, so only two labels appear and either could be either. The snapshot names
the workspace and tab labels for every agent, and matching those strings against what is on
screen settles it in one command. Two earlier rounds of reasoning about this row were both
wrong, so prefer the snapshot.

The tab bar is dimmed the same way and has no config lever at all. herdr styles it nowhere,
the config reference has thirty three `ui` keys and not one of them reaches a tab label, and
Ghostty's `faint-opacity` is the only other control, global to the terminal and certain to
flatten faint text in every program running in it.

It does not need one, because the dim there is not about the number. `herdr tab rename` with
the label the tab already has clears it, so what herdr tracks is whether a name was ever set
and not what the name says. A tab created by accepting the prompt's proposed number counts as
unnamed even though the proposal is stored as its label, which is why `herdr tab get` shows a
label of `4` on a tab whose number is 8 and still draws it faint. Renaming it to `4` changes
no visible text and settles it.

Two more things worth knowing before changing any of this. `sidebar_bg` is not the
highlighted row, it is the whole sidebar, and omitting it leaves the sidebar on the terminal
background, which is almost always what is wanted. And the theme is client local, so
`herdr server reload-config` reports applied and repaints nothing. A theme change needs a
detach and reattach, `prefix+q` then `herdr`, which keeps every pane since panes live in the
server. Reading an applied status as proof of a theme change is a mistake this section exists
to stop being repeated.
