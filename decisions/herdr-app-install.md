# herdr-app install

Status. The Herdr desktop app is an optional piece, `herdr-app`, off by default, installed once by `src/install-herdr-app.sh` from Herdr's own installer and updated by the app itself.

## Now

`machines/default/pieces` has a `herdr-app` row, off, and the piece is named like the module so
the reconciler skips the module wherever it is off. Where it is on, `setup.sh` runs
`src/install-herdr-app.sh` right after the herdr step, and the stow step links the `herdr-app`
package. The step looks for the app by its bundle id, `dev.herdr.app`, and runs
`https://releases.herdr.dev/app/install.sh` only when there is none, since running the installer
again updates the app and a setup run never upgrades anything. The installer checks the archive
against the SHA-256 in Herdr's release manifest, puts `Herdr.app` in `~/Applications`, links
`herdr-app` into `~/.local/bin`, and installs herdr-core only when there is none. The app keeps
itself and the core current. The `alt-z` popups run the herdr package's tools, so a machine
with this piece on takes `herdr` too. Switching a fresh machine to the `mdj` layout is still the
one command in `dotfiles/herdr-app/AGENTS.md`.

## Rejected

- 2026-11-12, the package riding on the `herdr` piece, which it did from 2026-11-09. A machine
  that wants the herdr multiplexer does not necessarily want a second terminal host app, and
  Milos asked for the app to be optional on its own.
- 2026-11-12, defaulting the piece on. Like Rex, it is an app a machine should ask for, and a
  machine that never opened it would carry its settings and mods for nothing.

## Log

### 2026-11-12 09:20

Milos installs the app with `curl -fsSL https://releases.herdr.dev/app/install.sh | sh` and asked
for it to be optional. The installer was downloaded and read before anything was wired, 149
lines: it reads `latest.json`, checks the checksum, keeps a certificate signed bundle untouched
and re-signs only an unsigned build ad hoc, moves `Herdr.app` into `~/Applications`, registers it
with Launch Services, and installs herdr-core through the core's own installer only when absent.
`DEPENDENCIES.map` had called the app a download by hand and now names the step. This machine,
Jelenas-MacBook-Pro, has the piece on through `machine.sh set`, and the step found its app and
did nothing.
