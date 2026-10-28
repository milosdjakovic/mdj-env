# The picker contract, written down 2026-09-11

Checklist item zero of docs/PLAN-CANVAS-CHOOSER.md. This is the reference. The work
order that makes the code match it is docs/BRIEF-CONTRACT-FREEZE.md.

## Why this exists now

`lib/chooser/init.lua` is a facade over one provider, and what a provider must offer has
never been written down anywhere except in what the two callers happen to call. That was
survivable with one provider and it stops being survivable with two, because a name the
survey missed is a name the default provider does not implement and nobody finds out until
a person opens a picker and it breaks.

Three surveys of 2026-09-11 produced this, one over every call site in the tree, one over
`lib/chooser/providers/legacy.lua` separating behaviour a caller observes from workaround
the widget forces, and one over `host/stage/init.lua` and `host/actionpanel/init.lua`
looking for code above the facade that only works for the legacy chooser. Every claim
below came from reading a line, not from reading a name.

## The shape

Strategy. `lib/chooser/init.lua` is the facade and names the concrete provider.
`host/stage/init.lua` and `host/actionpanel/init.lua` are the engine and know only this
contract. A provider is a new file plus one branch in the facade, and no consumer changes.
The contract knows nobody.

Lua has no compiled interface, so this is a documented set of required methods plus a
validation step at construction, and it cannot promise more than that. What validation
proves is presence and declared arity. What it cannot prove is that a method HONOURS its
meaning, so the semantics below are the part a person has to read and a reviewer has to
check.

## The validation rule

`lib/chooser/contract.lua` holds the required names with their arities and a
`validate(instance)` answering ok plus a reason. `Chooser.new` refuses an instance that
fails, with a phrase naming the method and what it declares rather than a bare name, the
discipline commit `3c8ad9d` gave the VPN provider contract.

Arity below counts arguments and excludes the implicit self, so a validator reading
`debug.getinfo(fn, "u").nparams` compares against the stated number plus one. A variadic
method is accepted whatever it declares, since a provider forwarding its arguments cannot
state a count. A method declaring MORE parameters than required is accepted, since
ignoring a trailing argument is that provider's own business. Only declaring too few is
refused, because that is the one shape that reads a caller's arguments in the wrong slots.

## The methods

Twenty five names. Sixteen exist today, nine are added by the contract freeze to absorb
code that reaches past the facade.

### Lifecycle

`show()` arity 0, answers nothing. Puts the picker on the configured screen, seeds an
empty query, builds rows for that empty query, puts the highlight on row one, reports its
frames through `onPositioned`, and arms whatever the configured callbacks call for. An
instance is reused across shows, so nothing may survive a hide that would make a reopen
look like the last session.

`hide()` arity 0, answers nothing. The single idempotent dismissal path. Every way a
picker can end, a selection, escape, a click outside, or a programmatic call, funnels
through it, and `onClose` fires exactly once per open however it ended. Calling it when
nothing is up is not an error.

`isShowing()` arity 0, answers a boolean. Whether the surface is genuinely on screen.
`test/world.lua` reaches this generically by duck typing through a module's `_instance`
field, so it takes no arguments and answers a plain boolean and not a truthy object.

`isActive()` arity 0, answers a boolean. Whether the provider BELIEVES it is up. This is a
different question from `isShowing`, which asks the surface, and the two disagree during
the window between a show being asked for and the surface actually appearing. The stage
gates placement on this one.

### Rows and the query

`refresh(resetRow)` arity 1, answers nothing. Asks `config.rows` again for the current
query, reranks, and redraws. A truthy `resetRow` returns the highlight to row one.

`query()` arity 0, answers the current field text as a string.

`setQuery(text)` arity 1, answers nothing. Sets the field text and leaves the caret AFTER
the text rather than leaving the text selected. That second half is the contract, not an
implementation detail. A provider that leaves the text selected means a seeded scope like
`t ` is silently replaced by the next character typed.

`setPlaceholder(text)` arity 1, answers nothing.

`setRows(n)` arity 1, answers nothing. Remembers a row count for this instance's next
show. No provider promises a live resize, and a caller wanting one today hides and shows.

`rowCount()` arity 0, answers the row count currently configured. The stage reads this once
at configure to learn the provider's own shipped default so a presentation naming no count
of its own can return to it.

### Selection

`selectNext()` and `selectPrev()`, arity 0, answer nothing. Move the highlight by one.

What happens at the ends is deliberately NOT fixed by this contract. The legacy provider
clamps and says so in its own comment. The default provider wraps, by an explicit decision
recorded in docs/BRIEF-CANVAS-LIST.md. This is a visible difference between two backends
and it is intentional rather than an oversight, so a provider states its own end policy in
its own header and neither one is wrong against this document.

`selectRow(n)` arity 1, answers nothing. Clamps into range and ignores a nil argument
rather than raising.

`selectedRow()` arity 0, answers the highlighted row number or nil.

`selectedItem()` arity 0, answers the caller's own opaque `item` from the highlighted row,
or nil.

