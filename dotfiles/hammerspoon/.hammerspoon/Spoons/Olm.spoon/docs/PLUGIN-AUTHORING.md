# Writing an Olm plugin

A recipe, read top to bottom before you write a line. It tells you the smallest thing that
works, what that smallest thing already buys you, what each extra field costs and earns, and
which of your mistakes the wiring layer will shout about before you ever press a key.

`docs/PLUGIN-CONTRACT.md` is the reference. It answers every field in full, with the defect
each one exists because of. This page does not repeat it. When you want depth on a field,
go there.

## The shape

A plugin is a directory under `plugins/`. Discovery is a scan, so adding one is a new
directory and zero edits anywhere else.

`manifest.lua` returns pure data. It must load with nothing required and must never touch
`hs`. Olm reads it before anything initializes, so a manifest that requires a module has
broken the contract even when it happens to work.

Every manifest opens with the contract version it was written against and, optionally, what a
person reads about it.

```lua
return {
  apiVersion = 1,

  about = {
    title = "Obsidian",
    author = "Milos Djakovic",
    version = "0.1",
    license = "MIT",
  },
  -- everything else
}
```

`apiVersion` is required and must equal the spoon's own `obj.apiVersion` in `init.lua`. A
manifest without it, or naming another number, is left out before any of its code runs. `about`
takes `title`, `author`, `version`, `license` and `homepage`, all strings, and refuses any other
key, so a typo is reported rather than shown blank.

`init.lua` returns the module and exposes `configure(opts)`, unless the manifest declares
`wiring` steps that stand in for it. Everything else `init.lua` exposes, the manifest
declares.

Write `configure` as a colon method, `function M:configure(opts)`. The wiring layer's
default call for configure is a method call, so a plain dot function receives the module
table where opts belongs, every granted service lands one argument to the right, and the
plugin reads nil for all of them while the wiring report says no problems. Obsidian
shipped exactly that for a day, every grant silently false, and nothing anywhere raised.
A plugin that wants a dot called configure declares it as a wiring step with `call =
"dot"` instead of relying on the default.

## Declare three things

If your plugin shows a list, it shows that list through the shared stage. You do not build a
window. You declare a presentation, and three fields inside it are required.

```lua
presentation = {
  rows   = { member = "rows",   call = "dot" },
  select = { member = "select", call = "dot" },
},
```

Plus a name, which you do not write here. The presentation's name is the identity Olm
registered you under, your directory unless `name` says otherwise, and the registrar stamps
it. Hints, navigation, and the "is this tool showing" question all route by that identity, so
if you also declare `surface.context`, spell it the same word.

`rows` is a function of the typed query answering the row tables the picker already takes. It
runs on every keystroke, so it is a read of something you already hold, never a scan.

`select` is a function of the chosen row, run when that row completes. The contract table
calls this field `onSelect`, and the manifest calls it `select`, deliberately, because
`provides.select` and `registry.scope.run` already use that word for the same function.

Write both in the table form with `call` stated outright. A presentation member is the one
place in this whole contract that refuses a call kind left to default, because a wrong guess
here does not raise. Lua binds your module table where the query belonged and shifts every
argument along by one, and your list quietly answers nothing forever.

## What that alone buys you

Declare only those two members, plus `registry` for a row and a key and `surface` for a
context, and all of this already works.

Your leader key opens you standalone, the root asking the registry for your presentation and
handing it to the stage as a fresh stack of one.

A launcher row that names you pushes your presentation onto the stack instead of opening a
second window, so the list swaps in place with no flicker and no field text nobody typed.

Your alias and a space scopes the launcher to your rows, once `provides` or `registry.scope`
names the two functions, and choosing there does what choosing in your own list does.

Backspace on an empty field pops back to whatever was underneath, the launcher included, with
that level's placeholder restored and its highlight at the top. At the bottom of a stack the
press stays an ordinary press.

Every swap is a swap. The one chooser instance is built once at configure and never rebuilt,
so no open after the first one pays construction, and no handoff closes a window so another
can open.

The shared navigation keys are live while you are showing, j, k, i, x, and your primary key,
routed to the stage through the one nav adapter. The docked hint panel names them, the cheat
sheet lists you, and the action panel opens over your list and offers your verbs.

