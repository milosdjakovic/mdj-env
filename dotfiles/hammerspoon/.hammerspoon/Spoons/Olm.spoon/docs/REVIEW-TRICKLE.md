# Adversarial review, feat/chooser-trickle, 2026-08-27

Four commits on top of main at c4eeb8b, in the worktree
`/Users/milos.djakovic/Development/personal/.worktrees/chooser-trickle`.

    03c5cc9  the presentation contract gains matcher and enter
    1edeeb9  filesearch migrates onto the shared stage
    252f4a4  processes migrates onto the shared stage
    32592b5  clipboard migrates onto the shared stage

Read whole, both trees: `host/stage/init.lua`, `lib/registrar.lua`, `root/compose.lua`,
`lib/chooser/init.lua`, `lib/chooser/providers/native.lua`, `lib/resolve.lua`,
`lib/services.lua`, the three plugins' `chooser.lua` / `manager/ui.lua` /
`manager/init.lua` / `manifest.lua` / `init.lua`, plus
`docs/PLAN-CHOOSER-STAGE.md`, `docs/BRIEF-STAGE.md`, `docs/BRIEF-CONTRACT-V2.md`,
`docs/PLUGIN-CONTRACT.md` presentation section, `docs/CONSUMER-MAP-2026-08-27.md`
sections 6, 7.3, 8 and 9.11, and the two prior reviews.

Verdict, NOT READY. Two of the findings are load time defects that the console will
name on the very first reload, and one of them takes a whole tool off the catalogue.

Counts. High 7, Medium 5, Low 5.

--------------------------------------------------------------------------------

## HIGH

### H1. FileSearch's presentation names a member that does not exist, so the entire plugin is refused at register. CONFIRMED.

`plugins/filesearch/manifest.lua:299`

    placeholder = { member = "chooser.placeholder", call = "dot" },

`plugins/filesearch/chooser.lua` defines no `placeholder` function anywhere. The only
occurrence of the word on that module is `cfg.placeholder = ""` at line 39, an
injected config field, not a member. Compare the other two migrations, which both
define one, `plugins/processes/chooser.lua:450` `function M.placeholder()` and
`plugins/clipboard/manager/ui.lua:1409` `function UI.placeholder()` with the forward at
`plugins/clipboard/manager/init.lua:178`.

`lib/registrar.lua` puts `placeholder` in `presentationFields` and checks every named
member against the real loaded module:

    local function memberResolves(module, member)
      ...
      return type(value) == "function"
    end

`owner.chooser.placeholder` is nil, so `memberResolves` answers false, `broken` becomes
true, and the branch at `lib/registrar.lua:556` sets `presentation = {}` on purpose, so
that `lib/registry.lua`'s own `presentationIsWellFormed` refuses it on "has no rows
function" and the refusal reaches `wire.record.problems` rather than vanishing.

Failure sequence. The config loads. Two console errors appear, one from the registrar
naming `chooser.placeholder`, one from the register step. FileSearch has no registry
entry, so it has no launcher row, no scope, no shortcut, and
`wiredRegistry.presentationFor("fileSearch")` answers nil forever. `M.show()` calls
`cfg.stagePresent("fileSearch")`, which asks the registry for a presentation that does
not exist and does nothing, so the leader key opens nothing. `surfaceAdapterFor` never
takes its presenting branch, falls to the plain module walk, and looks for `isShowing`,
`selectNext`, `selectPrev`, `insertSelected` and `hide` on the chooser submodule, all
five of which this commit deleted, so every routed key is dead too. The tool is gone.

This is the failure class both prior reviews already named, a declaration resolving to
nothing. The registrar catches it loudly, which is the system working, but the branch
ships the declaration.

### H2. `stageSetPlaceholder` is declared by the clipboard and published by nobody. CONFIRMED.

`plugins/clipboard/manifest.lua:91` declares it `source = "root"`, `policy =
"optional"`. `plugins/clipboard/manager/ui.lua:1371` and `:1390` are the two callers.
`root/compose.lua` publishes `stagePresent`, `redrawPresented`, `stageHide`,
`stageSetQuery`, `stageTextBudget`, `stageTextWidth` and `stageSelectedRow`, and
nothing named `stageSetPlaceholder`. The word appears in this repository only inside
the clipboard's own manifest, its own ui, and their comments. Commit 32592b5 does not
touch `root/compose.lua` at all.

Consequence. Both guarded calls are skipped. Entering manage history leaves the field
reading "Search clipboard" while a duration ladder is on screen, which is exactly the
manifest's own `breaks` sentence. `root/compose.lua:1883` runs
`servicesLib.owed(manifests, ..., "root")` at the end of every compose, so this also
prints, on every load,

    Olm compose, nothing supplied the root value 'stageSetPlaceholder' that clipboard
    declares as optional, so ...

which `lib/services.lua`'s own doc calls "the check the whole build needed and did not
have" for precisely this shape, a declaration that is right, validated, reported
satisfied, and then never delivered. This one is delivered nowhere and reported
correctly. The fix is one closure in the published set.

This also breaks `docs/PLUGIN-CONTRACT.md`'s own stated rule, line 862, that "a
`source = "root"` entry names a field the composition root actually publishes through
the fan out, never a word this plugin invented for itself."

### H3. A pending `enter` survives the atom's own teardown, so escape during a scan makes the window come back. CONFIRMED.

`host/stage/init.lua`. `_bumpEnterGen` is called by `present`, `push`, `pop` and
`hide`, and by nothing else. `_onClose`, the last function in the file, is what the
atom fires for "a completed selection, escape, a click away, or a programmatic hide".
It clears the stack and does not bump the generation.

Failure sequence, escape. Launcher is up at generation N minus one. Choosing the
Processes row calls `push`, which bumps to N and, because Processes declares `enter`,
hands over `proceed` and returns with the launcher still on screen, exactly as decision
two intends. The person changes their mind and presses Escape. `hs.chooser` completes
with nil, the atom tears down, `_onClose` runs, `_panelOnClose` fires, `closeStack`
tells the launcher its `onClose`, and `self._stack = {}`. `_enterGen` is still N. The
scan lands a moment later. `proceed` finds `fired` false and `self._enterGen == myGen`,
so it calls `finish`, which reads `wasShowing` false, builds a fresh stack, announces
Processes and cold shows it. The chooser reappears on screen seconds after the person
dismissed it, over whatever they went back to.

Failure sequence, completion. Same start. Instead of escaping, the person types
"safari" and presses Return. The launcher's app row completes, Safari is focused, the
atom tears down, `_onClose` runs, generation unchanged. The scan lands and the
Processes list opens on top of Safari.

`docs/BRIEF-CONTRACT-V2.md` decision two states the requirement in these words, "proceed
called after the stage moved on, the person escaped or opened something else meanwhile,
is dropped by the same staleness discipline". The guard covers only the programmatic
doors. The atom's teardown is the one path a person actually takes.

