# Iris

Running. It was disabled for half a day on 2026-09-16 so the herdr agents panel could see
sessions, and came back the same day. `decisions/shell-autocomplete.md` has both routes.

Why it is built from a fork rather than installed, its two patches, the keys it claims before
the shell ever sees them, and how it follows the terminal's appearance, are all below. The
fork itself is declared at `forks/iris` and `forks/CLAUDE.md` carries the rule that governs
every carried fork. This file is the whole of iris, so the repository `CLAUDE.md` names it
only in the module list.

## The theme, and how to reload it

`theme.toml` is two things in one file. Everything drawn on the page is an ANSI slot written
by hand, `"4"` for the primary accent and `"8"` for the comment grey, because a slot follows
whatever the terminal is painting and Ghostty is painted from the same palette. The `[dark]`
and `[light]` tables at the bottom are generated and must not be edited by hand. They hold
the four keys of the selected row, which a slot cannot carry because a bar has to be a tint
of the page and no slot is dark on one half and light on the other. `theme-map` at this
package root says which key takes which role and why, `theme-emit` beside it rewrites the
span from the `[dark]` header to the end of the file and copies everything above it through.
Run `src/check-theme.sh` after changing a colour or a role, review the regenerated tables,
and commit them. `theme/CLAUDE.md` has the whole contract.

iris reads `theme.toml` once, when it starts, and there is no reload command. A new shell is
the test, so open a new pane after regenerating and look at the selected row there. A pane
that was already open keeps the old tables until its shell is replaced.

The two tables need the fork. Stock iris has one flat set of keys and no idea what the
terminal is painting, and `forks/iris/FORK` is where that patch is declared.

**Running, and it costs the herdr agents panel.** A PTY proxy hides every session behind it
from the panel, so iris was disabled for half a day on 2026-09-16 in favour of fzf-tab with
carapace as its dictionary, and came back the same day because a Tab picker with its own
query row and no history was nowhere near it. fzf-tab and carapace stay underneath as what
Tab does when the iris menu is closed. `decisions/shell-autocomplete.md` carries both
routes, the versions, and the herdr change that would let the panel see through a proxy.

Shell autocomplete, configured in `.config/iris/` under this package and built rather than
installed, because the released binary has two defects this repository does not want to live
with. `src/build-forks.sh` compiles it from `github.com/milosdjakovic/IRIS`, pinned to one
commit, into `~/.local/bin`. Updating means moving the pin, the same ritual as the Neovim
lockfile, so two machines build the same binary.

The fork carries the two fixes on their own branches, each a single commit above upstream so
either can be offered back without being rewritten first.

Staying current is the thing a fork is bad at, so `src/check-forks.sh` keeps asking the
question a fork stops asking. It reports what upstream has released since the pin, reading the
changelog rather than the log because upstream writes one line per thing that changed where the
log writes one per merge, and then it answers for each patch whether vanilla upstream still
needs it. That answer is measured rather than guessed. It lays the branch's own tests onto an
unmodified upstream checkout and runs them there, so a branch whose tests pass on vanilla is
describing behaviour upstream now has and the branch can go, while one that fails or does not
compile is still earning its place. It also rebases each patch onto the new upstream in a
throwaway worktree, so a conflict is known before anyone commits to resolving it.

It reports and changes nothing, the same split `check-dependencies.sh` keeps, because every
answer it gives leads to a decision. Taking an update means rebasing the patches still needed,
merging them into the fork's main, moving `IRIS_COMMIT` and rebuilding. Dropping a patch means
deleting the branch and reverting its merge, not only leaving it unbuilt. If both patches ever
go, the fork goes with them and iris becomes an ordinary tap line again.

The only hand written part is the list of patches at the top of the script. Which test files
prove a patch, and which packages they live in, are read out of the branch itself, so a third
patch is one line and nothing else. Which branch to watch was also worth settling once.
Upstream has a `dev` branch that reads like where new work lands and is not, it forked in May
2026 and carries four commits nobody merged, while every release since has been cut from `main`
through pull requests. The script says so in a comment, so the guess is not made twice.

`fix/alias-display-preserves-typed-command` is upstream issue 158. Iris expands a shell alias
so the target's spec can answer, which it has to do, and then never puts the typed word back,
so with `cd` aliased to zoxide the rows read `z /path`. Ghost text dies from the same cause,
since it only draws when the top result has the literal buffer as a prefix and `z ` never has
`cd ` as one. One bug, two symptoms, and no configuration option touches it. `expand-alias`
governs something else entirely, whether iris rewrites your literal prompt text on space.

`feat/appearance-aware-theme` gives `theme.toml` optional `[dark]` and `[light]` tables over
its flat keys, and asks the terminal which it is in. Stock iris has one flat set of colours
and no idea what is behind them.

The hook `iris init zsh` emits ends in `exec iris`, replacing the shell with one running
behind a PTY proxy. That is why it sits at the very top of the generated `.zshrc` above the
Powerlevel10k instant prompt, and why the PATH line is hoisted above it. Painting a prompt
into a process about to be replaced leaves a screen p10k never gets to tear down. `~/.local/bin`
comes first on that line so the built binary wins over any package manager copy left behind.

Because iris reads every keystroke before the shell does, a key it claims never reaches zle at
all, whether its menu is open or not. That was measured rather than assumed. So `toggle-mode`
is moved to ctrl+o, leaving ctrl+r for atuin, and `navigate-closed` is `shell` so a bare up
arrow reaches atuin too. `atuin-history` is 1, so iris reads atuin's database rather than
keeping a second history of its own. `ghost-text` is 1, so the menu opens as you type and
Shift+Tab toggles it away again when the ghost text alone is enough. Setting it to 2 inverts
that, ghost text only until Shift+Tab asks for the menu, and 0 turns both off.

