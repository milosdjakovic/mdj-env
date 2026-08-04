# Olm, a core layer for the Hammerspoon config, and snippets as its first plugin

## Status

Nothing is built. Fully reverified 2026-08-04 against the tree at `6bd5b8d`, every line citation in
the document checked in one sweep, the phase 0 rescan from the build plan. Of the forty eight
citation instances, about a third held and the rest had drifted, all now corrected. Three findings
from that sweep were material rather than numeric. The paste block in `monitor.lua` roughly doubled
to about 610 lines and is no longer a clean tail, since the Cmd+V walk watcher now sits after it
and stays with the clipboard, recorded in the paste section. The chooser atom grew to 1274 lines
and the core total to about thirty seven hundred. And the clipboard documentation blocks scheduled
to move grew to about 280 lines of the module file's 1531. The next commits to land will drift the
numbers again, so the rule stands, check a citation before trusting it.

The first open decision is settled. The user chose one visible home directory for everything
durable, collapsing three storage roots to two, recorded in the storage section with `~/Olm` as the
proposed name. The build itself remains closed, and a build plan now exists beside this file at
`2026-08-04-hammerspoon-olm-build-plan.md`, holding the phases, the gates, and the orchestration
and model policy.

Nothing is built on purpose rather than by accident. This stays a design until it is deliberately
opened for work, and spoons are still being changed underneath it, so a rescan comes before any
revision and no claim here should be repeated without checking it first.

Two standing rules for the eventual build were set on 2026-08-04 and are recorded at the top of the
order of work. No original spoon is ever destroyed, moved, or edited, new code is built beside the
old with a comment toggle in `init.lua` so both can be tested against each other. And the roles are
split, the architect and QA never writes implementation code, Sonnet 5 agents build from precise
instructions and every result is verified and returned for rework when it falls short.

This file lives in one place, `docs/superpowers/specs/` in this repository, beside the other design
documents. A second copy sat under `Documents/specs/mdj-env/` in the home folder for a while, because
this file was accidentally deleted once while untracked and git had nothing to restore from. That copy
is gone. Two identical files kept in step by hand drift, and a backup nobody remembers to update is
not one. It has been tracked since `f04a21c` on 2026-08-01, so git is the protection now, and the only
exposed material at any moment is whatever revision has not been committed yet.

Two things landed underneath this document while it was being written, the FileSearch scopes and
alias in `8674f78` and the FileSearch preview pane in `5fdae8d`, and both touch conclusions here. One
of them reverses a section outright. Line citations drifted twice in one day, so treat any number in
this document as needing a check before it is trusted rather than after it fails.

This began as a snippets design and grew into something larger, because the question of where
snippets should live turned out to be a question about what this config's core is. Snippets is
still here, but it is now the last part rather than the first, and it is smaller than it was.

This revision added the packaging decision, how a plugin is enabled and disabled, the named value
convention, the full roster of what every spoon becomes, the layout inside `Olm.spoon`, and a
ninth core module for the paste primitives. All of it came out of one question, what shipping olm
to somebody else would actually require, which constrains the design more than any internal
concern does.

It then gained the test scaffold and a gate on every step, since the order of work promised no
behaviour change in three places with nothing able to check it. Two facts were verified against a
running Hammerspoon rather than assumed. That `hs -c` runs Lua 5.4 and can load a module straight
out of the working tree without this checkout being the live config, which is why a unit suite needs
no lock. And that the binding surface is enumerable from this config's own registries but almost
invisible from Hammerspoon's, since `hs.hotkey.getHotkeys()` sees six of it.

Four earlier conclusions in this document were reversed, three on evidence and the fourth because the
rule it rested on was rewritten in the codebase. One rule written in this revision was also corrected
within it. Every reversal is recorded where it happened rather than quietly edited out, since the
reasoning is the useful part.

The parts below are named rather than numbered. They were once phases one through four and the
numbering had already rotted, running one, zero, three, four with no two and with zero after one. The
sequence lives in the order of work at the end, which is the only place it should have lived.

## Problem

Five problems, related by the fact that none of them has an owner.

**No core layer is declared.** Six spoons are mechanisms rather than features, and nothing says
so. `Chooser`, `CanvasPanel`, `CheatSheet`, `ChordKey`, `HyperKey`, and `Dependencies` sit as
siblings of `Vpn` and `Caffeinate`, which are features. A reader cannot tell which of the
thirty four spoons are infrastructure.

**Internal dependencies are invisible.** Nothing records that `Emoji` needs the Chooser, or
that the clipboard needs `CanvasPanel`. The manifest contract covers `path`, `system`, `app`,
`manual`, and `package`, all of them external tools. So the layering above is real, load
bearing, and undeclared, which is exactly the drift that contract exists to prevent.

**Nothing owns where files go.** Five conventions are in use and three are named inside the
spoon that writes them.

- `~/.cache/hs-clipboard`, hardcoded at `Spoons/ClipboardHistory.spoon/manager/init.lua:54`
- `~/Library/Caches/Hammerspoon-Eyedropper`, hardcoded at `Spoons/Eyedropper.spoon/init.lua:44`
- `~/Library/Caches/Hammerspoon-BrowserTabs`, hardcoded at `Spoons/BrowserTabs.spoon/permissions.lua:29`
- `hs.configdir .. "/config/display-profiles.json"`, injected from the root at `init.lua:2525`
- `~/.cache/hammerspoon/filesearch-previews`, declared as data in `config/filesearch.lua:177`

The last two follow the composition root rule the rest of this module lives by, and the fifth
arrived after this document proposed the convention. It is worth reading, because it is not a
problem, it is the answer already being applied. It sits under `~/.cache/hammerspoon`, exactly the
cache root proposed below, it is written with a tilde and expanded by `util.expandHome` so nothing
in the spoon names an absolute location, and its comment says it is kept outside the git tracked
config and beside the other caches. That last clause is aspirational rather than true, since the
other caches are in two different places, which is the whole problem stated from the inside by
somebody trying to do the right thing.

So the storage section below is no longer a proposal. It is finishing a convention the newest code
in the repository already chose, which is the strongest evidence available that the convention is
right.

The defect is unchanged and still the reason to do it. `~/.cache/hs-clipboard` holds regenerable
data, thumbnails and preview PNGs, alongside unregenerable data, `history.json` and up to two
gigabytes of frozen file snapshots. Anything that clears a cache silently destroys the clipboard
history and every snapshot of a file that has since moved or been deleted.

**Remembered ordering is implemented five times.** `BrowserTabs.spoon/recency.lua`,
`Vpn.spoon/init.lua:81`, `Launcher.spoon/init.lua:69`,
`Emoji.spoon/providers/hammerspoon.lua:194`, and `DisplayMemory.spoon/init.lua:78`. BrowserTabs
already pulled its copy into a file of its own, which is the strongest available signal that
something wants to be shared.

**A tool joins the launcher three different ways.** A closure in `actions.special` at
`init.lua:1328`, of which there are about twenty. A query row source in `queryProviders` at
`init.lua:1203`. Or a scope through `QueryScope`. Three contracts for one idea.

**There is no snippet store.** A snippet is a clipboard entry that was authored rather than
captured, the Alfred model. Same data shape, same paste path, and the only real differences are
who wrote it, that it never expires, and that it has a name.

---

# The olm core

## What is already right, and must not be disturbed

Three findings, because each one removes work rather than adding it.

`Chooser.spoon` already owns the docked side panel. It reserves the companion rect
(`providers/native.lua:298`), reports it through `onPositioned`, and fires `onHighlight`. Three
tools use it, the clipboard at `manager/ui.lua:1051`, Processes at `chooser.lua:586`, and FileSearch
at `chooser.lua:414`. Each draws its own content while sharing `CanvasPanel.surfaceElements`, which
`Processes/preview.lua` explains in its header. So the list with a docked pane is already an
atom, split correctly, and there is nothing to extract.

This finding got stronger while the document was being written. `5fdae8d` gave FileSearch a real
preview pane, 650 lines of it plus a 274 line thumbnail renderer, and `8702ea2` taught the atom to
let a trackpad scroll any companion pane. Both landed as changes to the atom and its consumers with
no new abstraction between them, which is what an atom being correctly split looks like from the
outside. A third heavyweight consumer arriving without forcing a redesign is the evidence, not the
original three.

The launcher already takes plugins. `queryProviders` is the contract, `rows(query)` plus an
optional claim on the query, and `Arithmetic` and `Convert` are already plugins in exactly this
sense, two spoons rather than one calculator because they fail differently.

Alternatives are already exposed as references rather than named by strings. The root writes
`spoon.Chooser.matchers.fuzzy` and `spoon.Chooser.matchers.words`, functions the atom exposes
from `match.lua`, with `matcher = false` as a deliberate opt out sentinel. The same convention
runs through `ClipboardHistory.providers`, `BrowserTabs.providers`, the Emoji backends, and the
Vpn providers.

## What goes into `Olm.spoon`

Nine things, six that exist as spoons, two that do not exist at all, and one to be extracted.

