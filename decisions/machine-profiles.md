# Machine profiles, and what each machine takes from this repository

Status. One tracked file, `MACHINES`, says which optional pieces each machine takes, keyed by
its `LocalHostName`, with a default row per piece for a machine that has none. `src/machine.sh`
is its only reader and every consumer asks it.

## Now

Three machines use this repository and they differ, one of them is not the user's and carries
its own setup, so a piece like mise must be possible to leave off without leaving the
repository. `MACHINES` lists six pieces, mise, hammerspoon, herdr, mole, docker and vpn. The
defaults keep what every machine got before the file existed, except mise, which is off unless
a machine asks, since mise acting on every `.nvmrc` would take over a machine's own pyenv or nvm.

A piece reaches a machine through four consumers and each asks the reader. The stow step adds
the optional packages that are on. `setup.sh` runs a piece's step through `step_if`, which
counts a skip as done. The Brewfile guards a piece's lines with `on?`, and since Homebrew hides
every variable but its own from a Brewfile, `install-homebrew-packages.sh` passes the machine
name as `HOMEBREW_MDJ_MACHINE`. The reconciler checks every machine row names a known piece,
and skips presence and grant checks for a module switched off here. The shell activates mise
only when its config exists, so it needs no knowledge of the profile at all.

Switching a piece off never removes anything. It only stops a run from adding it.

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
Proposed in the same conversation and dropped while building, since a setup run writing into a
tracked file is a new behaviour with its own failure modes and the defaults already give an
unlisted machine a safe answer. The run says in its closing block that the machine took every
default, which is the moment the rows get written by hand. Reopen if a third machine makes
writing them by hand a real cost.

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
