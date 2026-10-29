# Machine profiles, and what each machine takes from this repository

Status. A tracked `machines/` directory says which optional pieces each machine takes.
`machines/default/pieces` has a default row per piece, and `machines/<name>/pieces` has the rows
where one machine differs, the directory named by its `LocalHostName`. A row reads
`piece | value  # reason`. `src/machine.sh` is its only reader and every consumer asks it.

## Now

Three machines use this repository and they differ, one of them is not the user's and carries
its own setup, so a piece like mise must be possible to leave off without leaving the
repository. `machines/default/pieces` lists eight pieces, mise, hammerspoon, herdr, mole, docker, vpn, tools
and kanata. The defaults keep what every machine got before the directory existed, except mise, which is off unless
a machine asks, since mise acting on every `.nvmrc` would take over a machine's own pyenv or nvm, and kanata,
which came later and is off unless a machine asks, since it puts a driver and a root daemon on a machine.

A piece reaches a machine through four consumers and each asks the reader. The stow step adds
the optional packages that are on. `setup.sh` runs a piece's step through `step_if`, which
counts a skip as done. The Brewfile guards a piece's lines with `on?`, and since Homebrew hides
every variable but its own from a Brewfile, `install-homebrew-packages.sh` passes the machine
name as `HOMEBREW_MDJ_MACHINE`. The reconciler checks every machine row names a known piece and every machine directory a valid
name, and skips presence and grant checks for a module switched off here. The shell activates mise
only when its config exists, so it needs no knowledge of the profile at all.

Switching a piece off never removes anything. It only stops a run from adding it.

A machine's Hyper app keys and display profiles are two more files in its folder,
`hammerspoon-apps.lua` and `hammerspoon-displays.lua`, Lua tables Hammerspoon reads. The default
apps are only those macOS ships and the Brewfile installs, the default displays are none, and a
machine's own file replaces its default whole. `src/setup-hammerspoon-apps.sh` copies each one that
applies to `~/.hammerspoon/machine-<kind>.lua`, and `config/machine.lua` reads them, so the
Hammerspoon config never names a machine. A copy edited by hand is refused rather than overwritten,
and an app key in `config/keymap.lua` is reported, both as closing notes. `--capture` writes this
machine's files from what is in place, `--discard` overwrites a hand edit. Rule 9 in the root
`AGENTS.md` says an agent changes a key or a profile in this machine's file only, runs the script,
and proposes discarding or moving a change it finds made directly.

## Rejected

**One git branch per machine, 2026-10-06.** Every shared fix would be copied onto each branch
and the branches would drift, and a machine's home directory links into whatever its checkout
has open, so it would sit on its own branch for good and never take main. It is the carried
fork failure `iris.md` records, applied to configuration.

**An untracked file on each machine, 2026-10-06.** It answers the same question but nobody can
see from the repository which machine runs what, and a reinstall loses it. The tracked rows are
data about machines the user owns or uses, which is the same kind of fact DisplayProfiles
already keys by `LocalHostName` in git.

**Asking for each piece on a machine with no rows and writing the answers back, 2026-10-06.**
Reopened the same day, see the log, as `capture`, a command a person runs rather than a step
setup runs on the way past.
Proposed in the same conversation and dropped while building, since a setup run writing into a
tracked file is a new behaviour with its own failure modes and the defaults already give an
unlisted machine a safe answer. The run says in its closing block that the machine took every
default, which is the moment the rows get written by hand. Reopen if a third machine makes
writing them by hand a real cost.

**Olm reading a per machine keymap by host name, 2026-10-27, about 14:50, estimated.** The way
`config/displays.lua` keys display profiles by `LocalHostName`. Milos turned it down, he would not
teach Olm about machines, and wanted the setup script that already does per machine work to put
the machine's keys where Hammerspoon reads them.

**A machine's app keys added on top of the default, 2026-10-27, about 14:50, estimated.** Milos chose a file that
repeats the default and adds its own, so one file says everything a machine's Hyper reaches.

**Every app key in the shared keymap, 2026-10-27, about 14:50, estimated.** A key there reaches every machine, and
an app one machine lacks, or a Chrome web app whose bundle id differs per install, cannot be
right on all of them. Google Chat was the case, its id here differs from the one `apps.lua` held.

**TOML for the file, 2026-10-06.** Nothing in bash or in the Brewfile's Ruby reads it without a
dependency, and every other declaration in this repository is a pipe table already, so the
reader is one awk program.

## Log

**2026-10-06 14:55.** Built at the user's request, after they said mise must stay optional
because some machines are already set up their own way, and that more than mise differs between
their three machines. Every IVPN choice was to become Mullvad, so `vpn` defaults to mullvad and
gates only the IVPN permission repair, and this machine's Hammerspoon backend was switched from
ivpn to mullvad in `hs.settings` and reloaded with no wiring problems. Mullvad itself stays a
manual install, as `DEPENDENCIES.map` already says.

