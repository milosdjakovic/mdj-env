# What a plugin must expose, and what Olm does with it

This is the contract. A plugin that satisfies it can be dropped into `plugins/` and
Olm will wire it with no edit anywhere else. A plugin that does not satisfy it will be
reported at load rather than failing quietly at the moment someone presses a key.

Read this with `docs/AUDIT-2026-08-13.md` beside it if you are wondering why a field
exists. Almost every field below is here because its absence caused a real silent
failure in the first attempt.

## The two files

A plugin is a directory under `plugins/`. Discovery is a scan, so adding one is a new
directory and zero edits.

`manifest.lua` returns pure data and must load without loading the plugin. That
property is load bearing. It is what lets Olm compute wiring order before anything
initializes, and what lets a shell script build the install list with Hammerspoon not
running. A manifest that requires anything, touches `hs`, or reads a file has broken
the contract even if it happens to work.

`init.lua` returns the module. It must expose `configure(opts)`, unless it declares
`wiring` steps of its own, since a step is a call into the module too and a plugin whose
whole lifecycle is expressed as steps has already said what runs in place of configure
rather than left it out. KeyRemap is the real example. Its wiring names
`apply(catalog, activeNames)`, a call that is not configure and was never going to be one,
so writing an empty `configure(opts)` beside it would exist only to satisfy a rule rather
than to do anything, which is the exact ceremony this contract elsewhere refuses to keep. A
plugin with neither configure nor a declared wiring step does nothing at all no matter what
runs, and that is not this exception, it is the defect the exception exists beside.
Everything else `init.lua` exposes it must declare.

## The rule that decides whether a field belongs in a manifest

**If Olm can derive the need from something the plugin already declared, the plugin
must not declare it again.**

This is the whole reason the manifest is short. Fifteen plugins need the shared chooser
factory and the shared theme. None of them declare either, because all fifteen declare
`surface`, and declaring a surface is what makes a plugin one that opens a list. The
entitlement follows from the role. Writing `chooser` and `theme` into fifteen manifests
would be retyping global policy fifteen times, which is the exact defect this design
exists to remove, and it would give fifteen places for that policy to drift.

So the manifest answers what is true about this plugin alone. Olm answers what follows
from that.

### What is ambient, and what earns it

| A plugin gets | when it declares |
| --- | --- |
| `chooser`, `theme`, `placeholder`, the panel triple, `matcher` | a `surface` |
| `surface` elements, the docked companion pane | `surface.pane = true` |
| `deps`, the scoped adapter that turns a tool name into an absolute path | any `needs.tools` |
| `recency` | `needs.lib.recency` |
| `after`, the deferred call helper | nothing, every plugin may ask |
| every `needs.lib` capability, under the field name it asked for | that `needs.lib` entry |
| every `needs.siblings` capability, under the field name it asked for | that `needs.siblings` entry |

Ambient services arrive on the same `opts` table as everything else. A plugin cannot
tell an ambient value from a declared one, and must not try.

The last two rows of that table read as obvious and were the two hardest defects in this
build, twice over. Both `needs.lib` and `needs.siblings` were validated at load, used to
compute wiring order, and then **never delivered to anybody**. A declaration that is checked
and never satisfied is worse than one never written, because the check reports success and
the plugin gets `nil` at the moment it matters. The launcher declared it wanted the window
manager's action map and received nothing, so every window row in the catalogue silently
failed to build. If you add a new kind of need, the delivery is the part to write first.

## Fields

Every field is optional. A plugin with nothing to claim returns `{}` and that is a
complete answer, not an omission. KeyRemap and WindowMemory both do.

### name

The plugin's identity everywhere outside its own directory. The directory is lowercase
by convention, the identity often is not, and the two are not the same thing.

```lua
name = "colorPicker",   -- the directory is eyedropper
```

Omit it only when the identity is exactly the directory name. Seven of the twelve
surfaced tools differ, so omitting it is the exception rather than the rule.

### needs.tools

An external binary or bundle. Presence is proven by `kind`, `path` for a command on
PATH, `system` for a fixed absolute path, `app` for a macOS bundle id, `manual` for a
marker path.

`policy = "required"` means the plugin is not wired at all when the tool is absent,
because a dead surface is worse than no surface. `policy = "optional"` means the plugin
loads degraded and Olm says on the console what was lost.

