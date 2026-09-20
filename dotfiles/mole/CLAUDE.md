# mole Configuration

There is none yet, and that is the whole point of this file.

`mole` is a disk and system maintenance CLI, `tw93/Mole`, a Homebrew core formula with a `mo`
alias. This module exists so the dependency layer knows the machine needs it. Before this
package, mole was installed here by hand and was a brew leaf in daily use, and nothing in the
repository had ever heard of it, so a fresh machine would not have got it and the gap would
have surfaced months later.

## Why a module with nothing in it

mole reads two files and writes both of them itself, through its own interactive commands.
`mo clean --whitelist` writes `~/.config/mole/whitelist`, the caches it must not delete, and
`mo purge --paths` writes `~/.config/mole/purge_paths`, the directories it scans for project
build artifacts. There is also `whitelist_optimize` for maintenance items, and a legacy
`whitelist_checks` it still reads.

Neither file exists on this machine, because no whitelist and no scan path has ever been
chosen. Shipping either one to give this package something to stow would be writing a choice
nobody made, into a tool whose job is deleting things. So the package declares and documents
and stows nothing, and it is not in the stow list in `src/setup-stow-dotfiles.sh`.

Both files are plain text read line by line, and mole's own README says to copy a path into the
whitelist by hand, so a version controlled one is supported rather than a trick. The day a
whitelist is worth keeping, it moves under `.config/mole/` here and this package joins the stow
list.

## What has to happen on the day it is stowed

`~/.config/mole` needs a `NO-FOLD` declaration, and this is the part that is easy to miss.
Alongside the two config files mole writes `mole_debug_session.log` into that same directory,
and older versions wrote `mole.log` and `operations.log` there too, both of which are sitting
in it on this machine right now. Stow folds a directory into one symlink when the path does not
exist and one package supplies it, so without the declaration every one of those lands in this
checkout. That is exactly the failure `decisions/stow-folding.md` records for herdr.

Everything else mole writes is already safe. Caches go to `~/.cache/mole` and current logs to
`~/Library/Logs/mole`, neither of which this package supplies.

## Full Disk Access, and why it is not declared as a grant

mole checks for Full Disk Access internally, `lib/core/ui.sh` carries a `has_full_disk_access`
function that answers granted, denied or unknown. It is deliberately not declared as a `grant`
here.

The reason is the one the root `CLAUDE.md` already gives. macOS answers a permission question
for the process that asks, so a probe run from a setup script answers about the terminal it
runs in and not about mole, and it would report granted on a machine where mole is refused. A
check that lies is worse than no check. mole also degrades rather than breaks without the
grant, so there is nothing that stops working and needs reporting.

If it is ever wanted as a real gate, it needs a `grants-probe` at this package root that asks
mole itself, the way the Hammerspoon module's prober asks the running Hammerspoon, since only
the program can answer for itself.

## Things it will delete

`clean`, `uninstall`, `purge`, `installer` and `remove` can all delete files, and `mo analyze`
moves what you select to the Trash after confirming. `--dry-run` previews and `--debug` explains.
Run it without `sudo`, it asks for administrator access only where it needs it.
