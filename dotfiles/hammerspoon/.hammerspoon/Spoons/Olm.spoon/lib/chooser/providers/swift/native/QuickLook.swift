// The Quick Look pane, a core surface, step 1.4c, docs/DESIGN-APP-QUICK-LOOK.md. One Olm glass
// pane over the list, its top line a close button, the file's name and a button naming the
// application that opens the file with the list's Return key cap, and the file's content below in
// an inset of its own, all in the list's own style, asked by Milos on 2026-11-10. Built into both
// Hammerspoon's library and Olm.app, and owned by the panel, Panel.swift, which hands it its style
// and keeps its rules, Escape closing it first, the list closing it and a press on it not counting
// as a press outside the list.
//
// THE MEASURES. The glass is the list's own, at the list's corner radius. The top line is as tall
// as an actions pane holding one action, a bar item's height with the pane's padding above and
// below, asked by Milos in the trial on 2026-11-10, a row's height having read as too large, and
// its words are the row title's font and colours. The content's inset stands the kit's outer
// padding in from the glass on every side, and its corner is the glass's less that padding, the
// rule every chip inside a panel follows. The close button is the system's xmark.circle.fill symbol
// at the size of every other icon on a bar item's line, placement.infoIcon, in the dimmed text
// colour, asked by Milos in the trial on 2026-11-10 over a drawn disc that read too large, and
// stands at the padding, where a row's icon starts. Its size and place are viewers/quicklook.swift's, centred on the list's screen at
// most 1100 by 820 points and 70 by 80 percent of the screen.
//
// THE KEY. Its window never becomes key. The list keeps the caret and stays key, and a list that
// resigns key closes, so the pane is refused key and every control in it answers the first press.
//
// It comes and goes as every Olm surface does, WindowMotion and the motion in config/settings.lua.

import Cocoa
import Quartz

final class QuickLookPane: NSObject {
  // The longest edges and the shares of the screen, viewers/quicklook.swift's.
  private static let maxSize = NSSize(width: 1100, height: 820)
  private static let screenShare = NSSize(width: 0.7, height: 0.8)

  private let window: KeylessWindow
  private let body = FlippedView()
  private lazy var glass = Surface(holding: body)
  private let disc = CloseButton()
  private let name = NSTextField(labelWithString: "")
  private let open = PressView()
  private let openLabel = NSTextField(labelWithString: "")
  private var openCap: KeyCap?
  private let inset = NSView()
  private var preview: QLPreviewView?
  private lazy var motion = WindowMotion(window)
  private var style = Style()
  private var placement = Placement()

  /// The path the pane shows, nil while it is down or going down.
  private(set) var path: String?
  /// Told when a press on the close button closed the pane.
  var onClosed: (() -> Void)?
  /// Told when the open button was pressed, which the list answers as its Return.
  var onOpen: (() -> Void)?

  var isOpen: Bool { path != nil }

  override init() {
    window = KeylessWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
    super.init()
    // Titled for its rounded outline and shadow, as the list's own window is, Panel.swift's THE
    // OUTLINE, its title bar see through and empty.
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(button)?.isHidden = true
    }
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.becomesKeyOnlyIfNeeded = true
    window.animationBehavior = .none
    window.isMovableByWindowBackground = true
    // One above the list's pop up menu level, so it covers the list and everything it draws.
    window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    window.contentView = glass.view

