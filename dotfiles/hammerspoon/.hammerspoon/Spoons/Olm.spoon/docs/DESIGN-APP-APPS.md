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

## Where a shown window goes, an app's own place

Asked by Milos on 2026-11-23. Each row of the Applications page opens a Customize sheet holding the
app's mode and its place, which the toggler hands to the app in `appRun` in place of the style's
placement. Placement fires as before, on a press that launched or focused the app.

- **Display.** Where it was, the default, leaves the window on the display it stands on, so moving
  the window moves where it shows next time. Active is the display of the window that was in front
  when the key was pressed, and Pointer the display under the pointer then, both read at the press,
  before the app comes forward. Built-in and external are not offered here, Milos's choice.
- **Position.** Kept, the default, or centred. A kept window moved to another display keeps its
  distance from that display's corner and is moved in only as far as it has to be to fit.
- **Size.** Kept, the default, or set in points or a percent of the display's visible frame, then
  held between the least and the most, then to the display less the padding. The padding wins over
  the least, so the window never reaches a display's edge. 90 percent with a most of 2400 by 1350
  grows to that on a large display and fills a small one less the padding.

The rule is `Placement.place(current:from:to:)` in `OlmApps/Placement.swift`, checked by
`olm-apps-check`. It answers nothing when the window already stands where it would go, so nothing is
written. The sheet shows what the place comes to on every display connected now, from the same rule.
A place the same as what the app would do with none, its style's placement or nothing, is not saved.
Hammerspoon's styles in `config/toggles.lua` stay the starting point the sheet shows for Ghostty,
Herdr and Rex until the catalog and the styles move into the app with the rest of 6.2.

## The catalog in the app, 6.2b

Asked by Milos on 2026-11-24, after a Customize save reloaded Hammerspoon as the window closed,
rule 11 of the plan. What moves is everything 6.2 left in Hammerspoon about which apps have a key
and what each does: the catalog, each app's mode and place, and its key. Every application the
Applications page lists, the scan and the added ones, can then take a mode, a place and a key, and
a change applies the moment it is made, with the window left open and nothing reloaded.

**One table, Olm's own.** `apptoggler.apps` in Olm's store, by bundle id, already holds an app's
mode, its place and an added app's name and path. It takes the key too, `key = { leader, key,
code, mods }`, the leader by the name a keymap row spells it, `hyper`, `meta`, `super` or none for
a plain combination, the key as the keymap names it, its key code and the modifiers beyond the
leader. That table is the catalog. There is no second list of apps, and an app with nothing in it
is a row of the scan and nothing more.

**Seeded once from what Hammerspoon has.** The first time the app reads the table with the switch
on and it has not been seeded, it writes every key Hammerspoon binds on an `apptoggler` action,
read from `keymap.json` and the action's bundle from the setting's catalog, and every styled app's
mode and place, the popup style of Ghostty, Herdr and Rex, into the table, marking it seeded. So
the flip loses no key and no popup, rule 9. `config/apps.lua`, `config/toggles.lua` and this
machine's keys file are left as they are, the fallback while the app is down and what every other
machine still reads, rule 6.

**The app claims and runs every app key.** Its catalog's rows join the rows it resolves, on the
leader each names, and a press runs in the app, `AppFocus` with the table's mode and place, telling
Hammerspoon nothing but `keyRan`, so a held leader's sheet goes down. The `apptoggler` rows of
`keymap.json` are left out of the share while the switch is on, so an old chord is never claimed
beside a new one. A key the keymap already binds to another action is refused on the page, with
what holds it, and a claim that fails is logged and left unbound rather than taking the leader
back. A launcher row choosing an app, which still reaches the app through Lua's `appRun`, runs with
the table's mode and place in place of what Lua sent.

**Live.** The Settings window hands each change it made to the app, and the app reads the table
again and claims the difference, keeping every claim it still wants, so a key moved is live before
the window has drawn the change. The setting is declared live while the switch is on, so nothing
waits for the window to close. The app then tells Hammerspoon `appsChanged` with the table's keys,
spelled, and Hammerspoon lays them in place of the toggler's own rows on the Hyper sheet and on each
app's launcher row, so both say what a press does.

**The switch** is `appCatalog` in `config/plugins.lua`, off as shipped. Off, everything is as 6.2
left it.

Steps.

1. **The app's half.** The table read and seeded, the rows claimed and run in the app, the change
   applied live, the page's mode and key offered for every app, the share's rows left out, the
   setting declared live under the switch. `olm-apps-check` covers the seed, the rows and the
   difference claimed.
2. **Hammerspoon's half.** `appsChanged` laid over the Hyper sheet's app section and the launcher's
   app rows, so both follow a change with no reload. Until it lands the switch stays off.
3. **The flip**, with Milos's trial, then removing `HammerspoonCatalog` and `config/toggles.lua`
   once every machine has run the app, rule 6.

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
