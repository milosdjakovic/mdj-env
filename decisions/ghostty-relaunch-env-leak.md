# An app launched with `open` from a pane inherits the pane, and passes it on

Status. Fixed at both launch sites. `bin/hs-devlock` relaunches Hammerspoon with an empty
environment, and `ghostty-new` opens a fresh Ghostty the same way.

## Now

`open` hands the application it launches the calling shell's whole exported environment. Run
from inside a pane that includes every `HERDR_*` variable herdr sets to identify the pane,
every `CLAUDE_CODE_*` variable a running Claude Code session carries, and, while iris was
here, every `IRIS_*` variable its proxy set. None of those describe the new process, but nothing started
under it can tell an inherited value from one that is true for it.

Two symptoms follow from the same cause. A herdr started under the poisoned process sees
`HERDR_ENV=1` already set and refuses itself as nested. A Claude Code session started under it
sees `CLAUDE_CODE_CHILD_SESSION=1` and treats itself as a child of a session long gone, which
is why it disables transcript persistence.

The launch site that matters is not Ghostty. It is `relaunch_hs` in `bin/hs-devlock`, which
ran `open -a Hammerspoon` from whatever shell called it, and that shell is nearly always a
Claude Code tool shell inside a herdr pane. Hammerspoon then carried the pane's identity, and
since the Hyper+backtick binding and the launcher open Ghostty through Hammerspoon, every
Ghostty opened that way inherited it too, Cmd+N windows included. So quitting and reopening
Ghostty changed nothing, `herdr server stop` changed nothing, and a `hs.reload()` changes
nothing either, since a reload keeps the process and its environment. Only a relaunch of
Hammerspoon from a clean caller clears it, and until it is cleared the poison comes back with
the next Ghostty.

