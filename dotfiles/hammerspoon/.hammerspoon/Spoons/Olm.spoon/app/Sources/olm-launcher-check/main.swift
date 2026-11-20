// Step 6.1's check, docs/DESIGN-APP-LAUNCHER.md. The catalog built in the app against the rules of
// host/launcher/init.lua: applications running first and then by name, one the scan missed listed
// only with a place in the Dock, every row picked before above every row never picked, the most
// recent first, a kind that ignores usage keeping its natural place and taking no bonus, a gated
// row hidden when its gate is shut or unknown, and an application's subtitle with its chord.
//
//   olm-launcher-check            exits 0 when every case held, 1 otherwise
//   olm-launcher-check --live     also builds the catalog from this machine's share and applications
//     --dump F                    and writes its resting order to F, a key, a title and a subtitle a line

import Foundation
import OlmBridge
import OlmKit
import OlmLauncher

var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: String) {
  checks += 1
  if !ok {
    failures += 1
    print("  FAIL \(what)")
  }
}

// The applications.
do {
  let listed = AppScan.listed(
    installed: [("com.apple.Safari", "Safari"), ("com.apple.mail", "Mail"), ("com.apple.Maps", "maps"),
      ("com.apple.Notes", "Notes")],
    running: [("com.apple.Notes", "Notes", true), ("com.example.helper", "Helper", false),
      ("com.example.Docked", "Docked", true)])
  check(listed.map(\.bundleID) == ["com.example.Docked", "com.apple.Notes", "com.apple.mail", "com.apple.Maps", "com.apple.Safari"],
    "running first then by name, case aside, a docked app the scan missed listed, a helper not, \(listed.map(\.bundleID))")
  check(listed[0].running && listed[1].running && !listed[2].running, "running marked")
}

// The catalog.
let shareJSON = """
{"version":1,"self":"org.hammerspoon.Hammerspoon","appWord":"Application","appOpen":"Application · Open",
 "ignoreUsage":["Olm"],"recency":["special:clipboard","app:com.apple.mail","special:settings"],
 "apps":{"com.apple.Safari":{"closed":"Application · Hyper S","open":"Application · Open · Hyper S"}},
 "rows":[
  {"key":"special:clipboard","title":"Clipboard History","subtitle":"Plugin · Hyper V","word":"Plugin","item":{"kind":"special","name":"clipboard"},"icon":{"owner":"clipboard","key":"clipboard"}},
  {"key":"special:settings","title":"Olm Settings","subtitle":"Olm","word":"Olm","item":{"kind":"special","name":"settings"}},
  {"key":"window:nextDisplay","title":"Next Display","subtitle":"Window","word":"Window","when":"multipleDisplays","item":{"kind":"window","name":"nextDisplay"}},
  {"key":"window:other","title":"Other","subtitle":"Window","word":"Window","when":"somethingNew","item":{"kind":"window","name":"other"}},
  {"title":"Never Remembered","subtitle":"Plugin","word":"Plugin","item":{"kind":"x","name":"y","remember":false}}
 ]}
"""
let share = CatalogShare.parse(Data(shareJSON.utf8))!
let apps = [ScannedApp(bundleID: "com.apple.Safari", name: "Safari", running: true),
  ScannedApp(bundleID: "com.apple.mail", name: "Mail", running: false)]
do {
  let built = Catalog.build(share, apps: apps, gate: { $0 == "multipleDisplays" ? false : nil }, icon: { _ in nil })
  let keys = built.rows.map(\.key)
  check(keys.first == "special:clipboard" && keys[1] == "app:com.apple.mail",
    "the rows picked before lead, the most recent first, \(keys)")
  check(!keys.contains("window:nextDisplay"), "a shut gate hides its row")
  check(!keys.contains("window:other"), "an unknown gate hides its row, as the Lua catalog does")
  check(keys.firstIndex(of: "special:settings")! > keys.firstIndex(of: "app:com.apple.Safari")!,
    "a kind that ignores usage keeps its natural place though it was picked")
  check(keys.contains(where: { $0.hasPrefix("olm:unremembered:") }), "a row never remembered is listed")
  check(!built.remembered.contains(where: { $0.hasPrefix("olm:unremembered:") }), "and not remembered")
  let safari = built.rows.first { $0.key == "app:com.apple.Safari" }
  let mail = built.rows.first { $0.key == "app:com.apple.mail" }
  check(safari?.subtitle == "Application · Open · Hyper S", "a running app with a chord wears it open, \(safari?.subtitle ?? "")")
  check(mail?.subtitle == "Application", "an app with no chord, closed, \(mail?.subtitle ?? "")")
  check(safari?.icon == .app("com.apple.Safari"), "an app wears its own icon")
  check(built.items["app:com.apple.mail"]?["bundleID"].string == "com.apple.mail", "an app's item names its bundle")
  check(built.items["special:clipboard"]?["name"].string == "clipboard", "a row's item as the share carried it")
  let bonus = Catalog.withBonus(built, memory: ["ol": ["special:settings", "special:clipboard"]], query: "ol")
  check(bonus.first { $0.key == "special:settings" }?.bonus == 0, "a kind that ignores usage takes no bonus")
  check((bonus.first { $0.key == "special:clipboard" }?.bonus ?? 0) > 0, "a remembered row takes its bonus")
  check(Catalog.withBonus(built, memory: ["ol": ["special:clipboard"]], query: "").allSatisfy { $0.bonus == 0 },
    "no bonus on an empty query")
  check(share.inApp == false, "a share that does not say inApp leaves the launcher on Hammerspoon's whole list")
  let switched = CatalogShare.parse(Data(shareJSON.replacingOccurrences(of: "\"version\":1,", with: "\"version\":1,\"inApp\":true,").utf8))
  check(switched?.inApp == true, "the launcherCatalog switch read from the share")
  let open = Catalog.build(share, apps: apps, gate: { _ in true }, icon: { _ in nil })
  check(open.rows.contains { $0.key == "window:nextDisplay" }, "an open gate shows its row")
}

if CommandLine.arguments.contains("--live") {
  let url = URL(fileURLWithPath: NSHomeDirectory() + "/.olm/run/launchercatalog.json")
  if let data = try? Data(contentsOf: url), let live = CatalogShare.parse(data) {
    let t = Date()
    let installed = AppScan.installed()
    let scan = Date().timeIntervalSince(t) * 1000
    let listed = AppScan.listed(installed: installed, running: AppScan.running())
    let built = Catalog.build(live, apps: listed, gate: { _ in true }, icon: { _ in nil })
    print(String(format: "live: %d applications scanned in %.0f ms, %d other rows, %d in all, recency %d",
      installed.count, scan, live.entries.count, built.rows.count, live.recency.count))
    print("live: first ten, " + built.rows.prefix(10).map(\.title).joined(separator: ", "))
    if let i = CommandLine.arguments.firstIndex(of: "--dump"), i + 1 < CommandLine.arguments.count {
      let lines = built.rows.map { "\($0.key)\t\($0.title)\t\($0.subtitle)" }.joined(separator: "\n") + "\n"
      try? lines.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
    }
    checks += 1
  } else {
    check(false, "live: no catalog share at \(url.path)")
  }
}

print("olm-launcher-check, \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