| Module | Lines today | Why it qualifies |
|---|---|---|
| `chooser` | 1274 | Every picker is built on it. Already owns the companion pane and the highlight |
| `panel` | 381 | One drawing surface behind preview panes, docked shortcut panels, and both cheat sheets |
| `cheatsheet` | 422 | The shared overlay mechanism, two consumers |
| `chordkey` | 353 | The shared hold and tap engine under every leader |
| `hyperkey` | 238 | The leader modal every context binds into |
| `deps` | 388 | The manifest reader, and what would enforce the new layering |
| `storage` | new | Where files go. No owner today |
| `recency` | new | Remembered ordering, five separate implementations today |
| `paste` | about 610 | Text into the frontmost app. Three consumers today, four with snippets |

That totals about thirty seven hundred lines, which makes `Olm.spoon` about the size of
`BrowserTabs` counting only the core. Worth recording, because the usual failure of a core is that
it becomes a monster, and this one does not. Note that the plugins bundled beside it are far larger
in total, which is fine, since bundling is about distribution and the core boundary is about
dependency direction.

## What looks like core and is not

`QueryScope` is a genuine mechanism and names no tool, but its only consumer is the launcher.
One caller is not a core service, by the rule this repository already applies to indirection,
so it belongs beside the launcher as part of the host.

`HyperCheatSheet` and `WindowCheatSheet` are policy over the `CheatSheet` mechanism, one per
leader. The mechanism goes in and the two configurations stay out.

`WindowLeader` is a consumer of `ChordKey`, not a peer of it.

Everything else is a feature, which means it stays out of the core whether or not it ships in the
same archive. That includes the ones with no launcher presence at all, `DockAutoHide`, `KeyRemap`,
`StageManager`, and `AppToggler`.

## Three categories, not two

Core is the mechanisms. Plugins are the features. The launcher is neither, it is the host, the
surface most plugins appear on, and `QueryScope` belongs to it. Keeping the host separate
avoids the trap of calling the launcher a plugin of itself.

Two axes get confused easily and this document keeps them apart. What a thing is, core or plugin
or host, is a question about which direction the dependency points. Where it ships, inside the
archive or beside it, is a question about how an install fails. A plugin bundled with the core is
still a plugin, because it still depends on the contract and the core still does not name it. If
bundling ever starts letting a plugin reach into core internals, the category has collapsed and
the bundling was the cause.

## Packaging, and why there is no nested spoon

Hammerspoon has no nesting feature. `hs.loadSpoon` calls `package.searchpath(name,
package.path)` and then `require(name)`, and `package.path` holds `.../Spoons/?.spoon/init.lua`.
Because `require` maps dots onto directory separators, `hs.loadSpoon("Olm.Chooser")` would
resolve to `Spoons/Olm/Chooser.spoon/init.lua`, so a plain grouping directory works. What does
not work is a `.spoon` inside a `.spoon`, since the name would have to contain the literal word
spoon.

None of that is needed, because the mechanism is already in use here. `ClipboardHistory.spoon`
is fifteen files across `manager/` and `providers/`, loaded with `loadfile(spoonPath .. name)`,
and the comment at its `init.lua:58` states why, a spoon directory is not on `package.path`. So
`Olm.spoon` is one spoon holding `lib/chooser.lua` and the rest, loaded by path.

One practical gain comes with it. `~/.hammerspoon/Spoons` holds one symlink per spoon, thirty
four of them today, so a new top level spoon needs a restow while a new file inside an existing
spoon does not. Folding the core in means adding a core module stops being a stow operation, and
once the plugins fold in too, by the section below, most new work stops being one.

## Reversal, plugins ship inside olm and are activated from a list

The earlier version of this document said plugins stay outside as sibling spoons, and called
Seal's bundling its weakness on the grounds that a bundled plugin cannot be versioned or dropped
independently. That was reasoned from inside the repository, where every spoon is a symlink and
everything is always the same version. It does not survive the question of shipping.

Hammerspoon has no dependency resolution of any kind. `hs.loadSpoon` calls
`package.searchpath` and finds a directory or does not. There are no versions, no load ordering,
and no compatibility check, and `SpoonInstall` fetches by name without resolving anything. So a
separately shipped `ClipboardHistory.spoon` makes the person installing it the dependency
resolver, and every mistake shows up either as a stack trace at load or, much worse, as a plugin
registering into an older core and misbehaving quietly.

Seal's actual model, checked rather than remembered, is bundling with an escape hatch. Its
plugins live inside `Seal.spoon`, `loadPlugins` activates them by name, and
`plugin_search_paths` defaults to both the spoon directory and `~/.hammerspoon/seal_plugins/`, so
a plugin from outside the bundle is still a first class citizen. That is the right shape and this
design takes it. Bundle the plugins, activate them from an explicit list, and keep the
registration contract public so a plugin nobody bundled loads the same way.

The real objection to bundling is that nobody wants a launcher that starts watching their
pasteboard because they installed a launcher. Activating from a list answers it completely. A
plugin that is not activated is bytes on disk rather than behaviour, and nothing starts that was
not named. The privacy concern is about what runs, and bundling decides only what is present.

There is also a naming problem worth stating plainly. Once the clipboard draws its chooser, its
storage, and its ordering from olm, it is not standalone in any useful sense. Shipping it as a
sibling spoon would be a label rather than independence, and the label is precisely what invites
someone to install it alone and get a broken config.

## Correction, nothing of ours ships on its own

The first attempt at this section proposed a test, whether a plugin drags in a dependency or a
permission that olm does not already need, and concluded that `Convert` and `BrowserTabs` stay
outside. The test is too coarse and the conclusion does not survive it.

`Convert` needs a tool from outside Hammerspoon, and that case is already fully handled. It
declares the tool required in its manifest, the root leaves it out of `queryProviders` entirely
when the tool is absent, and the load summary names it. So a missing tool produces a plugin that is
quietly not there while arithmetic keeps working, which is a degraded install rather than a broken
one. That machinery is the reason the test was wrong, because the graceful path already exists and
bundling does not touch it.

`BrowserTabs` needs Apple Events approval per browser, but those prompts are lazy and arrive on
first use rather than at install. Accessibility it needs too, and so does every hotkey in this
config, so Hammerspoon has already asked before any plugin loads. Its integration suite is a
repository concern and invisible to anyone installing.

The activation list closes the gap entirely. A plugin that is not activated asks for nothing,
starts nothing, and prompts for nothing, so the worst case for a bundled plugin with an unusual
dependency is bytes on disk. The install promise survives in every case.

So everything written here ships inside. The search path exists for plugins somebody else wrote,
which is the case that genuinely cannot be bundled, and that is the whole of what it is for.

## The roster, what all thirty four spoons become

Every spoon is accounted for, because a plan that classifies most of them leaves the rest to be
argued about later, which is how a boundary rots.

**Core, nine modules from six spoons plus three new.** `Chooser`, `CanvasPanel`, `CheatSheet`,
`ChordKey`, `HyperKey`, and `Dependencies` move in as `chooser`, `panel`, `cheatsheet`,
`chordkey`, `hyperkey`, and `deps`. `storage`, `recency`, and `paste` are new, the first two by
the sections below and the third extracted from the clipboard.

**Host, three spoons.** `Launcher` is the host. `QueryScope` is the alias grammar, the word
followed by a space that hands the list to one tool, and it belongs to the host because the host
is its only consumer. `HyperCheatSheet` is the overlay content for the host's own leader.

**Plugins with a surface, fourteen spoons plus three that do not exist yet.** `Arithmetic` the
calculator, `Convert` the converter, `ClipboardHistory`, `Caffeinate` the keep awake tool, `Vpn`,
`BrowserTabs` the tab search, `Emoji`, `FileSearch`, `Processes` which the docs now
call Local Servers, `TextCase`, `Eyedropper`, `Capture`, `DisplayProfiles`, and `SystemSettings`. The three new ones are `apps`, extracted from
the launcher, `snippets`, and menu search, which is the odd one out because it has no spoon at all
and lives in the root today as `menuSearchSurface` in the `choosers` registry at `init.lua:2199`.
Under one plugin contract it stops being a root resident and becomes a plugin like the others.

**Plugins that are pure behaviour with no surface, eleven spoons.** `AppToggler`, `DockAutoHide`,
`KeyRemap`, `StageManager`, `TerminalHandler`, `DisplayMemory`, `WindowMemory`, `WindowManager`,
`WindowLeader`, `WindowCheatSheet`, and `WorkspaceEngine`. These bundle and activate like any
other plugin and implement none of the surface methods, which is the point of every method being
optional. They are the reason the contract must not require a `rows` function.

That is six plus three plus fourteen plus eleven, thirty four, with nothing left over.

## What decides core membership, since reusable is not the test

Two spoons make the rule necessary. `SystemSettings` describes itself as the reusable mechanism
for reaching macOS System Settings, and `WindowManager` is window positioning used by the leader
and by launcher rows. Both are reusable. Neither is core.

Core is infrastructure in four kinds, input, presentation, persistence, and output, plus the
dependency contract. `chordkey` and `hyperkey` are input, `chooser`, `panel`, and `cheatsheet` are
presentation, `storage` and `recency` are persistence, `paste` is output, and `deps` is the
contract. Anything shaped like a domain is a plugin even when two things use it, because a domain
mechanism pulls domain knowledge into the core and the core stops being reusable in the only sense
that matters, that it names nothing above it.

