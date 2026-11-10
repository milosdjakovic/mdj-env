// The file index helper. It does every piece of file search work that touches many paths, so
// none of that memory is ever Hammerspoon's. Each run does one thing, prints, and exits, and
// whatever it allocated leaves with the process.
//
//   fileindex build  OUT PRUNE ROOT...      walk ROOTs into the index file OUT
//   fileindex search INDEX LIMIT [-h] [-e EXT]... WORD...
//   fileindex recent INDEX LIMIT SINCE [-e EXT]...
//   fileindex peek   PATH OUT READCAP SCANCAP ENTRIES
//
// peek is what the preview pane knows about one path. It stands here because a stat, a folder scan
// or a read can take seconds on a file that is not on this disk yet, and on Hammerspoon's main
// thread that is seconds of no typing and no leader keys. It writes OUT rather than printing, since
// hs.task hands stdout over as text and a file's head need not be valid UTF-8, nor be cut on a
// character boundary. OUT is one header line, `file|dir TAB size TAB mtime TAB birthtime`, or the
// word `missing`. After it comes the first READCAP bytes of a file, or for a folder a line
// `scanned TAB truncated` and then `mtime TAB d-or-dash TAB name`, newest first, at most ENTRIES of
// the first SCANCAP entries, with no second line at all for a folder that could not be opened.
//
// The index is one line per entry, `mtime TAB flags TAB path`. flags holds `d` for a folder and
// `h` for a path with a dot segment below its root, which is how a search leaves hidden files
// out unless asked and recent leaves them out always. PRUNE is a list of names joined by
// newlines, never descended into, the same names the plugin's own prune setting holds.
//
// The index is mapped rather than read, so a search touches clean file backed pages that are
// never counted as this process's memory, and only the matching lines are copied out.
//
// It is compiled together with the shared search, app/Sources/OlmSearch/Match.swift, the Swift
// copy of lib/chooser/match.lua, which the root hands the plugin the path of. So a search keeps a
// name exactly when the list would, one typo included, and typing on over held rows and asking
// again for the same text find the same files.

import Darwin
import Foundation

// MARK: build

// Bundles are listed but never entered. Their insides are thousands of resource files nobody
// searches for by name, and an app is found by its bundle.
let bundleExtensions: Set<String> = [
  "app", "appex", "framework", "bundle", "plugin", "kext", "xpc", "photoslibrary",
]

func build(out: String, prune: Set<String>, roots: [String]) -> Int32 {
  let tmp = out + ".tmp"
  guard let file = fopen(tmp, "w") else { return 1 }
  // A large stdio buffer, since the index is written in one pass of short lines.
  setvbuf(file, nil, _IOFBF, 1 << 20)

  var paths = roots.map { strdup($0) } + [nil]
  defer { paths.forEach { free($0) } }
  guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
    fclose(file)
    return 1
  }

  var count = 0
  while let ent = fts_read(fts) {
    let info = Int32(ent.pointee.fts_info)
    if info == FTS_DP || info == FTS_DNR || info == FTS_ERR || info == FTS_NS { continue }
    let name = withUnsafePointer(to: &ent.pointee.fts_name) {
      String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
    }
    let level = Int(ent.pointee.fts_level)
    let isDir = info == FTS_D

    if level > 0 && prune.contains(name) {
      if isDir { fts_set(fts, ent, FTS_SKIP) }
      continue
    }
    if isDir, let dot = name.lastIndex(of: "."),
      bundleExtensions.contains(name[name.index(after: dot)...].lowercased())
    {
      fts_set(fts, ent, FTS_SKIP)
    }
    if level == 0 { continue }

    // A dot segment anywhere below the root marks the entry hidden. The parent's answer is
    // carried down in fts_number, so it is decided once per folder rather than per path.
    let parentHidden = ent.pointee.fts_parent.pointee.fts_number != 0
    let hidden = parentHidden || name.hasPrefix(".")
    ent.pointee.fts_number = hidden ? 1 : 0

    let mtime = ent.pointee.fts_statp.map { Int($0.pointee.st_mtimespec.tv_sec) } ?? 0
    let flags = (isDir ? "d" : "") + (hidden ? "h" : "")
    fputs("\(mtime)\t\(flags)\t", file)
    fwrite(ent.pointee.fts_path, 1, Int(ent.pointee.fts_pathlen), file)
    fputc(0x0A, file)
    count += 1
  }
  fts_close(fts)
  guard fclose(file) == 0, count > 0, rename(tmp, out) == 0 else {
    unlink(tmp)
    return 1
  }
  print(count)
  return 0
}

// MARK: reading the index

// One line of the mapped index, as byte offsets, so nothing is copied until it is printed.
struct Line {
  let start: Int, end: Int  // the whole line, without its newline
  let path: Int  // where the path begins
  let mtime: Int
  let isDir: Bool, hidden: Bool
}

