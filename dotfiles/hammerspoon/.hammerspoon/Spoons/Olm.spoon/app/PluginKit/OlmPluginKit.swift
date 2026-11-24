// OlmPluginKit, what an external plugin is written with, docs/DESIGN-APP-PLUGINS.md. One file,
// compiled into every plugin beside its own sources, so a plugin is its handlers and nothing else.
// It speaks the bridge protocol, docs/PROTOCOL-BRIDGE.md, over the process's stdin and stdout, each
// message its length, a newline and the JSON, and asks Olm for what the sandbox keeps the plugin
// from doing itself, opening an app, writing the clipboard, saying a line.
//
// A plugin answers one list, a level at a time:
//
//   let plugin = OlmPlugin()
//   plugin.open = { context in OlmLevel(placeholder: "Pick") }
//   plugin.rows = { query in [OlmRow(key: "a", title: "A")] }
//   plugin.choose = { key, query in [.hide] }
//   plugin.start()
//
// Every handler runs on one queue of the kit's, never the thread reading the pipe, so a handler
// may ask Olm something and wait for the answer.

import Foundation

/// A JSON value as JSONSerialization reads and writes it.
public typealias OlmJSON = [String: Any]

/// What the list looks like, the level the plugin answers.
public struct OlmLevel {
  public var placeholder: String
  /// true when Olm ranks the rows with its shared search, false when the plugin's order is final.
  public var searched: Bool
  /// The actions of the actions pane, by id, each run through `run`.
  public var actions: [String]
  /// The window as tall as the rows.
  public var fit: Bool

  public init(placeholder: String, searched: Bool = true, actions: [String] = [], fit: Bool = false) {
    self.placeholder = placeholder
    self.searched = searched
    self.actions = actions
    self.fit = fit
  }
}

/// One row. The icon is an SF Symbol's name, an emoji or an application's bundle id.
public struct OlmRow {
  public var key: String
  public var title: String
  public var subtitle: String
  public var icon: Icon?
  public var keywords: [String]
  /// Kept below every match and on an empty query, Copy Link after the browsers.
  public var pinned: Bool

  public enum Icon {
    case symbol(String)
    case emoji(String)
    case app(String)
  }

  public init(key: String, title: String, subtitle: String = "", icon: Icon? = nil, keywords: [String] = [],
              pinned: Bool = false) {
    self.key = key
    self.title = title
    self.subtitle = subtitle
    self.icon = icon
    self.keywords = keywords
    self.pinned = pinned
  }

  var wire: OlmJSON {
    var o: OlmJSON = ["key": key, "ref": key, "title": title]
    if !subtitle.isEmpty { o["subtitle"] = subtitle }
    if !keywords.isEmpty { o["keywords"] = keywords }
    if pinned { o["pinned"] = true }
    switch icon {
    case .symbol(let name)?: o["icon"] = ["sf": name]
    case .emoji(let glyph)?: o["icon"] = ["emoji": glyph]
    case .app(let bundle)?: o["icon"] = ["app": bundle]
    case nil: break
    }
    return o
  }
}

/// What choosing a row or running an action did, applied by Olm in order.
public enum OlmEffect {
  /// The list closes.
  case hide
  /// The rows are asked again, the highlight kept on its row.
  case redraw
  /// The input field's empty text says this.
  case placeholder(String)

  var wire: OlmJSON {
    switch self {
    case .hide: return ["hide": [String: Any]()]
    case .redraw: return ["rows": ["hold": true]]
    case .placeholder(let text): return ["setPlaceholder": ["text": text]]
    }
  }
}

public final class OlmPlugin {
  /// The list opens, handed what Olm opened it with, a link for a plugin receiving links.
  public var open: (OlmJSON) -> OlmLevel = { _ in OlmLevel(placeholder: "") }
  /// The rows for what is typed.
  public var rows: (String) -> [OlmRow] = { _ in [] }
  /// Return on a row, by its key, with what is typed.
  public var choose: (String, String) -> [OlmEffect] = { _, _ in [.hide] }
  /// An action of the actions pane on a row, by the action's id and the row's key.
  public var run: (String, String) -> [OlmEffect] = { _, _ in [] }
  /// The actions that apply to a row, each its id and title, in order.
  public var actions: (String) -> [(String, String)] = { _ in [] }
  /// The list closed.
  public var closed: () -> Void = {}

  /// Where the plugin may keep files, its own data folder.
  public private(set) var data = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OLM_PLUGIN_DATA"] ?? NSTemporaryDirectory())

  private let out = FileHandle.standardOutput
  private let outLock = NSLock()
  private let work = DispatchQueue(label: "olm.plugin.work")
  private var nextID = 0
  private var waiting: [String: (DispatchSemaphore, Box)] = [:]
  private let waitLock = NSLock()
  private var levelID = "l0"
  private var opened = 0

