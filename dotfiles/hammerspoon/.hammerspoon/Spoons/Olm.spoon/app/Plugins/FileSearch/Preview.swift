// What file search's preview pane says about a row, step 1.4a of docs/PLAN-STANDALONE.md, the port of
// plugins/filesearch/viewers/sidepanel.lua's describers and of the helper's peek in
// plugins/filesearch/sources/fileindex.swift. A plugin never draws, so this answers a Preview, the
// header's facts and a body, and the core lays it out the way the Lua pane does.
//
// The read is the helper's own, a stat, a folder scan newest first or the head of a file, done here
// in process rather than by running the helper, on a thread of its own and bounded by peekSeconds,
// so a slow disk holds up its own preview and never a row or a key. What it found is described by
// the same chain the Lua pane runs, a folder, then a picture type, then text, and a row nothing
// answers for is described by its header alone.
//
// A type the thumbnail chain covers, Thumbs.swift, is described by its picture since step 1.4b,
// the PREVIEW heading over the picture, over "rendering" while Quick Look draws it, the preview
// then pending so the stage asks again, and over "no preview" when nothing could, the words and the
// states of the Lua pane's imageBody and _image. Frecency is 1.4d, so the header has no USED fact.
// test/fixtures/chooser/pane.json pins both this and the layout, run by olm-fixtures, its
// expectations recorded from the Lua pane.

import Foundation
import OlmKit

/// config/filesearch.lua's preview block, the numbers that bound what one highlighted row costs.
public struct PreviewLimits: Equatable, Sendable {
  public var settleMs = 60
  public var peekSeconds = 5.0
  public var readCap = 64 * 1024
  public var headLines = 400
  public var headSlack = 20
  public var folderEntries = 100
  /// The largest raster drawn from the file itself, thumbs.lua's nativeMaxBytes.
  public var nativeMaxBytes = 1024 * 1024
  /// The larger edge of a Quick Look render, in pixels.
  public var imageEdge = 600
  /// How many renders are kept before the oldest are swept.
  public var cacheFiles = 400
  /// The Lua side's renders, read and never written by the app, nil for none.
  public var cacheDir: String?
  public init() {}

  /// The block as the bridge wrote it, each field the Lua default when it is missing.
  public init(_ object: [String: Any]) {
    func int(_ name: String) -> Int? { (object[name] as? NSNumber).map { $0.intValue } }
    settleMs = int("settleMs") ?? settleMs
    peekSeconds = (object["peekSeconds"] as? NSNumber)?.doubleValue ?? peekSeconds
    readCap = int("readCap") ?? readCap
    headLines = int("headLines") ?? headLines
    headSlack = int("headSlack") ?? headSlack
    folderEntries = int("folderEntries") ?? folderEntries
    nativeMaxBytes = int("nativeMaxBytes") ?? nativeMaxBytes
    imageEdge = int("imageEdge") ?? imageEdge
    cacheFiles = int("cacheFiles") ?? cacheFiles
    if let dir = object["cacheDir"] as? String {
      cacheDir = dir.hasPrefix("~/") ? NSHomeDirectory() + dir.dropFirst(1) : dir
    }
  }
}

/// What one path holds, as the helper's peek answers it and index.lua's parsePeek shapes it.
public struct Peek: Equatable, Sendable {
  public struct Attrs: Equatable, Sendable {
    public var isDir: Bool
    public var size: Int
    public var modification: Int
    public var creation: Int
    public init(isDir: Bool, size: Int, modification: Int, creation: Int) {
      self.isDir = isDir
      self.size = size
      self.modification = modification
      self.creation = creation
    }
  }

  public struct Entry: Equatable, Sendable {
    /// A folder's name ends in a slash, as parsePeek writes it.
    public var name: String
    public var at: Int
    public init(name: String, at: Int) {
      self.name = name
      self.at = at
    }
  }

  public struct Folder: Equatable, Sendable {
    public var scanned: Int
    public var truncated: Bool
    public var entries: [Entry]
    public init(scanned: Int, truncated: Bool, entries: [Entry]) {
      self.scanned = scanned
      self.truncated = truncated
      self.entries = entries
    }
  }

  /// Nil for a path that is gone.
  public var attrs: Attrs?
  /// The head of a file, the bytes as they are.
  public var blob: Data?
  /// A folder that could be opened.
  public var folder: Folder?

  public init(attrs: Attrs? = nil, blob: Data? = nil, folder: Folder? = nil) {
    self.attrs = attrs
    self.blob = blob
    self.folder = folder
  }

  /// How far into a folder the scan looks, sidepanel.lua's DIR_SCAN_CAP.
  public static let scanCap = 2000

  /// The stat alone, nil for a path that is gone, and whether the file is a placeholder iCloud
  /// holds, its contents not on this Mac, so that opening it downloads it first. A stat never
  /// fetches, so it answers at once where reading the head waits on the download, found in the
  /// 1.4b trial on 2026-11-09 with PDFs in a synced Documents folder.
  public static func attributes(_ path: String) -> (attrs: Attrs, dataless: Bool)? {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    let isDir = (info.st_mode & S_IFMT) == S_IFDIR
    let attrs = Attrs(isDir: isDir, size: Int(info.st_size), modification: Int(info.st_mtimespec.tv_sec),
      creation: Int(info.st_birthtimespec.tv_sec))
    return (attrs, !isDir && (info.st_flags & Self.datalessFlag) != 0)
  }

