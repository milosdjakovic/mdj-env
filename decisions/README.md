# Decisions

What was decided here, what was tried and turned down, what was believed wrongly and when
that was found out. One file per topic, each carrying its own dated history.

## Why this exists beside the commit log and CLAUDE.md

Three records live in this repository and each answers a different question. A commit says
what changed and why, at the moment it changed. CLAUDE.md says what is true now and the
reasoning a person needs to work in a module today. Neither answers the question that costs
the most time, which is what has already been tried here and why it was turned down, because
a rejected approach never reaches a commit and a current truth file has no room for the
history behind it.

That is what this directory holds. It records the approaches that were tried and never
committed, the beliefs that were held and later corrected, and the order in which all of it
happened. The herdr agent detection entry is the reason it was started. In one evening an
integration was installed on a reasonable guess and permanently broke a pane, a CLI was
declared broken on a misread exit code and a workaround was built and documented around it,
and two confident suggestions arrived from elsewhere describing configuration options that do
not exist. None of that reached git. All of it would have been tried again.

## The contract for a file

Every file here has these four parts, in this order.

**Status.** One line under the title. The current stance, so a reader who reads nothing else
knows where the topic stands.

**Now.** What is true today, in a few sentences. This is the only section that is rewritten,
and only when an entry in the log below justifies the rewrite. It should agree with the module
CLAUDE.md, and when the two disagree that disagreement is itself a defect to fix rather than a
choice to make.

**Rejected.** Every approach considered here and turned down, each with the date and the reason.
This is the section to read before proposing anything in the area. An entry never leaves this
list. If a rejected approach later becomes right, it stays listed, gains a note saying it was
reopened and when, and a log entry records why.

**Log.** Dated entries, oldest first, newest last. An entry is written once and never edited,
with one exception. When an entry turns out to be wrong, it keeps its text and gains a single
line at its end, `Corrected <date>, see below`, and a new entry records what was wrong, how it
was found out and what is true instead. Both stay. The wrong belief and the date it was held
are part of the history, and a reader who finds the old entry alone must not be misled by it.

Dates carry the time, local, to the minute, `2026-09-14 22:01`. An estimated time says so, and
is anchored to the nearest commit or file timestamp rather than to a sense of elapsed time,
since the first estimate written here was fifteen minutes out.
Entries that reconstruct history from commits cite the commit hash and take its timestamp.

## When to read and when to write

Read before proposing. Any change in an area that has a file here starts by reading that file,
the Rejected section first. Proposing something listed there without first saying why the
rejection no longer holds is the failure this directory exists to prevent.

Write in the same change that moves behaviour. A decision, a rejection, a bug found, a belief
corrected, each is recorded when it happens rather than afterwards, since afterwards the
reasoning is already gone. A topic with no file gets one the first time it produces a decision
worth keeping. A file that turns out to be wrong is corrected by the procedure above, never
by rewriting.

Keep the index below current. One line per file, the topic and one clause on where it stands.
`check-dependencies.sh` verifies that every file is listed, every listed file exists, and
every file carries the four parts, so a file that drifts from the contract is reported rather
than discovered.

## Index

- [iris](iris.md), the shell autocomplete that was built from a fork for a theme and an alias fix, then removed because a pty proxy hides every session from the herdr agents panel, with the herdr version, the mechanism, the upstream record and how to recheck it
- [theme-palette](theme-palette.md), one palette in theme/, every stowed tool painted from it by a generator that lives with the tool, and the checker proves it across every file
- [fzf-appearance-colour](fzf-appearance-colour.md), slots for everything fzf draws except the selection bar, which a watcher rewrites into a file because it cannot be a slot
- [herdr-finder-keys](herdr-finder-keys.md), the fuzzy search copies a path on `ctrl-y`, and why it is not shift and enter or `ctrl-c`
- [herdr-theme](herdr-theme.md), Aura in herdr's own tokens on both appearances, and the faint agent line that was never a colour
- [ghostty-aura-theme](ghostty-aura-theme.md), how the terminal palette settled on Aura for both halves after three other pairings
- [claude-code-theme](claude-code-theme.md), Claude Code draws hex colours per theme and only `auto` asks the terminal, so setup merges it
- [neovim-lockfile-pin](neovim-lockfile-pin.md), the lockfile is the pin and the bootstrap restores it rather than updating past it
- [olm-workspaces](olm-workspaces.md), window layouts are snapshots a person takes and applies, keyed by display role, after the automatic version was pulled out
- [olm-storage-roots](olm-storage-roots.md), everything Olm writes lives under `~/.olm`, data and cache apart, after five plugins each kept their own path
