# Adversarial review, 591f51a, chooser stage phase four, live geometry

Branch feat/chooser-geometry, worktree /Users/milos.djakovic/Development/personal/.worktrees/chooser-geometry,
one commit on top of bfd9a00. Diffed against bfd9a00, every touched file read whole, every new
manifest field followed from lib/registrar.lua through lib/registry.lua into host/stage/init.lua
and lib/chooser/providers/native.lua.

Mechanical gates, both run from the worktree root by me.

    luac -p on all seven touched lua files, clean
    src/check-dependencies.sh, "Dependency check passed, 0 warning(s)", exit 0
    git status clean after the reconciler ran, so no generated manifest drifted

Counts. Three high, six medium, eight low, one sound section.

Every high and medium finding is latent today. No presentation in the tree declares paneWidth
and none declares rowCount, so the brief's own acceptance, unchanged observable behavior for the
launcher and for VPN, genuinely holds. I traced it. The findings are about what phase five walks
into, and phase five is the reason this phase exists.

---

## High

### H1. pop performs no geometry at all, so a two row window survives back into a ten row list

Confirmed.

`host/stage/init.lua:563` `obj:pop()` removes the top level, fires its onClose, and then does
exactly three things on the instance, `setPlaceholder`, `setQuery("")`, `refresh(true)`. It never
calls `_applyRowCount` and never calls `_applyPaneGeometry`. `self._rowCount` and
`self._instance.layout.rowCount` both keep the value the presentation that just left installed.

The concrete sequence, the only real consumer shape phase five has, caffeinate at
`plugins/caffeinate/init.lua:353`, `layout = { rowCount = 2 }`, consumer map 9.5 confirming it is
the single row count consumer in the tree.

1. Launcher hotkey. `present(launcher)` over a hidden window. `_applyRowCount` computes
   `desired = nil or 10`, equal to `self._rowCount`, returns false. Cold show, ten rows, window
   height 514 by the atom's own arithmetic, probe C2.
2. Launcher row chooses caffeinate. `push(caffeinate)` with `wasShowing` true. `_applyRowCount`
   computes desired 2, sets `self._rowCount = 2`, raises `_suppressClose`, hides, `setRows(2)`,
   returns true. `cold` is true, `resized` is true so the covered app is correctly not
   recaptured, `show()` brings the window back at 220 points. Correct so far.
3. Backspace on the empty field. `_back` finds caffeinate declines, calls `pop()`. Caffeinate is
   removed, the launcher is current again, the field is cleared and the rows are rebuilt.
   `self._rowCount` is still 2 and `layout.rowCount` is still 2.
4. The window is still 220 points tall. Probe C1 measured this directly, a `choices()` swap to
   forty rows left the frame at exactly the size it already had, "a list becoming shorter or
   longer moves nothing". So the launcher's full list is now rendered into a two row window and
   stays that way until the user presses something that re presents.

Self healing only on the next present or push, since `_applyRowCount` will then see 10 against a
stored 2 and drive the resize. Until then the launcher is a two row picker.

The pane half of the same walk is H2.

The fix is one line and the shapes already match. `pop`'s body is byte for byte the swap branch of
`_show`, `setPlaceholder`, `setQuery("")`, `refresh(true)`, `host/stage/init.lua:334` against
`:568`. Replacing the body with `self:_show(below, self._instance:isShowing())` gives pop the row
count path and the pane path for free and removes a duplicated pair of lines.

Nothing in the tree discloses this. `pop`'s own docstring at `:553` through `:562` says it
restores "with an empty query and the highlight at row one" and never mentions geometry, and the
module header's geometry paragraph at `:44` names present and push only. See L6.

### H2. The outgoing presentation is never told it lost the pane, on push or on pop

Confirmed.

`_positionPane` at `host/stage/init.lua:441` fires `p.onPositioned` for the presentation that is
becoming current and for nobody else. `_applyPaneGeometry` is only ever reached from `_show`,
which is only reached from `present` and `push`. So the presentation that just stopped being
current is told nothing about geometry on any door.

On present that is survivable, because `_freshStack` runs `closeStackExcept` and the discarded
level hears its own onClose, which is where every existing pane consumer already erases its
canvas, `plugins/filesearch/chooser.lua`, `plugins/processes/chooser.lua`,
`plugins/clipboard/manager/ui.lua`. On push and on pop it is not, because push deliberately tells
nobody's onClose, `host/stage/init.lua:520`, and pop tells only the level that is leaving.

Two sequences.

Pop. Launcher, push a pane tool A with `paneWidth = true`. `_positionPane(A)` shifts the window
left by `(gap + paneW) / 2`, stamps `paneFrames.companion`, calls `A.onPositioned` and A docks its
canvas. Backspace pops A. A's onClose fires so A erases, but `self._paneW` stays at 480,
`self._instance.paneFrames.companion` stays at A's rect, and the window is never shifted back. The
launcher is now sitting off centre by half a pane with the click watcher at
`lib/chooser/providers/native.lua:637` still answering `pointInFrame(p, fr.companion)` true for a
rectangle with nothing in it, so a click in that dead area is swallowed as "a real interaction"
instead of dismissing. Two separate wrongs from one missing call.

Push. Launcher, push pane tool A, then from A's own rows push a paneless tool B. Push tells nobody
onClose, so A never erases. `_applyPaneGeometry(B, false)` does not take the early return, since
`self._paneW` is 480, so it recentres the window for a lone chooser and sets `companion = nil`. B
declares no onPositioned so nothing is called at all. A's canvas is left drawn beside a window
that just jumped right by 246 points. Depth three is not reachable today, phase five makes it
ordinary.

The brief's decision one says onPositioned refires "so the pane consumer draws or clears". The
clear half is only delivered when the same presentation is the one being repositioned. The
outgoing one has no path.

### H3. rowCount reaches math.min unvalidated and a bad declaration poisons the shared instance for the life of the config

Confirmed by construction. This is the declaration level class the brief's own history warns about,
and the commit added a type guard on one of the two new plain values and none on the other.

The chain. `lib/registrar.lua:490` `rowCount = p.rowCount` and `:491` `paneWidth = p.paneWidth`,
both copied straight off the manifest. `presentationFields` at `:424` covers the nine member specs
and neither of these, correctly, since neither is a member. `lib/registry.lua`'s
`presentationIsWellFormed` checks `type(presentation) ~= "table"`, `rows`, and `onSelect`, and
nothing else, and the diff's own new comment says the rest is "passed through untouched". So
neither value is type checked anywhere between the manifest and the stage.

`paneWidth` survives that, because `obj:_resolvePaneWidth` at `host/stage/init.lua:468` opens with
`if type(w) ~= "number" or w <= 0 then return 0 end`, which is stricter than the atom's own
`_resolveCompanionWidth` at `lib/chooser/providers/native.lua:305` and refuses everything that is
not a positive number.

