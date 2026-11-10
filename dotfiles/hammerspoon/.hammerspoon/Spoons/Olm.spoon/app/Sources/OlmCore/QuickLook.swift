// The Quick Look panel over the app's list, step 1.4c, docs/DESIGN-APP-QUICK-LOOK.md. It is the
// panel plugins/filesearch/viewers/quicklook.swift opens for the Lua list, moved into the app's own
// process, so no helper is compiled and no process starts per file, and the two lists look the
// same until the flip retires the helper. The same QLPreviewView, the same header with the file's
// name and a grey close disc, the same size, level and nonactivating style. That file's comments
// carry why each was chosen, measured there.
//
// The stage owns it, as it owns the info pane and the actions pane, since a source puts no window
// on screen. It answers the source's quickLook effect, and keeps the list's rules, Escape closing
// the panel first and the list closing it with itself.
//
// The panel never becomes key. In this process a panel taking key would take it from the list,
// which closes when it resigns key, so the list keeps the caret and the panel is refused key.

import AppKit
import Quartz

@MainActor
final class QuickLook: NSObject, NSWindowDelegate {
  private var panel: NSPanel?
  /// The path the panel shows, nil while it is down.
  private(set) var path: String?

  var isOpen: Bool { panel != nil }

  /// Shows path, replacing what is up, centred on screen, or the pointer's screen with none.
  func show(_ path: String, on screen: NSScreen?) {
    close()
    guard FileManager.default.fileExists(atPath: path) else {
      NSLog("Olm: Quick Look has nothing at %@", path)
      return
    }
    let url = URL(fileURLWithPath: path)
    let screen = screen ?? Self.pointerScreen()
    let area = screen.visibleFrame
    let width = min(1100, area.width * 0.7)
    let height = min(820, area.height * 0.8)
    let rect = NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)

    guard let view = QLPreviewView(frame: .zero, style: .normal) else {
      NSLog("Olm: Quick Look could not build a preview view")
      return
    }
    // Video and audio play at once, as Finder's panel does.
    view.autostarts = true
    view.previewItem = url as NSURL

    // surface-exempt, a Quick Look view needs a window of its own and the chooser has none that can host it
    let panel = KeylessPanel(contentRect: rect,
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.title = url.lastPathComponent
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      panel.standardWindowButton(button)?.isHidden = true
    }
    panel.isMovableByWindowBackground = true
    panel.becomesKeyOnlyIfNeeded = true
    // One above the pop up menu level the list stands at, so it covers the list and all it draws.
    panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self
    panel.contentView = Self.content(preview: view, title: url.lastPathComponent, size: rect.size) {
      [weak self] in self?.close()
    }
    self.panel = panel
    self.path = path
    // surface-exempt, the Quick Look window above, shown once it is built
    panel.orderFrontRegardless()
  }

  /// Takes the panel down, nothing when it is down.
  func close() {
    guard let panel else { return }
    self.panel = nil
    path = nil
    panel.delegate = nil
    // A video stops with its panel rather than playing on unseen.
    if let view = Self.preview(in: panel.contentView) { view.close() }
    panel.orderOut(nil)
  }

  /// Whether a point, in AppKit's screen space, is on the panel.
  func contains(_ point: NSPoint) -> Bool {
    guard let panel else { return false }
    return panel.frame.contains(point)
  }

  // The panel closed some way other than close, a press on its disc goes through close.
  func windowWillClose(_ notification: Notification) {
    guard (notification.object as? NSPanel) === panel else { return }
    panel = nil
    path = nil
  }

  private static func pointerScreen() -> NSScreen {
    let pointer = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private static func preview(in view: NSView?) -> QLPreviewView? {
    guard let view else { return nil }
    if let preview = view as? QLPreviewView { return preview }
    for child in view.subviews { if let found = preview(in: child) { return found } }
    return nil
  }

  // The helper's header, the one inset its disc's three margins are built from.
  private static let inset: CGFloat = 8
  private static let discSize: CGFloat = 15
  private static var barHeight: CGFloat { discSize + inset * 2 }

  private static func content(preview: QLPreviewView, title: String, size: NSSize,
    close: @escaping () -> Void) -> NSView {
    let bar = barHeight
    let container = NSView(frame: NSRect(origin: .zero, size: size))

    preview.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - bar)
    preview.autoresizingMask = [.width, .height]
    container.addSubview(preview)

    let header = NSVisualEffectView(frame: NSRect(x: 0, y: size.height - bar, width: size.width, height: bar))
    header.material = .titlebar
    header.blendingMode = .withinWindow
    header.state = .active
    header.autoresizingMask = [.width, .minYMargin]
    container.addSubview(header)

    let divider = NSView(frame: NSRect(x: 0, y: 0, width: size.width, height: 1))
    divider.wantsLayer = true
    divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
    divider.autoresizingMask = [.width, .maxYMargin]
    header.addSubview(divider)

    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    label.lineBreakMode = .byTruncatingMiddle
    label.sizeToFit()
    let labelWidth = min(label.frame.width, size.width - (inset * 2 + discSize) * 2)
    label.frame = NSRect(x: (size.width - labelWidth) / 2, y: (bar - label.frame.height) / 2,
      width: labelWidth, height: label.frame.height)
    label.autoresizingMask = [.minXMargin, .maxXMargin]
    header.addSubview(label)

    let disc = CloseDisc(frame: NSRect(x: inset, y: inset, width: discSize, height: discSize))
    disc.autoresizingMask = [.maxXMargin]
    disc.onClick = close
    header.addSubview(disc)
    return container
  }
}

// A panel that never takes key, so the list behind keeps it, see the header.
private final class KeylessPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

// The helper's grey close disc, Finder's rather than the red traffic light, its cross knocked out
// of the disc so the title bar's material shows through. It answers the first press, the panel
// never being key.
private final class CloseDisc: NSView {
  var onClick: (() -> Void)?
  private var pressed = false

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    pressed = true
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    let inside = bounds.contains(convert(event.locationInWindow, from: nil))
    pressed = false
    needsDisplay = true
    if inside { onClick?() }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    NSColor.secondaryLabelColor.withAlphaComponent(pressed ? 0.85 : 0.55).setFill()
    NSBezierPath(ovalIn: bounds).fill()
    let arm = bounds.width * 0.32
    let centre = NSPoint(x: bounds.midX, y: bounds.midY)
    let cross = NSBezierPath()
    cross.lineWidth = max(1.5, bounds.width * 0.11)
    cross.lineCapStyle = .round
    cross.move(to: NSPoint(x: centre.x - arm / 2, y: centre.y - arm / 2))
    cross.line(to: NSPoint(x: centre.x + arm / 2, y: centre.y + arm / 2))
    cross.move(to: NSPoint(x: centre.x - arm / 2, y: centre.y + arm / 2))
    cross.line(to: NSPoint(x: centre.x + arm / 2, y: centre.y - arm / 2))
    context.setBlendMode(.destinationOut)
    NSColor.black.setStroke()
    cross.stroke()
    context.setBlendMode(.normal)
    context.endTransparencyLayer()
  }
}
