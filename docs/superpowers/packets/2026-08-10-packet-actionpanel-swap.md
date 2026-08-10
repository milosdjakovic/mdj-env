# Work packet, the panel itself, on a chooser opened by its own chord

Phase 8 of the build plan, the action panel, packet two of three. Written 2026-08-10 against
`feat/action-panel` after packet one landed. Work in the worktree at `../.worktrees/action-panel`
on the branch already checked out there. Never work from the primary checkout, never push, never
merge.

Read `docs/superpowers/packets/2026-08-10-packet-actionpanel-classification.md` and the module it
built, `Spoons/Olm.spoon/host/actionpanel/init.lua`, before starting. Read the design's action
panel section, and verify its line citations rather than trusting them.

Packet three handles a list hosted inside the launcher, where the verbs belong to a tool whose own
picker is not open. Nothing here anticipates it. This packet is the panel on a chooser the user
opened by that tool's own chord, which is eleven of the twelve contexts working the ordinary way.

## The shape

Decorator. The chooser atom is the component, the panel is the decorator, and it is installed
through the seam `Chooser.configure` already is. Every chooser in this configuration is built by
one of twelve calls to `Chooser.new`, each handing in its own `rows`, `intercept`, `back`,
`onSelect`, `onHighlight` and `onClose`. The panel wraps those functions rather than replacing any
of them, so a chooser behaves exactly as it did whenever the panel is closed, which is almost
always. No plugin is edited and no plugin learns the panel exists.

That matters because only two of the twelve pass `intercept` today and only one passes `back`. A
panel that needed a plugin to opt in would be ten edits and a silent gap the eleventh time somebody
added a chooser.

## Where the design was wrong, and what that costs

The design says the atom already exposes everything the swap needs and that no new atom surface is
required. Both are false, verified against the code rather than argued.

`config.rows` is captured at construction and read live from `self.config.rows` on every build, and
there is no setter for it anywhere in the tree. `refresh` re-asks that same function. So the only
way to change what a chooser shows is to change what its own supplier answers, which is what
wrapping the supplier does.

The highlighted row number is read and written only from inside the atom. `selectedItem` is public
and answers the item, but nothing answers or sets the number, and the number is what has to be put
back so that a verb acts on the row the panel was opened over rather than on the panel's own first
row.

So this packet adds three things to the atom and no more. Two accessors, and one injection door on
`configure`. The picker contract the design was protecting grows by two ordinary accessors that the
atom already uses internally in four places, which is a smaller thing than the design feared.

## The atom

In `Spoons/Olm.spoon/lib/chooser/providers/native.lua`, two methods.

`Chooser:selectedRow()`, the highlighted row number or nil, the plain public counterpart of
`selectedItem` beside it.

`Chooser:selectRow(n)`, setting it, clamped to the number of rows currently built so a caller
cannot ask for a row that is not there. It clears `self.lastRow` afterwards, the same clearing
`refresh` already does and for the same reason, so the highlight poll notices that what is under
the cursor changed.

In `Spoons/Olm.spoon/lib/chooser/init.lua`, one more `configure` option beside `screen` and
`matcher`, a function called with the newly built instance and its config, after `native.new`
returns and before `new` hands the instance back. It is allowed to mutate the config in place.

That is legal rather than a trick, and say so in a comment. `native.new` stores the config table by
reference and never copies it, and every key this packet wraps is read live through `self.config`
on each use rather than captured at construction. Only `matcher`, `fieldMode` and `layout` are
captured, and this packet touches none of them. `Chooser.new` already mutates the caller's own
config in place for `screen` and `matcher`, so this follows the file's existing idiom rather than
inventing one.

The atom learns nothing about what the function does. It calls what the root gave it.

## The panel

`Spoons/Olm.spoon/host/actionpanel/init.lua` grows its runtime half. `configure` keeps `kindOf` and
`log` and gains two more injected collaborators.

