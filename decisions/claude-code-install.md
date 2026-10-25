# Claude Code install

Status. Installed on every machine by `src/install-claude-code.sh` from Anthropic's native installer, which updates itself, with no Brewfile line.

## Now

The claude module declares `claude` as required, since the module configures nothing else, and
`DEPENDENCIES.map` maps it as `manual`, installed by `src/install-claude-code.sh`. `setup.sh`
runs that step on every machine. It installs once and then leaves the copy alone, since the
native copy updates itself. The copy lives in `~/.local/share/claude/versions` behind a link at
`~/.local/bin/claude`, and `setup-zshrc.sh` already puts `~/.local/bin` ahead of the Homebrew
prefix on PATH. A leftover `claude-code` cask is reported through `mdj_note` and not removed,
since removing it can need another account's password.

## Rejected

- 2026-10-08, the `claude-code` Homebrew cask. Claude Code switches its own updater off when
  Homebrew installed it, so the copy changes only on `brew upgrade`, and
  `homebrew-upgrades.md` says a setup run never upgrades anything. The cask would therefore sit
  on whatever version the machine first got.
- 2026-10-08, a Brewfile line of any kind for it. The Brewfile is what a fresh machine installs
  by default, and Milos wants Claude Code chosen per machine rather than forced.
  Reopened 2026-10-08, the per machine reason no longer holds, see the log. The cask reason
  above still does, so it is installed by a setup step rather than a Brewfile line.

## Log

### 2026-10-08 11:49

Milos asked for Claude Code to update itself. This machine had the `claude-code` cask at
2.1.286, installed by hand and declared nowhere, although `dotfiles/claude` configures it. The
native installer put 2.1.294 at `~/.local/bin/claude`. Removing the cask needs sudo, since this
Homebrew prefix is owned by another account, so Milos removes it by hand. The declaration and
the map line were added in the same change.

A chooser that installs the opt in extras per machine was proposed and set aside for now. If it
is built, it must not keep the choice in a state file, for the reason `dev-defaults.md` records.
Whether a tool is present is already the record.

### 2026-10-08 12:05

Milos wants Claude Code installed on every machine rather than chosen per machine, so it moves
out of the opt in extras. A Brewfile line is still wrong, since the only Homebrew copy is the
cask that never updates, so `src/install-claude-code.sh` runs the native installer the way
`install-ohmyzsh.sh` runs that framework's own, and `setup.sh` calls it before stow.
