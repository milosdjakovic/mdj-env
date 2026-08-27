# Adversarial review, chooser stage phase two

Commit 617a5494 on feat/chooser-stage, reviewed against main in the worktree at
`/Users/milos.djakovic/Development/personal/.worktrees/chooser-stage`. Read whole,
`host/stage/init.lua`, `host/stage/manifest.lua`, `host/launcher/init.lua`,
`host/launcher/manifest.lua`, and every part of `root/compose.lua` the diff touches, plus
`lib/wire.lua`, `lib/resolve.lua`, `lib/services.lua`, `lib/plugins.lua`, `lib/loader.lua`,
`lib/registrar.lua`, `lib/nav.lua`, `lib/hints.lua`, `lib/chooser/init.lua`,
`lib/chooser/providers/native.lua`, and `host/actionpanel/init.lua`. The four contract
documents were read from the main checkout, since they are untracked and do not exist inside
the worktree. Nothing was edited, no Hammerspoon was reloaded, no devlock was taken.

Ten findings. One medium high, three medium, six low. No finding is fatal on its own and
none of them is the nil sibling wiring class the audit history warns about, which I looked
for specifically and did not find.

---

## 1. A new console error on every load, stage.placeholder is owed and nothing pays it

**Severity** medium high, because the brief's own acceptance list names it.
**Verdict** confirmed by code reading.

`host/stage/manifest.lua:34` declares

    placeholder = { source = "root", policy = "optional", breaks = "..." }

and `root/compose.lua:1048` pays it with

    placeholder = policy.placeholder,

`policy` is `defaultsLib.merge(SHIPPED_POLICY, cfg.policy)` at `root/compose.lua:132`.
`SHIPPED_POLICY` at `root/compose.lua:90` through `root/compose.lua:113` carries no
`placeholder` key at all, and the person's own `cfg.policy` at
`dotfiles/hammerspoon/.hammerspoon/init.lua:67` through `:78` sets seven keys, none of them
`placeholder`. So `policy.placeholder` is nil, `stageOpts.placeholder` is nil, the key never
appears in `wireData.stage`, and the delivery check at `root/compose.lua:1653` finds it.

`servicesLib.owed` at `lib/services.lua:180` tests `(data[name] or {})[field] == nil`, and
`data` is `servicesLib.merge(wireData, lateData)`, so a nil value and an absent key are the
same thing to it. The line printed is a `log.e`, and it will read

    Olm compose, nothing supplied the root value 'placeholder' that stage declares as
    optional, so the field carries the atom's own bare default until the first presentation
    sets its own

BRIEF-STAGE.md's acceptance for phase two says "The console shows no new warnings on load."
This is a new error line on every single load, and it is exactly the shape
`root/compose.lua:1639` through `:1651` argues most strongly against, a check that cries wolf
so the next real line in the same list reads as noise.

The other five stage needs are genuinely delivered. `chooser` is `chooserAtom`. `theme` is
`policy.chooserTheme`, a real table from `config/settings.lua:82`. The panel triple is
`perPluginData.launcher.shortcutPanel`, and `lib/hints.lua:396` through `:401` returns all
three fields non nil, so all three arrive.

Two ways out, either drop the `placeholder` declaration from the stage manifest, since
nothing in the tree publishes that word through the fan out and the atom's own default is
already the answer, or add `placeholder` to `SHIPPED_POLICY`. The second is the better one,
since `ambientServices.placeholder` at `root/compose.lua:1094` has been nil for every
surfaced plugin all along and nothing was checking that either.

---

## 2. Launcher isShowing stopped asking whether there is a window, and present can leave the stack stuck

**Severity** medium.
**Verdict** the code path is confirmed, the timing window it needs is unproven.

`host/launcher/init.lua:1038` through `:1041` now answers

    return self._presentation ~= nil and self._stage ~= nil
      and self._stage:current() == self._presentation.name

Nothing in that consults `stage:isShowing()`. The only thing keeping the stack in step with
the window is `Stage:_onClose` at `host/stage/init.lua:349` through `:354`, which clears the
stack, and it only ever runs through `Chooser:_teardown` at
`lib/chooser/providers/native.lua:245`, which returns immediately when `self.active` is
already false.

Now the second half. `Stage:present` at `host/stage/init.lua:189` branches on
`self._instance:isShowing()`, which is `self.chooser:isVisible()` at
`lib/chooser/providers/native.lua:780`. When that answers true it swaps the list and never
calls `Chooser:show`, so `self.active` is never set back to true and no key watcher, click
watcher, poll loop, or settle is armed.

The concrete sequence. The launcher is open. A row completes, so `Chooser:_completion` at
`lib/chooser/providers/native.lua:715` fires `onSelect` and then `_teardown`, which sets
`active` false and fires `onClose`, and the stage clears the stack. Note that `_completion`
never calls `chooser:hide()`, it relies on the widget dismissing itself, so there is a real
interval in which `active` is false and `isVisible()` may still be true. If a present lands
in that interval, and the launcher has one that lands on a timer, `_runItem` at
`host/launcher/init.lua:223` fires at 0.1 seconds and the alias directory's own row runs
`launcherModule:show(query)` through `root/compose.lua:1442`, then `present` pushes the
launcher onto the empty stack, sees `isShowing()` true, swaps, and returns. The widget then
finishes dismissing. The stack now holds `launcher` with no window, no teardown pending, and
nothing that will ever clear it.

What that costs. `isShowingFor("launcher")` at `root/compose.lua:841` reads
`launcherModule.isShowing` on the root, answers true, so the `launcherOpen` predicate is
stuck on, so j, k, space, and the action panel chord stay bound to launcher navigation over a
list that is not on screen and the plain Hyper layer stays suppressed. It recovers on the
next hyper space, since `present` then finds `isShowing()` false and calls `show()`, but until
then the leader is wrong.

The old code could not reach this. `Launcher:show` used to call `self._instance:show()`
unconditionally, and `Chooser:show` always sets `active = true` and rearms every watcher.

Two independent fixes, either make `Stage:present` re show whenever the atom is torn down
rather than only when the window is invisible, or make `Launcher:isShowing` require both the
name and `self._stage:isShowing()`. The second is one line and closes the predicate half of
it whatever the timing turns out to be.

I could not settle the timing without running a probe, which the brief forbids at this stage.

---