`deps.rowsFor(contextName)`, answering the ordered rows the panel should show for that context,
each a table carrying `action`, `title`, and `chord`. Presentation, so the root owns it.

`deps.run(action)`, running a named action. The root owns that too.

The panel exposes three things.

`obj:decorate(instance, config)`, the function the root hands to `Chooser.configure`. It records
the instance and wraps six config functions, described below.

`obj:toggle()`, what the chord runs.

`obj:isOpen()`, whether the panel is currently showing.

### What decorate wraps, and why each one

`rows`, so that while the panel is open on this instance the supplier answers the panel's rows
instead of the tool's. This is the swap and there is no other.

`intercept`, so that choosing a panel row is answered by the panel rather than completing as a row
of the underlying list. Absent on ten of the twelve, so the wrapper supplies one where there was
none and falls through to the original where there was.

`back`, so Backspace on an empty field steps out of the panel, which the design names as one of the
two ways out. Absent on eleven of the twelve, same treatment.

`onSelect`, which with every chooser in filter mode should never see a panel row at all, since
`intercept` answers first. So the wrapper does not call the original for one and logs a warning
naming it, because a panel row reaching a tool's own select handler is a defect and the tool would
otherwise treat it as one of its own items in silence.

`onHighlight`, which is not called at all while the panel is open, so a companion pane keeps
showing the item the panel was opened over. That is deliberate rather than an omission. The
captured item is exactly what a chosen verb acts on, so leaving the preview on it is more honest
than blanking it or than describing a menu row as though it were a file. Say that in a comment.

`onClose`, so that escaping, clicking away, or a tool closing itself clears the panel state. Without
this an escape out of an open panel leaves the state set and the next chooser opened anywhere comes
up showing stale panel rows. That is the worst failure available here, so it gets a unit case of
its own.

### Filtering

Read `config.matcher` at decoration time. Where it is `false` the supplier owns filtering, so the
panel filters its own rows itself, a plain case insensitive substring against the title. Otherwise
it answers all of them and lets the instance's own matcher rank, and every panel row carries
`filterText` set to its title so the matcher has something stable to work against.

### Opening

`toggle` closes the panel when it is open. Otherwise it finds the first recorded instance answering
`isShowing`, and does nothing at all when none does, since the chord being pressed with no chooser
open is ordinary rather than a mistake. Say in a comment that first showing wins, and that this is
the same rule and the same unproven assumption `activeChooser` in the root already runs on.

It then captures the highlighted item and the highlighted row number, asks `rowsFor` for the live
context's rows, sets its state and calls `refresh(true)` on the instance.

**The panel opens even when the context has no verb at all**, showing only Back. Nine of the twelve
contexts are in that position today and the phase's own gate names it. An empty list is the one
thing it must never show.

### Choosing a row, and the deferral this needs

Back closes the panel and returns true.

A verb row records the action, marks the panel closed, and returns true. The rest happens on a
continuation scheduled with `hs.timer.doAfter(0, ...)`, which puts the highlight back on the
captured row and then runs the action.

**Comment the deferral thoroughly, because it looks removable and is not.** `_intercept` in
`providers/native.lua` calls `refresh(true)` itself the moment a handler answers true, and it does
that after the handler has returned. So anything the handler does to the highlight is undone a
moment later. Answering false instead is not available, because that lets the row complete and
tears the chooser down, and six of the ten verbs must leave it open. So the restore is scheduled to
run after the atom's own rebuild, which is the only order that works.

The continuation checks the instance is still showing before it touches anything. If it is not,
warn naming the action and run nothing, since acting on a selection nobody can see is worse than
not acting.

**Why this is worth the trouble.** The action then runs through exactly the same `contextActions`
entry the chord runs, against exactly the row the chord would have acted on, because the list and
the highlight are both back where they were before the panel opened. The panel and the chord cannot
disagree about what a verb does, which is the same argument the design makes for the panel and the
chord not disagreeing about what a verb is called.