The one caller rule settles the two examples anyway. `SystemSettings` is reached only from the
root, at `init.lua:1221`, `1269`, `1327`, and `1346`, all of it launcher wiring. `WorkspaceEngine`
is the same, only the root uses it and it depends on `AppToggler` and `WindowManager`, so it is a
coordinator rather than a mechanism. Reusable and shared are not the same claim, and the second one
needs a second consumer that is not the composition root.

## The layout inside `Olm.spoon`

```
Spoons/Olm.spoon/
  init.lua              the api version, the registry, the activation list, the search path
  DEPENDENCIES          generated, as today
  CLAUDE.md
  lib/                  chooser, panel, cheatsheet, chordkey, hyperkey, deps, storage,
                        recency, paste
  host/                 launcher, queryscope, hypercheatsheet
  plugins/
    apps/  arithmetic/  clipboard/  snippets/  caffeinate/  vpn/  browsertabs/
    emoji/  filesearch/  processes/  textcase/  eyedropper/  capture/  convert/
    displayprofiles/  systemsettings/  menusearch/
    apptoggler/  dockautohide/  keyremap/  stagemanager/  terminalhandler/
    displaymemory/  windowmemory/  windowmanager/  windowleader/  windowcheatsheet/
    workspaceengine/
```

Each plugin keeps the directory it has today, its own `CLAUDE.md` where it has one, and its own
declarations beside the code that needs them, so only the load path changes. Loading is
`loadfile(spoonPath .. name)` throughout, the pattern `ClipboardHistory.spoon` already uses for
fifteen files and explains at its `init.lua:58`.

No core module becomes olm, and the chooser is the one most likely to be mistaken for it since it is
the largest and every picker is built on it. It becomes `lib/chooser.lua`, reached as `olm.chooser`,
one of nine. Olm is the container, the core plus the host plus the bundle, and it is deliberately not
a renamed chooser, because the moment `olm` and `olm.chooser` mean the same thing the other eight
modules have nowhere to live.

The rename is cheap because the public surface is tiny. `Chooser.spoon` exposes four things,
`init`, `configure`, `new`, and `matchers`, at `init.lua` lines 58, 66, 78, and 41. Every consumer
either takes the module itself as an injected factory from the root or names a matcher on it, so the
migration is `spoon.Chooser` becoming `olm.chooser` at each site with no change in shape. No tool
learns anything new, which is the test for whether a move is really a move.

The composition root stays where it is and keeps doing what it does. It is not absorbed into olm,
because the root is this machine's policy and olm is the reusable part, and folding a machine's
choices into the shipped artifact is the one move that would undo the whole exercise. What changes
is that the root asks olm for plugins by name rather than calling `hs.loadSpoon` thirty four times.

One consequence to plan for. `hs.loadSpoon` is what the root calls today, thirty four times, and
each one currently gives a global under `spoon.`. After this there is one `hs.loadSpoon("Olm")` and
everything else is reached through olm, so every `spoon.Something` reference in the root changes.
That is mechanical and large, roughly the whole wiring section, and it is the reason the move is one
pass rather than a gradual migration. Two ways to reach a plugin would be worse than either.

## The one thing nesting quietly breaks

The hammerspoon manifest is generated rather than written, and the generator derives who owns a
declaration from where the file sits. `dependencies-collect` finds every declaration with one
recursive `find` at line 74, which keeps working, and then `owner_of` at lines 80 to 95 takes the
first path segment under `Spoons/` and strips `.spoon` from it. Its own comment says so, that under a
spoon the first path segment names the spoon.

After nesting, the first segment is `Olm.spoon` for every declaration in the tree. So every consumer
in the generated manifest collapses to `Olm`, or to `Olm/mullvad` for a per file declaration, and the
consumer column stops naming who needs the tool. That column is the entire reason the manifest has
six fields instead of five, and nothing would fail. The file would regenerate, the reconciler would
pass, and the contract would be quietly worthless.

There is a live example to test against rather than a hypothetical one. `8674f78` added
`Spoons/FileSearch.spoon/thumbs.dependencies`, declaring `qlmanage` as an optional `system` tool
beside the only file in that spoon that renders a picture. Today that reports `FileSearch/thumbs`.
After nesting it would report `Olm/thumbs`, which names nothing useful, and the declaration's own
comment about being placed beside the one file that needs it would become false.

The fix is small. Strip a leading `Olm.spoon/plugins/`, `Olm.spoon/host/`, or `Olm.spoon/lib/` before
taking the first remaining segment, so `plugins/filesearch/thumbs.dependencies` still reports
`filesearch/thumbs`. Worth writing down because it is the kind of defect that a passing check hides,
and the only reason it surfaced here is that the generator was read rather than assumed to be path
agnostic.

Two smaller notes in the same family. `src/check-dependencies.sh` is documented as module agnostic
and reads manifests without knowing any module by name, so it needs nothing. And the checks that
match every file type under `dotfiles` for install commands and hardcoded prefixes keep working
unchanged, since they walk paths rather than a spoon list.

## The version check that stands in for a package manager

Bundling makes the first party versions consistent by construction, one archive and one version
number rather than a compatibility matrix maintained by hand and checked by nobody. It does
nothing for a plugin loaded from the search path, which is the case that will actually break.

So olm exposes an api version and a plugin declares the one it was built against, and the core
refuses to register a mismatch with a log line naming the plugin and both numbers. One integer
and one comparison. Since there is no package manager to hold a version constraint, the runtime
is the only place the constraint can live, and this is the same reasoning as the validation step
in the core API rules below.

## What bundling costs, recorded honestly

A bundled plugin cannot be released on its own cadence, and somebody who wants only the clipboard
downloads the launcher with it. Both are real. Neither is worth the install failures that
independent distribution buys in a runtime with no resolver, and if a plugin ever genuinely needs
its own cadence, the search path already lets it leave.

## Enabling and disabling a plugin, and why not at runtime

The activation list wants a way to edit it, and the obvious wish is a plugin roster in the
launcher where each row toggles. Yes to the roster, no to toggling live, because those are two
features and only one of them is cheap.

Turning a plugin off at runtime means an honest teardown, unbinding hotkeys, stopping eventtaps
and watchers, removing menubar items, deleting canvases, and cancelling timers. Seven of the
thirty four spoons define `stop` today, and that is not an oversight. The lifecycle contract at
`CLAUDE.md:476` says `start` and `stop` exist only when a spoon owns live resources and
explicitly tells you not to add an empty one. So a toggle switch means writing twenty seven
teardowns whose only consumer is that switch, in a language with no way to check that any of them
is complete. A teardown that leaks leaves a hotkey firing into a plugin that is supposed to be
off. That is single caller ceremony with a silent failure mode attached, which is the exact thing
the design principles reject.

Reloading gets nearly all of it for almost nothing. The activation list is data, persisted in
`hs.settings`, read once at load. A toggle writes the setting and reloads. Discarding the whole
Lua state is the only teardown guaranteed to be complete, so no spoon grows a `stop` it does not
otherwise need. A reload is already the normal rhythm here since the pathwatcher at
`init.lua:2558` fires on every file save, and it has to be scheduled on a short timer rather than
called inline, the same deferred pattern the launcher already uses to run a chosen row after its
chooser tears down.

The surface is a scope rather than a single row, since the launcher already carries a
`settingsPane` row kind for macOS panes and a roster is the same idea pointed inward. One
interaction question is genuinely open. A chooser hides on accept while a toggle list wants to
stay up, so either the scope reopens itself after a flip or accept writes and closes. The native
provider has `refresh` and `setQuery`, so staying open is possible, it just needs deciding rather
than discovering.

Where the line sits matters more than the surface. Only the activation list is a setting.
Per plugin choices, which VPN row sits above the recency ordered ones, which matcher a picker
uses, stay in Lua in the composition root, because those are code and ordering rather than
booleans. The moment a preferences screen starts holding those, this has become a configuration
framework, and the config file that already exists is a better one.

Worth knowing what the roster buys, because for the author it is close to nothing. Editing one
line in `init.lua` and saving already reloads, faster than opening a chooser. The roster exists
for people who will not open a Lua file, so it is a shipping feature and it is reasonable to
defer it until there is something to ship.

## Declaring the dependency on core

This is the part that makes a core worth assembling rather than a rename.

A plugin declares which core capabilities it needs, in the manifest it already has, through one
new kind alongside `path`, `system`, `app`, `manual`, and `package`. The root then asks olm for
exactly that slice and injects it. So the declaration is not documentation, it decides what the
plugin receives. And `src/check-dependencies.sh` reconciles declared against used, so a spoon
reaching for the chooser without declaring it is an error, the same class as one hardcoding an
install prefix.

Today `Launcher:configure` takes thirteen separate collaborators and nothing says which are
core. Afterwards it takes a core slice plus its own options, and the list is checkable by a
script.

## The core API rules

Four rules, three of which the codebase already follows.

**Expose alternatives as references, never ask for a name.** `Chooser.matchers.fuzzy` is
already this. A core service offering a choice exposes a table of implementations and the
composition root picks one by reference.

