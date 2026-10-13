# Contract freeze brief, phase 1 of the canvas chooser track, 2026-09-11

Phase one of docs/PLAN-CANVAS-CHOOSER.md. The reference this implements is
docs/CONTRACT-PICKER.md, read it first and completely. Decisions were made by the
orchestrator. Follow them rather than relitigating them, and where this brief and the code
disagree, stop and report rather than improvising.

## What this phase is for

A second picker provider is being built. Today the stage and the action panel reach past
the facade and touch the native provider's private representation, so a second provider
would either break on those reads or, worse, happen to carry similarly named fields and be
silently corrupted. This phase puts every one of those reaches behind a named method, and
it changes no behaviour at all. A person using this configuration must not be able to tell
this phase happened.

## What to build

### 1. lib/chooser/contract.lua

A new module holding the required method names with their arities and one
`validate(instance)` answering `ok, reason`.

The names and arities are in docs/CONTRACT-PICKER.md under "The methods". Take them from
there rather than from this file. Arity there excludes the implicit self, so reading
`debug.getinfo(fn, "u").nparams` compares against the stated number plus one.

The rules, matching what commit `3c8ad9d` gave the VPN provider contract. A missing method
is refused. A method that is not a function is refused. A variadic method is accepted
whatever it declares. A method declaring more parameters than required is accepted. Only
declaring too few is refused. A refusal reads as a phrase naming the method and what it
declares rather than a bare name, so a reader learns what is wrong and not only where.

`lib/chooser/init.lua` loads this by path the way it already loads the provider and
`match.lua`, and `obj.new` validates the instance the provider answered before any
`decorate` runs, raising with the reason when it fails. Validating before decorate is
deliberate, a decorator wrapping a broken instance would bury the reason.

### 2. Nine new methods on lib/chooser/providers/native.lua

Every one of these is a move of code that exists today, not a new capability. Their
signatures and semantics are in the contract document.

`reposition(paneWidth)`. Its body is `host/stage/init.lua`'s current `obj:_positionPane`,
lines 633 to 663, moved here and adapted. It keeps the window hunt by title, the frame
read, the screen read, the recentre and the `setTopLeft`, since all of that is this
provider's own legitimate business. It reads `paneMaxW` and `gap` from its own layout
rather than from a table handed in. It writes its own `paneFrames`. It answers the chooser
frame and the companion frame, the second nil when there is no companion, and answers
nothing at all when it is not up. What does NOT move here is the stage's own guard that the
presentation is still current, and the stage's own call to `_onPositioned`. Those are stage
concerns and they stay in the stage.

`settleDelay()`. Answers this provider's own settle delay. There is a literal `0.03` at
line 335 inside `_settleFrames` and the stage carries a copy of it. Lift it to one named
constant in this file, use it in both places, and answer it here. After this there is
exactly one `0.03` in the tree for this purpose.

`isActive()`. Answers `self.active`. One line. It exists so nothing outside reads the field.

`matcher()` and `setMatcher(m)`. The instance currently carries a top level field literally
named `matcher`, so a method of that name cannot sit beside it. Rename the field to
`_matcher` and update every internal read, then add the two methods. `false` and nil are
different answers and both survive the round trip. Check every use of `self.matcher` inside
this file and change all of them, a missed one silently disables filtering.

`titleLineBreak()` and `setTitleLineBreak(mode)`, fronting `self.layout.titleLineBreak`.

`setPaneWidth(w)`, fronting `self.layout.companionWidth`.

`rowCount()`, answering `self.layout.rowCount`.

### 3. Extract textWidth into lib/chooser/textwidth.lua

`Chooser:textWidth`, lines 995 to 1026, and its per character memo table, are not coupled
to `hs.chooser` in any way. They solve measuring rendered text cheaply and safely, which
every provider that draws its own rows has, so the canvas provider must not reimplement it
and must not reach into the native provider to borrow it.