  private final class Box { var value: Any? }

  public init() {}

  // MARK: Asking Olm

  /// Asks Olm something and waits for the answer, at most a few seconds, nil for none or a refusal.
  @discardableResult
  public func ask(_ method: String, _ params: OlmJSON = [:]) -> Any? {
    waitLock.lock()
    nextID += 1
    let id = "k\(nextID)"
    let sem = DispatchSemaphore(value: 0)
    let box = Box()
    waiting[id] = (sem, box)
    waitLock.unlock()
    send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    let answered = sem.wait(timeout: .now() + 4) == .success
    waitLock.lock()
    waiting[id] = nil
    waitLock.unlock()
    return answered ? box.value : nil
  }

  /// Opens a link, in the application at path when one is named, with arguments for its program,
  /// a browser's profile, done by Olm since a plugin may not start an application.
  public func openLink(_ url: String, app path: String? = nil, arguments: [String] = []) {
    var params: OlmJSON = ["url": url, "args": arguments]
    if let path { params["app"] = path }
    ask("open", params)
  }

  /// Writes the text to the clipboard.
  public func copy(_ text: String) { ask("copy", ["text": text]) }

  /// Says one routine line.
  public func notify(_ text: String) { ask("notify", ["text": text]) }

  /// Writes a line to the plugin's log.
  public func log(_ text: String) { send(["jsonrpc": "2.0", "method": "log", "params": ["text": text]]) }

  // MARK: The loop

  /// Reads Olm's messages until it closes the pipe, which is Olm asking the plugin to go.
  public func start() -> Never {
    var buffer = Data()
    let input = FileHandle.standardInput
    while true {
      let chunk = input.availableData
      if chunk.isEmpty { exit(0) }
      buffer.append(chunk)
      while let nl = buffer.firstIndex(of: 0x0A) {
        guard let n = Int(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)) else { exit(2) }
        let start = buffer.index(after: nl)
        guard buffer.distance(from: start, to: buffer.endIndex) >= n else { break }
        let body = buffer[start..<buffer.index(start, offsetBy: n)]
        buffer = Data(buffer[buffer.index(start, offsetBy: n)...])
        if let message = try? JSONSerialization.jsonObject(with: body) as? OlmJSON { take(message) }
      }
    }
  }

  private func take(_ message: OlmJSON) {
    // An answer to something the plugin asked, handed to whoever waits for it.
    if message["method"] == nil, let id = message["id"] as? String {
      waitLock.lock()
      let w = waiting[id]
      waitLock.unlock()
      if let (sem, box) = w {
        box.value = message["result"]
        sem.signal()
      }
      return
    }
    guard let method = message["method"] as? String else { return }
    let params = message["params"] as? OlmJSON ?? [:]
    guard let id = message["id"] else { return }
    work.async { self.handle(id, method, params) }
  }

  private func handle(_ id: Any, _ method: String, _ p: OlmJSON) {
    switch method {
    case "hello":
      answer(id, ["protocol": 1])
    case "open":
      let what = p["what"] as? OlmJSON ?? [:]
      let level = open(what["context"] as? OlmJSON ?? [:])
      opened += 1
      levelID = "l\(opened)"
      var wire: OlmJSON = ["id": levelID, "placeholder": level.placeholder,
        "ranking": level.searched ? "app" : "source", "rowLimit": "default", "actions": level.actions]
      if level.fit { wire["fit"] = true }
      answer(id, ["level": wire])
    case "rows":
      let list = rows(p["query"] as? String ?? "")
      answer(id, ["q": p["q"] ?? 0, "rows": list.map(\.wire), "revision": UUID().uuidString])
    case "choose":
      answer(id, ["effects": choose(p["ref"] as? String ?? "", p["query"] as? String ?? "").map(\.wire)])
    case "run":
      answer(id, ["effects": run(p["action"] as? String ?? "", p["ref"] as? String ?? "").map(\.wire)])
    case "actions":
      let list = actions(p["ref"] as? String ?? "").map { ["action": $0.0, "title": $0.1] }
      answer(id, ["h": p["h"] ?? 0, "actions": list])
    case "choices":
      answer(id, ["choices": [Any]()])
    case "back":
      answer(id, ["handled": false, "effects": [Any]()])
    case "close":
      closed()
      answer(id, true)
    default:
      send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "no method \(method)"]])
    }
  }

  private func answer(_ id: Any, _ result: Any) { send(["jsonrpc": "2.0", "id": id, "result": result]) }

  private func send(_ object: OlmJSON) {
    guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
    outLock.lock()
    out.write(Data("\(body.count)\n".utf8) + body)
    outLock.unlock()
  }
}