`rowCount` does not. `_applyRowCount` at `:363` does `local desired = p.rowCount or
self._defaultRowCount`, compares it with `==`, stores it in `self._rowCount`, and hands it to
`self._instance:setRows(desired)`, which at `lib/chooser/providers/native.lua:947` is a bare
`self.layout.rowCount = n` with no validation whatsoever.

The sequence. A phase five manifest declares `rowCount = "2"`, or declares it the way every
neighbouring field is declared, `rowCount = { member = "rowCount", call = "dot" }`, which is the
likelier mistake since nine of the eleven presentation fields take exactly that shape and the
registrar refuses the wrong shape for all nine and for neither of these two.

1. The registrar accepts it, no console line.
2. The registry accepts it, no console line.
3. First push of that tool. `desired` is a string or a table, never equal to 10, so
   `self._rowCount` is set to it and `setRows` writes it into `layout.rowCount`.
4. `_show` calls `show()`, which calls `_positionAndShow` at `:391`, which does
   `local rows = min(L.rowCount, maxRows)`. `math.min` with a string raises "bad argument #1 to
   'min' (number expected, got string)", with a table likewise.
5. The error unwinds out of `show()`. `layout.rowCount` is left holding the bad value on the one
   instance the stage never rebuilds, `configure` refusing a second construction at `:141`. Every
   subsequent show of every presentation raises at the same line. The single window every tool
   presents into is dead until the config is reloaded.

Note that `_suppressClose` is already back to false by then, `:380`, so that flag does not
compound this. The corruption is in `layout.rowCount` alone and it is permanent.

Two cheap closes, either one enough. Refuse a non number `rowCount` in the registrar beside the
`callKindStated` loop, with the same console line shape, or make `setRows` guard itself the way
`selectRow` at `:895` already guards a nil, and have `_applyRowCount` fall back to
`_defaultRowCount` on anything that is not a positive integer. The registrar is the better place,
because it is where the defect actually is and where it can be named.

---

## Medium

### M1. The "a swap races nothing" invariant is false within thirty milliseconds of a cold show

Confirmed as a logic error, plausible as a reachable sequence.

`_applyPaneGeometry` at `host/stage/init.lua:400` branches on `cold`, and `cold` is
`resized or not wasShowing`, a fact about *this* call. The comment on the else branch at `:415`
reads "A swap changes no frame at all and nothing else is moving the window, so there is nothing
to race and the pane is placed at once." The second clause does not follow from the first. What is
moving the window is the atom's own settle timer, armed inside `show()` at
`lib/chooser/providers/native.lua:427` and firing 0.03 seconds later, and its lifetime is a
property of the last cold show, not of the current call.

The sequence.

1. t = 0. `present(launcher)` over a hidden window. `_positionAndShow` seeds the frames and arms
   `settleTimer` for t = 0.03. Launcher declares no pane so `_applyPaneGeometry` takes its early
   return and arms nothing.
2. t = 0.02. `push(paneTool)`. `wasShowing` is true, no row count change, so `cold` is false.
   `_applyPaneGeometry` cancels nothing, `p.paneWidth` is truthy so it does not return early, and
   the else branch calls `_positionPane` immediately. The window is shifted left, `paneFrames` is
   stamped with a companion rect, and paneTool docks its canvas there.
3. t = 0.03. The atom's settle fires. `self.active` is still true, the window is still titled
   "Chooser" and visible, so it passes every guard. It recomputes with
   `_resolveCompanionWidth(cf.w)`, which reads `layout.companionWidth`, permanently zero on this
   shared instance by the stage's own design. `total` is `cf.w` alone, so it moves the window back
   to the lone chooser centre, overwrites `self.paneFrames` with `companion = nil`, and fires
   `config.onPositioned`, which on this instance is the docked panel callback and not the
   presentation's.

The result is a pane canvas drawn 246 points away from the window it belongs to, and a
`paneFrames.companion` of nil, so the click watcher at `:637` reads a click on the visible pane as
outside both rects and dismisses the chooser. The presentation's own onPositioned is never fired
again, so nothing corrects it.

Reachability today is nil, no presentation has a pane. Reachability in phase five is a push landing
inside thirty milliseconds of the launcher's own cold open, which a programmatic route can do
trivially and which the launcher's own seeded query and alias paths sit close to. I did not find a
present immediately followed by a push in the tree, so I am calling this plausible rather than
confirmed reachable, and confirmed as a wrong invariant either way.

The fix is to stop asking `cold` and start asking whether the window has settled. Record the time
of the last `show()` and take the timer branch whenever `now - lastShow < PANE_SETTLE_DELAY`,
whatever this particular call is.

### M2. The stage moves the window and never re anchors the docked shortcut panel

Confirmed.

`configure` at `host/stage/init.lua:187` hands `self._panelOnPositioned` straight to the atom as
`config.onPositioned`. The atom fires that at two moments only, the seed at
`lib/chooser/providers/native.lua:422` and the settle at `:352`, both inside a show. `_positionPane`
then moves the window afterwards and calls only `p.onPositioned`, `host/stage/init.lua:463`. The
panel is never told.

So on every cold open of a pane presentation the docked hint bar is positioned twice against the
pre shift frame and then abandoned, while the window slides 246 points left underneath it. On a
swap into a pane presentation the atom fires nothing at all, so the panel keeps the previous
presentation's anchor forever.

`paneAnchor` at `:657` is the arithmetic that would fix it and the stage never calls it. It is
built for phase five's plugins to call, and a plugin can call it, since each of the three carries
its own root sourced `cfg.onPositioned` need, `plugins/filesearch/chooser.lua:451`,
`plugins/processes/chooser.lua:344`, `plugins/clipboard/manager/ui.lua:1178`. But then the panel is
driven from two places, the stage's own `_panelOnPositioned` at t = 0 and t = 0.03 with the
unshifted list frame, and the plugin's at t = 0.06 with the spanning anchor, and the last write
wins by luck of ordering rather than by design. The stage declares the docked panel triple to be
"atom level policy this host owns", `:31`, and then hands half the responsibility for it to the
presentation.

The clean shape is for `_positionPane` to call `self._panelOnPositioned(self:paneAnchor(chooserFrame,
companionFrame))` itself, which is one line, keeps the panel entirely inside the host that claims
to own it, and lets a migrating plugin delete the anchor block from its own onPositioned rather
than carry a fourth copy of the call.

### M3. _suppressClose has no unwind protection and a stuck flag silences every future dismissal permanently

Plausible, catastrophic if it lands.

`host/stage/init.lua:377` through `:380`.

    self._suppressClose = true
    self._instance:hide()
    self._suppressClose = false