## 3. The seeded query refresh gained a guard it never had

**Severity** medium.
**Verdict** plausible but unproven.

`host/launcher/init.lua:1017` through `:1021`

    self._stage:present(self._presentation)
    if query and query ~= "" then
      self._stage:setQuery(query)
      self._stage:refresh(true)
    end

`Stage:refresh` at `host/stage/init.lua:233` is

    if self._instance and self._instance:isShowing() then
      self._instance:refresh(resetRow)
    end

The old code called `self._instance:refresh(true)` straight, and `Chooser:refresh` at
`lib/chooser/providers/native.lua:787` guards on `self.chooser` alone and never on
visibility. So a guard that did not exist now sits between a freshly shown window and the
rebuild that makes the seeded query mean anything.

The launcher's own comment at `host/launcher/init.lua:994` through `:997` states exactly what
is lost when that rebuild does not happen, "setting a chooser's query does not fire the
callback that rebuilds the rows, so without it the field would read one thing and the list
would show another".

Whether it fires depends on whether `hs.chooser:isVisible()` is true the instant
`Chooser:show` returns. PROBE-FINDINGS-2026-08-27.md section A measured 41 to 60 milliseconds
for the show call and 99 to 130 milliseconds until a window titled Chooser could be found,
which is 40 to 70 milliseconds of gap, but that was measured through `hs.window` rather than
through `chooser:isVisible()`, so it does not answer this. Evidence pointing the other way is
that `_settleFrames` at `lib/chooser/providers/native.lua:333` finds a visible window at 30
milliseconds and positioning demonstrably works, which those two numbers cannot both be true
about.

Reachable through every `show(query)` caller, which today is the alias directory row at
`root/compose.lua:1442` and nothing else. One line of live probing settles it, and until then
this is the highest value unknown in the change.

---

## 4. present pushes onto whatever stack exists rather than starting a fresh one

**Severity** medium, entirely forward looking, unreachable in phase two.
**Verdict** confirmed by code reading, no phase two consequence.

BRIEF-STAGE.md decision 6 says "A tool opened by its own hotkey presents over an empty stack,
so backspace there has nothing to pop and the launcher does not appear uninvited. Opening the
launcher presents it as the bottom of a fresh stack."

`Stage:present` at `host/stage/init.lua:185` through `:187` only ever appends, and
`Launcher:show` clears nothing. The one thing that clears a stack is a teardown or an
explicit `hide`. In phase two there is one presentation, so the stack is either empty or
holds the launcher already, and the identity guard at `:185` covers the second case, which is
why nothing is broken today. Phase three inherits it, and the first plugin migrated will make
"the launcher does not appear uninvited" false, since presenting a tool over a live launcher
will push rather than replace and backspace will drop back into the launcher.

Worth deciding now rather than after a plugin lands on it, since the fix is a policy question
the brief already answered and the code does not implement.

---

## 5. The world capture is per hidden present, not per stack

**Severity** low, forward looking.
**Verdict** confirmed by code reading.

BRIEF-STAGE.md decision 7 says the capture happens "once per stack, at the first present over
a hidden window". `Stage:present` at `host/stage/init.lua:192` through `:194` calls
`_captureWorld` on every present that finds the window hidden, with no reference to the stack
depth, so the guard is a window guard rather than a stack guard. The two coincide in phase
two only because `_onClose` empties the stack on every teardown. A present that finds a hidden
window with a non empty stack, which is exactly the stuck state finding 2 describes, bumps
`_openId` mid stack.

Also worth recording that `Stage:world` at `host/stage/init.lua:259` has no readers anywhere
in the tree, which the brief explicitly sanctions, and the guard at
`host/stage/init.lua:161` correctly mirrors `host/launcher/init.lua:1008`, same `SELF_BUNDLE`
derivation, same test, so the phase three deletion the brief wants really will be a deletion.

---

## 6. Stage configure is not idempotent and a second call orphans a decorated instance

**Severity** low, not reachable today.
**Verdict** confirmed by code reading.

`Stage:configure` at `host/stage/init.lua:106` calls `self._chooser.new` unconditionally.
A second configure builds a second instance and drops the first, but
`ActionPanel:decorate` at `host/actionpanel/init.lua:377` through `:379` appends every
instance it ever sees to `self._instances` and never removes one, and
`ActionPanel:_findShowing` at `host/actionpanel/init.lua:288` walks that list and takes the
first that answers `isShowing`. So an orphan lives forever in the panel's roster.

Not reachable today. `lib/wire.lua:316` configures once per name in `plan.order`, the stage
declares no `wiring` block so `w.steps` calls nothing on it, and the composition root's own
comment at `root/compose.lua:1544` through `:1547` says the stage is not configured a second
time. It is worth naming anyway because the launcher sitting right beside it IS configured
twice, at `lib/wire.lua:323` and again at `root/compose.lua:1633`, and until this commit that
second call built a second Chooser and orphaned one exactly this way. This change removes one
orphan and introduces a place a new one could appear.

---

## 7. The composition root reaches into the launcher's manifest shape with a bare literal

**Severity** low.
**Verdict** confirmed by code reading.

`root/compose.lua:1044`

    local stagePanel = perPluginData.launcher and perPluginData.launcher.shortcutPanel

Two undeclared couplings in one line. The plugin key is a bare `launcher` rather than
`plan.identity.launcher or "launcher"`, which is the form every other host lookup in the file
uses, at `:557`, `:566`, `:1351`, `:1352`, `:1430`, and `:1548`. It happens to be correct
because `host/launcher/manifest.lua` declares no `name` and so its identity is its directory,
but it is the one place in this file that relies on that rather than asking. And
`.shortcutPanel` hardcodes the value of `surface.panelAs` from
`host/launcher/manifest.lua:239`, so the stage silently loses its docked panel if the launcher
ever moves to the flat form or renames the nest. That failure is loud rather than silent,
since three owed lines would name it, but the coupling itself is written nowhere.

Second, smaller point. The file's own header at `root/compose.lua:20` through `:24` says
"Every such seam below is commented as one and says why", and the four other host namings are
each marked "THE SEAM". The comment at `root/compose.lua:1034` through `:1043` explains itself
well but is not marked, while the launcher's own stage lookup at `root/compose.lua:1544` is.

---

## 8. Two sentences in the launcher manifest now describe deleted code