The ambient policy arrives without a word from you. Ten rows, the uniform width, the fuzzy
matcher, the shared theme, the overlay display policy, and the highlight reset to row one on
every present, since a new list means something new.

## The optional fields

Add one only when something is actually wrong without it.

`matcher` is `false` when your own supplier ranks the query and the widget must not rank it
again, or a string naming a strategy the Chooser atom exports. Absent inherits the root
default. Beware that `surface.matcher` is a different question, which strategy gets injected
into your code, and this one is whether the widget itself filters.

`enter` is a member handed one function, `proceed`, called in place of showing you
immediately. Use it when your first row is meaningless before an async gather lands, as
Processes does for its scan. Whatever was showing stays up and answerable until you call
`proceed`, which answers true when it really made you current. Arrange your own timeout, since
an answer that never comes must not strand a person on a row that does nothing.

`paneWidth` reserves the docked companion pane beside your rows, a number of points, `true`
to inherit the chooser width, or a member spec resolved once at register when your own wiring
is what decides whether a pane exists at all. Absent means no pane.

The pane itself is core. Declaring `pane = true` on your surface earns `opts.dockedPane`, a
function answering a pane from `lib/dockedpane.lua`, which owns the canvas, the docking, the
shared surface, the shared empty state, the scroll and the teardown. You make one in configure
and hand it what to draw, a describer answering one kit node or a painter answering elements,
and never build a canvas of your own for it. docs/PLUGIN-CONTRACT.md has the calls under "The
docked pane".

```lua
local pane = opts.dockedPane({ scroll = true })

-- onPositioned
if companionFrame then pane.dock(companionFrame) else pane.hide() end
-- onHighlight
if item then pane.show(function(ui) return ui.text(item.title, "title") end) else pane.clear() end
-- onScroll
pane.scrollBy(points)
-- onClose
pane.destroy()
```

A docked pane is never hidden while its presentation is showing. A highlight with nothing to
describe calls `pane.clear()`, which paints the shared empty state, so a reserved rect never sits
there with nothing drawn in it. The pane genuinely vanishes only when `onPositioned` is told both
frames as nil, the stage's own swap signal, and when the stage closes, and a late repaint after a
hide stays down until the next dock.

`rowCount` is a positive whole number, declared only when ten genuinely does not fit. It costs
a hide and show to resize, so it blinks, which is why almost nothing declares it.

`titleLineBreak` names where a title too long for its row loses characters.
`"truncateMiddle"` for filenames, where the tail is the extension and worth keeping. Absent
means the atom's tail cut.

`onPresent` is told, with no arguments, whenever you become current through present or push,
never on a pop. It exists for a plugin whose rows depend on something async that nothing else
has warmed.

`onHighlight` is told the row under the highlight, for a companion consumer drawing a preview.

`onPositioned` is told the chooser frame and the companion frame whenever the stage moves the
pair for you, and is told both as nil, once, when a different presentation becomes current, so
a pane you drew clears rather than sitting beside a window that already moved past it.

`onClose` is told when the stage hides entirely, never on a swap. Every discarded level of a
stack is told, top down. This is where a timer, an eventtap, or a canvas you own gets torn
down.

`intercept` is asked for the highlighted row before that row is allowed to complete. Answer
"stay" when your row mutates the list it is standing on, changing what a sibling row shows
or removing one, in place, so the list stays open and rebuilds with the highlight held on
the row the person just chose rather than jumping away from it, the OLM settings placement
page's own two option rows and the clipboard's own prune page both being shipped examples.
Answer plain true only for a wholesale swap of the whole list, the one case it still means
what it always has, rebuilt from the top with the highlight starting over at row one. A page
of options a person flips this way never pops or closes on its own, leaving is always the
person's own Backspace or Escape.

`back` is asked on Backspace while the field is empty, and answers first. Only when it declines
does the stage pop the stack.

Three more exist and are used by exactly the plugins that needed them, `peekPreview`,
`onScroll`, and `onRightClick`. `docs/PLUGIN-CONTRACT.md` has each.

## Nesting