`origin` says how to get it, and it lives here rather than in a map at Olm's root. The
rule that matters is not that a plugin must not know Homebrew exists, it is that
install instructions must not be duplicated where they drift.

```lua
tools = {
  { name = "qalc", kind = "path", policy = "required",
    reason = "the calculator that answers a unit conversion",
    origin = { brew = "libqalculate" } },
},
```

### needs.lib

A capability from Olm's own `lib/`. Named by module and member.

```lua
lib = { recency = { from = "recency", policy = "optional" } },
```

A lib name that does not exist is a repository defect and is reported, never ignored.

The value is delivered on `opts` under the field name you chose, and a member defined as a
method arrives already bound to its own module, so you can call it plainly. Both halves
matter. An earlier version validated these declarations at load and then never handed the
value over, which is strictly worse than not declaring it, because the check reported
success while the plugin received nil.

### needs.siblings

A capability from another plugin. This is a table rather than a dotted string, because
a dotted string cannot say two things the wiring genuinely needs.

```lua
siblings = {
  -- the module itself, because the consumer calls windowLeader:bind(...)
  leader = { plugin = "windowleader", policy = "required" },
  -- one member, called with a dot
  rows   = { plugin = "systemsettings", member = "rows", call = "dot", policy = "optional" },
}
```

`member` absent means the module itself. This case is not a convenience. It was
inexpressible before and it is what WindowManager actually depends on.

`ordering` defaults to true, meaning this need is also an edge, so the plugin it names is
wired first. Set it to false when the capability arrives as a closure that reaches its
plugin at call time rather than at configure time. The need still resolves and is still
existence checked, it just contributes no edge.

This distinction is not theoretical. MenuSearch receives two Launcher capabilities as
closures, and the live root configures MenuSearch **before** the Launcher. An eager
declaration would invert that order for no reason, and in some pairings would produce a
cycle that fails the whole plan. The lesson is that a need and an ordering constraint are
two different statements, and the schema used to be able to make only one of them.

`call` is `"method"` or `"dot"`, defaulting to `"method"`. A resolved member with the
wrong convention is worse than a missing one, since it resolves and then fails on
arity at the moment a key is pressed. Olm binds `self` for you when `call = "method"`,
so the consumer always receives something it can call plainly.

**Existence is checked at load against the real module, not against the manifest set.**
A sibling naming a plugin that exists but a member that does not is a defect, and under
`policy = "required"` it blocks the plugin. The first attempt checked only that the
plugin existed, which is how four capabilities that had been deleted from the clipboard
module went on being declared by three manifests with nothing noticing.

### needs.data

Plain data the plugin cannot work without and cannot derive. Not a tool, not a
capability, just a parameter, and the category the first schema was missing entirely.

```lua
data = {
  apps = { source = "user", policy = "required",
           breaks = "every toggle logs Unknown app and does nothing" },
  scope = { source = "root", policy = "optional",
            breaks = "state stops being keyed to which displays are attached" },
}
```

`source` is `"user"` when it is the person's own knowledge, their apps, their monitors,
their account, and `"root"` when Olm computes it. A `"user"` requirement is also the
declaration that this plugin cannot ship a working default, which is what keeps the
fresh install promise honest.

`breaks` is not documentation. It is the sentence Olm prints when the value is absent,
so the console says what stopped working rather than only that something did.

This field exists because DisplayMemory's manifest was `return {}` while `bundleID` was
a hard requirement whose absence made `start()` a silent no-op.

**`source` decides whether an absent value blocks, and the two are not alike.** A `"user"`
need that nothing supplied blocks the plugin, because it is a statement that this plugin
cannot ship working. A `"root"` need is Olm's own obligation to itself, and it is recorded
as an obligation rather than a block, **always**, whether or not any data was attached to
that particular call. An inspect run is the main caller with no root, and it must not claim
six plugins are broken on a machine where nothing is wrong.

That last word, always, is load bearing and was learned the hard way. The test used to be
whether any data table arrived at all, and the composition root plans **twice**, the first
pass existing precisely to compute the values only a plan can tell it. That first pass
carries the person's own data, so the test read true, so every root sourced need looked
unmet by a root that was present. WindowManager was blocked on the very pass whose purpose
was to produce the mapping it was blocked for wanting. It never reached the second pass, its
sixteen bindings were stamped off an empty list, holding the window leader did nothing at
all, and the report said no problems, because a blocked plugin is a planning outcome rather
than a wiring failure. A debt Olm owes itself is never grounds for refusing to plan. What
keeps this honest is that the obligation is still recorded, so a root that genuinely fails to
discharge one leaves a line a person can read rather than silence.

