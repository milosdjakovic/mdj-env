// Checks bringing an app forward in Olm.app, step 6.2, docs/DESIGN-APP-APPS.md: the decision against
// the cases test/appfocus.lua pins for lib/appfocus.lua, the placement geometry against the app
// toggler's, the press appRun carries and the shadow's counts. It touches no app and no window.

import Foundation
import OlmApps

var failures = 0, checks = 0
func eq<T: Equatable>(_ got: T, _ want: T, _ what: String) {
  checks += 1
  if got != want {
    failures += 1
    print("  FAIL  \(what), wanted \(want), got \(got)")
  }
}

// The decision.
let w30 = AppWindow(id: 30, standard: true, minimized: false)
let w10 = AppWindow(id: 10, standard: true, minimized: false)
let w20 = AppWindow(id: 20, standard: true, minimized: true)
let dialog = AppWindow(id: 5, standard: false, minimized: false)
eq(AppPlan.decide(AppState(running: false), hides: false), AppPlan(.launched), "an app not running launches")
eq(AppPlan.decide(AppState(running: true, frontmost: true), hides: false), AppPlan(.focused),
  "an app in front with no window is focused")
eq(AppPlan.decide(AppState(running: true, frontmost: false, windows: [w30, w10, w20]), hides: false), AppPlan(.focused),
  "an app behind is focused")
let front = AppState(running: true, frontmost: true, windows: [w30, w10, w20, dialog], focused: 10)
eq(AppPlan.decide(front, hides: false), AppPlan(.cycled, window: 30), "an app in front cycles to the next by number, the minimized and the dialog left out")
eq(AppPlan.decide(AppState(running: true, frontmost: true, windows: [w30, w10], focused: 30), hides: false),
  AppPlan(.cycled, window: 10), "and wraps to the first")
eq(AppPlan.decide(AppState(running: true, frontmost: true, windows: [w30, w10], focused: nil), hides: false),
  AppPlan(.cycled, window: 10), "and with no focused window starts at the first")
eq(AppPlan.decide(AppState(running: true, frontmost: true, windows: [w30, w10], focused: 99), hides: false),
  AppPlan(.cycled, window: 10), "and with focus in another app starts at the first")
eq(AppPlan.decide(AppState(running: true, frontmost: true, windows: [dialog]), hides: false), AppPlan(.focused),
  "an app in front with only a dialog is focused")
eq(AppPlan.decide(AppState(running: true, frontmost: true, windows: [dialog]), hides: true), AppPlan(.hidden),
  "the show and hide form hides an app in front with any window")
eq(AppPlan.decide(AppState(running: true, frontmost: true), hides: true), AppPlan(.focused),
  "and focuses one in front with none")
eq(AppPlan.decide(AppState(running: true, frontmost: false, windows: [w10]), hides: true), AppPlan(.focused),
  "and focuses one behind")
eq(AppPlan.decide(AppState(running: false), hides: true), AppPlan(.launched), "and launches one not running")
eq(AppPlan(.launched).places && AppPlan(.focused).places, true, "placement fires on launched and focused")
eq(AppPlan(.cycled, window: 1).places || AppPlan(.hidden).places, false, "and never on cycled or hidden")

// Padding, the toggler's normalizePadding.
eq(Padding(nil), Padding(), "no padding insets nothing")
var four = Padding(); four.top = 8; four.right = 8; four.bottom = 8; four.left = 8
eq(Padding(8.0), four, "a number insets all four")
var pair = Padding(); pair.top = 20; pair.bottom = 20; pair.left = 40; pair.right = 40
eq(Padding(["x": 40.0, "y": 20.0]), pair, "x and y inset the pairs")
var sides = Padding(); sides.top = 5
eq(Padding(["top": 5.0, "x": 40.0]), sides, "a named side insets exactly the sides named")

