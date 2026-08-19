# Work packet, a README for every plugin

Phase 10 of the build plan, sweeps and the tail, the first of its four items. Written 2026-08-11
against `feat/olm-readmes`. Work in the worktree at `../.worktrees/olm-readmes` on the branch already
checked out there. Never work from the primary checkout, never push, never merge.

This item has its own branch because it touches nothing the other three phase 10 items touch. It
adds new files under `plugins/` and edits no existing file anywhere, so it merges on its own and
neither branch waits for the other.

This packet writes documentation and changes no behaviour. It adds twenty three new files and edits
no existing one. If you find yourself opening a `.lua` file to change it, stop, that is a different
packet.

## What the item is

The build plan says READMEs, every plugin gets its short gist, none repeating its `CLAUDE.md`. The
design says more, at lines 1098 to 1102 of
`docs/superpowers/specs/2026-07-27-hammerspoon-olm-core-and-plugins-design.md`.

> Every plugin also carries its own `README.md`, a short gist for a human rather than a decisions
> record, what the tool is, how it opens, and its keys, in a handful of lines. The split is by
> audience. The `README.md` answers what is this and how do I use it, the `CLAUDE.md` answers why is
> it built this way, and neither repeats the other.

That is the whole specification and it is enough. Three questions answered in a handful of lines,
for a person who wants to use the tool rather than change it.

## The scope, exactly twenty three directories

Every directory directly under
`dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/plugins/` gets one `README.md` at its own root.
They are apptoggler, arithmetic, browsertabs, caffeinate, capture, clipboard, convert, displaymemory,
displayprofiles, dockautohide, emoji, eyedropper, filesearch, keyremap, menusearch, processes,
systemsettings, textcase, vpn, windowcheatsheet, windowleader, windowmanager, and windowmemory.

Nothing under `host/` and nothing under `lib/` gets one. The design says every plugin, and the four
host modules and the chooser atom are not plugins, they are the machinery a plugin is presented
through. A person does not open the launcher, they open a tool with it. Do not add a README to
`host/actionpanel`, `host/hypercheatsheet`, `host/launcher`, `host/queryscope`, or `lib/chooser`,
and do not add one at `Spoons/Olm.spoon/` either.

`plugins/browsertabs/test/README.md` already exists and is a different animal entirely, a record of
what a test suite covers. Leave it alone completely. The new `plugins/browsertabs/README.md` sits
beside the plugin's own files and says nothing about the suite beyond, at most, that one exists.

## The one rule that keeps a README out of the CLAUDE.md's territory

A README carries no reasoning. No why, no because, no history, no alternative that was tried and
rejected, no trap, no measurement, no degradation story. Every one of those is the `CLAUDE.md`'s
job, and twelve of these plugins have a very good one already.

That rule is easier to check than a judgment about overlap, and it is what the design means by a
split by audience. A sentence that would make a person understand the code better rather than use
the tool better does not belong in the file. When you catch yourself writing the word because, the
sentence is in the wrong file.

So the README says what happens, and the `CLAUDE.md` says why it happens that way. Both may name the
same feature, and that is not repetition. The clipboard README saying that media is kept and pasted
back is not a repeat of the clipboard's reasoning about how it stores media, it is the same subject
answered for a different reader.

Eleven of these plugins have no `CLAUDE.md` at all, which are apptoggler, capture, clipboard,
displaymemory, eyedropper, keyremap, menusearch, systemsettings, windowcheatsheet, windowleader, and
windowmanager. There is nothing to avoid repeating there, and that is exactly where the temptation
to write the missing decisions record will be strongest. Resist it. A README is a handful of lines
whether or not a `CLAUDE.md` sits beside it, and writing one of those eleven is not in this packet.

## Where each of the three answers comes from

Read the code, not the prose. Every fact in a README is verifiable in a file, and a README that
inherits a wrong claim from a stale comment is worse than no README.

What the tool is comes from the plugin's own `init.lua` and whatever files it loads, its public
surface and what those functions actually do.

How it opens comes from the composition root. Search
`dotfiles/hammerspoon/.hammerspoon/init.lua` for the plugin's `registry.register` block, which is
one per registered tool and carries its `open`, its launcher `row` with the category it appears
under, whether it is `hosted`, whether it declares a `scope`, and any `commands`. Twelve of the
twenty three are registered tools and eleven are not, so read rather than assume.

