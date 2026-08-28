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

`init.lua` returns the module and exposes `configure(opts)`, unless the manifest declares
`wiring` steps that stand in for it. Everything else `init.lua` exposes, the manifest
declares.

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

`intercept` is asked for the highlighted row before that row is allowed to complete, and true
in reply means you already did what the row meant and the list stays open, rebuilt from the
top. Reserve it for a row that mutates the list it is standing on, the clipboard's prune page
being the case it exists for.

`back` is asked on Backspace while the field is empty, and answers first. Only when it declines
does the stage pop the stack.

Three more exist and are used by exactly the plugins that needed them, `peekPreview`,
`onScroll`, and `onRightClick`. `docs/PLUGIN-CONTRACT.md` has each.

## Nesting

A level inside your plugin is a child presentation, not hand wired plumbing. Your `select`
returns a presentation table, and the stage pushes it exactly as a launcher row pushes a tool,
so choosing the row swaps the list in place, backspace pops back to you, and the child may
declare its own placeholder, matcher, paneWidth, or rowCount and inherit whatever it does not.
Returning nil or nothing keeps today's meaning, the row completed and the window hides. A
child needs no name, the stage derives context from you, though it may carry one when its
level genuinely wants different hint content.

This is `docs/BRIEF-CONTRACT-V3.md`, decided and being built now. Until it lands,
`Stage:_onSelect` discards what your handler returns, so a returned table does nothing rather
than something wrong. Check the code before relying on it.

Children and `intercept` are not interchangeable. A row that takes you somewhere is a child. A
row that changes the list it is on and stands still is an `intercept`.

## The stage words

You hold no chooser, so the few things a chooser owner used to do directly arrive as words the
composition root publishes. Declare each in `needs.data` with `source = "root"`, a policy, and
a `breaks` sentence, then read it off `opts`.

`stagePresent(name)` hands your own presentation to the stage, the door your hotkey and your
`registry.open` both go through.

`redrawPresented(name, resetRow)` reruns your rows when your background status changes, and
does nothing at all unless you are what is showing. Pass true for `resetRow` only when every
row moved.

`stageHide()` takes the shared window down at once, for an action whose feedback is that the
list is gone.

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

`registry.open`, `provides`, and `registry.scope` members are resolved lazily and answer nil in
silence when they name nothing, by design, because a plugin may still be assembling its module
when they are read. A typo there costs you a key that does nothing with no line anywhere. Only
presentation members are checked against the real module.

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
`CLAUDE.md`.

## The build order

1. New directory under `plugins/`, `manifest.lua` loading with nothing required and no `hs`.
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
9. The dry contract gate, a lock free check that reads your manifest and your module and
   reports every refusal above without Hammerspoon running. It is arriving under the Olm test
   directory. Until it lands, reload and read the console, which is where every line above
   appears.
10. Then use it once, with a real key press. Everything above is structure, and structure has
    never proven that a key fires.
