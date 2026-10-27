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
rather than left it out. A plugin that does nothing but bind keys is the real case. Its
wiring names one call that is not configure and was never going to be one, so writing an empty
`configure(opts)` beside it would exist only to satisfy a rule rather
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
| `chooser`, `theme`, `placeholder`, `matcher` | a `surface` |
| `dockedPane`, a function answering a docked companion pane, see "The docked pane" below | `surface.pane = true` |
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

Every field is optional except `apiVersion`. A plugin with nothing to claim returns
`{ apiVersion = 1 }` and that is a complete answer, not an omission. This used to name KeyRemap and WindowMemory as the two
worked examples of that, and neither is one any more. WindowMemory is gone, replaced by
Workspaces, and KeyRemap grew a real declaration and then left the plugin set for the core
in phase two of the core split, since the remap serves every leader and no plugin. So the
rule stands and the tree happens to have no example of it right now, which is worth saying
plainly rather than citing a plugin that has moved on.

### apiVersion

The contract version this manifest was written against, a whole number, and the one required
field.

```lua
apiVersion = 1,
```

`lib/plugins.lua` compares it for equality with the spoon's own `obj.apiVersion` while the
manifests are read, so a plugin written against another contract is left out before any of its
code runs, with one console line saying which version it named. Equality rather than at least,
because the contract has changed meaning without changing shape before. The spoon's value is
the one copy of the number. The composition root and the dry gate both read it from there.

The registry also compares an `apiVersion` on every descriptor, and that check cannot fail for
a manifest plugin, since the registrar stamps the core's number onto what it builds. It guards a
descriptor assembled some other way. This field is the check that actually stops a manifest.

### about

What a person reads about the plugin, all optional strings.

```lua
about = {
  title = "Obsidian",
  description = "Search the notes in your Obsidian vaults and open one.",
  author = "Milos Djakovic",
  version = "0.1",
  license = "MIT",
  homepage = "https://example.com",
},
```

`title` is the name a person reads, which may differ from both the directory and the identity.
`description` is one short sentence saying what the plugin does, shown in the Olm Plugins page's
pane beside the highlighted plugin. `version` is the plugin's own, separate from `apiVersion`. A
key outside these six is refused
with the plugin, so a misspelt field is reported where it was written. Nothing here is read by
the wiring, it exists for a page or a listing that describes plugins. `defaults.description`
stays where it is and is not repeated here, since the launcher reads it and a person can
override it.

### name

The plugin's identity everywhere outside its own directory. The directory is lowercase
by convention, the identity often is not, and the two are not the same thing.

```lua
name = "colorPicker",   -- the directory is eyedropper
```

Omit it only when the identity is exactly the directory name. Most surfaced tools differ,
so omitting it is the exception rather than the rule.

This is also the identity a person's own configuration has to use. `cfg.plugins` is keyed by
plugin, each entry holding that plugin's overrides, its `data`, and the `global` it should be
mirrored onto, and it is keyed by the identity a plugin declares for itself here, never by the directory
it happens to live in. Eight plugins in this tree spell the two differently, browsertabs
the directory and browserTabs the declared identity among them, so a person's own file
that copies the directory into either key lands data or a global under a name no plugin
answers to. Olm names the mismatch out loud at compose time rather than merging it into
nothing, but the fix is still to write the identity a plugin claims for itself, never the
folder it was found in.

### icons

The row icons a plugin names, a table of key to a table of source name to value. Pure data like
the rest of the manifest.

```lua
icons = {
  on = { emoji = "🟢", sf = "circle.fill" },
},
```

A row says `icon = "on"` and the stage, and the query scope for launcher scope rows, resolve it
against the icons of the plugin that owns the presentation or the scope, through
`lib/icons/rows.lua`. A row may instead carry a table spec such as `icon = { emoji = flag }` for
a glyph that is content, and a row that carries an `image` keeps it. The registrar refuses a
declaration that is not a table, a key that is not a string, or an entry with no string value for
any source, and an entry may carry `content = true`, which is not a source and only marks the icon
for the dry gate's coverage report.

`defaults.icon` is the plugin's identity icon, read by the launcher row, the action panel and the
scoped list. It is a key into `icons`, or a table spec. The registrar refuses a
key that `icons` does not declare, naming the plugin. A binding, a row and a `registry.row` name
an icon the same way with `icon = "key"`, and `defaults.glyph` and every `glyph` field are gone.
`lib/icons/rows.lua` `image(spec, owner)` is the one function that resolves an owner and a key
or a spec, and a string that is not an identifier, an emoji a person wrote in config, reads as
`{ emoji = string }`. A key a row names that nothing declares logs one warning and the row shows no icon.
Which source draws is the active set in `config/icons.toml`, with the fallback behind it.

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

Validation admits any name that is the basename of a `.lua` file in the spoon's `lib` directory, but only the keys of the root's `libs` table are delivered, so asking for another lib basename passes validation and arrives as nil. The delivered names are `paste`, `cheatsheet`,
`registry`, `glyphicon`, `chordkey`, `leader`, `recency`, `queryassoc`, `storage` and `ui`.
`ui` is the UI kit, one style and one set of drawing primitives, and arrives as one table
holding the primitives, `layout`, `tokens()` for the current light or dark half, and
`measure`. Ask for it whole, with no member.

```lua
lib = { ui = { from = "ui" } },
```

docs/DESIGN-UI-KIT.md is the design and docs/PLUGIN-AUTHORING.md has a worked example under
"Drawing with the kit".

`leader` is not a leader. Every leader is an instance of the core adapter `lib/leader.lua`, which
the root builds and binds on, and a plugin never binds a key, so it never needs one. It answers
its actions through `provides.actions` and suggests keys in `defaults.bindings` on the leader its
`defaults.leader` names by role, and Olm binds every one, see `provides` below. What `leader`
delivers is a view with one method, `isActive`, answering whether any held leader is down right
now, for a plugin that posts a synthetic keystroke and must decide at the press whether to wait
for release, which is the clipboard, since its chosen provider decides. An action that always
waits says `afterRelease = true` on its descriptor instead and asks for nothing, which is
capture. The `hyperkey` and `windowleader` grants this replaced were retired in phase 3 of the
keymap plan.

