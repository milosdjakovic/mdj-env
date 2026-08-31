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

This is the whole reason the manifest is short. Every plugin that opens a list needs the
shared chooser factory and the shared theme. None of them declare either, because each one
already declares `surface`, and declaring a surface is what makes a plugin one that opens a
list. The entitlement follows from the role. Writing `chooser` and `theme` into every one of
those manifests would be retyping global policy in each, which is the exact defect this
design exists to remove, and it would give just as many places for that policy to drift.

So the manifest answers what is true about this plugin alone. Olm answers what follows
from that.

### What is ambient, and what earns it

| A plugin gets | when it declares |
| --- | --- |
| `chooser`, `theme`, `placeholder`, the panel triple, `matcher` | a `surface` |
| `surface` elements and `emptyState`, the docked companion pane and its quiet state | `surface.pane = true` |
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
complete answer, not an omission. This used to name KeyRemap and WindowMemory as the two
worked examples of that, and neither is one any more. WindowMemory is gone, replaced by
Workspaces, and KeyRemap grew a real declaration once it was understood that shipping with
the system is an origin rather than a reason to stay silent. So the rule stands and the tree
happens to have no example of it right now, which is worth saying plainly rather than
citing a plugin that has moved on.

### name

The plugin's identity everywhere outside its own directory. The directory is lowercase
by convention, the identity often is not, and the two are not the same thing.

```lua
name = "colorPicker",   -- the directory is eyedropper
```

Omit it only when the identity is exactly the directory name. Most surfaced tools differ,
so omitting it is the exception rather than the rule.

This is also the identity a person's own configuration has to use. `cfg.data` is keyed by
plugin, and `cfg.globals` says which spoon global a plugin should be mirrored onto, and
both are keyed by the identity a plugin declares for itself here, never by the directory
it happens to live in. Eight plugins in this tree spell the two differently, browsertabs
the directory and browserTabs the declared identity among them, so a person's own file
that copies the directory into either key lands data or a global under a name no plugin
answers to. Olm names the mismatch out loud at compose time rather than merging it into
nothing, but the fix is still to write the identity a plugin claims for itself, never the
folder it was found in.

### needs.tools

An external binary or bundle, and now the only place a tool is ever declared. A second
system used to exist beside this one, a plain file placed next to the code that wanted a
tool, and the running config read both. That system is gone, every such file has been
deleted, and nothing in this config reads one any more. A tool a plugin needs lives in
this field or it is not declared at all. The reason is not tidiness. The same tool named
in two places drifts, one answer changes and the other does not, and nothing anywhere
watches the two agree with each other, so one source is the only version of this that can
be trusted a year from now.

Presence is proven by `kind`, `path` for a command on PATH, `system` for a fixed absolute
path, `app` for a macOS bundle id, `manual` for a marker path.

`policy = "required"` means the plugin is not wired at all when the tool is absent,
because a dead surface is worse than no surface. `policy = "optional"` means the plugin
loads degraded and Olm says on the console what was lost.

`unit` names the file inside the plugin that actually wanted the tool, written as
`unit = "engine"` or `unit = "sources/hidden"`, and it is optional, since most plugins are
small enough that naming the plugin alone already says where to look. Where it is given,
two readers use it. Olm stamps a missing tool's owner label from it, so a console line
about an absent tool names the file responsible rather than the whole plugin, and the
collector that builds this module's upward facing dependency manifest stamps the same
label into that file's consumer column. This precision used to come for free from where a
separate declaration file happened to sit beside the code that needed it. Now that a
plugin declares everything in one manifest, a field is what carries the same precision
instead.

`stage` says when the tool is needed, `"runtime"` by default, or `"dev"`, or `"test"`. A
dev tool regenerates a dataset a plugin ships, and a test tool drives an integration
harness, and the running configuration never touches either kind while it is open and in
use. Declaring them anyway, under the stage that names what they are actually for, is what
keeps a tool only tooling uses from being the one category nothing checks.

One thing reads the field today. `lib/services.lua` grants the scoped `deps` adapter only to
a plugin with at least one runtime stage tool, so a plugin whose tools are all dev or test
never receives a door it would have no runtime use for. Nothing else reads it. The layer
above deliberately does not, since a dev tool still has to be installed on a machine somebody
develops on, so the generated manifest carries every stage and the map answers for all of
them. `lib/plugins.lua` used to carry an `installList` that would have been the natural second
reader, and it was deleted on 2026-08-20 having never once been called. A stage therefore keeps
no install list honest, and rather than leave a function sitting there implying otherwise, the
honest state is that this field has exactly one reader and the sentence above names it. Anyone
wanting an install report should write it against the manifest shape of the day rather than
resurrect thirty lines that were never run.

