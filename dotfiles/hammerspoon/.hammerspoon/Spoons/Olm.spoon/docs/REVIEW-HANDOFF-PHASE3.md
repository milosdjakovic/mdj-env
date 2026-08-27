# Adversarial review, chooser stage phase three, the handoff swap

Commit d902e55 on feat/chooser-stage, diffed against baeaaab in the worktree at
`/Users/milos.djakovic/Development/personal/.worktrees/chooser-stage`. Read whole, the diff
plus `host/stage/init.lua`, `host/launcher/init.lua`, `plugins/vpn/init.lua`,
`plugins/vpn/manifest.lua`, `lib/registrar.lua`, `lib/registry.lua`, `lib/hints.lua`,
`lib/nav.lua`, `lib/panel.lua`, `lib/resolve.lua`, `lib/wire.lua`,
`lib/chooser/providers/native.lua`, `host/actionpanel/init.lua`, and the relevant sequence of
`root/compose.lua`. Contract read from `docs/BRIEF-HANDOFF.md` in the main checkout, since
the worktree does not carry it. Nothing was edited, no Hammerspoon was run, no reload was
issued, no devlock was taken.

Ten findings. Two high, three medium, five low. The two high ones are both on the exact path
this phase exists to demonstrate, and neither is visible from any declaration.

---

## 1. Every navigation key is dead while VPN is presented

**Severity** high. It breaks the phase's own acceptance list in three places.
**Verdict** confirmed by code reading.

The surface adapters loop asks the registry a question the registry cannot answer yet.