No pcall, no reset anywhere else. `hide()` at `:585` does not clear it, `_onClose` at `:763`
returns early without clearing it, `present` and `push` never touch it, and `configure` refuses to
run twice so there is no reconstruction path either.

If anything between those two lines raises, the flag stays true for the life of the config, and
`_onClose` becomes a permanent no op. That means, on every subsequent real dismissal, escape, a
click away, a completed selection, a programmatic hide, all of it, `self._panelOnClose` is never
called so the docked hint panel is orphaned on screen, `closeStack` never runs so no presentation
ever hears its own onClose again, and `self._stack` is never emptied. The stack keeps every level
that was ever pushed. `Stage:current()` then reports a tool that is not on screen, which is what
`surfaceFor` at `:236` routes every navigation key by, so keys go to a presentation that closed
minutes ago. It is the worst available failure in this file and there is nothing anywhere that
would say why.

What can raise inside the window. I walked it. `Chooser:hide` at `:769` calls `_teardown`, which
stops four timers and one watcher and then calls `self.config.onClose()`. On this instance that is
ActionPanel's wrapper at `host/actionpanel/init.lua:472`, which calls `self:_close()`, six table
writes, and then the stage's own closure, which returns early. Then `self.chooser:hide()`. Nothing
in that path is obviously capable of raising today, so I am calling this plausible rather than
confirmed. The reason to fix it anyway is that the cost of the fix is one token and the cost of
being wrong is total and silent. `local ok, err = pcall(function() self._instance:hide() end)`
around it, flag cleared unconditionally afterwards, or better, replace the boolean with a token,
`self._closeToken = {}` before the hide and compare identity in `_onClose`, so a stale token can
never be a stuck door.

Reentry during the suppressed window is sound and I checked it. `_teardown` guards on
`self.active` so a second hide inside the first is a no op, the panel's `_close` reaches nothing
that calls back into the stage, and no presentation code runs at all during the hide, since rows,
onHighlight, and onPresent all run outside it. A present arriving during the window is not
reachable, there is no yield point.

One real consequence of the suppression that is not a bug but is worth stating. `_panelOnClose` is
skipped for the resize hide while ActionPanel's own `_close` is not, because ActionPanel wraps the
stage's closure rather than being called by it. So during a row count resize the docked hint panel
is never told to close and is redrawn by the atom's own onPositioned on the reshow. That is the
right split, the panel should survive a resize, but it is undocumented and it depends on the
decorator's ordering rather than on anything the stage states.

### M4. The resize hide and show bounces hs.chooser's own focus restore in the same tick and nothing has measured what it restores to

Plausible, unmeasured, and the probe does not cover it.

`_applyRowCount` hides and `_show` immediately shows, same tick. `hs.chooser` records the
previously frontmost application at show time and restores focus to it at hide time, which is the
behavior the atom's own click watcher ordering depends on and states at
`lib/chooser/providers/native.lua:619`, "hide the chooser so its focus restore is queued first".

The first hide queues a restore to the user's real app. The second show then happens before that
restore can land, at which point the frontmost application is still Hammerspoon's own chooser
panel. So the second show may record Hammerspoon as the app to return to. The eventual genuine
dismissal of caffeinate would then restore focus to Hammerspoon rather than to the editor the user
opened the launcher over.

The stage's own `_coveredApp` is unaffected and correctly not recaptured, `:328`, the split finding
five asked for. This is about `hs.chooser`'s internal restore, which the stage does not own and
cannot see.

Probe section C2 measured `rows(3)` while visible, then a later separate show. It never measured a
same tick hide and show, and it never sampled the frontmost application across one. Section C's own
"Losing key focus does not dismiss the chooser" note establishes the opposite property, not this
one. So the one resize path this phase builds rests on an untested focus assumption. This is the
single thing most worth a scripted probe at the live gate, and it is cheap, hide and show in one
tick and read `hs.application.frontmostApplication()` after the following dismissal.

### M5. The VPN rider leaves the exact bug it was written to close reachable through a different door

Confirmed by construction.

`plugins/vpn/init.lua:444`, inside `landedGate`.

    local function onAnswer(...)
      if fired then return end
      fired = true
      apply(...)
      landed()
    end

`apply` runs before `landed`. If `apply` raises, `fired` is already true so the timeout is now shut
too, and `landed()` is never called. `remaining` never reaches zero, `fetching` stays true forever,
and `pending` grows on every subsequent open with nothing left to drain it. That is word for word
the failure the docstring at `:407` says this rider closes, "fetching stayed true forever and every
request behind it queued into pending with nothing left to drain it, one stuck leg silencing every
future open of this tool".

Two of the three applies cannot raise, they are plain assignments. The third can. `:459`.

    local onList, listTimeout = landedGate(function(list)
      cache = cfg.recency.order(list or {}, function(loc) return loc.id end)
    end)

`cfg.recency.order` is injected policy running over whatever `parseRelays` made of the CLI's
output. A malformed relay row, a `loc` that is not a table, an id that is not a string, any of
those raising inside the ordering service takes the whole leg down. An hs.task completion callback
that raises is caught by LuaSkin and logged, the Lua stack unwinds, and `landed()` is skipped.

This shape predates the commit, the old code had `cache = ...` then `landed()` on the same two
lines. So it is not a regression. It is an incompletely closed claim, and the fix costs nothing,
either call `landed()` before `apply(...)`, since ordering between them does not matter to any
caller, or wrap the apply in a pcall inside the gate.

### M6. Every cold open of a pane presentation gains a visible sixty millisecond lateral jump that today's pane consumers do not have

Confirmed by construction, severity depends on the eye.

Today FileSearch, Processes, and the clipboard reserve their pane through `layout.companionWidth`
before the window is ever shown, so `_positionAndShow` at `lib/chooser/providers/native.lua:408`
computes `total` with the pane included and the window's very first paint is already in the right
place. The settle at 0.03 corrects for the real rendered height and moves it by a few points at
most.

Under the stage, `layout.companionWidth` is fixed at zero for the life of the instance by design,
stated at `host/stage/init.lua:46`. So the first paint centres the window as a lone 480 point
chooser, the settle at 0.03 confirms that same wrong centre, and the stage's own timer at 0.06
moves it left by `(gap + paneW) / 2`. With `paneWidth = true` and the uniform 480 width that is
246 points, roughly four frames after the window appears.

The module comment asserts this is "short enough that the eye never catches a second move", `:96`.
That is an assertion, not a measurement, and nothing in probe section C measured perceived motion.
Section C3 only established that `setTopLeft` works and that the widget stays live, with its first
sample at fifty milliseconds.

The pane's own first paint is also pushed to 0.06, since the presentation's onPositioned is not
fired before then, so the pane area is empty for four frames as well.