The root reads every global row the keymap holds on each leader whose policy states a cheat sheet,
HYPER and META on this machine, whichever plugin declared it, and hands each leader's rows to the
one sheet host, `host/leadersheet`, so a key
declared this way appears in the held sheet with no other step, a tool's open key moved to that
leader included. A row's `when` gates the key and its sheet row together, its `repeats` marks a
step worth repeating while the key is held, and its label is its `description`, each the
binding's own where it states one and its action descriptor's otherwise, the sheet humanizing the
action name when neither says. A false predicate makes a window key a swallowed no op and an
unknown name stays active and is warned about once. On every leader a key whose matching bindings
are all gated off is swallowed rather than passed to the app in front, and only a key nothing
binds passes through. Inside an open list the rule reaches further, one rule for every held leader.
While any list is open a held leader answers only its bindings for the open list and swallows
every other key, so with the launcher open Hyper and A or B or C or E is swallowed alike while the
launcher's own keys act, and a leader binding no list key, META here, is inert. Outside lists an
unbound key still passes through. A leader policy no longer says any of this, so `contexts`,
`quietOverLists` and `sealedOverLists`, the three fields that once did, are refused by name with
what replaced each, and `ranked` is the one field left that shapes how a leader resolves a press.

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
  -- the module itself, because the consumer calls the capability with a colon
  actions = { plugin = "windowmanager", policy = "required" },
  -- one member, called with a dot
  rows   = { plugin = "systemsettings", member = "rows", call = "dot", policy = "optional" },
}
```

`member` absent means the module itself. This case is not a convenience. It was
inexpressible before and it is what a consumer of another plugin's whole module depends on.

`ordering` defaults to true, meaning this need is also an edge, so the plugin it names is
wired first. Set it to false when the capability arrives as a closure that reaches its
plugin at call time rather than at configure time. The need still resolves and is still
existence checked, it just contributes no edge.

This distinction is not theoretical. MenuSearch received two Launcher capabilities as
closures, and the live root configures MenuSearch **before** the Launcher. An eager
declaration would have inverted that order for no reason, and in some pairings would produce
a cycle that fails the whole plan. The lesson is that a need and an ordering constraint are
two different statements, and the schema used to be able to make only one of them. Those two
are root published words now, `coveredApp` and `refreshLauncher`, since phase three of the core
split, because a sibling may name another plugin and never a host.

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
publishes the following words. `coveredApp`, the application the launcher opened over and the
id of that open, and `refreshLauncher`, asking the launcher to draw again, both closures over
the launcher for a plugin that works in the app underneath it, MenuSearch, TextCase and WindowSize today. `predicates`, the shared when name to
predicate table every gated binding is resolved against. The leader sheet's `sheets` is not in that
table. It is one record per leader whose policy states a sheet, its keycode, its layout and its
entries, the leader's rows from the keymap in blocks by each plugin's cheatSheetOrder,
so it exists only once the keymap is built after register, and the root hands it to the leader
sheet in its second configure, step K. What a sheet's heading is called follows the role the
leader holds, `policy.roleTitles` read by `lib/leader.lua`'s `sheetHeading`, and no longer a root word. `redraw`, repaint whichever list is on screen,
for a plugin whose own answer lands after the keystroke that asked for it. `notify`,
`showColor`, and `report`, one line of feedback, one sampled colour, and one titled list of
rows each with an icon, a label, and a detail, all drawn on the shared overlay so they read
as part of the same interface as the cheat sheet and the action bar.
`host`, this machine's own identity, for anything a plugin keys per host. `scope`, which
arrangement of displays is attached right now, as one comparable string, so two plugins
that both scope memory to the desk agree on what the desk currently is. `storePath`, where
a plugin keeps data a person is meant to read, edit, and commit by hand.

Four words over the one plugin switch, `lib/pluginswitch.lua`, for a settings page. A choice
is staged in the root and applied later, all at once, with one reload.
`pluginCatalog()` answers a list of `{ identity, directory, about, needs, disabled, lockedBy,
offBecause, pending, after }` for the plugins under `plugins/`, never a host, sorted by about
title, `needs` being sorted names under `tools`, `libs`, `siblings` and `data`, `lockedBy`
being `"config"` for a plugin switched off in `config/plugins.lua` and `"core"` for one a host
requires, `offBecause` being the sorted list of every switched off plugin this one depends on
in this load, or nil, `pending` the staged off state for this identity or nil, and `after`,
present on every row while anything is staged, `{ off, offBecause }` for the state once the
staged set is applied.
`pluginCascade(identity)` answers `{ off, staged, others }`, `off` the state the choice for
this identity sets, `staged` whether that choice is already staged, and `others` the
identities that go off or come back with it, measured against every other staged choice, from
a dry run of the resolver's plan that loads and probes nothing.
`stagePluginSwitch(identity, off)` answers ok and why. It refuses a host, a config locked
plugin and one the core needs, and once a reload is on its way it refuses everything. It writes
nothing. A choice equal to what this load has drops the staged entry, so choosing a row twice
leaves nothing staged.
`applyPluginSwitches(resume)` saves the staged set under `Olm.disabledPlugins` in
`hs.settings`, holding only identities that are still switchable, schedules one reload, and
answers whether anything was staged. `resume`, optional, is the place to reopen after the
reload, described by the caller about itself, `{ tool, path, highlight }`, `tool` the name it
registered under, `path` a list of items its own `select` answers a child for, one per level
down, and `highlight` a flat table of item fields the row to highlight carries. The root leaves
it in a one shot note under `Olm.resume`, `lib/resume.lua`, takes the note once at the end of
the next load and hands it to `stage.presentAt`. The root also applies by itself when the stage
goes away, through `stage.onClosed`, reopening nothing and saying one routine line after the
reload naming what changed, so a page never has to ask for it.

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
permission read on browsertabs' own settings level being the shipped example,
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
  surfaces     = { has = "surface" },
  scopes       = { provides = { "rows", "select" } },
  queryRows    = { provides = { "queryRows" } },
  launcherRows = { provides = { "launcherRows" } },   -- rows that are not actions
  launcherRun  = { provides = { "launcherRun" } },
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
The split is not cosmetic. A query for `rows` alone returns every scopable tool too. A
computed source may also propose `defaults.example`, one short line the launcher's empty
field can wear, which is the only way a person finds out a typed sum answers at all.

`actions` is what a plugin can run, and the one way to declare anything runnable. It names a
member answering a list, or a list itself, each entry a descriptor naming its own action in
`name`. The list's order is the order the plugin's rows take wherever Olm lists its actions,
the launcher's catalog first. The function form is called once, with its module as the receiver,
after every plugin's `configure` and wiring have run and every tool has registered, so a list
built in `configure` is there.

```lua
provides = { actions = "actions" },

function obj:actions()
  return {
    { name = "leftHalf", run = function() self:leftHalf() end,
      description = "Left Half", subtitle = "Window", icon = "windows", kind = "window" },
    { name = "moveLeft", run = function(depth) self:moveByPixels("left", self:_moveStep(depth)) end,
      repeats = true, description = "Move Left", subtitle = "Window", icon = "windows", kind = "window" },
    { name = "exactSize", run = function(size) self:resizeByPixels(size) end, listed = false },
  }
