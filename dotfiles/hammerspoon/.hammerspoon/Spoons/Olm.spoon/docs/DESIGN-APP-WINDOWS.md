# The window manager in Olm.app, step 6.3

Step 6.3 of `docs/PLAN-STANDALONE.md`. META's keys are the app's since 5.3, and each window row still
runs in Hammerspoon, asked by `runKey`. This step moves the rows themselves, so a window moves with
no Hammerspoon in the path. It goes in two parts, the way 6.2 did.

## 6.3a, the geometry as one pure function, built 2026-11-23

`plugins/windowmanager/plan.lua` holds every placement the plugin makes, `plan(action, s)`, over the
focused window's frame, its screen, every screen with its visible frame, the margins, the gap, the
`windowSizing` block, the hold depth, an exact size or a target screen, and what the window
remembers of each screen. It answers the frame to write, the screen it lands on, the frame to
remember for the screen it leaves, and whether the write is read back, which only a move between
screens needs. The plugin's methods gather that from `hs`, call it and write the answer, so the
plugin behaves as before with its geometry stated once.

`test/fixtures/windows/plan.json` pins it, 72 cases recorded from the Lua by
`test/windowplan-record.lua`, every action on a laptop, with a gap and on an ultrawide, the moves
against each edge and with a window wider than its canvas, the resizes in landscape and portrait,
against an edge and at the floor, the display moves wrapping over three screens, a remembered frame
that fits and one that does not, and a window with no id. `test/fixtures.lua` runs them in Lua and
`olm-fixtures` runs them against `OlmApps/WindowPlan.swift`, the port, numbers within a millionth.
Lua's modulo floors where Swift's truncates, so the port wraps the previous screen by hand.

## 6.3b, the app places the window

The app reads the focused window over Accessibility, `AXFocusedWindow` of the frontmost
application, its position and size in the same top left space, each screen's visible frame and
uuid, and the window manager's settings from a share the bridge writes, applies the plan, and for a
move between screens reads the frame back and writes size, position and size again on a miss, as
`hs.window`'s workaround does. The round trip memory lives in the app. Hide Others is
`NSRunningApplication.hide` over the regular apps. Its shadow computes the plan beside each run
Hammerspoon makes and logs a difference, and the switch hands META's window rows to the app.

## Rejected

- **Porting the plugin method by method into Swift with no shared statement.** 2026-11-23. The
  geometry carries a dozen decisions, the long edge share, the floor per axis, the clamp on one axis,
  the remembered frame checked on four edges, and two copies would drift with nothing to say so.
  One pure function in each language, held to one recording, keeps them the same.