This is a design consequence of the brief's own decision one rather than a coding error, and it is
worth naming so phase five judges it against the alternative, which is letting a presentation set
`layout.companionWidth` before a cold show and paying the stage shift only on a swap. That would
cost a second `lib/chooser` touch the brief forbids for this phase, which is a fine reason to defer
it and a bad reason to never look at it again.

---

## Low

**L1. `_positionPane` has no equivalent of the atom's `self.active` guard.** `host/stage/init.lua:441`
finds its window by title and visibility alone, the same trick as `_settleFrames`, but
`_settleFrames` first checks `if not self.active then return end`, `lib/chooser/providers/native.lua:336`.
Consumer map 9.1 records a thirteenth unmanifested chooser at `lib/overlaydisplay.lua:418`, plus
twelve unmigrated ones, and every one of their windows is also titled "Chooser". If any of them is
visible when the stage's timer fires, `_positionPane` moves that window instead. The stack identity
guard at `:442` catches the case where the stage's own presentation changed, not the case where a
foreign chooser is the only visible one. The root's own "at most one chooser is showing" assumption
covers it in practice, and the atom is already leaning on the same assumption, so this is inherited
rather than introduced, but the stage inherited it without the one guard that made it safer.

**L2. A timed out status leg shows the stale snapshot with nothing marking it stale.** On timeout
`current` is deliberately untouched, `plugins/vpn/init.lua:451`, `fetching` goes false, and `rows`
draws the previous state as though it were fresh. If the daemon wedges during a connect, the picker
reports "Disconnected" while the tunnel is up. Better than hanging forever, which is what it
replaces, but an honest third answer exists, `current = { state = "unavailable" }` on timeout, and
the code chose the quieter one without saying it was a choice about what the user sees rather than
only about what the code holds.

**L3. `runAsync`'s new failure callback has no listener for the three calls it names.**
`plugins/vpn/providers/mullvad.lua:135` now answers `cb(false, "mullvad failed to launch")`, and the
comment at `:120` says the old silence left "nothing to tell connect, disconnect, or setLocation
their own action never ran". All three call sites pass no callback at all, `plugins/vpn/init.lua:287`,
`:289`, `:294`, so `cb` is nil and the new branch does nothing. The guard is correct and worth
keeping for a future caller. The comment overstates what it delivers today.

**L4. The stage reaches into the instance's private layout and writes `paneFrames` directly.**
`host/stage/init.lua:199` reads `self._instance.layout.rowCount`, `:447` reads `L.paneMaxW` and
`L.gap`, and `:462` writes `self._instance.paneFrames`. The brief permitted exactly one lib/chooser
change, `setRows`, "keep it a passthrough", and the letter of that is honored. The spirit is not,
because the stage now depends on three internal fields of the atom that no method exposes, and the
atom will silently overwrite `paneFrames` on its own next show. A reader of `native.lua` has no way
to learn that another file writes that field. At minimum the atom's own doc block should say so.

**L5. The contract doc overclaims what a migrating plugin has to change.** `docs/PLUGIN-CONTRACT.md`,
the new paragraph, says a plugin "hands over the identical function it already wrote for that field
on a `Chooser.new` call, with nothing to rewrite beyond where it is declared". Three things are
wrong with that for all three existing pane consumers. Their `onPositioned` is a file local
function, `plugins/filesearch/chooser.lua:435`, `plugins/processes/chooser.lua:337`,
`plugins/clipboard/manager/ui.lua:1172`, and a manifest member spec can only name a module member,
so it has to be exposed first. Each ends by calling `cfg.onPositioned(anchor)`, which under the
stage now races the stage's own panel call, see M2. And FileSearch's seeds a first pane paint from
`picker:selectedItem()` at `:449`, which no longer exists once the plugin stops holding its own
instance. The paragraph should say the function moves largely intact, not that nothing is rewritten.

**L6. Nothing in the tree discloses the pop gap.** The commit message names present and push and
never mentions pop, the module header geometry paragraph at `host/stage/init.lua:44` names present
and push, and `pop`'s own docstring at `:553` is silent. `_announce`'s comment at `:482` shows the
file is perfectly capable of stating a deliberate pop exclusion when it makes one. If pop is meant
to stay geometry free until phase five, the docstring should say so and say why, so the next reader
does not have to derive H1 the way I did.

**L7. The stage's instance declares no `onScroll`, so a migrated pane consumer loses the wheel.**
`_startScrollWatcher` at `lib/chooser/providers/native.lua:690` returns immediately when
`config.onScroll` is absent, and the stage's `Chooser.new` at `host/stage/init.lua:174` names every
other seam and not that one. Consumer map 7.3 records two consumers of it, the clipboard and
FileSearch. This is a phase five gap rather than a defect here, and it belongs on that phase's list
now rather than being discovered when a preview pane stops scrolling.

**L8. The VPN timeout timers are never stopped on the success path.** All three stay armed for the
full five seconds after a round that landed in a hundred milliseconds, then fire into a shut gate.
Harmless. I checked the reuse of `fetchTimers` carefully and it is safe, see the sound section.

---

## What I checked and found sound

**The pane arithmetic is an exact mirror of the atom's, with no off by one anywhere.** Side by side,
`host/stage/init.lua:447` through `:461` against `lib/chooser/providers/native.lua:344` through
`:351` and `_companionFrame` at `:314`. Same `total = cf.w + (paneW > 0 and (L.gap + paneW) or 0)`,
same `x = sf.x + math.floor((sf.w - total) / 2)`, same companion at `x + cf.w + L.gap` with the
chooser's own `w` and `h`. The gap is added once, on the correct side, and the centring divides the
same total the same way. The one deliberate divergence is `y`, the stage keeps `cf.y` rather than
recomputing `_topBiasedY`, which is right, the settle has already placed it and a second vertical
decision would fight the first.

**`_resolvePaneWidth` is stricter than the atom and never worse.** `:468` against `:305`. Both map
`true` to the chooser width and both cap at `paneMaxW`. The atom's `if not cw or cw <= 0` would
raise on a string, the stage's `type(w) ~= "number"` will not. Absent, false, zero, and negative all
answer zero on both.

**`paneAnchor` is arithmetically identical to all three copies it replaces.**
`host/stage/init.lua:664` against `plugins/clipboard/manager/ui.lua:1181`,
`plugins/filesearch/chooser.lua:454`, `plugins/processes/chooser.lua:347`. Same `x`, `y`, `h` from
the chooser, same `w = (companionFrame.x + companionFrame.w) - chooserFrame.x`, and the same return
of the chooser frame itself, by reference, when there is no companion. A migrating plugin gets
byte identical results. Decision three is honored exactly.