A level inside your plugin is a child presentation, not hand wired plumbing. Your `select`
answering a table pushes it, the stage taking the returned table exactly as a launcher row
pushes a tool, so choosing the row swaps the list in place, backspace pops back to you, and
the child may declare its own placeholder, matcher, paneWidth, or rowCount and inherit
whatever it does not. Returning nil or nothing keeps today's meaning, the row completed and
the window hides. A child needs no name, the stage derives context from you, though it may
carry one when its level genuinely wants different hint content.

This is `docs/BRIEF-CONTRACT-V3.md`, built and landed. BrowserTabs and DisplayProfiles are the
two plugins that nest this way today, each a settled example worth reading beside the brief.

Children and `intercept` are not interchangeable. A row that takes you somewhere is a child. A
row that changes the list it is on and stands still is an `intercept`. Backspace out of a
level your own row pushed needs no hook from you either, `Stage:pop` already restores the
parent, but a row that must leave a level itself, rather than waiting for Backspace, calls
`stagePop()` from inside its own `intercept`, decision three's reserved case, since a child
returned from `select` can only ever push, never pop.

## Disabled rows

A row you build with `enabled = false`, a status line, a piece of guidance, an empty state,
never reaches your `intercept` or your `select`, however it is chosen, Return, the insert key,
or a click. The enabled state is checked before your presentation is ever asked, first thing
inside the stage's own gate for the keyboard paths, and by the atom itself before a click is
even offered to that gate, so the row is simply inert on every path and nothing runs. You do
not write a guard for it. Earlier code in this tree carried a hand written
`if not item or item.noop then return true end` at the top of an `intercept` for exactly this
case, and every one of those guards is now redundant, the stage having taken the check over as
its own business rather than leaving each plugin to reinvent it.

## The stage words

You hold no chooser, so the few things a chooser owner used to do directly arrive as words the
composition root publishes. Declare each in `needs.data` with `source = "root"`, a policy, and
a `breaks` sentence, then read it off `opts`.

`stagePresent(name)` hands your own presentation to the stage, the door your hotkey and your
`registry.open` both go through.

`redrawPresented(name, resetRow, token)` reruns your rows when your background status changes,
and does nothing at all unless you are what is showing. Pass true for `resetRow` only when
every row moved. Without `token`, `name` means your top level specifically, so an async answer
belonging to a child you have drilled into would otherwise land on whichever level is current,
which is very rarely what you want. A child with its own async work passes `token`, the
presentation table it closed over while building itself, `local child; child = { ... }` being
how you get a table to close over before it exists to be returned, and the redraw then lands on
that child specifically, `Stage:isCurrent(token)`, or not at all. An async answer lands on its
own level or not at all, never on whatever else happens to be current when it arrives.

`stageHide()` takes the shared window down at once, for an action whose feedback is that the
list is gone.

`stagePop()` leaves the current level the way Backspace on an empty field already does,
restoring whatever sits below and answering false at the bottom. Call it from inside your own
`intercept` for a row that must leave a level itself rather than waiting for Backspace, a
delete or a rename landing you back on a list above the thing you just acted on being the
ordinary case. This is the one thing a child returned from `select` cannot express on its own,
since a child only ever pushes.

`stageSetQuery(text)` puts text in the field, the way a parent row in file search steps up a
level.

`stageSetPlaceholder(text)` changes what the field says it is for, when a page changes the
meaning and not only the contents.

`stageSelectedItem()` reads the highlighted row off the live widget, which is the only honest
answer. Do not keep a cache of your own, every plugin that tried grew a stale one.

`stageSelectedRow()` is the plain row number, for deciding whether a background correction is
safe to draw.

`stageTextBudget()` and `stageTextWidth(str, which)` measure a row's room on the live
instance, for a plugin that elides its own text.

## Navigation belongs to the user

Your plugin supplies rows and answers questions about them. It never moves the highlight.
Selection is the person's, the nav layer owns j and k, and the stage resets to the top on
present because the list changed underneath. The one sanctioned way to ask for the top back is
`redrawPresented(name, true)`, and only when a reorder left no row worth preserving. A
background correction landing while somebody is reading has to check `stageSelectedRow()` and
defer rather than redraw under a hand.

## What the wiring layer refuses, loudly

