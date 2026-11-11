// File search, the app's first native plugin, docs/DESIGN-APP.md, the counterpart of
// plugins/filesearch/engine.lua for the unscoped search and the recent list.
//
// It answers through ListSource and knows nothing of the panel. Every query is parsed with the
// grammar and answered by the index, and the rows go to the stage in the index's order with the
// free text the grammar parsed out of the query to rank them by, the presentation's searchText on
// the Lua side. The stage ranks them with the shared search, each row searched by its file name
// alone, filterText set to the title, as on the Lua side.
//
// Every search is asked of the index, as on the Lua side since 2026-11-09, which shows its held
// rows only while the answer is on its way. A longer word can match a name a shorter one did not,
// one typo from four letters and inside a word from three, so held rows are never the answer. An
// unscoped query shorter than minChars hands over the
// recent list, which the stage ranks by the text typed so far, as the Lua side hands its recent
// rows to the shared search. A scoped query, a folder walk on the Lua side, is step 1.4e and says
// so. Frecency, step 1.4d, Frecency.swift, gives every row the bonus of how much you use it and
// floats the paths you use most to the top of the recent list, as engine.lua's preference and
// _float do. The shadow's source keeps none, so it compares the order the query decides.
//
// It answers the preview pane too, step 1.4a, Preview.swift, the highlighted row read in process on
// a thread of its own and described as the Lua side pane describes it, and since step 1.4b its
// picture, Thumbs.swift, a preview saying rendering pending until previewLanded answers the same
// row with the picture or no preview.
//
// The settings, file search's types, limits and preview block and its placeholder, are
// config/filesearch.lua's,
// written by the bridge to ~/.olm/run/filesearch.json where the olmapp piece is on and read on
// every open, so the config keeps one owner.

import Foundation
import OlmKit

public struct FileSearchSettings: Equatable, Sendable {
  public var types: [String: [String]] = [:]
  public var retainCap = 2000
  public var rowLimit = 200
  public var minChars = 1
  public var recentDays = 7
  public var recentCount = 40
  public var placeholder = ""
  /// The preview block, what one highlighted row may cost.
  public var preview = PreviewLimits()
  /// The folder aliases, `dl/` for Downloads, and the names a walk never descends into, step 1.4e.
  public var roots: [String: String] = [:]
  public var prune: [String] = []
  public var timeoutSeconds = 5.0
  /// The walker's path as Hammerspoon's dependency door resolved it, nil where fd is missing.
  public var walker: String?
  /// Frecency's half life and size, and how many of the paths you use most lead the recent list.
  public var frecencyHalfLifeDays = 14.0
  public var frecencyMaxEntries = 500
  public var recentFloat = 8
  /// Which of the store's orders leads them, recentFloatOrder, use where the word is unknown.
  public var recentFloatOrder: Frecency.Order = .use
  public init() {}

  /// config/filesearch.lua's settings as the bridge wrote them, or the Lua defaults.
  public static func read(from run: URL) -> FileSearchSettings {
    var settings = FileSearchSettings()
    guard let data = try? Data(contentsOf: run.appendingPathComponent("filesearch.json")),
      let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return settings }
    if let types = doc["types"] as? [String: [String]] { settings.types = types }
    let limits = doc["limits"] as? [String: Any] ?? [:]
    if let n = limits["retainCap"] as? Int { settings.retainCap = n }
    if let n = limits["minChars"] as? Int { settings.minChars = n }
    if let n = limits["recentDays"] as? Int { settings.recentDays = n }
    if let n = limits["recentCount"] as? Int { settings.recentCount = n }
    settings.placeholder = doc["placeholder"] as? String ?? ""
    settings.preview = PreviewLimits(doc["preview"] as? [String: Any] ?? [:])
    if let roots = doc["roots"] as? [String: String] { settings.roots = roots }
    if let prune = doc["prune"] as? [String] { settings.prune = prune }
    if let n = (limits["timeoutSeconds"] as? NSNumber)?.doubleValue { settings.timeoutSeconds = n }
    if let n = (limits["frecencyHalfLifeDays"] as? NSNumber)?.doubleValue { settings.frecencyHalfLifeDays = n }
    if let n = limits["frecencyMaxEntries"] as? Int { settings.frecencyMaxEntries = n }
    if let n = limits["recentFloat"] as? Int { settings.recentFloat = n }
    if let word = limits["recentFloatOrder"] as? String { settings.recentFloatOrder = Frecency.Order(rawValue: word) ?? .use }
    // The tools the list declares, resolved by the door and written by the root, step 1.4e.
    if let data = try? Data(contentsOf: run.appendingPathComponent("filesearchtools.json")),
      let tools = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let paths = tools["paths"] as? [String: String] {
      settings.walker = paths["fd"]
    }
    return settings
  }
}