**`_defaultRowCount` is read at the only moment it is still honest.** `:199`, immediately after
`Chooser.new` and before any `setRows` on that instance. `Chooser.new` copies `DEFAULT_LAYOUT` into
a fresh per instance table, `lib/chooser/providers/native.lua:1050`, so this reads 10 and cannot be
nil, which also means `desired` can never be nil and `setRows(nil)` is unreachable through the
default path. It also means the stage's `setRows` writes cannot leak into any of the other twelve
instances, each of which owns its own layout table.

**The geometry timer is held, cancelled on both doors, and identity guarded.** Held in
`self._geometryTimer`, the repo's documented collection hazard closed the same way `_settleFrames`
closes it. Cancelled unconditionally at the top of `_applyPaneGeometry`, before the skip check,
which is the right order and the comment gives the right reason. Cancelled again in `hide()`.
`_onClose` does not cancel it, and does not need to, because it empties the stack and the identity
guard `if self:_current() ~= p then return end` at `:442` then makes the stale fire a no op. I
walked escape at t = 0.02 with the fire at t = 0.06 and it lands harmlessly. Nilling the field
inside the callback before calling `_positionPane` is safe, a one shot timer that has already fired
loses nothing by being finalised.

**Settle and stage timer ordering cannot invert.** The settle is armed inside `show()`, the stage's
is armed after `show()` returns, so their fire dates are 0.03 and 0.06 plus a positive epsilon.
Even with the main thread blocked past both, the run loop fires by scheduled date, so the settle is
always first. The 0.06 against 0.03 choice is sound for the cold path. It is the swap path that is
wrong, M1.

**The row count comparison is cheap and correct for the no change case.** `desired == self._rowCount`
short circuits with one comparison for every present and push in the tree today, so the brief's
"costs nothing" claim for unchanged behavior holds for the row count half as well as the pane half.

**Today's observable behavior really is unchanged, and I traced it rather than assumed it.** Neither
the launcher nor VPN declares `paneWidth` or `rowCount`. `_applyRowCount` returns false on the first
comparison. `_applyPaneGeometry` returns on `not p.paneWidth and self._paneW == 0`. The `_show`
restructure reduces to the old `if wasShowing then swap else capture and show end` exactly, since
`resized` is always false so `cold` is `not wasShowing` and the capture guard is always taken.
`_onClose`'s new first line is always false. `hide()`'s two new lines act on a nil timer and a zero.
Acceptance met.

**The registrar addition is consistent with the phase three rule.** `onPositioned` is in
`presentationFields` at `lib/registrar.lua:424`, so it goes through `callKindStated`, refusing the
bare string shorthand and refusing a member that leaves `call` unstated, and through
`memberResolves(owner, member)` against the real already loaded module, with the same console line
and the same `broken` path that hands an empty table down to `presentationIsWellFormed` rather than
returning nil. Refusal semantics are structural, the whole registration falls, which matches every
sibling. The doc paragraph in `PLUGIN-CONTRACT.md` describes that behavior accurately, including
naming `paneWidth` and `rowCount` as the two fields exempt from the member spec rule, which is
exactly what the code does. The only doc inaccuracy I found is L5.

**`setRows` is exactly a passthrough and no existing consumer can reach it.** One line,
`self.layout.rowCount = n`, no side effect on a live window, which is what probe C2 measured. I
grepped the whole spoon, the only callers are `host/stage/init.lua:375` and `:381`. No other
consumer names it, nothing iterates instance members by name, and `lib/surface.lua` and `lib/nav.lua`
forward a fixed set that does not include it. Adding it to the picker contract list in
`lib/chooser/init.lua:7` is prose, nothing validates a provider against that list. So the accidental
reach surface is empty. My objection to it is only that it validates nothing, H3.

**The VPN once only gate is genuinely once only, per leg and in aggregate.** `landedGate` gives each
leg its own `fired` upvalue, and both `onAnswer` and `onTimeout` test and set it before doing
anything, so exactly one of the two ever calls `landed()` for that leg. `remaining` starts at three
and is decremented exactly three times, so it reaches zero exactly once, `fetching` is cleared once,
and `pending` is swapped for a fresh table before the flush so a callback that calls `prepare` again
during the flush queues into the new table rather than the one being iterated. A timeout landing
after a genuine answer finds `fired` true and returns, so no double decrement and no double flush.
Verified.

**`fetching` resets on every path.** Available false returns before `fetching` is ever raised. A
second call while `fetching` is true appends to `pending` and returns without starting anything.
Every started round has exactly three legs and every leg resolves, by answer or by timeout, so
`fetching` always returns to false. The one hole is M5, an error inside `apply`.

**Reusing one `fetchTimers` table across rounds is safe, and for the reason the comment gives.** A
new round can only start once `fetching` is false, which means all three of the previous round's
gates are already shut. So overwriting the three slots can never orphan a timer whose gate is still
open, and a previous round's timer losing its last reference and being finalised early costs
nothing.

**The four `t:start()` checks are correct and complete.** All four spawns in
`plugins/vpn/providers/mullvad.lua` are covered, `runAsync` at `:135`, `statusAsync` at `:161`,
`selectedLocationAsync` at `:174`, `listLocations` at `:233`. `hs.task:start()` answers the task on
success and nil on failure, so `if not t:start()` reads it correctly. The failure branch and the
completion callback are mutually exclusive, a task that failed to start never runs its completion,
so no leg can be answered twice even before the gate. Each degraded value matches what a missing
`cli` already answers on the same door, `{ state = "unavailable" }`, nil, and `{}`.

**`world()` across the push and resize cycle is correct.** `_bumpOpenId` fires only from
`_freshStack`, so a push does not advance the open id, which is what a consumer keying a per open
cache off it wants. `_captureCoveredApp` is correctly skipped when `resized` is true, since the
resize hide and show gives focus nowhere else to go and recapturing would record Hammerspoon. The
finding five split is preserved exactly.

**The highlight across the cycle is correct.** The resize path ends in `show()`, which does
`selectedRow(1)` before revealing, `lib/chooser/providers/native.lua:759`, and pop does
`refresh(true)`, so both ends of a row count cycle land on row one as the contract says.

---

## Verdict

Not ready.

Nothing here breaks the live config today and the acceptance criteria in the brief are met. But
three high findings sit directly in phase five's path, and one of them, H3, is the declaration
level class this track has already been burned by, where a manifest states something false, every
layer passes it through untouched, and the damage lands in an arithmetic operation two files away.
H1 and H2 are the same omission seen twice, pop and the outgoing presentation are both blind to
geometry, and both close for a few lines. M1's invariant is provably wrong as written and its
comment argues for it, which is worse than an unstated assumption.