## The chord

Hyper and period, settled in phase 0.

`config/keys.lua` gains one shared binding, declared once and folded into every context by that
file itself, at the bottom, commented as the seam. One source rather than twelve copies, and the
three consumers that walk `hyperContexts`, the binding loop, `footerFor`, and `test/inventory.lua`,
then all see it without being taught anything.

Its action is a name of your choosing that reads as opening the panel. The root adds one entry for
it to `contextActions`, calling `spoon.ActionPanel:toggle()`, and one entry to `actionKinds`.

**Classify it as navigation, and widen what navigation means to match.** The panel must not list
its own way in among the verbs it offers. The kinds set has two members and adding a third would
mean a new branch in `verbsIn`, which is not worth it for one binding. So navigation becomes every
binding the panel does not list, the shared movement plus the panel's own chord, and both the
comment above `obj.kinds` and the `CLAUDE.md` beside it say that rather than the narrower thing
they say now. A stale definition is exactly the defect packet one's rework already fixed once.

## The rows, built in the root

`rowsFor(contextName)` lives in the root, beside `footerFor`, and **shares its helpers rather than
copying them**. `footerFor` already turns a binding into a label and a chord badge, already applies
`bindingApplies`, and already asks `liveHintLabels` for a wording that changes with the situation.
The panel and the docked hint bar reading the same code is the whole reason a panel built this way
cannot drift from the chord it prints. Report what you shared and what you could not.

It applies `bindingApplies`, the wiring time filter, and it does not apply `bindingActive`. Say in a
comment that no verb in `config/keys.lua` carries a `when` today, that this is why the live filter
is not applied, and that adding one would mean teaching the panel about it. That is a real
limitation stated once rather than a predicate with no caller, which this repository's own design
rules reject.

The Back row belongs to the panel rather than to the root, since Back is the panel's own mechanism
and no context declares it. Give it the Backspace glyph as its chord, since Backspace also goes
back and the row is the honest place to say so.

## The measurement

`rowsFor` takes a context name rather than reading the live one precisely so that
`test/inventory.lua` can ask it for all twelve without a chooser being open. Add a section
recording, per context, the rows the panel would show, with the title and the chord as they would
be rendered. That measures the presentation end to end, through the same code the panel runs, and
it is what packet three will be gated against.

Three sections change and no others. `hypercontexts` gains twelve binding lines for the shared
chord. `hyperkey` gains the period key. The new panel rows section appears. **The `actionpanel`
verbs section from packet one must be byte identical**, since nothing here changes what a verb is,
and so must `choosers`, `tools`, `scopes`, `launcherrows`, `hotkeys`, and the spoon list.

## What the numbers have to be

Nine contexts show exactly one row, Back alone. The clipboard shows three, `processes` four.

File search depends on whether `bindingApplies` keeps `peekPreview`, which carries
`needs = "askedPreview"` and so depends on which preview provider this root chose. Either answer is
correct. Report which way it went and report the file search row list in full, then **check it
against what the docked hint bar shows for the same context**, whose verb rows must be exactly the
same set. If those two disagree, stop and tell me, because then the sharing above did not actually
happen.

## What not to change

Do not touch any file under `Spoons/Olm.spoon/plugins`. Do not touch the launcher, `QueryScope`,
`lib/registry.lua`, the registrations, `actions.rowIntercept`, the hosted path, `hyperActions`, or
`lib/panel.lua`. Do not change `HyperKey`. Do not change what `verbsIn` answers or what any action
classifies as, apart from the one new entry for the chord. Do not add an unbind to anything. Do not
change any existing binding, any existing description, or any of the twelve `Chooser.new` call
sites.

## Gates

`luac -p` parses every touched file.