end
```

`name` and `run` are required. `run` is a function called with the hold depth, 0 on the press and
counting up while a key carrying `repeats` is held, and with nothing when the action is chosen as
a launcher row. A caller that is neither may hand its own argument, the window manager's
`exactSize` taking the size Window Size parsed, so an action that reads its argument says what it
expects. Every other field is optional and checked by type where present, `description`,
`subtitle`, `kind` and `app` strings, `icon` a string or a table, `keywords` a string or a list
of strings, `repeats`, `afterRelease` and `listed` booleans, `when` a predicate name, and `group`
a string, a table with a `title` string and an optional `faded` boolean, or a function. `afterRelease = true` says the action posts a keystroke a held leader
would stand in front of, so a key runs it only once the leader that fired it is released and its
launcher row only once no held leader is down, which is capture's case. A field outside that list, or one of the wrong type, refuses that one action with a
problem line naming the plugin, the action and the field, and the rest of the plugin is still
wired. A descriptor with no name is refused by its place in the list, a second one taking a name
already taken is refused while the first keeps it, and a table keyed by name rather than a list,
the shape before phase 2b of the keymap plan, is refused whole, since it cannot say an order.

What each field earns. A binding in `defaults.bindings` names an action by its `name`, and Olm
binds the binding's key on its leader to that descriptor's `run`, the binding's own `when`,
`repeats` and `description` winning over the descriptor's and the descriptor's answering where the
binding is silent. A binding naming an action the list does not hold is reported and left unbound.
Every action that is not `listed = false` is a row of the launcher's own catalog, built by Olm,
its title the `description` or else the name, its subtitle the `subtitle` followed by the chord
the keymap binds the action to, its icon the `icon` read against the plugin's own manifest icons,
its search terms the `keywords`, and its `when` hiding it live exactly while its key is gated.
The row's memory key is the `kind`, else the plugin's identity, joined to the name, so a
descriptor states `kind` exactly when its rows must keep a key the launcher remembered them by
before they were descriptors, and the launcher's catalog scopes narrow by it. Choosing the row runs
the descriptor. A plugin with actions therefore builds no launcher row and declares no
`launcherRows` or `launcherRun` for them. `group` is the section a cheat sheet files the row under, since phase 4 of the keymap plan, a
word, a table `{ title = word, faded = true }` for a section drawn dimmed with its title bright
and placed after every section in full colour, or a function asked with nothing at every show and
answering either, and a row with none goes under the leader's default section, headed by the
role the leader holds, WINDOW MANAGEMENT wherever the window role sits. A plugin's rows sit on a sheet in a block placed by its
`defaults.cheatSheetOrder`, compared with the sheet host's own fifty. `app` is a bundle id the
action stands for, since phase 6. The action is then no launcher row of its own, it merges into
the launcher's row for that app, which shows the action's chord, a plain combination winning that
row over a leader chord, and its sheet row wears the app's icon and name, resolved by Olm, and is
left off a sheet when the app is not installed. Capture, the window manager and the clipboard are
the shipped cases of fixed actions, and Window Size reads the window manager's list as a sibling,
finding `exactSize` by its name and calling `run`.

A list may be built from the plugin's own data rather than fixed in code, answered by a member
that builds it in `configure`, once per load, which is an ordinary case rather than a trick. The
app toggler answers one action per app in its catalog, styled where its toggles list says so, each naming its
app and a group function answering a `RUNNING` table or a `DORMANT` table with `faded = true`, and
System Settings one per pane. A person's keys reach them from `config/keymap.lua`,
`["hyper+S"] = "apptoggler.Safari"`. Keys bind at load, so an action added while Hammerspoon runs
is bindable after the next reload.

```lua
provides = { actions = "actions" },
-- answers, built in configure from data.apps, data.styles and data.toggles
{ { name = "Safari", app = "com.apple.Safari", group = runningGroup, run = focusSafari },
  { name = "Ghostty", app = "com.mitchellh.ghostty", group = runningGroup, run = popupGhostty } }
```

`bindings`, `cheatSheetSections` and `launcherAppDetails` were provides fields until phase 6, the
side channels the app toggler alone spoke, complete key rows built from the person's data, sheet
sections of its own and the launcher's app row details. Each is retired and refused by name with
what replaced it, an action built from data, the descriptor's `group`, and the descriptor's
`app`.

`profile` means this plugin can say which display arrangement is current, which the overlay
resolver asks for without knowing any plugin manages arrangements at all. A value may be
`true` where the capability is a fact about the plugin rather than a member to call, as
`profile` is.

`launcherRows` and `launcherRun` are how a plugin puts rows that are not actions in the
launcher's own catalog and runs the one a person chooses, the launcher asking the set for each
and naming no plugin. An action is never declared this way, since Olm lists every action
descriptor itself, see `actions` above. System Settings declares both for its panes and its
search row. Each pane is also an action, but the row is not, since a row opens its pane and never
hides the app while the action a key runs hides System Settings when it is in front, so the pane
rows stay rows and keep the url they are remembered by. Window Size declares `launcherRun`
alone, since its one row is computed from a typed size and reaches the list as a query row.

```lua
provides = { launcherRows = "launcherRows", launcherRun = "launcherRun" },
```

`launcherRows` is a member answering a list of plain descriptors, asked when the launcher first
builds its rows rather than at load, so a list assembled inside configure is ready. It is the
same shape Olm builds for an action descriptor, which is why a row that names a chord reads one
way whoever built it.

```lua
{ title = "Wi-Fi", group = "System Settings",
  chord = nil,                              -- { leader = role or false, key, mods }, optional
  icon = "wifi",                            -- a key into this plugin's own manifest icons
  when = nil,                               -- a predicate name gating the row live, optional
  keywords = "wifi, wireless, airport",     -- comma separated phrases a person types, optional
  order = nil,                              -- this row's own place, else the plugin's
  item = { kind = "settingsPane", name = "wifi",
           key = "x-apple.systempreferences:com.apple.wifi-settings-extension",
                                            -- what it is remembered by, else the name
           remember = nil } }               -- false keeps it out of every memory
