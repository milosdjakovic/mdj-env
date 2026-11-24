// The sidebar's search over everything the window holds, every setting, every choice of a menu,
// every application, every window layout and size, and every permission. Typing shows the results
// in a dropdown under the field, and choosing one opens its section, scrolls to its row and lights
// it for a moment, as System Settings does.

import AppKit
import SwiftUI

/// One thing a search can land on, the row it lights and the section that holds it.
struct SearchHit: Identifiable, Equatable {
  /// The row's target, setting:<id>, app:<bundle>, window:<action>, size:<id> or permission:<id>.
  let id: String
  let section: String
  let title: String
  /// Where it sits, the section and, for a choice, the setting it belongs to.
  let detail: String
  let symbol: String
  /// The application's bundle, whose icon the row wears.
  var bundle: String?
  /// The plugin whose own page holds it, opened before the row is lit.
  var page: String?
  /// The words it is found by beyond its title.
  let words: [String]
  /// Its place in the window's order, which breaks a tie.
  var order = 0
}

enum SearchTarget {
  static func setting(_ id: String) -> String { "setting:" + id }
  static func app(_ bundle: String) -> String { "app:" + bundle }
  static func window(_ action: String) -> String { "window:" + action }
  static func size(_ id: String) -> String { "size:" + id }
  static func permission(_ id: String) -> String { "permission:" + id }
}

@MainActor
enum SettingsSearch {
  /// Every hit the window holds now, in the sidebar's order.
  static func index(_ model: SettingsModel) -> [SearchHit] {
    var out: [SearchHit] = []
    for section in model.share?.sections ?? [] {
      for setting in section.settings {
        switch setting.kind {
        case .apps:
          out += apps(setting, section, model.appsPage)
        case .sizes:
          for a in setting.windowActions {
            out.append(SearchHit(id: SearchTarget.window(a.action), section: section.id, title: a.title,
              detail: section.title, symbol: section.symbol, words: [a.group]))
          }
          for z in setting.value.sizes ?? [] where !setting.windowActions.contains(where: { $0.size == z.id }) {
            out.append(SearchHit(id: SearchTarget.size(z.id), section: section.id, title: z.name,
              detail: "\(section.title) › Sizes", symbol: section.symbol, words: ["size"]))
          }
        case .keys:
          continue
        default:
          let target = SearchTarget.setting(setting.id)
          // A setting on a plugin's own page says the plugin after the section.
          let place = setting.page.map { page in
            "\(section.title) › " + (section.settings.first { $0.plugin == page }?.title ?? page)
          } ?? section.title
          out.append(SearchHit(id: target, section: section.id, title: setting.title, detail: place,
            symbol: section.symbol, page: setting.page, words: setting.keywords + [setting.detail ?? ""]))
          // A menu's choices, each found by its own name and landing on the menu.
          for choice in setting.choices where choice.title.lowercased() != setting.title.lowercased() {
            out.append(SearchHit(id: target, section: section.id, title: choice.title,
              detail: "\(place) › \(setting.title)", symbol: section.symbol, page: setting.page, words: []))
          }
        }
      }
    }
    for p in model.permissions {
      out.append(SearchHit(id: SearchTarget.permission(p.id), section: PermissionsPage.id, title: p.title,
        detail: PermissionsPage.section.title, symbol: p.symbol, words: [p.detail, "permission", "privacy"]))
    }
    for i in out.indices { out[i].order = i }
    return out
  }

