import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var moveObserver: NSObjectProtocol?
    private var hasPositionedOnce = false

    private let savedOriginKey = "SibilDockOrigin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLoginItemIfNeeded()
        setupPanel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// No menu bar icon, so this is the only affordance to quit — reached via
    /// the dock's right-click context menu (see DockView).
    private func registerLoginItemIfNeeded() {
        guard SMAppService.mainApp.status != .enabled else { return }
        try? SMAppService.mainApp.register()
    }

    /// The dock's tiles are always the same square size, but its overall
    /// footprint still changes when the user flips orientation in Settings
    /// (a vertical stack vs. a horizontal row). Every layout — the initial
    /// one and any later resize — comes through `reportSize`, so this is the
    /// single place that sizes and positions the panel: first launch goes to
    /// the saved (or default) spot, every later resize keeps the dock's
    /// on-screen center fixed so it doesn't jump when it changes shape.
    private func setupPanel() {
        let placeholderSize = CGSize(width: DockMetrics.tileSize, height: DockMetrics.tileSize)
        let content = DockView(onSizeChange: { [weak self] size in
            self?.layoutPanel(size: size)
        })
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: placeholderSize)

        let panel = FloatingPanel(contentRect: NSRect(origin: initialOrigin(for: placeholderSize), size: placeholderSize))
        panel.contentView = hosting
        self.panel = panel
        panel.orderFrontRegardless()

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.savePosition()
        }
    }

    private func layoutPanel(size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        panel.contentView?.frame = NSRect(origin: .zero, size: size)

        let origin: CGPoint
        if hasPositionedOnce {
            let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        } else {
            origin = initialOrigin(for: size)
            hasPositionedOnce = true
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func initialOrigin(for size: CGSize) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.visibleFrame
        let defaultOrigin = CGPoint(x: screenFrame.minX + 16, y: screenFrame.midY - size.height / 2)

        guard let saved = UserDefaults.standard.string(forKey: savedOriginKey) else { return defaultOrigin }
        let origin = NSPointFromString(saved)
        let bounds = NSRect(origin: origin, size: size)
        return screenFrame.intersects(bounds) ? origin : defaultOrigin
    }

    private func savePosition() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: savedOriginKey)
    }

    /// If the display configuration changes (monitor unplugged, resolution
    /// change) and the dock is now off-screen, snap it back to the default
    /// left-edge spot rather than leaving it somewhere unreachable.
    @objc private func screenParametersChanged() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        if !screenFrame.intersects(panel.frame) {
            let size = panel.frame.size
            let origin = CGPoint(x: screenFrame.minX + 16, y: screenFrame.midY - size.height / 2)
            panel.setFrameOrigin(origin)
        }
    }
}

/// A borderless, non-activating panel that floats above nearly everything,
/// follows the user across Spaces and full-screen apps, and never steals focus.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
