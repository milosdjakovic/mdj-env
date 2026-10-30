# TmuxSessions

Lists every tmux window across every session as one flat list, each row titled by
the window and subtitled by the session holding it, so several sessions each
keeping a plain zsh window still read apart. Typing matches either name, or both
at once a word at a time in any order, so vic zsh finds the zsh window inside
vicert. Choosing a row jumps straight to that window.

Terminal in the action panel names the terminal a fresh attach opens into, the
one in force marked and any this machine lacks dimmed.

Opens on Hyper and U, appears in the launcher under Tools, and can be searched
without leaving the launcher by typing u or tmux.

It needs tmux itself, and without it the tool cannot list or switch anything,
which is the whole reason it exists. Opening a fresh terminal already attached to
a session also wants the system launcher, and without that only the switching
inside an existing terminal still works.