**The caller composes, the service orders.** Most settings that feel necessary are not. Vpn
pins an action row above its cities and orders the cities by recency below. That is not a
recency setting, it is Vpn building a list with one row on top. BrowserTabs is the same case
inverted, its Settings row pinned last. `BrowserTabs/recency.lua` already documents the rule,
that the caller decides the resting order and the file knows only recency. Keeping that rule
when it moves into core means a whole category of configuration never appears.

**What remains is a number or a function.** For recency that is where to persist, which core
derives from the plugin name so the plugin passes no key at all, a cap, and how to identify an
item. That last is a function, since Vpn keys by city, BrowserTabs by bundle id plus URL, and
the launcher by kind plus name. Strategy, injected, not a setting.

**Validate in `configure` and refuse what is not recognised.** Lua offers no check, so a wrong
value silently takes the default, which is the real danger. A typo against a reference yields
nil, and nil must be rejected loudly. This is the runtime validation step that stands in for a
compiled interface.

## Named values, and who owns the set

The first rule above is already followed in one place and nowhere else, so it needs finishing
rather than inventing. `init.lua:822` wires `matcher = spoon.Chooser.matchers.fuzzy`, a reference
handed out by the module that defines the behaviour, exposed from `match.lua` at
`Spoons/Chooser.spoon/init.lua:41`. Everything that selects from a closed set should look like
that.

The matchers stay under the chooser rather than becoming a core module of their own. `match.lua` is
177 lines holding `fuzzy`, `substring`, and `words`, and every consumer reaches them as chooser
config, including the two that override the shared default, the clipboard and `Processes`. No
consumer outside a chooser exists, so a tenth module would be a rename with no second caller.

The live counterexample is placement. The root writes `placement = "below"` at `init.lua:945` and
`placement = "center"` at `init.lua:2143` and `init.lua:2365`, and `CanvasPanel.spoon/init.lua`
compares that string against literals in six places, at 180, 181, 218, 221, 224, 238, and 274.
The accepted set is five values, documented in a comment at line 55. Write `"bellow"` and nothing
errors, every comparison falls through, and the panel lands wherever the final arm puts it. That
is the whole argument for named values, and it is a correctness argument rather than a tidiness
one.

**The set lives on the module that defines the behaviour, not centrally.** A central
`olm.settings.vpn` branch would mean the core names a plugin, so adding a plugin edits the core,
which is the leak the layering exists to prevent. `Vpn` exposes its own set, olm exposes sets only
for the mechanisms it actually implements, `olm.chooser.matchers.fuzzy`,
`olm.panel.placement.below`, and `olm.recency.order.byUse`, and the composition root is the one
place allowed to know both names. The set is named after the module that owns it, never invented as
a shorter word beside it, because a second naming scheme is a second thing to keep in sync.
Uniformity comes from every module following one convention rather than from one table holding
everything.

**Do not call it settings.** That word is carrying the persisted activation list, and
`hs.settings` on top of that. These are named constants in code, so name them for what they
select.

**The value is what the mechanism consumes, never a label.** A function, a small table, or an
opaque token the module recognises. That is what makes validation possible, since `configure` can
test membership in its own set and, on a miss, raise naming the valid keys. A typo then becomes a
load error that tells you the answer.

**Only closed sets.** A history cap of fifty, a timeout, a path, a hotkey. There is no set to
belong to, so a namespace adds a lookup and buys nothing. This is the same rule that keeps the
configuration from growing, stated one level down.

**The persistence boundary needs stable ids.** `hs.settings` cannot store a function or a table
identity, so the activation list and any persisted choice keeps a short string id and resolves it
through the owning module's set at load. The string then lives only in the store and never in
configuration, and an unknown id at load is a named warning rather than a silent default. Worth
settling before the roster is built, since the roster is the first thing that persists a choice.

`src/check-dependencies.sh` already proves the enforcement pattern. A sibling check that flags a
bare string passed to a known enumerated option is the same reconciler idea, catching the drift
rather than trusting discipline. Optional, and cheap once the convention is uniform enough for a
grep to be accurate.

## Recency, and the split that matters

`BrowserTabs/recency.lua` is two halves and only one of them is core. `keyFor`, `touch`, and
`order` are generic and become the service. The application watcher, the window title filter,
and the sampler that feed it are browser specific and stay where they are.

The five callers convert. Watch `DisplayMemory` and `WindowMemory` in particular, since both
are hand rolled remembered state and at least one may shrink to almost nothing.

## Paste, the same split one layer over

`ClipboardHistory.spoon/manager/monitor.lua` is 918 lines and splits the same way recency does,
though the split is no longer a clean tail. The pasteboard watcher and the history capture,
everything up to about line 243, are what the clipboard is and stay in the clipboard plugin. From
the insertion helpers at about 244 through the exports, `M.paste` at 584, `insertText` at 625, the
selection read at 652, `pasteBatch` at 715, `pasteText` at 750, and the read side mirror at 790,
runs roughly 610 lines about putting content into whatever app is in front. The file then ends with
the Cmd+V walk watcher from 858, which exists to end a clipboard paste walk and stays with the
clipboard, which is why to the end stopped being the boundary. The block roughly doubled since this
was first measured, the paste under original name and restore work of `6bd5b8d` landed inside it,
and some of the growth is entry aware, `writeEntry` and the restore machinery know the shape of a
clipboard entry, so drawing the exact line between primitive and entry knowledge is now a real
piece of the extraction rather than a formality.

Three features already use that half, and none of them is the clipboard. `Emoji` takes `pasteText`
through the root at `init.lua:1648`, `TextCase` takes both `pasteText` and the selection read at
`init.lua:1679`, and snippets would be the fourth. So this is a delicate mechanism with three
consumers that currently lives inside one feature, which every other consumer reaches through by
injection from the root. That is the definition of something that wants to be core, and it is a
stronger case than recency because the sharing is already happening rather than being predicted.

The header comment at `monitor.lua:21` already frames it correctly, that a paste is not the only way
in, only the universal one. That sentence is a core module's documentation sitting in a plugin.

Two cautions. This is the most carefully measured code in the config, the `insertText` versus paste
findings, `sequenceDrainDelay`, and the held chord behaviour, and the measurement trail is currently
recorded in the module level `CLAUDE.md` at lines 1006 to 1201. That trail must travel with the code
and not be split from it, which changes the documentation plan below. And the clipboard snapshot and
restore that hides a paste from history is part of the insertion side, so olm ends up owning a small
amount of knowledge about not polluting a history it does not own. Keep that as one commented seam
rather than inventing an abstraction for it, which is what the design rules say to do when one
coupling genuinely belongs inside the reusable part.

---

# Storage roots

Ordered before the rest because everything else assumes it, and because it stands on its own
even if none of the rest is ever built.

## Two roots, the decision landed

One folder for everything is what produced the defect above, so the split is by kind of data
rather than by spoon. This section proposed three roots, a cache, a hidden XDG data root, and a
separate content root, and left open whether the durable two should collapse into one visible
directory in the home folder. The user settled it on 2026-08-04. They collapse.

```
CACHE_ROOT = ~/.cache/hammerspoon    regenerable, safe to delete, costs a rebuild
OLM_ROOT   = ~/Olm                   durable and visible, deleting it loses something
```

Everything durable lives in the visible root, the clipboard history and its frozen files, the
snippet bodies, the usage state, all of it, and it is the directory a person may turn into a git
repository. The name `~/Olm` is the architect's pick, capitalised like the other visible home
directories, and it stays cheap to change until the storage phase lands, since exactly one line
in the `paths` block knows it.

The tradeoff is accepted knowingly. Durable machine state such as `history.json` sits visibly
rather than hidden away XDG style, which buys one obvious answer to where is my stuff and one
directory to back up, at the price of a folder in the home directory that is not hand curated
content. The cache stays XDG style like the nvim, zsh, and lf configs on this machine, since
nobody needs to see a cache. Small preferences stay in `hs.settings`, which is already correct.

## Per spoon underneath, concatenated by the root

The root owns the concatenation and hands each spoon a finished absolute path. A spoon receives
a directory and never sees a prefix, the same rule the dependency contract applies to tools.

```
CACHE_ROOT/clipboard      thumbs, preview PNGs
CACHE_ROOT/eyedropper     the compiled Swift sampler binary
CACHE_ROOT/browsertabs    the permission probe results
CACHE_ROOT/filesearch     rendered previews, already here under a longer name
OLM_ROOT/clipboard        history.json, frozen file snapshots
OLM_ROOT/snippets         the snippet files themselves
```

The `paths` block is pure data in `config/settings.lua`, with the join done in the root,
matching how the overlay display policy is expressed as data and resolved in the root.

## What changes

`ClipboardHistory.manager.configure` already accepts every path as an override, so the
clipboard is wiring only. `Eyedropper` and `BrowserTabs` bake theirs as file locals and each
needs one config field. `DisplayProfiles` is already correct and is the model.