`insertSelected()` arity 0, answers nothing. Behaves exactly as Return does, including
asking `intercept` first and honouring a disabled row.

### Measurement

`textBudget()` arity 0, answers the pixel room a row's text has on the screen this picker
will open on. Consumers format against it, deciding for themselves how much of a path they
can keep before it would be cut, so it is a number a caller builds logic on rather than a
hint. It is resolved per open, since a different screen answers differently.

`textWidth(str, which)` arity 2, answers the rendered pixel width of a string. `which`
selects the title size or the subtitle size. The legacy implementation is a UTF8 safe per
character memoised sum that over counts by roughly zero point seven percent, chosen because
over counting shortens a string marginally early which looks like nothing, while under
counting lets a string through that then gets cut. Nothing in that function is coupled to
`hs.chooser`, so it is shared by every provider rather than written twice.

### Placement

`reposition(paneWidth)` arity 1, answers a chooser frame and a companion frame, the second
nil when there is no companion, both in absolute screen points. Recentres the picker and
its companion for the given pane width, updates the provider's own `paneFrames`, and
answers nil when it is not up. This is the method that replaces the stage reaching into
`hs.application`, hunting a window titled Chooser, and calling `setTopLeft` on it. Only a
provider knows how its own surface is drawn and moved.

`settleDelay()` arity 0, answers seconds. How long after `show()` returns the provider's
own placement is still moving. The legacy provider answers its own post show correction
delay. A provider whose placement is final on the first frame answers zero. The stage waits
this out before repositioning on a swap, so it never computes a frame from a surface that is
about to move under it.

### Live policy the stage pushes per presentation

Each of the three below exists because a presentation declares a policy and the shared
instance has to take it before the next show, and today the stage writes them as raw
fields on the provider's private struct.

`matcher()` arity 0, answers the current matching strategy, a `match(query, hay)` function,
or `false` meaning the supplier owns filtering, or nil meaning no matching. The action panel
reads this live inside its own wrapped `rows` closure, because `decorate` runs once at the
shared instance's single construction, long before any presentation exists to capture. Its
second answer is the search set beside the strategy, see `setMatcher`.

`setMatcher(m, search)` arity 1, answers nothing. `false` and nil are different answers and both
must survive the round trip. `search`, optional since phase three of the unified search, is the
presentation's `{ searchText, rowLimit }`, handed to `lib/chooser/rank.lua`'s `apply` with the
strategy on every rank, and nil clears it. The stage writes both together before every show, so
a presentation declaring neither leaves nothing of the one before it behind.

`titleLineBreak()` arity 0, answers the truncation mode a title takes, `truncateTail` or
`truncateMiddle`. Subtitles are always cut at the tail.

`setTitleLineBreak(mode)` arity 1, answers nothing.

`setPaneWidth(w)` arity 1, answers nothing. `true` means the companion inherits the
picker's own resolved width, a number overrides it, nil or zero means no companion. Every
answer is capped by the provider's own pane maximum.

## The default provider is an engine and a view, since 2026-10-28

The default provider is two halves joined at a second, smaller contract, the Bridge pattern.
`lib/chooser/engine/init.lua` is the engine. It owns every rule this document states and all of a
picker's state, implements the twenty five methods above and the extras the stage calls,
`setPosture`, `posture`, `toggleKeys` and `closeKeys`, and answers the static `uses`. A view owns
only drawing and raw input. `lib/chooser/providers/default/canvas.lua` is the canvas view, and
`lib/chooser/providers/default/init.lua` composes the two and is the provider the facade names, so
nothing above the facade changed. The split exists so a second view, a native panel, stands under
the same engine instead of beside a copy of its rules, `decisions/olm-swift-chooser.md`.

`lib/chooser/view.lua` holds the view contract the way `lib/chooser/contract.lua` holds this one,
the required names with their arities and a `validate(view)` the engine runs at construction, by
the same rules. Every name below is required.

`restyle()` resolves the view's styles from the engine's scene, on every show. `place(rects)` puts
the surface at `rects.canvas`. `presentRows(rows)` answers the ranked rows in the form the view
draws them, same length and order, each keeping `item` and `enabled`, and the engine holds that and
never ranks it again. `text()` answers the field's text. `setText(text)` replaces it with the caret
after it and reports the change back before returning. `feedKey(event)` handles a key heard by
another route, the focus hold's relay. `redraw()` draws what the scene says now. `show()` reveals
the surface. `start()` begins reading keys and the pointer and starts the view's own timers.
`stop()` ends the input first and the timers after. `stopScroll()` ends a scroll animation.
`hide()` hides the surface and forgets the pointer. `isVisible()` answers a plain boolean.

A view calls back into the engine through these. `scene()` answers what to draw, the rects, both
layouts, the tokens and type, the list model's state, the ranked query, the placeholder, the
posture, the footer model and whether the key panel is open. `fieldChanged(text)` after every
change the field reports. `highlightIndex`, `chooseIndex` and `rightClickIndex` for the pointer on
a row, `toggleKeys` for the key button, `scrollTo` and `scrollBy` for the viewport,
`companionScroll` for a scroll over the companion, and `hide` for a press outside.

