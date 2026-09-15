# Herdr fuzzy search, how it leaves

Status. Enter opens the chosen place, `ctrl-y` copies its absolute path and closes.

## Now

The finder in the herdr popup, `prefix+f`, had exactly one ending for a long time. Enter
resolved the pick to a place and either typed a `cd` into the calling pane or, when that pane
was busy, opened a new tab there. Wanting the path itself meant opening the place and reading
it back out of the shell, which is a lot of ceremony for a string.

`ctrl-y` is now a second ending. It puts the absolute path on the clipboard, shows a
notification naming what it took, and exits without touching the pane or creating a tab. It is
declared with `--expect` rather than as a binding that copies in place, so fzf prints the key it
left on as the first line and the selection after it, and both endings are read by one parse at
the bottom of the script. A picker that has already answered should close, so there was never a
reason for the copy to stay resident.

The header carries the hint beside the two toggles, which is the one place in this popup a
header earns its keep, since the frame already carries the name and cannot carry keys.

## Rejected

**Shift and enter for the copy, 2026-09-15.** It is the shape the request arrived in and it
reads better than any control chord. fzf does not accept the key. `fzf --bind shift-enter:abort`
answers `unsupported key: shift-enter` and exits, on 0.74.4, which is current. The terminal is
not the obstacle and turning on a keyboard protocol does not help, the name is simply not in
fzf's table. `shift-up` and the other three arrows are, which is what makes the absence look
like an oversight rather than a rule.

**`ctrl-c` for the copy, 2026-09-15.** The other shape the request arrived in, and the familiar
one from everywhere outside a terminal. fzf aborts on `ctrl-c`, so binding it to copy takes an
exit away from the picker rather than adding an ending to it. Escape still closes everything,
which is this surface's rule, but a key that used to leave and now copies is worse than a key
that never did either.

**A binding that copies without closing, 2026-09-15.** `execute-silent` with `pbcopy` would
keep the list on screen after a copy. Turned down because the popup gives no feedback of its
own, so the user would be left looking at an unchanged screen wondering whether anything
happened, and because a picker that has answered has nothing left to pick.

**Setting the footer colour inside `tools/find.sh`, 2026-09-15.** It would take effect on the
next popup rather than waiting for a herdr restart, which is the only thing it has going for it.
Turned down because the fzf palette has one owner, `FZF_DEFAULT_OPTS` in `.zshrc.custom`, and a
colour written into a tool is a second owner that nothing reconciles. The restart is a one time
cost and a divided palette is not.

**A palette slot for the selection bar, 2026-09-15.** It is what every other colour in these
pickers uses and it would need no detection and no config reading. It cannot work. A bar is a
tint of the page under it and no slot is dark on the dark palette and light on the light one,
which iris measured in full when its own menu hit this, landing at 2.05 on slot 8, 1.08 on slot 4
and 1.27 on slot 7. That measurement is why the bar here went straight to hex without repeating
it.

**Copying herdr's `selection_bg` hex into the script, 2026-09-15.** The obvious way to get the
value and the way iris carries it, since iris has no shared reader to reach for. Turned down
here, because `config.toml` sits one directory up from the script and an awk over it is eight
lines, so there is no reason for this module to hold the same colour twice and let the pair
drift.

**Reading the appearance from the environment, 2026-09-15.** `IRIS_TERM_BACKGROUND` already
carries the answer and is rewritten on every iris start, so it looked like the cheap route.
Wrong here. A popup is a child of the herdr server, not of a shell, so it sees the copy the
server froze when it started and would happily draw the wrong half for as long as that server
lives.

**Declaring `pbcopy` in the module manifest, 2026-09-15.** It is a command the module now runs
and the rule says a module declares what it needs. Left undeclared anyway, to match the tmux
module, which has copied with `pbcopy` from its own pickers since those were written and does
not declare it either. It ships with the operating system and cannot be absent. Worth revisiting
as one change across both modules rather than as an asymmetry introduced here.

## Log