`FileSearch` is the second one already correct and is the closer model, since it is a cache rather
than tracked content. Its path is data in `config/filesearch.lua:177`, tilde relative, expanded by
`util.expandHome`, and already under `~/.cache/hammerspoon`. Two things change for it and both are
small. The name becomes `filesearch` rather than `filesearch-previews`, since the root supplies the
prefix and a spoon does not need to repeat what kind of thing it is, and the tilde expansion moves
to the root along with everything else so one place does it rather than each spoon owning a helper
for it.

That leaves the honest count. Of five path conventions, two are already right, one is nearly right
and predates the rule, and two are hardcoded file locals. So this is a small piece of work that has
already half happened by itself, which is usually the sign a convention is real rather than imposed.

## Migration

`history.json` and `files/` move to the visible root, `thumbs/` stays in cache. A few lines on
load, or accept losing history once and start clean. Either is fine, but decide it rather than
discover it. Given the standing rule that history is never expired, migrating rather than
starting clean is the likely answer, but it stays an open decision.

---

# One plugin contract for the launcher

## The one idea worth taking from Seal

Seal keys dispatch by plugin. A row carries the name of the plugin that produced it and Seal
does the equivalent of `plugins[row.plugin].completionCallback(row)`. Adopt that and
`actions.special` disappears, and adding a tool becomes one registration instead of edits in
`config/keys.lua`, the actions table, the `choosers` registry at `init.lua:2199`, and
`hyperContexts`.

## Two things not to take

Seal stores functions in its command registry. That cannot happen here, because the Chooser
hands every row to `hs.chooser`, which serialises it and silently drops a function, leaving an
empty list. The serializable descriptor rule stays exactly as it is.

And every method must be optional and structural, so a purely behavioural spoon like
`DockAutoHide` or `KeyRemap` implements none of it and stays a plain spoon. Resist making
everything a plugin.

## Apps becomes a plugin, last

App scanning, an `hs.application.watcher`, and two caches currently live inside
`Launcher.spoon`. Extracting them is what makes the launcher a pure host. It is last because it
owns the shared recency timeline and a watcher, so it is the one extraction with real risk.

---

# The action panel, every chooser's verbs as a searchable list

Raycast has this as its actions menu. One chord, the same on every list, swaps the visible rows for
the actions available on the highlighted item, first row Back, typing filters them, each row shows
the chord that runs it directly, and selecting one runs it against the item that was highlighted
when the panel opened. Navigation is excluded, moving up and down and closing need no menu, so the
panel carries only the verbs, reveal in Finder, copy path, open the folder, open in Preview, the
things a person forgets the chord for.

## Why this is mostly already built

Verified against the working tree at `6bd5b8d` rather than assumed. Three pieces exist and the panel
is a fourth consumer of them, not a new subsystem.

The declarations exist. Every chooser's verbs already live in `config/keys.lua` as per context
binding tables carrying a key, an action name, and a description, reveal in Finder on o, copy path
on y, into folder on l, up a level on h, and so on. That table is exactly the row list the panel
needs, title from the description, subtitle from the chord, action name as the descriptor.

The rendering exists. Holding Hyper while a chooser is open already draws those same declarations as
a read only shortcut overlay, through `shortcutPanelFor` at `init.lua:943`. The panel is the same
data made selectable.

The in place swap exists. The Chooser atom's `intercept` hook, `providers/native.lua` around line
430, lets a row mean this list becomes another list, keeps the window open, and rebuilds from the
top, and the `back` hook makes Backspace on an empty field step out again. The comments there record
that this was verified against `hs.chooser`'s hardwired Return. The panel swap is one more use of
machinery that already carries scope hosting.

So one declaration drives three surfaces, the chord itself, the hold overlay, and the searchable
panel. That is the reason to build it this way and not as a separate action registry, a panel that
reads the same table the binding is made from can never disagree with the chord it displays.

## The gap it closes was already named

`init.lua:306` records that a list hosted inside the launcher does not carry the tool's own verbs,
only the shared navigation, and says the gap closes when a scope can carry a tool's extra verbs,
which is worth doing and is not this. The action panel is that sentence built. Inside a hosted file
search list the chords for reveal and copy path belong to a context that is not active, but the
panel can still list and run them, because running a named action does not require the chord that
would have run it.

## What the panel needs decided

**The chord cannot be Hyper Space.** That is the launcher's own open and close key at
`config/keys.lua:520`, and Space already means close inside the caffeinate context. The question
mark is ruled out as taken by intent. Surveying every context, the letters j, k, i, x, y, s, r, o,
l, h, f, d, a, and q are spoken for somewhere, and k, the Raycast reflex, means move up in all
eleven contexts. Hyper period is free in every context and at the app layer, where comma is System
Settings, and period reads as the more of this place key. Recommended, Hyper period, recorded as an
open decision since a chord this habitual is the user's to pick.

**Navigation is excluded by classification, not by guesswork.** The shared rows, move up, move
down, insert, close, and the preview scrolls, are stamped by the host where it already copies
binding tables, so a binding gains a kind from a named set per the named values rule, and the panel
lists only the verbs. Explicit beats inferring from action names.

**The acted upon item is captured at swap time.** The panel replaces the list, so the highlighted
row it acts on is the one recorded when the chord was pressed, not whatever the panel's own
highlight sits on. Getting this wrong turns copy path into copying the path of a menu entry.

**Ways out follow the grammar.** First row Back, Backspace on an empty field also goes back, both
through the existing hooks, and Escape closes the whole tool rather than stepping back, matching
every other list here.

**It lives in the host, and the atom stays ignorant.** The panel reads binding declarations, which
are host material, and the atom already exposes everything the swap needs. No new atom surface,
which keeps the picker contract at its current size.

---

# The interaction grammar, written down as rules

These patterns exist in the code and are confirmed against the working tree, but they live as
scattered comments, so nothing stops a future tool from breaking one. They become a section of
`Olm.spoon`'s `CLAUDE.md` when it exists, since they bind every plugin and the host, and until then
this list is their home.

A list that becomes another list swaps in place. The window never closes and reopens, the
`intercept` hook is the mechanism, and the rebuild starts from the top row. Two tools predate this
machinery and still close and reopen on a timer, menu search and the overlay display picker, whose
own comment calls it the reopen idiom. They are grandfathered, new work may not copy them, and each
migrates to the swap whenever it is next touched.

Backspace on an empty field steps out one level. It is the same press that deletes a typed scope
word, so one habit covers both. A parent step can also be an ordinary row, the way file search
offers a two dots row, and the two coexist.

Escape always closes the whole tool, never steps back a level.

The shared navigation is uniform and carried by every chooser, Hyper j and k to move, i to insert,
x to close. A chooser's open chord doubles as its close.

Holding Hyper reveals the active context's shortcuts as a read only overlay. The action panel is
the selectable form of the same declarations, on one chord that is identical everywhere.

Every row handed to a chooser is a serializable descriptor, never a function, because `hs.chooser`
drops functions silently.

A list shaped tool chosen from the launcher is hosted in place rather than opened as a second
window, the `hostedInPlace` table at `init.lua:316`, and stepping out is the Backspace rule above.

---

# Snippets

## Reversal, and why

The earlier version of this document said snippets must live inside `ClipboardHistory.spoon`,
because it needs the paste engine in `manager/monitor.lua` and that engine is the most
carefully measured code in the config.

That is weaker than stated. `pasteText` is already public on the manager at
`manager/init.lua:221`, and the root already injects it into `Emoji.spoon`, a spoon of its own
reusing the paste engine that way. Snippets need only that, not `monitor.paste`, because a
snippet paste must never touch clipboard history and its ordering lives in settings anyway.

Note that the packaging reversal above does not disturb this one, and the two are easy to
conflate. This reversal is about snippets being its own unit rather than living inside the
clipboard's, which is about where the code and the state sit. Packaging is about which archive
that unit travels in. Snippets ends up bundled beside the clipboard rather than inside it, and
takes paste through the same injected door either way.

So snippets is its own unit, taking paste from the root, owning its store, and joining the
launcher as a plugin. It is the first plugin built on a finished core.

## Two plugins, not one, and what they actually share

Bundling raises the question again, because once the clipboard and snippets sit in the same archive
under adjacent directories, merging them into one plugin costs nothing structural. They should still
be two, and the reason is worth stating because it is the general test for every future pair.

What they share is a surface. What differs is the domain, and the domain is what a plugin is.

Six things differ and none of them is cosmetic. Origin, one is captured by a watcher and the other
is authored by a person. Storage shape, one is a history file plus frozen snapshots plus thumbnails
and is media aware, the other is one text file per name. Search target, bodies against names, which
is why one needs the `words` matcher and the other does not. Ordering, chronological against usage
plus pins. Mutation, the clipboard needs delete and append, snippets need create, rename, edit,
delete, and a handoff to a real editor. And content types, the clipboard holds images and file
references while a snippet is text.

A single plugin holding both would need a mode flag on nearly every one of those, which is the shape
that reads as one feature and behaves as two. Worse, it would reintroduce the five surface state
questions that splitting them removed, the typed query, the preview scroll offset, the marked append
batch, which hint panel is showing, and which Hyper context is live.

