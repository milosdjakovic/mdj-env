# lf Configuration

Terminal file manager configuration in `dotfiles/lf/.config/lf/`. Stow symlinks to `~/.config/lf/`.

## Why lf instead of yazi

Yazi sends passthrough escape sequences at startup to detect terminal capabilities. tmux `display-popup` does not support `allow-passthrough` because popups have no real pane backing them. Yazi times out and crashes. lf does not do terminal capability detection so it works directly in a popup.

## Nested tmux session for popup nesting

lf runs inside a nested tmux session (`~files`) created by the tmux binding. This gives lf a real pane, which allows sub-commands to open their own tmux popups via `&{{ tmux display-popup }}`. Without the nested session, popups from within a popup target the outer client instead.

All interactive sub-commands (bat preview, nvim edit, copy menu, trash confirmation, fzf find, tag browser, help) use `&{{ tmux display-popup }}` so lf stays visible behind the popup.

The `&{{ }}` command type runs in the background without suspending lf. This is essential for the popup approach. Using `${{ }}` would suspend lf and clear the screen.

## Keybindings with descriptions

Every `map` line with a `# description` comment is picked up by the `?` help command. The help parser greps for this pattern and extracts the key and description. Follow this pattern when adding new bindings.

## Tags

Tags persist across sessions and directories. `U` clears selections and cut/copy marks but preserves tags. Tag management lives in the `T` popup (tag-browser.sh) which supports removing individual tags with ctrl-d and removing all visible tags with ctrl-x (with confirmation). Tag removal is scope-aware, respecting the current dir / all filter.

## fzf find has two independent filters

The `F` binding opens fzf with two toggleable dimensions. Scope (current dir / global) and type (all / dirs / files). Each can be changed independently. The active option shows in brackets, inactive ones show their shortcut. Uses `become()` for state transitions, same pattern as the tmux scoped fzf switchers.

## Escape responsiveness in fzf popups

fzf has a hardcoded ~100ms delay on Escape to distinguish it from escape sequences (arrow keys, etc). This is unavoidable. tmux escape-time is set to 0 to prevent additional delay. Scripts send results directly to lf via `lf -remote` instead of writing temp files, eliminating post-processing overhead after the popup closes.

## Previous directory tracking

lf has no built-in previous directory feature. The `on-cd` hook saves the current directory to a temp file. The `-` binding navigates to the previous directory. Temp files use lf's instance id to avoid conflicts between multiple instances.

## Declared dependencies

This module needs tools on the machine and installs none of them. `DEPENDENCIES` at
the package root is the whole contract upward, and the repository root `CLAUDE.md`
explains the format and who acts on it.

Worth noting that tmux is a required dependency here, not an optional one. Every
preview, confirmation, and picker in `lfrc` opens as a `tmux display-popup`, so this
module does not work standalone in a bare terminal. That is a deliberate consequence
of the popup approach documented above, not an oversight.