Fix, bump the generation at the top of `_onClose`, outside the `_suppressClose` guard
or inside it as the code prefers, since `_applyRowCount`'s internal hide is the only
call that must not count as the stage moving on.

### H4. `proceedOnce` commits `showing` and starts the sampler before it knows whether proceed was honoured, leaking a repeating timer for the life of the config. CONFIRMED.

`plugins/processes/chooser.lua`, inside `M.enter`:

    local function proceedOnce()
      if proceeded then return end
      proceeded = true
      showing = true
      startSampling()
      local waiting = entering
      entering = {}
      proceed()
      for _, cb in ipairs(waiting) do cb() end
    end

`proceed` may be dropped as stale by the stage's generation guard, which is the designed
behaviour, and `proceedOnce` has already set `showing = true` and started
`metrics.start(metricTargets, onSample)` by then. When proceed is dropped, Processes was
never put on the stack, so its `onClose` never fires, so `showing` is never returned to
false.

`onSample` then reads:

    if showing then
      misses = 0
      ...
      return
    end
    misses = misses + 1
    if misses >= MISSES_BEFORE_STOP then metrics.stop() end

`misses` is reset to zero on every tick, so `MISSES_BEFORE_STOP` never trips and
`metrics.stop()` is never reached. The sampler runs forever, sampling processes for a
window that is not on screen. The comment directly above `MISSES_BEFORE_STOP` says this
backstop exists "for a window that vanished without one". Replacing the widget question
with a plugin flag makes the backstop blind to the exact case it was written for.

Reachable today without H3 being fixed or unfixed. Press the Processes hotkey twice
while one scan is in flight. The second `present` bumps the generation, the scan lands,
`proceedOnce` runs once, the first `proceed` is dropped as stale by design, the second
is honoured. That is the intended path and it already leaves `showing` true and the
sampler started from a call that was discarded. With H3 present, an escape during a scan
leaves the same state plus a window on screen.

Fix, set `showing` and start the sampler from `onPresent` or from inside the honoured
branch, not before `proceed` has answered, and let the stage's own answer decide.

### H5. `M.enter`'s queued branch arranges no timeout, so a stuck `scanning` flag strands a launcher row permanently. CONFIRMED.