What they genuinely share is already core by the sections above, and this is the useful part of the
answer. `paste` for insertion, `chooser` for the list with a companion preview pane, `panel` through
`surfaceElements` for drawing in it, `recency` for ordering, and `storage` for where files go. Five
core services, no shared plugin, and each one has consumers beyond these two, which is what keeps
them honest as mechanisms rather than as a merged feature wearing a library's clothes.

One thing is deliberately not shared. The store. That was already reversed once in this document, and
the reasons hold with more force now, unreadable git diffs from one JSON file, no way to edit a body
in a real editor, and no way to touch a snippet from outside Hammerspoon. A shared store would be the
lowest common denominator of two different data models plus an escape hatch on each side.

The general test, for the next pair. Share the mechanism, never the feature. If two things want the
same widget, the same persistence, and the same output primitive, that is five core services and two
plugins. If they want the same domain model, they were one plugin all along, and neither of these is.

## What that costs

The swap. Two plugins means two chooser instances, so reaching snippets from the clipboard
becomes close one and open the other, a visible transition rather than an instant swap.

What it buys is that five pieces of surface state never need an answer. The typed query, the
preview scroll offset, a marked append batch, which hint panel is showing, and which Hyper
context is live. None of those questions exist today, all of them would exist with a shared
surface, and they were the expensive half of the feature.

Snippets gets its own key and its own launcher row, which was wanted anyway, so the rescue path
is one keypress either way.

## Storage, one file per snippet

The filename is the name and the file contents are the body. No metadata format, no schema, no
parsing. Rename is a move, delete is a remove, create is a write, edit is opening the file, and
listing is reading the directory.

This is a departure from the earlier assumption that snippets would ride `manager/store.lua` as
a second instance with a text only accept set. That reuse is genuinely free, `loadfile` is not
cached so a second call returns a fully independent instance, and it was the right answer until
git entered the picture. One JSON file gives unreadable diffs, forces an export and reimport
dance to edit a body in a real editor, and makes editing from outside Hammerspoon impossible.

## Where the directory goes

Not `~/.hammerspoon`. The pathwatcher at `init.lua:2558` reloads on any change under that tree,
which is survivable since a directory could be excluded as the display profiles JSON already
is. Stow is the real objection. That path is a stow target whose contents are symlinks into
`dotfiles/hammerspoon/.hammerspoon/`, so a snippets directory there is either inside the stow
package, which puts it in this repository as a nested git repository, or a loose untracked
directory sitting among the symlinks. Outside the tree it is just a directory the root points
at.

## Order and pinning, both local

Usage order lives in `hs.settings`, not in the store, and this is the decision the design turns
on. Reorder on use is the wanted behaviour, but if a mutation commits and pushes then pasting a
snippet runs git twice and puts a network call in the paste path, and within a month the
history is thousands of identical commits with the real edits buried among them. That is a
modelling mistake rather than a git tuning problem.

Usage order is machine state, like the BrowserTabs enabled set and the overlay display pin,
both of which already live in `hs.settings`. Bodies and names are versioned content, usage
order is local preference. Pasting touches only settings. It also means the work machine and
the home machine each float their own snippets to the top, which is correct.

Pinning is local too. A pinned snippet sits at the top in the order it was pinned, everything
else stays usage ordered below. Full manual ordering was rejected, because it needs a manual
mode and a usage mode and the user has to know which one they are in.

Once `recency` is a core service this is a consumer of it, not a hand rolled sixth copy.

## Search names, not bodies

Clipboard search scans full bodies because you have no idea what is in there. Snippets are the
opposite, you named them and you will type that name. Searching bodies here means a long
snippet matches everything, and name search makes a thousand snippets trivially fast.

## CRUD

Two tiers, split by how long the snippet is.

One line snippets are created and renamed in the chooser field itself, the single input frame
shape `DisplayProfiles` already uses, where the confirm row leads so Return commits and Back
trails. This covers most of what gets stored, an email address, a phone number, a command.

Anything multiline opens the real file in the real editor. This is the `crontab -e` pattern. A
chooser field is one line and any attempt to make it multiline ends in a webview, which this
config already tried and removed. A dev editor is already the default for dev file types on
this machine, so opening the file brings syntax highlighting, undo, and multiple cursors for
free. The spoon does not name the editor, the root injects how to open a body. Because storage
is file per snippet there is no temp file and no read back plumbing, and a pathwatcher on the
snippets directory picks up the save.

Delete is a remove, with the safe row leading on the confirm frame per the existing convention.

Promoting a clipboard entry into a snippet becomes a nicety rather than the main authoring
path. Build it last or not at all.

## Git versioning

Optional, deliberate, and dumb on purpose.

Never auto init, since creating a git repository inside someone's directory without asking is a
bad surprise. It is an action in the snippets surface, and until then snippets are plain files
that work fine.

Commit on content change only, meaning create, edit, rename, delete, never on use, which the
usage order split already guarantees. Push separately and lazily, batched a short while after
the last change, always in the background and always best effort. A failed push must never
block and never lose the snippet, because the file is already written and that is the part that
matters.

Say the missing remote thing once, at repository creation, and then leave it as visible state,
cheapest being the chooser placeholder. Not in the preview pane, because a missing remote is a
property of the store rather than of a snippet, so putting it there means seeing it forever,
which is the nag that teaches people to stop reading warnings.

Declare `git` as an optional dependency, kind path. No git means snippets still work,
unversioned, and the load summary says so by name.

The store stays ignorant. It writes files, and something else decides a write is worth a
commit, wired through an injected hook. If iCloud later turns out to be a better answer than
git, that is one wiring line and no snippet code.

## Reversal, a query scope is now allowed and probably right

This section previously said snippets cannot be a launcher scope, and rested on a rule that no
longer exists in that form. The rule said a tool owning a canvas companion pane cannot be scoped in
place, naming the clipboard and Processes as the exclusions, and snippets was excluded by having the
same shape.

`8674f78` and `5fdae8d` rewrote it. `CLAUDE.md:1335` now says a tool whose companion pane IS the
reason for the tool cannot be scoped in place, and `CLAUDE.md:1344` adds the case that forced the
change. File search has both a pane and a scope, and the paragraph states the point directly, that
the rule is about the pane's weight rather than about panes. Its reason is finding a file by name and
acting on it, the scope does that in full, and the pane only helps you decide between two rows that
already matched. So `/ ` lists rows with no pane, exactly as it did before the pane existed.

Snippets is the same case, and the argument that saved file search is stronger here. This design
already commits to searching names and not bodies, on the grounds that you named the snippet and you
will type that name. If names are reliable enough to be the only thing searched, they are reliable
enough to choose by, and a pane that shows the body is helping you separate two names that already
matched. Holding both positions at once, that names are sufficient for search and insufficient for
selection, is not coherent.

So the categorical objection is gone and this becomes a judgment call rather than a rule violation.
The recommendation is to allow the scope, and to build it after the plugin works rather than with it,
for two reasons. The plugin needs to exist before there is anything to scope, and the body preview is
the part most likely to change during the build, which is the part the scope has to do without.

What the old section got right and is worth keeping. The clipboard genuinely stays excluded, because
its preview is most of what it is, and Local Servers stays excluded because the process tree is what
makes pressing stop safe. The refined rule did not open those two, it explained why they are shut.

## The tripwire worth setting now

Snippets may add exactly one concept beyond the body, its name, which the filename already
carries. If a pin flag, a manual order index, a folder, and an expansion trigger all start
wanting to live on the entry, that is the signal snippets has outgrown its shape, and the
answer is not to keep widening it.

## Scale

Ten to forty snippets in practice, a thousand comfortably. A thousand short files is a few
megabytes read once and a name search over a thousand short strings. No tags, no folders.

---

# Documentation

`ClipboardHistory.spoon` has no `CLAUDE.md` of its own, so its decisions sit in the module level
file. Three blocks move out of `dotfiles/hammerspoon/.hammerspoon/CLAUDE.md`, about 280 of its
1531 lines.

| Lines | Block | Where it goes |
|---|---|---|
| 941 to 1005 | Clipboard preview | The clipboard plugin. Entirely internal to `manager/ui.lua` and `manager/preview.lua` |
| 1006 to 1201 | Clipboard append and sequential paste | Split. The measurement trail follows the code into `lib/paste.lua`, the append and sequence behaviour stays with the clipboard |
| 923 to 940 | Why the clipboard uses the `words` matcher | The clipboard plugin. Leave one line in the shared matcher section pointing at it |

The middle row changed once `paste` became core, and it is the one to get right. The `insertText`
versus paste finding, `sequenceDrainDelay`, and the held chord behaviour are properties of the
insertion primitives, so they belong in olm beside the code they describe. What stays with the
clipboard is the append and sequential paste feature those findings enabled. Splitting a measurement
trail from the code it measured is how a hard won finding gets argued again two years later, so this
row is a real decision rather than bookkeeping.

One caveat that survives either way. The trail is partly general macOS knowledge rather than
knowledge about this config, so the module level file keeps a pointer instead of losing the thread.

`Olm.spoon` gains its own `CLAUDE.md` holding the core rules, the three categories, the
declaration mechanism, the four API rules, the named value convention, and the packaging
decision with its reasoning, since the packaging decision is the one a future reader is most
likely to try to undo. `Chooser`, `CanvasPanel`, and `CheatSheet` have no `CLAUDE.md` today so
nothing is reshuffled for them, while `ChordKey` and `HyperKey` have theirs and those files travel
with them.

