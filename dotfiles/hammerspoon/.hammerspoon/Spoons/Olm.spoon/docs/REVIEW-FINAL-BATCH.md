# Adversarial review, feat/chooser-final, the final migration batch, 2026-08-28

Eight commits in `/Users/milos.djakovic/Development/personal/.worktrees/chooser-final`,
diffed against main at `8bb354f`.

    e7edbd6  textcase
    f559018  emoji
    31f454b  tmuxsessions
    46d7d73  caffeinate
    8f63d3a  stage, contract v3, a select may answer a child
    eb7257c  displayprofiles on children
    8edee41  overlaydisplay as a root built presentation
    72b810b  browsertabs on children

luac and check-dependencies were run by the coordinator and are not repeated.

Verdict, NOT READY. The child mechanism itself is well built and the two plugins that use
it are the best written code in the batch. The defect is one line missing from the stage's
new intercept path, and because contract v3 routes every presentation's `onSelect` through
that path it breaks tools that were migrated and reviewed in earlier batches, not only the
eight here.

Counts. High 2, Medium 3, Low 4.

--------------------------------------------------------------------------------

## HIGH

### H1. A disabled row leaves `_selectHandled` stuck true, and the next row chosen anywhere is silently swallowed. CONFIRMED.

`host/stage/init.lua`, contract v3's new `_intercept`:

    function obj:_intercept(item)
      local p = self:_current()
      if p and p.intercept and p.intercept(item) then return true end
      if p and p.onSelect then
        local child = p.onSelect(item)
        if child ~= nil then
          ...
          if self:push(child) then return true end
        else
          self._selectHandled = true
        end
      end
      return false
    end

The flag is consumed in exactly one place, `_onSelect`, and the file's own comment states
the invariant it depends on, "it is asked on the very next call this host receives after
_intercept sets it". That premise does not hold for a disabled row.

`lib/chooser/providers/native.lua:470`, the keyboard path, calls
`self:_intercept(self:selectedItem())` with no `_enabled` check, and `selectedItem()` at
`:868` reads `currentChoices[selectedRow()]._item` without one either. So the stage's
`_intercept` runs for a disabled row and sets the flag. Return is then let through, and
`_completion` at `:733` reads

    if item and enabled and self.config.onSelect then

so `config.onSelect` never fires, `_onSelect` is never reached, and the flag is never
consumed. `_teardown` follows, `_onClose` clears the stack, and the flag survives the
window closing.

`Chooser:insertSelected` at `:862` takes the identical unguarded path.

Failure sequence, the most reachable one. Press the caffeinate leader key. Type `1h3`
and pause. `plugins/caffeinate/init.lua:262` answers

    { title = "Keep typing", subTitle = EXAMPLES, image = ..., enabled = false, item = { id = "hint" } }

Press Return, which is the ordinary impatient thing to do while typing a duration.
`plugins/caffeinate/manifest.lua` declares no `intercept`, so the stage calls
`select({ id = "hint" })`, `plugins/caffeinate/init.lua:275`'s `onSelect` matches none of
its four branches and answers nil, `_selectHandled` becomes true, `_completion` skips
`onSelect` because the row is disabled, and the window tears down. Now open the clipboard,
or the launcher, or anything at all, and choose the first row. `_onSelect` sees the stale
flag, clears it, and returns. Nothing happens. Press Return again and it works. One dead
keypress, no console line, no way to guess why.

Second confirmed vector, filesearch, which this batch does not touch and which contract v3
breaks anyway. `plugins/filesearch/chooser.lua:325` builds the status row as
`{ enabled = false, item = { status = true } }` and `:352` builds every help row as
`{ enabled = false, item = { help = true } }`. `M.choose` forwards to the file local
`onSelect`, which guards on `status` and `help` and answers nil. The help screen, reached
by typing a question mark, is nothing but inert rows, so Return anywhere on it arms the
flag.

Ruled out by inspection, not by luck. Processes' "Nothing running" row at
`plugins/processes/chooser.lua:233` and textcase's empty row at
`plugins/textcase/init.lua:145` both carry no `item` field, so `selectedItem()` answers nil
and `Chooser:_intercept` returns at its own `not item` guard before reaching the stage.
The click path at `native.lua:638` guards with `choice._enabled ~= false` and is safe.

The fix is one condition. Either `native.lua` passes the enabled state into `_intercept`
the way its click path already tests it, or the stage refuses to run `onSelect` for a row
the atom will not complete. The second is not expressible from the stage today, since a
presentation's row tables carry `enabled` but the item handed to `_intercept` does not, so
the honest fix is in the atom.

