// What the chooser panel tells the side that drives it, and the values that travel with it. This is
// the seam step 0.6 of docs/PLAN-STANDALONE.md names. The panel knows only this protocol, so the
// same panel is driven by Lua through Entry.swift inside Hammerspoon and, compiled as the Swift
// package beside this directory, by anything else that answers it, Olm.app's own engine or a test.
//
// The events and their arguments are the ones the Lua view reads today,
// providers/swift/view.lua, so a new event is added there and here together. ask answers whether
// the driver claimed what it was told, which only yields and listKey read, to decide whether the
// field edits a key. It is called on the main thread, and a driver that answers slowly holds the
// panel for that long, which is why Olm.app's engine answers from its own state and never waits.

import Foundation

// One argument of an event the panel sends.
enum PanelValue {
  case string(String)
  case bytes(Data)
  case int(Int)
  case number(Double)
  case bool(Bool)
  case none
}

// The side that drives a panel.
protocol ChooserSource: AnyObject {
  func ask(_ event: String, _ args: [PanelValue]) -> Bool
}
