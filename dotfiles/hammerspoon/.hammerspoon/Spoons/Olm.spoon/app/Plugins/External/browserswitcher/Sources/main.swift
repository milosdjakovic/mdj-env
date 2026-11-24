// Browser Switcher, the first external plugin of ours, docs/DESIGN-BROWSER-SWITCHER.md and
// docs/DESIGN-APP-PLUGINS.md. Olm.app is the default browser and opens this list for each link it
// receives, handing it the link, the browsers Olm found and the favourites set in Olm Settings. The
// list asks where the link opens, a browser, one of its profiles or Copy Link, with Show All in the
// actions pane for the rest. It runs sandboxed and holds no permission of macOS's: Olm reads the
// profiles for it, Browser Profiles, and opens the link where it is chosen, since a plugin may not
// start an application.
//
// The last link is kept in its data folder, so the launcher's row opens it again to send it
// somewhere else.

import Foundation

struct Target {
  var title: String
  var bundle: String
  var path: String
  var args: [String]
}

let copyTitle = "Copy Link"
let plugin = OlmPlugin()
var link: String?
var targets: [Target] = []
var favourites: [String] = []
var showAll = false
let lastFile = plugin.data.appendingPathComponent("last.json")

func remember(_ url: String) {
  if let data = try? JSONSerialization.data(withJSONObject: ["url": url]) { try? data.write(to: lastFile, options: .atomic) }
}

func remembered() -> String? {
  guard let data = try? Data(contentsOf: lastFile),
    let o = (try? JSONSerialization.jsonObject(with: data)) as? OlmJSON else { return nil }
  return o["url"] as? String
}

/// The link with its scheme and www left off, cut in the middle past 64 characters so its start
/// and its end both show.
func placeholder(_ url: String?) -> String {
  guard let url else { return "Open link in" }
  var text = url
  for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
  if text.hasPrefix("www.") { text.removeFirst(4) }
  let room = 64
  let chars = Array(text)
  guard chars.count > room else { return text }
  let head = Int(Double(room) * 0.6)
  let tail = room - head - 1
  return String(chars[0..<head]) + "…" + String(chars[(chars.count - tail)...])
}

/// The favourites shown, by name, Copy Link among them, or every browser then Copy Link.
func shown() -> [Target?] {
  if showAll || favourites.isEmpty { return targets.map { $0 } + [nil] }
  var byTitle: [String: Target] = [:]
  for t in targets { byTitle[t.title.lowercased()] = t }
  return favourites.compactMap { name -> Target?? in
    if name.lowercased() == copyTitle.lowercased() { return .some(nil) }
    return byTitle[name.lowercased()].map { .some($0) }
  }
}

func copyLink() {
  guard let link else { return }
  plugin.copy(link)
  plugin.notify("Link copied")
}

plugin.open = { context in
  if let given = (context["link"] as? OlmJSON)?["url"] as? String {
    link = given
    remember(given)
  } else {
    link = remembered()
  }
  targets = (context["browsers"] as? [OlmJSON] ?? []).compactMap { t in
    guard let title = t["title"] as? String, let bundle = t["bundle"] as? String, let path = t["path"] as? String
    else { return nil }
    return Target(title: title, bundle: bundle, path: path, args: t["args"] as? [String] ?? [])
  }
  favourites = (context["settings"] as? OlmJSON)?["favourites"] as? [String] ?? []
  showAll = false
  return OlmLevel(placeholder: placeholder(link), actions: ["copyLink", "showAll", "showFavourites"])
}

plugin.rows = { _ in
  guard link != nil else {
    return [OlmRow(key: "none", title: "No link yet",
      subtitle: "Links you click while Olm is the default browser land here",
      icon: .symbol("exclamationmark.triangle"), pinned: true)]
  }
  let rows = shown().map { t -> OlmRow in
    guard let t else { return OlmRow(key: "copy", title: copyTitle, icon: .symbol("doc.on.doc")) }
    return OlmRow(key: "t:" + t.title, title: t.title, icon: .app(t.bundle))
  }
  if rows.isEmpty {
    return [OlmRow(key: "none", title: "No favourite is on this Mac",
      subtitle: "Show All in the actions pane lists every browser", icon: .symbol("exclamationmark.triangle"),
      pinned: true)]
  }
  return rows
}

plugin.choose = { key, _ in
  guard let link, key != "none" else { return [] }
  if key == "copy" {
    copyLink()
    return [.hide]
  }
  guard key.hasPrefix("t:"), let t = targets.first(where: { "t:" + $0.title == key }) else { return [] }
  plugin.openLink(link, app: t.path, arguments: t.args)
  return [.hide]
}

plugin.actions = { _ in
  var out: [(String, String)] = [("copyLink", copyTitle)]
  if showAll { out.append(("showFavourites", "Show Favourites")) }
  else if !favourites.isEmpty { out.append(("showAll", "Show All")) }
  return out
}

plugin.run = { action, _ in
  switch action {
  case "copyLink":
    copyLink()
    return [.hide]
  case "showAll":
    showAll = true
    return [.redraw]
  case "showFavourites":
    showAll = false
    return [.redraw]
  default:
    return []
  }
}

plugin.start()
