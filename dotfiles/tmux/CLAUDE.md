# Tmux Configuration

Configuration lives in `dotfiles/tmux/.tmux.conf` with helper scripts in `dotfiles/tmux/.tmux/scripts/`. Stow symlinks everything to `~/.tmux.conf` and `~/.tmux/scripts/`.

Prefix is `Alt-z` with `Alt-Z` as secondary for caps lock tolerance.

## Binding conventions

Every custom prefix binding must include `-N "description"` so it appears in `tmux list-keys -N`. The `?` binding shows a searchable cheat sheet of all noted bindings via fzf.

## Priority system

`tmux list-keys` outputs bindings alphabetically by key, which scatters the most used bindings among navigation and resize keys. The `[p:N]` priority tag controls visual order in the `?` cheat sheet so the most important bindings appear at the top regardless of which key they are bound to.

Custom bindings use a `[p:N]` prefix in their `-N` note, for example `-N "[p:1] Tmux actions (tmux-fzf)"`. The cheat sheet sorts prioritized bindings by N first, then appends unprioritized bindings. The `[p:N]` tag is stripped before display using sed so the user only sees the clean description.

When adding a new binding, pick a priority number that places it in the right group. Do not duplicate priority numbers. The current assignments are listed below.

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
10. Sessions tree view (`S`)
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
35. Search lf tags, copy path (`t`)
36. Find files globally, copy path (`f`)
37. Find files, copy path (`F`)

Plugin bindings (tpm, yank, resurrect, sensible) do not use priority tags and appear after all prioritized bindings.

## FZF switchers

Sessions (`s`) use fzf in a `display-popup`, sorting by last used and excluding the current session. `S` opens the native tmux tree view.

## FZF search popups

Tags (`t`), files (`f`), and files globally (`F`) open fzf in a popup and copy the selected path to clipboard on Enter. Tags reads from lf's tags file. File search uses fd with process substitution (via `~/.tmux/scripts/fzf-files.sh`) so fzf exits instantly without waiting for fd to finish traversing.

## FZF launcher (command palette)

`prefix+Space` opens a command palette showing all available tools and actions. The launcher script lives at `~/.tmux/scripts/fzf-launcher.sh`.

Entries are defined in a pipe-delimited data section at the top of the script. Each line has four fields: `category|display_key|description|command_id`. The display key is what the user sees (e.g. `prefix+g`), or `---` if no direct binding exists. The command ID maps to a case in the `execute_cmd` function which handles the actual tmux command. This separation avoids quoting issues with complex tmux commands in the data section.

To add a new entry, add a line to the `ENTRIES` variable with the correct category, key, description, and a new command ID, then add a matching case to `execute_cmd`.

Categories are toggled via keyboard shortcuts in the fzf header, using the same `become()` pattern as the scoped fzf switchers and lf fzf-find. The active category shows in brackets. Available categories are `tools` (popup apps like lazygit, lf, scratch shell, tag/file search), `nav` (session switcher and tree view), and `tmux` (session management, config reload, plugin operations). The default view shows all.

The pane's working directory is passed as `$PANE_PATH` from the `.tmux.conf` binding since `#{pane_current_path}` does not resolve inside a popup. Commands that need a working directory (lazygit, lf, scratch) use this variable.

## Popup apps and the nested session approach

tmux `display-popup` does not support `allow-passthrough` because popups have no real pane. Apps like yazi that send passthrough escape sequences crash (tmux issue 4329, yazi issue 2308). lf is used instead because it does not need passthrough.

Popups also cannot nest by default. A second `display-popup` from within a popup targets the outer client. The workaround is to run a nested tmux session (`~files`) inside the popup. The nested session creates a real pane, which allows sub-commands to open their own popups. lf's sub-commands (bat, nvim, copy, trash, fzf find, tags, help) all use this to show popups overlaying lf.

Lazygit runs in a plain popup without a nested session because it does not need passthrough or sub-popups.

## Passthrough

`allow-passthrough` is set to `all` (not `on`). The `all` setting enables passthrough from any pane, not just the active one. The `update-environment` entries for `TERM` and `TERM_PROGRAM` ensure these variables are refreshed when attaching to an existing session from a different terminal.

Changing `allow-passthrough` requires a full tmux server restart (`tmux kill-server && tmux`), not just a config reload.

## Escape time

`escape-time` is set to 0 (overriding tmux-sensible's default of 10ms). This eliminates tmux's delay when processing the Escape key, which matters for nested popups where the delay would compound across layers.

## Status bar

Changes color based on state. Green background when prefix is active, yellow when in copy mode, transparent otherwise.

Copy mode state is tracked via a global `@copy_mode` variable propagated through hooks because `pane_in_mode` only works for the evaluated pane. Non-active windows cannot see whether the active pane is in copy mode, so the hooks set a global flag on mode change, pane focus, window change, and session change.

## Plugins

Managed through TPM. Resurrect and continuum handle session persistence. tmux-fzf provides additional management via `m`.

Plugin bindings are re-bound after TPM initialization with `-N` descriptions so they appear in the `?` cheat sheet. This is necessary because TPM sets up bindings without descriptions.