```

`keywords` is a string or a list of strings, comma separated phrases a person would actually
type to find the row that are not in its title, a synonym, an abbreviation, an old or an Apple
name, a closely related task. A few phrases, never a title word, never a generic word such as
settings, the or app, never a sentence. Each matches where one of its words starts with a query
word or where the phrase is typed run together from its start, always below a title match, and a
query's words match on their own with a bonus when all land in one phrase in order.
PLUGIN-AUTHORING.md says more.

A row is data and never a function, because the launcher hands every row to `hs.chooser`,
which drops a row holding one without a word. The subtitle is either a finished `subTitle` or
the parts, `group` and `chord` with its leader named by role, or `false` for a plain combination
the glyph renderer spells whole, which the launcher spells with the shared chord speller so a row
and the action bar print the same words for one key. The
root stamps the plugin's identity on every item as `owner`, always, over anything the row
arrived with, so a plugin cannot route a row into another plugin's runner, and on the row as
`iconOwner`. The launcher routes a chosen row by that owner, so `launcherRun` is handed the whole
item back after the chooser has closed and focus has returned, and reads whatever fields it put
there itself. An owned row is never asked for an alias hint, never taken by the root's intercept
for a registered tool or a scope of the same name, and when its owner runs nothing it still
reaches the launcher's plain kinds, a computed value copied or an app opened, but never
`special` or `scope`.

Identity belongs to the row. The launcher remembers a row as its `kind` joined to its item's
`key`, or to its `name` when it states no key, so choose them once and keep them. A row whose
kind or key changes is a new row to the recency memory and to the query memory, and every pick a
person made under the old key is forgotten. System Settings states each pane's url as its key,
which is the key the launcher persisted for a pane before rows were contributed. `remember =
false` keeps a row out of both memories, for a row computed from what was typed, Window Size's
typed size being the shipped case. Two contributors answering one kind and one key are named on
the console with both owners when the launcher builds its rows. `app`, `calc`, `scope` and
`special` are the launcher's own kinds, and a contributed row may use `special` only for a name
no registered tool has. A member named here that resolves to nothing on the real module is named
by the dry gate and on the console rather than failing in silence.

Where a row sits is a number, `defaults.launcherOrder` in the contributing plugin's manifest,
which a person overrides in `config/plugins.lua` like any default and which the root stamps on
every row of that plugin that states no `order` of its own, the rows Olm builds from its action
descriptors included. The launcher's own declared rows and the rows of its own descriptors, lock
and sleep, take its own `defaults.launcherOrder`, its declared alias directory first. The
registry's rows lead the catalog, and a row whose owner is a registered tool with a row of its own
follows that tool's row directly, which is where the clipboard's three action rows sit, beside
Clipboard history, as they did when they were registry commands. Every other row follows sorted by
its number, a row with none after every numbered one, a tie keeping the launcher's own declared
rows first and then the suppliers' own order, the set's suppliers first and then the plugins with
actions in plan order, then each supplier's own order of rows. The shipped numbers reproduce the order the list has
always had.

| Rows | Number | Declared in |
|---|---|---|
| Capture's screenshot actions | 10 | `plugins/capture`, `defaults.launcherOrder` |
| The System Settings search row | 20 | `plugins/systemsettings`, `defaults.searchRow.order` |
| The alias directory, lock and sleep | 30 | `host/launcher`, `defaults.launcherOrder` |
| The window actions | 40 | `plugins/windowmanager`, `defaults.launcherOrder` |
| The System Settings panes | 50 | `plugins/systemsettings`, `defaults.launcherOrder` |

Leave gaps when choosing a number, so a plugin added later can sit between two without anybody
renumbering.

A plugin's rows on a leader's held cheat sheet are the keymap's rows on that leader, each filed
under its descriptor's `group`, see `actions` above. No plugin supplies a section of its own since
phase 6 of the keymap plan. Where a plugin's rows sit on a sheet is `defaults.cheatSheetOrder`,
compared with the sheet host's own number for every row whose plugin states none, the blocks in
ascending order and a plugin with no number among the host's.

```lua
defaults = { leader = "app", cheatSheetOrder = 10 },
```

| Rows | Number | Declared in |
|---|---|---|
| The app toggles, running then dormant | 10 | `plugins/apptoggler`, `defaults.cheatSheetOrder` |
| Every other chord bound on a leader | 50 | `host/leadersheet`, `defaults.cheatSheetOrder` |

What an installed app's launcher row shows beyond the app is the chord of an action whose
descriptor names that app in `app`, which Olm works out from the descriptors and the keymap, so no
plugin answers anything for an app row. A chord on a leader reads as the leader's name and the
key, `Open · Hyper F`. A plain combination is spelled by the glyph renderer and followed by its
action's description, ``Open · ⌥` Terminal placed``, and wins the row over a leader chord on the
same app, since it is on no cheat sheet and the row is the only place it is found. Choosing an app
row focuses or cycles the app, whatever action's chord it shows.

### registry

How this plugin appears in the tool registry, which is what gives it a launcher row, a
searchable word, a base key, and a place in the cheat sheet. Pure data, and every function
is named as a **member** the registrar resolves lazily against the loaded module rather than
captured now, because two real tools build their surface inside their own `configure` and
anything captured at declare time would capture nothing, permanently and silently.

```lua
registry = {
  row = { category = "Tools", icon = "filesearch", detail = "...", keywords = "..." },
  open = "show",                                  -- a colon method on this plugin's root
  surface = "chooser",                            -- this plugin's own submodule
  hosted = true,
  shortcut = "leader",                            -- or "global"
  scope = {
    -- Reached through the submodule they actually live on, since a bare name is walked
    -- against the plugin ROOT. This example named them bare for a while and a real manifest
    -- copied it, which built a scope, registered it, resolved its word, and answered an empty
    -- list to every keystroke, with nothing raised anywhere.
    rows = { member = "chooser.scopeRows", call = "dot" },
    run  = { member = "chooser.activate",  call = "dot" },
  },
}
```

A member is a bare string for a colon method on the plugin root, or a table carrying
`member` and `call`. A dotted member reaches a submodule, `chooser.scopeRows`. `surface`
may be `true` to mean the plugin root itself.

`row` is what a person reads. Its `category` is required for a row to exist at all, and
`description`, `icon` and `aliases` come from `defaults` rather than being retyped here, so one
answer serves the row, the cheat sheet and the scope directory. The chord the row names is the
tool's open row in the keymap, the `defaults.bindings` row whose action is `open`, which the
launcher asks the root for by the tool's name.

`row.bundle` is a bundle id for a tool that fronts exactly one application, and it puts that
application's real icon on the launcher row in place of the drawn icon, resolved by the
launcher at row build. The icon stays declared as the fallback for every other surface and
for a machine where the bundle resolves to nothing. Obsidian is the consumer.

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

`shortcut = "leader"` binds the tool's open row on the leader that row names, its own role or
else `defaults.leader`, the window leader included, and `shortcut = "global"` binds it as a plain
combo. Olm's keymap holds it as one row and binds it like every other, and the window sheet,
which reads the keymap, lists it on whichever leader it sits. A tool on the window leader used to
be refused at wiring, while the registrar bound a tool's key on Hyper alone, and that refusal is
gone.

