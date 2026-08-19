# TmuxSessions

Lists every tmux window across every session as one flat list, each row titled by
the window and subtitled by the session holding it, so several sessions each
keeping a plain zsh window still read apart. Typing matches either name, or both
at once a word at a time in any order, so vic zsh finds the zsh window inside
vicert. Choosing a row jumps straight to that window.

The last row is a settings door leading to a second level, which names the
terminal a fresh attach opens into. Both levels share one list, so stepping in and
back never flickers a close and reopen.

Opens on Hyper and U, appears in the launcher under Tools, and can be searched
without leaving the launcher by typing u or tmux.

It needs tmux itself, and without it the tool cannot list or switch anything,
which is the whole reason it exists. Opening a fresh terminal already attached to
a session also wants the system launcher, and without that only the switching
inside an existing terminal still works.
