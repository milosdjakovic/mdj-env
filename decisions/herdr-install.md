# herdr install

Status. Installed where the herdr piece is on by `src/install-herdr.sh` from herdr's own installer, which updates through `herdr update`, with no Brewfile line.

## Now

The herdr module declares `herdr` as required, and `DEPENDENCIES.map` maps it as `manual`,
installed by `src/install-herdr.sh`. `setup.sh` runs that step through `step_if herdr on`, after
the Claude Code step and before stow. It installs once and then leaves the copy alone, since
`herdr update` moves it from then on, on the stable channel unless `herdr channel set preview`
says otherwise. The installer checks the binary against the SHA-256 in herdr's release manifest
and puts it at `~/.local/bin/herdr`, which `setup-zshrc.sh` already puts ahead of the Homebrew
prefix on PATH. The step knows nothing about Homebrew. A formula left on a machine from before
is removed by hand, once, as a one off act on that machine.

## Rejected

- 2026-11-03, the `herdr` Homebrew formula. herdr refuses `herdr update` on a Homebrew install
  and says to run `brew upgrade herdr`, and `homebrew-upgrades.md` says a setup run never
  upgrades anything, so the formula would sit on whatever version the machine first got.
- 2026-11-03, removing a leftover formula from the setup step, the way
  `src/install-claude-code.sh` removes its cask. Rule 4 in the root AGENTS.md says an uninstall
  is never a setup step, so the step reports the formula instead.

## Log

### 2026-11-03 11:45

Milos ran `herdr update` and got "self-update is disabled for Homebrew installs; run
`brew update && brew upgrade herdr`". This machine had the formula at 0.9.5. herdr's install
docs say `herdr update` is only for installs made by `https://herdr.dev/install.sh`, and that
Homebrew, mise and Nix installs update through their package manager. The installer script was
read before anything ran: it fetches `https://herdr.dev/latest.json`, the same manifest
`herdr update` reads, checks the checksum and installs to `$HERDR_INSTALL_DIR`, defaulting to
`~/.local/bin`. The Brewfile line, the map line and the module's stated origin moved in the same
change. Milos installs with the installer and removes the formula by hand on this machine.

### 2026-11-03 11:55

`src/setup-herdr-plugins.sh` found herdr through PATH, and on a fresh machine the shell running
`setup.sh` may not have `~/.local/bin` yet, since only the generated `.zshrc` adds it. It would
then skip the plugin with "herdr is not installed". The script now puts `~/.local/bin` first on
its own PATH.

### 2026-11-03 12:10

The installer's copy went onto this machine and `herdr update` answered "already up to date
(0.9.5)". Milos asked for the repository to keep only the native installer, so the step no
longer looks for a leftover formula or reports one, and it no longer sources `lib/backup.sh`.
The formula on this machine is removed by hand, since Homebrew here belongs to another account.