The rework I would ask for before this lands, in order. Give pop the geometry path by routing it
through `_show`. Fire the outgoing presentation's onPositioned with a nil companion when it loses
the pane. Validate `rowCount` at the registrar beside the call kind loop. Replace `cold` with a
settled test in `_applyPaneGeometry`. Move the panel re anchor into `_positionPane`. Put unwind
protection on `_suppressClose`. Call `landed()` before `apply()` in the VPN gate. Everything below
that is a comment or a doc sentence and can travel with the fixes.

One thing to add to the live gate script when it runs. The row count resize path's effect on
`hs.chooser`'s own focus restore, M4, which no probe has measured and which the one resize path this
phase builds depends on.

---

# Second pass, 2026-08-27, verification of the rework at dee23ee

feat/chooser-geometry, dee23ee on top of 591f51a, same worktree. Focused verification of the
eight triaged items plus the two the builder applied unasked. Gates rerun by me from the
worktree root.

    luac -p on all seven touched lua files, clean
    src/check-dependencies.sh, "Dependency check passed, 0 warning(s)", exit 0
    git status clean after the reconciler ran

Five new findings, all low or informational, none blocking. No new medium and no new high.

## Verdict per finding

### H1, pop routes through _show. Fixed.

`host/stage/init.lua:663` through `:668`. pop's hand rolled trio is gone and the body is
`self:_show(below, self._instance:isShowing(), leaving)`. Traced the caffeinate shape end to
end. Launcher present cold at ten rows, push caffeinate, `_applyRowCount` sees 2 against 10 and
drives the suppressed hide and reshow, Backspace pops, `_show` now runs `_applyRowCount` again
and sees 10 against 2, drives the resize back, and `show()` brings the launcher up at ten rows.
The two row window can no longer survive the pop. The docstring at `:649` through `:659` and
the module header at `:65` both state that pop applies geometry now, which closes L6 in the
same edit rather than leaving a disclosed gap.

### H2, the outgoing presentation is told it lost the pane. Fixed.

`host/stage/init.lua:366` through `:368`, inside `_show`, and the capture sites at `:592` in
present, `:627` in push, and `leaving` handed straight in from pop at `:667`. All three doors
now pass an outgoing. Verified the placement is genuinely before the incoming side is given
anything, the notice sits above the `if cold` branch, so it precedes both `show()` and the swap
path's own `_applyPaneGeometry`.

The two guards are right. `outgoing ~= p` correctly skips a reopen, which matters on push's own
dedup at `:634` and on present reopening the top, where `closeStackExcept` already skips the
survivor for the same reason. `outgoing.onPositioned` skips a presentation that declares none,
matching every other optional field in the file.

The double notice on pop, `leaving.onClose()` at `:665` and then `leaving.onPositioned(nil, nil)`
a moment later, is defensible as the builder argues. They are told for different reasons and a
canvas erase is idempotent. Verified the same double does not happen on push, which fires
nobody's onClose, which is exactly the door where the notice was load bearing.

The nil convention is documented, which was the half of this I would have failed it on if it had
stayed a code comment. `docs/BRIEF-STAGE.md`, the onPositioned field entry now says "Also told
with both frames nil, once, when present, push, or pop makes a different presentation current",
and `docs/PLUGIN-CONTRACT.md` says the same in its own paragraph. A plugin author writing
`if companionFrame then` and never considering a nil chooserFrame now has a doc telling them to.

### H3, rowCount and paneWidth type checked at the registrar. Fixed.

`lib/registrar.lua:465` through `:479`. Both checks sit immediately after the call kind loop and
inside the same `type(manifest.presentation) == "table"` block, so they share the `broken` flag.

Loudness and recording are identical to the phase 3 rule, which is what I was asked to confirm,
and I traced the whole path rather than reading the flag. `broken` true leads to
`presentation = {}` at `:512`, that empty table reaches `presentationIsWellFormed` in
`lib/registry.lua`, which refuses it on "has no rows function", `register` answers false, and
`lib/wire.lua:421` records `fail("register", name, "was refused by the registry, see its own
warning line for why")` into `record.problems`. Same console level, `deps.log("e", ...)`, same
message shape naming the tool and the field, same wire report entry as the nine member spec
refusals. Nothing about this refusal is quieter than its neighbours.

`lib/registry.lua`'s own comment was updated to say the two are checked one layer up rather than
"passed through untouched", so the two declaration readers no longer describe different rules.
That is the two declaration systems drift hazard closed rather than reopened.

Residual, N4 below, the check is for a number and not for a usable number.

### M6, companionWidth written into the live layout. Fixed, and it is the strongest change here.

`host/stage/init.lua:356`, `self._instance.layout.companionWidth = p.paneWidth`, written on
every door before anything touches the window. This is a better answer than the one I asked for
and it dissolves most of M1 as a side effect.

Verified the value is safe for everything the registrar now permits. A number, `true`, and nil
all pass through the atom's own `_resolveCompanionWidth` correctly, `not cw` catching nil and
`cw == true` catching the inherit case. The registrar refuses anything else before it can get
here, so the raw write cannot hand the atom a string.

Verified the field self heals rather than persisting. `hide()` and `_onClose` do not reset it,
which I checked deliberately, but every path that shows the window runs `_show` first and `_show`
always writes it, so a stale value from a dismissed pane presentation cannot survive into the
next open. `self._instance:show()` appears at exactly one place in the file, `:384`.

The claim in the comment about a pending settle is correct and I confirmed it rather than took
it. `_settleFrames` reads `layout.companionWidth` live at fire time, `lib/chooser/providers/native.lua:344`,
so a settle left armed by an earlier cold show now computes for whatever presentation is current
when it fires, not for the one that armed it. Paired with `_onPositioned` reading `self:_current()`
rather than a captured presentation, this means a swap landing inside the settle window is
reported to the right consumer with the right frames by the atom itself. That is the interplay
the coordinator asked me to attack, and it holds.

### M1, the age gate against _lastShowAt. Partially fixed.

The wrong invariant is gone. `_applyPaneGeometry` at `:457` now gates on
`age = hs.timer.secondsSinceEpoch() - (self._lastShowAt or 0)` against `ATOM_SETTLE_DELAY`
rather than on whether this call happened to be cold, and the false comment about a swap racing
nothing is deleted. The nil fallback to zero yields an enormous age and runs immediately, which
is the right default.

`_lastShowAt` is set on every show path. `show()` is called at `:384` and nowhere else in the
file, and the stamp is the line directly above it, `:383`. It cannot go stale in the sense of
missing a show.

It is stamped in the wrong place by a measurable margin, which is N1 below. The outcome still
converges, because M6 made the atom's own settle authoritative and correct, so whichever of the
two runs last computes the same pair. I am calling M1 partially fixed rather than fixed because
the comment at `:96` through `:104` and at `:449` through `:456` states a guarantee the code
does not deliver, and a wrong comment about timing is what produced M1 in the first place.

