# Tmux Scoped FZF Switchers

Adds dynamic scope filtering to the existing fzf window and pane switchers. Instead of always searching globally, users can toggle the scope within fzf using keyboard shortcuts. The action hints update contextually based on the current filter state.

## Files

- `dotfiles/tmux/.tmux/scripts/fzf-windows.sh` for the window switcher
- `dotfiles/tmux/.tmux/scripts/fzf-panes.sh` for the pane switcher
- `dotfiles/tmux/.tmux.conf` updated binds for `w` and `f`

The session switcher (`s`) stays unchanged since it is already flat and does not need scoping.

## Window Switcher (prefix + w)

Opens fzf showing all windows across all sessions sorted by last used, excluding the current window. The header shows the active filter and available actions update contextually.

### States and transitions

**All windows (default).** Header shows `Filter: all`. Actions shown: `ctrl-s this session | ctrl-e pick session`.

**Current session.** Header shows `Filter: session <name>`. Actions shown: `ctrl-a all sessions | ctrl-e pick session`.

**Picked session.** Header shows `Filter: session <name>`. Actions shown: `ctrl-s this session | ctrl-a all sessions | ctrl-e pick session`.

### Pick session flow

When the user presses `ctrl-e`, fzf reloads its list to show sessions instead of windows. The user picks a session and the script relaunches with the window list filtered to that session. This uses fzf's `become()` to relaunch the script with the selected session as an argument.

### Keyboard shortcuts

- `ctrl-s` scope to current session
- `ctrl-a` show all (reset filter)
- `ctrl-e` pick a session from a list
- `enter` switch to selected window

## Pane Switcher (prefix + f)

Same pattern as the window switcher but with two filter dimensions. Session filtering works identically. Window filtering layers on top and respects the active session filter.

### States and transitions

**All panes (default).** Header shows `Filter: all`. Actions shown: `ctrl-s this session | ctrl-e pick session | ctrl-w this window | ctrl-f pick window`.

**Filtered by session.** Header shows `Filter: session <name>`. Actions shown: `ctrl-a all sessions | ctrl-e pick session | ctrl-w this window | ctrl-f pick window`.

**Filtered by window.** Header shows `Filter: session <name> > window <name>` (or `Filter: all > window <name>` if no session filter). Actions shown: whatever session actions apply + `ctrl-a all windows | ctrl-f pick window`.

### Window pool respects session filter

When picking a window, the list of available windows is scoped to the active session filter. If all sessions are shown, all windows appear. If a session is selected, only that session's windows appear.

### Keyboard shortcuts

- `ctrl-s` scope to current session
- `ctrl-a` show all (reset all filters)
- `ctrl-e` pick a session from a list
- `ctrl-w` scope to current window
- `ctrl-f` pick a window from a list
- `enter` switch to selected pane

## tmux.conf changes

The `w` and `f` binds simplify to script calls.

```
bind -N "[p:7] Windows (fzf switcher)" w display-popup -w 80 -h 70% -E "~/.tmux/scripts/fzf-windows.sh"
bind -N "[p:8] Panes (fzf switcher)" f display-popup -w 80 -h 70% -E "~/.tmux/scripts/fzf-panes.sh"
```

## Implementation details

Each script accepts optional arguments to set the initial filter state. This is how `become()` relaunches with a filter applied after picking a session or window.

```
fzf-windows.sh [--session <name>]
fzf-panes.sh [--session <name>] [--window <session:index>]
```

The scripts use fzf features for dynamic behavior.

- `reload(...)` to refresh the list when toggling scope
- `change-header(...)` to update the filter indicator and available actions
- `become(...)` to relaunch the script after picking a session or window from the selection list

Action hints appear in the fzf header so users always know what keys are available.

## What stays the same

- Sort order by last used
- Current item excluded from results
- `enter` to switch
- Uppercase variants (`S`, `W`, `F`) still open native tmux tree views
- Session switcher (`s`) unchanged