**Severity** low.
**Verdict** confirmed by code reading.

`host/launcher/manifest.lua:227` through `:232` says of `surface.member`, "This host builds a
dot called adapter over its own Chooser instance in configure". It does not any more.
`host/launcher/init.lua:271` assigns `self._surface = self._stage and self._stage.surface`.

`host/launcher/manifest.lua:234` through `:238` says of `panelAs`, "This plugin's configure
reads the docked panel's three callbacks nested under one field rather than as three flat
ones, so the shape is named here". Its configure no longer reads them at all. The field is
still load bearing, because `lib/services.lua:273` through `:275` is what puts the panel under
that name in `perPluginData` where the composition root now reads it for the stage, so the
declaration must stay. But it now describes a consumer that is the root rather than this
plugin, and the manifest is the contract a person reads.

The launcher also still receives `opts.shortcutPanel` through `lib/wire.lua:191` and
`root/compose.lua:1076`, and drops it on the floor. Harmless, and worth a line so the next
reader does not go looking for the consumer.

---

## 9. The stage's root sourced needs name words the fan out does not publish

**Severity** low, with a precedent in the tree.
**Verdict** confirmed by code reading.

PLUGIN-CONTRACT.md's own checklist says a `source = "root"` entry "names a field the
composition root actually publishes through the fan out, never a word this plugin invented for
itself". `rootValues` at `root/compose.lua:651` through `:707` publishes eleven words and none
of the stage's six is among them. They are delivered instead through the hand assembled table
at `root/compose.lua:1077` through `:1081`, which is the same door ActionPanel's own three go
through, declared the same way at `host/actionpanel/manifest.lua:32` through `:37`. So the
change is consistent with the tree and inconsistent with the document.

This is not merely a paperwork point. It is exactly why finding 1 exists. A word delivered by
hand rather than by the fan out has no mechanism keeping the declaration and the delivery in
step, so `placeholder` could be declared, never published, and reported as owed, with nothing
between the two halves noticing.

---

## 10. One word, two questions, isShowing on the surface and isShowing on the launcher

**Severity** low in phase two, a live landmine for phase three.
**Verdict** confirmed by code reading, no phase two consequence.

`Stage.surface.isShowing` at `host/stage/init.lua:132` answers whether the shared window is
visible, whatever is in it. `Launcher:isShowing` at `host/launcher/init.lua:1038` answers
whether the launcher is the current presentation. Both are reached by the routing layer, and
by different doors. `isShowingFor` at `root/compose.lua:841` through `:846` takes
`module.isShowing` when the root has one, and the launcher root does, so the `launcherOpen`
predicate reads the presentation name. `nav.activeSurface` at `lib/nav.lua:51` reads the
adapters built at `root/compose.lua:1207` through `:1233`, which resolve through
`manifest.surface.member`, which is `_surface`, which is now the stage's table, so navigation
routing reads the window.

They agree today because there is one presentation. The moment a second one exists,
`nav.activeSurface` will pick the launcher's adapter for any presentation the stage is
showing, since that adapter's `isShowing` is the stage's window and the launcher sits early in
`plan.order`. Every routed verb then reaches the launcher's surface rather than the tool's.
Worth settling before phase three, and the honest fix is probably for the stage to stop
lending its `isShowing` to a presentation's surface at all.

---

## What I checked and found sound

The nil wiring class the history warns about is not here. Every name in the two changed
manifests was followed to a real field on a real module.

* `host/launcher/manifest.lua:110`, `data.stage`, source root, optional. Delivered at
  `root/compose.lua:1551` as `stage = stageModule`, resolved at `root/compose.lua:1548` as
  `modules[plan.identity.stage or "stage"]`. The stage manifest declares no `name`, so
  `lib/plugins.lua:140` keys it by its directory, `plan.identity.stage` is `"stage"` at
  `lib/resolve.lua:118`, and `lib/loader.lua:65` keys the module the same way. Resolves.
* Ordering. `Launcher:configure` runs twice, once from `lib/wire.lua:323` with no stage and
  once from `root/compose.lua:1633` with one, and the stage's own configure is in the first
  pass, so `self._stage.surface` is a built table by the time the launcher captures it at
  `host/launcher/init.lua:271`. This was the most likely place for a nil capture and it is
  correct. Note it is correct by sequence rather than by a declared edge, since a
  `needs.data` entry creates no ordering constraint, but the sequence is fixed by the file
  rather than by the graph so it cannot reorder.
* The launcher's surface adapter is a lazy metatable proxy built at
  `root/compose.lua:1186` before `w.configure` runs, resolving `_surface` per method access
  at `:1189`, so its being nil at build time costs nothing.
* All six functions the old adapter carried are on `stage.surface`, `isShowing`,
  `selectNext`, `selectPrev`, `insertSelected`, `hide`, and `peekPreview`, matching
  CONSUMER-MAP surprise 9.14. `refreshList` maps to `refresh` at `root/compose.lua:1154`,
  which the old adapter also lacked and which still falls back to the plugin root at
  `root/compose.lua:1191` through `:1193`, reaching `Launcher:refresh`.
* Calling convention. `stage.surface`'s members are closures with no self parameter, and
  `surfaceAdapterFor` calls colon style first at `root/compose.lua:1197` through `:1199`, so the surface table
  arrives as an ignored first argument. No arity fault. `self._chooser.new` at
  `host/stage/init.lua:106` is dot called, matching `lib/chooser/init.lua:116`.
  `Stage:configure` is a colon method, matching `lib/wire.lua:273`.
* Every launcher reader of the old `self._instance` has a live replacement.
  `peekSelected` `:747`, `canPeekSelected` `:758`, `selectedKind` `:802` all go to
  `Stage:selectedItem` `host/stage/init.lua:292`. `seedQuery` `:818` and `enterPage` `:841`
  and `leavePage` `:879` go to `Stage:setQuery` and `Stage:setPlaceholder`. `currentQuery`
  `:869` goes to `Stage:query`. `refresh` `:894` goes to `Stage:refresh`. `show` `:999` goes
  to `present`, `setQuery`, and `refresh`. `grep` for `_instance`, `_chooser`, `_theme`, and
  `_shortcutPanel` in `host/launcher/init.lua` returns nothing.