`test/units.sh` from `dotfiles/hammerspoon/.hammerspoon` passes. It is 163 assertions today. The
decoration is testable without a live chooser, since `decorate` only wraps functions. Build a fake
config carrying all six, and a fake instance answering `isShowing`, `selectedItem`, `selectedRow`,
`selectRow` and `refresh`, then drive the whole cycle. Cover at least the supplier answering panel
rows while open and the original's rows while closed, an original `intercept` and `back` still
reached when the panel is closed, a chooser with no `intercept` and no `back` of its own gaining
both, the captured row being what `selectRow` is later asked for, `onHighlight` not reaching the
original while open, `onClose` clearing the state, a panel row reaching `onSelect` warning rather
than reaching the original, and a context with no verbs answering exactly one row. Report the
assertion count before and after.

`src/check-dependencies.sh` from the repository root passes with no new warnings, and the tree is
clean afterwards.

`test/inventory.sh --check` three times, five minute timeout on each. Print the new section in
full, print the `hyperkey` line for the period key, and print one of the twelve new binding lines.

Do not live test this yourself and do not take the devlock. The user tests it.

## Deliverable

This packet committed first. Then the two atom accessors and the `configure` door, alone, with
nothing using them yet. Then the panel's runtime with its unit cases. Then the chord and the root's
rows and wiring. Then the inventory and the golden together. Then the documentation. Small commits.
Every message ends after a blank line with

    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>

and every subject has the form scope subject with no colon after the scope. Do not merge.

Documentation extends `Spoons/Olm.spoon/host/actionpanel/CLAUDE.md` with what the panel is, the
decorator shape and why it is installed at the one seam rather than at twelve call sites, what each
wrapped function is for, why the highlight is captured and restored, why the deferral cannot be
removed, and the widened meaning of navigation. `Spoons/Olm.spoon/CLAUDE.md` and the hammerspoon
`CLAUDE.md` may carry a sentence about the chooser contract or about a hosted list not carrying a
tool's verbs that this packet makes stale, so grep for one and correct it if it exists. The
hammerspoon `CLAUDE.md` has a short paragraph for both Launcher and QueryScope and none for
ActionPanel, which packet one deliberately left, so add it now.

Report the commit hashes, each gate's real numbers, the twelve row counts, the file search row
list and its comparison against the hint bar, the new inventory section in full, and anything in
this packet that did not survive contact with the code, flagged loudly. If a decision here turns
out wrong once you can see the code, stop and say so rather than choosing for yourself.

Every line you author follows the repository writing rules, no colons, no semicolons, no hyphens or
dashes, periods and commas only, plain flowing prose rather than bullet lists. Copied names and
existing identifiers keep their form.

## Hazards

The ordering hazard bit three times in phase seven. Every name inside a closure must have its
`local` statement lexically above it or Lua resolves it to a nil global in silence. The wrapping
here is all closures, so this is the packet most exposed to it.

Silence where a warning belongs produced six of ten review findings in phase seven. A legitimate
absence may be silent, the chord pressed with nothing open, a context with no verbs. A mistake must
name itself, a panel row reaching a tool's own handler, a continuation finding the chooser gone.

Never run `bin/hs-devlock` yourself. `test/inventory.sh` takes the lock and gives it back, and
killing it mid run strands the lock and blocks the user, which is why it gets five minutes. Never
call `hs.logger.setGlobalLogLevel`, it floods every logger and wedges the ipc port. Never pass an
angle bracket inside inline Lua to `hs -c`. Never call `hs.reload` inline, schedule it with
`hs.timer.doAfter` and poll `hs.configdir`. A console read can take minutes and is not hung. Never
run `git reset`, `git checkout` on a path, or `git stash` to clean the tree, read `git status` and
report instead. Never write an absolute path into any file.

This packet changes the most visible thing in the configuration, a key that now does something in
every chooser. A mistake here is one the user feels immediately rather than one a gate catches, so
wire nothing you cannot see in the snapshot.