All of this happens at register, stage five, after every plugin's wiring has run, so the
module checked against is the real finished one. A refusal is one console line naming your
tool and the reason, and the whole registration is dropped, so you lose your row, your key,
and your list rather than getting a silently wrong one.

One refusal comes earlier than all of these, while the manifests are read, before any plugin
loads. A manifest that fails it is left out entirely, and whatever needed it is then reported
by the cascade that already handles a missing plugin.

- `Olm compose, plugin '%s' was left out, declares no apiVersion`
- `Olm compose, plugin '%s' was left out, was written against apiVersion %s and this Olm is %s`
- `Olm compose, plugin '%s' was left out, about.%s is not a field about carries`

`lib/registrar.lua`, on the presentation block.

- `registrar refused '%s', its presentation.%s does not state call, dot or method, explicitly`
- `registrar refused '%s', its presentation.%s names '%s', which does not resolve to a function on the real module`
- `registrar refused '%s', its presentation.rowCount is '%s', not a positive whole number`
- `registrar refused '%s', its presentation.paneWidth does not state call, dot or method, explicitly`
- `registrar refused '%s', its presentation.paneWidth names '%s', which does not resolve to a function on the real module`
- `registrar refused '%s', its presentation.paneWidth is '%s', not a plain number, true, or a member spec`
- `registrar refused '%s', its presentation.matcher is '%s', not false or a string naming a matcher strategy`
- `registrar refused '%s', its presentation.matcher names '%s', which is not a strategy the Chooser atom exports`
- `registrar refused '%s', its presentation.titleLineBreak is '%s', not a string`

And one warning rather than a refusal, worth reading as a real defect, since the routing it
names really does go quiet.

- `registrar found '%s' presenting under identity '%s' while its surface declares context '%s', the docked hint bar routes by identity and will not follow that context`

`lib/registry.lua`, on the descriptor the registrar built for you.

- `Registry refused a descriptor, its name is missing or is not a string`
- `Registry refused a second registration for '%s', the first registration keeps it`
- `Registry refused '%s', apiVersion %s does not match the core's %s`
- `Registry refused '%s', its presentation is present and is not a table`
- `Registry refused '%s', its presentation has no rows function`
- `Registry refused '%s', its presentation has no onSelect function`
- `Registry refused '%s', its row is present and is not a table`
- `Registry refused '%s', its row has no category`
- `Registry refused '%s', its surface is present and is not a function`
- `Registry refused '%s', its shortcut is '%s', neither 'leader' nor 'global'`
- `Registry refused '%s', its shortcut has nothing to bind`
- `Registry refused '%s', its command '%s' collides with its own tool name`
- `Registry refused '%s', its command '%s' collides with '%s' already registered`
- `Registry refused '%s', its command '%s' is not a function or a table with a callable fn`
- `Registry refused '%s', its scope is present and is not a table`
- `Registry refused '%s', its scope has no rows function`
- `Registry refused '%s', its scope has no run function`
- `Registry refused '%s', its scope's matcher is present and is neither false nor a function`
- `Registry refused '%s', its scope's peek is present and is not a function`
- `Registry refused '%s', its scope's redirect is present and is not a function`
- `Registry refused '%s', its scope's act is present and is not a function`
- `Registry refused '%s', its scope's verbs is present and is not a table`
- `Registry refused '%s', its scope's verbs entry '%s' is not a function or a table with a callable fn`
- `Registry refused '%s', its scope's verbs entry '%s' does not say whether it closes the list`

`lib/services.lua` answers one more question separately, `owed`, every `source = "root"` need
that nothing actually delivered. A declaration that is right, validated, reported satisfied,
and then never published is the failure class that check exists for, and six of them were live
at once.

## What nothing catches yet

Care is still manual here, so read this list as the places to be careful rather than as gaps
somebody forgot.

Your `rows` function is never checked. It runs on every keystroke and whatever it returns goes
straight to the widget, so a row with no text, no category, or a wrong shape is your problem
alone.

