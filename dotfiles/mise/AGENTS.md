# mise Configuration

mise is the one place language runtimes come from on this machine. `.config/mise/config.toml`
is the global config, stowed to `~/.config/mise/config.toml`, and `decisions/runtime-versions.md`
holds what was tried and rejected, read it before changing anything here.

## Which machines

This package is optional per machine. `MACHINES` at the repository root turns it on, and it is
off by default. Where it is off the package is not stowed, the Brewfile skips mise, the install
step is skipped, and the shell does not activate mise, because `.zshrc.custom` activates it only
when `~/.config/mise/config.toml` exists. `decisions/machine-profiles.md` has the mechanism.

## What it manages

python, ruby, node, go, rust and uv, plus the tool groups below, one default version each, written as the major or minor
rather than an exact release. Python lists three. The first is the default and the rest are on
PATH as `python3.13` and `python3.12` for projects that pin them.

The shell activates mise in shims mode, from `.zshrc.custom` in the zsh package, so a tool
resolves its version from the directory the process runs in rather than the one the shell
started in. One consequence worth knowing is that `[env]` values reach a program only when it
is started through a shim, which is why uv is a mise tool rather than a Homebrew one, since
the uv settings below would otherwise never reach it.

## Tool groups, and which machine takes which

Runtimes are in `config.toml` and every machine that takes mise gets all of them. Commands run
from any directory are in groups instead, one file each, `config.dev.toml` for package managers
and project tooling, `config.work.toml` for client work, `config.personal.toml` for personal use.
The `tools` row in `MACHINES` names the groups a machine takes, alphabetical and comma separated,
or `none`. `src/install-mise-tools.sh` turns that row into `miserc.toml`, the file mise reads
before any config, whose `env` list loads `config.<group>.toml` for each group named. miserc.toml
is generated and ignored by git, since it is one machine's answer and lands in this checkout
through the fold. Moving a machine between groups is changing its row and running the step again.

A tool goes into the group that says who needs it, and a new group is a new file plus its name in
the `tools` default row comment. A group a machine does not take leaves its shims refusing to run
with no version set, rather than running something unlisted.

## Changing a version

Edit the line here, or run `mise use -g <tool>@<version>`, which writes this same file through
the folded symlink, and then commit. `mise install` brings the machine in line. A setup run
installs what is missing and never moves what is present, so upgrading stays a deliberate act,
`mise up` inside the prefix or a new prefix written here.

A project pins its own version with `mise use <tool>@<version>` in its directory, or with an
idiomatic file, `.python-version`, `.ruby-version`, `.nvmrc`, `.node-version`, or
`rust-toolchain.toml` for rust, which rustup reads itself.

## Python and uv

uv still owns projects, lockfiles, venvs, `uv run` and `uv tool`. It is held to the
interpreters mise installed by `UV_PYTHON_DOWNLOADS=never` and `UV_PYTHON_PREFERENCE=only-system`.
Both are needed, since forbidding downloads alone still lets uv prefer a build it fetched
earlier. The cost is that a project pinning a Python mise does not have fails until that version
is added, with `mise use -g python@3.11` appending it beside the others, or installed for that
project alone.

## Folding

`~/.config/mise` is one stow symlink into this checkout, on purpose, and the package declares no
`NO-FOLD`. mise keeps installs, shims and state under `~/.local`, so the only file it writes in
this directory is the config, and a `mise use -g` should land in the repository.
