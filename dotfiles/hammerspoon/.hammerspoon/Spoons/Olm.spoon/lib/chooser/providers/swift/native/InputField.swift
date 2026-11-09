// The one input field every field in the chooser is made from, the list's input field at the top and
// the actions pane's own at its foot, asked by Milos on 2026-11-09, so the two type, select, scroll
// and draw their placeholder alike and differ only in the look they are handed. It is a clip holding
// a bare single line text field. The clip is the rect the field stands in, so text scrolled past
// either end is cut on its edges, and the text field reaches one line fragment padding past both
// ends, the padding the field editor keeps inside each, so the caret lands on the rect's left edge.
//
// It holds no key rule. The panel routes every key, Panel.swift's THE KEY ORDER, to whichever field
// has the caret, and is the text field's delegate for both.

import Cocoa

final class InputField: NSView {
  // What a field looks like, its font, its text's colour and its placeholder's words and colour.
  struct Look {
    var font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    var text = NSColor.labelColor
    var dim = NSColor.secondaryLabelColor
    var placeholder = ""
  }

  let field = NSTextField()
  private(set) var look = Look()

  override init(frame: NSRect) {
    super.init(frame: frame)
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.usesSingleLineMode = true
    field.allowsEditingTextAttributes = false
    wantsLayer = true
    layer?.masksToBounds = true
    addSubview(field)
  }

  required init?(coder: NSCoder) { nil }

  func apply(_ next: Look) {
    look = next
    field.font = next.font
    field.textColor = next.text
    field.placeholderAttributedString = NSAttributedString(string: next.placeholder,
      attributes: [.font: next.font, .foregroundColor: next.dim])
  }

  // The height one line of this field's font takes, which the field is laid out at.
  var lineHeight: CGFloat { ceil(look.font.ascender - look.font.descender + look.font.leading) + 2 }

  var editor: NSTextView? { field.currentEditor() as? NSTextView }

  var text: String { field.stringValue }

  // Replaces the text with the caret after it and nothing selected, through the field editor while
  // it is editing, since setting the value under an active editor would be overwritten.
  func setText(_ text: String) {
    if let editor = field.currentEditor() {
      editor.string = text
      editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    } else {
      field.stringValue = text
    }
  }

  // Stands the field in rect, centred on it at its own line height, in its superview's space.
  func place(_ rect: NSRect, in window: NSWindow) {
    let h = lineHeight
    let lead = (window.fieldEditor(true, for: field) as? NSTextView)?.textContainer?.lineFragmentPadding ?? 0
    frame = NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
    field.frame = NSRect(x: -lead, y: 0, width: rect.width + 2 * lead, height: h)
  }

  // Puts the caret in this field, the text all after it, its caret and selection in the colours
  // handed in.
  func focus(in window: NSWindow, caret: NSColor, selection: NSColor) {
    window.makeFirstResponder(field)
    if let editor {
      editor.insertionPointColor = caret
      editor.selectedTextAttributes = [.backgroundColor: selection, .foregroundColor: look.text]
      editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
    }
  }

  // Whether responder is this field or the editor it edits through, any field editor while it has
  // none yet, the one AppKit is about to hand it.
  func owns(_ responder: NSResponder?) -> Bool {
    if responder === field { return true }
    guard let editor = responder as? NSTextView, editor.isFieldEditor else { return false }
    return editor === field.currentEditor() || editor.delegate === field || field.currentEditor() == nil
  }
}
