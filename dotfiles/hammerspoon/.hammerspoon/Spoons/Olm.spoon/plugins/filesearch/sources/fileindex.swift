// The file index helper. It does every piece of file search work that touches many paths, so
// none of that memory is ever Hammerspoon's. Each run does one thing, prints, and exits, and
// whatever it allocated leaves with the process.
//
//   fileindex build  OUT PRUNE ROOT...      walk ROOTs into the index file OUT
//   fileindex search INDEX LIMIT [-h] [-e EXT]... WORD...
//   fileindex recent INDEX LIMIT SINCE [-e EXT]...
//
// The index is one line per entry, `mtime TAB flags TAB path`. flags holds `d` for a folder and
// `h` for a path with a dot segment below its root, which is how a search leaves hidden files
// out unless asked and recent leaves them out always. PRUNE is a list of names joined by
// newlines, never descended into, the same names the plugin's own prune setting holds.
//
// The index is mapped rather than read, so a search touches clean file backed pages that are
// never counted as this process's memory, and only the matching lines are copied out.

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

// A rough first ranking, only good enough that the best LIMIT rows are the ones handed back.
// The shared search in Olm ranks those again, so this only has to keep the right candidates.
// Every word must be in the name. A name that starts with the first word beats one where a
// word starts after a separator, which beats one that merely contains it, and a shorter name
// wins a tie, since a query names a short name more completely.
func search(index: String, limit: Int, hidden: Bool, exts: [[UInt8]], words: [String]) -> Int32 {
  let needles = words.map { Array($0.lowercased().utf8) }
  var found: [(score: Int, line: Line)] = []

  let ok = withIndex(index) { bytes in
    forEachLine(bytes) { l in
      if l.hidden && !hidden { return }
      let nameStart = nameStart(bytes, l)
      if !hasExt(exts, bytes, nameStart, l.end) { return }
      var score = 0
      for (k, w) in needles.enumerated() {
        guard let at = find(w, in: bytes, nameStart, l.end) else { return }
        if at == nameStart {
          score += k == 0 ? 300 : 200
        } else {
          let prev = bytes[at - 1]
          let boundary = prev == 0x20 || prev == 0x2D || prev == 0x5F || prev == 0x2E
          score += boundary ? 150 : 50
        }
      }
      score -= min(l.end - nameStart, 100)
      found.append((score, l))
    }
    found.sort { $0.score != $1.score ? $0.score > $1.score : $0.line.mtime > $1.line.mtime }
    emit(bytes, found.prefix(limit).map(\.line))
  }
  return ok ? 0 : 1
}

// MARK: recent

// The newest files changed at or after SINCE, folders and hidden paths left out, newest first.
// A date more than a day ahead is corrupt metadata rather than a recent file, and is left out,
// or one such file would sit at the top of the list for good.
func recent(index: String, limit: Int, since: Int, exts: [[UInt8]]) -> Int32 {
  let horizon = Int(time(nil)) + 86400
  var found: [Line] = []
  let ok = withIndex(index) { bytes in
    forEachLine(bytes) { l in
      if l.isDir || l.hidden || l.mtime < since || l.mtime > horizon { return }
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

func main() -> Int32 {
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
  default:
    return 2
  }
}

exit(main())