Two rules belong in the module level `CLAUDE.md` rather than inside olm, because they bind
everything in the tree and not only the core. That a value chosen from a closed set is passed by
reference from the module that owns the set, and that a plugin is activated from a list rather
than torn down at runtime. The second one is a promise about `stop`, so it belongs beside the
lifecycle contract it qualifies.

Every plugin also carries its own `README.md`, a short gist for a human rather than a decisions
record, what the tool is, how it opens, and its keys, in a handful of lines. The split is by
audience. The `README.md` answers what is this and how do I use it, the `CLAUDE.md` answers why is
it built this way, and neither repeats the other. The interaction grammar section above goes into
`Olm.spoon`'s `CLAUDE.md` so every future plugin is written against it.

---

# Proving a step changed nothing

Three steps in the order of work below promise no behaviour change, and one of them rewrites thirty
four load sites in a single pass. A promise like that cannot be kept by reading the diff, because the
failure it invites is a reference that quietly became nil in a place nobody thought to open. So the
scaffold comes before the migration rather than beside it, and each step below gets a gate it either
passes or does not.

The finding that makes this affordable, checked rather than assumed. `hs -c` runs Lua 5.4, the same
interpreter Hammerspoon itself uses, and `dofile` on a path inside this repository loads a module
without this repository's config being the live one. Verified against
`Spoons/Chooser.spoon/match.lua`, which loaded straight from the working tree and returned its three
matchers while the main config carried on untouched. A pure module test therefore needs no devlock, no
relaunch, and no marker file. That is the whole difference between a suite that runs on every commit
and one that runs when somebody remembers.

The live config also exposes its own binding surface, which is what makes a before and after
comparison possible at all. `spoon` enumerates the thirty four loaded spoons, `ChordKey._keys` holds
the chord tree at twenty nine nodes, and `HyperCheatSheet` holds ninety items, thirty five apps, and
one hundred and forty five toggles, because a cheat sheet has to know every binding in order to draw
it. The caveat is worth writing down plainly. `hs.hotkey.getHotkeys()` returns six. Almost nothing in
this config is an `hs.hotkey`, so an inventory read from Hammerspoon's own registries would report a
clean run while seeing almost none of the surface. It has to be read from this config's registries
instead.

| Tier | What it covers | Needs the lock | When it runs |
|---|---|---|---|
| Pure units | `match`, then `recency` and the path building in `storage` as each is extracted | No | Every commit |
| Inventory snapshot | Every registry the config keeps, so a binding, chooser, scope, or alias that disappeared | Yes | Before and after any step promising no behaviour change |
| Live behaviour | Paste timing, the companion panes, anything only an eye or an agent can judge | Yes | At the paste step, and before the bundling branch lands |
| The reconciler | `src/check-dependencies.sh`, the manifests and the layering | No | Exists already, and gates the new dependency kind |

The inventory snapshot is the one that earns its keep, and it is a fingerprint rather than a proof. A
sorted text dump of every registry, a golden file committed beside it, and a diff that must come back
empty. It cannot tell whether a chooser still works, only that it still exists, still answers to the
same name, and is still reachable by the same key. For a mechanical move that is exactly the failure
mode, so the narrowness is the point rather than a shortcoming.

The harness shape already exists and should not be invented twice.
`Spoons/BrowserTabs.spoon/test/suite.sh` solves the awkward parts already, dropping an `ENABLED`
marker that `Spoons/BrowserTabs.spoon/init.lua:266` checks so a harness is never part of a normal
config, taking the lock with `--manual` because a suite outlives the short timeout, and putting both
the marker and the lock back on any exit including an interrupt. Two harness styles in one tree is
worse than either of them.

The unit runner belongs beside the code it covers, so it starts at the hammerspoon package level and
moves under `Spoons/Olm.spoon/test/` once olm exists. On the question of a standalone interpreter,
Homebrew's `lua` happens to be on PATH at 5.5.0, is declared nowhere, and is absent from the
Brewfile. It should stay that way. Going through `hs -c` uses 5.4, the version that actually matters,
so reaching for the standalone binary would buy a declared dependency and a version skew in exchange
for nothing.

The honest limit. Paste timing cannot be tested this way, since its correctness is a measured delay
and a regression there is felt rather than observed. Nothing drawn on a canvas can be tested this way
either. Neither can the question of whether the plugin contract is any good, which is what snippets
is for. So this scaffold covers the mechanical risk almost completely and the judgment risk not at
all, which is the right split, because the mechanical risk is the one that is large, boring, and easy
to get wrong late at night.

---

# Order of work, with a test in it

Two standing rules sit above every step here, set on 2026-08-04, and they change what some steps
mean.

**No original spoon is destroyed, moved, or edited.** New code is built beside the old, pulled in
one piece at a time, and `init.lua` carries both wirings with one commented out, so old and new can
be flipped between and compared live. A step below that says convert a caller means convert the new
copy that lives under olm, while the original keeps working exactly as it does today. Retiring an
original is its own explicit step, ordered by the user per tool and never bundled into anything
else. The inventory gate gets stronger under this rule, since flipping the toggle from old to new
must produce an identical inventory, which is a before and after on the same machine in the same
minute.

**The roles are fixed.** The architect and QA never writes the implementation. Sonnet 5 agents do
the work from precise instructions that include the read only rule above, and every result is
checked against this design and its gates, with anything short of the mark returned for rework
rather than patched in review.

**The scaffold, before anything moves.** Two runners and one golden file. The unit runner, driving
`hs -c` so the interpreter matches, covering `match.lua` on day one because it is the module every
plugin leans on and the one where a regression stays silent. The inventory script, dumping every
registry the config keeps into sorted text, with its output committed as the baseline. Half a day,
and it pays for itself at the bundling pass alone. Doing it first is what lets every step below
state a gate instead of an intention.

**Storage into core.** Create `Olm.spoon` holding only that, the smallest core that does real
work. About an hour plus the migration. Gate, the path building goes into the unit runner as it is
written, since a root that resolves one directory wrong is silent until something is lost.

**Recency into core**, converting all five callers. This is the proof. If extracting recency
does not delete more code than it adds, the core idea is wrong and the right move is to stop
there having spent half a day. Given BrowserTabs already keeps it in a file of its own, it
should delete a fair amount. Gate, unit tests for the ordering, plus a line count before and
after, since the line count is the stated proof and should be recorded rather than estimated.

**Paste into core**, the second half of `monitor.lua` out and the three existing consumers pointed
at it. Half a day, and the riskiest of the three extractions despite being the smallest, because the
timing behaviour is measured rather than obvious and a regression here is felt on every paste. Do it
after recency has proved the pattern, not before. Gate, the live tier and nothing else, since no unit
test can see a delay that is wrong by thirty milliseconds. Paste into a terminal, a browser field, and
an Electron app, run the sequential walk to the end of a full history, and do it before the diff is
committed rather than after.

**The new dependency kind and the reconciler check**, so the layering is enforced rather than
described. Half a day. Gate, `src/check-dependencies.sh` clean, which is the tier that already
exists.

**Move the remaining five atoms into `Olm.spoon`.** One pass, one restow, no behaviour change.
About a day. Two ways to reach the chooser is worse than either, so this cannot be half done. Gate,
an empty inventory diff, which is the first step where that gate carries real weight.

**The bundling pass.** Every remaining spoon is copied under `Spoons/Olm.spoon/plugins/`, the
originals staying untouched where they are, and `init.lua` gains the second wiring, one
`hs.loadSpoon` and the rewritten references, commented against the current thirty four. This was
written as a move before the read only rule landed and is now a copy, which trades disk for the
ability to flip between the two worlds while testing. One to two days, almost entirely mechanical,
and no behaviour changes at all, which is what makes it reviewable at that size. Deliberately
before the plugin contract and not combined with it, because copying files and changing how they
register are two different kinds of mistake and mixing them makes a bisect useless. Gate, an empty
inventory diff across the toggle flip, and this is the step the snapshot was built for. Thirty four
rewritten references cannot be eyeballed, and the diff finding one missing chooser is worth more
than a careful review of the whole pass. The cost of the copy is honest too, a fix landing in an
original while the copy exists must be carried across by hand, so the window where both live
should be kept short per tool.

**One plugin contract for the launcher**, replacing the three join points. One to two days. The
api version check and the activation list belong here, since this is the step that creates a
registration to gate. Both are small, an integer comparison and a settings read. Gate, an empty
inventory diff again, and one deliberate failure, an activation list naming a plugin that is not
there and a plugin declaring an api version too old, both of which should be refused with something
readable rather than a stack trace.

**The action panel.** After the plugin contract, because that is when a tool's verbs become
registered data the panel can read uniformly, though a prototype against today's `hyperContexts`
is possible earlier if the chord question gets settled first. A day. Gate, the panel on three
choosers with different verb sets, file search, the clipboard, and one with no verbs at all, which
must show only Back rather than an empty list, plus the hosted case, a file search list inside the
launcher offering reveal and copy path even though their chords are not active there.