`provides` members are resolved lazily and answer nil in silence when they name nothing, by
design, because a plugin may still be assembling its module when they are read. A typo there
costs you a key that does nothing with no line anywhere. `registry.open` and every
`registry.scope` member used to share that gap and no longer do, the dry gate's own
`checkRegistryMembers` resolves both against the real module the identical way it resolves a
presentation member, step 9 of the build order below. Presentation members are checked at the
live wiring layer too, register, stage five; `registry.open`, `registry.scope`, and every
`registry.commands.*.fn` are checked only by the gate, never by a live reload, so running it is
what stands between a typo there and a key that does nothing.

A `matcher = false` plugin that then filters nothing shows an unfiltered list, and nothing
notices. The two questions, whether the widget filters and whether you rank, are independent
and only one of them is declared.

An `enter` that never calls `proceed` strands the person on a launcher row that silently does
nothing. The stage will not time you out.

A timer, an eventtap, or a canvas you start and do not tear down in `onClose` survives the
window. Nothing audits that.

Moving the highlight yourself is not forbidden by anything. It is simply wrong.

`surface.context` and your identity agreeing is a warning, not a refusal, and everything keeps
working until the hint bar goes quietly empty.

## Drawing with the kit

A pane that draws on its own canvas asks for the UI kit rather than choosing its own colours,
fonts, sizes and spacing. Declare it whole.

```lua
needs = { lib = { ui = { from = "ui" } } },
```

It arrives as `opts.ui`. Build a tree of nodes, each naming a variant and never a colour, a
font or a size, and hand it to `ui.layout` with the rect you want it in. What comes back is the
canvas elements and the height the tree wants. A docked companion pane does not need this
step, since the docked pane lays out the node a describer answers and hands the describer the
kit itself, so the example below is for a canvas of your own that is not a docked pane.

The layout engine closes its clip with resetClip, which clears every clip on the canvas, so never lay out a clipped subtree inside a clip of your own.

```lua
local ui

function obj.configure(opts)
  ui = opts.ui
end

-- Called with the pane's own canvas and its size, on every redraw, so the tokens follow the
-- light and dark switch with no watcher of yours.
local function drawPane(canvas, w, h, entry)
  local tree = ui.stack({
    ui.text("Details", "section"),
    ui.row({ ui.text("SIZE", "caption"), ui.text(entry.size, "body") }, { gap = "m" }),
    ui.text("Measured a moment ago", "caption", { color = "subtext" }),
  }, { gap = "s" })
  local elements, contentHeight = ui.layout(tree, { x = 14, y = 10, w = w - 28, h = h - 20 })
  canvas:replaceElements(elements)
  return contentHeight
end
```

`surface()` paints the shared chrome behind the whole rect the tree is laid out in and takes no
room of its own, for a pane that does not already draw its chrome some other way. A row
gives its last child the remaining width. A group with `alpha` fades everything inside it, and
one with `id` makes everything inside it report that id to your canvas's mouse callback. For a
pane that scrolls, pass `{ scrollY = offset }` as the third argument, and the result is clipped
to the rect while `contentHeight` tells you where scrolling has to stop. An unknown variant is
an error naming it, at the line that built the node. `ui.tokens()` answers the resolved table
when something has to be drawn by hand, and docs/DESIGN-UI-KIT.md lists every name in it.

### Code blocks, long content and drawing your own

`ui.code(lines, { maxHeight, more })` is a preformatted block in the code role. `lines` is an
array of strings, one text element per line, whitespace kept exactly, never collapsed and
never wrapped. A tab is expanded to the next multiple of four columns, and each line is cut
at the rect width with truncateTail. When `maxHeight` is given and the lines do not fit, it
draws as many lines as fit minus one, then a closing line in the caption role. `more` is a
function of the count left out and answers that line, defaulting to "N more lines". The
content height is the drawn height.

When `ui.layout` is given `scrollY`, a code block lays out only the lines inside the visible
window. A line wholly outside it emits no element and is never measured, while the content
height still counts every line, since every line in this role has the same height. A long file
therefore costs the visible lines, not the whole file.

`ui.raw(height, draw)` is room you draw yourself, a graph or a scroll thumb. Layout reserves
`height` points, a number, at the node's position and calls `draw(rect, tokens)` with the
absolute rect it was given after the scroll offset. The element list `draw` returns is
inserted at that point, in order. Every colour in those elements must come from the tokens
passed in, which is why they are passed. Group alpha and the group click id are not applied to
raw elements.