* The intercept and back chain is correct in all three layers. The stage's own closures go
  into the table handed to `Chooser.new` at `host/stage/init.lua:116` and `:117`, the facade
  passes that same table to `native.new` and then to the decorate hook at
  `lib/chooser/init.lua:118` through `:121`, so `ActionPanel:decorate` at
  `host/actionpanel/init.lua:420` and `:434` wraps the stage's closures exactly once and the
  stage never touches config again, which is what BRIEF-STAGE.md decision 5 asks for. Under
  it, `Stage:_intercept` `:323` asks the presentation first and `Stage:_back` `:332` asks the
  presentation's `back` first and only pops when it declines, so the launcher's `leavePage`
  wins over a stack pop. `pop` answers false at depth one, so backspace stays an ordinary
  press, matching `lib/chooser/providers/native.lua:499` through `:508`.
* I walked the panel sequence by hand. Chord, `openActionPanel` at `root/compose.lua:1341`,
  `isShowingFor("launcher")` true, hosted branch resolves through `currentQuery` which now
  reads `stage:query()`, `toggle` finds the stage's instance through `_findShowing`, captures
  item, row, and query off it, swaps rows. Verb chosen, wrapped intercept answers first and
  never reaches the stage, `_leave` restores the query synchronously and defers the row and
  the run, the atom's own `refresh(true)` runs in between and reads the stage's `_rows`.
  Panel closed. Backspace on an empty field then reaches the wrapped back, falls through
  because `_openInstance` is nil, hits `Stage:_back`, the launcher declines with no page,
  `pop` answers false at depth one, the key falls through untouched. Correct at every step.
* onClose fires once. `Chooser:_teardown` at `lib/chooser/providers/native.lua:245` is
  idempotent on `self.active` and calls `config.onClose` once, decorate's wrapper at
  `host/actionpanel/init.lua:470` calls the original once, `Stage:_onClose` calls the panel's
  own `onClose` once and the presentation's own once. The launcher's presentation declares no
  `onClose`, so nothing fires twice and nothing that used to fire has stopped. A swap through
  `present` never tears the atom down, so it never fires on a swap, which is what the brief
  asks.
* MenuSearch's siblings still resolve. `plugins/menusearch/manifest.lua:26` names
  `launcher.coveredApp` and `:30` names `launcher.refresh`, and both methods are untouched at
  `host/launcher/init.lua:1028` and `:894`. The launcher keeps its own `_openId` and
  `_coveredApp` capture with its Hammerspoon guard at `:1008`, exactly as the brief asks for
  phase two.
* Show reset ordering is preserved. `openId` bump, covered app with the self guard,
  `leavePage`, then the show, in that order at `host/launcher/init.lua:1000` through `:1017`.
* The nav registry is unchanged in shape. The stage declares no surface and so opens no
  context, `hintsLib.contextOwners` never names it, and `surfaceAdapters` at
  `root/compose.lua:1207` is still built from context owners alone, so the stage does not join
  the nav list and the launcher still does under the same `member = "_surface"` spec. The
  launcher's context predicates still resolve, `launcherHostingList` at
  `root/compose.lua:566` reads `isHostingList` which is untouched.
* Registration. `registrarLib.describe` at `lib/registrar.lua:228` returns nil when neither
  the manifest nor `registryMeta` has a registry opinion. The stage manifest has none and the
  person's config sets no `cfg.registry` at all, so the stage produces no descriptor and
  `lib/wire.lua:421` cannot report a refusal. The derived open key block at
  `root/compose.lua:1289` needs `eff.key`, `eff.leader`, and a `show` method, and the stage has
  none of the three.
* The stage joins the identity keyed set without colliding. `lib/plugins.lua:141` reports a
  duplicate identity as an error and drops both, and no other manifest in the tree claims
  `stage`.
* Manifest hygiene. Both changed manifests load as pure data, no `hs` and no side effects,
  and `luac -p` is clean on all five changed files. The stage declares no tools, and running
  `dotfiles/hammerspoon/dependencies-collect` regenerates a byte identical `DEPENDENCIES`,
  so the reconciler view is unchanged. The `.stow-local-ignore` at the hammerspoon package
  root lists only repo level files, and `~/.hammerspoon/Spoons/Olm.spoon` is a symlink to the
  whole spoon directory, so `host/stage` needs no restow to be seen live.
* The highlight poll is not a regression. `Stage` installs `onHighlight` unconditionally at
  `host/stage/init.lua:118`, which looked like it would start the atom's poll loop where the
  launcher never ran one, but `ActionPanel:decorate` at `host/actionpanel/init.lua:463`
  already assigns `config.onHighlight` unconditionally on every instance, so
  `_startPollLoop`'s guard at `lib/chooser/providers/native.lua:513` has been passing for the
  launcher all along. Same for the key watcher, which decorate arms through `intercept` and
  `back`.
* Double show. Hyper space on an already presented launcher runs `show`, which bumps
  `openId`, keeps the previous covered app because the frontmost app is Hammerspoon and the
  guard catches it, leaves any page, and reaches `present`, which finds the presentation
  already on top so does not push, and swaps in place. No stack growth, highlight back to row
  one through `refresh(true)`. Correct.
* The launcher hotkey while another plugin's own chooser is up still opens a second window,
  since the stage's instance is not that plugin's. That is unchanged from before this commit
  and is what BRIEF-STAGE.md says phase two should leave alone.
* Instance count. The launcher used to call `Chooser.new` on both of its two configure calls,
  so one decorated orphan sat in `ActionPanel._instances` forever. The launcher now builds
  none and the stage builds one, so that orphan is gone. Nothing asserts on
  `decoratedCount`, so no check breaks.
* `Stage:selectedItem` and `Stage:query` both use the `and or` idiom, and neither can return
  the wrong value for it, since an item is a table or nil and an empty string is truthy in
  Lua.

## What I did not check

* No live run of any kind, so nothing here is confirmed by a key press. Findings 2 and 3 both
  turn on a timing question that only a probe can answer.
* `Launcher:canPeekSelected` and `Launcher:selectedKind` have no readers anywhere in the
  tree, which is a pre existing condition rather than anything this change caused, so their
  migration onto `stage:selectedItem` is correct by reading and unverifiable by use.
* `Launcher:start` is never called by anything, since the launcher manifest declares no
  `wiring` block and `lib/wire.lua` only calls `configure` for a plugin that has one. Pre
  existing, unrelated, but it means the persisted recency order is loaded by nothing, which is
  worth a separate look.

