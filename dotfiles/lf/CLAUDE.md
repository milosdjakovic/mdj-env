# lf Configuration

Terminal file manager configuration in `dotfiles/lf/.config/lf/`. Stow symlinks to `~/.config/lf/`.

## Why lf instead of yazi

Yazi sends passthrough escape sequences at startup to detect terminal capabilities (image protocol, cell size, light/dark mode). tmux `display-popup` does not support `allow-passthrough` because popups have no real pane backing them. This means yazi times out waiting for a response and crashes with "Terminal response timeout". A nested tmux session workaround exists but adds complexity. lf does not do terminal capability detection so it works directly in a plain `display-popup`. The yazi binding is kept commented out in tmux.conf for reference.

## tmux popup nesting limitation

lf runs inside a tmux `display-popup`. Commands inside lf cannot open additional tmux popups because tmux only supports one popup per client. Opening a second popup replaces the first, and when the inner popup closes, lf's popup is also gone. This is why all sub-commands (bat preview, nvim edit, fzf find, trash confirmation) run directly in lf's terminal instead of in popups.

## lf command types and when to use each

`${{ }}` suspends lf, clears the screen, and gives the terminal to the command. Use for interactive full-screen tools like bat, nvim, fzf, and the trash confirmation screen. lf resumes when the command exits.

`&{{ }}` runs the command in the background without suspending lf. Use for quick actions that only send messages back to lf via `lf -remote`, like copy-to-clipboard and go-to-previous-directory. Using `${{ }}` for these causes a visible screen flash.

`%{{ }}` runs a pipe command at the bottom of lf's screen. Can display output and read input but requires pressing enter to interact. Not suitable for single-keypress prompts.

## Keybindings with descriptions

Every `map` line that has a `# description` comment is picked up by the `?` help command. The help parser uses `grep '^map .* # '` to find described bindings, extracts the key and everything after `#` as the description. When adding new bindings, follow this pattern to have them appear in the help screen.

The `c` prefix is used for copy actions (`cp` path, `cn` name, `cq` cancel). lf natively waits for the second key and shows a built-in table of available sub-keys. This table cannot be customized visually.

## Trash uses macOS trash command

The `D` binding uses the `trash` CLI (Homebrew) instead of `rm`. Files go to macOS Trash and can be recovered from Finder. The confirmation screen is a custom full-screen UI built with tput that shows a header with the item summary, a divider, and the list of items to be trashed. It handles single files, single directories, and mixed multi-selections with appropriate messaging.

## Preview guards

The `i` (preview) command only opens bat for text-based files. It checks the MIME type and silently ignores directories and binary files, showing a dismissable message in the status line instead. Messages auto-clear after 3 seconds.

## Previous directory tracking

lf has no built-in "go to previous directory" feature. The `on-cd` hook saves the current directory to a temp file on every directory change. The `-` binding reads the previous directory from that file and navigates to it. The temp files use lf's instance id (`$id`) to avoid conflicts between multiple lf instances.

## Recursive find with scope toggling

The `F` binding opens fzf with all files and directories from the current location downward (using `fd`). Inside fzf, `^d` filters to directories only, `^f` to files only, `^a` resets to all. This uses fzf's `become()` to relaunch the script with different arguments, the same pattern used in the tmux scoped fzf switchers. Selecting a directory navigates into it. Selecting a file navigates to its location and highlights it.