  // SF_DATALESS in sys/stat.h, a file whose contents are not present.
  static let datalessFlag: UInt32 = 0x4000_0000

  /// The helper's peek of one path, the stat, the folder scan or the head of the file.
  public static func read(_ path: String, readCap: Int, entries: Int, scanCap: Int = Peek.scanCap) -> Peek {
    var info = stat()
    guard stat(path, &info) == 0 else { return Peek() }
    let isDir = (info.st_mode & S_IFMT) == S_IFDIR
    let attrs = Attrs(isDir: isDir, size: Int(info.st_size), modification: Int(info.st_mtimespec.tv_sec),
      creation: Int(info.st_birthtimespec.tv_sec))
    if isDir { return Peek(attrs: attrs, folder: folder(path, scanCap: scanCap, entries: entries)) }
    var blob = Data()
    if let handle = FileHandle(forReadingAtPath: path) {
      if let head = try? handle.read(upToCount: readCap) { blob = head }
      try? handle.close()
    }
    return Peek(attrs: attrs, blob: blob)
  }

  // folderListing in fileindex.swift, its order and its count, newest first.
  static func folder(_ path: String, scanCap: Int, entries: Int) -> Folder? {
    guard let dir = opendir(path) else { return nil }
    defer { closedir(dir) }
    var found: [(at: Int, isDir: Bool, name: String)] = []
    var scanned = 0
    var truncated = false
    let base = path.hasSuffix("/") ? path : path + "/"
    while let entry = readdir(dir) {
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
      }
      if name == "." || name == ".." { continue }
      scanned += 1
      if scanned > scanCap {
        truncated = true
        break
      }
      var info = stat()
      let known = stat(base + name, &info) == 0
      found.append((at: known ? Int(info.st_mtimespec.tv_sec) : 0,
        isDir: known && (info.st_mode & S_IFMT) == S_IFDIR,
        name: name.replacingOccurrences(of: "\n", with: " ")))
    }
    found.sort { $0.at > $1.at }
    let listed = found.prefix(entries).map { Entry(name: $0.isDir ? $0.name + "/" : $0.name, at: $0.at) }
    return Folder(scanned: min(scanned, scanCap), truncated: truncated, entries: Array(listed))
  }
}

/// sidepanel.lua's describers and util.lua's wording, the same strings with the same rounding.
public enum PreviewDescriber {
  /// The types the thumbnail chain draws, thumbs.lua's NATIVE_EXT and QL_EXT, which the picture
  /// describer claims ahead of text, so an svg is never printed as markup.
  public static let pictureExtensions = ThumbChain.extensions

  /// util.basename, the last component with trailing slashes dropped.
  public static func basename(_ path: String) -> String {
    let trimmed = trimSlashes(path)
    guard let slash = trimmed.lastIndex(of: "/") else { return trimmed.isEmpty ? path : trimmed }
    let name = String(trimmed[trimmed.index(after: slash)...])
    return name.isEmpty ? path : name
  }

  /// util.dirname, everything before the last component, nil for a path with no slash.
  public static func dirname(_ path: String) -> String? {
    let trimmed = trimSlashes(path)
    guard let slash = trimmed.lastIndex(of: "/") else { return nil }
    return String(trimmed[..<slash])
  }

  private static func trimSlashes(_ path: String) -> String {
    var s = Substring(path)
    while s.hasSuffix("/") { s = s.dropLast() }
    return String(s)
  }

