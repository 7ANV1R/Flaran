import AppKit
import FlaranKit
import Observation
import SwiftUI

/// The three menu bar items: hot reload, hot restart (only while something runs) and the Flaran mark,
/// which drops down the panel the way Wi-Fi and Control Center do.
final class StatusBar: NSObject {
    private let model: AppModel
    // A status item lands left of the others when it becomes visible: mark first, then restart, then reload.
    private let main = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let restart = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let reload = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private lazy var panel = MenuPanel(model: model)

    private struct Snapshot: Equatable, Sendable {
        var errors = false
        var visible = false
        var enabled = false
        var busy = false
        var flash: Bool?
        var title = ""
    }

    init(model: AppModel) {
        self.model = model
        super.init()
        main.autosaveName = "flaran.main"
        if let button = main.button {
            button.image = menuBarIcon(errors: false)
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])  // opens on press, like system items
        }
        setUp(restart, icon: .restart, name: "Hot Restart", action: #selector(restartClicked))
        setUp(reload, icon: .reload, name: "Hot Reload", action: #selector(reloadClicked))
        model.setPanelVisible = { [weak self] visible in visible ? self?.showPanel() : self?.panel.close() }
        panel.onClose = { [weak self] in
            self?.main.button?.highlight(false)
            self?.model.panelClosed()
        }

        Task { [weak self] in
            let changes = Observations { [weak self] in self?.snapshot() ?? Snapshot() }
            for await snapshot in changes { self?.apply(snapshot) }
        }
    }

    #if DEBUG
    /// Opens the panel under an arbitrary rect (the showcase's fake menu bar icon), kept left of `rightEdge`.
    func showPanel(below rect: NSRect, rightEdge: CGFloat) { panel.show(below: rect, rightEdge: rightEdge) }
    var panelFrame: NSRect { panel.frame }
    #endif

    @objc private func togglePanel() {
        panel.isVisible ? panel.close() : showPanel()
    }

    private func showPanel() {
        guard let button = main.button, let frame = button.window?.frame else { return }
        button.highlight(true)
        panel.show(below: frame)
    }

    private func setUp(_ item: NSStatusItem, icon: Glyph, name: String, action: Selector) {
        item.autosaveName = "flaran.\(name)"
        item.isVisible = false
        guard let button = item.button else { return }
        let image = icon.image(size: 17)
        image.accessibilityDescription = name
        button.image = image
        button.target = self
        button.action = action
    }

    private func snapshot() -> Snapshot {
        var s = Snapshot(errors: model.hasUnseenErrors)
        guard let session = model.selected, model.sessions.contains(where: \.isActive) else { return s }
        s.visible = true
        s.enabled = session.canReload
        s.busy = session.state == .reloading
        s.flash = session.lastActionOK
        s.title = session.title
        return s
    }

    private func apply(_ s: Snapshot) {
        main.button?.image = menuBarIcon(errors: s.errors)
        main.button?.toolTip = s.errors ? "Flaran: errors in a log" : "Flaran"
        restart.isVisible = s.visible
        reload.isVisible = s.visible
        for (item, name) in [(reload, "Hot reload"), (restart, "Hot restart")] {
            guard let button = item.button else { continue }
            button.appearsDisabled = !s.enabled
            button.alphaValue = s.busy ? 0.4 : 1
            button.contentTintColor = s.flash.map { $0 ? .systemGreen : .systemRed }
            button.toolTip = "\(name) \(s.title)"
        }
    }

    @objc private func reloadClicked() { Task { await model.selected?.reload() } }
    @objc private func restartClicked() { Task { await model.selected?.restart() } }
}

/// A borderless panel hanging under the menu bar icon. It takes key (for Esc and scrolling)
/// without activating Flaran, so the app you were in stays frontmost.
final class MenuPanel: NSPanel {
    var onClose: () -> Void = {}
    private var anchorTop: CGFloat = 0
    /// Preferred left edge (just left of the icon); pages wider than the room left are pulled in.
    private var anchorLeft: CGFloat = 0
    /// Right limit for the panel; the screen edge unless the showcase passes its backdrop's edge.
    private var rightEdge: CGFloat?
    private var outsideClicks: Any?

    init(model: AppModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
                   styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        // The SwiftUI view reports its natural size and we resize the panel ourselves, top edge pinned.
        // (NSHostingView's own window sizing recursed into a stack overflow with scrolling pages.)
        var resize: (CGSize) -> Void = { _ in }
        let host = NSHostingView(rootView: PanelView(model: model) { resize($0) })
        host.sizingOptions = []
        contentView = host
        resize = { [weak self] size in self?.fit(size) }
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes from anywhere, even with the log text view focused (it would eat cancelOperation).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 { return close() }
        super.sendEvent(event)
    }

    func show(below item: NSRect, rightEdge: CGFloat? = nil) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(item) }) ?? NSScreen.main else { return }
        self.rightEdge = rightEdge
        anchorTop = item.minY - 6
        anchorLeft = max(item.minX - 10, screen.visibleFrame.minX + 8)
        let x = min(anchorLeft, (rightEdge ?? screen.visibleFrame.maxX) - frame.width - 8)
        setFrameTopLeftPoint(NSPoint(x: x, y: anchorTop))
        makeKeyAndOrderFront(nil)
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in MainActor.assumeIsolated { self?.close() }
        }
    }

    override func close() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        super.close()
        onClose()
    }

    /// Content grows and shrinks between pages; keep the top edge pinned under the menu bar.
    private func fit(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        let top = isVisible ? anchorTop : frame.maxY
        var x = isVisible ? anchorLeft : frame.minX
        if let maxX = rightEdge ?? screen?.visibleFrame.maxX { x = min(x, maxX - size.width - 8) }
        setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}

/// The Flaran mark (Resources/Branding/flaran-mark.svg) as a template image; with unseen errors,
/// a non-template copy with a red dot (menu bar labels drop colour from template images).
func menuBarIcon(errors: Bool) -> NSImage {
    let mark = NSImage(data: Data(flaranMarkSVG.utf8)) ?? NSImage()
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        mark.draw(in: rect)
        if errors {
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6.5, y: rect.maxY - 6.5, width: 6.5, height: 6.5)).fill()
        }
        return true
    }
    image.isTemplate = !errors
    image.accessibilityDescription = "Flaran"
    return image
}

private let flaranMarkSVG = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path fill="#000" d="M32.70 14.66 L77.70 14.66 Q88.70 14.66 88.70 25.66 L88.70 25.66 Q88.70 36.66 77.70 36.66 L52.52 36.66 Q49.52 36.66 46.90 35.20 L21.33 20.99 Q18.70 19.54 18.70 17.10 L18.70 17.10 Q18.70 14.66 32.70 14.66 Z M21.33 29.00 L38.08 38.31 Q40.70 39.77 40.70 42.77 L40.70 79.66 Q40.70 90.66 29.70 90.66 L29.70 90.66 Q18.70 90.66 18.70 79.66 L18.70 30.54 Q18.70 27.54 21.33 29.00 Z M55.57 48.03 L75.84 59.28 Q83.70 63.66 75.84 68.03 L55.57 79.28 Q47.70 83.66 47.70 74.66 L47.70 52.66 Q47.70 43.66 55.57 48.03 Z"/></svg>"##