The fix is `env -i open`. Handed an empty environment, LaunchServices fills in exactly the
session environment launchd gives a Dock launch, `HOME`, `USER`, `LOGNAME`, `SHELL`,
`TMPDIR`, `SSH_AUTH_SOCK` and `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, measured on a throwaway
Ghostty instance rather than assumed. There is no list of variables to keep current, and a
Hammerspoon under test now runs in the environment it will really run in, which it did not
before, since a test could pass on a `PATH` the Dock launch never has. Anything the new
process should carry goes through open's own `--env VAR=value`, which survives `env -i`, so
a test instance is opened as `ghostty-new --env NAME=value`.

Recovery on a machine that already has it is quit Hammerspoon and relaunch it from the Dock,
Spotlight or the fixed `hs-devlock`, then quit Ghostty and open it again through Hammerspoon.
A `CLAUDE_CODE_CHILD_SESSION=1` on either application process, read with `ps -Eww`, is the
fingerprint.

## Rejected

- **Naming each leaking variable by hand in the `open` call.** 2026-09-16 about 11:16. Works
  once, and is what was done ad hoc on 2026-09-15, but a new herdr release or a new Claude Code
  environment variable silently reopens the hole, since nothing here would know to add it.
  Reading the live environment for the three prefixes at call time means a variable neither
  side has been told about yet is still caught.
- **Stripping the three known prefixes for the `open` call.** 2026-09-16 about 13:00. What
  `ghostty-new` did from 11:20 to 13:00, reading the live environment for `HERDR_`,
  `CLAUDE_CODE_` and `IRIS_` and unsetting each match. It catches a new variable in a known
  family and nothing in a new family, and the Hammerspoon process showed the shell env is far
  wider than three families, `ATUIN_*`, `P9K_*`, `GHOSTTY_*`, `FNM_*`, the lot, none of which a
  Dock launch has. An empty environment is what a Dock launch actually gets and needs no list.
- **Fixing it inside iris, herdr or Claude Code.** 2026-09-16 about 11:16. Not proposed in
  detail, listed because it was the first instinct. None of the three is wrong to set these
  variables for a pane or session they actually own, and `open` carrying a calling process's
  environment into the process it launches is documented macOS behaviour, not a bug in any of
  them. The leak only exists at the point something in this repository calls `open` from
  inside an already-identified pane, so the fix belongs here.

## Log

### 2026-09-15 about 01:35

First hit while testing the iris appearance fix, opening a throwaway Ghostty instance with
`IRIS_RESCUE=1` to watch herdr respond to an appearance switch directly. Refused as nested
herdr. Traced to `open` carrying the launching pane's `HERDR_` variables into the new instance,
worked around by unsetting them by hand for that one command. Recorded in
`decisions/iris-appearance-theme.md`, not here, since at the time it read as a detail of that
test rather than a mechanism of its own. No permanent fix was written.

### 2026-09-16 about 11:00

Milos reports the same nested-herdr refusal and a `recursion detected` message, opening an
ordinary new Ghostty window from a pane already running a herdr-identified Claude session, plus
a Claude Code transcript-saving warning naming an inherited `CLAUDE_CODE_CHILD_SESSION` marker.
Confirmed by reading this session's own environment, which carries `HERDR_ENV=1`,
`HERDR_PANE_ID`, `CLAUDE_CODE_CHILD_SESSION=1` and the `IRIS_*` set, and by rereading
`decisions/iris-appearance-theme.md`'s 01:35 entry, which is the same cause. The 09-15 fix was
scoped to one test command and never generalised, so this was always going to recur the next
time a fresh Ghostty instance was opened from an active pane, which is what happened.

### 2026-09-16 about 11:20

Added `ghostty-new` to `dotfiles/zsh/.zshrc.custom`, this file created and indexed. Not yet
confirmed against a live nested-herdr repro, since reproducing needs opening a new instance from
a pane already carrying the leaking variables, which is the state this session is already in;
confirmation is opening one with the function versus without it and comparing. Corrected at
13:00 below, the strip list is replaced by an empty environment and the Ghostty site was not
the one that mattered.

### 2026-09-16 11:31

Milos asks why `herdr server stop` followed by `herdr` refuses again, and why the other machine
never sees this. Read the environment of every process in this session's chain with `ps -Eww`.
The Ghostty application process, pid 68513, parent launchd, carries `HERDR_ENV=1`,
`HERDR_PANE_ID=w3:p1`, `CLAUDE_CODE_CHILD_SESSION=1` and `IRIS_IS_CHILD=true`, and so does
everything under it, including this very session, whose chain is Ghostty, login, iris, iris,
zsh, claude, with no herdr in it at all. The `CLAUDE_CODE_CHILD_SESSION` on the application
process says it was launched by a Claude Code tool call running `open`, which is what the
2026-09-15 theme testing did. So the poison is on the application, every window it has opened
since inherits it, and stopping the server changes nothing because the server was never the
source. The other machine's Ghostty was launched from the Dock and never relaunched from a
pane. Recovery is quitting Ghostty and relaunching it cleanly. Now section rewritten to say so.
Corrected at 13:00 below, the application process was poisoned from Hammerspoon, so that
recovery only lasts until the next launch.

### 2026-09-16 13:00

Milos hits it a second time, `herdr server stop`, Ghostty restarted, `herdr` refused as nested
again. Read `ps -Eww` on the new Ghostty, pid 91611, started 12:49:43 by launchd with
`_=/usr/bin/open`, `PWD` in the `storage-roots` worktree and the `CLAUDE_CODE_*` of session
`3cbac5da`, which had ended at 01:00. A shell that old could not have run `open` at 12:49, so
the values came through an intermediary, and Hammerspoon, pid 38199, started 00:48 during the
storage-roots testing, carries the identical set with the same `_` and `PWD`. The only
`open -a Hammerspoon` in the repository is `relaunch_hs` in `bin/hs-devlock`, run from a Claude
tool shell in pane `w3:p1`. Ghostty was reopened through Hammerspoon's Hyper+backtick, so it
inherited the lot. Both hits, 11:00 and 12:49, follow a devlock test session.

Measured `env -i open -na Ghostty` on a throwaway instance. It received `HOME`, `USER`,
`LOGNAME`, `SHELL`, `TMPDIR`, `SSH_AUTH_SOCK`, `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and the
XPC and CF plumbing, nothing from the shell, and `--env IRIS_RESCUE=1` survived it. Changed
`relaunch_hs` to `env -i open -a "$APP"` and `ghostty-new` to `env -i open -na Ghostty "$@"`,
dropping the prefix list. Relaunched Hammerspoon cleanly. The Ghostty this session runs in is
still poisoned and only Milos can quit it, so the last step is his.

### 2026-09-17 16:40

Found uncommitted a day later, after iris had been removed on the 16th at 16:55, and committed
now. Nothing in it depended on iris. `IRIS_*` was one of three leaking families and the other
two leak exactly as before, and an empty environment strips every family without naming one,
which is the reason the prefix list was rejected in the first place. Hammerspoon on this
machine, relaunched through the fixed `hs-devlock` at 22:52 on the 16th, carries none of the
variables, read with `ps -Eww`. The iris mentions in the Now section and the code comments are
reduced to the two families that still exist, and the log above keeps them as they were.

