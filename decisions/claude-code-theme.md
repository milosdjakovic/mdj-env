# Claude Code theme

Status. `theme` is `auto`, merged into `~/.claude/settings.json` by `src/setup-claude-settings.sh`.

## Now

Claude Code paints its UI in hex colours chosen per theme, not in palette slots, so unlike the
prompt, the iris menu or anything else drawn in slots it does not follow the terminal on its
own. `auto` is the one value that makes it ask, once by OSC 11 and then by listening for the
`2031` report, and that request travels through herdr and through iris, which is the chain
`iris-appearance-theme.md` exists to keep open, now merged into `iris.md`. A fresh install defaults to `dark`, and
`settings.json` is not stowed because Claude Code writes to it, so the value was set by hand on
the first machine and never reached the second. The merge script now writes it alongside the
status line and the hook, and the script's own comment says why.

A switch made while a session runs, waking the machine among them since the appearance is on
Auto, lands on the wrong half in herdr, and the defect is herdr's. Claude Code takes the `2031`
report only as a cue and asks OSC 11 again, and herdr answers that from a colour cache still
holding the half it just left. So the highlight bars come out opposite the terminal and a restart
is the only cure. herdr's issue 4183 is fixed on master and in no release after 0.9.5 yet, so it
is recorded below with a reproduction and the reconciler knows nothing of it.

In the Herdr desktop app a switch is followed, since 2026-11-15. The app's core answers OSC 11
from the theme of the half it is on and sends the report the moment the half changes. It went
stale there only because our zsh hook set the page in every pane, which the pane then answered
whatever the half, and the hook now sets only the four slots above sixteen.
`herdr-app-colors.md` has the measurement.

## Rejected

- 2026-09-15, stowing `settings.json` or tracking it. Claude Code rewrites the file itself, so a
  symlink into the repo would turn every session into an uncommitted change. Same reason the
  status line and the hook are merged rather than stowed.
- 2026-09-15, `claude config set theme auto`. The `config` subcommand is gone in 2.1.272, the
  binary treats it as a prompt and starts a session. `jq` on the file is the supported route
  this repository already uses.

## Log

### 2026-09-15 11:52

Milos reports, on the machine the env was just applied to, that slash commands in Claude Code
are light blue where they should be darker, and that yellow is off, the colours looking like
the dark palette kept on a light terminal. `~/.claude/settings.json` had `"theme": "dark"`.
The working machine is on `auto`, recorded in `iris-appearance-theme.md`, now merged into `iris.md`, at 01:05 the same
day, so the iris repaint fix was never in question here, Claude was simply never asking.
Set to `auto` by `jq`, then made `setup-claude-settings.sh` merge the same key so the next
machine gets it from `setup.sh`. Running the script after the hand edit reported already
configured, which is the convergence the script is built for.

**2026-09-15 23:16.** The statusline grey is slot 17 rather than a truecolour pair chosen by
reading the macOS appearance. `theme-palette.md` has it. `theme = auto` is unchanged and still
the reason the rest of the UI follows the terminal.

### 2026-10-26 18:33

Milos reports that on a switch of the system appearance Ghostty and herdr follow and Claude
Code follows only halfway, its prompt highlight bars painted for the half the terminal just
left, until Claude Code is restarted. Versions. macOS 27.0, herdr 0.9.3, Claude Code 2.1.310,
`theme = auto` confirmed in `~/.claude/settings.json`. The chain is Ghostty, herdr, Claude Code,
with no iris since 2026-09-16.

Measured with a probe in a fresh herdr pane, a raw mode Python script that sets `?2031h`, logs
every byte the terminal sends back, and asks OSC 11 the moment a `?997;Nn` report arrives,
which is what Claude Code does. Eight switches, eight reports, every one in the right
direction about a second after the switch, so herdr forwards the report faithfully. But the
OSC 11 answer that followed gave the background of the previous half seven times out of nine,
`1515/1414/1b1b` after a report of light and `f8f8/f7f7/fbfb` after a report of dark. herdr's
palette cache is updated after the report is forwarded rather than before.

Read Claude Code's `watchSystemTheme` in the 2.1.310 binary. On a theme report it ignores the
reported half, outside an internal surface override, and runs the same OSC 11 query it runs at
startup, then picks the theme from that answer. So the stale cache inverts the theme on almost
every switch, which is the opposite highlight Milos sees, and startup is right because herdr's
cache is settled by then.

A belief of mine during the session was wrong and is kept here. I first said Claude Code
switches straight from the report's flag, from reading its input parser alone. The subscriber
proves it asks again. And I first suspected herdr of dropping the dark report, from a probe
that had been closed before the switch back. The second probe disproved it.

Not fixed here, under the upstream defects rule in AGENTS.md. Reproduction for herdr, from
any herdr pane. Run the probe, switch the appearance a few times, read the log. A fixed herdr
answers every OSC 11 that follows a report with the background of the half that report names.

    import os, sys, tty, termios, time, select
    fd = sys.stdin.fileno(); old = termios.tcgetattr(fd); tty.setraw(fd)
    os.write(1, b"\x1b[?2031h")
    try:
        end = time.time() + 120
        while time.time() < end:
            if select.select([fd], [], [], 1)[0]:
                d = os.read(fd, 1024)
                sys.stderr.write("%s %r\r\n" % (time.strftime("%H:%M:%S"), d))
                if b"997;" in d: os.write(1, b"\x1b]11;?\x1b\\")
    finally:
        os.write(1, b"\x1b[?2031l"); termios.tcsetattr(fd, termios.TCSADRAIN, old)