**The plugin READMEs, as a sweep.** Once plugins sit in their final home, each gains its short
gist `README.md` per the documentation rule. Mechanical, an agent pass with review, and the gate is
only that every plugin has one and none repeats its `CLAUDE.md`.

**Snippets, the first plugin written rather than moved.** About a day and a half, smaller than the
earlier estimate because the shared surface and its five state questions are gone. It comes after
bundling so it is built in its final home, and it is the real test of the contract, since everything
before it was adapted to fit while this one is shaped by the contract from the start.

**Named values, as a sweep rather than a phase.** Placement is the only live defect and is three
call sites. Everything else is done as each module is touched, so this never becomes a piece of
work of its own. Half an hour for placement.

**Apps as a plugin.** Last, about a day.

**A query scope for snippets.** After the plugin works, not with it, per the reversal above. An hour
or two, since the machinery exists and file search is the worked example to copy.

**The plugin roster surface.** Deferred, and deliberately outside this order of work. It is
worth nothing until olm ships to someone, so it waits for that rather than for the steps above.

Two of these are worth stopping at if they go badly. Recency is the stated proof, and if it does not
delete more than it adds the core idea is wrong. The bundling pass is the other, because it is the
step that is hard to reverse, so it should be a branch that either lands whole or is thrown away
whole.

One rule holds across all of them. A step whose gate is an empty inventory diff may not change
behaviour in the same commit, however small the improvement looks while the file is already open.
The moment a step both moves code and changes what it does, the diff stops being a gate and becomes
a list of things to explain away.

---

# Files

**The scaffold**

- New `.hammerspoon/test/units.sh` and `cases/`, driving `hs -c` and needing no lock, starting with
  `match.lua` and gaining a file per core module as each is extracted.
- New `.hammerspoon/test/inventory.sh` plus a committed `inventory.golden`, reading this config's
  registries rather than Hammerspoon's, so `spoon`, `ChordKey._keys`, the chooser registry at
  `init.lua:2199`, the query scope prefixes and aliases, and the cheat sheet entries.
- Both borrow the lock discipline and the exit trap from `Spoons/BrowserTabs.spoon/test/suite.sh`,
  and only the inventory script needs the lock at all.
- Inside `.hammerspoon` rather than at the package root, so nothing is added to
  `.stow-local-ignore` and the later move under `Spoons/Olm.spoon/test/` is a rename within one
  tree instead of a jump across the stow boundary. Test material already appears in the live config
  this way, since `Spoons/BrowserTabs.spoon/test/` is not ignored either.

**Storage and core**

- New `Spoons/Olm.spoon/init.lua` plus `lib/storage.lua`, later `lib/recency.lua` and the five
  moved atoms.
- Edit `config/settings.lua`, add the `paths` block as pure data.
- Edit `init.lua`, resolve the roots and inject finished paths.
- Edit `Spoons/Eyedropper.spoon/init.lua` and `Spoons/BrowserTabs.spoon/permissions.lua`, take
  the directory as config.
- Edit `config/filesearch.lua:177`, shorten the cache name and let the root own the prefix and the
  tilde expansion, and drop the per spoon `util.expandHome` call at `Spoons/FileSearch.spoon/chooser.lua:441`.
- Edit `Spoons/ClipboardHistory.spoon/manager/init.lua`, split cache from data and drop the
  hardcoded defaults.
- Edit the five recency callers.
- Edit `src/check-dependencies.sh` for the new kind.

**Paste into core**

- New `Spoons/Olm.spoon/lib/paste.lua`, the insertion helpers and exports from about
  `monitor.lua:244` through the read side mirror near 857. Not to the end, the Cmd+V walk watcher
  from 858 is clipboard behaviour and stays.
- Edit `Spoons/ClipboardHistory.spoon/manager/monitor.lua`, keeping the watcher and the history
  capture, and take the primitives by injection like every other consumer.
- Edit `init.lua` at 1391 and 1422, point `Emoji` and `TextCase` at the core module instead of
  reaching through the clipboard manager.
- Move the measurement trail from the module `CLAUDE.md` lines 1006 to 1201, splitting it by the rule
  in the documentation section.

**Packaging and activation**

- Move every plugin under `Spoons/Olm.spoon/plugins/`, each keeping its own directory, its own
  `CLAUDE.md`, and its own declarations, so only the load path changes.
- Move the host under `Spoons/Olm.spoon/host/`, the launcher, `QueryScope`, and `HyperCheatSheet`.
- Edit `Spoons/Olm.spoon/init.lua`, the api version, the activation list read, the registration
  door, and the search path for a plugin from outside the bundle.
- Edit `init.lua`, one `hs.loadSpoon` in place of thirty four, activate from the list, and rewrite
  every `spoon.Something` reference. This is the bulk of the mechanical work.
- Edit `Spoons/CanvasPanel.spoon/init.lua`, expose the five placements as a named set, and edit
  the three call sites at `init.lua:945`, `2143`, and `2365`.
- Edit `dotfiles/hammerspoon/dependencies-collect`, specifically `owner_of` at lines 80 to 95. See
  the section below, this one is a real break rather than a rename.
- Nothing changes in `dotfiles/hammerspoon/.stow-local-ignore`. It sits at the package root and lists
  four files at that root, and its comment says the declarations inside `.hammerspoon` are
  deliberately not listed because the running config reads them. Nesting spoons does not touch either
  fact.
- Restow, which leaves `~/.hammerspoon/Spoons` holding one symlink, `Olm.spoon`, in place of the
  thirty four today. That is the visible sign the packaging changed.

**Snippets**

- New `Spoons/Olm.spoon/plugins/snippets/`, the store, the surface, and the versioning module last.
  Built here directly rather than as a sibling spoon first, since the bundling pass comes before it.
- New `DEPENDENCIES` beside it, declaring `git` as optional and the core slice.
- Edit `config/keys.lua`, `init.lua`, and the module `CLAUDE.md`.
- Add `git` to `DEPENDENCIES.map`.

---

# Out of scope

**Text expansion**, where typing a trigger substitutes a snippet. A global keystroke buffer with
per app behaviour turns a spoon into a keyboard daemon.

**Placeholders and variables** inside snippet bodies. Same reason.

**Tags and folders.** See the scale note.

**In place multiline editing.** The editor handoff is the answer.

**A webview surface.** Already tried and removed once.

**Full manual ordering.** Pinning covers the real need.

**Renaming the atoms' public behaviour.** Moving them into olm changes where they are reached
from and nothing else.

**Turning a plugin off without a reload.** It needs an honest `stop` on twenty seven spoons that
do not have one and do not otherwise need one, and no way to prove any of them is complete.

**A general preferences surface.** Only the activation list is a setting. Everything else stays
in Lua in the composition root.

**Any dependency resolution of our own.** No version constraint solving, no install ordering, no
fetching a missing plugin. Bundling exists so none of that is needed, and the api version check is
the whole of the runtime guard.

---

# Decisions still open

- Whether to migrate the existing clipboard history and file snapshots or start clean once.
  Migrating is the likely answer given history never expires, but it is not yet ordered.
- Whether to remove the config pathwatcher at `init.lua:2558` entirely. There is a case for it
  on its own merits, since the documented workflow already says never rely on it, and
  `Spoons/Caffeinate.spoon/engine.lua:10` records a real casualty. Separate decision, should not
  be bundled in. Note that the activation list now depends on a reload being available, though not
  on the watcher, since a toggle schedules its own.
- The exact name of the new manifest kind for a core dependency.
- Whether the roster reopens itself after a toggle or accept writes and closes.
- How the api version is numbered, a single integer bumped on any breaking core change being the
  cheapest thing that works. Decide before the first plugin loads from the search path, not after.
- Whether olm is a launcher that happens to bundle behaviour, or a config framework. The roster says
  eleven of the bundled plugins have no surface at all, `AppToggler`, `DockAutoHide`, `KeyRemap`,
  `StageManager`, `TerminalHandler`, `DisplayMemory`, `WindowMemory`, `WindowManager`,
  `WindowLeader`, `WindowCheatSheet`, and `WorkspaceEngine`. Nothing about the design forces a
  choice, since they bundle and activate identically either way, so this is a question about what
  the thing is called and what its first paragraph promises rather than about code. It is the one
  open item that shapes how somebody else understands the project.
- Whether the window group is one plugin or five. `WindowManager`, `WindowLeader`,
  `WindowCheatSheet`, `WindowMemory`, and `DisplayMemory` are five spoons that only make sense
  together, and by the same test that keeps the clipboard and snippets apart they may be one plugin
  with five files. Deliberately not decided here, because it is a question about the window feature
  and this document is about the core.
- The action panel's chord. Hyper Space is the launcher and Space already means close in one
  context, the question mark is ruled out, and k is move up everywhere. Hyper period is the
  recommendation, free in every context and at the app layer, but a chord this habitual is the
  user's to pick.
- Whether a hosted list's action panel also shows the chord column for verbs whose chords are not
  active in that context, which is honest but could teach a chord that will not work until the
  tool is opened directly. Showing them greyed or footnoted is the likely answer, decide when it is
  built.
