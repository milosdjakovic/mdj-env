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
  /// An SF Symbol by name, drawn in one colour that follows the row, lit or not, as Olm's sf icon
  /// source draws one. A symbol's meaning is Olm's, so `hand.raised` is a permission macOS holds.
  case symbol(String)
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
  /// How long the highlight rests on a row before its preview is asked for, in milliseconds, the
  /// file search config's preview.settleMs. Read only where the manifest has a preview pane.
  public var previewSettleMs: Int

  public init(placeholder: String = "", ranking: Ranking = .app, rowLimit: Int? = nil, titleLineBreak: String? = nil,
              previewSettleMs: Int = 60) {
    self.placeholder = placeholder
    self.ranking = ranking
    self.rowLimit = rowLimit
    self.titleLineBreak = titleLineBreak
    self.previewSettleMs = previewSettleMs
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
  /// Opens a URL, a pane of System Settings among them.
  case openURL(String)
  /// Opens the same list again from an empty input field, after the source changed what it lists,
  /// as file search does once its folder permissions are answered.
  case reopen
  /// Puts the text on the clipboard, a plain write anything watching the clipboard sees.
  case copyText(String)
  /// Shows the file in the Quick Look panel over the list, which stays up, or closes the panel
  /// when it already shows that file, docs/DESIGN-APP-QUICK-LOOK.md.
  case quickLook(String)
}

/// One of the eight colour roles lib/ui/style.lua resolves for the half the system is on. A plugin
/// names a role and never a colour, so this is the only colour a preview can carry.
public enum ColorRole: String, Sendable, Equatable {
  case foreground, subtext, background, border, highlight, primary, secondary, tertiary
}

/// What the preview pane beside a list says about one row, as a plugin describes it and never as it
/// is drawn. The core lays it out with the swift chooser's own type roles and spaces, the port of
/// plugins/filesearch/viewers/sidepanel-nodes.lua, so a plugin holds no font, size or colour.
public struct Preview: Sendable, Equatable {
  /// One fact under the name, a label at the left and its value flush right.
  public struct Fact: Sendable, Equatable {
    public var label: String
    public var value: String
    /// The value's colour, the foreground when nil.
    public var color: ColorRole?

    public init(label: String, value: String, color: ColorRole? = nil) {
      self.label = label
      self.value = value
      self.color = color
    }
  }

  /// What is drawn under the facts, a section heading with what it heads, sidepanel.lua's body as
  /// a describer answers it.
  public struct Body: Sendable, Equatable {
    /// The section's heading, HEAD, FOLDER or PREVIEW.
    public var label: String
    /// What the heading says at its right, nil for none.
    public var facts: String?
    /// The lines of a file's head or a folder's names, as they are, tabs and all.
    public var lines: [String]
    /// Whether each line wraps at the pane's width rather than being cut.
    public var wrap: Bool
    /// How many drawn lines are kept once more than budget and slack are there, nil for no limit.
    public var budget: Int?
    /// How far past the budget a body is still shown whole.
    public var slack: Int
    /// The file's whole size in bytes, which the note of what is left out counts against.
    public var total: Int?
    /// Whether a count of lines left out would mean anything.
    public var hasLines: Bool
    /// A picture under the heading in place of lines, nil for none.
    public var picture: Picture?

    public init(label: String, facts: String? = nil, lines: [String] = [], wrap: Bool = false,
                budget: Int? = nil, slack: Int = 0, total: Int? = nil, hasLines: Bool = false,
                picture: Picture? = nil) {
      self.label = label
      self.facts = facts
      self.lines = lines
      self.wrap = wrap
      self.budget = budget
      self.slack = slack
      self.total = total
      self.hasLines = hasLines
      self.picture = picture
    }
  }

  /// A picture a body shows, kit.image, as a file the core reads, decodes and scales off the main
  /// thread, so a plugin hands a path and never holds an image. It is drawn at the width of its
  /// slot, keeping its aspect, at the top left, its corners the nested radius.
  public struct Picture: Sendable, Equatable {
    /// A picture file the system can read, a raster or a rendered thumbnail.
    public var path: String
    /// Whether it may be drawn wider than its own size, kit.image's upscale.
    public var upscale: Bool

    public init(path: String, upscale: Bool = true) {
      self.path = path
      self.upscale = upscale
    }
  }

  /// The row's name, in the title role.
  public var name: String
  /// Where it lives, said as a person reads it, empty for nowhere worth saying.
  public var dir: String
  public var facts: [Fact]
  public var body: Body?
  /// Whether something this preview says is still on its way, a picture being rendered, which the
  /// stage asks for with previewLanded once this one is drawn.
  public var pending: Bool

  public init(name: String, dir: String = "", facts: [Fact] = [], body: Body? = nil, pending: Bool = false) {
    self.name = name
    self.dir = dir
    self.facts = facts
    self.body = body
    self.pending = pending
  }
}

/// A list's preview pane, as its manifest declares one.
public struct PreviewPane: Sendable, Equatable {
  /// What the pane says while the highlight has nothing to describe.
  public var emptyText: String

  public init(emptyText: String) {
    self.emptyText = emptyText
  }
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
  /// The pane beside the list, nil for a list with none, the Lua manifest's previewPane.
  public var previewPane: PreviewPane?

  public init(name: String, title: String, actions: [Action] = [], previewPane: PreviewPane? = nil) {
    self.name = name
    self.title = title
    self.actions = actions
    self.previewPane = previewPane
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
  /// `~/.olm/state/<plugin>`, what the plugin keeps, a directory of its own nothing else writes,
  /// docs/DESIGN-APP.md's store.
  public var store: URL

  /// store defaults to the state folder beside run, for a check that keeps nothing.
  public init(run: URL, cache: URL, resources: URL, store: URL? = nil) {
    self.run = run
    self.cache = cache
    self.resources = resources
    self.store = store ?? run.deletingLastPathComponent().appendingPathComponent("state")
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
  /// What the preview pane says about a row, nil for nothing to say, asked only where the manifest
  /// has a preview pane. A source reads what it needs off its own actor's thread, so the rows it
  /// answers never wait on a preview.
  func preview(_ pick: Pick) async -> Preview?
  /// The same row's preview again once what its last preview said was pending has landed, asked
  /// only after a preview with pending set and cancelled when the highlight moves on, nil when
  /// nothing more is coming. The stage draws it where the pane is scrolled, as the Lua pane's
  /// repaint does.
  func previewLanded(_ pick: Pick) async -> Preview?
  /// Whether the actions pane lists a row whose applies gate is this name over the row it opened
  /// on, the Lua surface's colon method of the same name, docs/PLAN-ACTION-PANEL.md. A gate the
  /// source does not know answers true, as the Lua pane shows a verb its surface cannot answer.
  func applies(_ gate: String, on pick: Pick) async -> Bool
  /// The list was closed.
  func close() async
}

extension ListSource {
  /// A source with no preview pane says nothing.
  public func preview(_ pick: Pick) async -> Preview? { nil }
  /// A source whose previews are never pending has nothing more to say.
  public func previewLanded(_ pick: Pick) async -> Preview? { nil }
  /// A source with no gates lists every row.
  public func applies(_ gate: String, on pick: Pick) async -> Bool { true }
}