Not yet reported upstream. A restart of the Claude Code session, or `claude --resume`, repaints
it correctly until the next switch.

### 2026-11-06 08:29

Rechecked on herdr 0.9.5, Claude Code 2.1.319, macOS 27.0.1, with the same probe in a herdr
pane and sixteen switches about two seconds apart. Every switch produced a report naming the
right half, so forwarding is still sound. The OSC 11 answer that followed was wrong eleven times
out of sixteen, the background of the half just left, and from the fifth switch on it was right
only twice. So the stale cache is unchanged in 0.9.5, and Claude Code still lands on the wrong
half more often than not. Still not reported upstream.

**2026-11-06 08:41.** The two lines above saying it was not reported upstream were wrong. Others
had already reported it at github.com/herdrdev/herdr, as issues 4844 and 4913, both closed by the
maintainers' bot as duplicates of 4183. Issue 4183 was closed as completed on 2026-10-23, and a
regular commenter there says the fix is on master and waiting for a release. The newest herdr
release is 0.9.5 from 2026-10-14, so no release carries it yet. herdr accepts only bug issues from
outsiders, and closes pull requests from anyone not on its approved list. So nothing here needs
reporting. The check is to run the probe again once a herdr release after 0.9.5 is installed.

### 2026-11-09

Milos asks for the Aura themes in Claude Code. Claude Code reads custom themes from
`~/.claude/themes/<slug>.json` (name, base, overrides of token to colour, per the terminal-config
docs), with no VS Code theme import. Added `theme-map` and `theme-emit` to the claude package so
the two files come from the palette like every other tool. `theme` stays `auto`, since selecting a
custom theme pins one half. Diff background tokens are left to the base theme. Not verified: that
the desktop app's Code tab honours these files, and the files are not yet linked on this machine.

### 2026-11-12

The entry above sat uncommitted in a worktree of its own until today, when it was brought onto
main as written, both files regenerated by `src/check-theme.sh` identical to the ones staged.
They reach `~/.claude/themes` on the next run of `src/setup-stow-dotfiles.sh`, which makes that
folder real first, `NO-FOLD`. The desktop app's Code tab is still unchecked.

### 2026-11-15 18:20

Milos asks for a script that repaints a Claude Code session after waking the machine, status
line included, in the Herdr app rather than in herdr. `src/claude-repaint.sh` sends every colour
of the half macOS is on to every pane under `herdr-core`, the sequences the prompt hook sends,
which a running Claude Code holds back from that hook. Measured on the izbori session, which
showed the fault, a navy status line and white prompt bars on the dark half. After the script the
status line was the right grey at once.

The prompt bars stayed white, which is Claude Code's light theme, `userMessageBackground`
rgb(240, 240, 240) against rgb(55, 55, 55) on dark, read from the 2.1.325 binary. Claude Code
asks the pane only when `watchSystemTheme` starts, at launch or when the theme setting changes in
its own state, and on a `?997` report. A first version of the script set `theme` in
`settings.json` to the half and back to `auto`, and no running session moved, so that file is not
watched for the theme and the step was taken out. Typing the report into a session's input was
refused by Claude Code's own permission check as tampering with a running agent, and was not
pursued. So the script ends by saying what to do in each session, `/theme` to a fixed theme and
back to `auto`, which restarts the watcher against a pane that now answers rightly. That last step
is read from the code and not yet seen working.

**Corrected 2026-11-15 21:10.** The fault was not that Claude Code could not be reached from
outside. The Herdr app had told it of the switch and it had asked, and the pane answered the
page our own hook had set at its last prompt. The script repaired the symptom after the fact,
and `/theme` was never needed. The script was removed before it was committed, and the entry
below has what replaced it.

### 2026-11-15 21:10

Measured in fresh Herdr app tabs, herdr-app 0.1.16 with core 0.1.21, macOS switched to light and
back by `osascript` while a raw mode probe logged every `?997` report and asked OSC 11 at once on
each. A clean pane got the report within a second of each switch and answered `#f8f7fb` on light
and `#151418` on dark in the same second, so the app does what its issue 122 says it fixed in
0.1.11. A pane that first received the hook's sequences got both reports and answered `#151418`
throughout, the page the hook had set. So a Claude Code running across a switch, every wake on
Auto appearance, asked on the report and kept the half of the pane's last prompt, which is the
white prompt bars on a dark page Milos saw after waking. The hook now sets only slots 16 to 19
and hands the rest back to Herdr, and a pane set by the older hook answered rightly again after
that reset, with nothing restarted. `herdr-app-colors.md` has the change. What stays is slot 17,
the status line's grey, which Herdr's sixteen slot theme cannot carry, so a status line running
across a switch keeps the old grey until the pane's next prompt.