  /// Every application the page lists, found or named in the catalog or added here.
  private static func apps(_ setting: Setting, _ section: SettingsSection, _ page: AppsPageModel) -> [SearchHit] {
    var names: [String: String] = [:]
    for app in page.installed { names[app.bundle] = app.name }
    for app in setting.catalog where names[app.bundle] == nil { names[app.bundle] = app.name }
    for (bundle, own) in setting.value.apps ?? [:] where names[bundle] == nil { names[bundle] = own.name ?? bundle }
    return names.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }.map {
      SearchHit(id: SearchTarget.app($0.key), section: section.id, title: $0.value, detail: section.title,
        symbol: section.symbol, bundle: $0.key, words: ["app", "application"])
    }
  }

  /// The hits a query finds, every word found in the title or the words, the title's own matches
  /// first: the title starting with the query, then a word of it starting with each, then the rest.
  static func find(_ query: String, in hits: [SearchHit], limit: Int = 60) -> [SearchHit] {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    let words = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !words.isEmpty else { return [] }
    var scored: [(Int, SearchHit)] = []
    var seen = Set<String>()
    for hit in hits {
      let title = hit.title.lowercased()
      let hay = ([title, hit.detail.lowercased()] + hit.words.map { $0.lowercased() }).joined(separator: " ")
      guard words.allSatisfy({ hay.contains($0) }) else { continue }
      let starts = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
      let score: Int
      if title.hasPrefix(q) { score = 0 }
      else if words.allSatisfy({ w in starts.contains { $0.hasPrefix(w) } }) { score = 1 }
      else if words.allSatisfy({ title.contains($0) }) { score = 2 }
      else { score = 3 }
      // One row per place and title, a choice named like its menu said once.
      guard seen.insert(hit.id + "|" + title).inserted else { continue }
      scored.append((score, hit))
    }
    return scored.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.order < $1.1.order }.prefix(limit).map(\.1)
  }
}

/// The dropdown under the search, a glass card of results, the highlighted one lit, a press or
/// Return choosing it.
struct SearchResults: View {
  @ObservedObject var model: SettingsModel
  @ObservedObject var page: AppsPageModel
  let hits: [SearchHit]
  let highlighted: Int
  let choose: (SearchHit) -> Void

  var body: some View {
    Group {
      if hits.isEmpty {
        Text("No Results").foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: Space.rowHeight * 2)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(spacing: 0) {
              ForEach(Array(hits.enumerated()), id: \.offset) { index, hit in
                row(hit, lit: index == highlighted).id(index)
              }
            }
            .padding(Space.related)
          }
          .scrollIndicators(.never)
          .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
        }
      }
    }
    .glassCard(cornerRadius: 16)
  }

  private func row(_ hit: SearchHit, lit: Bool) -> some View {
    Button { choose(hit) } label: {
      HStack(spacing: Space.pad) {
        Group {
          if let bundle = hit.bundle, let icon = page.icons[bundle] {
            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
          } else {
            Image(systemName: hit.symbol).foregroundStyle(.tint)
          }
        }
        .frame(width: 20)
        VStack(alignment: .leading, spacing: 0) {
          Text(hit.title).lineLimit(1)
          Text(hit.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Space.pad - Space.related)
      .padding(.vertical, Space.related)
      .contentShape(Rectangle())
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(lit ? Color.primary.opacity(0.09) : .clear))
    }
    .buttonStyle(.plain)
  }
}

/// A row a search can land on: it carries its target as its scroll id and lights while the window
/// says so, the light fading on its own.
struct SearchMark: ViewModifier {
  @ObservedObject var model: SettingsModel
  let target: String

  func body(content: Content) -> some View {
    content
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.tint.opacity(model.lit == target ? 0.18 : 0))
        .padding(-Space.related))
      .animation(.easeOut(duration: 0.35), value: model.lit)
      .id(target)
  }
}

/// A page's scroll view going to the row a search chose, once that row is on the page, the
/// applications arriving after the scan included.
struct SearchJump: ViewModifier {
  @ObservedObject var model: SettingsModel
  let proxy: ScrollViewProxy
  /// The targets the page holds now.
  let present: Set<String>

  func body(content: Content) -> some View {
    content
      .onAppear(perform: go)
      .onChange(of: model.focus) { go() }
      .onChange(of: present) { go() }
  }

  private func go() {
    guard let target = model.focus, present.contains(target) else { return }
    DispatchQueue.main.async {
      model.focus = nil
      withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
      model.lit = target
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
        if model.lit == target { model.lit = nil }
      }
    }
  }
}

extension View {
  func searchMark(_ model: SettingsModel, _ target: String) -> some View {
    modifier(SearchMark(model: model, target: target))
  }

  func searchJump(_ model: SettingsModel, _ proxy: ScrollViewProxy, _ present: Set<String>) -> some View {
    modifier(SearchJump(model: model, proxy: proxy, present: present))
  }
}
