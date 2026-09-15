# fzf's colour, and the one part of it that follows the appearance

Status. Slots in `FZF_DEFAULT_OPTS`, and the selection bar resolved inside the herdr finder
alone. Global to every fzf is wanted and not built.

## Now

Every colour fzf draws on this machine is an ANSI palette slot, exported once in
`FZF_DEFAULT_OPTS` from the zsh package, so Ghostty repaints all of it on a theme change and
nothing watches anything. That covers the matches, the prompt, the pointer, the counter, the
header, the footer, the borders and the scrollbar.

The selection bar is the exception and cannot join them. A bar is a tint of the page under it
and no slot is dark on the dark palette and light on the light one, so it has to be hex, and a
hex value has to be chosen at the moment of drawing rather than when a shell starts.

Only `tools/find.sh` in the herdr package does that today. It asks
`defaults read -g AppleInterfaceStyle` and lifts herdr's own `selection_bg` out of `config.toml`
for the matching half. Every other fzf on the machine draws no bar.

Making that global was asked for and the attempt was reverted, so the question is open. What is
settled is how it cannot be done, which is the Rejected list below, and it now includes the
approach that was built. Anything new here belongs in the shell, in a config file, or in a
script, and never in Hammerspoon.

## Rejected

**A palette slot for the bar, 2026-09-15.** What every other colour here uses, and it would need
no detection, no file and no plugin. It cannot work, and iris measured why in full when its own
menu hit this, landing at 2.05 on slot 8, 1.08 on slot 4 and 1.27 on slot 7. That measurement is
why this went straight to hex without repeating it.

**Ghostty's own `selection-background`, 2026-09-15.** The tidiest possible source, since Ghostty
already owns the palette and its aura themes publish a selection colour beside it. Not used,
because it is a different colour. Aura light's is `#dfdaf2`, which carries the page's lilac,
where herdr's light values were pulled to near neutral on purpose and give the grey that was
actually wanted.

**Resolving the bar inside each tool that runs fzf, 2026-09-15.** Shipped first, in the herdr
finder alone, and removed the same day. It works and it makes every tool a second owner of a
colour, which is the drift this repository spends its effort avoiding. It also cannot reach a
plain `fzf` typed at a prompt, which was the whole ask.

**A wrapper named `fzf` on PATH, 2026-09-15.** `~/.local/bin` is already first on PATH, so a
script there would shadow the Homebrew binary for every caller that resolves by name, and it
would be correct at every invocation with no file and no watcher. Turned down as the option with
the worst standing cost. It shadows a package manager binary, it adds a process to every
launch, and it would have to find the real binary without naming an install prefix, which the
reconciler errors on, so the one thing it saves is paid for three times.

**A Hammerspoon plugin watching the appearance and writing the file, 2026-09-15.** Built in
full, gated, loaded live, and reverted the same hour. It worked. It is rejected on where it
lives rather than on whether it functions. A shell colour problem does not get answered by a new
moving part in the layer that runs everything else on the machine, and it should never have been
offered as an option in the first place. The standing rule that came out of it is in the
repository CLAUDE.md and in the `olm-plugin` skill, never propose a plugin, only build one that
was asked for.

**Regenerating the file from shell startup and from the popup scripts instead of from a watcher,
2026-09-15.** The version with no new moving parts. Offered and not taken, because a bare `fzf`
in a shell older than the last appearance flip draws the previous grey until something else
regenerates, and the long lived servers are exactly where these pickers live.

**Exporting `FZF_DEFAULT_OPTS_FILE` unconditionally, 2026-09-15.** The obvious way to write the
line. It breaks every fzf on the machine on any day the file is not there. See the log below.

## Log

**2026-09-15 10:21.** The herdr finder got the grey bar first, resolved inside `find.sh` from
`defaults read -g AppleInterfaceStyle`. Asked the same evening to make it global to fzf rather
than local to one popup, which is what turned a colour into a mechanism question.

**2026-09-15 10:33.** Measured, and it changed the design. fzf treats an
`FZF_DEFAULT_OPTS_FILE` it cannot open as a hard error, not as an absent default. It prints
`$FZF_DEFAULT_OPTS_FILE: open ...: no such file or directory`, produces no output and exits 2.
So the export is guarded on the file being readable, and the plugin writes the file even when it
has no colour to put in it, since an empty file is a safe degradation and a missing one is a
machine with no working fzf.

**2026-09-15 10:34.** Also measured, and it is what makes the file worth having at all. `footer`
does not follow `header` and neither follows anything else, and more importantly fzf rereads the
FILE at every launch while it reads the VARIABLE once per process. Everything static stays in
the variable and the one moving value lives in the file.

**2026-09-15 10:43.** Shipped as the FzfTheme plugin, the second Olm plugin after KeyRemap with
no surface at all. It declares no tools, because reading one config file and writing another is
Lua's own work and there is no binary to run, so nothing for the layer above to guarantee.
Loaded live and the console carries its own line, `fzf selection bar is #dcdbe1`, with
`distributednotifications` loading right after it and the pipeline reporting no problems.

**2026-09-15 10:48.** The watcher itself was proved without touching the machine's appearance,
by blanking the file, posting `AppleInterfaceThemeChangedNotification` with
`hs.distributednotifications.post`, and watching the correct contents come back. That proves the
notification, the settle timer and the write, and it deliberately does not prove that macOS
posts that exact name on a real flip, which only a real flip can show.

**2026-09-15 11:14.** Reverted the whole Hammerspoon approach at Milos's instruction, and the
reason is worth separating from the mechanics. Nothing about it failed. The gates were green,
the console was clean, and the file was correct. It was the wrong layer, and the failure was
mine one step earlier, in putting a plugin on a menu of options at all. Picking an option
somebody else wrote is not the same as asking for it, which is now written down as a strict rule
in three places rather than left as a lesson.

The plugin directory, the `FZF_DEFAULT_OPTS_FILE` export, the generated file and the two
documentation sections are all gone. `footer:4` stays, since that was an ordinary palette fix
and had nothing to do with this. The finder keeps the bar it had, resolved inline.

**2026-09-15 11:14.** Two measurements survive the revert and are the reason this file is worth
keeping. fzf rereads `FZF_DEFAULT_OPTS_FILE` at every launch where it reads `FZF_DEFAULT_OPTS`
once per process, which is the only known way to reach a program inside a server that froze its
environment. And fzf treats a file it cannot open as a hard error, exiting 2 with no output, so
any future use of that variable has to be guarded on the file existing. Whoever solves the
global version next needs both and should not have to rediscover either.

**2026-09-15 16:15.** The global answer now has a home. `theme/` declares the palette and
`theme-palette.md` carries the design. fzf is not painted from it yet, and when it joins, the
selection bar becomes a slot the palette declares rather than a hex anything watches, which
closes this file's open question without a watcher.