### M2, the docked panel re anchor. Fixed.

`host/stage/init.lua:549` through `:555`, the new `_onPositioned`, and the wiring at `:193` that
routes the atom's own `config.onPositioned` through it instead of handing `_panelOnPositioned`
over directly. Both the native cold show path and the manual swap path converge on it,
`_positionPane` ending at `:523` with `self:_onPositioned(chooserFrame, companionFrame)`.

Verified the panel's argument shape did not change for anything shipping today. It used to
receive the atom's two arguments and read only the first. It now receives one argument,
`paneAnchor(chooserFrame, companionFrame)`, which returns `chooserFrame` itself when there is no
companion. Byte identical for the launcher and for VPN.

The double writer risk I raised is closed in the right place. `docs/PLUGIN-CONTRACT.md` now tells
a migrating plugin to drop its own `cfg.onPositioned(anchor)` call and says why, naming it as
"a second, competing writer of the identical panel". So the panel has exactly one writer, the
host that claims to own it.

### M3, the suppress flag hardened. Fixed.

`host/stage/init.lua:424` through `:431`. `pcall(function() self._instance:hide() end)`, flag
cleared on the very next line unconditionally, and a `log.w` naming the raise rather than
swallowing it. Spot checked the failure continuation, a raised hide still returns true so `_show`
takes the cold branch and calls `show()`, which on an already visible chooser reruns
`_positionAndShow` and rearms cleanly. There is no longer any path that leaves `_suppressClose`
true past this function.

### M5, the VPN pcall, and the builder's disagreement. Fixed, and the builder is right.

`plugins/vpn/init.lua:455` through `:459`. `local ok, err = pcall(apply, ...)` with a `log.w` on
failure, `landed()` unconditionally on the line after. The varargs forward correctly through
pcall and the list leg's closure is the only one that could raise.

Their ordering argument is correct and my suggested alternative was wrong. I asked for
`landed()` before `apply()` as an equally good close. It is not. `landed()` at zero flushes
`pending`, and every one of those callbacks redraws from `current`, `target`, and `cache`. The
last of the three legs to land is by definition the one whose own apply has not run yet at that
moment, so calling `landed()` first would flush a redraw that reads that leg's stale value on
every single round, not only on a failure. That is a real regression traded for a hypothetical
one. pcall keeps the ordering and puts a floor under it, which is the strictly better fix.
Conceded.

The four ways `fetching` returns to false, confirmed by reading rather than by taking the list.
One, all three legs answer normally, each `onAnswer` calling `landed()` once through its own
`fired` gate at `:443`. Two, a leg's task never calls back and its `hs.timer.doAfter` at `:479`
through `:481` fires `onTimeout`, which calls `landed()` without touching state. Three, a leg's
apply raises and the new pcall lets `landed()` run anyway, which is this fix. Four, a leg's
`hs.task:start()` answers falsy and the provider calls the callback synchronously with the
degraded value, `plugins/vpn/providers/mullvad.lua:161`, `:174`, and `:233`, which counts down
through the ordinary `onAnswer`. Plus the path where `fetching` is never raised at all, the
`available` false early return at `:426`. Every started round has exactly three legs and every
leg now resolves on all four. There is no remaining door to a stuck `fetching`.

### The eight lows

L1 fixed, `host/stage/init.lua:495`, `if not (self._instance and self._instance.active) then return end`,
placed before the window search, the same guard `_settleFrames` opens with. A foreign chooser
window cannot be moved in this instance's place.

L2 fixed, `plugins/vpn/init.lua:472` through `:478`, the stale snapshot is now named as a
deliberate choice weighed against reporting a confident wrong answer. The reasoning given is
sound.

L3 fixed, `plugins/vpn/providers/mullvad.lua:125` through `:131`, the comment no longer claims
the branch delivers to connect, disconnect, or setLocation and says plainly that none of the
three passes a callback today.

L4 fixed, `lib/chooser/providers/native.lua:1055` through `:1065`, the constructor now documents
that host/stage reads layout and writes companionWidth and paneFrames directly. Accurate, and it
correctly notes that neither `_positionAndShow` nor `_settleFrames` reads paneFrames back.

L5 fixed, `docs/PLUGIN-CONTRACT.md` no longer says nothing is rewritten and names the three
things that move, becoming a resolvable member, dropping the panel call, and FileSearch's own
instance held seed. All three are the ones I found. Honest.

L6 fixed by H1's own fix rather than by disclosure, which is the better outcome.

L7 left alone, and the disposition is honest in substance. The stage's Chooser.new still names
no `onScroll`, confirmed by grep, and pane content interaction is genuinely outside the geometry
brief's decision four. See N5 for the one thing about the wording I would not let stand.

L8 left alone, and the disposition is honest. It matches what my own sound section concluded
about the timers firing into an already shut gate, and I reverified the `fetchTimers` reuse
argument still holds unchanged.

### M4, deferred to the live gate. Honest.

Nothing in this commit can measure what `hs.chooser` restores focus to across a same tick hide
and show without driving the screen, which is exactly what my first pass asked for. It stays on
the gate script's list.

## New findings

### N1. _lastShowAt is stamped before show(), so the age gate under waits by one show. Low.

`host/stage/init.lua:383` stamps `_lastShowAt`, `:384` calls `show()`. The atom arms its settle
timer inside that call, at the end of `_positionAndShow`, `lib/chooser/providers/native.lua:427`,
after `chooser:show()` at `:426`. So the settle's fire moment is `_lastShowAt + duration(show) + 0.03`,
while `_applyPaneGeometry` schedules its own for `_lastShowAt + 0.03`, one full `show()` earlier.
`show()` is not free, it reselects the theme, rebuilds every row, and calls `hs.chooser:show`,
which probe section C measured as the dominant cost in a ninety to a hundred and sixty
millisecond open.

So a swap landing inside the gate window will in practice run its manual placement before the
settle it claims to wait out, reading a frame the probe itself notes renders taller than its
steady state on a first show. The comment at `:454` says it "still waits out whatever remains of
that window before reading the frame itself", and it does not.

The consequence is benign only because M6 landed. The atom's settle runs afterwards, recomputes
with the honest `companionWidth`, overwrites `paneFrames`, and fires `_onPositioned` again, so
the end state is right. The cost is one spurious `_onPositioned` carrying a pre settle height to
the pane consumer and the docked panel, and one extra small move.

Fix is to move the stamp to after `show()` returns. One line, and it makes the comment true.

### N2. The unconditional geometry timer cancel was lost on the cold path. Low.