---

# Second pass, rework verdict, 2026-08-27

Commit ac44d89 on feat/chooser-stage, read as `git show ac44d89` plus the surrounding code
each fix touches. Focused verification of the ten findings above, not a full re review. No
Hammerspoon was run, no reload was issued, no devlock was taken.

Nine of the ten are closed or correctly recorded. One is partially closed. The fix for
findings 1 and 9 introduces a visible regression in five other lists, which is the headline
of this pass and is finding 11 below.

## Per finding

**1. stage.placeholder owed. Fixed, and it broke five other tools doing it.**
`root/compose.lua:109` now carries `placeholder = "Search"` in `SHIPPED_POLICY`, so
`policy.placeholder` is a string, `stageOpts.placeholder` at `root/compose.lua:1070` is
non nil, and `servicesLib.owed` at `root/compose.lua:1675` no longer names it. The error line
is gone. See finding 11 for what else that value now reaches.

**2. Launcher isShowing and the stuck predicate. Fixed.**
`host/launcher/init.lua:1049` through `:1050` now requires `self._stage:isShowing()` as well
as the presentation name. Traced the whole interval by hand, see the residual risk section
below. The predicate cannot stay stuck on, and the self healing claim holds.

**3. The seeded query refresh guard. Fixed.**
`Stage:refresh(resetRow, force)` at `host/stage/init.lua:286` and the one caller at
`host/launcher/init.lua:1026` passing `refresh(true, true)`. Checked that no other caller
passes force, so `Launcher:refresh` at `:894` still no ops while the list is closed, which is
what the late arriving query sources want. Checked that a forced refresh on a torn down atom
is safe, `Chooser:refresh` at `lib/chooser/providers/native.lua:787` guards only on
`self.chooser`, `_build` reads `self.theme` which a prior show already selected, and the worst
case is rows built for a window nobody can see.

**4. present pushing onto a stale stack. Partially fixed.**
`host/stage/init.lua:234` replaces the stack wholesale when the window is hidden, so the
stale stack half is closed. The hotkey half is not, and cannot be from inside `present`
alone. When the window is already up, `host/stage/init.lua:227` through `:230` still pushes,
so a tool opened by its own hotkey over a live presentation becomes a level of that
presentation rather than the bottom of a fresh stack, which is what BRIEF-STAGE.md decision 6
says should happen. That is not a builder error. `present` cannot tell a hotkey open from a
drill in, and the brief's api gives it no way to be told. It needs an api decision in phase
three, a flag on present or a second verb, and it is unreachable until a second presentation
exists.

**5. World capture once per stack. Fixed.**
`host/stage/init.lua:234` and `:235` are now the same branch, so a fresh stack and a world
capture are the same event by construction and cannot drift.

**6. Configure idempotence. Fixed.**
`host/stage/init.lua:89` through `:92`. Attacked it two ways. The guard keys on
`self._instance` rather than on a configured flag, so a first call that returned early at
`:105` for want of a chooser factory still lets a later call build one, which is the right
answer rather than a hole. And the guard returns before reading `opts`, so a second call's
values are ignored rather than half applied, which is what idempotent has to mean here.

**7. The bare literal panel lookup. Fixed in form, with a comment that overstates it.**
`root/compose.lua:1065` and `:1066` now resolve through `plan.identity` and the seam is
marked. Both real complaints are answered. But the comment's stated reason is not true.
`lib/resolve.lua:118` builds `out.identity[name] = m.name or name` over `live`, which is
keyed by identity already, since `lib/plugins.lua:140` keys `found` by `manifest.name or
entry`. So `plan.identity` is an identity to identity map for every plugin in the tree, and
`plan.identity.launcher` can only answer for a manifest already keyed `launcher`, in which
case `perPluginData.launcher` was already correct. If the launcher ever declared a name, this
lookup would answer nil, fall back through `or "launcher"`, and miss exactly as the old line
did. The indirection is decorative here, unlike `modules[plan.identity.launcher]` elsewhere
in the file where `modules` really is keyed by identity and the translation really happens.
Harmless, but the comment claims a protection that is not there.

**8. Stale manifest sentences. Fixed, and the residue is now honest.**
`host/launcher/manifest.lua:227` through `:234` and `:235` through `:245` both describe what
is actually there. On the coordinator's specific question, no, the delivery did not move. The
launcher module still receives `opts.shortcutPanel` on its ordinary configure call, through
`lib/services.lua:273` through `:275` into `perPluginData`, into `wireData`, applied at
`lib/wire.lua:209`, and `Launcher:configure` never reads it. What changed is that the manifest
now says so out loud at `:242` through `:245`, which is what I actually asked for.

Worth naming the option not taken, since it closes this and finding 7's residue together.
Dropping `panelAs` entirely would make `lib/services.lua:277` through `:280` write
`onPositioned`, `onActivity`, and `onClose` flat onto `wireData.launcher`, the composition
root would read those three field names instead of `.shortcutPanel`, and the hardcoded
knowledge of one plugin's own nesting choice would leave `root/compose.lua` altogether. The
only thing `panelAs` buys now is a nested table nobody reads, since the plugin that once read
it no longer does. Not a defect, a smaller shape available for free.

**9. Root sourced words the fan out does not publish. Partially fixed, and the precedent is genuine.**
I checked the ActionPanel precedent rather than taking it on trust.
`host/actionpanel/manifest.lua:31`, `:33`, and `:35` declare `kindOf`, `rowsFor`, and `run` as
`source = "root"`, `policy = "required"`. `rootValues` at `root/compose.lua:661` through
`:718` publishes eleven words and none of those three. They are built by hand at
`root/compose.lua:1023` and handed over as one named entry at `root/compose.lua:1101`, the
identical door `stage = stageOpts` at `:1102` uses. So the precedent is real and exactly
parallel, not a rationalized version of the shortcut.

More to the point, the mechanism the contract actually cares about works through both doors.
`servicesLib.owed` at `lib/services.lua:180` reads the merged per plugin table, not the fan
out, so a root sourced declaration delivered by hand is checked exactly as one delivered by
name. What is wrong is the document. PLUGIN-CONTRACT.md's checklist sentence, "a
`source = "root"` entry names a field the composition root actually publishes through the fan
out, never a word this plugin invented for itself", is now false for two host manifests and
was already false for one.