### H2. Contract v3 makes a disabled row actionable through Return and the insert key. CONFIRMED.

Same root cause, separate consequence, and it violates a contract the atom states outright.
`lib/chooser/providers/native.lua:36` documents `onSelect` as "fired when a row is chosen
(Return or the insert key). Not fired for a disabled row or an empty dismissal."

Before contract v3 that held on every path, because `onSelect` was only ever reached
through `_completion`, which tests `enabled`. Contract v3 added a second call site for the
same function inside `_intercept`, and that one tests nothing. So a disabled row now runs
the plugin's `onSelect` on two of the three selection paths and not on the third, which is
the click path that kept its guard at `:638`.

For caffeinate the call is inert, `{ id = "hint" }` matching no branch. It is not inert by
design, it is inert by coincidence of that plugin's dispatch shape. A disabled row whose
item carries the same fields an enabled one does would act. `lib/overlaydisplay.lua:338`,
`plugins/vpn/init.lua:243` and `:378`, `plugins/menusearch/init.lua:241` and `:413`,
`plugins/convert/init.lua:284`, `host/queryscope/init.lua:279` and `:291`, and
`plugins/clipboard/manager/prune.lua:197` all build disabled rows, and none of them was
written against a contract where a disabled row reaches `onSelect`. Each needs reading
before this ships, and that reading is work the atom's own guard would make unnecessary.

Worse, a disabled row can now DRILL. If such a row's `onSelect` answered a child table, the
stage would push it and swallow Return, so a guidance row would become a working menu
entry. Nothing does this today.

The one plugin that is safe is safe by hand. `plugins/browsertabs/manifest.lua` declares
`intercept = { member = "chooser.intercept" }` and `M.intercept` is

    function M.intercept(item)
      if item and item.noop then return true end
      return false
    end

whose manifest comment says plainly it exists "for one narrow reason, standing on a stray
selection of one of this level's own disabled guidance rows". The builder found the hole,
patched the one plugin in front of it, and left the mechanism unguarded for everyone else.
The same guard appears again in every displayprofiles child, `if not item or item.noop then
return true end`. Two plugins carry a workaround for a stage defect, which is the signal
that it belongs in the stage.

--------------------------------------------------------------------------------

## MEDIUM

### M1. A select answering a malformed table, or anything truthy that is not a presentation, runs the action twice. CONFIRMED, latent.

In `_intercept`, when `child ~= nil` but `self:push(child)` refuses, control falls to
`return false` and `_selectHandled` is never set, because setting it lives in the `else`
branch of the nil test. Return is then let through, `_completion` calls `config.onSelect`,
`_onSelect` finds the flag false and runs `p.onSelect(item)` a second time on the same row.

`push` refuses whenever `isPresentation` fails, which is a table missing `rows` or
`onSelect`, and `type(child) == "table"` is never even required before the call, so
`select` returning `true`, a number, or a string reaches `push`, is refused, and
double runs too. That last shape is the reachable one in ordinary Lua, a select written as
`function M.select(item) return doThing(item) end` where `doThing` happens to answer a
boolean.

The stage's own comment describes this as degrading "to the ordinary completion path rather
than swallowing the press", which is true and incomplete. It degrades to running the action
twice, and the actions behind these selects are activating a tab, applying a display
profile, killing a process, and pasting.

No migrated plugin triggers it today. Checked every select in the batch and the three from
the trickle batch, `plugins/caffeinate/init.lua:275`, `plugins/textcase/init.lua:191`,
`plugins/processes/chooser.lua:429`, `plugins/filesearch/chooser.lua:737`,
`plugins/emoji/init.lua:159` and `providers/hammerspoon.lua:311`,
`plugins/tmuxsessions/chooser.lua:139`, `plugins/browsertabs/chooser.lua` `M.select`, and
the four displayprofiles children's `onSelect = function() end`. Every one answers nil or a
real presentation. So this is a trap the contract sets rather than a live fault, and it
costs one line to close, setting the flag on any path that does not push.

### M2. A child borrows its parent's name, so `redrawPresented` repaints whichever level is current rather than the level the answer belongs to. CONFIRMED.

`_intercept` fills a nameless child in with `child.name = p.name`, decision two, which is
what keeps hints and navigation working. The consequence nobody named is that
`Stage:current()` answers the parent's name at every depth, and `redrawPresented(name)` in
`root/compose.lua` is exactly `if stageModule:current() == name then stageModule:refresh()`.

So when browsertabs' async listing lands while the person is two levels down in Settings,
`plugins/browsertabs/chooser.lua`'s `M.refresh` calls `redrawPresented("browserTabs")`, the
name matches because the child borrowed it, and `Stage:refresh` re runs `_current().rows`,
which is `settingsRows`. The tab listing repaints a level that has nothing to do with it.