`commands` retired in phase 2b of the keymap plan. They were named actions belonging to a tool,
each with its own key, row and shortcut, and a second way beside `provides.actions` to declare
something runnable. The clipboard's append copy, paste next and manage history are action
descriptors now, their keys rows of the clipboard's `defaults.bindings`. A manifest still
declaring `registry.commands` is named on the console with what replaced it, and the registry
refuses a descriptor carrying commands.

**This block is the source and `cfg.registry` is only an override.** The composition root
merges any per identity override over what the manifest declares, per field. It used to be
the reverse, a separate undocumented table that `describe` refused to build any registration
without, so a fresh install registered zero tools out of twenty seven, silently, with every
base key bound to nothing and the cheat sheet empty. A plugin with a complete manifest is now
registered by that alone.

### defaults

What this plugin proposes, which the person may override. A key, a list key and an alias are
overridden in `config/keymap.lua` and nowhere else, see The person's keymap below, and every other
default in the plugin's entry in `config/plugins.lua`.

Each concern has one way, and this table is the whole of it.

| Concern | The one way |
|---|---|
| What a plugin can run | `provides.actions` descriptors |
| Which keys a plugin suggests | `defaults.bindings` |
| Which words a plugin suggests | `defaults.aliases` |
| A plugin's lists and their verbs | its `surface` block |
| A person's keys, list keys and aliases | `config/keymap.lua` |
| A plugin's data and its switch | `config/plugins.lua` |
| Which physical key is remapped | Olm's leader catalog |

A default names a leader **role** and never a physical key, so a person who moves the
app role to SUPER with `roles = { app = "super" }` carries every default with it.

```lua
defaults = {
  leader = "app", description = "Emoji & symbol picker",
  icon = "emoji", aliases = { "e", "emoji" },
  bindings = { { action = "open", key = "j" } },
},
```

`bindings` is the one place a plugin suggests a key. Each row names an `action`, a `key` and
optional `mods`, and a tool's or a host's own open key is the row whose action is `open`. A
plugin with a `presentation` may also suggest a row whose action is `cycle`, which the keymap
binds to the stage's cycle of that presentation, the list shown bare and stepped by repeated
presses of the key, rather than to its present, see Cycling a list in PLUGIN-AUTHORING.md. A
cycle row on a plugin with no presentation is refused by name. A row
may name its own `leader` role, or `leader = false` for a plain combination on no leader, which
must then state its `mods`, since a bare key with neither would be taken from every app. The one
exception is a key no app reads, which lib/keycodes.lua names, `globe` alone today, the key macOS
posts for a tap of fn. A row
naming no leader inherits `defaults.leader`, which is what that field is, the default role every
row of the plugin takes, and a person who overrides it moves every such row at once.
`defaults.key` and `defaults.mods` retired in phase 2b of the keymap plan, each a second way to
suggest the open key, and a manifest still declaring either is named on the console with the
open row that replaced it. `config/plugins.lua` refuses `key`, `mods`, `leader`, `bindings`,
`surface` and `aliases` since phase 7 of the keymap plan, each with one problem line naming
`config/keymap.lua`, which is where a person writes every key, list key and alias.

**The person's keymap.** `config/keymap.lua` reaches Olm as `cfg.keymap` and no plugin ever
reads it, so nothing here changes for a plugin. It has five sections.

- `keys`, a chord to an action id or `false`. A chord is a leader or modifiers joined by `+`, the
  key last, compared without case. The leaders are `hyper`, `meta` and `super`, one per leader
  catalog row, and any name in `leaders`. The modifiers are `shift`, `ctrl`, `alt`, `cmd` and
  `fn`, and `fn` is refused on a held leader, which compares only the other four. The keypad plus
  is `pad+`, and the main row plus is written as its unshifted key, `shift+=`. An action id is the plugin or host identity, a dot,
  and the action, the descriptor's `name` or `open` for a tool's or a host's open row,
  `vpn.open`, `windowmanager.leftHalf`, `apptoggler.Safari`,
  `systemsettings.General`, `launcher.lock`. An action named there takes exactly the chords listed for it and loses its
  defaults, and its new rows copy the gate, label, repeat and function of the row it had.
- `leaders`, a name to a list of real modifiers, `nav = { "shift", "ctrl" }`, a leader of its own
  on the modifier trigger, with no sheet and no tap, named on a launcher row by its name.
- `roles`, a role word to a held leader, `{ window = "super" }`, moving every default on the role.
  The words are `app` and `window`, which a plugin's global defaults name, and `list`, which every
  default list key rides, Olm's own `all` layer and every manifest's surface keys alike, so
  `{ list = "meta" }` moves every default list key to META. A plugin never names the list role, its
  surface keys ride it because they are surface keys.
- `aliases`, a plugin identity to its words, replacing its `defaults.aliases` exactly.
- `lists`, the keys live while a list is open, one table per list keyed by its `surface.context`
  and `all` for every list, each a chord to a surface action name or `false`. A list chord names
  its leader as a global chord does, any held leader, and moves only itself. A chord with no held
  leader, `ctrl+j`, a named leader's chord or a bare `tab`, is answered by the open list's own
  default chooser field and never claimed from another app, and one that would type into the field
  or that the field already reads is refused. A shared
  verb is named `primary`, `secondary`, `selectNext`, `selectPrev`, `close`, `openActionPanel` or
  `showKeys`, and any other
  action by the name its `surface` gives it. `all` is laid first and each list's own table over it,
  and `all` moves and frees only keys from Olm's own layer, so a key a manifest states for a shared
  verb, the launcher's `close.key`, moves only in that list's own table.
  A list chord may shadow a global chord while its list is open, since collisions are checked within
  the global layer and within each list's layer by leader, modifiers and key, never across them. A binding listed with
  `chord = false` is the list's own and no person setting.

A person's chord on a slot a default holds wins it and the default row is dropped, said in one
routine console line and never a problem, and `false` frees a chord. Every entry Olm cannot read,
a chord that does not parse, an id naming nothing, a leader name that clashes, a role naming no
held leader, an alias for no plugin, and two of the person's own chords on one slot, is a problem
line naming the entry. A held leader is remapped only while some bound row uses it.

A default is admissible only if it works on a fresh macOS install with nothing
configured. Two things disqualify one, and they are different. A missing binary
degrades, so the default may ship and announce what it lost. Missing local knowledge
cannot ship at all, which is why VPN correctly proposes nothing.

Overrides resolve as follows. A list replaces wholesale. A map merges per key. A plugin
level `false` switches the whole plugin off, see Switching a plugin off below. `defaults.NONE` removes a single key, and it
exists because overloading boolean `false` made a meaningful `false` impossible to
express, which silently broke `matcher = false`.