func forEachLine(_ bytes: UnsafeBufferPointer<UInt8>, _ body: (Line) -> Void) {
  let n = bytes.count
  var i = 0
  while i < n {
    let start = i
    var mtime = 0
    while i < n && bytes[i] != 0x09 {
      mtime = mtime &* 10 &+ Int(bytes[i] &- 0x30)
      i += 1
    }
    i += 1
    var isDir = false, hidden = false
    while i < n && bytes[i] != 0x09 {
      if bytes[i] == 0x64 { isDir = true } else if bytes[i] == 0x68 { hidden = true }
      i += 1
    }
    i += 1
    let path = i
    guard let nl = memchr(bytes.baseAddress! + i, 0x0A, n - i) else { return }
    let end = bytes.baseAddress!.distance(to: nl.assumingMemoryBound(to: UInt8.self))
    body(Line(start: start, end: end, path: path, mtime: mtime, isDir: isDir, hidden: hidden))
    i = end + 1
  }
}

func withIndex(_ path: String, _ body: (UnsafeBufferPointer<UInt8>) -> Void) -> Bool {
  guard let data = try? Data(contentsOf: URL(filePath: path), options: .alwaysMapped) else {
    return false
  }
  data.withUnsafeBytes { raw in body(raw.bindMemory(to: UInt8.self)) }
  return true
}

func emit(_ bytes: UnsafeBufferPointer<UInt8>, _ lines: [Line]) {
  let out = FileHandle.standardOutput
  var buf = [UInt8]()
  buf.reserveCapacity(lines.count * 96)
  for l in lines {
    buf.append(contentsOf: bytes[l.start..<l.end])
    buf.append(0x0A)
  }
  out.write(Data(buf))
}

// MARK: search

@inline(__always) func lower(_ b: UInt8) -> UInt8 { b >= 0x41 && b <= 0x5A ? b | 0x20 : b }

// Where a lowered ASCII needle first occurs in a slice, compared case insensitively. Non ASCII
// bytes compare as they are, which keeps an accented name findable by its own spelling.
func find(_ needle: [UInt8], in h: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Int? {
  let m = needle.count
  guard m > 0, to - from >= m else { return m == 0 ? from : nil }
  let first = needle[0]
  var i = from
  let last = to - m
  while i <= last {
    if lower(h[i]) == first {
      var j = 1
      while j < m && lower(h[i + j]) == needle[j] { j += 1 }
      if j == m { return i }
    }
    i += 1
  }
  return nil
}

// Whether a name ends in one of the extensions, each already lowered and led by its dot.
func hasExt(_ exts: [[UInt8]], _ h: UnsafeBufferPointer<UInt8>, _ nameStart: Int, _ end: Int) -> Bool {
  if exts.isEmpty { return true }
  for e in exts where end - nameStart > e.count && find(e, in: h, end - e.count, end) != nil {
    return true
  }
  return false
}

@inline(__always) func nameStart(_ h: UnsafeBufferPointer<UInt8>, _ l: Line) -> Int {
  var i = l.end
  while i > l.path && h[i - 1] != 0x2F { i -= 1 }
  return i
}

// Every name the shared search keeps for the words, ranked by its score, and a newer file wins a
// tie. The search is asked for the name alone, since a file row is found by its name. The rows
// are ranked again in Olm, so this only has to keep the right candidates in LIMIT. Until
// 2026-11-09 a name had to hold every word whole, so the list kept a name one typo away only
// when typing on narrowed rows a shorter word had brought back, and a fresh search did not.
func search(index: String, limit: Int, hidden: Bool, exts: [[UInt8]], words: [String]) -> Int32 {
  let query = words.joined(separator: " ")
  let fuzzy = Fuzzy()
  // Each word as the prefilter reads it, folded as the matcher folds it, lowered, and its letters
  // and digits only.
  let cores: [[UInt8]] = words.map { w in
    Array(Fuzzy.fold(w).lowercased().utf8).filter { b in (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x7A) || b >= 0x80 }
  }.filter { !$0.isEmpty }
  var found: [(score: Double, line: Line)] = []

  let ok = withIndex(index) { bytes in
    forEachLine(bytes) { l in
      if l.hidden && !hidden { return }
      let start = nameStart(bytes, l)
      if !hasExt(exts, bytes, start, l.end) { return }
      // A name the search keeps holds each word, less at most one letter, in order, at every
      // level, a word start, pieces, one edit or inside a word. So a name where that fails is
      // passed over before the matcher is asked. A name past ASCII is always asked, since the
      // matcher folds an accent the byte compare cannot see.
      if !nonASCII(bytes, start, l.end) {
        for w in cores where !nearlyInOrder(w, bytes, start, l.end) { return }
      }
      let name = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<l.end]), as: UTF8.self)
      guard let m = fuzzy.match(query, SearchFields(primary: name)) else { return }
      found.append((m.score, l))
    }
    found.sort { $0.score != $1.score ? $0.score > $1.score : $0.line.mtime > $1.line.mtime }
    emit(bytes, found.prefix(limit).map(\.line))
  }
  return ok ? 0 : 1
}