Colour follows the same rule as type. There are eight roles, foreground, subtext, background,
border, highlight, primary, secondary and tertiary, and a node or a raw element names one of
them and never a hex or a palette colour. A graph takes the accents in order, the first series
primary, the second secondary and the third tertiary, since accents are ranks and carry no
meaning. "Olm colour, eight roles and nothing else" in the config's `AGENTS.md` is the rule and
says what each role is for.

## Row icons

A plugin never draws a row icon. It declares its icons in its manifest and names one on a row,
and Olm draws it, so every icon comes out of one engine and the active icon set is one setting
in `config/icons.toml`.

```lua
-- manifest.lua
icons = {
  on  = { emoji = "🟢", sf = "circle.fill" },
  off = { emoji = "🔴", sf = "circle" },
},
```

Each key is a name your rows use and each value is a table of source name to the value that
source understands, an emoji string for `emoji` and an SF Symbol name for `sf`. Give every
entry at least one string. The set in use is tried first and the fallback after it, so an
entry with only an emoji still shows when the set is `sf`. A broken declaration, a table that
is not one, a key that is not a string, an entry with no string value, is refused at register
with one console line naming your tool.

```lua
-- in rows
{ title = "Deactivate", icon = "off", item = item }
```

A row says `icon = "key"` to use one of its own plugin's icons. A child presentation your
`select` returns is read against the same plugin, and so are the rows your launcher scope shows,
so one declaration serves every place a row appears. You never set `iconOwner` or `image` for an
icon. Olm stamps the owner on the row, and the chooser draws the picture when it paints, which is
how an icon follows a light and dark switch, so never hold or cache a picture of an icon yourself. A key your manifest
does not declare logs one warning naming the plugin and the key, and the row shows no icon.

The plugin's own identity icon, the one its launcher row, its action panel and its scoped list
wear, is `defaults.icon`, and it is a key into the same table. Name the key for the plugin and
declare it like any other.

```lua
icons = { vpn = { emoji = "🌐", sf = "globe" } },
defaults = { leader = "app", key = "P", description = "VPN", icon = "vpn" },
```

A key `defaults.icon` names that `icons` does not declare is refused at register with one console
line naming your plugin. A table spec is also accepted there, though a key serves the plugin's
own rows too and is preferred. A person who writes a string over it in `config/plugins.lua` that is
not a declared key means an emoji, the plain shorthand. An action panel verb or a binding names
its icon the same way, `icon = "key"` on the binding, read against the plugin that owns the
context. A computed row source names `icon = "key"` on the rows it answers, and the root
stamps that plugin as their owner.

Give every entry an `sf` name beside its `emoji`. Prefer the outline style SF uses in menus and
sidebars and fill only where the meaning needs it, a status dot. Every name must exist, so check
each one before it is written by running this through `osascript -l JavaScript` and replacing any
that print missing.

```js
ObjC.import('AppKit');
var names = ['circle.fill', 'clock'];
names.map(function(n){ var i = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(n, $('x')); return n + ' ' + (i.isNil() ? 'missing' : 'ok'); }).join('\n');
```

The dry gate prints one coverage line per icon source and a warning for every plugin and key
with no `sf` entry. An entry may carry `content = true`, which is not a source, to mark a glyph
that is content and leave it out of the count. It also refuses a literal `icon = "key"` in any
Lua file of a plugin when the manifest does not declare that key.

Content, known only at runtime, is a table spec on the row and never a key, as
in `icon = { emoji = flag }` for a country flag or the emoji a picker is offering. Switching the
set then never changes what the content is, so such a spec has no `sf` entry by design, and a
comment where it is built says so. A row that carries an `image` keeps it and `image` wins over
`icon`, since a real picture, an application icon or a file icon, is not an icon key. A colour swatch or
a thumbnail is content and is the one kind of drawing that may stay in a plugin, declared in
`test/drygate-accepted.txt` with its reason, and the dry gate refuses any other file under
`plugins` that creates a canvas and snapshots it into an image.

## Keys on a leader

