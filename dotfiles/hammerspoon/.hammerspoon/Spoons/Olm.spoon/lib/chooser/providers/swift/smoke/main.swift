// A list from a fake source, with no window, step 0.6 of docs/PLAN-STANDALONE.md. It proves the
// panel builds and works with nothing of Lua in it, which is what Olm.app needs of it. It never shows
// the panel, so it is safe to run at any time, and it prints one line per check and exits nonzero
// on any failure.

import AppKit
@testable import OlmChooser

final class FakeSource: ChooserSource {
  var events: [(String, [PanelValue])] = []
  func ask(_ event: String, _ args: [PanelValue]) -> Bool {
    events.append((event, args))
    return false
  }
}

var failures = 0
func check(_ ok: Bool, _ what: String) {
  print((ok ? "ok   " : "FAIL ") + what)
  if !ok { failures += 1 }
}

_ = NSApplication.shared

let rows = ["Safari", "System Settings", "Terminal"].map { title -> Row in
  var row = Row()
  row.title = title
  return row
}

let list = ListView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
list.setRows(rows)
check(list.numberOfRows(in: list.table) == 3, "the list holds the three rows it was handed")

let source = FakeSource()
let panel = ChooserPanel(source: source)
panel.applyStyle(Style())
panel.setRows(rows)
var state = ViewState()
state.highlight = 1
state.placeholder = "Search"
panel.update(state)
check(NSApp.windows.allSatisfy { !$0.isVisible }, "the panel takes rows and a state without a window on screen")

panel.start()
panel.throughField { panel.setText("saf") }
let told = source.events.last
var text: String? = nil
if let told, told.0 == "text", case .string(let t)? = told.1.first { text = t }
check(text == "saf", "an edit of the input field is told to the source as text")
panel.stop()

print(failures == 0 ? "olm-chooser-smoke, every check passed" : "olm-chooser-smoke, \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
