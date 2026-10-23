# kanata Configuration

kanata remaps the keyboard below every app, so Caps Lock held is Hyper as the four real modifiers
and Right Option held is META as shift, control and option. It reads the physical keyboard through
IOKit and types through a virtual keyboard that the Karabiner DriverKit VirtualHIDDevice driver
provides. Both run as root daemons. This module is an optional piece, `kanata` in `machines/`,
off by default and on for `Miloss-MacBook-Pro-Vicert`. `decisions/kanata.md` has why kanata, what
was turned down and what was measured, and it is the file to read before proposing anything here.

## What lives where

`.config/kanata/kanata.kbd` is the config, stowed to `~/.config/kanata/kanata.kbd`. Everything
else at this package root is repository only and listed in `.stow-local-ignore`.

`DRIVER` is the pin for kanata and its driver together, one row per kanata minor version with
the driver version, the package URL and its sha256. It is the one place either version is
written. `DEPENDENCIES` declares kanata, the driver and three grants. `grants-probe` answers the
grants for `src/check-dependencies.sh`.

No `NO-FOLD` is declared. kanata writes nothing beside its config, its log goes to the file the
daemon names, so `~/.config/kanata` may fold into one link into this checkout. Neither daemon
writes into the home directory at all.

## Setting it up, and applying a change

`src/setup-kanata.sh` does all of it, and `setup.sh` runs it through `step_if kanata on`, after
Homebrew and after the stow step. `src/setup-kanata.sh --dry-run` prints every change it would
make, every sudo command and both generated plists, and changes nothing. Read that first on a
machine that has not run it.

A config change is applied by running `src/setup-kanata.sh` again. It validates the stowed file
with `kanata --check`, compares its sha256 with the one recorded when the daemon last started,
and restarts kanata only when they differ. A change that does not validate leaves the running
daemon on what it had. To restart by hand instead, check the file first.

```bash
kanata --check -c ~/.config/kanata/kanata.kbd
sudo launchctl kickstart -k system/mdj-env.kanata
```

Restarting by hand skips the recorded hash, so the next run of the step restarts once more.

## The two daemons

`/Library/LaunchDaemons/mdj-env.karabiner-vhid-daemon.plist` runs the driver's daemon, and
`/Library/LaunchDaemons/mdj-env.kanata.plist` runs kanata with `--cfg` pointing at the stowed
config under the person's home directory. Both are `RunAtLoad` and `KeepAlive`. The step writes
them from the running user's home and the resolved kanata path, so no path of a person is in the
repository, and it replaces a plist only when the content differs.

kanata runs as `/Library/Application Support/mdj-env/bin/kanata`, a copy of Homebrew's binary
owned by root with mode 755, in directories only root can write. Homebrew's Cellar belongs to the
person, so a daemon running the Cellar file would hand root to anything that can write there, and
a binary found through PATH would let any directory early on PATH choose what root runs. So the
step asks Homebrew for the file, `$(brew --prefix kanata)/bin/kanata` resolved, never PATH, proves
it cannot run commands, copies it only when its sha256 differs from the copy, and then proves the
copy and checks the config with the copy, so what was proven is what runs. A new copy restarts
kanata. The step also takes back either directory if it finds one the person could write.

Logs go to `/Library/Logs/mdj-env/kanata.log` and `/Library/Logs/mdj-env/karabiner-vhid-daemon.log`,
readable by anyone and listed in Console under Log Reports. The driver also keeps its own log in
`/var/log/karabiner`. What kanata was last started with is recorded in
`/Library/Application Support/mdj-env/kanata.kbd.sha256`.

## What only a person can do

Three grants, each declared as a gate in `DEPENDENCIES` and answered by `grants-probe`. With a
terminal, `src/setup-grants.sh` opens the pane for each one missing, shows the binary in Finder
for the two that need it added, and waits until the probe reads it as given. Inside `setup.sh`
that step runs after this module's, and run alone this module's step calls it for kanata only.
Without a terminal each missing grant is a closing note. The probe's `--subject` answer, the
file to add, is read from launchd, so the binary's path stays written in `src/setup-kanata.sh`.

- **The driver extension.** Approved once per driver install, in System Settings, General, Login
  Items and Extensions, Extensions, Driver Extensions on macOS 26 and 27. The pane's address is
  the grant row's fourth field in `DEPENDENCIES.map`, which opens the Extensions section, and the
  Driver Extensions row is one click inside it. The probe reads `systemextensionsctl list`, which
  needs no privilege.
