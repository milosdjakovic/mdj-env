# Tmux Configuration

Configuration lives in `dotfiles/tmux/.tmux.conf` with helper scripts in `dotfiles/tmux/.tmux/scripts/`. Stow symlinks everything to `~/.tmux.conf` and `~/.tmux/scripts/`.

Prefix is `Alt-z` with `Alt-Z` as secondary for caps lock tolerance.

## Binding conventions

Every custom prefix binding must include `-N "description"` so it appears in `tmux list-keys -N`. The `?` binding shows a searchable cheat sheet of all noted bindings via fzf.

## Priority system

`tmux list-keys` outputs bindings alphabetically by key, which scatters the most used bindings among navigation and resize keys. The `[p:N]` priority tag controls visual order in the `?` cheat sheet so the most important bindings appear at the top regardless of which key they are bound to.

Custom bindings use a `[p:N]` prefix in their `-N` note, for example `-N "[p:1] Tmux actions (tmux-fzf)"`. The cheat sheet sorts prioritized bindings by N first, then appends unprioritized bindings. The `[p:N]` tag is stripped before display using sed so the user only sees the clean description.

When adding a new binding, pick a priority number that places it in the right group. Do not duplicate priority numbers. The one exception is a family of sibling bindings that are one feature spread across several keys, where a shared number is what keeps them adjacent in the cheat sheet instead of scattering the feature across the list. The nine session jump keys are the only family so far, and they all carry `[p:11]`. The current assignments are listed below.

### Priority assignments

