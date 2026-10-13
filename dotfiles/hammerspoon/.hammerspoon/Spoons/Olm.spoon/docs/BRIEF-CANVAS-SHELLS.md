# Canvas surface and mouse brief, phase three b of the canvas chooser track, 2026-09-11

Part two of phase three of docs/PLAN-CANVAS-CHOOSER.md. Read docs/CONTRACT-PICKER.md and
docs/BRIEF-CANVAS-GEOMETRY.md first. Decisions were made by the orchestrator. Follow them
rather than relitigating them, and where this brief and the code disagree, stop and report
rather than improvising.

These are the two side effecting shells the canvas picker needs, one owning a window and one
owning an event tap. Neither holds any policy. Neither knows what a row is, what a query is,
or that a picker exists. That is the same division `lib/chooser/providers/canvas/field/`
already takes, where `input.lua` is the only file touching `hs.eventtap` and `render.lua`
answers elements without owning a surface, and it is what keeps all of this placeable inside
the three pane window later.

Do not call either of these Strategy. A surface that draws what it is handed is not an
interchangeable policy behind a contract, it is a shell around a resource.

## 1. lib/chooser/providers/canvas/surface.lua

A window this configuration owns, drawn with `hs.canvas`, which never takes focus.

MIRROR `lib/panel.lua`'s own canvas setup rather than inventing one. Read how it creates its
canvas, what window level it uses, what behaviours it sets, and how it prepends
`CanvasPanel.surfaceElements` for the chrome. That file documents the second supported use,
a consumer owning its own canvas and prepending the same chrome, and the clipboard preview
already takes it. This provider is the third such consumer, so it looks identical and nothing
draws the surface a second way.

The API.

`Surface.new(opts)` where `opts.panel` is the CanvasPanel module, injected rather than
required by path here, and `opts.style` is the surface style table or nil to take the panel's
own configured default. It creates nothing yet.

`instance:setFrame(rect)` places and sizes the window in absolute screen points. It is legal
while visible and it is the thing that makes width, height and position live on this backend
where they cost a hide and a show on the native one. Say that in the file.

`instance:draw(elements)` replaces the canvas contents with the chrome for the current frame
followed by the elements it was handed, in that order. It appends nothing of its own after
them. The chrome is resolved on every draw rather than cached, so a light and dark switch is
picked up, which is what `lib/panel.lua` already does and for the same reason.

`instance:show()`, `instance:hide()`, `instance:isVisible()`, `instance:delete()`.

Nothing in this file decides what to draw, measures text, reads a theme colour beyond the
surface style, or knows a row from a caret.

State the focus guarantee in the header as a guarantee, not a hope. A canvas never becomes
the key window, so the frontmost application keeps its focus and keeps receiving keys, which
is the whole reason this backend exists and is also the reason the mouse and keyboard shells
have to claim events explicitly rather than relying on focus to route them.

## 2. lib/chooser/providers/canvas/mouse.lua

The only file in this provider that touches `hs.eventtap` for mouse events, the same way
`field/input.lua` is the only one that touches it for keys.

`Mouse.new(opts)` taking callbacks and nothing else. Every callback receives a point in
absolute screen coordinates, the same space `geometry.resolve` answers frames in.

    onDown(point, button)     button is "left" or "right"
    onUp(point, button)
    onMove(point)
    onScroll(point, dy, continuous)

Every callback ANSWERS TRUE TO CLAIM the event and anything else to let it through. This is
the load bearing decision in this file and it needs to be stated there. A canvas never takes
focus, so an unclaimed click reaches whatever application is underneath, and a picker that
lets its own clicks through would select a row and click the app behind it in the same
gesture. Equally, a picker that claimed every click on the whole screen would make the rest
of the machine unusable while it is open, so the decision cannot live here, it belongs to the
consumer that knows where its own surface is.

`instance:start()`, `instance:stop()`, `instance:isRunning()`. Armed on show and stopped on
hide, never left running. Commit `1ccab6f` is this configuration's own record of what a tap
left believed active costs on this machine. Nothing in a tap callback may raise, so each
consumer callback is invoked inside a `pcall` and a failure reports and lets the event
through rather than abandoning the callback halfway.

Scrolling. `Spoons/Olm.spoon/test/probe-canvasfield.lua` already carries a working scroll tap
built and hand judged in round five of the list. LIFT IT rather than writing a second one,
and say in the file that it came from there. It distinguishes a trackpad from a wheel through
`hs.eventtap.event.properties.scrollWheelEventIsContinuous`, the same property the native
provider's own companion pane watcher uses, and reports continuous point deltas for the one
and notch deltas for the other. `continuous` is handed to the consumer because the easing
policy, follow a trackpad directly and ease a wheel, is the consumer's decision and not this
file's.

`onMove` exists so the picker can highlight the row under the pointer, which the native
widget does for free and whose absence would read as this backend being broken. Install the
mouse moved watch only when `onMove` is supplied, the same shape the native provider uses for
`onHighlight`, so a consumer that does not want it pays nothing.

## What not to do

Do not create `lib/chooser/providers/canvas/init.lua`, the provider itself, that is part
three of this phase and another builder will write it against these two files. Do not touch
anything under `field/` or `list/`. Do not touch `lib/chooser/init.lua`,
`lib/chooser/contract.lua`, `lib/chooser/providers/native.lua`, `host/stage/init.lua` or
`host/actionpanel/init.lua`, another builder holds those. Do not touch `lib/panel.lua`, read
it and follow it. Do not touch any plugin, any manifest, or the composition root. Do not take
the devlock, restow, or reload the live config. Do not drive the screen or the keyboard.

## What to deliver

The two files, plus a live probe at `Spoons/Olm.spoon/test/probe-canvasshells.lua` following
the convention `probe-canvasfield.lua` already sets, loaded into the RUNNING Hammerspoon by
`dofile` over the instance that is already up. It draws a plain surface with a couple of
shapes on it, moves and resizes it on a timer to prove `setFrame` is live, and prints one
line per mouse event it sees with the point, the button, and for a scroll the delta and
whether it was continuous. It claims clicks inside its own frame and lets clicks outside
through, which is the exact behaviour the provider will need and the only way to judge that
the claiming rule works. It dismisses on escape through its own small key tap and arms a hard
watchdog that tears everything down after a bounded time whatever else has happened, read
from a global the way `probe-canvasfield.lua` reads `olmCanvasFieldProbeSeconds`, clamped the
same way. A mistake in a mouse tap must not leave a machine unclickable.

No offline unit case. There is nothing pure in either file, both are shells around resources,
and a case built on a fake `hs` would prove only that the fake was written to match. Say that
in your report rather than adding a case to raise the count.

## Acceptance

`./test/units.sh` shows the suite total UNCHANGED and no existing case changing its result,
since this part adds no offline case. `luac -p` clean on every file touched.
`src/check-dependencies.sh` clean. DO NOT run the probe yourself, it puts a surface on a
person's screen and takes over their mouse, and the user says when a live test starts. Hand it
over ready to run and say what the command is.

Report anything where this brief resists the code rather than bending either side quietly.

## Writing style, a hard requirement

Never use em dashes, en dashes, or hyphens in prose. Only periods and commas, no colons and
no semicolons. This applies to every code comment you write and to your report. It does not
apply to code itself or to file paths.