- **Input Monitoring** for `/Library/Application Support/mdj-env/bin/kanata`, the root owned copy.
- **Accessibility** for the same path. kanata 1.12 checks it right after Input Monitoring and
  refuses to open the keyboard without either. Its own source names a missing Accessibility grant
  as the usual cause of the not permitted error from `IOHIDDeviceOpen`, upstream issue 1211.
  On macOS 27 the Privacy and Security page lists no Accessibility row, so the list is opened
  directly at its address, which is the grant row's fourth field in `DEPENDENCIES.map`.

The probe answers the last two from kanata's own log, since asking from a terminal would answer
about the terminal. Keyboard grabbed, or any later failure at the driver, means both were given.
`Input Monitoring permission is denied for kanata` is denied, `kanata needs macOS Input Monitoring
permission` and `kanata needs macOS Accessibility permission` are not yet given. Only the last
start in the log counts, and a start that has not reached its checks is exit 2.

Running kanata by hand under sudo in a terminal is different, there macOS asks about the
terminal app instead, which is why the trial worked without either grant on the binary.

## Upgrading, kanata and the driver together

kanata talks to the driver's daemon over a protocol that changes between driver majors, so the
two move together or the keyboard stops being remapped. kanata is held with `brew pin`, which
the step sets, so a bulk `brew upgrade` skips it. The only way to move it is this.

1. Read the new kanata release's notes and pull request, find the driver version it needs, and
   write its row in `DRIVER` with the package URL from the driver's GitHub release and the sha256
   that release lists. Commit it.
2. Run `src/setup-kanata.sh --upgrade --dry-run`, then `src/setup-kanata.sh --upgrade` from a
   terminal.

The upgrade refreshes Homebrew, stops unless `DRIVER` has a row for the stable version, unpins,
upgrades with cleanup held back so the old binary stays until the new one is proven, then does
everything a normal run does against the new version, installs and activates the paired driver,
restarts both daemons, pins again and reads the grants. A failure anywhere after the unpin still
pins again. `brew cleanup kanata` removes the old version afterwards.

The copy's path does not move with an upgrade, but the grants may still have to be given again.
The Homebrew binary is ad hoc and linker signed, `codesign -d -r-` shows its designated
requirement is its own cdhash and nothing else, and macOS records that requirement with a grant,
so a new build at the same path is not the build that was allowed. Expect to switch kanata off and
on again under both panes after any new binary, an upgrade or a rebuild of the same version, and
the step says so through its closing notes when the grants probe does not answer granted. Whether
macOS really drops the grant on a new cdhash was not measured here, since that needs a granted
binary to replace. The first upgrade measures it.

## Gotchas

- **When the driver daemon is absent, kanata waits ten seconds and lets go.** It logs that the
  output backend is unavailable and releases the input devices, and the keyboard works unremapped. Caps
  Lock then still reaches Olm as F18 through Hammerspoon's own remap, so Hyper keeps working.
  That fallback is why Olm listens for both forms and needs nothing from this module.
- **A refused grant repeats every ten seconds.** KeepAlive restarts kanata after each refusal, so
  the log grows until the grant is given.
- **A copy started by hand fights the daemon.** The step will not load a daemon while a kanata or
  a driver daemon it did not start is running, and says so. Stop the hand started copy first.
- **Never add `danger-enable-cmd`.** A root daemon reads a file this user can write. The step
  proves on every run that the binary rejects `cmd` with the note `kanata was compiled to never
  allow cmd`, and refuses to start the daemon otherwise.
- **Only `kanata.kbd` is hashed.** An `include` of a second file would need the step to hash that
  too, or a change to it would not restart kanata.
- **The checkout must sit where root can read it.** A root daemon is still refused the privacy
  protected folders, Desktop, Documents and Downloads, so a checkout there would leave kanata
  without a config. This was reasoned rather than measured.

## Switching it off

Switching the piece off removes nothing, since nothing in this repository removes what a machine
has. `setup.sh` then skips the step entirely, so the run says only that it skipped it. Running
`src/setup-kanata.sh` by hand on such a machine says what is still there and points here. Removing
it is a one off act on one machine, done with the person's go ahead and recorded in
`decisions/kanata.md`.

```bash
sudo launchctl bootout system/mdj-env.kanata
sudo launchctl bootout system/mdj-env.karabiner-vhid-daemon
sudo rm /Library/LaunchDaemons/mdj-env.kanata.plist /Library/LaunchDaemons/mdj-env.karabiner-vhid-daemon.plist
sudo rm -r '/Library/Application Support/mdj-env' /Library/Logs/mdj-env
bash '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts/uninstall/deactivate_driver.sh'
sudo bash '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts/uninstall/remove_files.sh'
brew unpin kanata
```

The two uninstall scripts are the driver's own, from its README.