Its keys come from `dotfiles/hammerspoon/.hammerspoon/config/keys.lua`. The tool's own entry there
carries the chord, the description, the glyph, and any launcher aliases, and its context block,
found by the `name` matching and a `when` predicate, carries the bindings that work while its list
is open, each with its own `description` already written in a person's words. Use those descriptions
rather than inventing new words for the same actions.

A plugin that opens nothing and binds nothing says so plainly, and there are several. Some are
reached only as a row inside another list, some run entirely by themselves with no key anywhere. An
honest sentence saying it runs on its own and has no key is a complete answer to two of the three
questions, and it is far more useful than a paragraph pretending otherwise.

## Shape and length

One heading, the plugin's name as it is already written at the top of its `CLAUDE.md` where one
exists, otherwise the name as the registry knows it. Then prose. No sub headings, no tables, no
bullet lists, and no more than twenty five lines in total. Most should be nearer ten.

An illustrative shape, for vpn. Verify every fact in the code before writing the real one, since
this example was written from a quick read and is here for its shape rather than its content.

    # Vpn

    Picks a Mullvad relay and connects to it. The list is cities with the connect and
    disconnect action pinned above them.

    Opens on Hyper and P, appears in the launcher under Network, and can be searched
    without leaving the launcher by typing v or vpn.

    While the list is open, j and k move, i confirms, and x closes it. Typing filters.

The repository writing rules apply to every line, no colons, no semicolons, no hyphens or dashes,
periods and commas only, plain flowing prose. Existing identifiers and key names keep their form.

## Two things that will fail the reconciler

A README must never tell anyone to install anything. `src/check-dependencies.sh` matches an install
verb across every file type under `dotfiles`, precisely because the two real leaks it was written
for were both help text, and a README naming a tool the plugin needs is the obvious next one.
`DEPENDENCIES.map` and the Brewfile are the only places that answer how something is installed. A
backtick span slips past the check by design, so that a document can quote the rule, and using it to
smuggle an instruction through is the letter of the check against its purpose. Do not do it. If a
plugin needs an outside tool, say that it needs it and stop there.

No absolute path in any file, ever. Write a path relative to the repository root or to the file
itself.

## Nothing measures this

No gate can tell a good README from a bad one, and no gate can tell a truthful one from a confident
guess. So the report carries the evidence instead. For each of the twenty three, name the file you
read to answer how it opens and the file and line you read to answer its keys, and say which of the
three questions the plugin genuinely has no answer to.

Say plainly, per plugin, if anything you found contradicts its `CLAUDE.md` or a comment in the root.
A README sweep reads every plugin from a user's angle for the first time, which is the one moment a
stale claim is easy to spot. Do not fix it, this packet changes no code, report it.

## What not to change

No `.lua` file. No `CLAUDE.md`. No `DEPENDENCIES` manifest, no `dependencies` file, and no
`.stow-local-ignore`, since a README is meant to travel into the home directory alongside the code
the same way the BrowserTabs test README already does. No `test/inventory.lua` and no golden, since
a README is invisible to the snapshot and adding it there would measure the file system rather than
the configuration. No `Brewfile` and no `DEPENDENCIES.map`.

## Gates

`test/units.sh` from `dotfiles/hammerspoon/.hammerspoon` still passes at 251 assertions. It cannot
be affected by this packet, which is the point of running it.

`src/check-dependencies.sh` from the repository root passes with 0 warnings and the tree is clean
afterwards. This is the gate that matters here, since the install verb scan reads the files this
packet writes.

`test/inventory.sh --check` once, with a five minute timeout, and the diff must be empty. Once
rather than three times because nothing here can affect it, and a single run proves that.

`luac -p` is not applicable, no Lua is touched.

Do not live test anything and do not take the devlock.

## Deliverable

This packet committed first. Then the READMEs in four commits, so review can start before the last
is written. Take them alphabetically, apptoggler through convert, then displaymemory through
filesearch, then keyremap through textcase, then vpn through windowmemory. Each commit message names
what the batch covers.

Every message ends after a blank line with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope. Do not merge.

## Hazards

Never run `bin/hs-devlock` yourself. `test/inventory.sh` takes the lock and gives it back, and
killing it mid run strands the lock and blocks the user, which is why it gets five minutes. Never
call `hs.logger.setGlobalLogLevel`. Never pass an angle bracket inside inline Lua to `hs -c`. Never
call `hs.reload` inline, schedule it with `hs.timer.doAfter` and poll `hs.configdir`. Never run
`git reset`, `git checkout` on a path, or `git stash` to clean the tree, read `git status` and report
instead.