Before the rework `_applyPaneGeometry` was called on both branches of `_show` and cancelled
`_geometryTimer` unconditionally at its top. It is now called only from the swap branch, `:393`,
so a cold show cancels nothing. `hide()` still cancels at `:684`, but `_onClose` does not, which
was already true and is now reachable.

The sequence. Swap into a pane presentation A within thirty milliseconds of a cold show, so a
timer is armed. Escape before it fires, which runs `_onClose` and clears the stack without
cancelling. Re present A within the remaining milliseconds. The cold branch cancels nothing, the
stale timer fires, `_current()` is A again so the identity guard at `:494` passes, and
`_positionPane` runs against a window whose own settle has not fired yet.

It converges, the new settle corrects it, so this is genuinely low. It is worth closing because
the cancel used to be unconditional for a stated reason and the reason did not go away, only the
call site did. Moving the three cancel lines to the top of `_show` restores it for every door.

### N3. pop can now open a hidden window, capture a covered app, and not bump the open id. Low, unreachable today.

`:667` passes the real `self._instance:isShowing()` as `wasShowing`. When that is false, `_show`
takes the cold branch with `resized` false, which runs `_captureCoveredApp()` and `show()`. So
pop gained the ability to open the window, and it does so without `_freshStack`, meaning
`_bumpOpenId` never runs and a consumer keying a cache off `world()` would serve an answer
belonging to the previous open.

Unreachable today and I checked rather than assumed. `pop` has exactly one caller, `_back` at
`:846`, which the atom only invokes from its key watcher while the window is up, and every path
that hides the window also empties the stack, `hide()` at `:687` and `_onClose` at `:869`, so
`#self._stack <= 1` refuses first. Passing the honest visibility rather than a hardcoded true is
the more defensible choice, so I would close this with a comment on the docstring saying the
cold branch is unreachable and why, not with a guard.

### N4. The rowCount type check accepts numbers that are not usable row counts. Low.

`lib/registrar.lua:465` checks `type(p.rowCount) ~= "number"` and nothing more, so zero, a
negative, and a fractional value all pass. They reach `math.min(L.rowCount, maxRows)` at
`lib/chooser/providers/native.lua:403` and then `self.chooser:rows(rows)` at `:404`, with
`paneH = L.baseH + rows * L.rowH` computed from the same value.

This is a real improvement over the crash it replaces, and the check does match the contract's
own wording, "a plain number". But a manifest declaring `rowCount = 0` still produces a
degenerate window rather than a named refusal, and the refusal is free. `type(n) ~= "number" or
n < 1 or n % 1 ~= 0` in the same condition, with the message widened to say a positive whole
number, closes it.

### N5. The commit message claims L7 is named on a phase five list that does not exist. Informational.

"L7, left alone, a phase five gap named on that phase's own list". I grepped the docs directory.
`onScroll` appears in `docs/CONSUMER-MAP-2026-08-27.md` only as inventory, at `:33`, `:98`,
`:135`, the capability table at `:207`, and the pane section at `:797`. No phase five list in the
tree names it as an open item. The disposition itself is correct and I am not asking for the
code to change. The claim should either become true, one line added wherever phase five's own
items are being collected, or stop being made.

## Interactions I attacked and found sound

**The three doors converge on one geometry path.** present, push, and pop all reach `_show` with
an outgoing, `_show` writes `companionWidth` before anything else, tells the outgoing, then
either lets the atom place the pair natively on a cold show or places it by hand on a swap, and
both routes end at `_onPositioned`. I traced a push of a paned presentation over the launcher and
a pop back, frame by frame. On the push the window shifts left by the resolved half pair, the
click watcher gets a `paneFrames.companion` covering the real pane so a click on it is no longer
read as a dismissal, and the panel is anchored spanning both. On the pop the outgoing is told
nils and erases, the window slides back to the lone centre, `paneFrames.companion` returns to
nil so the dead rectangle stops swallowing clicks, and the panel is re anchored to the plain
chooser frame. Every one of the four things I said was broken in H1 and H2 now happens.

**`_onPositioned` reading `self:_current()` rather than a captured presentation is correct and
load bearing.** I went looking for this as a bug and it is the opposite. A settle timer armed by
an earlier cold show fires after a swap has already changed what is current. Because `_show`
rewrote `companionWidth` for the new presentation, that settle computes the new pair, and because
`_onPositioned` asks who is current now, it reports it to the new presentation. Capturing the
presentation at arm time would have been the bug.

**The tie at the gate boundary is harmless in both orders.** `ATOM_SETTLE_DELAY - age` schedules
the stage's timer for the same instant the atom's settle is due, and run loop ordering between
two timers with the same fire date is not something either file may rely on. With M6 landed both
compute the same pair from the same live `companionWidth`, so whichever runs last is right. This
is only safe because of M6, and it is worth knowing that the safety comes from there rather than
from the gate.

**The swap skip condition no longer needs persisted state.** `_paneW` is gone and
`hadPane = outgoing and outgoing.paneWidth` replaces it. I walked a chain of paneless swaps after
a pane presentation and the window is correctly repositioned exactly once, on the transition that
loses the pane, and left alone after that. Reading the outgoing declaration is a truer question
than the field it replaces, and it removes a piece of state that could disagree with reality.

**The `_applyRowCount` interaction with the pane on a cold reshow.** A pop or a push that resizes
takes the cold branch and never calls `_applyPaneGeometry`, which looked like a hole until I
followed it. `companionWidth` was written before `_applyRowCount` ran, so the reshow's own
`_positionAndShow` computes the pair natively and fires `_onPositioned` on its own. Correct, and
the ordering inside `_show` is what makes it correct, so it is worth not reordering those lines
later.

**onClose semantics survived the pop refactor intact.** `leaving.onClose()` fires exactly once,
before `_show`, and `_show` fires nobody's onClose. A resize inside pop runs the suppressed hide
whose teardown reaches `_onClose` and returns early, so no presentation hears a second close and
none is skipped. Verified against present and push too, `closeStackExcept` behaviour is unchanged
and the new outgoing notice is additive rather than a replacement.

## Verdict

Ready for the shared live gate.

All three highs are fixed and I traced each rather than reading the diff. M2, M3, M5, and M6 are
fixed. M1 is partially fixed, the wrong invariant is gone and the outcome is correct, and its
residual is N1, a comment that overstates a timing guarantee, with the real behaviour made safe
by M6 rather than by the gate. M4 is correctly left for the gate script, which should still
measure what `hs.chooser` restores focus to across the resize path's same tick hide and show,
since that is the one thing in this phase nothing has measured.

The five new findings are all low or informational and none of them changes what a user's fingers
will meet. N1 and N2 are each a small move of existing lines and would be worth taking before or
just after the gate, N4 is a free tightening of a refusal that already exists, N3 wants a comment
rather than code, and N5 wants a sentence somewhere or none at all.
