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

    /// A last-chance flush in case shutdown/restart cuts the process before
    /// the position from the last drag made it to disk.
    func applicationWillTerminate(_ notification: Notification) {
        savePosition()
    }

    /// No menu bar icon, so this is the only affordance to quit — reached via
    /// the dock's right-click menu (see `showDockMenu`).
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
        let hosting = DraggableHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: placeholderSize)

        let panel = FloatingPanel(contentRect: NSRect(origin: initialOrigin(for: placeholderSize), size: placeholderSize))
        panel.contentView = hosting
        panel.onRightClick = { [weak self] event in self?.showDockMenu(with: event) }
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
        let visibleFrame = screen.visibleFrame
        let defaultOrigin = CGPoint(x: visibleFrame.minX + 16, y: visibleFrame.midY - size.height / 2)

        guard let saved = UserDefaults.standard.string(forKey: savedOriginKey) else { return defaultOrigin }
        let origin = NSPointFromString(saved)
        let bounds = NSRect(origin: origin, size: size)
        // The panel floats above the real Dock and menu bar, so a saved spot
        // overlapping them is still perfectly valid — only fall back to the
        // default if the saved spot is off the screen entirely. Checking
        // against visibleFrame here (which excludes those reserved regions)
        // was rejecting exactly the spots users are most likely to drag the
        // dock to, resetting its position on every relaunch.
        return screen.frame.intersects(bounds) ? origin : defaultOrigin
    }

    /// `UserDefaults` writes are normally batched to disk lazily, which is
    /// fine for a quit initiated by the user — but a system restart can kill
    /// the process before that happens, silently dropping the last drag's
    /// position. `synchronize()` forces it to disk immediately so a restart
    /// can't lose it.
    private func savePosition() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: savedOriginKey)
        UserDefaults.standard.synchronize()
    }

    /// If the display configuration changes (monitor unplugged, resolution
    /// change) and the dock is now off-screen, snap it back to the default
    /// left-edge spot rather than leaving it somewhere unreachable.
    @objc private func screenParametersChanged() {
        guard let panel, let screen = NSScreen.main else { return }
        if !screen.frame.intersects(panel.frame) {
            let visibleFrame = screen.visibleFrame
            let size = panel.frame.size
            let origin = CGPoint(x: visibleFrame.minX + 16, y: visibleFrame.midY - size.height / 2)
            panel.setFrameOrigin(origin)
        }
    }

    /// A native AppKit menu, shown by the panel's own `rightMouseDown` override —
    /// deliberately not SwiftUI's `.contextMenu`, which makes its whole view hit-testable
    /// and breaks `isMovableByWindowBackground` (dragging stops working anywhere on the dock).
    private func showDockMenu(with event: NSEvent) {
        guard let panel, let contentView = panel.contentView else { return }

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "About SibilDock", action: #selector(openAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SibilDock", action: #selector(quit), keyEquivalent: "").target = self

        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }

    @MainActor @objc private func openSettings() {
        WindowManager.shared.showSettings()
    }

    @MainActor @objc private func openAbout() {
        WindowManager.shared.showAbout()
    }

    @MainActor @objc private func checkForUpdates() {
        UpdateChecker.shared.checkForUpdates()
    }

    @MainActor @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

/// A borderless, non-activating panel that floats above nearly everything,
/// follows the user across Spaces and full-screen apps, and never steals focus.
final class FloatingPanel: NSPanel {
    var onRightClick: ((NSEvent) -> Void)?

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
        // Dragging is handled manually by DraggableHostingView instead — see its
        // doc comment for why isMovableByWindowBackground isn't reliable here.
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick {
            onRightClick(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}