So this is contract compliant in behaviour and not in letter, and the builder documented the
deviation in the two files that deviate rather than in the one file that states the rule.
That is the same two places that must agree shape this repository's own dependency layer
exists to prevent. The one line fix is to amend PLUGIN-CONTRACT.md to describe two delivery
channels for `source = "root"`, the field name fan out for shared vocabulary and the root's
own per plugin table for a value only one host can use, with `owed` covering both. Out of
scope for phase two, in scope for whoever closes the build out.

**10. One word, two questions. Not fixed, deliberately recorded, and that is the right call.**
`host/stage/init.lua:145` through `:160` is a warning comment, not a fix. BRIEF-STAGE.md
forbids migrating a plugin in this phase, so a real fix would be out of scope. I checked the
warning is accurate rather than merely present. It correctly identifies that
`surfaceAdapterFor` at `root/compose.lua:1212` through `:1216` looks up the declared surface
first, so a presenting plugin's adapter finds the shared `isShowing` and never reaches its own
module's, and it correctly names `lib/nav.lua:51`'s first answering wins rule as the failure
mode. The prescription it gives, that the next plugin should answer about its own presentation
the way `Launcher:isShowing` does, is the right one.

## The residual risk, followed through the code

The builder disclosed an interval where `hs.chooser:isVisible()` may read true after
`Chooser:_teardown` at `lib/chooser/providers/native.lua:245` has already run, and claimed it
self heals on the next hidden present. Traced it step by step.

Inside the interval, `active` is false and every watcher is stopped, but `isVisible` still
reads true. `Launcher:isShowing` answers false, because `_onClose` at
`host/stage/init.lua:402` through `:407` already emptied the stack, so
`self._stage:current()` is nil and the name half of `host/launcher/init.lua:1050` fails. The
predicate is correct throughout, which is the whole of finding 2 and it is genuinely closed.

If a `present` lands inside the interval, `wasShowing` at `host/stage/init.lua:225` reads
true, so it takes the swap branch, pushes onto the empty stack, sets the query, refreshes,
and never calls `Chooser:show`, so `active` is never set back to true and no watcher is
rearmed. The window then finishes dismissing.

The self healing claim holds, confirmed by code reading. Once `isVisible` goes false, the very
next present takes the hidden branch, and that branch overwrites the stack wholesale at
`host/stage/init.lua:234` rather than appending, so no residue survives, then captures the
world and calls `show`, which sets `active` and rearms every watcher at
`lib/chooser/providers/native.lua:428` through `:431`. One press recovers it completely.

What a person would see, for the live test to watch for. The open they asked for simply does
not happen. No window appears, no error, nothing in the console. Any seeded query is written
into a field that is already gone. Nothing is stuck, no key is misrouted, and the next press
of the launcher key opens a clean launcher. Two ways to reach it. Choosing the Aliases row, or
any scope row that hands the list back through `Launcher:show(query)` at
`root/compose.lua:1464`, which fires 0.1 seconds after the completion that tore the window
down and so is far outside any plausible dismissal window. Or a second launcher key press
within a few milliseconds of the first one closing the list. So the symptom to look for is a
row that occasionally does nothing at all, recovering on the next press, and I would expect
the live test not to see it.

The cheap hardening is unavailable in this phase. `present` would need to ask the atom whether
it is still armed, and the atom exposes no such question, and BRIEF-STAGE.md forbids touching
`lib/chooser`. Deferring it is correct and the disclosure is honest.

## New findings from this pass

### 11. Shipping a default placeholder silently rewrote five other tools' placeholders

**Severity** high for a phase whose acceptance is "the launcher behaves identically under a
hand on the keyboard". Visible on the first keystroke of the live test.
**Verdict** confirmed by code reading.

`root/compose.lua:109` adds `placeholder = "Search"` to `SHIPPED_POLICY`. That value does not
stop at the stage. It flows into `ambientServices.placeholder` at `root/compose.lua:1116`, and
`lib/wire.lua:36` grants `placeholder` ambiently to every plugin that declares a surface. Five
consumers read that grant with a fallback, and every one of them had been falling back all
along precisely because the grant answered nil.

* `host/launcher/init.lua:147`, "Search apps and commands" becomes "Search". The launcher also
  takes it a second way, explicitly, at `root/compose.lua:1574`.
* `plugins/processes/chooser.lua:547`, "Search project, port, runtime" becomes "Search".
* `plugins/emoji/providers/hammerspoon.lua:327`, "Search by name or keyword" becomes "Search".
* `plugins/textcase/init.lua:147`, "Convert selected text" becomes "Search". This is the worst
  of the five, since that list is not a search at all and the new word describes nothing it
  does.
* `plugins/filesearch/chooser.lua:552` reads `cfg.placeholder` with no fallback, so its empty
  field gains "Search" where it had nothing.

All four of the other manifests declare a surface, checked, so all four earn the grant, and
the two that configure a submodule get it through the same opts table, since `lib/wire.lua:345`
builds wiring step options through the same `optionsFor`.

The commit message asserts the opposite, "every one of the thirteen original consumers passed
its own literal placeholder and never fell back to this one". They pass a literal as a
fallback, not as an argument, and the fallback is exactly what a shipped value displaces.

The irony is that the stage itself never displays the value it was added for.
`Stage:present` at `host/stage/init.lua:226` sets the presentation's own placeholder before
`show` is ever called at `:236`, so the construction time placeholder at `:118` is never on
screen for a single frame. So the only observable effect of this change is the regression.

I own part of this. My own finding 1 named adding it to `SHIPPED_POLICY` as "the better one"
of the two fixes, and I asserted that without checking the ambient blast radius. The other
option I gave, dropping the `placeholder` declaration from `host/stage/manifest.lua:34` since
the atom's own `config.placeholder or ""` at `lib/chooser/providers/native.lua:1063` is
already the answer, has zero blast radius and is the one to take.

If the shipped value is kept for its own sake, which is defensible since the ambient grant
answering nil was a real gap, then it is a separate change with its own decision about what
four other tools' fields should say, and it does not belong inside a phase whose acceptance
promises nothing else changed.

### 12. A stack deeper than one loses onClose for every level but the top

**Severity** low, forward looking, unreachable in phase two.
**Verdict** confirmed by code reading.