Harmless here, since the settings rows rebuild to the same content and `refresh(nil)` keeps
the highlight. It is not harmless as a rule. Any plugin whose child rows are expensive, or
whose parent redraw carries a status the child does not show, gets a silent wrong target,
and there is no way for a plugin to ask "redraw my top level" any more. Worth either a
depth aware word or a documented statement that `redrawPresented` means "redraw whatever of
mine is current".

### M3. ActionPanel's `filtersItself` is frozen at construction while the matcher is now written live per presentation. CONFIRMED, predates this batch, widened by it.

`host/actionpanel/init.lua:394` captures `local filtersItself = config.matcher == false` once,
inside `decorate`, which runs at the single `Chooser.new` the stage makes. At that moment
`lib/chooser/init.lua:122` has already folded the root default in, so `config.matcher` is a
function and `filtersItself` is false forever.

Contract v2 made the stage write `self._instance.matcher` live before every show. So when
the panel opens over any presentation declaring `matcher = false`, the atom is not filtering
and the panel believes it is, and `filterOwnRows(self._panelRows, query, false)` hands back
rows nobody filters. Typing in the action panel over those tools does not narrow the verb
list.

This batch adds four more such tools, browsertabs, caffeinate, emoji and tmuxsessions all
declaring `matcher = false`, plus every displayprofiles and browsertabs child. The defect
arrived with contract v2 in the previous batch and is named here because the batch widens
its reach from three tools to eleven.

--------------------------------------------------------------------------------

## LOW

### L1. textcase's enter timeout is held only as an upvalue of the read callback.

`plugins/textcase/init.lua:208`, `local timeoutTimer = hs.timer.doAfter(ENTER_TIMEOUT, ...)`,
referenced afterwards only inside the closure handed to `self._read`. This is exactly the
pattern the previous review raised as L1 against processes and that the builder fixed there
by promoting it to a module local, twice, first to `enterTimeoutTimer` and then to a per
attempt record. If `self._read` ever drops its callback, the timer written to protect
against that failure is collectable with it. The precedent is two commits old and sits in a
sibling plugin.

### L2. Every drill and every Back rebuilds the rows twice.

`Chooser:_intercept` at `native.lua:489` does `self:refresh(true)` after the consumer
answers true. The stage has already rebuilt by then, `push` and `pop` both running `_show`,
whose swap branch does `setQuery("")` then `refresh(true)`. So one keypress on a child
spawning row rebuilds the incoming level twice, and displayprofiles' delete, which pops
twice in one press at `plugins/displayprofiles/chooser.lua:290`, rebuilds three times.
Correct output, wasted work, and for browsertabs it means `tabRows(query)` scores the whole
tab set twice per drill.

### L3. `overlayDisplayOpen` is now a correct predicate that still gates nothing, which reads as more progress than was made.

`root/compose.lua:580` installs it and it answers honestly through `Stage:current()`. Nothing
binds against it. `lib/wire.lua:449` binds only what is in `plan.contexts`, and
`lib/resolve.lua:309` fills `plan.contexts` only from `live[name].surface` inside the loop
over plugins. See the overlaydisplay section below for the full verdict.

### L4. The branch forks before the brief every commit cites.

`git merge-base 8bb354f HEAD` answers `ea4ea36`, so `docs/BRIEF-CONTRACT-V3.md`, added on
main at `8bb354f` and cited by name in the stage commit's message, its file header, and
five manifests, is absent from every commit in this branch. It appears as a deletion in the
diff for that reason alone. Rebase onto `8bb354f` before merging so the cited authority
exists at the commit that cites it.

--------------------------------------------------------------------------------

## Overlaydisplay, the claim checked rather than accepted

The builder reports the panel half of consumer map surprise 9.2 fixed and the j and k half
structurally out of reach because bindings derive from manifest surface contexts a lib
module has none of.

The panel half is genuinely fixed. `host/stage/init.lua` routes the docked panel through
`_onPositioned`, which asks only `_current()`, and the presentation `root/compose.lua:1923`
builds by hand reaches it like any other, so the three callbacks that never fired now fire.

The navigation half is more nearly done than the claim says, and less done than one line.
Three things are needed and two of them already exist.

The predicate exists. `root/compose.lua:580` installs `overlayDisplayOpen` through
`ownPredicates`, which `lib/wire.lua`'s predicates stage merges with the generated ones, and
it answers correctly through `Stage:current()`.

