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
13. Switch to previous session (`(`)
14. Switch to next session (`)`)
15. Previous window (`p`)
16. Next window (`n`)
17. Previous pane (`O`)
18. Next pane (`o`)
19. Swap window left (`P`)
20. Swap window right (`N`)
21. Select pane left (`h`)
22. Select pane down (`j`)
23. Select pane up (`k`)
24. Select pane right (`l`)
25. Resize pane left (`H`)
26. Resize pane down (`J`)
27. Resize pane up (`K`)
28. Resize pane right (`L`)
29. Zoom/unzoom pane (`z`)
30. Split pane horizontally (`"`)
31. Split pane vertically (`%`)
32. New window (`c`)
33. Show all keybindings (`?`)
34. Scratch shell popup (`` ` ``)
35. Search explorer tags (`t`)
36. Find files globally (`f`)
37. Find files in pane working dir (`F`)

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

Changes color based on state. Green background when prefix is active, yellow when in copy mode, transparent otherwise.

Two options name what that implies, so the rest of the bar states each idea once instead of repeating the same nested conditional. `@bar_muted` is true whenever the bar has taken a background colour, which is exactly when every foreground on it must go black to stay readable. `@bar_dim` is the quiet grey for chrome and for anything the eye should skip past. It is written as `colour246` rather than the `#949494` it equals, because a hex value loses its leading `#` when read back through a second expansion, and that grey is the same one the fzf popups use for their borders and headers. Read either option back with `#{E:...}`, since an option value is otherwise handed over literally.

`status-left` is a dim `W` label rather than the session name it used to hold. The session row below names every session including the current one, so printing it on the left as well said nothing. It is styled through `status-left-style` rather than an inline tag, because row 0's default format truncates `status-left` to `status-left-length` and a style tag inside the value would eat that budget.

Copy mode state is tracked via a global `@copy_mode` variable propagated through hooks because `pane_in_mode` only works for the evaluated pane. Non-active windows cannot see whether the active pane is in copy mode, so the hooks set a global flag on mode change, pane focus, window change, and session change.

## Session strip, the second status row

`status` is set to 2, which gives the bar two rows. Row 0 is left entirely at its
default so every window list setting above it keeps working untouched, and only
`status-format[1]` is written. That row lists every session with the number that jumps
to it, behind a dim `S` label that pairs with the `W` on row 0. The two labels start
both lists at the same column and stop either row being mistaken for the other. The far
right reads `⌥1-9` rather than naming the row again, because the label already says what
this is and the question in the moment is which key to press.

Sessions are marked the way windows are marked on the row above. The current one is
wrapped in angle brackets and green. The one `prefix+e` goes back to carries a leading
dash and is white, read straight from `client_last_session`, so the key shows where it
lands before you press it. Every other session is dim.

Those three levels of emphasis are doing real work rather than decoration. Windows and
sessions both render in an identical `N:name` shape, so brightness is the only thing
stopping the two rows reading as one list of ten items. The dim also settles which row
the eye lands on first, and that should be the window row, since windows are what get
switched constantly while the session row is glanced at.

The dash costs a column, so the row shifts by one character when the previous session
changes. The window row above already behaves that way, so it is consistent rather than
surprising.

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
holds. It has two subcommands, `--renumber` stamps the numbers and `--switch N [client]`
jumps. Both go through the same stored value rather than deriving the order twice, which
is the whole point, since a strip and a key that each sort their own list are free to
disagree. The number is stored on the session as the `@sidx` option, and that choice is
what keeps the row cheap, because a tmux format reads a session option directly and the
row never shells out on a redraw. A `#()` shell call in the format would have worked too
and would have cost a poll interval of staleness on every session change.

Order is by name in byte order, chosen over most recently used because a number worth
learning has to hold still. It still moves when a session is created, killed, or renamed,
which is why three hooks restamp, `session-created`, `session-closed`, and
`after-rename-session`. Rename counts because the order is by name. Renumbering ends with
`refresh-client -S`, since setting a session option changes nothing on screen by itself.
A `run-shell` at the end of `.tmux.conf` stamps whatever is already running, because the
hooks only see changes from that point on.

That churn is the honest cost of numbering things with no index, and it is why the fzf
switcher on `prefix+s` is still the right tool for a session you reach rarely. The strip
is for the handful you live in.

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
