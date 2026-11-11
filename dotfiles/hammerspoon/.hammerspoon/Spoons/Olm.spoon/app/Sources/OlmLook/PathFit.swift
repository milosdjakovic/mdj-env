// A folder fitted to a row, a port of plugins/filesearch/util.lua's elideDir, step 1.5 of
// docs/PLAN-STANDALONE.md, docs/PARITY-FILESEARCH.md. Whole folders are dropped from the middle,
// never letters from the end, so the head and the folder holding the file stay. The arithmetic is
// the Lua's in the same order, measured by the caller's width, so both lists cut at the same folder.

import Foundation

public enum PathFit {
  /// dir as it fits budget points, measured by width, or dir whole where it fits or has no middle.
  public static func elide(_ dir: String, budget: Double, width: (String) -> Double) -> String {
    if dir.isEmpty { return dir }
    if budget <= 0 || width(dir) <= budget { return dir }
    let parts = dir.split(separator: "/").map(String.init)
    // With two components or fewer there is no middle to drop, so the row's own tail cut applies.
    let n = parts.count
    if n <= 2 { return dir }
    let sep = width("/")
    let absolute = dir.hasPrefix("/")
    // The leading slash, each head component with its separator, and the ellipsis, the narrow head
    // the wide one without its second component.
    let narrow = (absolute ? sep : 0) + width("\u{2026}") + width(parts[0]) + sep
    let wide = narrow + width(parts[1]) + sep
    // A two component head needs four components and room for the leaf beside it.
    var head = 2, fixed = wide
    if n < 4 || wide + sep + width(parts[n - 1]) > budget { head = 1; fixed = narrow }
    // The tail grows while it fits, and stops one past the head so the ellipsis stands for a folder.
    var keep = 0, running = 0.0
    var i = n
    while i >= head + 2 {
      let next = running + sep + width(parts[i - 1])
      if fixed + next > budget { break }
      running = next
      keep = n - i + 1
      i -= 1
    }
    // Even the leaf alone overruns, so it is shown regardless.
    if keep < 1 { keep = 1 }
    let kept = Array(parts[0..<head]) + ["\u{2026}"] + Array(parts[(n - keep)...])
    let joined = kept.joined(separator: "/")
    return absolute ? "/" + joined : joined
  }
}