The bindings exist. `config/keys.lua:322` already carries a complete `overlayDisplay` block,
`when = "overlayDisplayOpen"`, priority 100, binding `i`, `j`, `k` and `x`, and
`test/inventory.golden:91` records the retired live root binding all five of them. The
person's own config has been asking for this the whole time.

What is missing is the join. `lib/resolve.lua:309` writes `out.contexts[contextName]` only
inside the loop over plugins that declare `surface`, and there is no merge of user declared
context blocks anywhere in that file, so a keys.lua block with no plugin behind it never
becomes a `plan.contexts` entry and `lib/wire.lua:449` never binds it. Second, the nav
adapter list in `root/compose.lua` is built from `plan.order` and `contextOwners`, so
nothing answers `selectNext` for this name even once a binding exists.

So the conclusion is right, j and k stay dead, but "structurally unfixable" overstates it.
Both gaps have precedent in this tree, `ownPredicates` for the predicate half and the
`services.nonPluginSurfaces` escape hatch the audit records for the surface half, and the
shape of the fix is a root contributed context block plus a root contributed adapter, both
fed from `Stage:surfaceFor("overlayDisplay")`. That is close out design, small and
precedented, not a one line grant and not a structural impossibility. Recommend saying so
in the close out plan rather than leaving it recorded as unreachable.

--------------------------------------------------------------------------------

## Checked and sound

The child mechanism, traced by hand.

- A select answering a table pushes. `_intercept` fills the name from the parent when the
  child names none, calls `push`, and answers true, so `native.lua:470` swallows Return and
  no window ever closes. A select answering nil sets the flag, answers false, and the row
  completes and tears the stack down through `_onClose`, unchanged from before.
- The click path reaches the same place. `native.lua:638` calls the same `config.intercept`,
  so a click on a child spawning row drills identically, and it additionally checks
  `_enabled` first, which is the guard the keyboard path is missing, H1 and H2.
- The ActionPanel decorator sits outermost and does not disturb any of it.
  `host/actionpanel/init.lua:394` wraps `rows`, `intercept`, `back`, `onSelect`,
  `onHighlight` and `onClose`, and every wrapper falls through to the captured original when
  `self._openInstance ~= instance`. While the panel is open its `intercept` answers for
  itself and the stage's `_intercept` is never reached, so no child is pushed and
  `_selectHandled` is never written from under the panel. Its `onSelect` wrapper swallows a
  panel row with a warning rather than calling through, which cannot strand the flag either,
  since the flag can only have been set on a path the panel was closed for.
- Backspace pops a child built by return value with nothing new. `_back` asks the current
  presentation's own `back` first, children of browsertabs and displayprofiles declare none,
  so `pop()` runs, and `pop` restores whatever sits below, which is the parent by
  construction.
- Three deep then all the way out. Launcher, browsertabs, settings child, browser child.
  Three backspaces land on the launcher, a fourth finds `#stack <= 1` and answers false, so
  it stays an ordinary press. Opened by its own hotkey instead, the stack starts at
  browsertabs and the launcher never appears uninvited.
- Every `onClose` is told exactly once, and the reason is that no child declares one. Only
  the top level presentation of each plugin carries `onClose`, so `pop` telling
  `leaving.onClose`, `closeStack` walking a hidden stack top down, and
  `closeStackExcept` skipping a survivor all converge on one call. Hide from the middle of a
  three deep child stack tells the two children nothing, browsertabs once, and the launcher
  once. Had a child carried the plugin's own `onClose`, a single backspace would have torn
  the plugin's state down while its parent list stayed on screen, and neither plugin does
  this.
- A malformed table does not crash. `push` runs `isPresentation`, logs "Stage push was given
  something that is not a presentation", and answers false, so the keypress completes the row
  normally. The stage survives. What it does wrong is run the action twice, M1.

`stagePop`, judged as a self extension. Thin and precedented. `root/compose.lua:775` is a
three line closure over the forward declared `stageModule` proxying `Stage:pop`, the
identical shape `stageHide`, `stageSetQuery` and `stageSetPlaceholder` already take, declared
in both plugins' `needs.data` with a real `breaks` sentence, optional, and degrading to an
inert press. It is not smuggled design. It exists because a Back ROW is genuinely the one
thing a child pushed from `select` cannot express, since answering nil means completion and
there is no "answer my parent" value, and the alternative would have been a second contract
field. Using `intercept` to carry it is decision three used exactly as written.

