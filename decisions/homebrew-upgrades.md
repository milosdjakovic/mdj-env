# Homebrew upgrades, and why setting a machine up does not perform one

Status. `src/install-homebrew-packages.sh` installs what the Brewfile declares and is missing,
upgrades nothing, and never touches an app Homebrew did not install. Moving something already
present to a newer version is a deliberate act taken on its own.

## Now

The step's guarantee is that everything the Brewfile declares is on the machine. That is the
whole of it, and it is what every later step depends on. Whether a thing present is the newest
version of itself is a different question, and nothing in this repository is pinned to an
answer to it, so a setup run has no reason to change one on the way past.

`brew bundle --no-upgrade` is the flag that separates the two. A missing formula or cask is
installed, a present one is left at whatever version it is. Upgrading is `brew upgrade`, run
when upgrading is the thing being done and when there is somebody at the keyboard for the
password a cask may ask for.

This is the same shape as the Neovim bootstrap, which used to run a sync that updated every
plugin as a side effect of setting a machine up and now installs and restores instead, with
updating left as a deliberate act recorded by committing the lockfile.
`decisions/neovim-lockfile-pin.md` has that one.

A cask whose app already sits in `/Applications` or `~/Applications`, put there by hand
rather than by Homebrew, is skipped through `HOMEBREW_BUNDLE_CASK_SKIP` with a note the run
repeats at the end. `brew bundle` installs every cask with `--adopt` and offers no way to turn
it off, adopting claims the existing app as part of the install, and a failure later in the
same install rolls back everything the install claimed, so the app is deleted. The app being
there already is the whole of this step's guarantee, so skipping meets it. Without jq the
artifacts cannot be read and every cask not yet installed is held back to a later run instead,
since holding back is safe and adopting blind is not.

## Rejected

- **Leaving the upgrade in and letting the run abort.** 2026-09-17. It is what happened, and
  the failure was legible, which is the trap doing its job rather than an argument for the
  behaviour. A machine that already had the declared cask met the guarantee in full and still
  lost fourteen later steps to a version bump none of them cared about.
- **Keeping the upgrade and running the step under a terminal that can ask for a password.**
  2026-09-17. It makes a setup run depend on somebody being there to type, for a job the run
  did not need to do. The password is a symptom. The upgrade not belonging here is the reason.
- **A separate step that upgrades, run later in `setup.sh`.** 2026-09-17. Same thing with more
  moving parts. It would still upgrade on every run, still ask for a password, and the abort
  trap would still stop what came after it.

- **Letting `brew bundle` adopt an app it did not install.** 2026-09-24. It is the default and
  cannot be switched off from the Brewfile, and it is what deleted a Docker.app on a second
  machine. A step that can remove what it never put there is not idempotent.
- **`--force` on the cask install instead.** 2026-09-24. It overwrites the existing app rather
  than adopting it, which trades a deletion on failure for a replacement on success.
- **Only dropping docker-desktop from the Brewfile.** 2026-09-24. It removes the one cask seen
  to fail and leaves the mechanism in place for every other cask with a privileged step.

## Log

- **2026-09-17 00:52.** A second machine ran `setup.sh` and it aborted at step 3 of 17.
  `brew bundle` found a Docker Desktop cask two minor versions behind, started the upgrade, and
  the upgrade wanted sudo to remove privileged helpers, which a shell with no terminal cannot
  give. The abort trap reported it correctly, naming the fourteen steps that never ran. Homebrew
  had already quit the application before failing, so the machine was left with it stopped and
  still on the old version.
- **2026-09-17 00:55.** Changed the step to `--no-upgrade`. The argument is not that the failure
  was badly handled, it is that the step was doing two jobs and only one of them is this layer's.
- **2026-09-24 15:15.** A second machine reran `setup.sh` and lost `/Applications/Docker.app`.
  Docker Desktop was installed there by hand, so `brew bundle` installed the cask with
  `--adopt`, Homebrew adopted the app, and the cask's next step needed `sudo chgrp`, which a
  run without a terminal cannot answer. The failure rolled back every artifact the install had
  claimed, the adopted app included, and purged the Caskroom entry. User data in
  `~/Library/Containers/com.docker.docker` and `~/.docker` survived. The mechanism was read in
  Homebrew 7.0.4's own source, `bundle/installer.rb` adding `--adopt` for any cask and
  `cask/installer.rb` reverting every installed artifact on failure. The step now skips such a
  cask. Tested against a sample Brewfile on this machine, where Chrome and Slack, installed by
  hand, were skipped, Hammerspoon, installed by Homebrew, and IINA, absent, were passed through,
  and a simulated machine without jq held back every cask not yet installed.