`plugins/processes/chooser.lua`:

    if scanning then
      entering[#entering + 1] = proceed
      return
    end

`ENTER_TIMEOUT` is armed only on the branch below this one, the branch that starts a
scan. A proceed that lands in `entering` has no timer of any kind behind it.

`scanning` is set true in two places. `M.enter`, whose callback and whose timeout both
clear it and both drain `entering`. And `M.refresh`, whose callback clears `scanning`
and never touches `entering` at all.

`plugins/processes/engine.lua:234` `obj:scan(cb)` calls back only once every source has
answered through `done()`. A source whose `hs.task` never returns leaves `pending` above
zero forever and `cb` is never called, so `scanning` stays true for the life of the
config with no timer anywhere.

Failure sequence, the reachable one. Processes is showing. The person presses the
refresh key, `M.refresh` sets `scanning = true` and a scan goes out. Within that window
they press Escape, then hyper space, then choose Processes from the launcher. `M.enter`
runs, `pending` is nil, `scanning` is still true, `proceed` goes into `entering` and the
function returns. The refresh callback lands, sets `scanning = false`, sees `showing`
false and does nothing else. `entering` is never drained. The launcher row silently did
nothing, with no timeout and nothing in the console. It self heals only on the next
open, whose fresh scan drains `entering` and calls the stale proceed, which the
generation guard then drops.

`docs/BRIEF-CONTRACT-V2.md` decision two, "enter must arrange its own timeout ... so an
answer that never comes cannot strand a person on a launcher row that silently does
nothing." Half the doors in this implementation arrange one.

### H6. `lastHighlighted` is never seeded from the widget and never cleared on close, so every cold open acts on the previous session's row for one poll interval. CONFIRMED.

Ordering, from `lib/chooser/providers/native.lua`. `config.onPositioned` fires at line
422, then `self.chooser:show({...})` at 427, then `self:_startPollLoop()` at 428.
`_startPollLoop` clears `lastRow` and arms `hs.timer.doEvery(self.config.pollInterval
or 0.08, ...)`, which first fires one full interval later. So on a cold show the
plugin's `onPositioned` runs before the widget has ever reported a highlight, and the
first real `onHighlight` is 80 milliseconds away.

All three migrations replaced `picker:selectedItem()` with a module local cache and none
of the three clears it on close.

    plugins/filesearch/chooser.lua:466   if viewer.followsHighlight then onHighlight(lastHighlighted) end
    plugins/processes/chooser.lua        renderHighlighted() -> onHighlight(lastHighlighted)
    plugins/clipboard/manager/ui.lua     onPositioned -> renderPreview(lastHighlighted)

`plugins/filesearch/chooser.lua` `M.onClose` clears `dirFits`, `iconMemo` and
`lastChooserFrame` and leaves `lastHighlighted`. `plugins/processes/chooser.lua`
`M.onClose` clears nothing of the sort. `plugins/clipboard/manager/ui.lua` `onClose`
clears `batch` and `page` and leaves it.

The clipboard is where this costs data, since a wrong deletion is unrecoverable.
`UI.deleteSelected` used to read `picker:selectedItem()` and now reads:

    local entry = lastHighlighted
    if not entry then return end
    store.removeEntry(entry)

Failure sequence. Yesterday the person had the clipboard open with entry E under the
highlight, and closed it. Today they press hyper x and then d in quick succession. The
open runs `onPositioned`, which calls `renderPreview(lastHighlighted)` and so actively
re caches E rather than reading the widget. The poll has not fired yet. `d` deletes E,
which is wherever it happens to sit in history now, not row one. Same shape for
`UI.appendSelected`.

Same shape, non destructive, elsewhere. Processes' `M.stopForced` resolves
`rowByKey(lastHighlighted.key)` and force kills it, so a key that still exists from the
previous session is a wrong target. FileSearch's `selectedRow()` now answers
`lastHighlighted`, and it feeds `M.peekPreview`, `M.revealRow` and `M.copyPathRow`, so
Finder opens on the previous session's file.

The stage already exposes `Stage:selectedItem()` as public api and `root/compose.lua`
already publishes `stageSelectedRow` for the menu search cache. The fix is one more
published word, `stageSelectedItem`, and deleting the cache, rather than a cache that
cannot answer the question the widget answers directly.

### H7. FileSearch's `onHighlight` and `onScroll` lost their `followsHighlight` gate, reintroducing a bug the plugin's own CLAUDE.md records as found and fixed. CONFIRMED.

Before, in the retired `Chooser.new` block:

    onHighlight = viewer.followsHighlight and onHighlight or nil,
    onScroll    = viewer.followsHighlight and viewer.scrollBy or nil,

After, `plugins/filesearch/manifest.lua` declares both unconditionally and
`plugins/filesearch/chooser.lua:591` and `:592` expose the raw functions:

    M.onHighlight = onHighlight
    function M.onScroll(points)
      viewer.scrollBy(points)
    end

`plugins/filesearch/viewers/quicklook.lua:56` sets `M.followsHighlight = false` and it
is a selectable docked provider, `opts.previewWith`, defaulted to `"sidepanel"` in the
manifest but documented as swappable at `plugins/filesearch/init.lua:128`.

With `previewWith = "quicklook"`, every highlight move now calls `viewer.show(item)`.
`plugins/filesearch/CLAUDE.md:995` through `:1002` states the consequence in its own
words, "under Quick Look that meant merely opening the picker threw a panel onto the
screen for whatever row happened to be first, and a result set landing threw another",
and `:793` through `:796` records it as one of the two bugs that came out of building
the provider split. The gate the fix installed is gone.

Note that the two remaining gates inside the file, at `:466` and `:709`, are still
there. It is the atom facing wiring that lost it, which is the half the file's own
comment says can never reach a non following provider.

--------------------------------------------------------------------------------

## MEDIUM

### M1. `paneWidth = true` is a static declaration where all three plugins used to compute the reservation. CONFIRMED, partly disclosed.

FileSearch before, `companionWidth = viewer.companionWidth(policy)`, and
`plugins/filesearch/viewers/quicklook.lua:177` `function M.companionWidth()` answers 0.
Processes before, `companionWidth = preview.isEnabled() and (cfg.previewWidth or true)
or 0`. Both now declare a flat `paneWidth = true` in the manifest.

`host/stage/init.lua`'s `_resolvePaneWidth(true, cf.w, L.paneMaxW)` answers
`min(480, 480)`, so the pair is centred as 480 plus 12 plus 480 with a blank right half
whenever the viewer or the pane actually stands down. The FileSearch manifest names the
`previewWith = false` case in its own comment and calls it "one honest gap this
migration leaves named rather than papered over". It does not name the `quicklook` case,
where a provider is present and available and simply asks for no room, nor the Processes
case where `opts.surface` is absent. Disclosed in part, real in full.

### M2. The explicit re render after a rebuild now feeds itself the stale item. CONFIRMED.

`renderHighlighted()` in `plugins/processes/chooser.lua` is `onHighlight(lastHighlighted)`
and `onHighlight` begins `lastHighlighted = item`, so the call assigns the cache to
itself. Its entire reason for existing, consumer map surprise 9.12, is that the atom's
poll compares the highlighted row NUMBER and does not fire when the list changes under a
stationary highlight.

`Chooser:refresh` does clear `self.lastRow`, so the poll corrects it one tick later,
80 milliseconds. That downgrades this from permanent to a race, but the whole value of
the direct call, stated in `plugins/filesearch/CLAUDE.md`, is that "it repaints at once
rather than on the next poll tick", and it now repaints the wrong row at once and is
corrected by the poll it exists to pre empt.

Worst case is `M.sortByLoad`, which reorders every row and asks for the highlight back at
the top. Its own comment says "The highlight returns to the top, which is where it
usually already was, so the poll sees no move even though every row has changed place
underneath it." With the highlight already on row one, the number does not change, and
the pane describes the pre sort process until `refresh`'s `lastRow = nil` lets the next
tick correct it. `M.stopForced` pressed inside that window force kills the pre sort
target.

Same shape in `plugins/filesearch/chooser.lua` `M.refresh` and in
`plugins/clipboard/manager/ui.lua` `UI.mediaReady` and `UI.entryChanged`.

### M3. PLUGIN-CONTRACT.md still says twice that a presenting plugin declares no `registry.surface`, while all three migrations declare one. CONFIRMED.

`docs/PLUGIN-CONTRACT.md:742`, "**A presenting plugin declares no `registry.surface`.**
... So a `registry.surface` entry left in place would be dead weight nobody reads rather
than a second answer." And the checklist at `:867`, "declares no `registry.surface`,
since host/stage answers navigation for it once presentationFor answers something."
Neither line changed on this branch.

Judgment asked for. The fallthrough is the honest fix, not a hole. The stage's
`surfaceFor` answers exactly five generic verbs plus `peekPreview`, and Processes binds
`refresh`, `sortByLoad` and `stopForced`, the clipboard binds `appendSelected`,
`deleteSelected`, `manageHistory`, `leaveManageHistory` and two scroll keys, and
FileSearch binds seven more. None of those live anywhere but the declared surface
object, so answering nil for them was a real defect that would have dropped bound keys
in silence, and `root/compose.lua`'s new fallthrough closes it with the ordinary walk it
already used before presentation existed. The mechanism is right.

What is wrong is that the contract now contradicts three shipped manifests, which is
this repository's own "two declaration systems drift" hazard, and the fix has to land in
the same commit as the thing it describes. The sentence should read that a presenting
plugin declares `registry.surface` only when it carries verbs beyond the five, that the
stage answers the five first and always wins them, and that a plugin with no extra verbs
declares none.

### M4. `UI.manageHistory`'s cold path now also runs its warm path. CONFIRMED.

    if not showing then
      if cfg.stagePresent then cfg.stagePresent("clipboard") end
    end
    if cfg.stageSetPlaceholder then ... end
    if showing then
      ... stageSetQuery("") ... redrawPresented("clipboard", true) ... renderPreview(lastHighlighted)
    end

`Stage:present` calls `_announce(p)` before `_show(p, ...)`, and the clipboard's
`UI.onPresent` sets `showing = true`. So by the time `cfg.stagePresent` returns, the
flag it was tested against is already true and the second block runs on what used to be
an early `return`. The comment says "Already showing, the field is cleared and the ladder
rebuilt exactly as before", which is not what the code does on the cold path.

The extra `stageSetQuery("")` and `redrawPresented(..., true)` are harmless on a fresh
field. `renderPreview(lastHighlighted)` is H6 in miniature, painting the previous
session's entry over a freshly opened prune page.

### M5. `onScroll` and `onRightClick` are now installed on the shared instance for every presentation. CONFIRMED.

`host/stage/init.lua`'s single `Chooser.new` wires both unconditionally. In
`lib/chooser/providers/native.lua`, `_startScrollWatcher` opens with `if not
self.config.onScroll then return end` and otherwise builds and starts an
`hs.eventtap` on every show, and the constructor at line 1100 installs
`rightClickCallback` when `config.onRightClick` is present. Both atoms document
themselves as wired "only when a consumer listens".

So the launcher, VPN, menu search, caffeinate and every future presentation now pay an
`hs.eventtap` on the scroll wheel per show, inert because `pointInFrame(e:location(),
fr.companion)` fails when there is no companion, and carry a right click callback that
routes to a `_onRightClick` no consumer answers.

Judgment on the extensions themselves. `onScroll` and `onRightClick` are true thin
passthroughs, identical in shape to `_onHighlight`, published in the presentation block,
checked by the registrar with the call kind rule applied, delivered by the current
presentation rather than by name, and documented in `docs/PLUGIN-CONTRACT.md:657` and
`:664`. They are correct additions. The cost is that the stage cannot gate the two
config fields the way each plugin used to, and it did not try. Gating them on the
current presentation declaring one, checked live inside the closure the same way
everything else is, would restore the atom's own promise at no cost to the routing.

--------------------------------------------------------------------------------

## LOW

### L1. `enter`'s timeout timer is held only as an upvalue of the scan callback.

`plugins/processes/chooser.lua`, `local timeoutTimer = hs.timer.doAfter(ENTER_TIMEOUT,
...)` inside `M.enter`, referenced afterwards only by the `cfg.api.scan` callback that
calls `timeoutTimer:stop()`. Two declarations above it, `reopenTimer` is a module local
with a comment stating this file's own rule, "A Hammerspoon timer is userdata whose
finalizer stops it, so one nothing refers to can be collected before it runs." If a
source ever drops the scan callback, the timer written to protect against exactly that
failure becomes unreachable with it. Make it a module local.

### L2. `refreshFooter` is now a conditional with an empty body.

`plugins/clipboard/manager/ui.lua:117`, `if cfg and cfg.footerFor then end`. The claim
that `setFooter` was already dead is correct, `grep -c setFooter` on
`lib/chooser/providers/native.lua` answers 0. `cfg.footerFor` now has no reader anywhere
in the plugin. An empty block is legal Lua and passes `luac -p`, and it is dead code the
next reader has to re derive.

### L3. `UI.build()` is a no op that still holds unused injection.

`local Chooser = nil` and `Chooser = opts.chooser` remain, along with `cfg.previewPoll`,
`cfg.previewW`, `cfg.chooserWidthPct`, `cfg.paneMaxW`, `cfg.chooserRowH`,
`cfg.chooserBaseH`, `cfg.chooserRows`, `cfg.uiGap`, `cfg.uiTopFrac` and `cfg.minVPad`,
all now unread. Correctly reasoned as inert and kept callable for
`manager/init.lua`'s own start. Named for the close out sweep.

### L4. The published root words are documented nowhere.

`stageHide`, `stageSetQuery`, `stageSetPlaceholder`, `stageTextBudget`, `stageTextWidth`
and `redrawPresented`'s new second parameter join `stagePresent` and `stageSelectedRow`
in appearing in no doc. `docs/PLUGIN-CONTRACT.md` contains none of these strings. A
pre existing gap that this branch widens by five, and the one place a plugin author
would look to find out which `source = "root"` words actually exist, which is what H2
would have been caught by.

### L5. `Launcher:refresh` is unscoped and now reaches three more presentations.

`host/launcher/init.lua:900`, `function obj:refresh() if self._stage then
self._stage:refresh() end end`. `Stage:refresh` re runs whichever presentation is
current, not the launcher's. A menu search scope answer landing late through
`cfg.refreshLauncher()` while the clipboard's prune page is pushed on top rebuilds the
prune ladder instead. Harmless today, rows rebuild and the highlight is kept, and it
predates this branch, but the surface of tools it can reach just grew from one to four.

--------------------------------------------------------------------------------

## Checked and sound

Mechanical.

- `luac -p`, luac 5.5.0 at `/opt/homebrew/bin/luac`, on all ten touched `.lua` files.
  All ten pass with exit 0 and no output. The other two touched files are markdown.
- `src/check-dependencies.sh` run from the worktree root. Exit 0, "Dependency check
  passed, 0 warning(s)", every one of the nine sections clean including "Refreshing
  module manifests, all module manifests current". `git status --porcelain` and
  `git diff` in the worktree are both empty after the run, so the script modified no
  tracked file and no generated manifest was stale.
- The same script from the main checkout prints identical text and exits 0. The only
  `git status` line there is an untracked `docs/BRIEF-CONTRACT-V2.md` predating the run.
- Both collectors, `dotfiles/tmux/dependencies-collect` and
  `dotfiles/hammerspoon/dependencies-collect`, produce byte identical output between the
  worktree and the main checkout, confirmed with `cmp`. All nine committed
  `DEPENDENCIES` manifests are identical between the trees. This is the expected result
  rather than a surprise, since every need this branch adds is a `source = "root"`
  computed word rather than a tool, and `needs.tools` is untouched.

The matcher, contract v2 decision one.

- The live write is on every door. `host/stage/init.lua` `_show` runs
  `self._instance.matcher = self:_resolveMatcher(p.matcher)` before the cold and swap
  branches alike, beside the identical `layout.companionWidth` write, and `pop` routes
  through `_show`, so present, push and pop all rewrite it.
- The restore is honest. `_defaultMatcher` is read once at configure from
  `self._instance.matcher`, which `lib/chooser/init.lua:122` has already folded
  `DEFAULT_MATCHER` into and `native.lua:1072` has already stored, and it is read before
  any presentation has written to that field. A presentation naming no matcher resolves
  back to it.
- `false` is honoured end to end. `native.lua:217` gates on `type(matcher) ==
  "function"`, so `false` takes the same path a nil matcher always did, the supplier owns
  filtering. `_resolveMatcher` returns `false` outright rather than falling through.
- The write is live rather than captured. `Chooser:_build` reads `self.matcher` on every
  keystroke, `native.lua:215`.
- No unmigrated consumer changed. The launcher, VPN, menu search and caffeinate all
  declare no matcher and now receive `_defaultMatcher` where they previously received the
  construction default, which is the same value.
- The registrar refusal is real and correctly scoped. A non string non false value is
  refused, a string absent from `deps.matchers` is refused, and `deps.matchers` being
  absent degrades to skipping the check rather than refusing every string, with the
  reasoning stated. `root/compose.lua` hands it `chooserAtom.matchers`, which is
  `lib/chooser/match.lua` exporting `fuzzy`, `substring` and `words`, so processes'
  `"words"` resolves.

Enter, the parts that hold.

- `proceed` called twice is a no op. The `fired` flag is checked before the generation
  and set before `finish`. Verified in both `present` and `push`, which carry identical
  copies.
- `finish` reads `outgoing` and `wasShowing` inside the closure rather than at call time,
  so a deferring presentation that runs long after the call that built it sees what is
  actually showing.
- `pop` bumps only when there is something to pop, and `hide` bumps unconditionally, both
  correctly reasoned in their own docstrings.
- Two presses during one scan behave. The second door bumps the generation, the first
  `proceed` is dropped as stale, the second is queued in `entering` and drained by
  `proceedOnce`, and the honoured one shows. This is correct as written, and it is also
  the path that triggers H4.
- The staleness rule exists in code rather than only in the commit message. It is
  `self._enterGen ~= myGen` inside both closures, backed by `_bumpEnterGen` returning the
  new value so the caller keeps its own copy. It is simply incomplete, H3.
- What happens when enter never calls proceed. On the scan branch, `ENTER_TIMEOUT` of 5
  seconds fires `proceedOnce` and the list opens on whatever rows were already held,
  which satisfies decision two. On the `pending` branch there is nothing to wait for.
  On the `scanning` branch there is no timeout at all, H5.

The stack, traced by hand.

- Launcher, then FileSearch pushed, then Backspace at empty, then Clipboard pushed. The
  push swaps into the live window, writes `companionWidth = true` and `matcher = false`,
  tells the launcher nothing since it declares no `onPositioned`, and re centres the pair
  through `_positionPane`. Backspace reaches `_back`, FileSearch declares no `back`, the
  stage pops, FileSearch hears its own `onClose` and clears its caches and viewers, the
  launcher below is restored through the same `_show` with `companionWidth` nil and
  `matcher` back to `_defaultMatcher`, FileSearch is told `onPositioned(nil, nil)` so any
  pane it drew clears, and `_positionPane` re centres the list alone because
  `_resolvePaneWidth(nil, ...)` answers 0. The clipboard push then rewrites both fields
  again. No matcher is left behind, no placeholder bleeds, no pane canvas is left
  standing.
- Processes entered while FileSearch's async results are in flight. FileSearch stays
  current for the whole deferral, `M.refresh` gates on its own `showing`, and
  `redrawPresented("fileSearch")` gates again on `stage:current()`, so results landing
  during the wait correctly still paint FileSearch. When the scan lands, `_freshStack`
  runs `closeStackExcept`, FileSearch hears `onClose`, `cfg.api.cancel()` abandons the
  engine's in flight work and its generation counter drops anything already queued.
- The clipboard's prune page and the delete paths. `intercept` is unchanged and safe. It
  acts on the item the atom hands it rather than on `lastHighlighted`, calls
  `prune.apply(item)`, reads the new count from `#store.all()`, notifies and answers
  true, and `native.lua` refreshes after the handler returns, so the list stands with a
  new count exactly as consumer map section 8.2 describes. `back()` answers true only on
  the page, so Backspace leaves manage history there and pops the stack from the history
  list. `deleteSelected` and `appendSelected` both remain inert while `page` is set, so a
  slice descriptor can never reach `store.removeEntry`. The three call sites the branch
  touched are `onRightClick`, `deleteSelected`'s batch loop and `deleteSelected`'s single
  entry, and only the last two changed what they read, H6.
- Paste and insert keep their deferral. `UI.select` is the same file local `onSelect`,
  reached by the atom's completion before teardown as before, `moveToFront` and
  `pasteBatch` are untouched, and the covered app the paste lands in is captured by the
  stage on cold show.
- Processes' confirmation frame still works. `reopenTimer` is still a module local so it
  cannot be collected. `runStop` sets `pending` and `reopen` after the atom has already
  torn down, exactly as before, arms the zero timer, and the timer now calls
  `cfg.stagePresent` instead of `chooser:show()`. `M.enter` sees `pending` truthy,
  proceeds at once and pays for no scan. `M.onClose` keeps `pending` when `reopen` is set
  and clears it otherwise, so an escape out of the confirmation still leaves the process
  alone. `stopForced` hides through `stageHide` before the async stop starts, matching the
  instant feedback the retired `chooser:hide()` gave.

Wiring and resolution.

- All three plugins' identity spellings match what their code passes. The manifests
  declare `name = "fileSearch"`, `"processes"` and `"clipboard"`, and the registrar
  stamps `presentation.name = identity`, which is what `stage:current()` answers and what
  `stagePresent` and `redrawPresented` are called with.
- All three submodule `configure` functions bulk merge, `for k, v in pairs(opts or {}) do
  cfg[k] = v end` in FileSearch and Processes and the `config` merge feeding `merged()`
  into `UI.configure` for the clipboard, and all three manifests wire `configure` at the
  submodule rather than the root, so every published root word reaches the code that
  reads it. The one that does not arrive is the one nobody publishes, H2.
- Every presentation member other than FileSearch's `placeholder` resolves on the real
  module. Checked by hand against the files, FileSearch's `rowsForQuery`, `choose`,
  `intercept`, `onHighlight`, `onScroll`, `onPositioned`, `onClose` and `peekPreview`,
  Processes' `rows`, `select`, `placeholder`, `enter`, `onHighlight`, `onPositioned` and
  `onClose`, and the clipboard's eleven forwards on `manager/init.lua`, each of which
  reaches a real function on `ui`.
- Every field on every presentation block states `call = "dot"` explicitly, so the
  registrar's `callKindStated` tightening passes.
- `Chooser:refresh(nil)` from `redrawPresented(name)` behaves exactly as the retired
  `picker:refresh(false)` did, `resetRow` being tested for truth.
- `pollInterval` genuinely was not an override. The clipboard passed `cfg.previewPoll`,
  which `manager/init.lua:111` sets to 0.08, and `native.lua:516` falls back to 0.08.
- `setFooter` really is absent from the only surviving backend, zero occurrences in
  `native.lua`, so the claim that `refreshFooter` was already dead is correct.
- FileSearch's `M:start` is still reached. It is in the manifest's `wiring` list as
  `{ target = "chooser", method = "start" }`, so dropping the `M.start()` call from
  `M.show` costs nothing.
- FileSearch's hosted launcher path still repaints. `plugins/filesearch/init.lua:260`
  composes `obj.chooser.refresh()` with `opts.redraw()`, so the retired `redraw` word and
  the new `redrawPresented` are both told.
- The `truncateMiddle` loss is the only layout field lost. Comparing the retired layout
  block against the atom defaults at `native.lua:104` through `:132`, `companionWidth`
  now travels as `paneWidth` and `titleLineBreak` has nowhere to go. Nothing else of
  either FileSearch's two field block or the clipboard's nine field block was silently
  dropped, the other eight being restated defaults per consumer map surprise 9.4.

================================================================================

# Second pass, rework verification, 2026-08-27

Four rework commits on `feat/chooser-trickle`, `b748fcf` stage infrastructure,
`e43a71f` filesearch, `2c7ae35` processes, `d85b5a7` clipboard. Judged as fixes
and as interactions, not as a fresh read of the branch.

Verdict, NOT READY. Fourteen of the eighteen prior items are genuinely closed,
two were legitimately left, one is partly closed with two residues, and one fix
is worse than the finding it answered and introduces two new highs.

New counts. High 2, Medium 1, Low 1.

--------------------------------------------------------------------------------

## Verdict per prior finding

### H1, FileSearch refused at register. CLOSED.

`plugins/filesearch/chooser.lua` now defines `function M.placeholder() return
cfg.placeholder end`. `memberResolves(owner, "chooser.placeholder")` walks
`owner.chooser.placeholder` and finds a function, so `broken` stays false and the
descriptor is built. `cfg.placeholder` arrives through `lib/wire.lua`'s own
`ENTITLEMENTS` table, `surface` earning `chooser`, `theme` and `placeholder`, and a
nil would still be harmless since `_show` does `p.placeholder or ""`. Correct.

### H2, `stageSetPlaceholder` published by nobody. CLOSED.

Defined at `root/compose.lua:764`, beside `stageSetQuery`, proxying
`Stage:setPlaceholder`. `services.owed` will no longer name it. Grepped the whole
spoon, the word now appears at the manifest declaration, both ui call sites, the
compose definition, and the contract doc.

### H3, a pending proceed surviving the atom's teardown. CLOSED.

`host/stage/init.lua` `_onClose` now calls `self:_bumpEnterGen()`, placed after
`if self._suppressClose then return end` and before `_panelOnClose`. The placement
is right and is the part worth checking, since `_applyRowCount`'s own internal
resize hide is the one teardown that must not count as the stage moving on, and it
returns before the bump. Escape, a click away and a completed selection all now
invalidate a proceed still in flight.

### H4, the sampler leaking on a dropped proceed. CLOSED.

`present` and `push` both return true from `proceed` only on the call that ran
`finish`, false on a second call and false on a stale one. Every caller reads it,
which is the part worth checking rather than the return value existing.
`plugins/processes/chooser.lua`, `M.enter`'s pending branch, `if proceed() then
showing = true end`, `proceedOnce`, `if proceed() then accepted = true end`,
`resolveEntering`, `if w.proceed() then accepted = true end`, and `queueEnter`'s own
timer, `if w.proceed() then showing = true; startSampling() end`. Four call sites,
four reads. `showing` and `startSampling()` are now reached only through `accepted`,
so a dropped proceed leaves neither set and `onSample`'s own miss backstop can see a
window that is not there again.

### H5, the queued enter with no timeout. PARTLY CLOSED, two residues below.

`queueEnter` gives each queued proceed its own `ENTER_TIMEOUT` timer, held in the
`entering` list, which is a module local, so nothing is collectable. Each entry
carries a `done` flag and removes itself from `entering` before firing late, so
whichever drains first is the only one that ever calls it. `M.refresh`'s callback
now drains `entering` too.

Both sequences asked for, walked by hand.

Double press. Press one, `push` bumps to N, `M.enter` takes the scan branch,
`scanning` true, `enterTimeoutTimer` armed. Press two during the scan, `push` bumps
to N plus one, `M.enter` finds `scanning` true and calls `queueEnter(proceed2)`. The
scan lands, `enterTimeoutTimer:stop()`, `scanning` false, `proceedOnce` runs,
`waiting` is taken and `entering` emptied, `proceed1` answers false against the
newer generation, `resolveEntering` stops `w2.timer` and calls `proceed2`, which
answers true, so `accepted` is true and `showing` plus the sampler are set exactly
once. No leaked timer, one honoured entry.

Press then refresh. Processes showing, refresh key pressed, `M.refresh` sets
`scanning` true and dispatches. Escape during that scan, `_onClose` bumps the
generation and `M.onClose` clears `showing`. Reopen from the launcher, `M.enter`
finds `scanning` still true and queues. The refresh callback lands, sees
`#entering > 0`, drains it, `resolveEntering` honours the queued proceed and sets
`showing` and the sampler. If the refresh scan never lands at all, the queued entry's
own five second timer fires, removes itself, and opens on whatever rows were held.
The strand is gone.

### H6, the `lastHighlighted` caches. CLOSED.

All three module locals are deleted, confirmed by grep, the only remaining
occurrences of the name being comments describing the retired cache.
`Stage:selectedItem()` is guarded on `#self._stack == 0` and published as
`stageSelectedItem` at `root/compose.lua:778`, declared by all three manifests.

The guard, checked against the question asked. The right answer at the
`onPositioned` seed call is the real row one, not nil, and that is what it gives.
`Chooser:show()` runs `choices(self:_build(""))`, then `selectedRow(1)`, then seeds
`config.onHighlight` with `currentChoices[1]`, and only then calls
`_positionAndShow`, which is where `config.onPositioned` fires. So the stack is
populated, `currentChoices` is this presentation's list and the row is one by the
time any plugin can ask. Borrowing `selectedRow`'s own `isShowing` guard would have
answered nil for exactly that call, and the builder's comment says so correctly. The
guard is false only after `hide` or the atom's teardown has emptied the stack, which
is the one case worth refusing, since `hs.chooser` restores rather than forgets a
selection across a hide.

The clipboard's delete, checked directly. `UI.deleteSelected` guards on `showing`,
which `UI.onPresent` sets, and `_announce` runs before `_show`. On both doors the
list is rebuilt synchronously inside `_show` before it returns, `show()` doing
`choices` plus `selectedRow(1)` on the cold path and `setQuery("")` plus
`refresh(true)` doing the same on the swap path, with no yield to the event loop
anywhere between. A key press cannot interleave, so `stageSelectedItem()` can never
answer a row from before the current open. A missing `stageSelectedItem` leaves
`entry` nil and the function returns without deleting, which is the right way for a
delete path to degrade.

The cross presentation question, filesearch on row three, push clipboard, delete
within the poll interval. `push` calls `finish`, which appends the clipboard to the
stack, announces it, and calls `_show`. `_show`'s swap branch runs `setQuery("")`,
whose `queryChangedCallback` rebuilds `currentChoices` through `_build`, which asks
`self.config.rows` and therefore the stage's `_rows` and therefore
`_current().rows`, already the clipboard's `buildChoices`. `refresh(true)` then
rebuilds again and sets `selectedRow(1)` unconditionally. Both are synchronous
inside `push`, so by the time the delete key can fire, `currentChoices` is the
clipboard's list and the row is one. The only code that runs against the
intermediate state is `outgoing.onPositioned(nil, nil)`, and all three plugins'
`onPositioned` return immediately on a nil companion frame without asking for a
selection. No cross presentation read is possible.

One honest correction to my own first pass. I cited the cold open as the stale
window, on the grounds that `onPositioned` fires before `_startPollLoop`. That half
is true, but `Chooser:show()` has always seeded `config.onHighlight` with
`currentChoices[1]` immediately before `_positionAndShow`, and that seed predates
this branch, confirmed at `c4eeb8b`. So the cold open was never stale. The real
stale window was the swap path, where `refresh(true)` clears `lastRow` but seeds no
highlight, so a push from the launcher left the cache at the previous session's
entry until the poll fired, and the stationary highlight rebuild, which was M2. The
finding and its cost were real on the door people actually use, my stated mechanism
was wrong in its first half, and the fix closes both paths regardless.

### H7, the lost `followsHighlight` gate. CLOSED, and better than asked for.

The gate is now inside `onHighlight` itself, `if not viewer.followsHighlight then
return end`, and inside `M.onScroll`, rather than only at the two call sites the
migration happened to touch. That covers the atom facing wiring, the
`onPositioned` seed, and `M.refresh` at one seam, which is what
`plugins/filesearch/CLAUDE.md:997` asks for. `quicklook.lua`'s
`followsHighlight = false` can no longer be handed a highlight event by any path.

### M1, static `paneWidth`. CLOSED.

`paneWidth` may now be a member spec. `plugins/filesearch/manifest.lua` names
`chooser.paneWidth`, which answers `viewer.companionWidth(cfg.preview or {})`, and
`plugins/processes/manifest.lua` names `chooser.paneWidth`, which answers
`preview.isEnabled() and (cfg.previewWidth or true) or 0`. Both mirror the retired
layout arithmetic exactly. The clipboard correctly keeps the flat `true`, since
`cfg.previewW` was unconditional there and M1 never named it.

The loudness, checked. `lib/registrar.lua` runs `callKindStated` then
`memberResolves` on the table form, sets `broken` and logs an error naming the tool
and the member on either failure, the identical shape every other member spec in
that loop gets, and the plain value branch's message was widened to "not a plain
number, true, or a member spec". Same refusal, same volume.

The ordering, checked, since a member resolved before wiring had run would have
answered zero and killed the pane outright. `lib/wire.lua`'s fixed stage order is
`leaders, configure, steps, predicates, register, contexts, start`. Stage three,
`self.steps`, runs `plan.wiring`, and both plugins declare `{ target = "chooser",
method = "start" }` there. Stage five, `self.register`, is what calls `describe`.
So `viewer` and `preview` are both resolved by the time `resolvePaneWidth()` runs.
`describeForRegistry` has exactly one call site, `root/compose.lua:1495`, inside
`w.register`, so there is no earlier pass to freeze a wrong answer.

### M2, the direct re render feeding itself. CLOSED.

`renderHighlighted` reads `cfg.stageSelectedItem()` live. After `sortByLoad`'s
`redrawPresented("processes", true)`, `Chooser:refresh(true)` has already rebuilt
`currentChoices` from the sorted rows and set `selectedRow(1)`, so the immediate
repaint describes the new top row rather than the pre sort one. The
`stopForced` mis target that rode on it goes with it.

### M3, the contract contradicting three manifests. CLOSED.

`docs/PLUGIN-CONTRACT.md:797` now reads "A presenting plugin declares
`registry.surface` only when it carries verbs beyond the five", with the checklist
at `:931` matching. Both describe the rule the code follows.

### M4, `manageHistory`'s cold path running the warm path. CLOSED.

`local wasShowing = showing` is captured before `cfg.stagePresent`, and both
branches test it. The comment now describes what the code does.

### M5, `onScroll` and `onRightClick` installed for every presentation. NOT CLOSED, REGRESSED. See N1 and N2.

### Rework rider, `titleLineBreak`. CLOSED.

A fourth live written field. `_defaultTitleLineBreak` is captured at configure from
`self._instance.layout.titleLineBreak`, which `DEFAULT_LAYOUT` has already folded
`"truncateTail"` into at `native.lua:127`. `_show` writes `p.titleLineBreak or
self._defaultTitleLineBreak` on every door before either branch. The value is
consumed per row at `native.lua:189`, `styledText(it.title, ..., L.titleLineBreak)`,
inside `_build`, and `L = self.layout` is read live, so both a cold `show()` and a
swap's `refresh(true)` pick up the new value. The registrar type checks it as a
string and refuses loudly otherwise. FileSearch gets its `truncateMiddle` back and
no other presentation is affected.

### L1, the collectable timeout timer. CLOSED.

`enterTimeoutTimer` is a module local, and every queued entry's timer is held on its
own record inside the module local `entering` list. Nothing depends on a scan
callback staying reachable to keep a timer alive. See N3 for what the module local
introduced.

### L2, the empty conditional. CLOSED.

`refreshFooter` is now an empty function body rather than an `if` guarding nothing.

### L3, `UI.build` and its unused injection. LEGITIMATELY LEFT.

`UI.build()` is now a bare `return UI`. The `local Chooser` and its assignment in
`UI.configure`, and the nine unread layout fields on `cfg`, remain. My own first
pass named this "for the close out sweep" rather than as a defect, phase 7 of
`docs/PLAN-CHOOSER-STAGE.md` being explicitly "retire dead surface plumbing". Both
are inert and neither can be reached at runtime. Correctly deferred.

### L5, `Launcher:refresh` unscoped. LEGITIMATELY LEFT.

`host/launcher/init.lua:900` is unchanged, still `self._stage:refresh()`. This
predates the branch, arrived with phase 3, and its worst outcome is a rows rebuild
of whichever presentation is on top with the highlight kept, which touches no data
and loses no state. Widening its blast radius was a consequence of the migrations
rather than a defect they introduced. Correctly deferred to the same close out.

### L4, the undocumented root words. CLOSED.

`docs/PLUGIN-CONTRACT.md:338` through `:348` now document `redrawPresented(name,
resetRow)`, `stageHide()`, `stageSetQuery(text)`, `stageSetPlaceholder(text)`,
`stageSelectedRow()`, `stageSelectedItem()`, `stageTextBudget()` and
`stageTextWidth()`, in the root fan out section, which is the one place that would
have caught H2.

--------------------------------------------------------------------------------

## New findings

### N1. HIGH. The clipboard's right click delete is now dead on every path. CONFIRMED.

`lib/chooser/providers/native.lua:1101` is the only occurrence of
`rightClickCallback` in the whole atom, and it sits inside `obj.new`, guarded by
`if config.onRightClick then` and evaluated once, at construction:

    if config.onRightClick then
      c:rightClickCallback(function(row)
        local ch = self.currentChoices[row]
        if ch then config.onRightClick(ch._item, row) end
      end)
    end

The M5 fix deleted `onRightClick` from the config table `host/stage/init.lua` hands
`Chooser.new`, so at construction the field is nil and the callback is never
registered on the `hs.chooser` at all. `_show`'s later
`self._instance.config.onRightClick = ...` writes into a table that nothing reads
again for this purpose, since the only reader lives inside a closure that was never
installed.

Failure sequence. Open the clipboard by any door. Right click any history row. The
entry is not deleted and nothing happens. There is no console line, because nothing
failed, the callback simply does not exist. `plugins/clipboard/manager/ui.lua`'s
`onRightClick` is unreachable dead code and its `store.removeEntry` never runs.

This is the failure class the commit message itself invokes and gets backwards.
`config.onScroll` is genuinely re read per show, at `_startScrollWatcher`.
`config.onRightClick` is not, it is read once at construction, so moving it out of
the constructor removes the feature rather than deferring it.

### N2. HIGH. The pane's trackpad and wheel scroll is dead for any presentation reached by a swap, which is the launcher door. CONFIRMED.

`_startScrollWatcher` has exactly one caller, `lib/chooser/providers/native.lua:431`,
inside `_positionAndShow`, which runs only from `Chooser:show()`. `_teardown` at
`:264` stops and nils the watcher, so it must be restarted by a show every time.

The M5 fix writes `self._instance.config.onScroll` only on `_show`'s cold branch,
immediately before `self._instance:show()`. A presentation reached by a swap gets
neither the write nor a watcher, because a swap runs `setQuery` and `refresh` and
never calls `show()`.

Failure sequence. Press hyper space. The launcher cold shows, declares no
`onScroll`, so the stage writes nil and `_startScrollWatcher` returns at its first
line, leaving no watcher. Choose the Clipboard row. `push` swaps into the live
window, no `show()` runs, `config.onScroll` stays nil and no watcher is ever
started. Scroll the trackpad over the preview pane. Nothing moves. The same for
FileSearch's detail pane. The two bound scroll keys still work, since they call
`viewer.scrollBy` and `UI.scrollPreviewBy` directly through the surface adapter, so
the loss is the gesture only, which is what the atom grew the callback for.

The asymmetry makes it worse rather than better. Opening the clipboard by its own
leader key over a hidden window is a cold show, writes the closure, and the gesture
works. Opening the same tool from the launcher is a swap and it does not. One tool,
two doors, two behaviours, with nothing anywhere saying why.

Judgment on M5 as a whole. The permanent closures were correct and the finding I
raised against them was worth no more than it cost, one idle `hs.eventtap` per cold
show, because the routing closure resolves through `_current()` on every call and
can never reach the wrong plugin. Trading that for a dead feature and a door
dependent one is a bad trade. The right shape, if the idle watcher is worth
removing at all, is to restore both fields to the constructor and let
`_startScrollWatcher` itself decline when the current presentation declares no
`onScroll`, or to have the stage re arm the watcher on a swap. Recommend reverting
the `Chooser.new` half of M5 and keeping everything else in `b748fcf`.

### N3. MEDIUM. The shared `enterTimeoutTimer` slot lets a late scan stop its successor's timeout, reopening H5 by another route. CONFIRMED.

`plugins/processes/chooser.lua`. The scan branch of `M.enter` writes the module
local `enterTimeoutTimer`, and its scan callback stops whatever that slot holds at
the moment the callback fires, not the timer this call armed:

    enterTimeoutTimer = hs.timer.doAfter(ENTER_TIMEOUT, function()
      scanning = false
      proceedOnce()
    end)
    cfg.api.scan(function(result)
      if enterTimeoutTimer then enterTimeoutTimer:stop() end
      scanning = false
      ...

The commit's own comment claims this is safe, "a fresh chooser.enter call always
finds scanning already true or already false and never starts a second timer racing
this one." That is false, because a timer having already FIRED does not prevent its
own scan from landing later, by which point a second enter has legitimately armed a
new one into the same slot.

Failure sequence. Enter A at t equals zero, `scanning` true, `T_A` armed, a scan
dispatched against a slow source, docker starting up being the ordinary case. At t
equals five `T_A` fires, sets `scanning` false and opens the list on stale rows. At
t equals six the person escapes, the generation bumps, `showing` clears. At t equals
seven they reopen from the launcher, enter B finds `scanning` false, arms `T_B` into
the same slot and dispatches scan B. At t equals eight scan A finally lands, stops
`T_B`, and clears `scanning` for a scan that is still in flight. Scan B now has no
timeout at all. If it hangs, `proceed_B` is never called and the launcher row did
nothing, silently and permanently, which is exactly the H5 failure the rework was
written to close. The same `scanning = false` also lets a third enter start a third
overlapping scan.

`queueEnter` got this discipline right, a per entry timer on its own record with a
`done` flag and self removal. The scan branch should follow it, capture the timer in
a local, compare identity before stopping, and nil the slot when it fires.

### N4. LOW. The queued timeout proceeds without clearing `scanning`, so a hung scan permanently degrades the tool.

`queueEnter`'s timer honours its proceed, sets `showing` and starts the sampler, and
never touches `scanning`. Only `M.enter`'s own scan callback, its own
`enterTimeoutTimer`, and `M.refresh`'s callback clear that flag. So after a scan
that genuinely never returns, `scanning` stays true forever. `M.refresh` then
returns at its own `if not showing or scanning` guard, so the refresh key is dead,
and every later `M.enter` takes the queued branch and waits the full five seconds
before showing anything.

This is a large improvement on the previous silent strand and is arguably the
correct conservative behaviour for a hung task, but it is undocumented and one line
from being unnecessary. Either clear `scanning` in the queued timeout or say in the
comment that the flag is deliberately left set.

--------------------------------------------------------------------------------

## Mechanical, rerun

- `luac -v`, `Lua 5.5.0`. `luac -p` on all ten touched `.lua` files from
  `git diff --name-only c4eeb8b..HEAD`, all ten pass, exit 0, no output. The other
  two touched files are markdown.
- `src/check-dependencies.sh` from the worktree root, exit 0, stderr empty, all nine
  sections clean, "all module manifests current", "Dependency check passed, 0
  warning(s)". `git status --porcelain` and `git diff --stat` both empty afterwards,
  so the script modified no tracked file and no generated manifest was stale.

Both builder grep claims spot checked rather than trusted.

- `setFooter` in `lib/chooser/providers/native.lua`, zero hits, exit 1, and zero
  recursively across all of `lib/chooser`. The claim that it was already dead before
  the migration holds.
- `lastHighlighted` across the whole spoon, eight hits, every one of them prose
  inside a comment describing the retired cache, at
  `plugins/processes/chooser.lua:61,373,374,665`,
  `plugins/filesearch/chooser.lua:71`, and
  `plugins/clipboard/manager/ui.lua:37,1329`. No `local lastHighlighted` declaration
  survives anywhere. The claim holds.

Additional sweeps run for this pass. `stageSelectedItem` defined once at
`root/compose.lua:778` and declared by all three manifests. `stageSetPlaceholder`
defined once at `root/compose.lua:764`. `rightClickCallback` exactly one occurrence,
`native.lua:1101`, inside `obj.new`, which is N1. `scrollWatcher` started from one
place, `native.lua:431` inside `_positionAndShow`, which is N2. `titleLineBreak`
consumed at `native.lua:189` inside `_build` off a live `self.layout`.