A Back row in displayprofiles, traced. Return on `{ nav = true, to = "back" }` reaches the
child's `intercept`, which calls `cfg.stagePop()`. `pop` bumps the enter generation, removes
the child, tells its `onClose` which it has none of, and calls `_show(parent, isShowing,
leaving)`, which rewrites placeholder, matcher, companionWidth and titleLineBreak for the
parent, tells the departing child `onPositioned(nil, nil)`, sets the query empty, refreshes
with the row reset to one, and re places the pair. The child's intercept then answers true,
the atom refreshes once more, and Return is swallowed. Window never closes, highlight at row
one, pane correct. The rename child additionally corrects its shared `state.name` before
popping so the profile screen it lands on does not read "Profile is gone", which is the kind
of detail that is usually missed.

Browsertabs.

- The three levels are children, each declaring its own `placeholder` and an explicit
  `matcher = false`, so nothing inherits the root fuzzy default by accident on drill in.
  This is the trap contract v3 sets, a child naming no matcher silently gets fuzzy, and both
  migrated plugins avoid it on every level.
- `M.select` answers nil or `buildSettingsChild()`, the settings child answers nil or
  `buildBrowserChild(bundleID)`, and the browser child answers nil. Genuine completions go
  through select, in place mutations and Back go through intercept, exactly as decision three
  splits them.
- The async guards survive. `M.prepare` keeps its single in flight `loading` guard and its
  waiter list, `setTabs` moves the listing and its signature together, and the redraw is still
  skipped when the signature is unchanged, so a landing answer that says nothing no longer
  rebuilds rows under a stationary highlight. The permission request callback still redraws
  through `redrawPresented`.
- The test harness flag is truthful. `showing` is set only in `M.onPresent`, which
  `_announce` runs for the top level presentation and never for a child, since children carry
  no `onPresent` except the settings level's `refreshPermissions`. It is cleared only in
  `M.onClose`, which only the top level declares. Checked against four doors, hide from a
  child level, backspace out through every level, another tool's hotkey firing `present` while
  a child is current, and the browsertabs hotkey pressed again from a child, and it answers
  correctly in all four. `plugins/browsertabs/test/agent.lua` reads it through
  `chooser.isShowing` and that member is intact.
- The private machinery is gone. Grepped the whole spoon. No `hs.eventtap.new` in
  `plugins/browsertabs/chooser.lua` or `plugins/displayprofiles/chooser.lua`, the only hits
  being prose comments and the test harness's own synthetic keystroke sender. `drawFrame`,
  `frameStack`, `pushFrame` and `popFrame` appear nowhere in code, only in the consumer map.
  No `doAfter(0` in either plugin. No `keyWatcher` or `SUBMIT_KEYCODES` outside the atom.
  `Chooser.new` survives in exactly two live call sites, `host/stage/init.lua:233` and
  `native.lua:1084`, every other occurrence in the tree being a comment. Thirteen consumer
  instances are now one.

Displayprofiles. Same shape, smaller. Drill in through `select` answering
`buildProfileChild`, rename and delete children pushed from that one, apply and capture
riding intercept, Back on every level through `stagePop`. Delete pops twice in one press so
it lands on the top list rather than on a profile screen naming something that no longer
exists, and both pops are legal at every reachable depth, four levels from the launcher and
three from the hotkey. The zero timer reshow is gone.

Caffeinate. `rowCount = 2` is the one consumer in the tree that differs from ten, which is
what the stage design brief named it for. Entering from a live ten row window takes
`_applyRowCount`'s hide, `setRows(2)`, show, which is the documented blink, and leaving takes
it again in reverse because the next presentation resolves to `_defaultRowCount`. A cold open
pays no blink at all, since `_applyRowCount` finds the window hidden, calls `setRows` and
answers false, and the ordinary cold show follows. `nav = false` is unchanged from before the
migration and is what keeps j and k dead on this one tool, correctly, since the list is a
single morphing row there is nothing to navigate. `matcher = false` is right and newly
expressible, the field being a value typed rather than a filter.

Emoji, textcase, tmuxsessions against the consumer map. Emoji goes through the provider
facade untouched, its presentation naming `rows`, `insert` and `placeholder` as method calls
matching `obj:` definitions, so the arity is right and the facade still decides which backend
answers. Textcase uses `enter` for its deferred selection read, with its own timeout and a
`fired` flag, the shape contract v2 asks for, and it declares no matcher so its fixed list of
cases keeps the shared fuzzy default it always had. Tmuxsessions deliberately stays on
intercept and back levels per decision four, its `intercept` setting `level` and answering
true and its `back` stepping out, which is the pre migration behaviour unchanged, and its
`primary` becomes `insertSelected` now that a private mechanism is no longer needed to hold
the window open.