0. Launcher / command palette (`Space`)
1. Tmux actions via tmux-fzf (`m`)
2. Tmux management menu (`M`)
3. Lazygit popup (`g`)
4. File explorer popup (`b`)
5. Switch to last window (`a`)
6. Switch to last session (`e`)
7. Sessions fzf switcher (`s`)
8. Recent repos & worktrees lazygit (`G`)
9. Repos & worktrees picker (`r`)
10. Sessions tree view (`S`)
11. Jump to session by number (`M-1` through `M-9`)
13. Previous session (`M-p`)
14. Next session (`M-n`)
15. Move session left (`M-P`)
16. Move session right (`M-N`)
17. Previous window (`p`)
18. Next window (`n`)
19. Previous pane (`O`)
20. Next pane (`o`)
21. Move window left (`P`)
22. Move window right (`N`)
23. Select pane left (`h`)
24. Select pane down (`j`)
25. Select pane up (`k`)
26. Select pane right (`l`)
27. Resize pane left (`H`)
28. Resize pane down (`J`)
29. Resize pane up (`K`)
30. Resize pane right (`L`)
31. Zoom/unzoom pane (`z`)
32. Split pane horizontally (`"`)
33. Split pane vertically (`%`)
34. New window (`c`)
35. Show all keybindings (`?`)
36. Scratch shell popup (`` ` ``)
37. Search explorer tags (`t`)
38. Find files globally (`f`)
39. Find files in pane working dir (`F`)

## Switching and moving, one modifier apart

Windows and sessions share one scheme rather than two unrelated ones. Plain `n`/`p`
switches windows, `M-n`/`M-p` (option) switches sessions, `N`/`P` (shift) moves the
current window left or right, and `M-N`/`M-P` (option+shift) moves the current session
left or right. The rule is just the two modifiers composing: option means session
instead of window, shift means move instead of switch. Nothing about `n` or `p`
themselves changes meaning, only what's layered on top of them.

Window move is `swap-window` against the adjacent index. Session move is
`session-index.sh --move`, the session-strip equivalent, and is what makes the
session order in that strip persistent and user-orderable rather than always
re-sorted alphabetically, see below.

Plugin bindings (tpm, yank, resurrect, sensible) do not use priority tags and appear after all prioritized bindings.

## FZF switchers

Sessions (`s`) use fzf in a `display-popup`, sorting by last used and excluding the current session. `S` opens the native tmux tree view.

## FZF search popups

Tags (`t`), files (`f`), and files globally (`F`) open fzf in a popup. Tags reads from the file explorer via `~/.tmux/scripts/fzf-tags.sh`, which asks `explorer.sh --tags` for plain paths and never knows which explorer it is. File search uses fd with process substitution (via `~/.tmux/scripts/fzf-files.sh`) so fzf exits instantly without waiting for fd to finish traversing.

Four actions are available inside every finder popup, all selected by the key you press to leave fzf rather than by separate top-level bindings. Enter copies the selected path to the clipboard. `^v` opens the file or folder in nvim inline in the same popup, replacing the script process via `exec nvim`, so the popup closes when nvim exits. `alt-v` opens it in a new tmux window with the right cwd, and the window auto-closes when nvim exits because tmux's default `remain-on-exit` is off. `^b` hands the path to the file explorer through `explorer.sh --reveal`, chosen to match the `prefix+b` mnemonic, and it takes over the popup by the same `exec` move as `^v` rather than opening a second one, which tmux refuses while a popup is on screen. Its hint reads the explorer's name from the adapter, so it shows `^b lf` today and renames itself with the adapter. Files and folders are both supported by every action. The branching is implemented with fzf's `--expect=ctrl-v,alt-v,ctrl-b` flag, which prints the pressed key as the first line of fzf's output.

Popup size is 90% x 90% so inline nvim has room comparable to the lazygit and file explorer popups. The smaller 80 x 70% sizing was kept only on read-only popups (sessions list, cheat sheet) where extra height would just be empty space.

## FZF launcher (command palette)

`prefix+Space` opens a command palette showing all available tools and actions. The launcher script lives at `~/.tmux/scripts/fzf-launcher.sh`.

Entries are defined in a pipe-delimited data section at the top of the script. Each line has four fields: `category|display_key|description|command_id`. The display key is what the user sees (e.g. `prefix+g`), or `---` if no direct binding exists. The command ID maps to a case in the `execute_cmd` function which handles the actual tmux command. This separation avoids quoting issues with complex tmux commands in the data section.

To add a new entry, add a line to the `ENTRIES` variable with the correct category, key, description, and a new command ID, then add a matching case to `execute_cmd`.

Categories are toggled via keyboard shortcuts in the fzf header, using the same `become()` pattern as the scoped fzf switchers and lf fzf-find. The active category shows in brackets. Available categories are `tools` (popup apps like lazygit, the file explorer, scratch shell, tag/file search), `nav` (session switcher and tree view), and `tmux` (session management, config reload, plugin operations). The default view shows all.

The pane's working directory is passed as `$PANE_PATH` from the `.tmux.conf` binding since `#{pane_current_path}` does not resolve inside a popup. Commands that need a working directory (lazygit, the file explorer, scratch) use this variable.

## File explorer

Opened by `prefix+b` and from the launcher, where it shows as `File explorer popup (lf)` with the name computed at open time from `~/.tmux/scripts/explorer.sh --name`, so switching explorers renames the entry automatically. The same name fills the tag picker entry.

The design splits a rigid interface from a swappable adapter, the same shape as the VPN popup. `explorer.sh` is the whole interface and never names an explorer. All explorer specifics live in `explorer/<adapter>.sh`, selected by `EXPLORER_ADAPTER` at the top of `explorer.sh` (default `lf`). An adapter defines four functions. `explorer_name` prints a human label. `explorer_argv` prints the command one argument per line, so an argument may contain spaces and the interface never word splits a string. `explorer_needs_nested_session` returns 0 when the explorer opens popups of its own, which makes the interface wrap it in a nested tmux session, and 1 when it runs directly. `explorer_tags` prints every tagged path, one absolute path per line, and an explorer without such a feature prints nothing, which leaves the tag picker simply empty.

The interface offers four subcommands. `--name` is the label. `--open [dir]` resumes the explorer where it was left, or starts it at the directory when nothing is running, which is what `prefix+b` and the launcher do. `--reveal <path>` starts it showing one path, a file or a directory. `--tags` is the normalized path list. Every caller goes through these and none of them knows which explorer is configured, the `prefix+b` binding, the launcher, `fzf-files.sh`, and `fzf-tags.sh`. Adding an explorer is a new file in `explorer/` plus one line at the top of `explorer.sh`, and a line in `DEPENDENCIES` naming the new binary.

`--open` and `--reveal` differ in one deliberate way. `tmux new-session -A` attaches to an existing session and ignores both the working directory and the command, so the persistent `~files` session means a second `--open` resumes the kept place rather than honouring the directory it was handed. That is right for `prefix+b`, where resuming is the point. It is wrong for `--reveal`, where being taken to a specific path is the entire request, so `--reveal` kills any running session first and starts a fresh one at the target. The cost is real and worth knowing, using `^b` from a picker discards wherever the explorer was last sitting. Reveal also passes the target to the explorer as a trailing argument, which is why the contract asks an adapter for a command that accepts an optional path, and it is what puts the cursor on the file rather than only on its folder.

The lf adapter knows lf's tag file lives under the XDG data directory and that its format is `path:X` with a single character tag, so it strips the trailing marker and hands back plain paths. It names the binary rather than pathing to it, and keeps an `LF` environment override so the contract can be exercised against a stub.

## VPN control popup

Reached only from the launcher, shown as `VPN service (Mullvad)` where the provider name is dynamic. It has no direct binding. The launcher computes the label at open time by calling `~/.tmux/scripts/fzf-vpn.sh --name`, so switching providers renames the entry automatically.

The design splits a rigid interface from a swappable adapter. `fzf-vpn.sh` is the whole interface and never talks to a VPN directly. It asks the active adapter for normalized values and lays them out identically for any provider. All VPN specifics live in `vpn/<adapter>.sh`, selected by `VPN_ADAPTER` at the top of `fzf-vpn.sh` (default `mullvad`). An adapter defines six functions, `vpn_name`, `vpn_status`, `vpn_connect`, `vpn_disconnect`, `vpn_locations`, and `vpn_set_location`. Each may run several CLI commands to produce one normalized answer. `vpn_status` emits `STATE<TAB>LOCATION<TAB>RELAY<TAB>TARGET_ID` with STATE being `connected` or `disconnected` and TARGET_ID identifying the configured relay so the active row can be marked, and `vpn_locations` emits `DISPLAY<TAB>ID` rows where ID is opaque to the interface and handed back verbatim to `vpn_set_location`. To add a provider, copy `vpn/_template.sh`, implement the six functions, and point `VPN_ADAPTER` at it.

The popup is a single fzf instance that never auto closes. The header is one line, provider then state then location and relay, with the state word in bright white. The bottom border carries the state-aware verb, disconnect when up and connect when down. The body is the searchable location list, and the currently configured relay is marked with a trailing ` <` so it reads the same whether or not the cursor is on it. Selecting a location runs `vpn_set_location` and connects, and `ctrl-space` toggles connect or disconnect. Both actions use fzf `execute-silent` with `reload` and `transform-header` plus `transform-border-label`, so the command runs, the list re-marks the new active row, the header and border rebuild from fresh adapter data, and the popup stays open. It closes only on `ctrl-c` or `ctrl-d`, leaving every printable key free for the search. Actions block briefly while the adapter waits for the tunnel so the refreshed status reads accurately.

## Keep-awake control popup

Reached only from the launcher, shown as `Keep awake` and, when a keep-awake is
active, `Keep awake (ACTIVE, indefinite)` or `Keep awake (ACTIVE, until 16:45)`.
The launcher computes the suffix at open time by calling
`~/.tmux/scripts/fzf-caffeinate.sh --summary`, so the current state shows
without opening the popup.

It deliberately mirrors the VPN popup shape, a single fzf instance that never
auto closes, a one-line status header with the state word in bright white, a
state-aware bottom border, and a body list whose active row is marked with a
trailing ` <`. It offers four actions. Indefinite keeps the Mac awake with no
timeout. For a duration keeps it awake for N hours and minutes. Until a time
keeps it awake until an HH:MM within the next 24h. Disable stops any active
keep-awake. Enter applies the highlighted action, using fzf `transform` to run
the script, which rebuilds the list, header, and border from fresh state so the
popup stays open. It closes only on `q`, `ctrl-c`, or `ctrl-d`.

Unlike VPN there is no swappable adapter, because macOS has a single backend,
the `caffeinate` binary, so the interface and mechanism live in one file. A
keep-awake is one detached `caffeinate -d -i -s` process, which prevents
display, idle, and system sleep (`-s` holds only on AC power). A small state
file under `$TMPDIR` records its pid, mode, and end epoch so status survives
across popup opens, and a dead pid clears the file so a self-exited timer reads
as inactive. Timed modes pass `-t <seconds>` so caffeinate self-exits, with the
duration computed from a parser that requires a unit and accepts `1h30m`, `45m`,
or `5h` but not a bare number, and the until time rolled to tomorrow when it has
already passed today.

The two timed actions need a typed value rather than a search, so fzf search is
`--disabled` and the query becomes a free input field feeding the duration or
HH:MM. The four fixed rows never filter, and selection still moves with the
arrow keys. Input is guarded in two layers. As you type, a `change` binding runs
`transform-query` through the script to strip the value to the charset the
focused row allows, digits with `h` and `m` for a duration, digits and colon for
a time, so a stray key like `y` never lands. A `focus` binding clears the field
when you move rows, since each mode wants a different format. The dim gray format
hints in parentheses are also re-rendered on `focus`, dark on the focused row so
they read like normal highlighted text on the green bar rather than staying gray,
because fzf keeps an ANSI foreground even on the current line. The focus handler
emits a `reload` that recolors plus a `pos()` computed from the row index, since
`reload` otherwise resets the cursor to the top. On enter the whole
value is validated for a real format, and an invalid one like `12:45` for a
duration writes a message that the header shows as a red INVALID line, leaving
the bad input in place to fix. A valid apply clears the input. Enter is bound to
fzf's `transform` action so the script decides the follow-up actions, clear and
reload on success or just a header refresh on failure. The invalid message lives
in a second temp file next to the state file and is cleared on the next
keystroke, on a successful apply, and when the popup opens. `q` is bound to abort
because the restricted charset never needs it, alongside `ctrl-c` and `ctrl-d`.

## Popup apps and the nested session approach

tmux `display-popup` does not support `allow-passthrough` because popups have no real pane. Apps like yazi that send passthrough escape sequences crash (tmux issue 4329, yazi issue 2308). lf is the configured explorer because it does not need passthrough, which is a real constraint on any adapter written for the explorer contract above.

Popups also cannot nest by default. A second `display-popup` from within a popup targets the outer client. The workaround is to run a nested tmux session (`~files`) inside the popup. The nested session creates a real pane, which allows sub-commands to open their own popups. lf's sub-commands (bat, nvim, copy, trash, fzf find, tags, help) all use this to show popups overlaying lf, which is why its adapter answers yes to `explorer_needs_nested_session`. The session name and the wrapping both live in `explorer.sh`, since they are tmux mechanism rather than explorer knowledge.

Lazygit runs in a plain popup without a nested session because it does not need passthrough or sub-popups.

The recent repos picker (`G`) needs two popups of different sizes, a small fzf picker followed by a full size lazygit. The binding uses `run-shell -b` instead of `display-popup -E` so the script runs outside any popup. fzf opens its own small popup via `fzf --tmux center,60%,50%`, and after fzf exits the script calls `tmux display-popup -w 90% -h 90% -E lazygit` so lazygit gets the same size as `prefix+g`. Chaining popups from inside a popup would fail because tmux refuses to open a second popup while one is already on screen.

## Passthrough

`allow-passthrough` is set to `all` (not `on`). The `all` setting enables passthrough from any pane, not just the active one. The `update-environment` entries for `TERM` and `TERM_PROGRAM` ensure these variables are refreshed when attaching to an existing session from a different terminal.

Changing `allow-passthrough` requires a full tmux server restart (`tmux kill-server && tmux`), not just a config reload.

## Escape time

`escape-time` is set to 0 (overriding tmux-sensible's default of 10ms). This eliminates tmux's delay when processing the Escape key, which matters for nested popups where the delay would compound across layers.

## Status bar

The bar itself never takes a background. State is said on the current entry instead, which is the one item the eye is already on, so the answer to "am I in prefix" lands in the same place as the answer to "which window am I on". A whole bar changing colour said it far louder than it needed saying, and it cost every other foreground on the line its own colour, since nothing stays readable on green.

The current entry on both rows is a filled block rather than coloured text between angle brackets. One background colour carries the index and the name together, with a space of padding at each end. It is grey normally, green under prefix, and yellow in copy mode, with black text on either signal colour. Prefix takes priority over copy mode, so pressing prefix while already in copy mode shows green rather than staying stuck on yellow. Everything else on the line stays plain white through all three states, and there is deliberately no grey tier between entries.

The last used entry on both rows is underlined. It was a leading dash until then, one dim character in a row already full of colons and digits, which read as punctuation rather than as a mark. A rule is the width of the name it belongs to, costs no column, and needs no colour of its own, so it stays out of the way of the block's three states. On the window row the underline is written inline in `window-status-format` rather than through `window-status-last-style`, because that style covers the whole entry including the padding space at each end, and the last window is very often the one sitting right beside the current one, so the rule would run straight into the block's edge with no gap.

Rounded Nerd Font caps, `U+E0B6` and `U+E0B4`, were tried on the ends and dropped. A half disc inks only half of the cell it occupies, so the leftover half read as slack beside the block and no format tuning reaches it. `window-status-separator` is emptied and the gap between entries moved into `window-status-format`, so the block's own padding is the only space touching it.

Three options carry all of this. `@pill_hot` is true whenever the block has taken a signal colour, which is exactly when its text must go black. `@pill_bg` holds the three way colour choice and `@pill_fg` the readability rule that follows from it, so the two formats that draw a block name a colour and never repeat the conditional. `@pill_grey` holds the resting colour on its own line, since `@pill_bg` is a format now and a literal buried in a false branch is harder to find. Read any of them back with `#{E:...}`, since an option value is otherwise handed over literally. Holding a colour in an option is also what keeps it safe, because a tmux colour is written with a leading hash and a hash is the character that opens every format token, so an inline value would put a live token opener against the digits of a colour.

`status-left` is a plain white `W` label rather than the session name it used to hold. The session row below names every session including the current one, so printing it on the left as well said nothing. It is styled through `status-left-style` rather than an inline tag, because row 0's default format truncates `status-left` to `status-left-length` and a style tag inside the value would eat that budget.

The current entry on both rows is a pill rather than coloured text between angle brackets. One background colour carries the index and the name together, and a rounded Nerd Font cap closes each end, `U+E0B6` on the left and `U+E0B4` on the right. Both caps are the pill colour on `bg=default`, so the round edge is the pill body bleeding into whatever the bar itself currently is, which is what keeps the shape correct when the bar turns green or yellow with no state conditional of its own. The pill keeps its grey through all three states, because the whole bar changing colour already says which state you are in and a second signal on the same item would say it twice.

A cap is a half disc, so it inks only half of the cell it occupies and always leaves half a cell of bar showing past the round edge. That half cell is fixed and cannot be reclaimed, which is why `window-status-separator` is emptied and the gap between entries moved into `window-status-format` instead, so the pill is not paying for a list separator on top of the half cell it already owes.

The two colours live in `@pill_bg` and `@pill_fg`, and that is not only tidiness. A tmux colour is written with a leading hash, and a hash is the character that opens every format token, so writing the value inline puts a live token opener against the digits of a colour. Holding it in an option and reading it back with `#{E:...}` expands the value exactly once, after which nothing parses those characters again.

Copy mode state is tracked via a global `@copy_mode` variable propagated through hooks because `pane_in_mode` only works for the evaluated pane. Non-active windows cannot see whether the active pane is in copy mode, so the hooks set a global flag on mode change, pane focus, window change, and session change.

## Session strip, the second status row

`status` is set to 2, which gives the bar two rows. Row 0 is left entirely at its
default so every window list setting above it keeps working untouched, and only
`status-format[1]` is written. That row lists every session with the number that jumps
to it, behind a plain white `S` label that pairs with the `W` on row 0. The two labels start
both lists at the same column and stop either row being mistaken for the other. The far
right reads `⌥1-9` rather than naming the row again, because the label already says what
this is and the question in the moment is which key to press.

Sessions are marked the way windows are marked on the row above, minus a grey tier.
The current one wears the same block in the same colours, handed to `--render` as two
more arguments rather than read back with two more `show-option` forks the redraw would
have to wait on. That the colours arrive as text is also what makes the block turn
green the moment prefix is pressed, since the argument changing rewrites the command
line, so tmux reruns the job instead of serving the cached grey one. The one `prefix+e` (or
`M-p`/`M-n`) goes back to is underlined, read straight from
`client_last_session`, so the key shows where it lands before you press it. Every
other session renders in the same plain white, since there is no grey on this bar to
spend on a third tier. The underline is what used to be dim-vs-white's job, carrying it
alone now.

It replaced a leading dash, which was one dim character in a row already full of colons
and digits and read as punctuation rather than as a mark. A rule is the width of the
name it belongs to, which is what makes it findable without hunting, and it costs no
column, so the row no longer shifts sideways when the previous session changes. The
window row above is marked the same way for the same reason, so one shape means last
used on both rows.

### Why the rows are ordered this way

Content, then windows, then sessions, reading down. Distance from the content matches
nesting depth, since content sits in a window and that window sits in a session, so
reading downward walks outward through the containers one layer at a time. It is the
same relationship a browser tab strip has with its page. Putting sessions in the middle
would place the outer container between the content and its own tabs.

That reasoning depends on the bar being at the bottom. Moving `status-position` to top
inverts the correct order to sessions, then windows, then content, for the same reason.

Clicking a session switches to it, the same as clicking a window on the row above, and
that needed no new binding. Each entry is wrapped in a `range=session` marker, and the
default `MouseDown1Status` is already `switch-client -t =`, so a session range simply
hands it the session as its target. The range takes a session id rather than a name,
which is also what makes it safe, since `range=user` caps its argument at 15 bytes and
a longer session name would not survive. The separating space sits outside each range so
the gap between two entries is not clickable.

Windows already answered half of this. `prefix` plus a bare number is a tmux default and
selects a window, which works here because `base-index` is 1 and `renumber-windows` is
on, so the numbers on row 0 stay dense and match the keys. Sessions needed building,
because a session has a name and no index of its own.

`~/.tmux/scripts/session-index.sh` is the one place that decides which number a session
holds. It has five subcommands, `--ensure`, `--compact`, `--move left|right <session>`,
`--switch N [client]`, and `--render <current> <last> <muted> <gen>`. All five go
through the same stored value rather than deriving the order twice, which is the whole
point, since a strip and a key that each sort their own list are free to disagree. The
number is stored on the session as the `@sidx` option.

The strip's body is drawn by `--render`, not by tmux's native `#{S:}` loop, and that
took a wrong turn to learn. `#{S:}` can only sort by index, name, or activity time,
none of which is `@sidx`, and tmux has no `swap-session` to give a session a movable
position the way `swap-window` gives a window one. So a first pass kept `#{S:}` for
the body and let `M-P`/`M-N` change only the number next to a session, which is exactly
where the bug this section used to warn about lived: the number moved, the row's actual
left-to-right position could not, because that position was tmux's fixed name order and
nothing in the format language can reorder a loop by a custom option. A session moved
with the number said one thing while the strip still said another, the same failure
mode the opening paragraph of this file warns a strip and a key can fall into if they
derive an order twice instead of reading one. `--render` is the fix: it lists sessions,
sorts them by `@sidx` itself, and prints the whole coloured, clickable row as text,
so position finally means what the number says.

That fix costs the thing the row used to avoid, a shell call in the redraw path. tmux
caches a `#()` job's output and will not re-run it more than once a second, which would
let a move sit behind a stale render for up to a second if nothing forced a fresh run.
Two things close that gap. `bump_gen` in the script increments a `@sidx_gen` counter on
every write, and `--render` is always called with it as a trailing argument it never
reads, purely so the exact shell command text differs after every write and tmux has no
cached result to reuse. `current`, `last`, and the two block colours are resolved
client side and passed in as the other four arguments (`#{client_session}`,
`#{client_last_session}`, `#{E:@pill_bg}`, `#{E:@pill_fg}`), because the job's output is
one cached string shared by every attached client, and a client's own session and
prefix or copy-mode state are the things that still have to vary per client. `#[range=...]` and `#[fg=...]` in the script's output are
honoured exactly as if written directly in the format string, since those are
screen-writing tags applied to the fully expanded line, not format tokens `#()`
substitution would need to re-expand.

The order is manual and persistent, the same shape tmux already uses for window
indices, chosen over always re-deriving from the name because `M-N`/`M-P` need a
position that actually stays where it's put. `--ensure` seeds the whole list by name,
byte order, the one time nothing has a position yet, and after that only ever fills in
a position that's missing, appending after the current highest rather than resorting
everyone, which is what makes it safe to run on `session-created`. `--compact` runs on
`session-closed` and renumbers the survivors to 1..N in their existing relative order,
closing the hole a dead session leaves without touching anyone's place in line.
`--move` swaps a session's position with whichever session sits one slot to its left or
right, the session-strip equivalent of `swap-window`, and is what `M-P`/`M-N` call.
Renaming a session touches none of this, since the order no longer comes from a name,
so there is no `after-rename-session` hook. Every mutation ends with `refresh-client
-S`, since setting a session option changes nothing on screen by itself. A `run-shell`
at the end of `.tmux.conf` calls `--ensure` on whatever is already running, because the
hooks only see changes from that point on.

That bookkeeping is the honest cost of numbering things with no index, and it is why
the fzf switcher on `prefix+s` is still the right tool for a session you reach rarely.
The strip, and now the move keys, are for the handful you live in and want to arrange.

The jump bindings pass `#{client_name}` to the script rather than letting tmux pick.
They run through `run-shell -b` so the key never blocks, and a backgrounded
`switch-client` with no client chosen moves the most recently used one, which is the
wrong terminal as soon as two are attached. `run-shell` expands formats in its command,
which is what makes passing the client possible at all.

Numbers past 9 are still stamped and still shown, they just have no key.

## Plugins

Managed through TPM. Resurrect and continuum handle session persistence. tmux-fzf provides additional management via `m`.

Plugin bindings are re-bound after TPM initialization with `-N` descriptions so they appear in the `?` cheat sheet. This is necessary because TPM sets up bindings without descriptions.

## Declared dependencies

This module needs a long list of tools on the machine and installs none of them.
`DEPENDENCIES` at the package root is the whole contract upward, and the repository
root `CLAUDE.md` explains the format and who acts on it. Adding a tool to a script
means adding a line there, and nothing in this module ever mentions Homebrew.

Two entries are worth knowing about. `tpm` is declared with the `package` kind rather
than `path` because it ships no command, only a script inside its package, which is
why `.tmux.conf` loads it through `brew --prefix tpm`. That call is the one place this
module names a package manager, and it stays because there is no portable way to find
a file inside a package without asking the package manager where the package is. The
preview tools, `bat`, `eza`, and `chafa`, are optional because a missing one only
breaks the preview pane of a picker that otherwise works, so the pane shows a shell
error rather than the picker refusing to open.

The mullvad adapter names the CLI rather than pathing to it, and keeps the `MULLVAD`
environment override so the adapter contract can be exercised against a stub.