Verified with this machine's real name and with `MDJ_MACHINE` and `HOMEBREW_MDJ_MACHINE` set to
an unlisted one. The Brewfile dropped mise for the unlisted machine and dropped mise and docker
when this machine's rows were set off for a moment. The first test passed `MDJ_MACHINE` straight
to `brew bundle` and mise stayed listed, which is how Homebrew's variable filter was found. The
reconciler reported a misspelt key as an error. `setup.sh` itself was not run end to end.

**2026-10-06 15:30.** `src/machine.sh capture` added at the user's request, who asked how a
machine's own setup gets recorded and then that a rerun modify the existing block rather than add
to it. It probes each piece, reports the fact found and the value it suggests, asks, and rewrites
that machine's block where it stands, under a `# NAME, captured DATE` header. Rows are compared
without the header, so a second run on an unchanged machine writes nothing. A proposal the person
turns down is written as a row too, since otherwise the next run would ask the same question as
if it were new, which the first version did. A row set by hand that disagrees with the evidence
is kept unless the person says otherwise, and every run asks with no as the default. A generic
name such as `MacBook-Pro` stops it, since two machines could share it, and `MDJ_MACHINE` in that
machine's shell profile is the answer where the Mac cannot be renamed.

Verified with `expect` across six runs on a pretend machine, declining, rerunning, adding a hand
row, accepting and rerunning, and on this machine, where the first run wrote its block and the
second reported nothing to change. Piping answers through `script` did not reach the prompt and
is not a way to test it.

**2026-10-06 17:05.** A seventh piece, `tools`, whose value is a list rather than one word, the
mise tool groups a machine takes, at the user's request that tools differ between machines and
that the choice live in `MACHINES`. Its probe in `capture` counts a group as used when any command
it lists is already on the machine, from anywhere. The list is alphabetical, since the first probe
reported `dev,personal,work` against a row of `dev,work,personal` and called a match a change.

**2026-10-07 11:55.** `tools` now names catalog entries rather than groups. Its probe in `capture`
proposes every catalog name whose command is on the machine, alphabetical. The first version
found nothing, because capture reads the probe's answer with `IFS='|'` set and the probe's own
`read` inherited it, so each line came back as one field. The probe sets its own separator now.
`Miloss-MacBook-Pro` gained `mise` on and `tools` of `node,python,uv`, written by hand from the
user saying that machine needs python and node only. Its capture had left every piece on its
default.

**2026-10-22 23:37.** A plan to replace this file's arrangement was written with the user and
reviewed the same day, `docs/PLAN-MACHINES.md`. `MACHINES` becomes a `machines/` directory with a
`pieces` file per machine, a module declares overlay seams a machine may fill, and no tool chooses
its behaviour by the machine it runs on, with DisplayProfiles named as the one exception since it
writes hardware state it captured itself. The trigger was kanata on this machine, which the user
wants as a module of its own while Olm stays unaware of it. Nothing here changes until the phases
land, and each one writes its own entry.

**2026-10-23 09:40.** Phase 2 of `docs/PLAN-MACHINES.md` landed. The root `MACHINES` file became the
`machines/` directory. `machines/default/pieces` holds the default rows and each machine block
became `machines/<name>/pieces`, with the machine column dropped from every row, since the
directory names the machine. Every comment after a value and each `# NAME, captured DATE` header
moved with its rows. `src/machine.sh` reads the directory with the same commands, `listed` means
the machine's pieces file exists, `check` also refuses a directory that is no valid machine name,
and `capture` rewrites `machines/<name>/pieces`, creating the directory when it is missing. A
machine name from `LocalHostName` or `MDJ_MACHINE` must hold only letters, digits, hyphen, dot and
underscore with no leading dot, and `default` is refused, each as exit 1 with a clear line from
every command that needs the name. This checkout sits on a case insensitive volume, so `machines`
and `MACHINES` are the same path, and the move went through a temporary name. Verified by running
`get` and `on` for every piece, plus `listed` and an unknown key, as each of the two real machines
and as `Some-Unlisted-Mac`, before and after. The only difference is the words of the unknown key
error on stderr, which now names `machines/default/pieces`. The Brewfile listing through
`HOMEBREW_MDJ_MACHINE` was identical for this machine and for an unlisted one. `capture` was run
through `expect` on a pretend machine in a scratch copy, declining a proposal, rerunning, accepting
the change, keeping a hand comment, and rerunning on an unchanged machine, which wrote nothing.
The readers, their commands, their answers and their exit codes are unchanged.

**2026-10-23 09:59.** Phase 3 of `docs/PLAN-MACHINES.md` added the `kanata` piece, off by default,
covering the kanata package and formula and `src/setup-kanata.sh`, which installs the Karabiner
driver and runs both as root daemons. `Miloss-MacBook-Pro-Vicert` takes it on, the row written in
the shape `capture` writes, so a later capture there reports it unchanged, which a run without a
terminal confirmed. The probe in `capture` suggests on only when kanata is on PATH and the
Karabiner driver extension is activated and enabled, since kanata without the extension remaps
nothing. The stow step adds the package where the piece is on, the Brewfile guards its line with
`on?(:kanata)`, and `setup.sh` runs the step through `step_if kanata on`. `decisions/kanata.md`
has the rest.