The long chain, walked field by field. Launcher cold, filesearch pushed, backspace,
browsertabs pushed, its settings child pushed, backspace, backspace, clipboard pushed, hide,
then caffeinate opened cold by its hotkey. `_show` writes all four live fields on every door
including `pop`, so `placeholder`, `matcher`, `layout.companionWidth` and
`layout.titleLineBreak` are rewritten eight times and each resolves either to the incoming
presentation's own value or to the default captured at configure. Filesearch's
`truncateMiddle` does not survive its own pop, the clipboard does not inherit browsertabs'
`matcher = false` by accident since it declares its own, the pane is reserved and released
correctly at each step because `_applyPaneGeometry` is told the outgoing presentation on
every door, and the departing level is told `onPositioned(nil, nil)` so no canvas is left
beside a window that moved. Hide leaves the instance carrying the clipboard's values, which
nothing reads, because the next open goes through `_show` before anything is drawn. Nothing
bleeds.

================================================================================

# Second pass, rework verification, 2026-08-28

One rework commit, `1ae5fb7`, on `feat/chooser-final` rebased onto main at `8bb354f`.
Focused verification of the eight findings, plus the new plumbing the rework introduced.

Verdict, NOT READY. Six of the eight are genuinely closed. H1 and H2 are not, and the
branch is now strictly worse than it was before this commit, because the hand written
guards that were containing the defect were deleted on the strength of a central guard
whose argument never arrives.

New counts. High 1.

--------------------------------------------------------------------------------

## N1. HIGH. The enabled flag is dropped by the ActionPanel decorator, so the new disabled row guard never fires, and the local guards that used to contain the damage are gone. CONFIRMED.

The rework's own design is right. `lib/chooser/providers/native.lua:469` adds the shared
lookup, `:483` and `:886` make the keyboard and insert paths use it, `:513` widens the atom's
own call to `ask(item, enabled)`, and `host/stage/init.lua:248` widens the stage's config
closure to `function(item, enabled) return self:_intercept(item, enabled) end`. Every one of
those four edits is correct in isolation.

The chain between them is not. `Chooser:_intercept` resolves `ask` as `self.config.intercept`,
and that field is not the stage's closure. `host/actionpanel/init.lua:208` in the composition
root installs the decorator on every `Chooser.new`, and `host/actionpanel/init.lua:437`
overwrites `config.intercept` with its own wrapper after capturing the stage's as
`originalIntercept`:

    config.intercept = function(item)
      if self._openInstance == instance then
        return self:_choose(instance, item)
      end
      if originalIntercept then return originalIntercept(item) end
      return false
    end

One parameter, one argument forwarded. Lua drops the extra argument silently. So the real
chain is `ask(item, enabled)` into a wrapper that accepts only `item`, which calls
`originalIntercept(item)`, which is the stage's two parameter closure receiving `enabled` as
nil, which calls `Stage:_intercept(item, nil)`, whose first line is

    if enabled == false then return true end

and `nil ~= false`, so the guard never fires. H1 and H2 are exactly as open as they were.

This is the arity shift failure class this tree already has a written history of, the same
one `callKindStated` exists to refuse for presentation members. It is invisible to every
check that was run, since nothing raises, `luac -p` passes, and the reconciler has no view of
argument counts. It is also conditional on the decorator being installed, which it always is
in the real configuration, so a probe against a bare `Chooser.new` with no decorate policy
would have shown the fix working.

The regression is the second half. The commit deleted the containment. `plugins/browsertabs/manifest.lua:166`
now reads "No intercept at this level any more", and `M.intercept` is gone with it. All three
displayprofiles children lost their first line, `if not item or item.noop then return true end`
becoming `if not item then return true end`, each with a comment saying the stage now answers
for it. It does not.

Failure sequence, displayprofiles, which used to be safe and now is not. Open display
profiles, drill into a profile, choose Rename. `plugins/displayprofiles/chooser.lua:180`
draws a disabled `{ noop = true }` row reading "Type a new name" while the field is empty.
Press Return, which is the ordinary thing to do before realising you have to type first.
`_highlightedChoice` correctly answers item and `false`. The decorator drops the `false`.
The stage's guard does not fire. The rename child's own guard no longer tests `noop`, so it
falls through to `return false`. The stage then runs the child's `onSelect`, which is
`function() end`, gets nil, sets `_selectHandled = true`, and answers false. Return is let
through, `_completion` skips `config.onSelect` because the row is disabled, so the flag is
never consumed, and `_teardown` closes the whole tool. Two failures in one press. The
guidance row closed the picker, which it never did before this commit, and the stale flag
now silently swallows the first row chosen in the next tool opened, anywhere.

Browsertabs has seven such rows, `chooser.lua:199, 211, 224, 227, 230, 470, 479, 501, 510`,
and lost its guard entirely rather than partially.

