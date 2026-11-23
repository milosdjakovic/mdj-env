# Bringing apps forward in Olm.app

Written on 2026-11-20 for step 6.2 of `docs/PLAN-STANDALONE.md`, the app toggler. It says how
focusing, cycling, hiding and placing an application move out of Hammerspoon into the app while
Hammerspoon still binds every key, which it does until step 5.3.

## What moves and what stays

**What moves is the behaviour, `lib/appfocus.lua` and the toggler's styles.** Focus or cycle, the
`hides` form that hides an app already in front, and `placement`, which sizes and centres the
window on the display it is already on once a press showed it. These are what a Hyper app key, an
app row in the launcher and a style in `config/toggles.lua` all run, and they are the first thing
the app does to another application, so they are Olm.app's first use of Accessibility.

**What stays is who presses.** Hammerspoon still binds the Hyper app keys until 5.3, and the
launcher still chooses a row in Lua, since recency and the per query memory are Lua's, step 6.1.
So both end up in one place, `lib/appfocus.lua`, and that one place hands the press to the app.
There is one seam, and both callers pass through it unchanged.

**A placement written as a Lua function stays in Lua.** A function cannot cross the socket, and
`config/toggles.lua` writes none today, so such an entry runs in Hammerspoon as before, and
everything else about that app still moves.

## How a press reaches the app

`lib/appfocus.lua` takes a forwarder from the root. When the `appToggler` switch in
`config/plugins.lua` is on, the socket is up and the app has said it may act, the forwarder sends
the notification `appRun` with the action, the bundle id, `hides` and the placement table, and the
app runs it. In every other case, the switch off, the app gone, or the app without Accessibility,
Lua runs it as before, so nothing is lost while the grant is missing.

The app says whether it may act with the notification `appsReady`, once each session opens and
again whenever its grant changes, which it checks every ten seconds as the key tap does. The flag
is dropped with the session, so a closed socket is never mistaken for a ready app.

## How the app acts

**On a queue of its own, never the main thread.** Every Accessibility call can wait on the app it
asks, up to six seconds by default for one that hangs, which is how a Hammerspoon key stalls today.
Each call on that queue is bounded to one second, so a hung app costs one key and nothing else.

**The same decisions, read the same way.** An app's windows are its `AXWindows`, a standard one is
subrole `AXStandardWindow`, a minimized one is left out, and they are ordered by window number,
`_AXUIElementGetWindow`, the same private call Hammerspoon's `hs.window:id()` stands on, so the two
orders match. Frontmost is the running application's `isActive`. A cycle steps from the app's own
focused window, or from its main window when the focused one is not a window the cycle walks, read
from the app's element in both, `hs.application:focusedWindow()` and `mainWindow()` in Lua. It used
to be the system wide focused application's focused window, and on 2026-11-23 that answered none of
Chrome's at every press, so each press started again at the first window and two windows swapped
once and then stood still, while Chrome's own focused window was right all along. Launching or
focusing goes through LaunchServices with activation, which reopens a window for a running app that
has none, as `launchOrFocusByBundleID` does. A window is focused by making it main, raising it and
making its application frontmost through Accessibility, which an app in the background may do.

**Placement keeps its timing.** A tenth of a second, then every quarter second up to twenty times
until the app has a main window and holds focus, then the frame, the screen's visible frame inset by
the padding and the window sized and anchored inside it. A newer placing press cancels an older
one's wait. The geometry is a port of the toggler's own and is checked by the app's check program.

## Shadow, beside the flip

Rule 3 of the plan. Before forwarding, Lua works out what it would have done, the same decision
`focusOrCycle` and the toggle make, its outcome and for a cycle the window it would reach, and
sends it in `appRun`. The app works out its own from what it reads and logs any difference to
`~/.olm/log/shadow-apps.jsonl`, with the counts in `shadow-apps-count.json`. After a placement the
app reads the frame back and logs one the window refused, since an app with a minimum size does
that and Hammerspoon never said so. The trial is the log empty through a day of ordinary use.

The shadow costs Lua one extra read of the app's windows per press, the same reads it made before,
and it goes when the keys move at 5.3 and Lua no longer sees the press.

## Steps

1. **6.2, this.** The seam, `appRun` and `appsReady`, `app/Sources/OlmApps`, the Accessibility
   grant declared as `olmapp-accessibility`, the shadow, `olm-apps-check`.
2. **At 5.3** the Hyper app keys are claimed by the app and run there directly, with no trip
   through Lua, and the Lua plan and its shadow go.
3. **When recency moves**, a launcher app row runs in the app on Return and tells Lua nothing.

## Open questions

1. Whether making an app frontmost through Accessibility lands focus as reliably as Hammerspoon's
   activation on macOS 27. The shadow's log and a day of use answer it.
2. Whether an app hanging under Accessibility stalls only its own press, as the bound calls are
   meant to make it.