// Whether w, less at most one letter, occurs in order in h[from..<to], compared lowered. The
// longest prefix taken from the left and the longest suffix taken from the right leave out at
// most one letter between them exactly when it does.
func nearlyInOrder(_ w: [UInt8], _ h: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Bool {
  let n = w.count
  var p = 0, i = from
  while i < to && p < n { if lower(h[i]) == w[p] { p += 1 }; i += 1 }
  if p >= n - 1 { return true }
  var q = 0, j = to - 1
  while j >= from && q < n { if lower(h[j]) == w[n - 1 - q] { q += 1 }; j -= 1 }
  return p + q >= n - 1
}

func nonASCII(_ h: UnsafeBufferPointer<UInt8>, _ from: Int, _ to: Int) -> Bool {
  var i = from
  while i < to { if h[i] >= 0x80 { return true }; i += 1 }
  return false
}

// MARK: recent

// The newest files changed at or after SINCE, folders and hidden paths left out, newest first.
// A folder whose name ends in a type asked for is kept, since to a person it is a file, a bundle,
// so `.app` lists every app rather than the one the index does not mark as a folder, step 1.4h.
// A date more than a day ahead is corrupt metadata rather than a recent file, and is left out,
// or one such file would sit at the top of the list for good.
func recent(index: String, limit: Int, since: Int, exts: [[UInt8]]) -> Int32 {
  let horizon = Int(time(nil)) + 86400
  var found: [Line] = []
  let ok = withIndex(index) { bytes in
    forEachLine(bytes) { l in
      if (l.isDir && exts.isEmpty) || l.hidden || l.mtime < since || l.mtime > horizon { return }
      if !hasExt(exts, bytes, nameStart(bytes, l), l.end) { return }
      found.append(l)
    }
    found.sort { $0.mtime > $1.mtime }
    emit(bytes, Array(found.prefix(limit)))
  }
  return ok ? 0 : 1
}

// MARK: main

// The flags, the extensions each given after -e, and the remaining words.
func options(_ args: ArraySlice<String>) -> (flags: Set<String>, exts: [[UInt8]], words: [String]) {
  var flags = Set<String>(), exts: [[UInt8]] = [], words: [String] = []
  var it = args.makeIterator()
  while let arg = it.next() {
    if arg == "-e" {
      if let e = it.next() { exts.append(Array(("." + e.lowercased()).utf8)) }
    } else if arg == "-h" {
      flags.insert(arg)
    } else {
      words.append(arg)
    }
  }
  return (flags, exts, words)
}

// MARK: peek

func folderListing(_ path: String, scanCap: Int, entries: Int) -> String? {
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
    found.append((
      at: known ? Int(info.st_mtimespec.tv_sec) : 0,
      isDir: known && (info.st_mode & S_IFMT) == S_IFDIR,
      name: name.replacingOccurrences(of: "\n", with: " ")
    ))
  }
  found.sort { $0.at > $1.at }
  var text = "\(min(scanned, scanCap))\t\(truncated ? 1 : 0)\n"
  for item in found.prefix(entries) {
    text += "\(item.at)\t\(item.isDir ? "d" : "-")\t\(item.name)\n"
  }
  return text
}

func peek(path: String, out: String, readCap: Int, scanCap: Int, entries: Int) -> Int32 {
  var answer = Data()
  var info = stat()
  if stat(path, &info) != 0 {
    answer.append(Data("missing\n".utf8))
  } else {
    let isDir = (info.st_mode & S_IFMT) == S_IFDIR
    let times = "\(info.st_mtimespec.tv_sec)\t\(info.st_birthtimespec.tv_sec)"
    answer.append(Data("\(isDir ? "dir" : "file")\t\(info.st_size)\t\(times)\n".utf8))
    if isDir {
      if let listing = folderListing(path, scanCap: scanCap, entries: entries) {
        answer.append(Data(listing.utf8))
      }
    } else if let handle = FileHandle(forReadingAtPath: path) {
      if let head = try? handle.read(upToCount: readCap) { answer.append(head) }
      try? handle.close()
    }
  }
  do {
    try answer.write(to: URL(fileURLWithPath: out), options: .atomic)
    return 0
  } catch {
    return 1
  }
}

func fileindexMain() -> Int32 {
  let a = CommandLine.arguments
  guard a.count >= 2 else { return 2 }
  switch a[1] {
  case "build" where a.count >= 5:
    let prune = Set(a[3].split(separator: "\n").map(String.init))
    return build(out: a[2], prune: prune, roots: Array(a[4...]))
  case "search" where a.count >= 4:
    guard let limit = Int(a[3]) else { return 2 }
    let (flags, exts, words) = options(a[4...])
    return search(index: a[2], limit: limit, hidden: flags.contains("-h"), exts: exts, words: words)
  case "recent" where a.count >= 5:
    guard let limit = Int(a[3]), let since = Int(a[4]) else { return 2 }
    return recent(index: a[2], limit: limit, since: since, exts: options(a[5...]).exts)
  case "peek" where a.count >= 7:
    guard let readCap = Int(a[4]), let scanCap = Int(a[5]), let entries = Int(a[6]) else { return 2 }
    return peek(path: a[2], out: a[3], readCap: readCap, scanCap: scanCap, entries: entries)
  default:
    return 2
  }
}

// The entry point, a type rather than a line at the top level, since the helper is two files.
@main
enum FileIndexTool {
  static func main() { exit(fileindexMain()) }
}