The fix is one parameter and one argument in `host/actionpanel/init.lua:437`. Given the
decorator wraps five other config functions the same way, it is worth widening the wrapper to
`...` and forwarding with `...` rather than fixing this one by hand, since `onSelect` and
`onHighlight` will meet the same problem the first time the atom widens either.

--------------------------------------------------------------------------------

## Verdict per prior finding

### H1, `_selectHandled` stranded by a disabled row. NOT CLOSED, see N1.

The guard is written, placed first, and correct. It receives nil instead of false on every
path. Additionally, the click path was verified to need nothing, correctly. `native.lua:665`
still calls `self:_intercept(choice._item)` with one argument, but tests
`choice._enabled ~= false` inline before it, so a disabled row never reaches intercept via a
click at all. That asymmetry is deliberate and fine, the click path gates before asking and
the keyboard paths ask and let the consumer gate.

### H2, a disabled row actionable through Return and the insert key. NOT CLOSED, and regressed. See N1.

Same root cause. Worse than before the rework because the two plugins that were carrying
their own guards no longer are.

### M1, malformed child running the action twice. CLOSED.

`host/stage/init.lua:1180`:

    local child = p.onSelect(item)
    if type(child) == "table" and (child.name == nil or child.name == "") then
      child.name = p.name
    end
    if child ~= nil and self:push(child) then return true end
    self._selectHandled = true

The flag now sits outside the nil branch, on every path that does not end in a real push, so
a refused push and a truthy non table both set it and the atom's own completion consumes it
rather than running `onSelect` a second time. The name fill is correctly restricted to tables
and now runs before the push guard rather than inside the non nil branch, which changes
nothing behaviourally and reads better.

### M2, an async answer landing on the wrong level. CLOSED, and the token design holds up.

`root/compose.lua:765`:

    redrawPresented = function(name, resetRow, token)
      if not stageModule then return end
      if token ~= nil then
        if stageModule:isCurrent(token) then stageModule:refresh(resetRow) end
        return
      end
      local top = wiredRegistry.presentationFor and wiredRegistry.presentationFor(name)
      if top and stageModule:isCurrent(top) then stageModule:refresh(resetRow) end
    end

`Stage:isCurrent(token)` is `token ~= nil and self:_current() == token`, a plain identity
comparison with an explicit nil refusal so a plugin passing nothing cannot accidentally match
a nil stack top.

The identity survives, checked rather than assumed. `describeForRegistry` has exactly one
call site, inside `w.register`, so the registrar builds each presentation table once per
compose run and the registry holds that one table. `stagePresent` pushes the same table
`presentationFor` answers, so the no token path compares the stack top against the table that
was pushed. The stage's `child.name = p.name` mutates in place and preserves identity. A
`hs.reload` rebuilds the registry and the stage together, so there is no window where a stale
table could outlive the registry that produced it. The failure shape named, a stale identity
silently never matching again, would need a second `describe` pass or a registry rebuild
without a stage rebuild, and neither exists.

Browsertabs' self referential locals do reference the tables that get pushed.
`buildSettingsChild` declares `local child` and assigns the table to it, so
`onPresent = function() refreshPermissions(child) end` closes over the same table the function
returns and the stage pushes. Worth noting as a virtue rather than a risk, each drill builds a
fresh table, so an async answer started by an earlier visit to the same level holds the old
table, `isCurrent` answers false, and the stale redraw is dropped. That is the right behaviour
and it falls out of the design rather than needing a generation counter.

### M3, ActionPanel's frozen `filtersItself`. CLOSED.

`host/actionpanel/init.lua:428` moves the read inside the closure:

    config.rows = function(query)
      if self._openInstance == instance then
        local filtersItself = instance.matcher == false
        return filterOwnRows(self._panelRows or {}, query, filtersItself)
      end
      return originalRows and originalRows(query) or {}
    end

Reads the right field. `decorate(instance, config)` is handed the object `native.new`
returned, which is the same table the stage stores as `self._instance` and writes
`.matcher` onto in `_show`, so this is the same field, not a copy. Does not run on every
keystroke in a way that matters, since the read is inside the `self._openInstance == instance`
branch, so it costs one table index and one comparison only while the panel is actually open,
and the ordinary path returns `originalRows(query)` without touching it. The comparison is
against `false` specifically rather than a truth test, matching the atom's own contract where
nil means the default and false means the supplier owns filtering.

### L1, textcase's collectable enter timer. CLOSED.

Held at `self._enterTimeoutTimer`, `plugins/textcase/init.lua:81, 215, 229, 238`, the same
promotion already applied twice in `plugins/processes/chooser.lua`.