**A required user need must earn it, and this is the rule that protects the whole
project.** Before writing one, ask whether Olm could ship a working value. If it could, the
value belongs in `defaults` and the need is optional or absent. Only genuine local
knowledge qualifies, meaning this person's own apps, monitors, or account.

Four manifests got this wrong at once and the result was instructive. A macOS pane
catalog, a leader key remap table, and a default Finder toggle were each declared as the
user's own required data, so a fresh install wired none of them. The leader table was the
worst of the four, since without it no leader key exists at all and every app toggle, the
window leader, and every context die together while the console blames one plugin.

**The policy must agree with the `breaks` sentence.** BrowserTabs declared a required need
whose own sentence said one browser would drop out. A sentence describing degradation under
a policy meaning total failure is a contradiction, and the policy was the half that was
wrong. Required there would have taken Safari's tabs down over an application that may not
even be installed.

### needs.set

A question about the whole plugin set rather than about any one plugin, and the field that
separates a host from a plugin. A plugin knows only itself. A host composes across a set it
must never learn the membership of, so it states the question and Olm computes the answer
from what the plugins themselves declared.

```lua
set = {
  surfaces   = { has = "surface" },
  scopes     = { provides = { "rows", "select" } },
  queryRows  = { provides = { "queryRows" } },
  actionRows = { provides = { "actionRows" } },
},
```

`has` asks which plugins declare a given manifest field at all. `provides` asks which
plugins offer a capability, and a list means every one of them, so `{ "rows", "select" }`
matches a browsable list and not a computed source that only answers `rows`.

The answer arrives on the plan as `plan.sets[host][name]`, an ordered list of identities,
and a satisfied query is also an ordering edge, so every plugin in the answer is wired
before the host that asked. A plugin joins an answer by declaring a capability, never by
being named, which is the whole point. Adding a scopable tool is a new directory and no
edit anywhere else.

A host is excluded from its own answer, so a launcher that declares a surface does not
become a dependency of itself. That exclusion lives in one place rather than as a rule each
host has to remember about itself.

### provides

What other plugins and hosts may ask this one for.

```lua
provides = { rows = "rows", select = "select" },
```

`rows` and `select` together mean a browsable list that a host may scope. `queryRows`
means a computed source that claims the whole query, which arithmetic and convert do.
The split is not cosmetic. A query for `rows` alone returns every scopable tool too.

Two more are answered today. `profile` means this plugin can say which display arrangement
is current, which the overlay resolver asks for without knowing any plugin manages
arrangements at all. `actionRows` means each of this plugin's own keyed actions deserves a
row of its own in the catalogue rather than one row for the plugin, which capture declares
because it has four actions, a key each, and no picker of its own to open.

A value may be `true` where the capability is a fact about the plugin rather than a member
to call, as `actionRows` and `profile` both are.

### registry

How this plugin appears in the tool registry, which is what gives it a launcher row, a
searchable word, a base key, and a place in the cheat sheet. Pure data, and every function
is named as a **member** the registrar resolves lazily against the loaded module rather than
captured now, because two real tools build their surface inside their own `configure` and
anything captured at declare time would capture nothing, permanently and silently.

```lua
registry = {
  row = { category = "Tools", glyph = "🗂️", detail = "...", keywords = "..." },
  open = "show",                                  -- a colon method on this plugin's root
  surface = "chooser",                            -- this plugin's own submodule
  hosted = true,
  shortcut = "leader",                            -- or "global"
  scope = {
    matcher = false,
    rows = { member = "scopeRows", call = "dot" },
    run  = { member = "activate",  call = "dot" },
  },
  commands = {
    appendCopy = {
      fn = { member = "manager.appendCopy", call = "dot" },
      key = "C", mods = { "ctrl", "alt" },
      row = { category = "Clipboard", description = "Append copy", chord = "modifier" },
      shortcut = "global",
    },
  },
}
```

A member is a bare string for a colon method on the plugin root, or a table carrying
`member` and `call`. A dotted member reaches a submodule, `manager.appendCopy`. `surface`
may be `true` to mean the plugin root itself.

`row` is what a person reads. Its `category` is required for a row to exist at all, and
`description`, `glyph`, `aliases`, `key` and `leader` come from `defaults` rather than being
retyped here, so one answer serves the row, the key binding and the scope directory.