`bindings` is not overridden here at all since phase 7 of the keymap plan. A person moves or frees
any row in `config/keymap.lua`, `["hyper+Q"] = "vpn.open"` or `["hyper+P"] = false`, so the open
row's old exception to the list rule, and `key = defaults.NONE` or `key = false` unbinding it, went
with the field. A registered tool with a leader shortcut left with no open row is named in the
wiring report, since it would have no key, unless the person's keymap moved or freed it.

#### Switching a plugin off

There is one switch. A plugin is off when its entry in `config/plugins.lua` is `false` or when
its identity is in the set a settings page saved, and the root merges the two before anything
loads. Only a plugin under `plugins/` can be switched off. A host is core, and a host written
`false` or saved is refused with a console line rather than honoured.

A switched off plugin's code never runs. Its `init.lua` is not loaded, its tools are not
declared or probed, its predicates and live labels are not harvested, and it is in no set, no
list and no key. Its manifest still reaches the resolver, which reports it as switched off, a
choice rather than a failure. A plugin that REQUIRES a sibling that is switched off goes off
with it and is reported as off because of that plugin, named, never as blocked. A plugin that
only optionally uses one loads without that part and says nothing about it, so write an
optional sibling knowing it may simply be absent. Whether a plugin runs is decided once per
load, so a change takes one reload. The registry activates every tool that registered, there is
no second switch.

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

`example` is a default whose only actual reader is a host rather than the plugin proposing
it, and it belongs to a computed row source. It still arrives as `opts.example` on the
proposing plugin's own `configure`, exactly as the rule above says every default does,
simply unread there, since neither arithmetic's nor convert's own configure asks for it. It
is one short line for the launcher's empty field, `Try 128 * 4` from arithmetic, or a list of
several lines when one plugin covers more than one capability worth teaching, convert's own
four lines for currency, temperature, weight, and speed being the case that needed the list
form. The launcher rotates through its own base wording plus every line that arrived, a
uniformly random pick each open that is never the one the immediately previous open just
showed, so two opens in a row still read two different things without any hint being locked
into a fixed position in the pool. That is what a computed row has instead of the
discoverability a bound key and a launcher row give every other tool, since typing is the
only way one could ever be found.

Declare each line whole rather than the expression alone, for the reason `category` is a
whole word here, the source owns how it reads and the host decides nothing about its wording.
Keep every line at or under twenty eight characters, about what the field holds, since
nothing truncates it and nothing drops it for being too long, a clipped hint being visible
and fixable where a silently discarded one would look like a feature that never arrived. A
source proposing nothing contributes nothing and the field keeps saying exactly what it said
before. No host names a source, the composition root reads this field off each source's own
effective defaults on the same walk that assembles the sources that declare `queryRows`,
flattening a list into as many pool entries as it carries, so a plugin declaring `queryRows`
and added later joins the rotation with no edit anywhere, and one left out for a missing tool
takes every line it proposed with it rather than advertising something this machine cannot
do. A claiming source is a different case. QueryScope is prepended to the launcher's own
`queryProviders` outside that same walk, since it claims the whole query rather than
proposing a row for it, so it is never asked for an example and could not join the rotation
by declaring one.

### surface

The bindings that are live while this plugin's list is open, plus the presentation
choices that are this plugin's own rather than global policy.

```lua
surface = {
  context = "browserTabs",         -- defaults to name
  primary = { action = "enter", description = "Select" },
  secondary = { action = "reveal", description = "Reveal" }, -- optional, Command and Return
  nav     = true,                  -- the two move keys, defaults to true
  extra   = { { key = "d", action = "close", description = "Close tab" } },
  pane    = true,                  -- the docked companion preview
  when    = nil,                   -- defaults to <context>Open
}
```

The keys of the shared verbs, the primary, the secondary, the two move keys, close, the action
panel and the key panel, are not the plugin's. They are Olm's own `all` layer, `lib/keymap.lua`'s
`listDefaults`, `i`, `j`, `k`, `x` and `o` on the leader the `list` role lands on, HYPER unless
the person's `roles` section moves it, and Command and Return for the secondary and Command and ?
and Command and slash for the key panel, keys the default chooser's field answers with no leader. `lib/surface.lua` builds each verb on its key and holds
no key itself, which the dry gate checks. A key a manifest states, an `extra` row's or a `close.key`
such as the launcher's, is that list's default, laid over the `all` layer, and rides the same role,
so a surface key names no leader. A person moves any of
them in the `lists` section of `config/keymap.lua`, never here and never in `config/plugins.lua`.

`secondary` is optional, the second thing a list does with its highlighted row, the same shape as
`primary` and checked the same way, with `needs`, `repeats` and `icon` allowed and any other field refused,
a key among them and `chord`, since `chord = false` would leave the action bar naming a key nothing
binds. It sits on Command and Return and on Command and keypad Enter. `primary.icon` and
`secondary.icon` name a key of the manifest's `icons` for the two rows in the action panel, checked
by the dry gate's scan like an extra row's, and a list naming none shows Olm's own Return and
Command icons, declared in the action panel's manifest. It is built right after the primary, so the action panel lists the two
together, and its action is answered by the plugin's surface adapter like any `extra` row's. A list
declaring none binds nothing on Command and Return, which keeps choosing the row there. The action
bar under the list names the primary on Return, the secondary on its chord and the action panel on
its own, `docs/PLAN-ACTION-BAR.md`.

`matcher` and `pane` live here rather than being ambient because they are per plugin
choices. Since phase three of the unified search on 2026-10-17 no plugin names a matcher, and
since phase four the launcher ranks through the shared search too, so no list matches or ranks
its own rows, and the dry gate refuses one that does, `test/drygate-search.lua`. Five want the
preview pane. The rest want neither and say nothing.

### The docked pane

`pane = true` earns `opts.dockedPane`, a function answering a new pane from
`lib/dockedpane.lua`. Call it once, in configure, with a spec, and keep what it answers. The
pane owns the canvas, docking it on the companion rect, the shared surface underneath, the
shared empty state, the scroll and its clamp, the hide guard and the teardown, and draws text
through the kit the root built it with. A plugin keeps only what it draws.

```lua
local pane = opts.dockedPane({ scroll = true, thumb = false, emptyText = "Highlight a file" })

pane.dock(companionFrame)                      -- from onPositioned, repaints what is current
pane.show(function(ui, view) return node end)  -- one kit node, laid out in the padded box
pane.draw(function(view) return els, overflow end) -- several regions drawn by hand
pane.show(describe, { keepScroll = true })     -- a refresh of the same content
pane.clear()                                   -- the shared empty state
pane.scrollBy(points)                          -- positive is further down, answers whether it moved
pane.hide()                                    -- onPositioned(nil, nil), the swap away
pane.destroy()                                 -- onClose
```