### L2, the rebuild count on a drill and a Back. CLOSED as documented rather than as code.

`plugins/displayprofiles/chooser.lua` now states the true count of three for the delete path
and explains where each rebuild comes from, the two pops' own swaps plus the atom's post
intercept refresh. This was raised as a Low costing microseconds nothing measures, and a
comment that stops the next reader re deriving it is the proportionate answer.

### L4, the branch forking before the brief it cites. CLOSED.

`git log --oneline 8bb354f..HEAD` shows nine commits on top of main, `docs/BRIEF-CONTRACT-V3.md`
is present in the tree, and the nineteen citations of it across `host/stage`, both migrated
plugins, `lib/overlaydisplay.lua`, `root/compose.lua` and both contract docs now resolve at the
commits that make them.

--------------------------------------------------------------------------------

## Checked and sound

The new lookup cannot desync from the widget's real highlight.

`Chooser:_highlightedChoice` at `native.lua:469` is the same two reads `Chooser:selectedItem`
at `:893` already makes, `self.chooser:selectedRow()` for the widget's live row number and
`self.currentChoices` for the atom's own row table, differing only in also returning
`c._enabled`. Both sources are written together and never apart. `_build` at `:237` is the
only writer of `currentChoices`, and every path that calls it, `Chooser:show` at `:775`, the
`queryChangedCallback`, and `Chooser:refresh` at `:811`, sets the choices and then sets
`selectedRow` in the same synchronous block. During a stage swap the sequence is
`setQuery("")`, whose callback rebuilds and clears `lastRow`, then `refresh(true)`, which
rebuilds again and sets row one, all inside `Stage:_show` with no yield to the event loop
anywhere. The key watcher is an `hs.eventtap` callback and cannot interleave with a
synchronous Lua block, so there is no instant at which the row number indexes a table from a
different presentation. `_enabled` itself is written by `_build` alongside `_item` on the same
row table, so the pair cannot separate even in principle.

The degenerate cases answer safely. When `c` is nil, both returns are nil and
`Chooser:_intercept` stops at its own `not item` guard before asking anything. When `c` exists
but carries no item, the first return is nil and the same guard applies. Neither reaches the
consumer.

The click path truly needed nothing. `native.lua:665` reads
`choice and choice._enabled ~= false and self:_intercept(choice._item)`, so the enabled test
happens before intercept is asked at all and a disabled row is simply not a click target. The
one argument call there is correct rather than an oversight.

Caffeinate's row count path, re verified after the rebase. `plugins/caffeinate/manifest.lua:78`
still declares `rowCount = 2` beside `matcher = false`, and `surface.nav = false` at `:47` is
unchanged, so j and k stay dead on this one tool and nowhere else.
`host/stage/init.lua:_applyRowCount` is untouched by the rework, so entering from a live ten
row window still pays the documented hide, `setRows(2)`, show, leaving pays it in reverse
against `_defaultRowCount`, and a cold open pays no blink at all because the branch that finds
the window hidden calls `setRows` and answers false.

Hide from the middle of a child stack, re verified after the rebase. No child table in either
`plugins/browsertabs/chooser.lua` or `plugins/displayprofiles/chooser.lua` declares `onClose`,
the only definition being browsertabs' top level `M.onClose` at `:835`. `closeStack` walks
`for i = #stack, 1, -1` and calls each level's own hook once, so hiding from three deep tells
the two children nothing, browsertabs once, and the launcher once. `Stage:hide` clearing the
stack after `_onClose` has already emptied it leaves the second walk with nothing to do, so no
level is told twice on any path.

Mechanical, rerun after the rebase.

`luac -v` reports Lua 5.5.0. `luac -p` passes on all nineteen touched `.lua` files, exit 0 and
no output on every one, the two remaining touched files being markdown.
`src/check-dependencies.sh` from the worktree root exits 0 with all nine sections clean and
"Dependency check passed, 0 warning(s)", and `git status --porcelain` and `git diff --stat`
are both empty afterwards, so no generated manifest was stale and no tracked file moved.

Grep sweeps confirming the rework's own claims. `_highlightedChoice` exists at
`native.lua:469` with call sites at `:483` and `:886` and nowhere else. `_selectHandled` lives
only in `host/stage/init.lua`. `filtersItself` lives only in `host/actionpanel/init.lua` and
is now a local inside `config.rows` rather than a captured upvalue. `timeoutTimer` survives
only as `self._enterTimeoutTimer` in textcase and the module local `enterTimeoutTimer` in
processes. Sixteen `{ noop = true }` row constructions remain across tmuxsessions,
displayprofiles and browsertabs, and not one of them is now guarded anywhere, which is N1.
