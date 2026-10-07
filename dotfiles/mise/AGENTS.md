# mise Configuration

mise is where language runtimes and the commands run from any directory come from, on every
machine that takes it. `decisions/runtime-versions.md` holds what was tried and rejected, read it
before changing anything here.

## Which machines

This package is optional per machine. `MACHINES` at the repository root turns it on, and it is
off by default. Where it is off the package is not stowed, the Brewfile skips mise, the install
step is skipped, and the shell does not activate mise, because `.zshrc.custom` activates it only
when `~/.config/mise/config.toml` exists. `decisions/machine-profiles.md` has the mechanism.

## Three files, three questions

`TOOLS` at this package root is the catalog. Every tool any machine may take is defined once, with
its mise name, its version and the command capture looks for. It knows nothing about machines, and
it is repo only, never stowed.

The `tools` row in `MACHINES` is each machine's pick list, catalog names separated by commas,
alphabetical, with no spaces, or `none`. It knows nothing about versions.

`.config/mise/config.toml` is how mise behaves on every machine, the version file support and the
two uv settings. It lists no tools.

`src/install-mise-tools.sh` is the only place that joins the catalog and a row. It writes
`~/.config/mise/conf.d/machine.toml`, which mise loads beside `config.toml`, and runs
`mise install`. The file is regenerated on every run and never committed. Catalog rows that share
a mise tool merge into one list in catalog order, so the first python row is the default and the
others are on PATH as `python3.13`, `python3.11` and so on. A name the catalog does not define
stops the step with that name.

## Adding a tool, and changing a version

A new tool is one row in `TOOLS`, then its name in the rows of the machines that want it, then
the step again on each of them. A new version is the row's version column, after which every
machine that picked the tool follows on its next run. Never add a tool to `config.toml` and never
run `mise use -g`, since both would give every machine what one machine asked for. A tool one
project needs belongs in that project.

A setup run installs what is missing and never moves what is present, so upgrading stays a
deliberate act, `mise up` inside the prefix or a new prefix written in the catalog. Dropping a name
from a row leaves the tool installed, with its shim refusing to run because no version is set.

A project pins its own version with `mise use <tool>@<version>` in its directory, or with an
idiomatic file, `.python-version`, `.ruby-version`, `.nvmrc`, `.node-version`, or
`rust-toolchain.toml` for rust, which rustup reads itself.

## The shell, shims, and environment values

The shell activates mise in shims mode, from `.zshrc.custom` in the zsh package, so a tool
resolves its version from the directory the process runs in rather than the one the shell
started in. One consequence worth knowing is that `[env]` values reach a program only when it
is started through a shim, which is why uv is a mise tool rather than a Homebrew one, since
the uv settings below would otherwise never reach it.

## Python and uv

uv still owns projects, lockfiles, venvs, `uv run` and `uv tool`. It is held to the
interpreters mise installed by `UV_PYTHON_DOWNLOADS=never` and `UV_PYTHON_PREFERENCE=only-system`.
Both are needed, since forbidding downloads alone still lets uv prefer a build it fetched
earlier. The cost is that a project requiring a Python the machine has not picked fails until the
matching `python3.x` row is in the catalog and in that machine's row. A project that pins with a
`.python-version` file is spared, since mise installs that version the first time it is asked.

## Folding

`~/.config/mise` is a real directory, declared in `NO-FOLD`, with `config.toml` linked into it.
The install step writes `conf.d/machine.toml` there, one machine's answer, and a fold would send
that file into this checkout.