**2026-09-15 09:38.** Asked for a way to copy a path out of the finder rather than only opening
it, proposed as shift and enter or `ctrl-c`. Both were measured against fzf before anything was
written, since a key that the picker will not accept is not a design question. `shift-enter` is
rejected by fzf outright and `ctrl-c` is its abort, so the answer became `ctrl-y`, which is the
conventional yank and which fzf accepts. fzf does bind `ctrl-y` itself, to pasting from its kill
ring into the query, and overriding that costs nothing here because the query is typed rather
than pasted.

**2026-09-15 09:38.** Shipped as `--expect=ctrl-y` with the branch at the bottom of
`tools/find.sh`, ahead of the pane and tab logic so a copy never reaches either. The header
gained the hint and the module CLAUDE.md gained the paragraph. The popup closes on copy, so a
notification carries the confirmation and names the path with the home directory shortened.

**2026-09-15 09:52.** The hint was a `--header` and read above the list, and moved to `--footer`
so it sits on the bottom edge instead. fzf has had one since 0.60 and rules it off with the same
horizontal line it draws under the match counter, so the window is ruled at both ends and nothing
new is framed or labelled. `--footer-border` and `--footer-label` exist and are left alone, since
either would put a second frame or a second name inside a popup that already has both. The
lazygit fallback's own header stays a header, because it says why the picker appeared rather than
what the keys do, and that is read once at the top rather than referred back to while picking.

**2026-09-15 10:04.** The footer drew in a pale blue green that belongs to no theme here. It is
cube index 109, fzf's own built in default, and it survived because `footer` is a separate colour
name that does not follow `header`. Setting `header` alone leaves it, which was measured by
drawing both lines at once with `header` on slot 4 and reading the escapes back, where the header
came out as `34` and the footer as `38;5;109` beside it. `footer:4` joins `info` and `header` in
`FZF_DEFAULT_OPTS` and the finder now draws the line in the same accent as everything else,
verified the same way.

**2026-09-15 10:04.** Worth knowing before wondering why that change did nothing. The herdr
server carries the environment of the interactive shell that started it, and a popup command is
a child of the server rather than of a login shell, so `FZF_DEFAULT_OPTS` reaches the finder from
that frozen copy. `herdr server reload-config` rereads the config file and changes no process
environment, so a palette edit reaches these popups only once the server itself is restarted.
That the variable arrives this way at all was checked rather than assumed, by reading the running
server's environment out of `ps eww`.

**2026-09-15 10:21.** Asked what the green in the popup was and whether the selected row could
carry herdr's own grey. The green is fzf's, `prompt:2` and `pointer:2` from `FZF_DEFAULT_OPTS`,
slot 2 and therefore already the terminal's, so nothing to fix there. The row now draws
`--highlight-line` over `bg+` set to herdr's `selection_bg`, read out of `config.toml` for
whichever half `defaults read -g AppleInterfaceStyle` says the system is on. Verified by
rendering the real script and reading the escapes back, where the row came out
`48;2;220;219;225`, which is `#dcdbe1`, the light half's value. The green pointer bar is left as
it is, since it marks the row and the sidebar's own highlight has no equivalent to lose.

**2026-09-15 10:48.** The selection bar left this file. Asked for it globally rather than in one
popup, so it moved to an Olm plugin writing a file every fzf reads, and `find.sh` now resolves no
colour at all. The finder looks identical and owns one less thing. The topic lives in
`fzf-appearance-colour.md` from here, including the two measurements that shaped it.

**2026-09-15 11:14.** The bar came back to this file. The global attempt was reverted, so
`find.sh` resolves the colour inline again, exactly as it did before, and `fzf-appearance-colour.md`
carries why the global version is still open.


**2026-09-15 18:55.** The bar left this file for good. It is slot 16, declared as the `highlight`
role in Ghostty's map, and every fzf reads it from one options file, so `find.sh` carries no
colour and no appearance check. `fzf-appearance-colour.md` has the close.