Move the memo and the summing logic into `lib/chooser/textwidth.lua` as a small module
holding its own cache, keyed by font and size the way the current table is keyed by size.
The native provider loads it by path and `Chooser:textWidth` becomes a passthrough that
supplies its own font and the size `which` selects. Preserve the UTF8 stepping and the
deliberate over counting exactly, and carry the comment explaining why over counting is the
safe direction, since that reasoning is the whole value of the function.

This is a pure move. The numbers it answers after the move must be identical to the numbers
it answers before.

### 4. host/stage/init.lua stops reaching past the facade

Delete `ATOM_SETTLE_DELAY` and its comment block, lines 129 to 139. `_applyPaneGeometry`
asks `self._instance:settleDelay()` instead. Keep the age gate and the timer exactly as they
are, only the source of the number changes.

Replace the body of `obj:_positionPane` with a call to `self._instance:reposition(...)`. The
two guards at its top stay, the current presentation check and the active check, with the
second now calling `isActive()`. Resolve the pane width the same way it is resolved today
and hand it in. On a non nil answer, set nothing on the instance and call
`self:_onPositioned(chooserFrame, companionFrame)` as it does now. After this, the strings
`hs.application`, `allWindows`, `setTopLeft` and the literal `"Chooser"` must not appear in
this file at all.

Replace all nine direct field touches with the accessors, lines 287, 297, 304, 470, 479,
485, 635, 647 and 661. Line 661's direct `paneFrames` write goes away entirely, since
`reposition` now owns it.

While this file is open, correct the stale prose. Its docstring still names twelve
unmigrated consumers and three duplicated `paneAnchor` copies in plugins. The survey of
2026-09-11 found every one of those already done, and `host/stage/manifest.lua` already
states that the stage is the one place that ever calls `Chooser.new`. Fix the comments to
say what is true. Do not delete the guard against a second window titled Chooser without
saying why, it now lives inside the native provider.

### 5. host/actionpanel/init.lua line 442

`local filtersItself = instance.matcher == false` becomes a call to the accessor. One line.
Keep the comment above it explaining why this is read live, it is correct and it is the
reason this cannot be captured at decorate time.

## What not to do

Do not change any behaviour. Do not change the row shape, the config keys, the callback
timing, the placement arithmetic, or any visible geometry. Do not add `activeTheme` or
`close` to the contract, both are dead and the contract document says so. Do not touch
`lib/chooser/providers/canvas/` at all, that is a different phase running beside this one.
Do not touch any plugin, any manifest, or the composition root. Do not take the devlock,
restow, or reload the live config. Do not drive the screen or the keyboard.

## What to deliver

The five items above, plus an offline unit case at `test/cases/pickercontract.lua`
following the convention every case in that directory already follows, one PASS or FAIL
line per check, loading `lib/chooser/contract.lua` by path with `loadfile` and driving it
with hand built table shapes and no Hammerspoon behind it. Cover a correct shape passing,
a missing method refused with its name in the reason, a non function member refused, a
method declaring too few parameters refused, a variadic accepted, and an over declared
method accepted. Do not try to load the native provider in that case, it needs `hs`.

## Acceptance

`./test/units.sh` green with the suite total risen and no existing case changing its
result. `luac -p` clean on every file touched. `src/check-dependencies.sh` clean. A grep
proving the four forbidden strings are gone from `host/stage/init.lua` and that no file
outside `lib/chooser/` reads `.layout`, `.matcher`, `.active` or `.paneFrames` on a picker
instance. Report the before and after of that grep in your own words rather than asserting
it.

Report anything where this brief resists the code rather than bending either side quietly.
The most valuable thing you can hand back is a place where a move I called mechanical turns
out to change behaviour.

## Writing style, a hard requirement

Never use em dashes, en dashes, or hyphens in prose. Only periods and commas, no colons and
no semicolons. This applies to code comments and to your report. It does not apply to code
itself or to file paths.