    name.lineBreakMode = .byTruncatingMiddle
    openLabel.lineBreakMode = .byTruncatingTail
    inset.wantsLayer = true
    inset.layer?.masksToBounds = true
    open.addSubview(openLabel)
    for view in [disc, name, open, inset] as [NSView] { body.addSubview(view) }
    disc.onClick = { [weak self] in
      self?.close()
      self?.onClosed?()
    }
    open.onPress = { [weak self] in self?.onOpen?() }
  }

  /// The list's style and measures, which the pane draws in. A pane that is up is laid out again.
  func apply(style next: Style, placement nextPlacement: Placement) {
    style = next
    placement = nextPlacement
    glass.setCornerRadius(style.radius)
    name.font = style.titleFont
    name.textColor = style.text
    openLabel.font = style.titleFont
    openLabel.textColor = style.text
    disc.contentTintColor = style.textDim
    disc.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
      .withSymbolConfiguration(.init(pointSize: placement.infoIcon, weight: .regular))
    open.color = style.highlight
    open.radius = max(0, style.highlightRadius - placement.barPillPad)
    if isOpen { layout() }
  }

  /// Shows path on screen, the pane opening when it was down and taking the new file in place when
  /// it was up, as the pane following the highlight does. A path with nothing at it is said once
  /// and changes nothing.
  func show(_ path: String, on screen: NSScreen?) {
    guard path != self.path else { return }
    guard FileManager.default.fileExists(atPath: path) else {
      NSLog("Olm: Quick Look has nothing at %@", path)
      return
    }
    let url = URL(fileURLWithPath: path)
    let fresh = !isOpen
    self.path = path
    name.stringValue = url.lastPathComponent
    openLabel.stringValue = Self.openWords(url)
    if preview == nil, let view = QLPreviewView(frame: .zero, style: .normal) {
      // Video and audio play at once, as Finder's panel does.
      view.autostarts = true
      inset.addSubview(view)
      preview = view
    }
    preview?.previewItem = url as NSURL
    if fresh {
      let area = (screen ?? Self.pointerScreen()).visibleFrame
      let width = min(Self.maxSize.width, area.width * Self.screenShare.width)
      let height = min(Self.maxSize.height, area.height * Self.screenShare.height)
      window.setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height),
        display: false)
    }
    layout()
    // surface-exempt, a Quick Look view needs a window of its own and the chooser has none that can host it
    if fresh { motion.show { window.orderFrontRegardless() } }
  }

  /// Takes the pane down, faded unless animated is false, and nothing when it is down.
  func close(animated: Bool = true) {
    guard isOpen else { return }
    path = nil
    // A video stops with its pane rather than playing on unseen.
    preview?.previewItem = nil
    motion.hide(animated: animated)
  }

  /// Whether a point in AppKit's screen space is on the pane while it is up.
  func contains(_ point: NSPoint) -> Bool {
    isOpen && window.frame.contains(point)
  }

  private func layout() {
    let size = window.frame.size
    body.frame = NSRect(origin: .zero, size: size)
    let pad = placement.pad
    // The actions pane's own measures for one line, Panel.swift's actionsPop.show.
    let lineH = placement.barPillH
    let lineTop = placement.barPillPad
    let side = placement.infoIcon
    disc.frame = NSRect(x: pad, y: lineTop + (lineH - side) / 2, width: side, height: side)

    openCap?.removeFromSuperview()
    let cap = KeyCap(style.returnKey, ink: style.ink(lit: false), style: style, placement: placement,
      holderH: placement.barPillH, holderRadius: open.radius, radius: max(0, style.radius - pad))
    open.addSubview(cap)
    openCap = cap
    let capSize = cap.fittingSize
    let labelW = ceil(openLabel.fittingSize.width)
    let item = placement.barPillPad
    let gap = placement.barGap
    let roomForOpen = max(0, size.width / 2 - pad)
    let openW = min(roomForOpen, labelW + (capSize.width > 0 ? gap + capSize.width : 0) + 2 * item)
    let openH = max(placement.barPillH, capSize.height)
    // The key cap's right edge on the inset's, as the close button's left edge is on it, so the
    // button's own padding reaches past the inset's edge, asked by Milos in the trial on 2026-11-10.
    open.frame = NSRect(x: size.width - pad + item - openW, y: lineTop + (lineH - openH) / 2, width: openW, height: openH)
    let labelH = ceil(openLabel.fittingSize.height)
    let shownLabelW = max(0, openW - 2 * item - (capSize.width > 0 ? gap + capSize.width : 0))
    openLabel.frame = NSRect(x: item, y: (openH - labelH) / 2, width: shownLabelW, height: labelH)
    cap.frame = NSRect(x: openW - item - capSize.width, y: (openH - capSize.height) / 2,
      width: capSize.width, height: capSize.height)

    let nameX = disc.frame.maxX + placement.iconGap
    let nameH = ceil(name.fittingSize.height)
    name.frame = NSRect(x: nameX, y: lineTop + (lineH - nameH) / 2,
      width: max(0, open.frame.minX - placement.iconGap - nameX), height: nameH)

    let top = lineTop + lineH + lineTop
    inset.frame = NSRect(x: pad, y: top, width: max(0, size.width - 2 * pad), height: max(0, size.height - top - pad))
    inset.layer?.cornerRadius = max(0, style.radius - pad)
    preview?.frame = inset.bounds
    preview?.autoresizingMask = [.width, .height]
  }

  // Open in and the name of the application macOS opens the file with, or Open with none.
  private static func openWords(_ url: URL) -> String {
    guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return "Open" }
    let shown = FileManager.default.displayName(atPath: app.path)
    return "Open in " + (shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown)
  }

  private static func pointerScreen() -> NSScreen {
    let pointer = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
  }
}

// A window that never takes key, so the list behind keeps it, see THE KEY above.
private final class KeylessWindow: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// The open button, a bar item's shape, lit while the pointer is on it, answering the first press.
private final class PressView: FlippedView {
  var onPress: (() -> Void)?
  var color = NSColor.clear { didSet { needsDisplay = true } }
  var radius: CGFloat = 0 { didSet { needsDisplay = true } }
  private var hovering = false { didSet { needsDisplay = true } }
  private var area: NSTrackingArea?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let area { removeTrackingArea(area) }
    let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
    addTrackingArea(next)
    area = next
  }
  override func mouseEntered(with event: NSEvent) { hovering = true }
  override func mouseExited(with event: NSEvent) { hovering = false }

  override func draw(_ dirtyRect: NSRect) {
    guard hovering else { return }
    color.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
  }
}

// The close button, a symbol image that answers the first press, the pane never being key.
private final class CloseButton: NSImageView {
  var onClick: (() -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    imageScaling = .scaleProportionallyUpOrDown
  }

  required init?(coder: NSCoder) { nil }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
  }
}