A plugin that wants keys on the window leader declares `leader = "window"` and a `bindings`
list in its defaults, asks for the leader with `needs.lib.windowLeader = { from =
"windowleader" }`, and names a wiring step that binds each entry through the lib. That is all of
it, the same shape capture uses on the app leader. Windowmanager is the worked example, its
sixteen bindings are plain data in `defaults.bindings` and its `bindToLeader` step takes
`self.windowLeader` and `self.bindings`. The lib binds onto the one keycode the root gave it,
so a binding never names a keycode. A binding's `repeats = true` marks a step worth repeating
while the key is held, and its `when` names a predicate the lib checks live, a false one
making the key a swallowed no op.

You write nothing for the sheet. The root walks the plan for every binding declared on the
window leader and the held window sheet draws it, with `when` hiding the row and the key
together and `description` replacing the label humanized from the action name. A person moves
the whole leader to another physical key in `config/keys.lua`, and no plugin changes. The sheet
is one of the two places every key must be found. The launcher is the other, and a plugin puts
its keyed actions there itself, as the next section says, which is what the window manager does
for its window rows.

## Rows in the launcher's own catalog

A registered tool gets its one launcher row from its `registry` block. A plugin whose separate
actions each deserve a row, four screenshot actions, sixteen window actions, thirty nine System
Settings panes, contributes them to the launcher's own catalog instead, with two members.

```lua
provides = { launcherRows = "launcherRows", launcherRun = "launcherRun" },
```

`launcherRows` answers a list of plain rows, built from your own effective bindings or your own
data so a key moved in the person's config moves its row too. Keep the bindings your
`configure` receives, `opts.bindings` and `opts.leader`, and build from those.

```lua
function obj:launcherRows()
  local rows = {}
  for _, b in ipairs(self._bindings or {}) do
    rows[#rows + 1] = {
      title = b.description,
      group = "Capture",
      chord = { leader = self._leader, key = b.key, mods = b.mods },
      icon = b.icon,
      item = { kind = "capture", name = b.action },
    }
  end
  return rows
end

function obj:launcherRun(item)
  self:capture(item.name)
end
```

Four rules, each one a way this goes wrong without a sound.

A row is data. Never put a function in a row or its item, since the launcher hands every row to
`hs.chooser`, which drops a row holding one, and the list comes up without it.

Name the chord rather than spelling it. Give `group` and `chord` with the leader as a role, and
the launcher spells the subtitle with the same speller the hint bar uses. A finished `subTitle`
is for a row with no key, and it is taken as it stands.

Your run gets the whole item back. Olm stamps your identity on every item as `owner`, and the
launcher routes a chosen row to your `launcherRun` by it, after the list has closed and focus has
gone back to the app underneath. Read the fields you put there yourself.

The kind and the name are a memory key. The launcher remembers picks in `hs.settings` as the
kind joined to the item's `key`, or to its name when it states no key. Pick them once, since
renaming either makes the launcher forget every time a person chose that row. A row computed
from what was typed states `remember = false` and is never remembered at all.

`icon` is a key into your own manifest icons, read against your identity like every row icon.
`when` names a predicate that hides the row live, the way a window binding's gate hides its key.
`keywords` is hidden text the matcher reads. Where your rows sit is `defaults.launcherOrder`,
a number compared with every other contributor's, and a single row may state its own `order`
to sit apart from the rest of yours. The contract lists the shipped numbers, so choose one in a
gap between them.

A query row source owns the rows it computes too, so one that wants a chosen row run by itself
declares `launcherRun` alone and leaves `launcherRows` out. Window Size is that case.

## Sections on a leader's cheat sheet

Holding a leader shows every key bound on it. A key your manifest declares, your own `key`, your
`bindings`, a registry command on the leader, is collected by Olm and listed without you doing
anything. Only a plugin that binds keys from data the manifest does not spell as bindings needs
more, and it supplies its own sections.

```lua
provides = { cheatSheetSections = "cheatSheetSections" },
defaults = { leader = "app", cheatSheetOrder = 10 },
```

The member answers a list of sections, each a title and rows of badge, label and an optional
icon, and it is asked on every show. Build the expensive part once, where you bind, and keep the
member to what changes while Hammerspoon runs. List exactly what you bound on that leader. A
key that does nothing on the sheet is the dishonesty the sheet exists to prevent, and a global
combo belongs to no leader. The app toggler is the worked example, it resolves names and icons
in `bindHotkeys` and splits running from dormant in `cheatSheetSections`. The contract has the
section shape and the shipped numbers.

