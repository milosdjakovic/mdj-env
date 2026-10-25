# Homebrew owned by another account

Status. Where Homebrew belongs to another account, a run borrows the prefix with chown for its duration and hands it back to the owner when it ends, however it ends, from `src/lib/brew.sh`.

## Now

`setup.sh` calls `mdj_brew_borrow` after the Homebrew step. When `brew --prefix` belongs to
another account it writes that owner and the current list of `/Applications` to
`~/.local/state/mdj-env/`, then runs `sudo chown -R` to this account. Its exit trap calls
`mdj_brew_return` before it drops the sudo timestamp, which hands the prefix back, along with any
new app in `/Applications` this account now owns, and removes the note. Only the process that
borrowed returns, so a step inside the run does neither. A step run alone,
`install-homebrew-packages.sh` or `setup-kanata.sh`, borrows and returns for itself. A run that
dies without returning leaves the note, and the next run adopts the loan and returns it.

With no terminal and no sudo timestamp nothing can be borrowed, so the package step stops with
a note, as it would have failed anyway.

`check-dependencies.sh` run alone still asks Homebrew as the caller, so on such a machine it
reports Homebrew packages as not installed when they are. Inside `setup.sh` it runs while the
prefix is borrowed and reads correctly.

## Rejected

- 2026-10-25, making the prefix group writable for every admin account. It is the folk answer
  and Homebrew does not support it, every later install by the owner can reset the modes, and
  it changes another person's install to suit this repository.
- 2026-10-25, handing the owner the Brewfile on standard input. The Brewfile finds
  `src/machine.sh` from its own directory, which standard input does not have.
- 2026-10-25, a second Homebrew in this account's home. Two installs of every formula, and
  Homebrew supports only its default prefix for bottles.
- 2026-10-25, running Homebrew as its owner with `sudo -u`, the first fix, from earlier the
  same day. It worked, and installed kanata, but the owner cannot read this account's home, so
  the package step had to stage a copy of the Brewfile, `src/machine.sh` and `machines/` under
  `/tmp`, every `HOMEBREW_` variable had to be passed across sudo by name, and a cask whose
  installer runs sudo asked for the owner's password rather than the person's own. Milos asked
  for the takeover instead.

## Log

### 2026-10-25 06:22

On Jelenas-MacBook-Pro Homebrew belongs to jelenadjakovic and setup runs as milosdjakovic. The
interactive shell had an alias, `brew` as `sudo -u jelenadjakovic -H brew`, and scripts do not
see aliases, so the package step failed on Homebrew's download lock,
`Permission denied @ rb_sysopen - /opt/homebrew/var/homebrew/locks/...`. kanata, git, lazygit,
libqalculate, mole, docker-desktop and obsidian were never installed, and `setup.sh --only
kanata` installed nothing. The home directory is mode 750, so the owner could not read the
Brewfile either, which is why the package step stages a copy.

### 2026-10-25 06:35

The `sudo -u` helper ran once, on this machine, and installed kanata, still owned by
jelenadjakovic. Milos then asked for setup to take Homebrew over and give it back instead,
which needs no staged copy, keeps the Brewfile reading the checkout, and makes Homebrew run as
the person typing. `src/lib/brew.sh` was rewritten as borrow and return, wired into `setup.sh`,
`install-homebrew-packages.sh` and `setup-kanata.sh`, whose own pin on exit trap became a flag
inside one exit handler so the two cannot replace each other. Tested without a password, that
bash runs the exit trap on Ctrl-C and that a nested step neither borrows nor returns. Not yet
tested with a real chown.

### 2026-10-25 06:53

The first full `setup.sh` with the loan ran from a terminal on Jelenas-MacBook-Pro and finished.
Every path under `/opt/homebrew` belonged to jelenadjakovic again afterwards, the note under
`~/.local/state/mdj-env/` was gone, and git, lazygit, libqalculate and mole, which the failed
runs had never installed, were present. `check-dependencies.sh`, run inside that setup, reported
no Homebrew package as missing.