`Stage:_onClose` at `host/stage/init.lua:402` through `:407` reads only `_current()` and
calls only that presentation's `onClose`, then empties the stack. Every level below it is
discarded without being told. The same now happens at `host/stage/init.lua:234`, where a
hidden present replaces a whole stack wholesale, correctly for finding 4 but silently for
anything below the top that declared an `onClose`.

BRIEF-STAGE.md's contract says `onClose` is "told when the stage hides entirely", which reads
as every presentation on the stack rather than the top one. At depth one the two readings
agree, so nothing is wrong today. The first presentation that declares an `onClose` and can be
drilled into from another will find out the hard way.

## Soundness spot checks re run on what the second commit touched

* `luac -p` clean on all five touched files, run in the worktree.
* `dotfiles/hammerspoon/dependencies-collect` regenerates a byte identical `DEPENDENCIES`,
  `git status` stays clean after running it.
* `src/check-dependencies.sh` passes, zero warnings, all ten sections green, run in the
  worktree.
* `present`'s ordering is correct in both branches. The stack is written at
  `host/stage/init.lua:234` before `show` at `:236`, so `Chooser:show`'s own first
  `_build("")` at `lib/chooser/providers/native.lua:754` reaches the new presentation's rows
  rather than the previous one's, and the push at `:229` happens before `refresh(true)` at
  `:232` for the same reason. Getting either backwards would have built one presentation's
  rows for another, and neither is backwards.
* `wasShowing` is captured at `:225` before `setPlaceholder` at `:226`, and setting a
  placeholder cannot change visibility, so the single question the branch turns on is asked
  once and cannot be answered twice differently.
* The intercept and back chain is untouched by this commit and still correct, decorator
  outermost, presentation next, stack pop last, `pop` answering false at depth one.
* `Stage:hide` and `_onClose` still both clear the stack, so the double clear is harmless and
  the two paths still agree.
* `Launcher:refresh` at `host/launcher/init.lua:894` still calls `self._stage:refresh()` with
  no arguments, so `force` is nil and the ordinary guard applies. Checked every call site of
  `Stage:refresh` in the tree, there are exactly two.

---

# Third pass, final verdict, 2026-08-27

Commit eaaba33 on feat/chooser-stage, judged on its own and against everything already
verified. No Hammerspoon was run, no reload was issued, no devlock was taken.

Both questions answer clean. One new low finding, documentation only. Findings 11 and 7 and
8 are now fully closed, and nothing the sequence of three commits did is left inconsistent.

## Question one, the placeholder revert

**Verified, and the revert is complete rather than merely apparent.**

The blast radius is gone at the source. `SHIPPED_POLICY` no longer carries the key, and the
cumulative diff of all three commits against main touches that table not at all, the only
lines changed anywhere near it being the four host modules becoming five in the header
comments. So `policy.placeholder` is nil again, exactly as on main.

The five consumer fallbacks are reachable exactly as on main, traced individually rather than
assumed. `ambientServices.placeholder` at `root/compose.lua:1111` reads `policy.placeholder`,
which is nil, so `lib/wire.lua:92`'s grant writes nothing, so every one of the five reaches
its own literal. `host/launcher/init.lua:147` back to "Search apps and commands", and its
second delivery at `root/compose.lua:1569` is the same nil.
`plugins/processes/chooser.lua:547` back to "Search project, port, runtime".
`plugins/emoji/providers/hammerspoon.lua:327` back to "Search by name or keyword".
`plugins/textcase/init.lua:147` back to "Convert selected text".
`plugins/filesearch/chooser.lua:552` back to no placeholder, so
`lib/chooser/providers/native.lua:1063`'s own `config.placeholder or ""` answers, which is
what it did before.

Nothing is owed at load. `host/stage/manifest.lua` now declares five root sourced needs,
counted, `chooser` at `:43`, `theme` at `:46`, `onPositioned` at `:54`, `onActivity` at `:56`,
`onClose` at `:58`. `stageOpts` at `root/compose.lua:1063` through `:1069` supplies all five
and no sixth. `servicesLib.owed` at `lib/services.lua:180` iterates the manifest's own
declarations, so a need that no longer exists cannot be reported missing, and the removed
`placeholder` line is gone from the manifest rather than merely gone from the delivery. Zero
lines.

**No path to a show that skips present.** I looked for one rather than reasoning about it.
`_instance:show()` appears exactly once in the whole tree, `host/stage/init.lua:242`, inside
the hidden branch of `present`. `present` itself has exactly one caller,
`host/launcher/init.lua:1023`, inside `Launcher:show`. And `setPlaceholder(p.placeholder or "")`
at `host/stage/init.lua:232` sits above the branch, not inside either arm, so it is executed
on the swap path and the show path alike and cannot be skipped by taking one arm.

The nav surface cannot open anything. Its six members at `host/stage/init.lua:167` through `:177` are `isShowing`, `selectNext`, `selectPrev`, `insertSelected`, `hide`, and
`peekPreview`, none of which reaches `show`. Nor can the launcher's own methods.
`seedQuery`, `enterPage`, `leavePage`, `currentQuery`, `peekSelected`, `canPeekSelected`, and
`selectedKind` all route to `setQuery`, `setPlaceholder`, `query`, or `selectedItem`, and
`Launcher:refresh` routes to `Stage:refresh`, which calls `Chooser:refresh` and never
`Chooser:show`. `Stage:pop` at `:254` through `:267` sets a placeholder, a query, and a
refresh, and never shows. `Stage:hide` hides. Nothing in `host/actionpanel/init.lua` calls
`show` on an instance either, `_leave` uses `setQuery` and `selectRow` and `toggle` uses
`setQuery` and `refresh`.

And the atom does not re write the field on a show. `Chooser:show` at
`lib/chooser/providers/native.lua:745` through `:768` re selects the theme, clears the query,
builds, resets the row, and positions, and touches `placeholderText` nowhere.
`c:placeholderText(config.placeholder or "")` is written once, at
`lib/chooser/providers/native.lua:1063`, inside `native.new`. So
`CONSTRUCTION_PLACEHOLDER` at `host/stage/init.lua:54` is written at construction, overwritten
by the first present before the first show, and can never render. The claim holds literally.

## Question two, the panelAs drop

**Verified in `lib/services.lua` rather than taken on trust, and the three callbacks still
arrive.**