`origin` says where to get the tool, and it lives here rather than only in a map at Olm's
own root, because a plugin that travels to another machine has to carry that answer with
it. Its keys are `brew`, `cask`, `tap`, `xcode-clt`, `macos`, and `manual`, and an entry
carries exactly one of them. The detail is a formula, cask, or tap name for the first
three, and a plain sentence for the other two. `xcode-clt` needs the bracket form because
of the hyphen in the key, so it is written
`origin = { ["xcode-clt"] = "xcode-select --install" }`.

The repository also keeps a complete map of these same answers at its own root,
`DEPENDENCIES.map`, so the same fact exists twice on purpose. What makes that safe rather
than a second place for the answer to drift is that a reconciler one layer up reads both
and refuses to let them disagree, on the origin itself and, for the three package manager
origins, on the detail too. The duplication is not an oversight this contract missed. It
is the thing that makes carrying the answer inside a portable manifest safe to do at all.

```lua
tools = {
  { name = "qalc", kind = "path", policy = "required", unit = "engine",
    reason = "the calculator that answers a unit conversion",
    origin = { brew = "libqalculate" } },
  { name = "jq", kind = "path", policy = "optional", stage = "test", unit = "test/harness",
    reason = "reads what the integration harness gets back from a run",
    origin = { brew = "jq" } },
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

Naming a `member` means saying how it is called, exactly as `needs.siblings` does, and the
default is `"method"`.

```lua
lib = {
  apply = { from = "paste", member = "pasteText", call = "dot", policy = "optional" },
},
```

**Get this wrong and nothing anywhere will tell you.** A plain function bound as a method
receives its own module in the first parameter and every real argument shifted along one,
which Lua performs without complaint. Four declarations shipped without it. Text case could
neither read a selection nor apply a case, so the picker it opens after the read never opened
at all, choosing an emoji inserted nothing, and every chord printed in a launcher subtitle was
drawn from the wrong two arguments. All four looked correctly wired from every direction
except pressing the key.

Every function under `lib/` today is a plain one, `function M.pasteText(text)`, so a lib member
wants `call = "dot"` unless you have read the source and found a colon.

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

### The root fan out

A `needs.data` entry with `source = "root"` says a value exists and that the composition
root is the one that knows it, and delivering that half of the contract works differently
from every other field in this document. A root sourced value is not addressed by plugin
at all. It is addressed by FIELD NAME, through `services.fanOut`, so a plugin earns a copy
by declaring a need under the same word the root publishes it under, and which plugin is
doing the asking makes no difference whatsoever.

The composition root builds one table of these values, keyed by field name, and today it
publishes the following words. `activeNames`, which leader names are actually live on this
keyboard, KeyRemap's own contract. `mapping` and `windowManagement`, the identical stamped
window binding table handed to WindowManager and WindowCheatSheet under the two different
names their own configure calls happen to read, so a row that names a key and the dispatch
that acts on it can never be allowed to disagree. `predicates`, the shared when name to
predicate table every gated binding is resolved against. `leaders`, what the window
leader's own overlay section is called, since the leader's own name says nothing to
somebody reading a list of window actions. `redraw`, repaint whichever list is on screen,
for a plugin whose own answer lands after the keystroke that asked for it. `notify` and
`showColor`, one line of feedback and one sampled colour, both drawn on the shared overlay
so they read as part of the same interface as the cheat sheet and the docked hint bars.
`host`, this machine's own identity, for anything a plugin keys per host. `scope`, which
arrangement of displays is attached right now, as one comparable string, so two plugins
that both scope memory to the desk agree on what the desk currently is. `storePath`, where
a plugin keeps data a person is meant to read, edit, and commit by hand.

And the presenting plugin's own set, review finding L4, none of these named here until the
rework following the trickle migrations, which is what let one of them, `stageSetPlaceholder`,
be declared, validated, reported satisfied, and delivered nowhere for a whole migration,
review finding H2. `stagePresent(name)` asks the registry for `name`'s own presentation and
hands it to `stage.present`, the hotkey door for a plugin whose own leader key no longer
builds a window itself. `redrawPresented(name, resetRow, token)` asks the stage to re run
the current presentation's rows if, and only if, the level the caller belongs to is still
the one showing, `resetRow` optional and forwarded straight to `Stage:refresh`. An async
answer lands on its own level or not at all, review finding M2, rework, docs/BRIEF-
CONTRACT-V3.md, and `token` is what makes that precise rather than approximate. Without one,
`name` alone means the tool's own top level, checked by table identity against the
registrar's own stored presentation for that name, `wiredRegistry.presentationFor(name)`,
the one thing every level of a tool can be compared against that its shared `name` cannot,
since a child inherits its parent's name for hints and routing, decision two, and so cannot
be told apart from it by name alone. A tool with no children, which is most of them, never
notices the difference, its top level is always what `presentationFor` answers and matching
by name or by that table means the same thing. Given `token`, a presentation table a plugin
closed over while building a child, the check becomes `Stage:isCurrent(token)` instead,
identity against whatever is actually current, so a child's own async operation, a
permission read on browsertabs' own settings and browser levels being the shipped example,
redraws itself specifically and nothing else, self referential locals, `local child; child =
{ ... }`, being how a plugin gets a table to close over before that table exists to be
returned. `stageHide()` hides the shared window outright. `stagePop()`, contract v3's own addition, docs/BRIEF-CONTRACT-V3.md, asks the stage
to leave the current child the way Backspace on an empty field already does, `Stage:pop`
restoring the parent and answering false at the bottom exactly as that press does, for a
row that must leave a level rather than drill into one, the one shape a child returned from
`select` cannot express since a child only ever pushes, never pops. Called from inside a
presentation's own `intercept`, decision three's reserved case, a row that mutates the list
it is on and stands, the leaving being the mutation and the parent left standing being what
the list becomes. `stageSetQuery(text)` and `stageSetPlaceholder(text)` write the field's text and
its placeholder directly, for an inner level that changes what the box means without the
presentation closing, the way a manage history page or a parent row's own step up both do.
`stageSelectedItem()` answers the item under the highlight on the live widget, guarded so a
closed stage answers nil rather than whatever was last highlighted before it closed, review
finding H6, the fix for three module local caches that answered exactly that. `stageSelectedRow()`
is the same question by row number, for a background correction that has to know whether a
person has moved off row one before it is safe to redraw. `stageTextBudget()` and
`stageTextWidth(str, which)` answer the pixel room a row's text has and how wide a candidate
string renders in it, for a plugin whose own subtitle elides to fit. Every one of these
degrades to an inert press or a silently skipped redraw when the declaring plugin's own
`needs.data` entry names it as optional, which every one of them should, and none of them
exists for one plugin specifically, they exist for the question a presenting plugin with no
instance of its own left to ask directly, and today's declaring plugin is only ever today's
one answer.

A root sourced field name is therefore GLOBAL VOCABULARY. Two plugins that both declare
`needs.data.scope` receive the exact same value, which is the point, it is what lets one
display fingerprint serve every plugin that scopes its own memory by arrangement. It also
means the word has to mean one thing across the whole set. A plugin that invents its own
name for something the root already publishes under a different word gets nothing for its
trouble, since the fan out has no way to pay a debt nobody wrote down, and that plugin is
left blocked or degraded exactly as it would be if the root had never built the value at
all.

`storePath` cannot be one shared object the way the others are, since a store path is a
place a plugin writes its own data, and handing two plugins the same string would have
them silently overwrite each other's file with no error anywhere. `services.perName(fn)`
is the escape built for exactly this shape. It marks a root value as one `fanOut` must
compute once per declaring plugin rather than share whole, calling `fn(pluginName)` for
each plugin that asked instead of handing every one of them the same object. It exists for
this one case rather than as a general lazy value, since wrapping anything else in it would
only move the same work somewhere else and stop a flat table of values from reading like
one.

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
    -- Reached through the submodule they actually live on, since a bare name is walked
    -- against the plugin ROOT. This example named them bare for a while and a real manifest
    -- copied it, which built a scope, registered it, resolved its word, and answered an empty
    -- list to every keystroke, with nothing raised anywhere.
    rows = { member = "chooser.scopeRows", call = "dot" },
    run  = { member = "chooser.activate",  call = "dot" },
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

`row.detail` is display text when it is a string, which is nearly every row. It may instead
be a member spec, the table form only, and the registrar then resolves it lazily exactly as
it resolves `open`, so the launcher asks the plugin for the words at read time and the row's
subtitle can depend on the world at open time. The member answers the detail string, and any
answer that is not a plain string falls back to the row's static subtitle. The launcher asks
on every keystroke, so such a member caches its answer per launcher open, keyed by the open
id the launcher hands over beside the covered app. A bare string here is never read as a
member name, since a string detail already means words a person reads, which is also why the
dry gate checks only the table form against the real module. TextCase is the consumer, its
row saying up front that nothing is selected.

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

**A default is delivered on the same `opts` table every wiring step reads, not only the
one `configure` receives.** A submodule configured as a later wiring step sees the same
table, so a default named the same as a value that submodule already reads for itself
arrives twice, once through whatever the plugin root actually meant to pass and once more
as the ambient default sitting on the same table, and whichever lands second wins. This
cost a real picker once. A default proposed under the same name as a value a file search
submodule resolves for its own use arrived at that submodule as a plain string where a
table was expected, and the picker crashed instead of opening. Naming a default is
therefore not only a question of what a fresh install should propose, it is a question of
whether that name collides with something one of this plugin's own submodules already
reads off opts, and nothing checks that for you, so it has to be asked by hand every time.

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

### presentation

Phase three of the chooser stage build, docs/BRIEF-HANDOFF.md. A plugin declares this block
when it shows its own rows through host/stage, the one host owning the single live chooser
instance every presenting plugin shows into, rather than calling `Chooser.new` and building
a window of its own. VPN was the first plugin to declare it, phase three's own proving
consumer, and it no longer stands alone. The trickle and final batch migrations,
docs/PLAN-CHOOSER-STAGE.md, moved every remaining list in this configuration onto the shared
stage, so thirteen of the twenty four manifests under `plugins/` carry this block today
rather than building a picker of their own, every list bar the ones that were never a chooser
to begin with, an app toggle or a window action among them. The launcher is the one
presenting consumer with no manifest at all, being a host rather than a plugin, and builds
its presentation table directly in `host/launcher/init.lua`.

```lua
presentation = {
  rows        = { member = "rows", call = "dot" },      -- required
  select      = { member = "select", call = "dot" },    -- required
  placeholder = { member = "placeholder", call = "dot" }, -- optional
  onPresent   = { member = "onPresent", call = "dot" },  -- optional
  enter       = { member = "enter", call = "dot" },      -- optional
  intercept   = { member = "intercept", call = "dot" },  -- optional
  back        = { member = "back", call = "dot" },       -- optional
  onHighlight = { member = "onHighlight", call = "dot" },-- optional
  onScroll    = { member = "onScroll", call = "dot" },   -- optional
  onRightClick = { member = "onRightClick", call = "dot" }, -- optional
  onClose     = { member = "onClose", call = "dot" },    -- optional
  peekPreview = { member = "peekPreview", call = "dot" },-- optional
  onPositioned = { member = "onPositioned", call = "dot" }, -- optional
  rowCount    = 2,                                       -- optional, a plain number
  paneWidth   = 320,                                     -- optional, a plain number, true, or a member spec
  matcher     = "words",                                 -- optional, false or a strategy name
  titleLineBreak = "truncateMiddle",                     -- optional, a plain string
}
```

Every field but `rowCount`, `matcher`, and `titleLineBreak` is either a member spec or, for `paneWidth`
alone, may be either one, the same `{ member, call }` shape
`registry.open` and `registry.scope` already resolve, with one deliberate tightening. **A presentation member
must be the table form and must state `call` itself, `"dot"` or `"method"`, never the bare
string shorthand and never left to default.** Every other member spec in this whole contract
lets a bare string default `call` to `"method"` in silence, and for most of them that default
is harmless, since a wrong guess there fails loud, an arity mismatch on a call nobody expected
to work. A presentation's own `rows` and `select` run on every keystroke a presenting tool's
list receives, so a wrong default there fails quiet instead, `callMember` calls a plain dot
function as a method, and the module table lands where the first real argument belonged,
shifting everything after it along by one rather than raising anything. Phase three's own
review named this residue, the identical shape `docs/AUDIT-2026-08-13.md` already recorded
once for a sibling need bound the wrong way, and the registrar now refuses a presentation
member that leaves `call` unstated, the same refusal named below for a member that does not
resolve at all. The words themselves are the presentation contract's own, BRIEF-STAGE.md
version one plus phase three's own addition, `rows`, `onSelect`, `placeholder`, `onPresent`,
`intercept`, `back`, `onHighlight`, `onClose`, `peekPreview`, plus the geometry brief's own
two additions, `onPositioned` and `paneWidth`, docs/BRIEF-GEOMETRY.md, plus contract v2's own
pair, `matcher` and `enter`, docs/BRIEF-CONTRACT-V2.md, plus contract v3's own widening of
`select` itself to answer a child presentation table, docs/BRIEF-CONTRACT-V3.md, with one
deliberate difference. This block calls the contract's `onSelect` field `select` instead, the same word
`provides.select` and `registry.scope.run` already use for a plugin's own selection member,
so one plugin never has to name the same function two different ways depending on which part
of the config is asking.

`onPresent` is called with no arguments whenever this presentation becomes current, through
either door, `stage.present` or `stage.push`, never on `stage.pop`, which restores a
presentation rather than making it current through either door. It exists for a plugin
whose own rows depend on something async nothing else has necessarily warmed, VPN's own
location fetch being the case that named it, phase three review finding two, a launcher row
choosing a presenting tool used to swap onto whatever the plugin's own module happened to
hold already, empty on a fresh load, since nothing on that path used to call the plugin's
own fetch at all.

`paneWidth` and `onPositioned` are the geometry brief's own pair, and they arrive together
because the first is meaningless without the second. `paneWidth` is a plain number in points,
or `true` to inherit the chooser's own width, the atom's own `layout.companionWidth` semantics
carried one layer up. `host/stage` writes the current presentation's own `paneWidth` into that
same field on the shared instance before every show, present, push, and pop alike, adversarial
review finding M6, so a cold show computes the pair's centering natively, through the atom's
own arithmetic, rather than painting a lone chooser first and correcting it by hand a beat
later. A swap still moves the window itself, since it triggers no show the atom would
reposition on its own. `_resolvePaneWidth` on the stage reimplements the identical cap at
`layout.paneMaxW` for that manual arithmetic rather than reaching for the atom's private one.
Absent, `false`, or a non positive number all mean this presentation reserves no pane. Both
this field and `rowCount` are checked for their own type at register, a non number, or the
member spec shape every field but `matcher` and `titleLineBreak` takes, refusing the whole
registration loudly rather than reaching the stage as something that could corrupt the one
instance it never rebuilds, adversarial review finding H3.

`paneWidth` may also be a member spec, added in the rework following the trickle migrations,
review finding M1. A plain `true`, the value every one of the three trickle plugins first
shipped, papers over a viewer or a companion surface that resolves to no pane at all,
filesearch's own `quicklook.companionWidth()` answering `0` and Processes' own
`preview.isEnabled()` answering `false` when `opts.surface` was never injected among the ways.
A member spec resolves once, at register, the identical moment and the identical reason
`placeholder` already does, since by register every plugin's own wiring has already settled
which viewer or which surface won, so the answer is the real reservation rather than a number
frozen before it existed.

`titleLineBreak` is a plain string, restored in the rework following the trickle migrations
after the first pass silently dropped it, the one field of a plugin's own retired `layout`
block with nowhere else to travel once that whole block stopped existing. Where a title too
long for its row loses characters, `"truncateMiddle"` for FileSearch's own filenames, since
the last few characters of a filename are its extension and a tail cut, the atom's own
default, loses exactly the one thing a middle cut could have kept. `host/stage` writes it
onto `layout.titleLineBreak` before every show and swap, the identical live discipline
`matcher` already follows rather than a value resolved once at construction, and a
presentation naming none of its own resolves back to `"truncateTail"`, the atom's own default
inherited at configure.

`matcher` and `enter`, contract v2, docs/BRIEF-CONTRACT-V2.md, close the two gaps the trickle
migrations opened rather than one either brief anticipated. `matcher` is `false`, meaning the
supplier owns filtering, exactly what filesearch and clipboard already ask their own standalone
`Chooser.new` for, or a string naming a strategy in `Chooser.matchers`, the identical table
`root/compose.lua` already resolves this word against for every consumer that still builds its
own instance, `words` for processes among them. Absent inherits the root default, the version
one behaviour, unchanged for every plugin that names nothing here. The registrar checks a
declared string against the real strategy names at register, the same loud refusal `rowCount`
and `paneWidth` already get, since a typo left to `host/stage`'s own `_resolveMatcher` would
fall back to the root default in silence with nothing anywhere naming the misspelling.
`host/stage` writes the resolved value onto `self._instance.matcher` before every show and
swap, present, push, and pop alike, the identical live mutation discipline `paneWidth` already
follows for `layout.companionWidth`, since `native.lua`'s own `Chooser:_build` reads `self.matcher`
fresh on every keystroke rather than once at construction.

`enter` is a member, called with one function, `proceed`, in place of the stage showing this
presentation immediately. Processes' own documented rule is that its picker never appears
before its async scan lands, and `present` and `push` both used to call a presentation's own
`onPresent` and then show synchronously on the same call, with nothing able to delay the
second half. A tool declaring `enter` is handed `proceed` instead, and nothing about the stack
or the window moves until that presentation calls it, so the tool that must gather something
first controls exactly when its own first row means anything, while whatever was already
showing, the launcher included, stays up and answerable in the meantime. `proceed` takes no
arguments and answers `true` when it actually made the presentation current and `false`
otherwise, added in the rework following the trickle migrations, review finding H4, so a
caller queuing more than one `proceed` behind a single slow gather can tell which one, if any,
was honoured rather than assuming its own call succeeded merely because it was allowed to run.
A second call to the same `proceed` is a silent no op, and a call that arrives after the stage
has moved on, a person escaped, a completed selection or any other real dismissal tore the
atom down, or a different present or push already ran, is dropped the same way, `host/stage`'s
own generation counter being what tells the difference; the atom's own teardown bumping it too
is itself a rework fix, review finding H3, since without it a proceed still in flight when a
person dismissed what was showing would show itself back over whatever they returned to. A
tool declaring `enter` is responsible for its own timeout, the way VPN's and menu search's
async walks already arrange their own, since the stage will wait on `proceed` forever otherwise
and a person left on a launcher row that silently does nothing has no way to know why. The
stage never learns why a presentation deferred or what it was waiting for, only that it did.

**Child presentations, contract v3, docs/BRIEF-CONTRACT-V3.md.** `select`, the contract's own
word for `onSelect`, may answer a presentation table instead of nothing, and answering one means
the row was never a completion, it was a drill into a level of its own. `host/stage` pushes the
answered table as a child of the presentation that produced it, the identical door a launcher row
already pushes a tool through, so choosing such a row swaps the shared window in place with no
close and no reopen. Every field on this list may differ per child, its own `paneWidth`, `matcher`,
`placeholder`, `rowCount`, or `titleLineBreak`, or be left absent to resolve to the ordinary
default the way any other presentation's absent field already does, since a child is not a
distinct kind of table, it is an ordinary presentation table that happened to arrive through a
return value rather than through a call to `stage.present` or `stage.push`. `name` may be left off
a child, the one field this contract otherwise requires, and `host/stage` fills it in from the
parent's own name so the docked hint bar and `stage.current()` still answer something a context can
be found under, though a child whose own level genuinely wants different hint content may still
name itself. Backspace on an empty field needs no hook from the plugin, `Stage:pop` already
restores whatever sits below the top of the stack, which is the parent the moment a child sits
above it, the identical mechanism that already returns a launcher row's own tool back to the
launcher. A child answering nil from its own `select`, the ordinary case at any depth, still means
what a completion has always meant on this contract, the whole stack tears down, since nothing
about `onClose`'s own unconditional clear on a real dismissal changes for this.

The mechanism rides the existing `intercept` chain inside `host/stage` rather than adding a
second hook, since `intercept` is already the one gate every selection path, Return,
`insertSelected`, and a click alike, passes through before `hs.chooser` is ever allowed to
complete a row natively, and a child pushed there never lets that native completion happen
at all, which is the only way the window can stay open through the swap. A plugin writes no
`intercept` of its own to get this, `select` returning a table is the whole of what it does.
`intercept` itself, when a presentation still declares one, keeps meaning exactly what it
always has, a row that mutates the list it is on and stands, the reserved case neither a
child nor a completion could express, since the row does not want a new list, it wants the
same list with a different count. Contract v3 decision three names that boundary outright, a
plugin needing levels declares no `intercept` and returns children from `select` instead,
and a plugin needing in place mutation keeps `intercept` exactly as before, and the two are
not expected to mix on the same row.

The mandate for that reserved case is answering the string "stay", not true. Answering
"stay" rebuilds the list without moving the highlight off the row that was chosen, which is
what a mutation in place owes the person, the clipboard's own prune page and the OLM
settings placement page's own two option rows both being shipped examples, a delete
redrawing counts in place and a choice moving a marker in place respectively. Answering
plain true is reserved for a wholesale swap of the list, where the rows before and after
share no correspondence a held highlight could mean anything by, and the atom rebuilds from
the top instead. Any answer besides these two, including nil and false, is not an
interception at all, and a row that mutates the list it stands on and only ever answers true
is the wrong shape now, not merely an older style.

`onScroll` is a third addition the trickle migrations found rather than either contract brief
naming, `function(points)` for a trackpad or a wheel scrolled over the companion rect, which a
canvas cannot report for itself, `lib/chooser/providers/native.lua`'s own reason it exists at
all. filesearch and clipboard both already wired one directly into their own retired
`Chooser.new` calls, config read live on every scroll exactly the way `onHighlight` already is,
so `host/stage` routes it the identical way, a presentation with none simply never asked.

`onRightClick` is a fourth, found alongside `onScroll`, `function(item, row)` for a canvas row
right clicked, which a native chooser row cannot answer for itself either. clipboard's own
retired `Chooser.new` call is the only consumer anywhere, and `host/stage` routes it the
identical way.

`onPositioned` is called with `chooserFrame, companionFrame`, the same two frames
`lib/chooser/providers/native.lua`'s own `config.onPositioned` already hands its caller, once
the pair has been repositioned for this presentation, whether the atom placed it natively on a
cold show or the stage placed it by hand on a swap, both converging on the stage's own
`_onPositioned`, adversarial review finding M2. `companionFrame` is nil both when this
presentation declared no `paneWidth` and, once, when this presentation is the one a transition
is leaving, told with both frames nil so its own pane consumer hides rather than sitting drawn
beside a window that already moved on, adversarial review finding H2, fired on every door,
present, push, and pop, before the incoming side is given anything.

A plugin migrating its own companion pane onto the stage in phase five carries its existing
`onPositioned` function largely intact, not unchanged. Three things still move. It has to
become a resolvable module member, since a manifest member spec can only name one, and all
three of today's pane consumers keep theirs as a file local function instead, in
`plugins/filesearch/chooser.lua`, `plugins/processes/chooser.lua`, and
`plugins/clipboard/manager/ui.lua`. It drops its own call to `cfg.onPositioned(anchor)`,
since the docked hint panel is atom level policy the stage now re anchors itself, through
`paneAnchor` below, on every path that has real frames to report, and a plugin still making
that call would be a second, competing writer of the identical panel, finding M2's own residue
had this file's first draft not corrected it. And FileSearch's own seed of the first pane paint
reads `picker:selectedItem()` directly, `plugins/filesearch/chooser.lua:449`, which needs its
own instance to still exist by the time it runs, an instance that plugin stops holding once it
migrates. Docking the pane's own content stays this plugin's own business exactly as it is
today. `host/stage`'s own `paneAnchor(chooserFrame, companionFrame)` is the one true copy of
the anchor arithmetic three plugins each carried their own copy of before this phase, the
single call worth knowing about for the docked panel's own anchor, and it is the stage's own
call to make now, never a migrating plugin's.

`rows` and `select` are required. A plugin naming neither, or naming one without the other,
IS refused outright, `lib/registry.lua`'s own `presentationIsWellFormed` refuses the whole
registration the same way a malformed `scope` already does, structural rather than partial,
since a presentation with a hole in either of these two is not a presentation anything could
show.

**Every named member is checked against the real, loaded module at register, and a name
that does not resolve, or a member whose own `call` was left unstated, refuses the whole
registration, loudly, naming the tool and the field.** Phase three review finding four,
`docs/AUDIT-2026-08-13.md`'s own failure class reopened, a manifest naming a member that had
been deleted or misspelled, with nothing anywhere reporting it. This check is what makes
checking `rows` and `select` for existence, not merely for shape, safe to do at register at
all, since by then every plugin's own wiring step has already run and the module this checks
against is the real, finished one. A member this block leaves undeclared is never checked,
since there is nothing there to be wrong. A refused registration is recorded in
`wire.record.problems` too, not only logged, the identical path a malformed `scope` already
takes, `lib/registry.lua`'s own `presentationIsWellFormed` refusing an intentionally empty
presentation this file hands it in place of the broken one, so a load report can never say
no problems while a tool has silently vanished from the catalogue.

Every field the registrar resolves into a member becomes a closure on the presentation
table it hands to `registry.presentationFor(name)`, resolved fresh against the real module
on every call rather than once when this plugin wired, the identical laziness `registry.open`
and every scope action already keep, so a plugin that builds one of these functions inside
its own `configure` is still found once that has actually run. `placeholder` is the one
exception. It is called ONCE, at register time, stage five of the eight fixed stages, and
the plain string it answers is what the presentation table carries from then on, since the
presentation contract wants a value a presentation carries, not a function to call again
later. By register time every plugin's own wiring step has already run, so a placeholder
member that reads live state, VPN's own `available` flag among them, answers the real
answer rather than one frozen before that state existed.

`name` is never declared here. The registrar stamps the plugin's own resolved identity onto
it, the same identity `registry.presentationFor` is keyed by, so a presentation always
answers to the one name the rest of this configuration already knows it by.

**A presenting plugin's own `surface.context`, when it names one, should spell the identity
exactly.** `isShowingFor`, the surface adapters loop, and `stage.current()` all route a
presenting plugin by its resolved identity, never by its declared context, while the docked
hint bar still looks a context up in `plan.contexts`, keyed by the context a plugin declared.
The two agree today because every presenting plugin spells its context exactly as its
identity, and the registrar warns, one console line naming both words, phase three review
finding ten, the moment a plugin ever lets them diverge, since that plugin would route, gate,
and present correctly while its own hint bar silently went empty.

**A presenting plugin declares `registry.surface` only when it carries verbs beyond the five
generic ones.** `isShowing`, `selectNext`, `selectPrev`, `insertSelected`, and `hide` for a
plugin's own picker are answered by `host/stage`'s own `surfaceFor(identity)`, resolved by
the composition root the moment `registry.presentationFor` answers something for that
identity, checked lazily on every access rather than once when the adapter was built, phase
three review finding one, since nothing has registered yet at the point that adapter is
assembled, and `surfaceFor` always wins those five regardless of what `registry.surface`
names. Review finding M3, the trickle migrations. All three declare `registry.surface`
anyway, because all three carry extra verbs bound in `surface.extra`, Processes' `refresh`,
`sortByLoad`, and `stopForced`, the clipboard's `appendSelected`, `deleteSelected`,
`manageHistory`, `leaveManageHistory`, and two scroll keys, FileSearch's seven more, none of
which live anywhere but the declared surface object. `root/compose.lua`'s own
`surfaceAdapterFor` falls through to it for exactly those names, once the stage's own five
have been asked and answered nothing, so leaving the field out would silently drop every one
of those bound keys rather than leave dead weight. A plugin presenting with no verbs beyond
the five, VPN and menu search among them, still declares none. `registry.open` still stays,
and still matters, it is what this plugin's own leader key binds to directly, the hotkey
door, and what an unmigrated fallback would still call if `presentationFor` ever answered nil
for a name it used to answer for.

**`surface` itself is unchanged and still required.** `context`, `primary`, `nav`, and
`extra` are what `plan.contexts` is built from and what the navigation bind loop still binds
a presenting plugin's own keys against, `presentation` only changes which object answers
for those bindings once they fire, never whether they exist. `panelAs` stops mattering to a
presenting plugin's own `configure` and to the composition root alike. The docked shortcut
panel is atom level policy `host/stage` owns for the life of its one instance rather than
something a presentation carries, and the one such panel that matters for the stage is now
its own dedicated instance, built once by the composition root with a context resolver that
asks `stage.current()` on every reveal, never a nested or flat reading of any one plugin's
own `perPluginData` entry, so `panelAs` answers nothing for a presenting plugin's own panel
either way.

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
- `name` is set unless the identity is exactly the directory, and any `cfg.data` or
  `cfg.globals` key a person writes for this plugin uses that identity, never the
  directory.
- Every external binary is in `needs.tools` with a `reason` and an `origin`, and nowhere
  else, since a manifest is the only place a tool may be declared. A tool named by `unit`
  when more than one file inside the plugin could plausibly want it, and staged `dev` or
  `test` when the running configuration never touches it.
- Every sibling capability names a plugin, a member or the module, and a `call`.
- Every parameter the plugin cannot derive is in `needs.data` with a `breaks` sentence,
  and a `source = "root"` entry names a field the composition root actually publishes
  through the fan out, never a word this plugin invented for itself.
- Every default works on a fresh macOS install, or it is not a default, and its name is
  checked against every value this plugin's own submodules already read off opts, since
  a collision there silently overwrites what the plugin root meant to pass.
- A surfaced plugin declares `surface` and does not declare `chooser` or `theme`.
- A plugin that wants a launcher row, a word, or a key declares `registry`, and its `row`
  carries a `category`, without which no row is built.
- A plugin that shows its own rows through the shared stage rather than building its own
  `Chooser.new` declares `presentation`, with `rows` and `select` required. It declares
  `registry.surface` only if `surface.extra` binds a verb beyond the five generic ones,
  since host/stage answers those five for it once presentationFor answers something but
  falls through to the declared surface for anything past them.
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