// The popup style on a 3008 by 1667 visible frame below a 25 point menu bar.
let screen = Box(x: 0, y: 25, w: 3008, h: 1667)
let popup = Placement(["width": 2400.0, "height": 1350.0, "padding": ["x": 40.0, "y": 20.0]])!
eq(popup.box(screen), Box(x: 40, y: 45, w: 2928, h: 1627), "the box is the visible frame inset by the padding")
eq(popup.frame(in: popup.box(screen), current: Box(x: 0, y: 0, w: 800, h: 600)),
  Box(x: 304, y: 183.5, w: 2400, h: 1350), "and the window is centred in it at its size")
let small = Box(x: 1512, y: 25, w: 1512, h: 920)
eq(popup.frame(in: popup.box(small), current: Box(x: 0, y: 0, w: 800, h: 600)),
  Box(x: 1552, y: 45, w: 1432, h: 880), "a size bigger than the box is clamped to it")
let widthOnly = Placement(["width": 1000.0, "at": ["x": 0.0, "y": 1.0]])!
eq(widthOnly.frame(in: screen, current: Box(x: 0, y: 0, w: 800, h: 600)), Box(x: 0, y: 1092, w: 1000, h: 600),
  "an omitted height keeps the window's and the anchor puts it at the near and far edges")
let wild = Placement(["at": ["x": -3.0, "y": 9.0]])!
eq(wild.frame(in: screen, current: Box(x: 0, y: 0, w: 800, h: 600)), Box(x: 0, y: 1092, w: 800, h: 600),
  "an anchor past 0 or 1 is clamped")
eq(Placement("function") == nil, true, "a placement that is not a table is none")

// The screen a window stands on.
let left = Box(x: 0, y: 25, w: 1512, h: 920), right = Box(x: 1512, y: 0, w: 2560, h: 1415)
eq(screenOf(Box(x: 1400, y: 100, w: 800, h: 600), among: [left, right]), right, "the screen it overlaps most")
eq(screenOf(Box(x: -5000, y: 0, w: 10, h: 10), among: [left, right]), left, "and the first when it overlaps none")

// The press appRun carries.
let press = AppPress(["id": "apptoggler.Ghostty", "bundle": "com.mitchellh.ghostty", "hides": true,
  "placement": ["width": 2400.0], "lua": ["outcome": "cycled", "window": 42.0]])
eq(press?.id, "apptoggler.Ghostty", "a press keeps its action")
eq(press?.hides, true, "and its hides")
eq(press?.placement?.width, 2400.0, "and its placement")
eq(press?.lua, AppPlan(.cycled, window: 42), "and Lua's plan")
eq(AppPress(["bundle": "a.b"])?.id, "launcher", "a press with no id is the launcher's")
eq(AppPress(["id": "x"]) == nil, true, "a press with no bundle id is none")

// The shadow's counts.
let shadow = AppShadow(log: nil)
let plain = AppPress(id: "a", bundle: "a.b", hides: false, placement: nil, lua: AppPlan(.focused))
shadow.ran(plain, plan: AppPlan(.focused), trusted: true)
shadow.ran(plain, plan: AppPlan(.cycled, window: 3), trusted: false)
shadow.ran(AppPress(id: "a", bundle: "a.b", hides: false, placement: nil, lua: nil), plan: AppPlan(.focused), trusted: true)
shadow.placed(plain, asked: Box(x: 0, y: 0, w: 100, h: 100), got: Box(x: 1, y: 0, w: 100, h: 101.5))
shadow.placed(plain, asked: Box(x: 0, y: 0, w: 100, h: 100), got: Box(x: 0, y: 0, w: 120, h: 100))
shadow.unplaced(plain)
let c = shadow.current
eq([c.ran, c.same, c.differs, c.untrusted], [3, 1, 1, 1], "a press is counted, agreeing or not, and one without Lua's plan compares nothing")
eq([c.placed, c.refused, c.unplaced], [1, 1, 1], "a frame within two points is placed, one further refused")

print("olm-apps-check: \(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