Every spec field is optional. `scroll` lets content taller than the pane scroll, `thumb` draws
a thumb at the right edge while there is more than fits, and `emptyText` replaces the shared
empty state's default line. A describer is a function of the kit and the view, so a redock or a
change of appearance repaints from the same description. A painter is for a pane made of
several regions, a fixed header over a scrolled body, or a cached block under a live one, and
answers its elements and how far the content overflows, which the pane clamps the scroll
against. The view carries `frame`, `inner`, the padded box content is laid out in, `viewport`,
the box inside the border scrolled content is cut at, and `scrollY`. `pane.inner()` answers the
padded box once docked and nil before, for a plugin that caches a layout by its size.
`pane.isEnabled()` answers whether anything can be drawn, which is what a member spec
`paneWidth` should report, so a root that granted no pane gets the list with no companion rect.

**`matcher` names a strategy and nothing else.** It does not say whether the shared
widget filters, and the difference cost a real defect. Which strategy to inject is declared
here. Whether the widget filters is the presentation's `matcher` below. Four plugins once
turned the widget's filtering off and scored rows with the injected strategy themselves, and
since phase four of `docs/PLAN-UNIFIED-SEARCH.md` none may, since a call of a matcher outside
`lib/chooser` is a dry gate finding. FileSearch still reads the injected strategy, to ask its
sources for a word the way the search keeps it and to fill its retain cap with kept rows first,
and both lines carry a `search-exempt` reason since neither orders a shown row. Since the phase
four rework the dry gate also refuses any value here but absent or false in a plugin or a host,
a strategy name included, so every plugin takes the root's one strategy.

Writing `matcher = false` therefore means inject no strategy at all, which is almost never
what a plugin wants. BrowserTabs declared exactly that and the effect would have been to
suppress the strategy its own row ranking reads, silently degrading ranked tabs to
unranked order. It now declares nothing and inherits the default, which is correct.

A binding may carry `needs`, a data or tool name it depends on, and it is dropped when
that name is absent rather than binding a key to nothing. It may carry `repeats`, and
`chord = false` to be listed without being bound.

