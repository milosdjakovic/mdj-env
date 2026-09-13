# Herdr Configuration

Configuration lives in `dotfiles/herdr/.config/herdr/config.toml` and the tools it opens live
beside it in `.config/herdr/tools/`. Stow symlinks both into `~/.config/herdr/`.

Prefix is `Alt-z`, the same as tmux, because both run on this machine and one prefix in the
fingers is worth more than avoiding the overlap. tmux is never modified to suit herdr.

Every change to `config.toml` needs `herdr server reload-config`. The running client does not
notice an edit on its own.

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

A plugin pane requires a title. That is the only reason the three tools are a linked plugin
called `mdj-tools` rather than three keybinding popups. The titles are what the borders read.

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
machine chatter and answers in about a second. Library is kept rather than dropped whole, since
the Obsidian vault lives under Mobile Documents, so the exclusions name the noisy trees inside
Library instead.

Anything new that scans broadly owes the same measurement before it ships.

## Current keys

`g` the built in session navigator, herdr's `goto`. `alt+g` lazygit, in the repository the pane
sits in, falling back to the recent list lazygit keeps for itself. `f` the fuzzy search. `alt+f`
lf, viewing only, since every interactive key lf binds opens a tmux popup and there is no tmux
session inside a herdr popup to open one into.

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

Some of this is a render attribute rather than a colour, and that is the trap. The agent
name under an agent row and the branch under a space row both read `overlay0`, yet the
agent one is visibly lighter, because its row entry carries a `dim` flag. No value set
anywhere will level them. The fix is `ui.sidebar.agents.rows`, where each entry may be a
bare token name or a style table of `token`, `fg`, `bold`, `dim` and `rules`, so the default
`"agent"` string becomes `{ token = "agent", dim = false }`. `ui.sidebar.spaces.rows` is the
matching key for the other section. The same dimming is why an unfocused tab showing only
its number looks fainter than a renamed one.

That trap is also why this map is worth probing rather than reasoning about. Two rounds of
reasoning about which token painted the agent line were both wrong, because the premise that
a difference in appearance means a difference in token is false here.

Two more things worth knowing before changing any of this. `sidebar_bg` is not the
highlighted row, it is the whole sidebar, and omitting it leaves the sidebar on the terminal
background, which is almost always what is wanted. And the theme is client local, so
`herdr server reload-config` reports applied and repaints nothing. A theme change needs a
detach and reattach, `prefix+q` then `herdr`, which keeps every pane since panes live in the
server. Reading an applied status as proof of a theme change is a mistake this section exists
to stop being repeated.