`commands` are named actions that belong to a tool but are not tools themselves. A command
has no plugin directory, so nothing can resolve a key for it through the plan, which is why
its key and mods ride on the command itself. Both clipboard commands bound nothing at all
until they did.

**This block is the source and `cfg.registry` is only an override.** The composition root
merges any per identity override over what the manifest declares, per field. It used to be
the reverse, a separate undocumented table that `describe` refused to build any registration
without, so a fresh install registered zero tools out of twenty seven, silently, with every
base key bound to nothing and the cheat sheet empty. A plugin with a complete manifest is now
registered by that alone.

### defaults

What this plugin proposes, which the user's own file may override.

A default names a leader **role** and never a physical key, so a person who moves the
app leader to SUPER carries every default with it.

```lua
defaults = {
  leader = "app", key = "j", description = "Emoji picker",
  glyph = "😀", aliases = { "e", "emoji" },
},
```

A default is admissible only if it works on a fresh macOS install with nothing
configured. Two things disqualify one, and they are different. A missing binary
degrades, so the default may ship and announce what it lost. Missing local knowledge
cannot ship at all, which is why VPN correctly proposes nothing.

Overrides resolve as follows. A list replaces wholesale. A map merges per key. A plugin
level `false` disables the whole plugin. `defaults.NONE` removes a single key, and it
exists because overloading boolean `false` made a meaningful `false` impossible to
express, which silently broke `matcher = false`.

Two defaults claiming one slot is reported and never resolved. It is a defect identical
on every machine, and picking a winner by load order would make it a different defect
on every reload instead.

### surface

The bindings that are live while this plugin's list is open, plus the presentation
choices that are this plugin's own rather than global policy.

```lua
surface = {
  context = "browserTabs",         -- defaults to name
  primary = { action = "enter", description = "Select" },
  nav     = true,                  -- j, k, i, x, defaults to true
  extra   = { { key = "d", action = "close", description = "Close tab" } },
  matcher = false,                 -- opt out of the shared matcher
  pane    = true,                  -- the docked companion preview
  when    = nil,                   -- defaults to <context>Open
}
```

`matcher` and `pane` live here rather than being ambient because they are per plugin
choices. Three plugins want the words matcher rather than fuzzy, and three want the
preview pane. The rest want neither and say nothing.

**`matcher` names a strategy and nothing else.** It does not say whether the shared
widget filters, and the difference cost a real defect. Four plugins turn the widget's own
filtering off in their own code, because their query is structured rather than a plain
filter, and they then use the injected strategy for their own scoring, one layer further
down. So the two questions are independent and only one of them is the manifest's
business. Which strategy to inject is declared here. Whether the widget filters is the
plugin's own internal decision, already written in its own code, and restating it here
gives it a second place to drift.

Writing `matcher = false` therefore means inject no strategy at all, which is almost never
what a plugin wants. BrowserTabs declared exactly that and the effect would have been to
suppress the strategy its own row ranking reads, silently degrading ranked tabs to
unranked order. It now declares nothing and inherits the default, which is correct.

A binding may carry `needs`, a data or tool name it depends on, and it is dropped when
that name is absent rather than binding a key to nothing. It may carry `repeats`, and
`chord = false` to be listed without being bound.

`panelAs` names the field the docked hint panel's three callbacks arrive under, and its
absence means the flat form, three separate fields. Four plugins read them nested instead,
three under `shortcutPanel` and one under `panel`. That disagreement is real and lives in
those plugins' own configure contracts, so it has to be declared. Assuming one shape
silently removed the panel from all four while handing each three fields it never reads.

This field describes an inconsistency rather than endorsing one. Normalising those four
plugins onto a single shape would delete it, and that is worth doing once the wiring is
proved.

**A user override merges into this block rather than replacing it.** The first attempt
got this backwards and a user changing one key destroyed that plugin's whole context.

### wiring

The steps Olm must run beyond `configure`, in order. Omit it and Olm calls
`configure(opts)` on the plugin root, which is what most plugins want.

```lua
wiring = {
  { target = "manager", method = "configure" },
  { target = "manager", method = "start" },
}
```

`target` absent means the plugin root. A string names a submodule, so `"chooser"`
means `plugin.chooser`. This exists because five plugins keep their picker on a
submodule, and global policy landed on the parent for all five, where the live root
passes none of it.