Holding the tty has one consequence that reaches outside iris entirely. Anything that
identifies a program by reading a pane's foreground process sees iris and never sees what is
running behind it, and herdr's agents panel is exactly that, so a Claude session behind iris
is not listed there. Nothing in iris can change that, and a hook that announced the session
was tried and removed because it froze the state it announced. The section under Claude Code
above says why, and the only fix that costs nothing downstream lives in herdr.

## The theme

Almost every value is an ANSI palette slot rather than a hex colour, so Ghostty stays the one
owner of the palette. Slots work because lipgloss v2 turns `"4"` into `ansi.BasicColor(4)` at
`color.go:66-85`, which goes out as SGR `34` and lands on the terminal's slot 4. An earlier
version of this file claimed the opposite, on the strength of a measurement that only matched
`38;2` and `38;5` sequences and never looked at the `30` to `37` range, so it reported zero
colours while the menu was drawing in palette colours the whole time. A detector that can only
see one encoding reports the absence of every other one, and that mistake cost several rounds.

Slots are worth it because `aura-dark` and `aura-light` mirror each other by role, so slot 4 is
the primary accent on both and slot 8 is the comment grey on both. Slot 4 reads 5.77 to 1 on
the dark half and 4.83 on the light one, against 4.14 for the hand picked mid tone it replaced.
Change the Ghostty theme and the menu follows with no edit here.

`text` and the three idle tag backgrounds are deliberately unparseable rather than any colour,
because lipgloss renders an unparseable foreground unstyled, which inherits whatever the
terminal is painting, and does not draw an unparseable background at all. The second half is
what leaves a tag as a word on the page instead of a chip stamped onto it. Those chips were
dark blocks on a white page for a while, and fixing that is what the second half of this file
is for.

The `[dark]` and `[light]` tables exist for the selection bar and almost nothing else. A bar
has to be a tint of the page under it, and no slot is dark on the dark palette and light on the
light one. Every single file alternative was measured. Keeping the bar fixed forces `match`
fixed with it, since `match` is drawn on the page on every other row and inside the bar on this
one, and a fixed `match` only clears a bar that is very dark or nearly white. Letting the bar
inherit forces `match` to inherit, and then the bar has to be dark enough for the dark half's
match colour and light enough for the light half's at once, and those two are near opposite
ends of the range, which lands at 2.05 on slot 8, 1.08 on slot 4 and 1.27 on slot 7. There is no single bar, which is why the feature exists.

The two tables are generated from `theme/` by the emitter at the package root. The bar is
the `highlight` role, the same bar herdr's navigate row carries, and the secondary text is
`subtext`, so the two surfaces agree rather than each inventing a highlight. `text_sel` and
`sel_text` are the ink and the page by role, which is what their flipping slots always meant.
`dotfiles/iris/CLAUDE.md` has the reload step.

The appearance is asked for once by OSC 11 in the watchdog, which is the only moment iris holds
the tty with nothing else reading it, and after that the terminal reports changes on its own.
The wrapper turns on DEC private mode 2031, so a switch arrives as `CSI ? 997 ; 1 n` for dark
or `; 2 n` for light and the half follows without opening a new shell. That report lands on the
same stream as keystrokes, so the wrapper takes it out of the input before the shell or any of
the key handling sees it, otherwise it is printed onto the prompt as text. Only whole sequences
are recognised, since holding back a partial escape sequence would delay the arrow keys, which
begin the same way.

Taking it out is right for the shell and was wrong for everything else, and that cost a day of
every layer above iris being stuck. A program behind iris that asks for the same reports never
received one, because the terminal sends a single copy and iris consumed it. Herdr was the worst
case, since Neovim, Claude Code and the iris inside each pane all ask herdr rather than Ghostty,
so one report lost in front of herdr left the whole tree on the old half while iris itself, the
layer that ate it, switched perfectly. So the wrapper now reads the child's own `2031` switch
off the pty, the same way it reads the alternate screen switch, and relays each report to the
child verbatim while the child has asked for them. Zsh never asks, so the prompt stays clean.
Iris keeps the terminal's copy of the mode on regardless, answering a child's withdrawal by
turning it straight back on, and drops the child's request at every new prompt so a program
killed before it could withdraw cannot leave the line editor receiving reports.

Reloading the half is only part of it, because the box also has to be drawn again, and for a
while it was not. A terminal that changes appearance repaints its own palette, so every part
of the box drawn in a slot follows along with no help from iris, which made the switch look
like it worked. The selection bar is hex, for the reason the paragraph above gives, so it
stayed in the old appearance while everything around it changed, and closing the menu and
opening it again put it right. That is what proved the detection was already correct and only
the repaint was missing. It is asked for directly rather than through the usual render path,
which declines while the user is navigating the menu, the moment a stale bar shows most.

Two mistakes in that detection are worth not repeating, since both produced a terminal being
served the wrong half while plainly saying which it was. `IRIS_TERM_BACKGROUND` carries the
answer down to the process that draws, and it reaches the shell too, so an iris started from
that shell inherits it. Treating it as an override meant a decision made about an earlier
terminal outlived it and beat the one in front of you. It is rewritten on every start now, and
a value set by hand survives only when the terminal declines to answer, which keeps it useful
as a fallback for a terminal with no OSC 11 without letting it go stale. Separately, the query
paired the input tty with `os.Stdout`, and lipgloss refuses unless both handles are terminals,
which the watchdog's stdout is not always. That failure was invisible because
`HasDarkBackground` answers true for any error, so a query that never worked read as a terminal
that said dark. Asking through the tty iris already holds, and going through `BackgroundColor`
so a failure stays distinguishable from an answer, fixes both.
