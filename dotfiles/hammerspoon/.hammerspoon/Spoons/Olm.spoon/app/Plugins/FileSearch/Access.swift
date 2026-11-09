// File search's folder permissions, asked up front, step 1.4j of docs/PLAN-STANDALONE.md.
//
// macOS asks once per protected folder the first time an app touches a file there, so without
// this the prompts arrived one by one in the middle of a search as a preview reached a folder. File
// search searches the home folder, and Desktop, Documents and Downloads are the protected folders
// in it. On the first open of the person's list the source shows one row that asks, and choosing
// it touches each folder in turn, which is what raises each prompt, one at a time, off the main
// thread. What was answered is kept in the plugin's store, ~/.olm/state/filesearch, so it is asked
// once. A folder refused is said once on the next open, with a row that opens Files and Folders in
// System Settings, since macOS never asks a second time. A refused folder is tried again at each
// open, which raises no prompt, so one turned on in System Settings is seen.

import Foundation

public struct FolderAccess: Sendable {
  /// A protected folder file search reads, under the home folder.
  public struct Folder: Sendable, Equatable {
    public var name: String
    public var path: String
  }

  /// What the file says, written by this type alone.
  public struct State: Codable, Sendable, Equatable {
    /// Whether the person has been asked.
    public var asked = false
    /// The folders macOS refused, by name.
    public var refused: [String] = []
    /// Whether the refused folders have been said in the list.
    public var told = false

    public init(asked: Bool = false, refused: [String] = [], told: Bool = false) {
      self.asked = asked
      self.refused = refused
      self.told = told
    }
  }

  /// The macOS folders that raise a prompt, in the order they are asked.
  public static let protectedNames = ["Desktop", "Documents", "Downloads"]

  /// Files and Folders in System Settings, where a refused folder is turned on.
  public static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

  public let folders: [Folder]
  public let file: URL
  // Whether a folder can be read, macOS's answer, handed in by a check so no prompt is raised.
  private let readable: @Sendable (Folder) -> Bool

  /// home is the folder searched, store the plugin's own directory the answers are kept in.
  public init(home: URL, store: URL, readable: @escaping @Sendable (Folder) -> Bool = FolderAccess.readable) {
    folders = Self.protectedNames.map { Folder(name: $0, path: home.appendingPathComponent($0).path) }
    file = store.appendingPathComponent("folder-access.json")
    self.readable = readable
  }

  public func load() -> State {
    guard let bytes = try? Data(contentsOf: file), let state = try? JSONDecoder().decode(State.self, from: bytes)
    else { return State() }
    return state
  }

  public func save(_ state: State) {
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let bytes = try? JSONEncoder().encode(state) else { return }
    try? bytes.write(to: file, options: .atomic)
  }

  /// Whether the folder can be read now. For a folder never answered this raises macOS's prompt
  /// and waits for the person, so it is called off the main thread and only once asking.
  public static func readable(_ folder: Folder) -> Bool {
    var isDir: ObjCBool = false
    // A folder this Mac does not have is nothing to ask about.
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return true }
    return (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
  }

  /// Every folder asked in turn, one prompt at a time, the state written once all are answered.
  public func ask() async -> State {
    let folders = self.folders
    let readable = self.readable
    let refused = await withCheckedContinuation { (done: CheckedContinuation<[String], Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        done.resume(returning: folders.filter { !readable($0) }.map(\.name))
      }
    }
    let state = State(asked: true, refused: refused, told: false)
    save(state)
    return state
  }

  /// At an open, the refused folders tried again, which raises no prompt, so one turned on in
  /// System Settings since is dropped from the list.
  public func recheck(_ state: State) async -> State {
    let readable = self.readable
    guard state.asked, !state.refused.isEmpty else { return state }
    let still = folders.filter { state.refused.contains($0.name) }
    let refused = await withCheckedContinuation { (done: CheckedContinuation<[String], Never>) in
      DispatchQueue.global(qos: .userInitiated).async {
        done.resume(returning: still.filter { !readable($0) }.map(\.name))
      }
    }
    guard refused != state.refused else { return state }
    var next = state
    next.refused = refused
    save(next)
    return next
  }

  /// The names said as a person reads them, Desktop, Documents and Downloads.
  public static func spoken(_ names: [String]) -> String {
    switch names.count {
    case 0: return ""
    case 1: return names[0]
    default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
  }
}
