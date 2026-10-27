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

A switch made while a session runs lands on the wrong half, and the defect is in herdr. Claude
Code takes the `2031` report only as a cue and asks OSC 11 again, and herdr answers that from a
colour cache still holding the half it just left. So the highlight bars come out opposite the
terminal and a restart is the only cure. Nothing in this repository can fix it without a
workaround, so it is recorded below with a reproduction and the reconciler knows nothing of it.

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