`panelAs` once named the field a docked hint panel's three callbacks arrived under. The panel was
retired on 2026-10-23 for the action bar drawn inside the chooser's own canvas, so nothing arrives
under it and a manifest stating it is ignored.

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
  rowCount    = 2,                                       -- optional, a plain number or a member spec
  paneWidth   = 320,                                     -- optional, a plain number, true, or a member spec
  matcher     = false,                                   -- optional, false only where the field is not a search, with a search-exempt reason
  titleLineBreak = "truncateMiddle",                     -- optional, a plain string
  searchText  = { member = "searchText", call = "dot" }, -- optional
  rowLimit    = 200,                                     -- optional, a positive whole number
  labels      = { member = "labels", call = "dot" },     -- optional
}
```

Every field but `rowCount`, `matcher`, `titleLineBreak` and `rowLimit` is either a member spec or, for `paneWidth`
and `rowCount`, may be either one, `rowCount` as a member being asked on every show and clamped to the
default ten, for a list whose height follows its own length, the same `{ member, call }` shape
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
`preview.isEnabled()` answering `false` when no docked pane was granted among the ways.
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
migrations opened rather than one either brief anticipated. Since phase two of the unified
search a row may also carry `pinned`, `fromQuery`, `tier` and `bonus`, which
`lib/chooser/rank.lua` states. A row setting either of the first two is never scored or dropped,
so they replace a false matcher wherever the only reason for one was a row that must always show.
Under a typed query a `fromQuery` row, made from what was typed, leads the ranked rows and a
`pinned` row, a door or a placeholder, trails them, and on an empty query both keep the
supplier's order. `matcher` is `false`, meaning the field is not a
search and the supplier owns what shows, the one case that stays for an input page or a confirm,
which says so with a `-- search-exempt, <reason>` comment on the line or the line above, since the
dry gate refuses a false matcher without one. The registrar still accepts a string naming a
strategy in `Chooser.matchers`, the identical table `root/compose.lua` already resolves this word
against for every consumer that still builds its own instance, but the dry gate refuses one in any
plugin or host since the phase four rework, since search never differs per list. No presentation
names one since phase three of the unified search, and absent inherits the root default, the version
one behaviour, unchanged for every plugin that names nothing here. The registrar checks a
declared string against the real strategy names at register, the same loud refusal `rowCount`
and `paneWidth` already get, since a typo left to `host/stage`'s own `_resolveMatcher` would
fall back to the root default in silence with nothing anywhere naming the misspelling.
`host/stage` writes the resolved value onto `self._instance.matcher` before every show and
swap, present, push, and pop alike, the identical live mutation discipline `paneWidth` already
follows for `layout.companionWidth`, since `legacy.lua`'s own `Chooser:_build` reads `self.matcher`
fresh on every keystroke rather than once at construction.

`searchText` and `rowLimit` came with phase three of the unified search,
`docs/PLAN-UNIFIED-SEARCH.md`, and say how the rows are searched beside the matcher.
`searchText` is a member, called with the raw text of the field, answering the text
`lib/chooser/rank.lua` ranks by, so a field with a grammar of its own, FileSearch's root and
extension or the clipboard's kind, keeps that grammar in its plugin while the shared search ranks
the word. The supplier still receives the raw text. An empty answer ranks nothing and keeps the
supplier's order, as an empty field does, and an answer that raises or is not a string does the
same and is said in the console. `rowLimit` is the most rows shown that are neither `pinned` nor
`fromQuery`, cut after ranking, for a list of thousands of rows, since the provider styles every
row it is handed. The registrar refuses a `searchText` that is not a member spec resolving to a
function and a `rowLimit` that is not a positive whole number. `host/stage` hands both to the
instance as the second argument of `setMatcher` before every show and swap, so a presentation
declaring neither clears them, and the instance answers them as the second value of `matcher()`.
A scope declares the same two under `registry.scope`, and `host/queryscope` refuses either in a
wrong shape. The action panel takes them off the instance while it is open and gives them back as
it closes. A row may also carry `names`, a list of further names never shown, which
`rank.lua` states.

`labels` came with the action bar, `docs/PLAN-ACTION-BAR.md`. It is a member, called with the
highlighted item, answering a table with `primary` and `secondary` strings, the words the action bar
under the list and the action panel give the two for that row. It is asked live, every time the bar
is drawn, so "Uninstall 4" can count what is checked. A string left out, an empty one, a raise or
an answer that is not a table falls back to the next rule, `liveLabels`, then the binding's own
`description`, then Open for the primary and the action name spelled as words for the secondary.
`host/stage` asks it of the level on screen with the item last highlighted outside the action
panel, so the panel's own rows never reach it. `liveLabels` stays, the clipboard its one user.

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
parent's own name so the action bar and `stage.current()` still answer something a context can
be found under, though a child whose own level genuinely wants different keys in the action bar may
still name itself. A child inherits nothing else, so one that wants its own words for the primary
and the secondary hands its own `labels` function. Backspace on an empty field needs no hook from the plugin, `Stage:pop` already
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

A row number is the chosen row only while nothing above it moves, so the stage holds the
highlight on the same item instead whenever the item states a `key`. That holds across every
repaint that keeps the person on the same level, a "stay", a `redrawPresented` without
`resetRow`, and any other refresh, and it holds under a typed query, where the item is found in
the list as filtered and ranked, the order the provider shows. A row appearing above, the
Plugins page's own Apply now row after Back or a permission line landing in a settings list,
then leaves the highlight where the person put it. An item with no `key`, or a key no row
carries any more, keeps the row number exactly as before, so give every row of a list that can
grow or shrink above the highlight a stable key.

`onScroll` is a third addition the trickle migrations found rather than either contract brief
naming, `function(points)` for a trackpad or a wheel scrolled over the companion rect, which a
canvas cannot report for itself, `lib/chooser/providers/legacy.lua`'s own reason it exists at
all. filesearch and clipboard both already wired one directly into their own retired
`Chooser.new` calls, config read live on every scroll exactly the way `onHighlight` already is,
so `host/stage` routes it the identical way, a presentation with none simply never asked.

`onRightClick` is a fourth, found alongside `onScroll`, `function(item, row)` for a canvas row
right clicked, which a native chooser row cannot answer for itself either. clipboard's own
retired `Chooser.new` call is the only consumer anywhere, and `host/stage` routes it the
identical way.

`onPositioned` is called with `chooserFrame, companionFrame`, the same two frames
`lib/chooser/providers/legacy.lua`'s own `config.onPositioned` already hands its caller, once
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
since the docked hint panel that call fed was atom level policy the stage re anchored itself, and
that panel was retired on 2026-10-23 for the action bar inside the chooser's own canvas. And FileSearch's own seed of the first pane paint
reads `picker:selectedItem()` directly, `plugins/filesearch/chooser.lua:449`, which needs its
own instance to still exist by the time it runs, an instance that plugin stops holding once it
migrates. Docking the pane's own content stays this plugin's own business exactly as it is
today. The canvas that content lands on has since moved into core, see "The docked pane"
above, and a plugin's `onPositioned` now hands the companion frame to `pane.dock`. `host/stage`'s own `paneAnchor(chooserFrame, companionFrame)` is the one true copy of
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
presenting plugin by its resolved identity, never by its declared context, while the action
bar still looks a context up in `plan.contexts`, keyed by the context a plugin declared.
The two agree today because every presenting plugin spells its context exactly as its
identity, and the registrar warns, one console line naming both words, phase three review
finding ten, the moment a plugin ever lets them diverge, since that plugin would route, gate,
and present correctly while its own action bar silently lost its keys.

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
for those bindings once they fire, never whether they exist. The action bar is atom level policy
`host/stage` owns for the life of its one instance rather than something a presentation carries,
built once by the composition root over `stage.current()` and asked again on every redraw, so a
presenting plugin declares nothing for it beyond its `surface` and, optionally, `labels`.

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

`method` may be anything, not only `configure`. Without this, WindowManager once wired up
completely dead, because its binding step never ran and nothing anywhere said it should. No
step binds a key any more, Olm binds every key from the keymap, and the dry gate refuses a bind
call under `plugins/` and `host/`.

A step may declare `args`, a list naming what it receives when the step is not the
ordinary options table. Each entry is a dotted string whose first part says where the
value comes from, because the two sources are genuinely different and a bare name cannot
say which.

```lua
wiring = {
  -- this plugin's own effective declarations, already merged with the user's overrides
  { method = "start", args = { "self.settings" } },
}
```

No shipped step takes `args` today. The two that did were the binding steps the keymap retired,
which took `self.bindings`, and the shape stays for the next step that is not `configure(opts)`.
`self.` is right for a plugin's own data and for a lib grant, which arrives under the field name
the plugin declared it by. `root.` is right for
something built from several plugins, which is what the shared predicate table is.
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

1. **leaders**, every leader in use is named in the record. Each one arrives built whole,
   its keycode and trigger included, since phase 3 of the keymap plan, where the window
   leader once had to receive its keycode here or be silently never wired. Since phase 5 which
   leaders are in use is known only once the keymap is built, so the record names them after
   stage 6 though the report still lists the stage first.
2. **configure**, each plugin in dependency order.
3. **wiring**, the declared non configure steps.
4. **predicates**, the table is built and installed into every leader. This must land
   before stage 7, because a leader treats an unknown `when` as always active, so an
   uninstalled table leaves every navigation key live at all times.
5. **register**, a registry descriptor per tool. It carries `apiVersion` and a
   `category`, and its `surface` is a function. The registry refuses anything else.
6. **activate**. Then the root names every retired field a manifest still declares, asks every
   plugin for its `provides.actions`, builds the keymap from every
   declaration, and binds every global row through the one binder, in the order the paths it
   replaced bound them, plugin bindings in plan order, a host's own actions among them, then the
   registry's tools, then the hosts' open keys. The person's keymap is laid over the defaults in
   that build, and the leaders its bound rows use are the leaders in use.
7. **contexts**, the navigation bind loop over every surface, each key onto the held leader it
   names, a default on the leader the `list` role lands on.
8. **start**, leaders last, and the one shared event tap last of all, since it must
   see a complete key set.

Ordering within stage 2 comes from the graph. A sibling need is an edge. **A satisfied
set query is also an edge to every member of that set**, which the first attempt
missed, and missing it wired the launcher before SystemSettings so every settings pane
row silently vanished.

## Checklist for a new plugin

- `manifest.lua` loads with nothing required and touches no `hs`.
- `apiVersion` equals the spoon's `obj.apiVersion`, and `about` carries at least `title` and
  `author`.
- `name` is set unless the identity is exactly the directory, and any `cfg.plugins` key a person writes for this plugin uses that identity, never the
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
- A plugin that wants a launcher row, a word, or an open key declares `registry`, and its `row`
  carries a `category`, without which no row is built. The key is a `defaults.bindings` row
  whose action is `open`.
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
- Any lifecycle beyond `configure(opts)` is in `wiring`, and no step binds a key. What the
  plugin can run is `provides.actions`, a list of descriptors that also gives every listed
  action its launcher row, and the keys it suggests are `defaults.bindings`.
- `hs -c "return dofile(...inspect...)"` reports the plugin wired with no problems.
- The plugin is then actually **used**, once, with a real key press. Everything above is
  structure, and a clean plan has never once proven that a key fires.
