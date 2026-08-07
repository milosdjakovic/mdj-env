// The native Quick Look panel for one file, held open until this process is told to go.
//
// Hammerspoon has no binding for Quick Look and the command line tool is a dead end, since
// `qlmanage -p` starts, registers as running, spawns the system preview extension and then owns
// no window at all. So the panel is built here, out of the same AppKit view Finder uses, which
// is the only way to get a real one. The FileSearch quicklook viewer compiles this once, caches
// the binary, and runs it per preview.
//
// TWO CHOICES HERE ARE ABOUT THE PICKER RATHER THAN ABOUT QUICK LOOK, and both matter more than
// they look. The panel is nonactivating and is ordered front without being made key, because the
// thing it covers is a Hammerspoon chooser that hides the moment it stops being key. Activating
// normally would dismiss the very list the preview is meant to describe. And the window sits at
// the pop up menu level, which is where every canvas panel in this config already sits for the
// same reason, so it lands above the chooser rather than behind it.
//
// Closing it by hand ends the process, and the viewer terminates the process to close it, so
// the panel and this program have exactly one lifetime between them.

import AppKit
import Quartz

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("quicklook needs a file path\n".utf8))
    exit(1)
}
let target = URL(fileURLWithPath: arguments[1])

let app = NSApplication.shared
// Accessory so no Dock icon and no menu bar appear while the panel is up.
app.setActivationPolicy(.accessory)

// The grey close disc, Finder's rather than the red traffic light, drawn rather than assembled
// out of a button and a symbol image.
//
// IT IS DRAWN BECAUSE THE MARGINS HAVE TO BE EXACT. A symbol image inside a button is centred at
// whatever intrinsic size the symbol happens to have for a given point size, so the disc ends up
// a little smaller than the box holding it and the gap it leaves is not the gap that was asked
// for. Filling the view's own bounds means the distance from the left edge, from the top edge and
// from the content below is one number, set once, and true by construction.
//
// It answers the first click explicitly, which every control in this panel has to do, since the
// panel never becomes key and an ordinary control spends the first click on becoming key instead
// of on acting.
final class CloseDisc: NSView {
    var onClick: (() -> Void)?
    private var pressed = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

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
        // The cross is knocked out of the disc rather than painted on top of it, so the titlebar
        // material shows through the way it does in the system's own button. Painting it would
        // mean naming a colour that has to match a translucent background, which it cannot.
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

final class Preview: NSObject, NSWindowDelegate {
    let panel: NSPanel