### 2026-10-24 00:45

`src/machine.sh set KEY VALUE [REASON]` writes one row for this machine. Capture can only propose
what it finds, so a piece a machine does not have yet, kanata on the second machine that day, was
a row written into the file by hand. `set` writes only this machine's file, replaces the key's
row where it stands or adds one, refuses a key with no default and a value holding a space, a
pipe or a hash, and installs and removes nothing, so rule 2 of the root `AGENTS.md` still holds,
the person's explicit answer becoming the row. A file it creates starts with a header saying its
rows were set by hand and it was not captured yet, rather than a captured header it did not earn.
`./setup.sh --only PIECE` is the step that follows it, refusing a piece that is off or none here.
Checked on a throwaway machine name, the folder removed afterwards.

### 2026-10-27 14:56

Hyper app keys moved out of `config/keymap.lua` into `machines/default/hammerspoon-apps.lua` and
`machines/Jelenas-MacBook-Pro/hammerspoon-apps.lua`, at Milos's asking, after he wanted Google Chat
on Hyper and G on this machine only. The default is the ten macOS apps and keys that were in the
keymap plus Ghostty, Obsidian and Docker from the Brewfile. This machine's file repeats those and
adds Chrome, VS Code, Zed, Slack, Claude and Google Chat, with Google Chat's id as Chrome installed
it here, `com.google.Chrome.app.pommaclcbfghclhalboakcipcmmndhcj`, where `apps.lua` holds
`mdpkiolbdkhdjpekfbkbmhigcaggjagi`, presumably another machine's. The other two machines have no
file and take the default, so they lose Chrome, VS Code, Zed, Slack and Claude until each is
captured there, which Milos chose. The hammerspoon module gained a `NO-FOLD` for `~/.hammerspoon`,
since a folded one would send the copy into this checkout. Applied here, reloaded, the live keymap
read back 19 keys with Hyper and G on Google Chat and the id laid over the catalog, the console
clean of new errors, and the unit cases 2017 of 2017.

### 2026-10-27 15:05

Display profiles moved the same way, at Milos's asking, with an empty default. Only
Miloss-MacBook-Pro-Vicert had any, four, and they moved unchanged into its own folder, compared by
loading both and matching every name and command. Moving a machine's existing profiles is not
writing rows for it, and leaving them would have dropped them there. `config/displays.lua` keeps the
settle delay and hands DisplayProfiles this machine's list, which the plugin already took as is
when it is not keyed by host, so Olm is unchanged. The step copies both kinds now.

Milos asked in the same exchange for a rule, that an app key he asks for goes into this machine's
file and the script runs, never the shared config, and that a change found made directly is
proposed for discarding or moving. It is rule 9 in the root `AGENTS.md`. The script backs the half
it can see. It remembers each copy as `.machine-<kind>.copied`, refuses a copy that differs from
it, and reports an `apptoggler` key in `config/keymap.lua`, as closing notes inside `setup.sh` and
a nonzero exit alone. Checked in a scratch home through a fresh copy, a rerun, a hand edit, the
same inside a setup run, `--discard` and `--capture`, and live here, 19 keys and no profiles as
before, unit cases 2017 of 2017. This machine's built in panel reports `s4251086178`, the id the
Vicert profiles name for theirs, which `displays.lua` had called different on every Mac. Not acted
on.

### 2026-10-28 13:45

A Hyper hold sheet seen live on 2026-10-28 had no DORMANT group and listed the wrong running apps.
The cause was the test lock. `bin/hs-devlock acquire` points Hammerspoon at a worktree's own
`init.lua`, the config reads `machine-apps.lua` and `machine-displays.lua` from its own directory,
and those two files exist only in the real `~/.hammerspoon`, so every worktree test had run on the
shared defaults. The lock now links each `machine-*.lua` it finds in the real config directory into
the worktree's `.hammerspoon` directory on acquire, by pattern so a third kind needs no edit, and
never over a real file there. The links are recorded in the holder file. Release and break remove
exactly those, each only while it is still a symlink to its recorded target, before main is
restored. A `.gitignore` entry keeps `machine-*.lua` out of every checkout's commits.

### 2026-10-29 10:53

A worktree held under the test lock fails the offline goldens. The lock links this machine's
`machine-apps.lua` and `machine-displays.lua` into the worktree, and the goldens projection then
reads this machine's Hyper app keys rather than the shared defaults, so `keys.golden` and
`sheets.golden` differ with no change to any key. The same tree run on a copy without the two
links matched every golden. Not fixed yet, run the gate before taking the lock or on a copy.

### 2026-10-29 11:40

Fixed the entry above. The offline run, `test/drygate-composerun.lua`, now treats a
`machine-*.lua` beside the config as absent, refused by its sandbox and by its `loadfile`, so
every offline golden describes the repository's config whether or not the lock has linked this
machine's files in. With both links in place the dry gate and every golden passed, where they had
failed, and they pass without them as before. The live goldens, `goldens.sh --live`, still read
the running config and so still include this machine's keys, which is what a live read is for.