`method` may be anything, not only `configure`. Without this, WindowManager wired up
completely dead, because `bindToLeader` never ran and nothing anywhere said it should.

A step may declare `args`, a list naming what it receives when the step is not the
ordinary options table. Each entry is a dotted string whose first part says where the
value comes from, because the two sources are genuinely different and a bare name cannot
say which.

```lua
wiring = {
  -- this plugin's own effective declarations, already merged with the user's overrides
  { method = "bindHotkeys", args = { "self.bindings" } },
  -- values the composition root assembles
  { method = "apply", call = "dot", args = { "root.catalog", "root.activeNames" } },
}
```

`self.` is right for a plugin's own data, which is what a binding list is. `root.` is
right for something built from several plugins, which is what KeyRemap's catalog is.
Leaving the namespace implicit was the first version and two readers took it two
different ways.

A step may declare `call`, `"method"` or `"dot"`, defaulting to `"method"`, for the same
reason a sibling need may. A plain function called as a method does not fail cleanly, it
shifts every argument along by one.

`"method"` is colon style, and it is the default for a wiring step's own target for the
same reason it is the default everywhere else in this file. Stage two calls `configure`
through the identical mechanism, with no `call` field of its own to set, so `configure`
is always colon style too, never a separate rule stated twice. `call = "dot"` exists for
the one shape a colon call cannot serve, a target written as a plain function rather than
a method, since a plain function called with a receiver in front of it does not raise, it
silently answers the wrong argument to every parameter after the first. Every module Olm
itself ships, every plugin and every host, is written colon style throughout, so `call =
"dot"` names a real difference in one target's own contract on the day something finally
reaches for it, not a matter of preference between two ways of writing the same thing.

## The stage pipeline

Plugins do not choose when they run. Olm holds one fixed ordered pipeline and a plugin
slots into the stages its declarations earn. The order is not arbitrary and not
derivable, it is a property of the leader engines and the registry, so it is written
once in Olm's root and never computed.

1. **leaders**, every chord engine receives its leader keycodes. A leader not added
   here is silently never wired no matter what `configure` later receives.
2. **configure**, each plugin in dependency order.
3. **wiring**, the declared non configure steps.
4. **predicates**, the table is built and installed into HyperKey. This must land
   before stage 7, because HyperKey treats an unknown `when` as always active, so an
   uninstalled table leaves every navigation key live at all times.
5. **register**, a registry descriptor per tool. It carries `apiVersion` and a
   `category`, and its `surface` is a function. The registry refuses anything else.
6. **activate**, then the open keys read from `registry.shortcuts()`.
7. **contexts**, the navigation bind loop over every surface.
8. **start**, engines last, and the one shared event tap last of all, since it must
   see a complete key set.

Ordering within stage 2 comes from the graph. A sibling need is an edge. **A satisfied
set query is also an edge to every member of that set**, which the first attempt
missed, and missing it wired the launcher before SystemSettings so every settings pane
row silently vanished.

## Checklist for a new plugin

- `manifest.lua` loads with nothing required and touches no `hs`.
- `name` is set unless the identity is exactly the directory.
- Every external binary is in `needs.tools` with a `reason` and an `origin`.
- Every sibling capability names a plugin, a member or the module, and a `call`.
- Every parameter the plugin cannot derive is in `needs.data` with a `breaks` sentence.
- Every default works on a fresh macOS install, or it is not a default.
- A surfaced plugin declares `surface` and does not declare `chooser` or `theme`.
- A plugin that wants a launcher row, a word, or a key declares `registry`, and its `row`
  carries a `category`, without which no row is built.
- `configure` is a colon method, and so is every `wiring` target, unless the step says
  `call = "dot"`. Everything Olm ships is colon. Getting this wrong does not raise, Lua
  binds the module itself to the first parameter and drops the real options, which is a
  picker that never opens with nothing in the console.
- Anything only this plugin's own code could know stays inside it. Its provider order, the
  path one of its own backends needs, and what an empty list means are all its business, and
  a composition root that has to know any of them must be edited every time a file is added.
- Any lifecycle beyond `configure(opts)` is in `wiring`.
- `hs -c "return dofile(...inspect...)"` reports the plugin wired with no problems.
- The plugin is then actually **used**, once, with a real key press. Everything above is
  structure, and a clean plan has never once proven that a key fires.
