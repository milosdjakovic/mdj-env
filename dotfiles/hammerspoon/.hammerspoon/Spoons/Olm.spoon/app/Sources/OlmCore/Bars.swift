// The bottom bar a served list shows in the app, step 1.4f, docs/DESIGN-APP-LIST-KEYS.md piece 2.
// host/bridge writes it at every load as `~/.olm/run/<tool>keys.json`, from lib/hints.lua's
// bottomBarModel for the tool's context with the person's lists section laid over it, flattened as
// the swift view flattens it for Hammerspoon's panel. So the words and the key caps under the app's
// list are the ones under the Lua list, read through the bar's one reader in Fields.swift. Each
// action is already the verb the app runs, lib/nav.lua's name for it.

import CoreGraphics
import Foundation
@preconcurrency @testable import OlmChooser

// What the share holds for one tool, the bar and the keys the list's own field answers.
struct Bars {
  // A key the open list's field answers, by virtual key code and the modifiers it is pressed with
  // exactly, and the verb it runs, Command and Return Reveal in Finder, Command and ? the info pane.
  struct FieldKey {
    let code: Int64
    let mods: Set<String>
    let verb: String
  }
  var bar: BottomBar?
  var fieldKeys: [FieldKey] = []

  // What the bridge last wrote for the tool, or nothing when there is none, so the list shows no
  // bar rather than a wrong one and its field answers no key it was not told of.
  static func read(_ tool: String) -> Bars {
    let path = FileManager.default.homeDirectoryForCurrentUser.path + "/.olm/run/\(tool.lowercased())keys.json"
    guard let data = FileManager.default.contents(atPath: path),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return Bars() }
    var out = Bars()
    if let bar = doc["bar"] as? [String: Any] { out.bar = BottomBar(JSONFields(bar)) }
    for item in doc["fieldKeys"] as? [[String: Any]] ?? [] {
      guard let code = (item["code"] as? NSNumber)?.int64Value, let verb = item["verb"] as? String else { continue }
      out.fieldKeys.append(FieldKey(code: code, mods: Set(item["mods"] as? [String] ?? []), verb: verb))
    }
    return out
  }

  // The verb a key down answers, its modifiers compared exactly on the four real ones.
  func verb(code: Int64, flags: CGEventFlags) -> String? {
    var held: Set<String> = []
    if flags.contains(.maskCommand) { held.insert("cmd") }
    if flags.contains(.maskShift) { held.insert("shift") }
    if flags.contains(.maskAlternate) { held.insert("alt") }
    if flags.contains(.maskControl) { held.insert("ctrl") }
    return fieldKeys.first { $0.code == code && $0.mods == held }?.verb
  }
}