A registry tool's own open key, the one `registry.shortcut = "leader"` binds, goes on the app
leader only. A tool stating `leader = "window"` with a leader shortcut is refused at wiring with
a problem line naming it, since binding it on Hyper would put it on neither sheet. A key on the
window leader belongs in `bindings`, which that leader binds and its sheet lists.

## Chords on the launcher's app rows

The launcher lists every installed app from its own disk scan. A plugin that binds a chord for an
app tells the launcher so, and the app's row then names the chord and opens the url the plugin
states.

```lua
provides = { launcherAppDetails = "launcherAppDetails" },
```

The member answers a table keyed by bundle id, asked whenever the launcher builds its app rows,
which is after your wiring step has run. Each entry is `{ chord = { leader = "app", key = "f" } }`
for a key on a leader, or `{ chord = { key = "8", mods = { "ctrl", "alt" } }, description =
"Placed" }` for a literal combo, with an optional `url`. List only what you bound. The app
toggler is the worked example, it builds the table in `bindHotkeys` from exactly the entries it
bound.

## Tools your plugin needs

A plugin declares what it needs on the machine and installs nothing. Every external binary or
bundle goes in `needs.tools` with a `kind`, a `policy`, a `reason`, and an `origin`, and it is
declared there and nowhere else, since one tool named twice drifts.

`policy = "required"` means the plugin is not wired at all without it, and `optional` means it
loads degraded and Olm says on the console what was lost. Prefer optional and a single row
naming the missing tool, so the list still opens on any machine.

Never write an install command anywhere, not in code, not in a comment, and not in help text.
The repository root holds the answer key. When you declare something new, add its line to
`DEPENDENCIES.map` and its matching entry to the `Brewfile`, then run
`src/check-dependencies.sh`, which regenerates this module's manifest and refuses any
disagreement between your declaration and the map. The full rule is in the repository root
`AGENTS.md`.

## The build order

1. New directory under `plugins/`, `manifest.lua` loading with nothing required and no `hs`,
   opening with `apiVersion` and `about`.
2. `needs` first, tools with `reason` and `origin`, then the `DEPENDENCIES.map` and `Brewfile`
   lines at the repository root.
3. `init.lua` with `configure(opts)`, plus the `rows` and `select` members the presentation
   will name.
4. `defaults`, then `registry` with a row `category` and an `open`, which earns the launcher
   row, the word, and the key.
5. `surface` with a `context` spelled exactly as your identity, and the primary key.
6. `presentation` with `rows` and `select` only, table form, `call` stated, nothing else yet.
7. Add one optional field at a time, each because something was actually wrong without it.
8. `src/check-dependencies.sh` clean, no error and no new warning naming you.
9. The dry contract gate, `Spoons/Olm.spoon/test/drygate.sh`, or `test/suite.sh dry` from the
   same directory. A lock free check, plain lua, no Hammerspoon, no reload, no lock, that
   loads your manifest and your real module under a permissive stub and reports every refusal
   above in well under a second. A finding fails it. A module that will not load or configure
   under the stub is reported unknown rather than guessed at, and an unknown does not fail the
   gate unless you pass `--strict`. A clean tree exits zero, so run it and read the line it
   prints naming your tool before you commit.
10. Load it live once, before anything merges. Take the lock, let the config come up, and ask
    it a question, `hs -c "return hs.configdir"`. A silent answer, the ipc port refusing you,
    means the config died before ipc came up and the whole config is down, not only your
    plugin. Nothing above catches this. The close out of the chooser stage track shipped a
    branch that passed luac, the reconciler, the dry gate, the unit cases, and a full
    adversarial review, and still would not load, because it asked the stage for a surface at
    wiring time and the stage builds that surface at configure time, an ordering no static
    check in this repository can see. When a load does die, point Hammerspoon at a throwaway
    init that xpcalls the real one and writes the traceback to a file, which is how that one
    was found in a minute after an hour of reading.
11. Then use it once, with a real key press. Everything above is structure, and structure has
    never proven that a key fires.