The field's text editing is the view's, so a view whose field edits natively, with its own caret,
selection, undo and input methods, fits. The engine never edits text. It reads it, sets it, and
is told when it changes. A key down is asked of the engine in a fixed order around the field's own
editing. `dismissKey(event)` first, for Escape and its autorepeat, before anything can yield it.
`yieldsKey(event)` next, true meaning the key passes on unclaimed. `listKey(event)` next, true
meaning the open list took it. Then the field edits or types, with `emptyBackspace()` standing in
for a backward delete on an empty field with nothing selected. `leftoverKey(event)` last, for Up,
Down, Return, keypad Enter and Command with a digit. The canvas view's field asks in exactly this
order already, in `field/input.lua`, and a native view asks the same way.

The swift provider is the second composition, `lib/chooser/providers/swift/init.lua`, the same
engine with a native view, `providers/swift/view.lua`, over a panel Olm compiles in Swift. It
satisfies this contract through the engine with no extension to the view contract, and serves the
default provider until its library is built, see the Olm `AGENTS.md` section on it.

Three modules the engine reads still sit beside the canvas view, and the engine loads them from
there in one place it names as the seam. `geometry.lua` and `list/model.lua` are pure.
`footer.lua` is the view's drawing of the action bar, and the engine reads only its height.

## The config table

`Chooser.new(config)` accepts these. Read live means read again on a later event rather
than captured once at construction, and the distinction is load bearing, since the one
caller builds a single instance for the life of the process and every presentation after
that reaches it through a live read.

`theme`, a table of `dark` and `light`, each carrying `bgDark`, `titleColor`, `subColor`
and `preview`. Reselected on every show against the live system appearance, so a picker
tracks a light and dark switch at its next open.

`screen`, a function answering an `hs.screen`. Called once per show. Falls back to the
module default injected through `Chooser.configure`, then to the main screen.

`rows`, a function of the query answering the candidate list. Required. Called on show, on
refresh, and on every keystroke.

`matcher`, captured once at construction into the live field the accessors above now front.
Afterwards the accessors are the only route.

`onSelect(item)`, `intercept(item, enabled)`, `back()`, `onHighlight(item)`, `onClose()`,
`onActivity()`, `onPositioned(chooserFrame, companionFrame)`, all read live.

`onScroll(points)` is read when the scroll watcher is installed, which happens on show only
and not on a bare swap or refresh.

`onRightClick(item, row)` is read exactly ONCE, at construction, and never again even on a
later show. This asymmetry with `onScroll` is recorded as a past defect in the stage's own
comment. A second provider either reproduces it or the composition root is told it is no
longer safe to assume, and reproducing a known defect to preserve bug compatibility is not
the right answer, so the default provider reads it live and this document says so.

`placeholder`, a string, read once at construction. `setPlaceholder` is the live route and
the stage overwrites the constructed value on its very first show.

`layout`, merged once at construction over the provider's own defaults. The merged table is
the thing the accessors above front. The current caller passes no layout at all.

`pollInterval`, seconds. Live but dead, nothing in the tree sets it. It is legacy only, an
interval for a highlight poll that exists because `hs.chooser` has no highlight callback. A
default provider has no poll and ignores the key.

`provider`, accepted and ignored, the seam this whole track walks through.

## A row

What `config.rows` answers, one table per row. `title`, `subTitle`, `image`, `enabled`
where absent means enabled, `item` carried back untouched to `onSelect` and `selectedItem`,
and `filterText` which replaces title plus subtitle as the haystack when present. Rows must
be plain serializable data, a constraint several plugins already record in their own
comments.

## What is deliberately not in the contract

`activeTheme()` had no caller anywhere in the tree, confirmed by exhaustive search. It was
built so a consumer could style its own companion from `theme.preview` and no consumer ever
did. It was deleted from the legacy provider on 2026 10 14 along with the dead `preview` set.

`close()`, an alias for `hide`, likewise has no caller. The composition root's own close
binding routes to `hide`. Same treatment.

`paneFrames` as a field. It is written by the provider and read by the provider's own
watchers. Nothing outside needs it once `reposition` answers frames directly.

Everything under `layout` other than what the accessors above expose. `gap`, `paneMaxW`,
`width`, `widthPct`, `rowH`, `baseH`, `topFrac`, `minVPad`, `font`, `titleSize` and
`subSize` are each provider's own business, and the stage's current reads of `gap` and
`paneMaxW` disappear with `reposition`.

## Divergences a person should expect to see

Movement at the ends, clamping on legacy and wrapping on default, stated above.

Proportions. The default chooser does not copy the legacy widget's row height or field
height, which came from a compiled nib rather than from a design. It is a uniform sixteen
point type size with a thirty eight point field and a thirty eight point row, decided by
hand across five rounds.

Input method composition and the accessibility tree. Neither exists on a canvas surface.
Option e then e types a plain e, measured rather than assumed. The default chooser cannot be
driven through the accessibility route the existing probes use, so a probe against it
reports another way.
