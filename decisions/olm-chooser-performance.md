# Olm chooser performance, scrolling and memory

Status. The swift chooser scrolls at 3 frame drops in an 8 second flick and Hammerspoon starts at 44 MB. The canvas chooser's one remaining fault is fixed on the canvas-glass-layout branch and waits on a live measure, and the legacy chooser carries none that this repository can fix.

## Now

Five faults were found and fixed on 2026-10-30, each measured rather than reasoned about. Which
chooser each one reaches is the point of this file, since the three providers share the engine,
the list model and the kit and differ in how they draw.

| Fault | swift | canvas (default) | legacy (hs.chooser) |
|---|---|---|---|
| Hidden canvas window per text measure | fixed, shared kit | fixed, field through the kit, not yet measured live | not affected |
| Lua and AppKit fighting over one scroll | fixed | not affected | not affected |
| Cursor set again on every scroll frame | fixed | not measured | not ours to fix |
| A list drawn under an empty band after a filter | fixed | not affected | not affected |
| Command and a digit moving with the scroll | fixed, shared model | fixed, shared model | not affected |

**A hidden canvas window per text measure.** `hs.drawing.getTextDrawingSize` builds a hidden
`hs.canvas` window for every call, and the window outlives its `delete` until a reload. The kit's
whole string measure, `lib/ui/measure.lua` `exact`, was uncached, so every redraw measured the
same strings again. It is cached now and emptied at 512 strings, with the same values from the
same call, which fixes every surface drawn through the kit, all three choosers' bars and panels
among them. The canvas chooser's own field, `providers/default/field/render.lua`, still measures
the text before the caret through that call on every draw, and the canvas view redraws the field
on each half second caret blink, on every keystroke and on every tick of its 60 Hz scroll ease,
so with text typed it leaves a window behind at up to sixty a second while it scrolls. The legacy
chooser measures through the kit's per character `width`, which was always memoised, and its
rows are Hammerspoon's own `hs.chooser`, so it makes no such window.

**Two owners of one scroll.** The swift list reported every scroll frame to Lua and applied the
scrollTop Lua sent back, so a reversed flick landed late and jumped. The native list now owns its
scroll and its highlight, and Lua hears both afterwards. The canvas chooser has one owner by
construction, since Lua draws it and scrolls it, and the legacy one is AppKit's alone.

**The cursor set again on every frame.** As rows pass under a still pointer, AppKit sends a
cursor update up every superview to the window on every frame, which sets the arrow again, and
on this machine setting the cursor goes through the accessibility cursor generator, which draws
the cursor image anew. That was a third of the main thread during a swift scroll. `ListView`
ends the update itself. The canvas chooser is `hs.canvas` windows and was never profiled while
scrolling, so whether it pays the same is unknown. The legacy chooser is Hammerspoon's own
table in Hammerspoon's own window, so if it pays it, the fix belongs upstream.

**An empty band after a filter.** A swift list filtered after the highlight scrolled it down
showed its rows several rows down. `NSClipView` `scroll(to:)` from past the end of a shortened
table landed at minus 200 points once the table was laid out, and the origin is now set outright.
It was a fault of the native scroll view, which neither other chooser uses.

**Command and a digit.** The digits counted from the topmost row on screen and renumbered on every
scroll. They name the first nine rows now, `rowAtSlot` in `providers/default/list/model.lua`,
which the swift and canvas choosers both read. `hs.chooser` numbers its own rows and was not
touched.

The probe that found them stays in the swift library, `Perf` in `native/Entry.swift`, reached as
`perf("start")`, `perf("read")` and `perf("stop")` on the swift provider module. It notes every
gap in the main run loop over 25 ms and every call into Lua over 2 ms. A `sample` of Hammerspoon
taken the moment a live scroll begins names what a stall is spent on. A tracker that wraps
`hs.canvas.new` from the console names who makes canvases and whether each is deleted. Measure
with these before changing anything here.

## Rejected

- **2026-10-30, icons as the cause of the stutter.** The first three rounds assumed it, and
  paused, batched and moved icon work around the scroll. The probe then showed no Lua call at all
  during a stalling scroll, and the sample showed the cursor. An SF symbol loads from its cached
  PNG in 0.66 ms and an app icon in 0.64 ms.
- **2026-10-30, pausing all icon work for the length of a scroll.** It kept Lua off the main
  thread, and it left every row a flick reached blank until the flick ended. The list asks for the
  icons on screen and ahead of its velocity instead, a dozen at most per ask.
- **2026-10-30, turning the swift list's rubber band off.** It hid the ghost of two owners moving
  one viewport, and it felt unlike every other list on the machine. The fight was fixed and the
  band came back.
- **2026-10-30, leaving the kit's whole string measure uncached so a toast stream cannot grow a
  cache.** The cost was a hidden window per call, 632 alive after fifteen minutes. A cache emptied
  at a bound answers the same worry.
- **2026-10-30, a native text measure from the swift library in place of
  `hs.drawing.getTextDrawingSize`.** It would make no window at all, and it could differ from what
  Hammerspoon answers by a point, which moves every layout the kit places. The cache made the
  calls rare enough.

## Log

### 2026-10-30 17:20

The swift list scrolled choppily with a ghost bounce. Every frame reported to Lua and every Lua
redraw sent its scrollTop back. Reports were coalesced, scrollTop sent only when the engine moved
the viewport, and the rubber band allowed again. `decisions/olm-chooser-keys.md` has the round by
round entries for the whole day.

### 2026-10-30 18:15

Measured. A probe in the swift library and a `sample` taken as a live scroll began showed the
chooser making no Lua call during a stalling scroll, and a third of every frame setting the
cursor through the accessibility cursor generator. The list ends cursor updates and reuses row
views. Frame drops over ten seconds of flicking went from 129 to 64.

### 2026-10-30 18:40

Hammerspoon held about 200 MB. A tracker on `hs.canvas.new` found the kit's uncached whole string
measure making 454 hidden windows in the first minute after a reload, 353 alive. Cached and
bounded, commit d7a26b00, it made none in a minute and the footprint fell to 169 MB. The swift
list's work landed as commit 3cc2beaf, with icons asked ahead of the scroll's velocity. One eight
second flick then noted 3 frame drops, the worst 45 ms.

### 2026-10-30 19:04

The off screen checks moved into `test/swiftpane.swift`, commit 53ee283e. Putting `scroll(to:)`
back fails the empty band case at minus 200 points.

### 2026-10-30 19:15

A fresh launch of Hammerspoon measured 44 MB, a Lua heap of 11.7 MB, no canvas window alive and
one swift library loaded. The rest of the 169 MB was the day's twenty reloads, since a loaded
library is never unloaded. Each fault was then checked against the other two choosers for this
file. The canvas field's caret measure is the one still open, found by reading
`providers/default/field/render.lua` and the canvas view's redraws, not by measuring it live.

### 2026-10-30 19:50

The offline gates ran on this work for the first time, once Jelenas-MacBook-Pro took `lua5.4`
through mise. The Olm dry gate checked 35 plugins with 0 findings, 40 accepted and 0 warnings,
and every offline golden matches, so commits d7a26b00, 3cc2beaf and 53ee283e pass every gate.

### 2026-10-30 19:47

The canvas field's caret measure goes through the kit's cached `exact` now, handed in as
`style.measure` by the canvas view, on the canvas-glass-layout branch. Same call, same values, so
the caret cannot move. The standalone field probe hands no measurer and keeps the direct call.
The dry gate and the goldens pass. The tracker on `hs.canvas.new` has not been run against it
live yet, and the table says so until it has.