  /// util.ext, the lower cased letters and digits after the name's last dot, none for a dotfile.
  public static func ext(_ path: String) -> String {
    let name = basename(path)
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
    let e = name[name.index(after: dot)...]
    guard !e.isEmpty, e.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0)) })
    else { return "" }
    return e.lowercased()
  }

  /// util.shortDir, the home folder said as a tilde.
  public static func shortDir(_ dir: String?, home: String) -> String {
    guard let dir, !dir.isEmpty else { return "" }
    let d = Array(dir.utf8), h = Array(home.utf8)
    if !h.isEmpty, d.count >= h.count, Array(d[0..<h.count]) == h {
      return "~" + String(decoding: d[h.count...], as: UTF8.self)
    }
    return dir
  }

  /// util.humanBytes.
  public static func humanBytes(_ n: Int) -> String {
    if n < 1024 { return "\(n) B" }
    if n < 1024 * 1024 { return "\(Int((Double(n) / 1024 + 0.5).rounded(.down))) KB" }
    if n < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(n) / 1024 / 1024) }
    return String(format: "%.1f GB", Double(n) / 1024 / 1024 / 1024)
  }

  /// util.humanAge, how long before now, in one coarse unit.
  public static func humanAge(_ epoch: Int, now: Int) -> String {
    let secs = now - epoch
    if secs < 60 { return "just now" }
    if secs < 3600 { return "\(secs / 60)m ago" }
    if secs < 86400 { return "\(secs / 3600)h ago" }
    return "\(secs / 86400)d ago"
  }

  /// sidepanel.lua's kindOf, in one word. The helper's stat follows a link, so a link reads as
  /// what it points at, as it does on the Lua side.
  public static func kind(name: String, ext: String, isDir: Bool) -> String {
    if isDir {
      if ext == "app" || name.hasSuffix(".app") { return "Application" }
      return "Folder"
    }
    if ext.isEmpty { return "File" }
    return ext.uppercased()
  }

  /// Everything the pane says about one row, path being its key and isDir the index's word for
  /// it. peek nil is a read that never answered, which leaves the row described by its name. picture
  /// is what the thumbnail chain answered for a type it covers, nil for nothing.
  public static func describe(path: String, isDir: Bool, peek: Peek?, limits: PreviewLimits, now: Int,
                              home: String, picture: PictureState? = nil) -> Preview {
    let name = basename(path)
    let ext = isDir ? "" : Self.ext(path)
    let attrs = peek?.attrs
    var facts = [Preview.Fact(label: "KIND", value: kind(name: name, ext: ext, isDir: isDir))]
    if let attrs {
      if !isDir { facts.append(Preview.Fact(label: "SIZE", value: humanBytes(attrs.size))) }
      facts.append(Preview.Fact(label: "CHANGED", value: humanAge(attrs.modification, now: now)))
      facts.append(Preview.Fact(label: "ADDED", value: humanAge(attrs.creation, now: now)))
    }
    let body = folderBody(isDir: isDir, peek: peek, limits: limits)
      ?? pictureBody(isDir: isDir, ext: ext, picture: picture)
      ?? textBody(isDir: isDir, peek: peek, limits: limits)
    return Preview(name: name, dir: shortDir(dirname(path), home: home), facts: facts, body: body,
      pending: body?.label == "PREVIEW" && picture == .rendering)
  }

  /// The file the thumbnail chain is asked a picture of, nil for a row it does not cover.
  public static func thumbSpec(path: String, isDir: Bool, peek: Peek?) -> ThumbSpec? {
    let ext = isDir ? "" : Self.ext(path)
    guard !isDir, pictureExtensions.contains(ext) else { return nil }
    return ThumbSpec(path: path, ext: ext, size: peek?.attrs?.size, modification: peek?.attrs?.modification)
  }

  static func folderBody(isDir: Bool, peek: Peek?, limits: PreviewLimits) -> Preview.Body? {
    guard isDir, let folder = peek?.folder else { return nil }
    if folder.entries.isEmpty { return Preview.Body(label: "FOLDER", facts: "empty") }
    let lines = folder.entries.prefix(limits.folderEntries).map(\.name)
    let plural = (folder.scanned == 1 && !folder.truncated) ? "" : "s"
    let facts = "\(folder.scanned)\(folder.truncated ? "+" : "") item\(plural)"
    return Preview.Body(label: "FOLDER", facts: facts, lines: Array(lines), wrap: false)
  }

  // imageBody, the picture never drawn wider than it is, or a word for where it stands.
  static func pictureBody(isDir: Bool, ext: String, picture: PictureState?) -> Preview.Body? {
    guard !isDir, !ext.isEmpty, pictureExtensions.contains(ext) else { return nil }
    switch picture {
    case .ready(let path): return Preview.Body(label: "PREVIEW", picture: Preview.Picture(path: path, upscale: false))
    case .rendering: return Preview.Body(label: "PREVIEW", facts: "rendering")
    case .failed, nil: return Preview.Body(label: "PREVIEW", facts: "no preview")
    }
  }

  static func textBody(isDir: Bool, peek: Peek?, limits: PreviewLimits) -> Preview.Body? {
    if isDir { return nil }
    let attrs = peek?.attrs
    if let attrs, attrs.size == 0 { return Preview.Body(label: "HEAD", facts: "empty file") }
    guard let blob = peek?.blob, !blob.isEmpty, !blob.contains(0) else { return nil }
    // The terminator only when it is missing, so a file ending in a newline has no phantom line.
    var bytes = [UInt8](blob)
    if bytes.last != 10 { bytes.append(10) }
    var lines: [String] = []
    var start = 0
    for i in bytes.indices where bytes[i] == 10 {
      var end = i
      if end > start, bytes[end - 1] == 13 { end -= 1 }
      lines.append(String(decoding: bytes[start..<end], as: UTF8.self))
      start = i + 1
    }
    // A last line the read cap cut mid way is dropped, when there is a whole line to fall back on.
    let capped = blob.count >= limits.readCap
    if capped, lines.count > 1 { lines.removeLast() }
    return Preview.Body(label: "HEAD", lines: lines, wrap: true, budget: limits.headLines,
      slack: limits.headSlack, total: attrs?.size, hasLines: lines.count > 1 && !capped)
  }
}