    // The screen the caller's frame sits on, or the pointer's screen when no frame arrived.
    //
    // The viewer forwards the picker's own absolute frame as four more strings after the path,
    // x, y, w, h, so this reads them back and finds the NSScreen whose area contains the
    // center of that rect. That is the screen the picker actually opened on, which the pointer
    // is not reliably resting over, so the earlier version of this function picked the wrong
    // screen on any setup where the pointer had drifted off to another display. Falling back to
    // the pointer covers two cases rather than one, the four arguments missing entirely, and
    // the four arguments parsing fine yet matching no screen, which happens when the stored
    // frame names a display that has since been disconnected. Either way this keeps the helper
    // working rather than picking nothing at all.
    //
    // THE TWO COORDINATE SYSTEMS DISAGREE AND THAT IS NOT OPTIONAL TO HANDLE. Hammerspoon
    // reports its frame in Quartz display coordinates, the top left of the primary screen at
    // zero with y growing downward. NSScreen reports its own frame in Cocoa coordinates, the
    // bottom left of the primary screen at zero with y growing upward. So the y side of the
    // center point is flipped against the primary screen height before it is compared against
    // any screen's frame, or a rect near the top of one system reads as a rect near the bottom
    // of the other and lands on the wrong display whenever more than one screen differs in
    // height or sits above rather than beside the primary one.
    private static func screenFor(arguments: [String]) -> NSScreen {
        if arguments.count >= 6,
           let x = Double(arguments[2]), let y = Double(arguments[3]),
           let w = Double(arguments[4]), let h = Double(arguments[5]) {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let center = NSPoint(x: x + w / 2, y: primaryHeight - (y + h / 2))
            if let match = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) {
                return match
            }
        }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    init?(url: URL) {
        let screen = Preview.screenFor(arguments: CommandLine.arguments)
        let area = screen.visibleFrame
        let width = min(1100, area.width * 0.7)
        let height = min(820, area.height * 0.8)
        let rect = NSRect(x: area.midX - width / 2,
                          y: area.midY - height / 2,
                          width: width,
                          height: height)

        guard let view = QLPreviewView(frame: .zero, style: .normal) else { return nil }
        // Video and audio behave like Finder's panel rather than waiting to be clicked.
        view.autostarts = true
        view.previewItem = url as NSURL

        panel = NSPanel(contentRect: rect,
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView,
                                    .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.title = url.lastPathComponent
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        // THE HEADER IS DRAWN HERE RATHER THAN BEING THE SYSTEM TITLEBAR, which is the third
        // attempt and the first one that can be made to look right. Finder's panel is a filename
        // and one grey close disc, and neither of those is something the system bar will give.
        // Restyling the close traffic light is impossible, since it is drawn by a private cell
        // that ignores an image set on it. Hiding it and adding a leading titlebar accessory puts
        // the replacement a third of the way across the bar, because a hidden traffic light still
        // reserves its slot. Borrowing the hidden button's own frame and adding a sibling gets the
        // position right and moves the title to the left edge, since laying out an unexpected
        // child is enough to make the bar treat itself as having an accessory. So the system bar
        // is made transparent and empty, and the strip is ours, where the disc's inset from the
        // left is the same number as its inset from the top and from the content below it.
        //
        // The strip sits ABOVE the preview rather than floating on it. Floating is what the real
        // panel does and it was the second attempt, but it puts the first inch of the document
        // under the title, so the filename reads against whatever that document happens to be and
        // the top of the content has to be scrolled back into view.
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        // A bar with nothing of the system's left in it is not a drag handle, so the whole window
        // is one.
        panel.isMovableByWindowBackground = true
        // Only take key focus if something inside actually needs typing, which for a preview is
        // never. This is the second half of leaving the chooser alone.
        panel.becomesKeyOnlyIfNeeded = true
        // One step above the pop up menu level, which is where every canvas panel in this config
        // sits. Matching it is not enough, since the picker's docked shortcut hints are a canvas
        // at that level and drew straight over the preview. A window covering the list should
        // cover what the list draws around itself too.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init()
        panel.delegate = self
        panel.contentView = buildContent(preview: view, title: url.lastPathComponent,
                                         size: rect.size)
    }

    // The one number the header is built from. Everything else follows, so the disc's distance
    // from the left edge, from the top edge and from the content below it are the same by
    // construction rather than by three values that have to be kept agreeing.
    private static let inset: CGFloat = 8
    private static let discSize: CGFloat = 15
    private static var barHeight: CGFloat { discSize + inset * 2 }

    private func buildContent(preview: QLPreviewView, title: String, size: NSSize) -> NSView {
        let bar = Preview.barHeight
        let container = NSView(frame: NSRect(origin: .zero, size: size))

        preview.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - bar)
        preview.autoresizingMask = [.width, .height]
        container.addSubview(preview)

        // The system's own titlebar material, so the strip reads as a window bar rather than as a
        // block of flat colour, and follows light and dark for free.
        let header = NSVisualEffectView(frame: NSRect(x: 0, y: size.height - bar,
                                                      width: size.width, height: bar))
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
        // Kept off the disc at any width, and centred on the bar rather than on the space left
        // over beside the button, which is what keeps it centred on the window.
        let labelWidth = min(label.frame.width, size.width - (Preview.inset * 2 + Preview.discSize) * 2)
        label.frame = NSRect(x: (size.width - labelWidth) / 2,
                             y: (bar - label.frame.height) / 2,
                             width: labelWidth,
                             height: label.frame.height)
        label.autoresizingMask = [.minXMargin, .maxXMargin]
        header.addSubview(label)

        let close = CloseDisc(frame: NSRect(x: Preview.inset, y: Preview.inset,
                                            width: Preview.discSize, height: Preview.discSize))
        close.autoresizingMask = [.maxXMargin]
        close.onClick = { [weak self] in self?.closePanel() }
        header.addSubview(close)

        return container
    }

    @objc private func closePanel() {
        panel.close()
    }

    func present() {
        panel.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        exit(0)
    }
}

guard let preview = Preview(url: target) else {
    FileHandle.standardError.write(Data("quicklook could not build a preview view\n".utf8))
    exit(1)
}
preview.present()
app.run()
