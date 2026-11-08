// The vocabulary every part of Olm.app speaks, docs/DESIGN-APP.md. Value types with no AppKit and
// no behaviour, the shapes docs/PROTOCOL-BRIDGE.md already settled written once as Swift, so a row
// from a native plugin and a row from the bridge are the same value. A plugin is a module that
// imports this and nothing else of Olm's, which is what keeps it from drawing, from holding chooser
// state and from reaching another plugin. Everything here is Sendable, since a source answers on
// its own actor and the stage reads the answer on the main one.

import Foundation

/// What is drawn before a row's title. The stage resolves it, so a plugin never holds a picture.
public enum Icon: Sendable, Hashable {
  /// The icon the system shows for that path.
  case file(String)
}

/// One row, the bridge protocol's row with the fields the app reads today. key is the row's
/// identity, which a pick names it by, and the rest read as lib/chooser/rank.lua reads them.
public struct Row: Sendable, Equatable {
  public var key: String
  public var title: String
  public var subtitle: String
  public var icon: Icon?
  /// The primary search field in place of the title, the subtitle then not searched.
  public var filterText: String?
  /// From zero to one, orders only rows the search calls equally good.
  public var bonus: Double
  public var pinned: Bool
  public var fromQuery: Bool

  public init(key: String, title: String, subtitle: String = "", icon: Icon? = nil,
              filterText: String? = nil, bonus: Double = 0, pinned: Bool = false, fromQuery: Bool = false) {
    self.key = key
    self.title = title
    self.subtitle = subtitle
    self.icon = icon
    self.filterText = filterText
    self.bonus = bonus
    self.pinned = pinned
    self.fromQuery = fromQuery
  }
}

/// A list a source opened, the bridge protocol's level.
public struct Level: Sendable, Equatable {
  public enum Ranking: Sendable, Equatable {
    /// The stage ranks the rows with the shared search, every list that declares no matcher.
    case app
    /// The source's order is final, a field that is not a search.
    case source
  }

  public var placeholder: String
  public var ranking: Ranking
  /// The most rows shown after ranking, nil for none.
  public var rowLimit: Int?
  /// How a title too long for its row loses characters, a lib/chooser/providers/default
  /// geometry name, nil for the look's own.
  public var titleLineBreak: String?

  public init(placeholder: String = "", ranking: Ranking = .app, rowLimit: Int? = nil, titleLineBreak: String? = nil) {
    self.placeholder = placeholder
    self.ranking = ranking
    self.rowLimit = rowLimit
    self.titleLineBreak = titleLineBreak
  }
}

/// What is in the input field, and its generation, raised on every change.
public struct Query: Sendable, Equatable {
  public var text: String
  public var generation: Int

  public init(text: String, generation: Int) {
    self.text = text
    self.generation = generation
  }
}

/// A source's answer for one query.
public struct RowsAnswer: Sendable, Equatable {
  /// In the source's order. The stage ranks them unless the level says the source's order is final.
  public var rows: [Row]
  /// The text the rows are ranked by, a presentation's searchText, nil for the whole query.
  public var rankText: String?
  /// What the list says in place of its rows, nil to show them.
  public var status: String?
  /// What the list says when ranking leaves no row.
  public var emptyStatus: String?

  public init(rows: [Row], rankText: String? = nil, status: String? = nil, emptyStatus: String? = nil) {
    self.rows = rows
    self.rankText = rankText
    self.status = status
    self.emptyStatus = emptyStatus
  }
}

/// The row a person acted on, named by its key, with the query it was chosen under, so a source
/// answers about that row and never about one it remembers.
public struct Pick: Sendable, Equatable {
  public var key: String
  public var query: String

  public init(key: String, query: String) {
    self.key = key
    self.query = query
  }
}

/// What a source asks the stage to do, in order. The stage applies a hide before anything else in
/// an answer, so work that opens another app never lands in Olm.app's own window.
public enum Effect: Sendable, Equatable {
  case hide
  /// Opens the file with its own application.
  case openFile(String)
  /// Shows the file selected in Finder.
  case revealFile(String)
}

/// An action a row offers beyond Return, an actions pane verb. chord names its keys in
/// lib/kbd.lua's names, ["cmd", "return"].
public struct Action: Sendable, Equatable {
  public var id: String
  public var title: String
  public var chord: [String]

  public init(id: String, title: String, chord: [String] = []) {
    self.id = id
    self.title = title
    self.chord = chord
  }
}

/// What a plugin is, read without running it, the Lua manifest's fields where they mean the same.
public struct Manifest: Sendable, Equatable {
  /// The identity a URL and the registry name it by, olm://<name>.
  public var name: String
  public var title: String
  public var actions: [Action]

  public init(name: String, title: String, actions: [Action] = []) {
    self.name = name
    self.title = title
    self.actions = actions
  }
}

/// Where a plugin may read and keep things, docs/DESIGN-APP.md, handed in by the composition root.
public struct PluginContext: Sendable {
  /// `~/.olm/run`, what Hammerspoon hands the app, never edited by it.
  public var run: URL
  /// `~/.olm/cache`, what can be rebuilt.
  public var cache: URL
  /// The app's bundled resources, the helpers built beside it.
  public var resources: URL

  public init(run: URL, cache: URL, resources: URL) {
    self.run = run
    self.cache = cache
    self.resources = resources
  }
}

/// Every list the app shows is answered through this, a native plugin, the bridge or an extension
/// host, so the stage cannot tell them apart and a plugin's flip is which one is registered under
/// its name. Each method may be cancelled when the person moves on, by Swift's task cancellation,
/// and a source that checks for it stops early.
public protocol ListSource: Actor {
  nonisolated var manifest: Manifest { get }
  /// Opens the list, with the query it opens with.
  func open(query: String) async -> Level
  /// The rows for what is in the input field.
  func rows(_ query: Query) async throws -> RowsAnswer
  /// Return on a row.
  func choose(_ pick: Pick) async -> [Effect]
  /// An action of the manifest on a row.
  func run(_ action: String, on pick: Pick) async -> [Effect]
  /// The list was closed.
  func close() async
}
