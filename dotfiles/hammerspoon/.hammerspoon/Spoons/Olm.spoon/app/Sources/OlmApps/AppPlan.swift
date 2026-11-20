// What a press on an app does, decided from what the app's state is and changing nothing, step 6.2,
// docs/DESIGN-APP-APPS.md. A port of lib/appfocus.lua's decide, the one decision its focus or cycle,
// its toggle and the plan it hands the app's shadow all make, so the two compare rule for rule.

import Foundation

/// One window of an app as Accessibility answers it, its number the one hs.window:id() answers.
public struct AppWindow: Sendable, Equatable {
  public let id: UInt32
  public let standard: Bool
  public let minimized: Bool
  public init(id: UInt32, standard: Bool, minimized: Bool) {
    self.id = id
    self.standard = standard
    self.minimized = minimized
  }
}

/// An app as a press finds it. windows is every window AXWindows answers, focused the window number
/// of the focused application's focused window, whichever app that is.
public struct AppState: Sendable, Equatable {
  public let running: Bool
  public let frontmost: Bool
  public let windows: [AppWindow]
  public let focused: UInt32?
  public init(running: Bool, frontmost: Bool = false, windows: [AppWindow] = [], focused: UInt32? = nil) {
    self.running = running
    self.frontmost = frontmost
    self.windows = windows
    self.focused = focused
  }
}

/// What a press does, Lua's outcome words.
public enum AppOutcome: String, Sendable {
  case launched, focused, cycled, hidden
}

/// A press's decision, the window a cycle reaches by its number.
public struct AppPlan: Sendable, Equatable {
  public let outcome: AppOutcome
  public let window: UInt32?
  public init(_ outcome: AppOutcome, window: UInt32? = nil) {
    self.outcome = outcome
    self.window = window
  }

  /// hides true is the show and hide form, an app in front with any window hiding, otherwise focus
  /// or cycle, which walks the standard windows not minimized in window number order and wraps.
  public static func decide(_ state: AppState, hides: Bool) -> AppPlan {
    guard state.running else { return AppPlan(.launched) }
    if hides {
      return state.frontmost && !state.windows.isEmpty ? AppPlan(.hidden) : AppPlan(.focused)
    }
    let cyclable = state.windows.filter { $0.standard && !$0.minimized }.sorted { $0.id < $1.id }
    guard !cyclable.isEmpty, state.frontmost else { return AppPlan(.focused) }
    let index = state.focused.flatMap { f in cyclable.firstIndex { $0.id == f } }
    let next = index.map { ($0 + 1) % cyclable.count } ?? 0
    return AppPlan(.cycled, window: cyclable[next].id)
  }

  /// Whether placement fires on this outcome, the toggler's PLACING_OUTCOMES, a window brought
  /// forward rather than cycled to or sent away.
  public var places: Bool { outcome == .launched || outcome == .focused }
}