public actor FileSearchSource: ListSource {
  public nonisolated let manifest = Manifest(name: "filesearch", title: "File Search", actions: [
    Action(id: "reveal", title: "Reveal in Finder", chord: ["cmd", "return"]),
    Action(id: "copyPath", title: "Copy Path"),
    // The file or folder itself on the clipboard, step 1.4k, chooser.lua's copyFile.
    Action(id: "copyFile", title: "Copy File"),
    // The Lua list's verb name, so q under the list leader and the actions pane's row reach it.
    Action(id: "peekPreview", title: "Quick Look"),
    // A folder's own level and the one above, step 1.4e, chooser.lua's browseInto and browseUp.
    Action(id: "browseInto", title: "Into Folder"),
    Action(id: "browseUp", title: "Up a Level"),
  ], previewPane: PreviewPane(emptyText: FileSearchSource.paneEmptyText))

  /// What the pane says while nothing is highlighted, plugins/filesearch/chooser.lua's emptyText.
  public static let paneEmptyText = "Highlight a file to preview it"

  private let context: PluginContext
  private let index: FileIndex
  // How many letters a word needs before the shared search keeps it inside a word,
  // Match.swift's INSIDE_MIN, handed to the walker as the Lua root hands walk.lua its insideFrom.
  private let insideFrom: Int?
  public private(set) var settings: FileSearchSettings
  // What the rows held answer, set only from an index answer.
  private var held: (query: FileQuery, rows: [IndexRow])? {
    didSet { folders = nil }
  }
  // Which held rows are folders, by path, built the first time a preview asks.
  private var folders: Set<String>?
  /// How many times the index was asked, for a check that narrowing asks nothing.
  public private(set) var asks = 0
  private let thumbs: Thumbs
  // The rows whose preview said rendering, what was read for each, for previewLanded.
  private var rendering: [String: (spec: ThumbSpec, isDir: Bool, peek: Peek?)] = [:]

  /// Where the app keeps its own renders, under the cache handed in.
  public static func previewsDir(_ context: PluginContext) -> URL {
    context.cache.appendingPathComponent("filesearch/previews-app")
  }

  // The folder permissions, asked on the person's list only, nil for the shadow and a check, which
  // never ask. Step 1.4j, Access.swift.
  private let access: FolderAccess?
  private var accessState = FolderAccess.State()
  // What you use, the person's list only, nil for the shadow and a check that hands none in.
  private let frecency: Frecency?

  /// Where the person's list keeps its uses, and the Lua history the root shares, step 1.4d.
  public static func frecency(_ context: PluginContext) -> Frecency {
    Frecency(file: context.store.appendingPathComponent("frecency.json"),
      history: context.run.appendingPathComponent("filesearchhistory.json"))
  }

  /// The keys of the two rows the permissions add, never a path, since a path starts with a slash.
  public static let askKey = "olm:folder-access"
  public static let refusedKey = "olm:folder-refused"

  /// asksAccess is the person's list, which asks for the folder permissions on its first open,
  /// access the folders and the file, handed in by a check.
  public init(context: PluginContext, index: FileIndex? = nil, settings: FileSearchSettings? = nil,
              asksAccess: Bool = false, access: FolderAccess? = nil, insideFrom: Int? = 3,
              frecency: Frecency? = nil) {
    self.context = context
    self.frecency = frecency
    self.insideFrom = insideFrom
    self.access = access ?? (asksAccess
      ? FolderAccess(home: FileManager.default.homeDirectoryForCurrentUser, store: context.store) : nil)
    thumbs = Thumbs(dir: Self.previewsDir(context))
    self.index = index ?? FileIndex(
      helper: context.resources.appendingPathComponent("fileindex").path,
      index: context.cache.appendingPathComponent("filesearch/file-index.txt").path)
    self.settings = settings ?? FileSearchSettings.read(from: context.run)
  }

  /// Reads the settings again and forgets the rows held, since files change between two opens.
  public func open(query: String) async -> Level {
    settings = FileSearchSettings.read(from: context.run)
    held = nil
    rendering = [:]
    await thumbs.forget()
    if let access { accessState = await access.recheck(access.load()) }
    useSettings()
    return Level(placeholder: settings.placeholder, ranking: .app, rowLimit: settings.rowLimit,
      titleLineBreak: "truncateMiddle", previewSettleMs: settings.preview.settleMs)
  }

  /// The same with settings handed in rather than read, for a check and for the shadow.
  public func open(settings: FileSearchSettings) {
    self.settings = settings
    held = nil
    useSettings()
  }

  // Frecency's limits from the settings, and the Lua history taken when it holds a newer use.
  private func useSettings() {
    guard let frecency else { return }
    frecency.halfLifeDays = settings.frecencyHalfLifeDays
    frecency.maxEntries = settings.frecencyMaxEntries
    frecency.refresh()
  }

  public func rows(_ query: Query) async throws -> RowsAnswer {
    // Nothing is searched until the folder permissions are answered, so no prompt comes mid search.
    if access != nil, !accessState.asked { return RowsAnswer(rows: [Self.askRow]) }
    let answer = try await search(query)
    guard access != nil, !accessState.refused.isEmpty else { return answer }
    var said = answer
    said.rows.insert(Self.refusedRow(accessState.refused), at: 0)
    return said
  }

  static let askRow = Row(key: askKey, title: "Allow File Search to Read Your Folders",
    subtitle: "macOS asks once for " + FolderAccess.spoken(FolderAccess.protectedNames),
    icon: .symbol(FolderAccess.symbol), pinned: true)

  static func refusedRow(_ names: [String]) -> Row {
    Row(key: refusedKey, title: "Ask Again for " + FolderAccess.spoken(names),
      subtitle: "macOS refused it, so file search cannot preview files there",
      icon: .symbol(FolderAccess.symbol), pinned: true)
  }

  private func search(_ query: Query) async throws -> RowsAnswer {
    let q = FileQueryGrammar.parse(query.text, types: settings.types)
    if q.scope != nil { return try await folder(q) }
    let empty = q.kind == .search ? "No matches" : "Nothing changed lately"
    // What the index is asked for. An unscoped search too short to be worth asking is the recent
    // list, the Lua side's minChars, and the rows are still ranked by what was typed.
    let short = q.kind == .search && q.text.utf8.count < settings.minChars
    let asked = short ? FileQueryGrammar.parse("", types: settings.types) : q
    // The recent list held already answers any short text, the same list ranked again.
    // The plain recent list leads with what you use, engine:_float, a type or the dot leaving it out.
    let floats = asked.kind == .recent && asked.exts == nil && !asked.hidden
    if let held, asked.kind != .search, held.query == asked {
      return answer(held.rows, q, empty, float: floats)
    }
    asks += 1
    index.recentDays = settings.recentDays
    let cap = asked.kind == .recent ? settings.recentCount : settings.retainCap
    let rows: [IndexRow]
    do {
      rows = try await index.ask(asked, cap: cap)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      held = nil
      return RowsAnswer(rows: [], status: "The file index could not be read")
    }
    held = (asked, rows)
    return answer(rows, q, empty, float: floats)
  }

  private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

  /// A query naming a folder, a browse of one level with the `..` row first, or a search beneath
  /// it, walk.lua's two modes, docs/DESIGN-APP-FOLDER-SEARCH.md. Each failure is worded as the Lua
  /// list's status row words it.
  private func folder(_ q: FileQuery) async throws -> RowsAnswer {
    let home = Self.home
    held = nil
    guard let dir = FolderScope.resolve(q.scope ?? "", roots: settings.roots, home: home) else {
      return RowsAnswer(rows: [], status: "No such folder")
    }
    let walk = FolderWalk(fd: settings.walker, prune: settings.prune, insideFrom: insideFrom,
      timeoutSeconds: settings.timeoutSeconds)
    var up: [Row] = []
    if q.kind == .browse, let parent = Self.upPath(q, settings: settings) {
      up = [Self.upRow(parent, home: home)]
    }
    if q.kind == .search, settings.walker == nil {
      return RowsAnswer(rows: [], status: "Nothing can answer that")
    }
    do {
      asks += 1
      let rows = q.kind == .browse
        ? try await walk.browse(dir, cap: settings.retainCap)
        : try await walk.search(q, dir: dir, cap: settings.retainCap)
      if q.kind == .browse, rows.isEmpty { return Self.said(up, "Empty folder") }
      return RowsAnswer(rows: up + rows.map { Self.row($0, home: home, bonus: bonus($0.path)) }, rankText: q.text,
        emptyStatus: "No matches")
    } catch is CancellationError {
      throw CancellationError()
    } catch WalkError.timedOut {
      return Self.said(up, "Timed out")
    } catch {
      return Self.said(up, q.kind == .browse ? "Could not list that folder" : "Search failed")
    }
  }

  /// The key of a row that says what a folder holds rather than being a file.
  public static let statusKey = "olm:folder-status"

  // A status beside the `..` row is a row of its own under it, as the Lua list's status row is,
  // since the list says a status only while it holds no row. With no `..` row it is the status.
  static func said(_ up: [Row], _ status: String) -> RowsAnswer {
    guard !up.isEmpty else { return RowsAnswer(rows: [], status: status) }
    return RowsAnswer(rows: up + [Row(key: statusKey, title: status, subtitle: "",
      icon: .symbol("folder"), pinned: true)])
  }

  /// The folder above a query's scope, expanded, the path the `..` row stands for, nil without one.
  static func upPath(_ q: FileQuery, settings: FileSearchSettings) -> String? {
    guard let query = FolderScope.upQuery(q.scope, roots: settings.roots, home: home) else { return nil }
    var path = FolderScope.expandHome(query, home: home)
    while path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return path
  }

  /// chooser.lua's upRow, an ordinary folder row for the parent titled with two dots, pinned first.
  static func upRow(_ parent: String, home: String) -> Row {
    let shown = parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    return Row(key: parent, title: "..", subtitle: "up to " + shown, icon: .file(parent), filterText: "..",
      pinned: true)
  }

  // Whether a pick is the `..` row of the query it was made under.
  private func isUp(_ pick: Pick) -> Bool {
    let q = FileQueryGrammar.parse(pick.query, types: settings.types)
    return q.kind == .browse && Self.upPath(q, settings: settings) == pick.key
  }

  private func answer(_ rows: [IndexRow], _ q: FileQuery, _ empty: String, float: Bool = false) -> RowsAnswer {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let listed = float ? self.float(rows) : rows
    return RowsAnswer(rows: listed.map { Self.row($0, home: home, bonus: bonus($0.path)) }, rankText: q.text,
      emptyStatus: empty)
  }

  // How much you use a path, the row's bonus, engine:preference.
  private func bonus(_ path: String) -> Double { frecency?.preference(path) ?? 0 }

  /// engine:_float, the paths you have used ahead of the recent list's dates, recentFloat of them,
  /// in the order recentFloatOrder names.
  /// One the dates hold is moved up, keeping its date, and one they lack is built and stat'd.
  func float(_ rows: [IndexRow]) -> [IndexRow] {
    guard let frecency, settings.recentFloat > 0 else { return rows }
    let top = frecency.top(settings.recentFloat, by: settings.recentFloatOrder)
    guard !top.isEmpty else { return rows }
    var byPath: [String: IndexRow] = [:]
    for r in rows where byPath[r.path] == nil { byPath[r.path] = r }
    var out: [IndexRow] = []
    var seen = Set<String>()
    for path in top where seen.insert(path).inserted {
      out.append(byPath[path] ?? Self.stat(path))
    }
    out += rows.filter { !seen.contains($0.path) }
    return out
  }

  // A row no source returned, as the index would have written it.
  static func stat(_ path: String) -> IndexRow {
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    let mtime = (attrs?[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970) } ?? 0
    let isDir = attrs?[.type] as? FileAttributeType == .typeDirectory
    return IndexRow(path: path, mtime: mtime, isDir: isDir, hidden: (path as NSString).lastPathComponent.hasPrefix("."))
  }

  static func row(_ r: IndexRow, home: String, bonus: Double = 0) -> Row {
    let dir = (r.path as NSString).deletingLastPathComponent
    let shown = dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    return Row(key: r.path, title: r.name, subtitle: shown, icon: .file(r.path), filterText: r.name, bonus: bonus)
  }

  /// chooser.lua's noteUse, every action on a row counting the same, the `..` row and the rows
  /// that are no file excepted.
  private func use(_ pick: Pick) {
    guard let frecency, !pick.key.hasPrefix("olm:"), !isUp(pick) else { return }
    frecency.note(pick.key)
  }

  public func choose(_ pick: Pick) async -> [Effect] {
    switch pick.key {
    case Self.askKey:
      guard let access else { return [] }
      // Each folder in turn, the prompts one at a time, then the list from the top.
      accessState = await access.ask()
      return [.reopen]
    case Self.refusedKey:
      guard let access else { return [] }
      // The answer reset and asked again, or System Settings where tccutil could not reset it.
      guard let next = await access.askAgain(accessState) else {
        return [.hide, .openURL(FolderAccess.settingsURL)]
      }
      accessState = next
      return [.reopen]
    case Self.statusKey:
      return []
    default:
      // The `..` row goes up a level in place, chooser.lua's intercept.
      if isUp(pick), let query = FolderScope.upQuery(
        FileQueryGrammar.parse(pick.query, types: settings.types).scope, roots: settings.roots, home: Self.home) {
        return [.setQuery(query)]
      }
      use(pick)
      return [.hide, .openFile(pick.key)]
    }
  }

  public func run(_ action: String, on pick: Pick) async -> [Effect] {
    guard !pick.key.hasPrefix("olm:") else { return [] }
    if ["reveal", "copyPath", "copyFile", "browseInto", "peekPreview"].contains(action) { use(pick) }
    switch action {
    case "reveal": return [.hide, .revealFile(pick.key)]
    // A plain clipboard write, then the list closes, chooser.lua's copyPath.
    case "copyPath": return [.hide, .copyText(pick.key)]
    // The `..` row is where the list stands rather than a thing chosen, chooser.lua's copyFile.
    case "copyFile": return isUp(pick) ? [] : [.hide, .copyFile(pick.key)]
    // A folder's own level, the folder written as a scope, engine.lua's browseQueryFor.
    case "browseInto":
      guard FolderScope.isDir(pick.key) else { return [] }
      var path = pick.key
      while path.count > 1, path.hasSuffix("/") { path.removeLast() }
      return [.setQuery(path == "/" ? "/" : path + "/")]
    // The level above the folder the query names, engine.lua's upQuery.
    case "browseUp":
      let scope = FileQueryGrammar.parse(pick.query, types: settings.types).scope
      guard let query = FolderScope.upQuery(scope, roots: settings.roots, home: Self.home) else { return [] }
      return [.setQuery(query)]
    // Over the list, which stays up, chooser.lua's peekPreview, step 1.4c.
    case "peekPreview": return [.quickLook(pick.key)]
    default: return []
    }
  }

  /// The three gates chooser.lua's colon methods answer. isEntry is a real file or folder rather
  /// than a permission row, isFolder a real folder, and isBrowsing a query naming a folder with
  /// one above it, step 1.4e.
  public func applies(_ gate: String, on pick: Pick) async -> Bool {
    switch gate {
    case "isEntry": return !pick.key.hasPrefix("olm:")
    case "isFolder": return !pick.key.hasPrefix("olm:") && FolderScope.isDir(pick.key)
    case "isBrowsing":
      let scope = FileQueryGrammar.parse(pick.query, types: settings.types).scope
      return FolderScope.upQuery(scope, roots: settings.roots, home: Self.home) != nil
    default: return true
    }
  }

  /// Copy File reads Copy Folder over a folder, chooser.lua's labels.
  public func label(_ verb: String, on pick: Pick) async -> String? {
    guard verb == "copyFile", !pick.key.hasPrefix("olm:") else { return nil }
    var folder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: pick.key, isDirectory: &folder), folder.boolValue else { return nil }
    return "Copy Folder"
  }

  /// What the pane beside the list says about a row, sidepanel.lua's show. The read runs on a
  /// thread of its own rather than on this actor, so the rows of the next keystroke never wait on
  /// it, and it is bounded by peekSeconds, after which the row is described by its name alone, as
  /// the Lua pane does when the helper does not answer in time. A file iCloud holds only as a
  /// placeholder is described by its stat alone and never read, since reading it downloads it,
  /// Milos's call in the 1.4b trial on 2026-11-09, and the pane says it is not downloaded.
  public func preview(_ pick: Pick) async -> Preview? {
    switch pick.key {
    case Self.askKey: return Self.askPreview
    case Self.refusedKey: return Self.refusedPreview(accessState.refused)
    default: break
    }
    let limits = settings.preview
    // A file in a folder macOS refused says so, since nothing in it can be read.
    if let access, let folder = access.refusedFolder(of: pick.key, in: accessState) {
      var preview = describe(pick.key, isDir: false, peek: nil, limits: limits, picture: nil)
      preview.body = Preview.Body(label: "PREVIEW", facts: folder + " not allowed")
      return preview
    }
    if let quick = await Self.bounded(limits.peekSeconds, { Peek.attributes(pick.key) }) ?? nil, quick.dataless {
      if Task.isCancelled { return nil }
      var preview = describe(pick.key, isDir: false, peek: Peek(attrs: quick.attrs), limits: limits, picture: nil)
      preview.body = Preview.Body(label: "PREVIEW", facts: Self.notDownloaded)
      return preview
    }
    if Task.isCancelled { return nil }
    return await read(pick, seconds: limits.peekSeconds)
  }

  static let askPreview = Preview(name: "Folder Access", facts: [
    Preview.Fact(label: "FOLDERS", value: FolderAccess.spoken(FolderAccess.protectedNames)),
  ], body: Preview.Body(label: "WHY", lines: [
    "File search reads the files it finds, to preview them. macOS protects these folders and asks "
      + "once for each, the first time an app reads one.",
    "Choosing this row asks now, one folder at a time, so no question comes in the middle of a search.",
  ], wrap: true))

  static func refusedPreview(_ names: [String]) -> Preview {
    Preview(name: "Folder Access", facts: [
      Preview.Fact(label: "REFUSED", value: FolderAccess.spoken(names)),
    ], body: Preview.Body(label: "WHY", lines: [
      "macOS does not ask twice on its own. Choosing this row forgets Olm's answer for "
        + (names.count == 1 ? "that folder" : "those folders") + " and asks again.",
    ], wrap: true))
  }

  /// What the preview pane says of a file iCloud has not downloaded to this Mac.
  public static let notDownloaded = "in iCloud, not downloaded"

  /// The row whose preview said rendering, once its render lands, sidepanel.lua's rebuild when the
  /// thumbnail chain answers late. Cancelled when the highlight moves on, which leaves the render.
  public func previewLanded(_ pick: Pick) async -> Preview? {
    guard let row = rendering[pick.key] else { return nil }
    let limits = settings.preview
    let picture = await thumbs.landed(row.spec, limits: limits)
    if Task.isCancelled || picture == .rendering { return nil }
    rendering[pick.key] = nil
    return describe(pick.key, isDir: row.isDir, peek: row.peek, limits: limits, picture: picture)
  }

  // The whole read of a row, its head or folder and its picture, bounded by seconds.
  private func read(_ pick: Pick, seconds: Double) async -> Preview? {
    // A folder by the index's word for it, as the Lua row's isDir, and by the read's own stat for a
    // row the rows held no longer name.
    if folders == nil { folders = Set(held?.rows.filter(\.isDir).map(\.path) ?? []) }
    let listed = held?.rows.contains { $0.path == pick.key } ?? false
    let limits = settings.preview
    let peek = await Self.bounded(seconds) {
      Peek.read(pick.key, readCap: limits.readCap, entries: limits.folderEntries)
    }
    if Task.isCancelled { return nil }
    let isDir = listed ? (folders?.contains(pick.key) ?? false) : (peek?.attrs?.isDir ?? false)
    var picture: PictureState?
    let spec = PreviewDescriber.thumbSpec(path: pick.key, isDir: isDir, peek: peek)
    if let spec {
      picture = await thumbs.picture(spec, limits: limits)
      if Task.isCancelled { return nil }
      if picture == .rendering { rendering[pick.key] = (spec, isDir, peek) }
    }
    return describe(pick.key, isDir: isDir, peek: peek, limits: limits, picture: picture)
  }

  private func describe(_ path: String, isDir: Bool, peek: Peek?, limits: PreviewLimits,
                        picture: PictureState?) -> Preview {
    PreviewDescriber.describe(path: path, isDir: isDir, peek: peek, limits: limits,
      now: Int(Date().timeIntervalSince1970), home: FileManager.default.homeDirectoryForCurrentUser.path,
      picture: picture, usedAt: frecency?.usedAt(path))
  }

  // What work answers, or nil once seconds pass first. Work stuck on a disk that is not there
  // finishes on its own thread and is dropped.
  static func bounded<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () -> T) async -> T? {
    let once = Once()
    return await withCheckedContinuation { (done: CheckedContinuation<T?, Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        let value = work()
        if once.claim() { done.resume(returning: value) }
      }
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, seconds)) {
        if once.claim() { done.resume(returning: nil) }
      }
    }
  }

  // The first of two answers to arrive, the other dropped.
  private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
      lock.withLock {
        if done { return false }
        done = true
        return true
      }
    }
  }

  public func close() async {}

  /// Why the shadow of step 1.3e leaves a query out, or nil to compare it. A browse is compared,
  /// since ls orders it, and a search beneath a folder is not, since fd answers in no fixed order
  /// and stops at its cap, Milos's call on 2026-11-10. The recent list is compared since step 1.4d,
  /// with frecency left out on both sides, the Lua side handing its dates before the float and the
  /// shadow's source keeping no store, docs/DESIGN-APP-FRECENCY.md.
  public static func shadowSkip(_ raw: String, settings: FileSearchSettings) -> String? {
    let q = FileQueryGrammar.parse(raw, types: settings.types)
    if q.scope != nil, q.kind != .browse { return "a search beneath a folder, which fd answers in no fixed order" }
    return nil
  }
}
