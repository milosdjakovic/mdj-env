# lf

Status. lf runs every picker, preview and confirmation as its own `${{ }}` shell command, so it depends on no multiplexer and works the same in Rex, herdr, tmux or a bare terminal.

## Now

`dotfiles/lf/.config/lf/lfrc` runs bat, nvim, the copy menu, trash confirmation, both fzf finds,
both tag browsers and help as `${{ }}` commands. Copying is three background commands,
`copy-path`, `copy-name` and `copy-dir`, on `cp`, `cn` and `cd` and found by name with `:` and tab. lf pauses, the program takes the whole screen,
and lf comes back when it exits. Results return through a temp file or `lf -remote` as they did
before. tmux still wraps lf in its nested `~files` session, now only so `prefix+b` resumes lf
where it was left.

## Rejected

- 2026-11-02 12:50, keeping `tmux display-popup` and adding a helper that picks the popup by
  multiplexer, a tmux popup under tmux, a Rex float under Rex. It keeps lf visible behind each
  picker, but it ties lf to every multiplexer it runs in and needs a backend per multiplexer,
  and the point of Rex is not needing another one. lf's own shell command needs none.

## Log

- 2026-11-02 12:50, all nine `tmux display-popup` commands in `lfrc` became `${{ }}` commands,
  and `edit-popup` became `edit`. Driven in a throwaway Rex session with no tmux, `i` paged a file
  in bat and `q` returned to lf, `c` then `n` copied a name and lf echoed it, `F` with a pick moved
  lf to the chosen file and `-` went back, `D` then `n` trashed nothing, and `?` and `T` opened
  and escape closed them. tmux was dropped from the module's dependencies.
- 2026-11-02 13:15, the copy menu script gave way to three lf commands run in the background, on
  the key sequences `cp`, `cn` and `cd`, and tab on the `:` line became `cmd-menu-complete` so a
  command can be found by name. `y` was left alone, since it is lf's own copy of files for pasting
  and making it a prefix would make it wait for a second key.
- 2026-11-02 13:30, `?` now lists every key lf has, its defaults from `lf -remote "query $id maps"` as well as
  ours, with our descriptions where a map line has one and the command dimmed otherwise, and enter
  presses the key with `push`. It used to list only the 14 keys `lfrc` described.