`obj.perPlugin` at `lib/services.lua:268` through `:284` is the whole answer. It builds the
panel for a plugin whose surface produced a context, then reads `manifest.surface.panelAs` at
`:273`, and with no `panelAs` takes the else arm at `:277` through `:280`, writing
`onPositioned`, `onActivity`, and `onClose` as three separate fields onto that plugin's own
slot. So `perPluginData["launcher"]` now carries the three flat, which is exactly the shape
`root/compose.lua:1063` reads through `launcherPanel.onPositioned` and its two siblings. The
literal word `shortcutPanel` appears in `root/compose.lua` only inside a comment at `:1060`
saying it is gone, and nowhere as a lookup.

The context is still built, which is the one thing that could have silently emptied the panel.
`panelAs` appears nowhere in `lib/surface.lua` or `lib/resolve.lua`, so it is invisible to
validation and to the plan, and the launcher's surface still declares `context`, `member`,
`primary`, `close`, and `extra`, so `S.validate` at `lib/surface.lua:104` still passes and
`plan.contexts["launcher"]` still exists, which is what `lib/services.lua:270` gates the panel
on. The three callbacks are therefore still built by `lib/hints.lua:396` through `:401`, still
reach `stageOpts`, still reach `Chooser.new` at `host/stage/init.lua:138` through `:140`, and
still fire, `onPositioned` from `lib/chooser/providers/native.lua:422` and `:352`,
`onActivity` from `:468`, and `onClose` through `Stage:_onClose`.

**Nothing else in the tree read the nested shape for the launcher.** Grepped
`shortcutPanel` across `host`, `plugins`, `lib`, and `root`. Every remaining reader is
somebody else's, `plugins/emoji/manifest.lua:79` with
`plugins/emoji/providers/hammerspoon.lua:328`, and `plugins/textcase/manifest.lua:56` with
`plugins/textcase/init.lua:150`, both of which still declare their own `panelAs` and are
untouched. The rest are the generic mechanism, `lib/services.lua:271`, `lib/wire.lua:42`, and
`lib/hints.lua:385`, none of which names a plugin.

One thing worth stating plainly since it changed and nobody asked about it. The launcher's own
`configure` now receives three flat fields where it used to receive one nested table, and
still ignores all of them. Checked for a name collision, `Launcher:configure` reads no field
called `onPositioned`, `onActivity`, or `onClose`, its `plan.effective` block declares none,
and it passes `opts` wholesale to nothing. Checked that this does not breach
`lib/services.lua:18` through `:25`'s hard rule, which forbids the panel triple in `obj.ambient`
because the flat entitlement would then reach every surfaced plugin. This write is in
`perPlugin`, which is per plugin by construction, so it reaches the launcher alone and the
rule is intact.

## New finding

### 13. Two contract documents now describe a panelAs shape the launcher no longer has

**Severity** low, documentation only, and I recommended the change that caused it.
**Verdict** confirmed by code reading.

`docs/PLUGIN-CONTRACT.md:537` through `:541` says of `panelAs`, "Four plugins read them nested
instead, three under `shortcutPanel` and one under `panel`". It is three now, two under
`shortcutPanel` and one under `panel`.

`docs/CONSUMER-MAP-2026-08-27.md` section 3 lists the launcher first under "Nested under
`shortcutPanel`, three plugins" and cites `host/launcher/manifest.lua:232` for the declaration
and `host/launcher/init.lua:179` and `:208` for the read. All three citations are now dead,
the declaration deleted here and the two reads deleted in the first commit.

BRIEF-STAGE.md's must not do list says "Do not rename anything the consumer map cites". This
is a deletion rather than a rename, it is the correct deletion, and it was made on my own
recommendation in the second pass, so I am not calling it a violation. But the map is the
ground truth phase three will be planned from, and it is now wrong about the launcher in two
places. Whoever opens phase three should correct section 3 and the contract's own count before
using either.

## Cumulative scan across all three commits

Read the whole `git diff main` once more looking for a shape one fix left behind. Every count
claim in the added prose is correct, checked individually rather than skimmed. Five modules
under `host`, listed, `actionpanel`, `hypercheatsheet`, `launcher`, `queryscope`, `stage`. The
presentation contract's nine fields at `host/launcher/init.lua:260`, matching BRIEF-STAGE.md. The
eight member stage api at `host/stage/init.lua:324`, matching the brief. Five needs in the
stage manifest. Nine optional data needs in the launcher manifest. Four load bearing details
in `Launcher:show`. Twelve other consumers still owning their own window, which is the
thirteen `Chooser.new` sites the consumer map counted minus the launcher.

No comment left describing a removed shape. The launcher manifest's `member` and its replaced
`panelAs` paragraph both describe what is there today. The stage manifest and
`root/compose.lua` both explain the placeholder's absence rather than its old presence. The
launcher's own configure comment at `host/launcher/init.lua:212` through `:216` says the panel
triple is one this host "no longer passes anywhere", which is still exactly true, it passes
none and merely receives three it drops. `root/compose.lua:1052` through `:1060` no longer
claims the `plan.identity` indirection protects against a renamed launcher, it now says only
that identity and directory answer the same word here today, which is honest. The deeper fact,
that `lib/resolve.lua:118` makes `plan.identity` an identity to identity map so the lookup
could never translate a directory name in this table at all, is still unsaid, and that is the
last cosmetic residue of finding 7. It costs nothing.

Checks re run by me in the worktree on this commit. `luac -p` clean on all five touched files.
`dotfiles/hammerspoon/dependencies-collect` regenerates a byte identical `DEPENDENCIES`, `git
status` clean afterwards. `src/check-dependencies.sh` passes with zero warnings.

## Where the ten plus three findings stand

Closed. 1, 2, 3, 5, 6, 7, 8, 9 in behaviour, 11.
Partially closed, with the residue a phase three api decision rather than a defect. 4.
Recorded rather than fixed, correctly, since a fix is out of this phase's scope. 10, 12, 13.
Disclosed and traced, self healing confirmed, symptom named for the live test. The interval
where `hs.chooser:isVisible()` may read true after teardown.

Ready for the live test gate. What to watch for is in the second pass's residual risk section,
a launcher open that occasionally does nothing at all and recovers on the next press, and the
ordinary acceptance list in BRIEF-STAGE.md. The console should be clean on load, which is now
worth checking as a real signal rather than as noise.