`root/compose.lua:1328`

    if stageModule and wiredRegistry.presentationFor and wiredRegistry.presentationFor(identity) then
      surfaceAdapters[#surfaceAdapters + 1] = stageModule:surfaceFor(identity)
    else
      surfaceAdapters[#surfaceAdapters + 1] = surfaceAdapterFor(module, spec)
    end

That loop runs at `root/compose.lua:1294` through `:1334`. `w.register` runs at
`root/compose.lua:1364`, seventy lines later. `instance.presentationFor` at
`lib/registry.lua:591` through `:594` reads

    local entry = flatIndex[name]
    if not entry or not activeTools[entry.tool] then return nil end

`flatIndex` is filled by `register` and `activeTools` by `activate`, and both of those happen
inside `w.register`. So at loop time nothing has registered and nothing is active, and
`presentationFor("vpn")` answers nil for VPN exactly as it does for a plugin that never
declared a presentation. The else branch runs.

The else branch then finds nothing. `spec` at `root/compose.lua:1317` is
`(manifest.surface or {}).member or (manifest.registry or {}).surface`. VPN's surface block
declares no `member`, and this commit deleted `registry.surface = true` from
`plugins/vpn/manifest.lua`, so `spec` is nil, `surfaceOf(module, nil)` at
`root/compose.lua:858` answers the module itself, and the module no longer carries
`isShowing`, `selectNext`, `selectPrev`, `insertSelected`, or `hide`, all five deleted at
`plugins/vpn/init.lua:382` through `:387`. The lazy proxy's `__index` at
`root/compose.lua:1275` finds no function on the holder and none on the module root, so it
answers nil for every one of them.

The failure is silent rather than loud. `lib/nav.lua:53` guards with
`type(surface.isShowing) == "function"`, so VPN's adapter never raises, it simply never wins.
And no other adapter wins either, since the launcher's own is now scoped, answering
`current() == "launcher"`, which is false while VPN is up. So `activeSurface` returns nil and
`routeNav` at `lib/nav.lua:65` hides the hint panel and does nothing else.

The concrete sequence. Hyper space, type vpn, Return, the list swaps to VPN correctly.
Now press j. The `vpnOpen` predicate is true, because `isShowingFor` at
`root/compose.lua:899` is a closure evaluated at key press time and by then the registry is
built, so it takes the new presenting branch and answers correctly. The key is therefore
live, the plain Hyper layer is suppressed, and the key reaches nothing. Same for k, for the
close key, for refresh, and for the primary Confirm the manifest binds on i. Opening the
action panel over VPN works, since that path is the one routed through `isShowingFor` rather
than through an adapter, so it lists VPN's verbs, and then every verb it lists is inert for
the same reason, because `_run` at `host/actionpanel/init.lua:358` goes back through
`dispatchTable` into `routeNav`.

So this lands as a key that is bound, gated, listed in the hint bar, and reaches nothing,
which the composition root's own comment at `root/compose.lua:1306` through `:1312` calls out by name as the
defect that whole block exists to prevent.

The asymmetry is what makes it hard to see. The predicate is a closure and works. The adapter
is a value computed once and does not. Two answers to the same question, resolved at two
different times, which is the shape review finding ten warned about in phase two and this
commit set out to close.

Two fixes. Move the loop below `w.register`, which is the smaller change but reorders a block
other things read. Or make the branch lazy the way the rest of that adapter already is, since
`root/compose.lua:1270` states outright that nothing there is cached and a table walk per key
press costs nothing worth protecting, so asking `presentationFor` inside the proxy rather than
outside it matches the file's own rule and needs no reordering at all.

---

## 2. Choosing VPN from the launcher never fetches the location list

**Severity** high. The acceptance list's first sentence is about this exact row.
**Verdict** confirmed by code reading.

The old path ran `registry.run("vpn")`, which is `descriptor.open`, which is `M.show`, and
`M.show` calls `M.prepare` before revealing anything. The new path does not go near `M.show`.
`root/compose.lua:1723` answers a callable that is only

    return function() stageModule:push(presentation) end

and the presentation carries `rows`, `onSelect`, and `placeholder` and nothing else. Nothing
in that chain calls `M.prepare`.

`rows(query)` at `plugins/vpn/init.lua:238` reads the `cache` upvalue and never fetches.
`cache` is written in exactly one place, the `engine.listLocations` callback inside
`M.prepare` at `plugins/vpn/init.lua:375`. `M:start()` at `plugins/vpn/init.lua:439` does not
call `prepare`, it only configures and starts the engine. And `onChange` at
`plugins/vpn/init.lua:393` refreshes `current` and `target` and deliberately not `cache`.

So on a fresh Hammerspoon load, choosing the VPN row in the launcher swaps the list to a
single Connect row and no cities at all. It stays that way until something else calls
`prepare`, which today means either VPN's own leader key or typing its scope alias, both of
which do call it, `plugins/vpn/init.lua:301` and `:341`. Once one of those has run, the cache
is warm for the session and the row looks right, which is exactly the shape of bug that
survives a hand test done in the wrong order.

Even warm it is a regression against what the file promises. `plugins/vpn/init.lua:29` still
says the location list "is fetched on each open so a relay update is reflected, and the list
is refreshed once it lands". That is now true only for the hotkey door and the scope, and
false for the launcher row, which decision two makes the primary door.

The status snapshot is less bad but not clean either. `current` is refreshed by the engine's
own `onChange`, so it tracks while the daemon changes state, but a push does not re read it
the way `prepare` does at `plugins/vpn/init.lua:369`.

Smallest honest fix, inside VPN and nowhere else, is for `rows` to do what `scopeRows`
already does at `plugins/vpn/init.lua:342` and call `M.prepare` when `M.ready()` is false,
handing it the redraw it already has a word for. The larger and probably better answer is a
presentation contract field for "about to be shown", which the contract does not have and
which is out of scope for this phase, so it should be recorded rather than invented here.

---

## 3. Re presenting the top of a deeper stack fires that presentation's own onClose

**Severity** medium, no observable effect today, a trap for the next migration.
**Verdict** confirmed by code reading.

`host/stage/init.lua:289`

    if not (#old == 1 and old[1] == p) then
      closeStack(old)
    end

The dedup only recognises a reopen when the stack is exactly one deep. The sequence that
breaks it. Hyper space opens the launcher, stack is one. Choose the VPN row, push, stack is
launcher then vpn. Now press VPN's own leader key, which reaches `presentTool("vpn")` at
`root/compose.lua:698` and then `Stage:present`. `#old` is two, so `closeStack` runs and
tells `vpn.onClose` first and `launcher.onClose` second, and then `self._stack = { p }`
leaves VPN showing. VPN was told it closed while it is what stays on screen.

Decision six says a present tells "every discarded presentation". VPN is not discarded here,
it is the survivor. The doc comment at `host/stage/init.lua:271` claims the dedup covers "a
reopen of what is already current", which is the right intent and not what the condition
tests.

Nothing observable today, since VPN declares no `onClose` and the launcher declares none
either. It matters the moment a migrated plugin uses `onClose` for what onClose is for,
tearing down a preview, stopping a watcher, releasing a canvas, all of which would be torn
down underneath a list still on screen.

The condition wants to be about identity rather than depth, something like discarding only
the levels that are not p, or simply skipping p itself while walking.

---

## 4. A presentation member naming a function that does not exist registers cleanly and fails in silence

**Severity** medium, structural, no live instance today.
**Verdict** confirmed by code reading.

`lib/registry.lua:379` refuses a whole registration whose presentation has no `rows` or no
`onSelect` function, and its comment calls that "structural rather than partial". It cannot
see the failure that actually matters.

`obj.action` at `lib/registrar.lua:134` returns nil only when the member spec itself is
absent. Given any named member it always returns a closure, without ever checking the member
exists. `callMember` at `lib/registrar.lua:101` then answers nil for a path that does not
resolve, deliberately and quietly, per its own comment at `:98`. So a manifest declaring
`presentation = { rows = { member = "rowz" } }` produces a presentation whose `rows` is a
function, passes `presentationIsWellFormed`, registers, and answers nil on every keystroke.
`Stage:_rows` at `host/stage/init.lua:463` turns that into `{}`, so the tool presents an
empty list forever with nothing anywhere saying why. The same typo on `select` gives a list
where Return does nothing.

Nothing upstream covers it either. `lib/plugins.lua`'s own capability check validates
`needs.siblings` and `needs.lib` against the real modules and knows nothing about
`manifest.presentation`, so this new declaration kind reopens exactly the hole
`docs/AUDIT-2026-08-13.md` records, a manifest naming a member that had been deleted,
resolving to nil with nothing reporting it.

Not reachable for VPN today, all three members exist, checked. It is the contract that is
weak, not this instance.

---

## 5. The world capture invariant from phase two is broken, and the comment asserting it is now false

**Severity** medium, no readers today, a landmine for phase five.
**Verdict** confirmed by code reading.

Phase two's fix for findings two and five made a fresh stack and a world capture the same
branch, so they could not drift. This commit separates them again. `present` at
`host/stage/init.lua:292` builds a fresh stack unconditionally, while `_show` at
`host/stage/init.lua:253` through `:256` captures the world only when the window was hidden. So a present
over a visible window, which decision one newly makes a normal and expected thing, creates a
brand new stack carrying the previous stack's `_openId` and `_coveredApp`.

The comment at `host/stage/init.lua:280` still states the old invariant, "once per stack by
construction rather than once per hidden present, findings two and five, since a fresh stack
and a world capture are the same branch inside `_show` and cannot drift apart". They now can
and do.

No live consequence. `Stage:world` at `host/stage/init.lua:413` still has no readers anywhere
in the tree, checked again this pass. It matters because BRIEF-STAGE.md decision seven says
the stage's capture exists from day one precisely so a later phase deletes the launcher's own
copy rather than inventing one, and the copy that would be deleted is the one that is still
correct.

---

## 6. Two different things are named presentTool in one file

**Severity** low, readability, no runtime conflict.
**Verdict** confirmed by code reading.

`root/compose.lua:283` is `local function presentTool(tool)`, the predicate answering whether
a declared tool is installed on this machine, handed to `resolver.plan` as `present` at
`:451` and `:752`. `root/compose.lua:698` is `presentTool = function(name)` inside
`rootValues`, the stage hotkey door.

No shadowing, since the second is a table constructor key and not a local, so both resolve
correctly and I could not construct a failure. But the file's own header at
`root/compose.lua:12` through `:15` asks that it be read top to bottom, and the same word now means "is
this tool present on this machine" in one half and "present this tool's list" in the other.
The published word is the one a manifest has to declare, so renaming the local is the cheaper
side.

---

## 7. Every push and every pop rebuilds the rows twice

**Severity** low, cost only.
**Verdict** confirmed by code reading.

The commit message says the push path is "no hide, no deferral, one redraw". It is two.
`Stage:push` reaches `_show`, which calls `self._instance:refresh(true)` at
`host/stage/init.lua:253`. It returns true all the way back up to `Chooser:_intercept` at
`lib/chooser/providers/native.lua:489`, which then calls `self:refresh(true)` itself after the
handler returns, by its own documented contract. So the row supplier runs twice and every
surviving row is styled twice per push.

`pop` has the same shape. It refreshes at `host/stage/init.lua:348` and `Chooser:_back` at
`lib/chooser/providers/native.lua:499` through `:508` refreshes again.

Harmless for correctness, since a rebuild is idempotent, and cheap for the launcher. It is
worth naming because VPN's `rows` builds a flag image per city and phase four is going to put
geometry and panes on this same path, where a doubled rebuild stops being free.

---

## 8. push on a hidden window discards a stack without telling anyone, where present tells everyone

**Severity** low, unreachable today.
**Verdict** confirmed by code reading.

`host/stage/init.lua:322` through `:323` degrades a push over a hidden window to a fresh stack by writing
`self._stack = { p }` directly, with no `closeStack` call, while `present` in the identical
situation notifies. Decision six draws no distinction between the two doors for a discarded
level.

Unreachable today, because the only caller of `push` is the callable at
`root/compose.lua:1723`, which runs from inside the atom's intercept and therefore only ever
while the window is up, and because `_onClose` empties the stack on every teardown anyway. It
is an inconsistency between two doors that are otherwise carefully symmetric.

---

## 9. The contract doc contradicts itself on the refusal semantics

**Severity** low, documentation.
**Verdict** confirmed by reading.

`docs/PLUGIN-CONTRACT.md`, in the new presentation section, says

    `rows` and `select` are required. A plugin naming neither, or naming one without the
    other, is not refused outright, `lib/registry.lua`'s own `presentationIsWellFormed`
    refuses the whole registration the same way a malformed `scope` already does

The sentence states a thing and then states its opposite. The code refuses, `lib/registry.lua`
at `:494`. Almost certainly a dropped negation, and it lands on the one semantic the
coordinator asked to have checked.

The same section's `panelAs` paragraph also points at a mechanism that no longer exists,
saying the field "may still need to stay declared if `services.perPlugin` computing it is what
something else, the composition root's own stage wiring today, still reads it for". Phase
two's own third commit removed `panelAs` from the launcher and moved the composition root onto
the flat fields, so nothing reads a nested panel for the stage any more.

---

## 10. Routing by identity breaks the hint bar for any presenting plugin whose context is spelled differently

**Severity** low today, latent.
**Verdict** confirmed by code reading, no current instance.

Interpretation three routes by identity, and three of the four consumers agree with it.
`isShowingFor` at `root/compose.lua:902` resolves `ownerIdentity` and compares against
`stage:current()`, which is `presentation.name`, which the registrar stamps as the identity at
`lib/registrar.lua:364`. The adapters loop uses identity. `surfaceFor` compares against
identity. All three are consistent.

The hint bar is the fourth and is keyed differently. `root/compose.lua:1130` hands
`stageModule:current()` straight to `hintsLib.shortcutPanelFor`, whose content closure calls
`obj.footerFor(name, plan, deps)` at `lib/hints.lua:405`, and `footerFor` at
`lib/hints.lua:161` looks the name up in `plan.contexts`, which `lib/resolve.lua:307` keys by
`effectiveDecl.context or out.identity[name] or name`.

So a plugin whose surface declares a `context` different from its identity would present
correctly, route its keys correctly, gate its predicate correctly, and show an empty hint bar,
since `plan.contexts[identity]` would be nil and `footerFor` returns an empty list at
`lib/hints.lua:162` in silence.

I checked all twelve. Every plugin declaring a context today spells it exactly as its
identity, including the eight whose directory differs, so nothing is wrong now. The path to it
does not need a manifest edit though, since `lib/resolve.lua:295` merges a person's own
`surface` fragment over the declaration, so a user renaming a context in their own config
reaches it.

---

## What I checked and found sound

* **A click on a presenting row does the right thing, and the premise it might not is wrong.**
  `Chooser:_startClickWatcher` at `lib/chooser/providers/native.lua:622` does not hand a click
  inside the chooser frame straight to the widget. It reads the row under the pointer through
  the accessibility tree, `_rowAtPoint` at `:592`, asks `self:_intercept(choice._item)`, and
  when that answers true it swallows both the press and the release, `:636` through `:640`. So
  a click on the VPN row runs the identical chain Return runs and pushes, with the window
  staying up. The atom's own comment at `:490` states this is the point, that Return, the
  insert key, and a click all agree by asking in one place. What the consumer map records at
  section 8.4 is the opposite case, BrowserTabs and DisplayProfiles refusing the hook and
  running private Return swallowing eventtaps, which by construction never see a click, which
  is why those two carry a zero timer re show for the click path. That does not apply here.
  The one degradation worth naming is that `_rowAtPoint` can answer nil if the accessibility
  read fails, in which case the click falls through, the widget completes, `_completion` fires
  VPN's row into the launcher's own `onSelect`, and `_runItem` takes the unmigrated special
  branch, so VPN opens through `M.show` and `present` after the ordinary 0.1 second wait, with
  a close and a reopen and no backspace path home. That is the old behaviour rather than a
  dead key, which is the right way to fail.
* **The deferral split preserves all seven kinds.** Every branch of `_runItem`,
  `host/launcher/init.lua:920` through `:969`, is wrapped in the same `hs.timer.doAfter(0.1,
  ...)` the old outer wrapper used, so app, window, capture, settingsPane, calc, scope, and an
  unmigrated special all still close and then wait exactly as before. Total delay is unchanged,
  since `onSelect` now calls `_runItem` synchronously and the branch schedules. Checked
  specifically that a non presenting special still closes and defers, `:936` through `:943`,
  and that a scope row still defers, `:967`.
* **The run timer cannot double fire or leak.** Exactly one branch executes per `_runItem`
  call, so only one assignment to `self._runTimer` happens per call, and a presenting row never
  reaches the function at all, so the synchronous push path never writes the field. The
  overwrite hazard is unchanged from before this commit, since choosing a row that reaches
  `onSelect` still closes the window.
* **Backspace is correct at both depths.** `Stage:_back` at `host/stage/init.lua:486` asks the
  presentation first and pops second, VPN declares no `back`, so a push then backspace pops
  back to the launcher with the launcher's placeholder, an empty query, and a rebuild,
  `host/stage/init.lua:345` through `:350`. VPN opened by its own hotkey sits on a stack of one
  and its `pop` answers false, leaving backspace an ordinary press, decision five.
* **onClose widening is right in the three cases that are reachable.** `closeStack` walks top
  down, `host/stage/init.lua:239`. `_onClose` tells the whole stack, `hide` tells the whole
  stack, `pop` tells only the one leaving, and `push` tells nobody. The double `closeStack` in
  `hide` is safe for the reason its own comment gives, checked, since `instance:hide()` fires
  the atom's teardown synchronously and `_onClose` empties the stack before `hide`'s own call
  runs, and when the window was not showing the teardown returns early at
  `lib/chooser/providers/native.lua:245` through `:247` so `hide`'s call is the one that notifies.
* **VPN's select still fires and cannot act on the wrong app.** Choosing a city completes
  through the widget, since VPN declares no intercept, so `onSelect` runs before teardown at
  `lib/chooser/providers/native.lua:735`, and `onSelect` at `plugins/vpn/init.lua:263` calls
  `engine.setRelay` and `engine.connect`, which shell out to the provider CLI and read no
  focused window and no frontmost app. So nothing in that path depends on focus having
  returned, which is why removing the deferral for it is safe.
* **The async status refresh reaches the right list and only the right list.**
  `redrawPresented` at `root/compose.lua:708` compares `stageModule:current()` against the name
  and calls `stage:refresh()` with no arguments, so the highlight is kept and the call is a no
  op while VPN is not what is showing, `host/stage/init.lua:382` through `:385`.
* **VPN's scope is untouched and still works.** `M.scopeRows` still calls `M.prepare(redraw)`
  when nothing has landed, `plugins/vpn/init.lua:342`, and the manifest's whole `registry.scope`
  block is unchanged. That is also the reason the cache is ever warm, see finding two.
* **VPN's hotkey door resolves.** `registry.open` is still `{ member = "show", call = "dot" }`,
  and `shortcut = "leader"`, so `bindShortcut` still binds the key to `descriptor.open`, which
  is `M.show`, which now reaches `presentTool`. VPN's identity is `vpn`, its directory is
  `vpn`, and the two string literals `M.show` and `onChange` pass to the root words are both
  `"vpn"`, so all three agree.
* **Deleting `registry.surface` does not break registration.** `lib/registry.lua:486` refuses
  only a surface that is present and is not a function, so nil is accepted. The only reader of
  a missing surface is `instance.surfaces` at `:662`, the resolver consumer map surprise 9.10
  already records as unwired.
* **The two new fan out words are published, delivered, and do not collide.** Both sit in
  `rootValues` at `root/compose.lua:698` and `:708`, VPN declares both as `needs.data` source
  root at `plugins/vpn/manifest.lua:38` and `:40`, `servicesLib.fanOut` matches by field name,
  and VPN's `configure` stores the whole opts table as `cfg`. No other manifest in the tree
  declares either word, and neither collides with the existing `redraw`. The name clash with
  the local `presentTool` is finding six and is not a delivery problem.
* **Both closures survive the forward declaration.** `wiredRegistry` and `stageModule` are
  declared at `root/compose.lua:180` and `:181`, assigned at `:1193` and `:851`, and the two
  `rootValues` closures that reach them are only called at key press time. `isShowingFor`
  guards both with `if stageModule and wiredRegistry and wiredRegistry.presentationFor`, so it
  is safe even if something called it early. The `local wiredRegistry` at the old assignment
  site was correctly turned into a plain assignment, so nothing shadows.
* **The orphaned launcher panel costs nothing and cannot reveal.** `services.perPlugin` still
  builds one because the launcher's manifest still declares a surface, and it lands flat on
  `perPluginData.launcher` and reaches the launcher's own opts, which ignore it.
  `CanvasPanel.new` at `lib/panel.lua:410` allocates one table and builds no canvas and no
  timer, and a panel only ever draws from `arm`, which nothing calls for this one.
  `hideSharedOverlay` is `hideHyperLayer` and does not touch either panel. So the claim holds.
* **The dynamic hint panel resolves the right context at the right time.** The name is asked
  through a closure on every reveal, `lib/hints.lua:401` through `:406`, so it answers
  `launcher` at the bottom of the stack, `vpn` after a push, and `launcher` again after a pop,
  and `footerFor` finds a real context for both names today. The fallback in the closure at
  `root/compose.lua:1130` answers the launcher when nothing is current, which is only reachable
  before the first open.
* **The `_page` and placeholder mismatch I went looking for is unreachable.** A push can only
  come from a `special` row, and `_commandRows` at `host/launcher/init.lua:693` returns the
  query sources' rows alone while a page is hosted, and every row a source produces is kind
  `scope`. So `_page` cannot be set at the moment a push happens, and pop cannot restore the
  launcher's placeholder over a page's rows.
* **The intercept chain is correct at every layer for Return.** Atom key watcher at
  `lib/chooser/providers/native.lua:470`, ActionPanel's wrapper falling through at
  `host/actionpanel/init.lua:423`, `Stage:_intercept` asking the current presentation,
  the launcher's own intercept routing through `_replacementFor` and promoting on a true
  answer, `rowIntercept`'s new branch answering a callable, and `push`. Recency still promotes,
  since `recencyKey` answers `special:vpn` for that row and the launcher's intercept promotes
  anything it got a callable for.
* **With the action panel open, the presenting row is answered by the panel and never by the
  stage,** since the wrapped intercept returns before reaching the original. Choosing the Run
  verb over the VPN row reaches `insertSelected`, which asks `_intercept` itself at
  `lib/chooser/providers/native.lua:860` and so still pushes. That path is correct in
  principle and dead in practice today for VPN, because of finding one.
* **Checks re run by me in the worktree.** `luac -p` clean on all eight touched Lua files.
  `dotfiles/hammerspoon/dependencies-collect` regenerates a byte identical `DEPENDENCIES`, git
  status clean afterwards. `src/check-dependencies.sh` passes with zero warnings across all ten
  sections.

## What I did not check

* No live run of any kind. Findings one and two are both confirmed by reading rather than by a
  key press, and both should be trivially visible the moment the gate opens, which is the
  argument for fixing them before it does rather than during.
* The BrowserTabs suite was not run, correctly per the brief, since that plugin is untouched.

---

# Second pass, phase three rework verdict, 2026-08-27

Commit e2d94b6 on feat/chooser-stage, on top of d902e55, judged on its own and against
everything already verified. No Hammerspoon was run, no reload was issued, no devlock was
taken.

Eight of ten fully fixed, two fixed with a residue worth naming. One new finding, medium, and
it sits on the same swap path finding two was about.

## Per finding

**1. Dead navigation while VPN is presented. Fixed.**
`root/compose.lua:1286` moves the presenting question inside the proxy, and I traced j by hand
rather than taking the trace on trust. Pressing j while VPN is current reaches `binding.fn`,
which is `routeNav("selectNext", surfaceAdapters, hideShortcuts)`, which calls
`activeSurface`. That touches `.isShowing` on each adapter, and each touch runs `__index`
fresh. The launcher's adapter asks `presentationFor("launcher")`, gets nil because a host
never registers, falls to the module walk, resolves `_surface`, and answers the scoped closure
`self:current() == "launcher" and self:isShowing()`, which is false while VPN is current,
`host/stage/init.lua:195`. Confirmed exactly as claimed. VPN's adapter asks
`presentationFor("vpn")`, which now answers because `w.register` at `root/compose.lua:1374`
ran long before any key press, and returns `stageModule:surfaceFor("vpn").isShowing`, which is
true. `activeSurface` returns it and the next `__index` hands back `shared.selectNext`. The
whole trace holds.

Probed for costs the eager loop did not have. There is no memoization, by design and stated
as such. Each access calls `presentationFor`, two table lookups at `lib/registry.lua:591`, and
each presenting hit allocates a whole fresh six member table plus one fresh closure inside
`surfaceFor`, `host/stage/init.lua:192`. `activeSurface` walks up to twelve adapters, so a key
press costs up to twelve `presentationFor` calls plus one table allocation per presenting
adapter, and j and k are in `repeatableActions` so this is on a held key path. In absolute
terms it is nothing, one small table per repeat tick. It is worth knowing that `surfaceFor`
allocates rather than returning a cached per name adapter, since phase five multiplies the
presenting adapters by twelve.

Probed the half answering question. A nil `presentationFor` does not leave the adapter half
answering, it leaves it wholly absent and coherently so. If VPN's registration is refused,
finding four's new path, the adapter falls to the module walk, VPN's module carries none of
the five nav methods any more, so every member answers nil and `activeSurface` skips it
entirely, `lib/nav.lua:53`. `isShowingFor` takes the same non presenting branch and also
answers false, so the context never activates and the keys stay on the base layer. Nothing is
half wired. A mid session flip would be the harder case, and it is unreachable, since
`instance.activate` has exactly one caller in the tree, `lib/registrar.lua:588`, reached once
from `w.register`, and nothing ever deactivates.

One small inconsistency the fix introduces. The presenting branch returns the raw closure,
`root/compose.lua:1291`, while the non presenting branch wraps in `pcall` with a dot and colon
fallback. So a raise inside `stage:isShowing()` propagates out of a key handler for a
presenting plugin where it would be swallowed for every other one. Arguably the better
behaviour, worth being deliberate about rather than incidental.

**2. VPN's launcher row opening onto an empty list. Fixed, with a new cost. See finding 11.**
`onPresent` is a real contract addition, declared at `plugins/vpn/manifest.lua:94`, resolved at
`lib/registrar.lua:450`, called from `_announce` at `host/stage/init.lua:304` through `:306` on both doors and
never on pop. VPN's own `onPresent` at `plugins/vpn/init.lua:309` runs `M.prepare`, which
starts the `listLocations` fetch and redraws through `redrawPresented` when it lands, so the
cities now arrive on the launcher row path exactly as they always did on the hotkey path. The
ordering is right, `_announce` runs before `_show`, which mirrors the old `M.show` doing
`prepare` before `chooser:show()`.

On whether pop leaves the launcher stale. It does not. The launcher declares no `onPresent`
and needs none. `pop` rebuilds through `refresh(true)`, `host/stage/init.lua:390`, and the
launcher's row caches are invalidated by `_promote`, which the launcher's own intercept already
ran when the VPN row was taken, so the recency order the rebuild produces is the current one.
`_page` cannot be set at that point, established last pass. Worth recording for phase five that
a presenting plugin popped back TO gets no `onPresent`, so a three deep stack would restore a
middle level without refreshing its async data, which the brief does not cover.

On duplicate fetches. `listLocations` is properly guarded, `plugins/vpn/init.lua:380` returns
early while `fetching` is true and every waiting caller is queued in `pending`, so bouncing in
and out during a fetch spawns one process, not several. Once a fetch has landed there is no
age guard at all, so every entry spawns a fresh `mullvad relay list`. That is the same as the
old per open behaviour and is defensible for a relay list. The two reads above it are not, see
finding 11.

**3. onClose fired on a survivor. Fixed.**
`closeStackExcept` at `host/stage/init.lua:239` decides by identity rather than depth, and
`_freshStack` calls it before replacing the stack, `:275` through `:279`. The sequence that
broke it, launcher, push VPN, then VPN's own leader key, now tells the launcher only. One
forward note. Those `onClose` callbacks run while `self._stack` is still the old table, so a
callback that reached back into the stage would see the pre replacement stack. No presentation
declares `onClose` today, so it is theory, but it is the kind of reentrancy a plugin with a
real teardown will find.

**4. A presentation member naming nothing. Fixed for existence, not for convention.**
`memberResolves` at `lib/registrar.lua:100` walks the identical dotted path `callMember` walks,
so a nested path is covered, checked. Every one of the nine declared fields is checked at
`lib/registrar.lua:406` through `:416`, at register, after every plugin's wiring has run, which
is the right moment. The refusal names the tool, the field, and the member string, which is
enough to act on.

Two shapes it cannot see. A member reassigned after register still resolves at check time and
answers nil later, exotic and inherent to a lazy closure. The one that matters is the calling
convention. `memberSpec` hands back the member and the check discards the `call` kind
entirely, so a manifest naming a plain dot called function without saying `call = "dot"`
passes, and `callMember` then invokes it as `value(owner, query)`, shifting every argument by
one. For VPN's own `rows` that would silently drop the action row rather than fail, since the
module table arrives where the query belongs. That is precisely the defect `callMember`'s own
comment at `lib/registrar.lua:96` warns about, and it is the residue this fix leaves. Checking
it is possible, a dot declaration on a colon method and the reverse are both detectable only by
convention rather than by reflection, so the honest close is a note in the contract rather than
more code.

A refused tool does disappear everywhere, confirmed. `describe` returns nil at
`lib/registrar.lua:438` through `:440`, `wire.register` skips a nil descriptor at `lib/wire.lua:406`, so
nothing lands in `flatIndex`, which means no `run`, no `rowFor` and therefore no launcher row,
no `listing` entry, no scope through `scopeSpec`, no alias, and no `shortcuts` entry and
therefore no key. The plugin is still configured and started, so its engine runs unreachable,
which is what a refused registration has always meant rather than anything new. One gap worth
naming, the refusal is loud in the console through `deps.log` but leaves no entry in
`wire.record.problems`, so `w.report()` still says no problems while a tool has vanished. The
console is the gate here, so it is visible, but the two accounts disagree.

**5. The world capture split. Fixed.**
`_captureCoveredApp` at `host/stage/init.lua:262` keeps the `SELF_BUNDLE` guard intact,
verbatim, checked character by character against the launcher's own at
`host/launcher/init.lua:1008`. `_bumpOpenId` is called from `_freshStack` only, so the id
advances on every fresh stack including a push over a hidden window, `host/stage/init.lua:362` through `:363`,
and does not advance when a push genuinely stacks, which is correct since that is the same
open. The split is coherent, the covered app follows the window and the id follows the stack.

On MenuSearch. It is untouched by any of this, because it keys off the launcher's own pair
through `launcher.coveredApp`, `plugins/menusearch/manifest.lua:26`, not the stage's, and
`Launcher:show` still bumps and captures its own. Across a stack replacement while visible,
hyper space pressed while VPN is up, the launcher bumps its own id and keeps its covered app
because the frontmost app is Hammerspoon and the guard catches it, so MenuSearch invalidates
and re walks for the same app. Correct, slightly wasteful, unchanged by this commit. The
stage's own `world()` still has no readers, so this fix remains defensive until phase five
deletes the launcher's copy.

**6. The name collision. Fixed.** The published word is `stagePresent` at
`root/compose.lua:703`, the unrelated local predicate keeps its own name at
`root/compose.lua:283`, and the manifest and both call sites in VPN follow, checked by grep
that no `presentTool` remains as a published or declared word.

**7. Two rebuilds. Not fixed, correctly, and now honestly described.** The comments at
`root/compose.lua:1725` and in the stage say two rather than one. The behaviour is unchanged
and the reasoning holds, a rebuild is idempotent. It is worth revisiting when phase four puts
geometry on the same path.

**8. push discarding a stack in silence. Fixed.** `host/stage/init.lua:362` routes the hidden
branch through `_freshStack`, so both doors now notify identically.

**9. The contract doc. Fixed.** The negation is restored, "IS refused outright", and the
`panelAs` paragraph is rewritten for the dedicated dynamic stage panel. `onPresent` is
documented in both places the commit claims, `docs/PLUGIN-CONTRACT.md` and
`docs/BRIEF-STAGE.md:85` in the worktree copy.

**10. Identity versus context divergence. Fixed as far as this phase can.**
`lib/registrar.lua:426` through `:431` warns, once, naming both words, and only for a presenting plugin,
which is the right scope since the divergence only hurts one. It does not fix the routing,
which is correct, the hint bar keying by context is not this phase's to change. Worth knowing
the warning fires from `describe`, which `w.register` calls once per plugin, so it is one line
and not a repeat.

## New finding

### 11. onPresent puts two blocking shell calls on the swap path

**Severity** medium, and it lands on the exact sentence the acceptance list measures.
**Verdict** confirmed by code reading, the size of the stall unmeasured.

`M.onPresent` calls `M.prepare`, and `M.prepare` at `plugins/vpn/init.lua:377` through `:378`
does

    current = engine.status()
    target = engine.selectedLocation()

before it ever reaches the async fetch. Both are synchronous. `engine.status` at
`plugins/vpn/engine.lua:41` calls `provider.status`, which is `hs.execute(cli .. " status -j")`
at `plugins/vpn/providers/mullvad.lua:56`, and `selectedLocation` is a second `hs.execute` at
`:78`, its own comment calling it "a fast synchronous read like status". Only `listLocations`
is properly off the main thread, through `hs.task` at `:153`.

`_announce` runs before `_show`, `host/stage/init.lua:332` and `:367`, and the whole chain from the key
press down is synchronous, the atom's key watcher, the decorator, the stage's intercept, the
launcher's intercept, `rowIntercept`'s callable, `push`, `_announce`. So pressing Return on the
VPN row now blocks the main thread for two CLI spawns with the launcher's list still frozen on
screen, and only then swaps.

Total work is not new. The old path paid the same two reads inside `registry.run` after the
0.1 second deferral. What is new is where they are paid. Before, the window had already closed,
so the cost read as part of opening. Now it reads as the keystroke hanging. The phase's own
acceptance says the row "swaps the list in place with no blink and no 0.1 second wait", and two
process spawns are very plausibly slower than the wait that was removed.

Neither read is guarded or cached, unlike `listLocations`, so every entry pays both, and the
stage makes bouncing between the launcher and VPN cheap enough to do repeatedly.

Three ways out, all inside VPN. Read the status asynchronously the way the relay list already
is. Or skip both reads in `onPresent` when the snapshot is fresh, since the engine's own
`onChange` already keeps `current` current while the daemon changes state. Or, weakest, move
`_announce` after `_show` so the swap paints before the stall, which does not remove it.

## Soundness spot checks re run on what this commit touched

* The launcher's scoped adapter answers false while VPN is current, traced through
  `surfaceOf`, the `_surface` field, and the `pcall` wrapper, and `Launcher:isShowing` reaches
  the same one closure so the predicate and the routing cannot drift.
* `_freshStack` walks the old stack before replacing it, and `closeStackExcept` skips the
  survivor wherever it sits, so both the reopen at depth one and at depth two behave.
* `pop` still tells only the one leaving and never calls `onPresent`,
  `host/stage/init.lua:382` through `:385`.
* `deps.log` is now supplied, `root/compose.lua:1201`, and `logFn` maps `"e"` and `"w"` onto
  the real logger, so both new registrar lines actually print.
* VPN loses no verb to the six member `surfaceFor` set. Its context binds j, k, the action
  panel chord, close, and the primary `insertSelected`, and `surfaceFor` answers `selectNext`,
  `selectPrev`, `hide`, and `insertSelected`, with `openActionPanel` routed by the root's own
  exception rather than by any surface. Worth carrying into phase five, since the presenting
  branch shadows the plugin module entirely, and eight of the unmigrated tools answer more
  verbs than these six, FileSearch fourteen more by the consumer map's own count.
* `luac -p` clean on all five touched Lua files. `dependencies-collect` regenerates a byte
  identical `DEPENDENCIES`, git status clean afterwards. `src/check-dependencies.sh` passes
  with zero warnings.

---

# Third pass, confirmation, 2026-08-27

Commit bfd9a00 on feat/chooser-stage, on top of e2d94b6. Four items confirmed by reading.
One new finding, low, on the failure edge of the new countdown. No Hammerspoon was run.

## Finding 11, the async chain

**Fixed.** The chain reads clean end to end. `M.onPresent` at `plugins/vpn/init.lua:315`
calls `M.prepare`, which at `plugins/vpn/init.lua:391` through `:418` no longer touches
`hs.execute` at all. It sets `fetching`, opens a three way countdown, and fires
`engine.statusAsync`, `engine.selectedLocationAsync`, and `engine.listLocations`, each of
which reaches `hs.task` in `plugins/vpn/providers/mullvad.lua:132`, `:143`, and `:200`. So
the whole path from the keypress through the atom, the decorator, the launcher's intercept,
`rowIntercept`, `push`, and `_announce` returns without a single blocking spawn, and the swap
happens on that same keypress. The stall finding eleven named is gone.

**Re entrancy cannot loop.** `landed` clears `fetching` and swaps `pending` out before it
flushes, `plugins/vpn/init.lua:400` through `:408`, so a callback that calls `prepare` again
queues into a fresh list and starts a fresh round rather than deadlocking on its own guard.
And a redraw cannot start a fetch, since `rows` at `plugins/vpn/init.lua:238` reads `cache`,
`current`, and `target` and calls nothing, so `redrawPresented` to `stage:refresh` to `_rows`
to `rows` terminates.

**onChange cannot re enter the swap path.** It reaches only `cfg.redrawPresented`, which at
`root/compose.lua:714` calls `stageModule:refresh()` and never `present` or `push`. It also
cannot fire on a timer, checked, since `onChange` is reached only from `refresh` in
`plugins/vpn/engine.lua:21`, whose two callers are `M.start` once at load and the completion
thunk of a connect, disconnect, or setLocation. There is no poll anywhere in the engine or the
provider. So keeping the synchronous readers for `onChange` is genuinely off the hot path, as
the commit claims. One residual inefficiency, not this commit's, `refresh` reads the status
and then VPN's own `onChange` reads it again, two spawns where one would do.

**The last snapshot cannot show another tool's state.** `current`, `target`, and `cache` are
file locals of `plugins/vpn/init.lua`, shared with nothing, and VPN reads none of the stage's
world. `current` can never be set to nil either, checked on every path, `statusAsync` answers
`status or { state = "unavailable" }` and its no provider fallback answers the engine's own
`last`, which is initialised. So `rows` reading `current.state` cannot raise. What it can show
between the swap and the landing is VPN's own previous snapshot, which self corrects on the
redraw, which is the documented trade and the right one.

## New finding

### 12. The countdown has no failure path, so one task that never answers wedges every later open

**Severity** low, narrow but not theoretical.
**Verdict** confirmed by code reading.

`landed` at `plugins/vpn/init.lua:400` through `:408` clears `fetching` only when `remaining` reaches zero.
Nothing else ever clears it. There is no timeout, and none of the three `hs.task` calls checks
what `t:start()` answered, `plugins/vpn/providers/mullvad.lua:135`, `:146`, and `:203`.

So if any one of the three never calls back, and the two ways that happens are `t:start()`
failing because the binary moved or lost its executable bit, and the process never exiting
because the daemon is wedged, then `fetching` stays true for the life of the config. Every
later `prepare` queues its callback into `pending` and returns, so no fetch ever runs again,
no redraw ever fires from this path, and `pending` grows by one closure per open.

The list still draws, from the last snapshot, so the failure is quiet rather than visible. And
a mullvad daemon hanging on `status` is exactly the state a person opens this tool to look at,
which is why I am not calling it theoretical.

Not a regression. The single task version had the identical shape for `listLocations` alone.
The countdown triples the surface and now gates the status and the selected relay too. The
cheap close is one `hs.timer.doAfter` per round that forces `landed` for whatever has not
answered, or reading `t:start()`'s own answer and calling `landed` on false.

## The other three items

**Presentation members must state call. Fixed.** `callKindStated` at
`lib/registrar.lua:122` accepts only a table whose `call` is `dot` or `method`, so the bare
string shorthand is refused for a presentation and nowhere else, and the check runs before
`memberResolves` so the message names the right fault, `lib/registrar.lua:422` through `:441`.
`rowCount` is correctly outside the checked field list, so a plain number still passes. VPN's
own four members all state `dot` and already complied.

**Refused presentations reach wire problems. Fixed.** `describe` now returns a descriptor
carrying `presentation = {}` rather than nil. `lib/registry.lua:494` sees a non nil
presentation, `presentationIsWellFormed` refuses it on "has no rows function", `register`
answers false before `toolsByName` and `flatIndex` are touched at `:510` and `:511`, and
`lib/wire.lua` reads that false and calls `fail`, so the refusal lands in
`wire.record.problems` and prints through `w.report()`. The tool still vanishes everywhere,
no row, no key, no scope, no alias, and now the report agrees with the console.

**The pcall guard on the presenting branch. Fixed.** `root/compose.lua:1291` through `:1305`
resolves the member, answers nil when there is none so `activeSurface`'s own
`type(...) == "function"` test still works, and wraps the call. `pcall(fn, ...)` with no
receiver is right, since every closure `surfaceFor` builds is a plain closure over the stage's
own self. `return ok and result` answers false correctly for a false `isShowing` rather than
swallowing it into nil.

## Checks

`luac -p` clean on all six touched Lua files. `dependencies-collect` regenerates a byte
identical `DEPENDENCIES`, git status clean afterwards. `src/check-dependencies.sh` passes with
zero warnings.
