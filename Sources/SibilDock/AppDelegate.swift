import AppKit
import SwiftUI
import ServiceManagement
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Floating mode
    private var floatingPanel: FloatingPanel?
    private var moveObserver: NSObjectProtocol?
    private var hasPositionedOnce = false
    private let savedOriginKey = "SibilDockOrigin"

    // Edge-attached mode
    private var edgePanel: EdgePanel?
    private var edgeState: EdgeDockState?

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLoginItemIfNeeded()
        setupForCurrentMode()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // `@Published`'s publisher emits during willSet, before the property
        // is actually stored — so re-reading DockSettings.shared.attachmentMode
        // from inside this subscriber would see the *previous* mode, not the
        // one just selected (exactly backwards). Using the emitted value
        // directly instead sidesteps that entirely.
        DockSettings.shared.$attachmentMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in self?.setupForCurrentMode(mode) }
            .store(in: &cancellables)

        // Widget list changes (from Settings) only need to resize the
        // edge-attached panel, and only when that mode is active — it's a
        // deliberate, infrequent user action, not hover, so it doesn't
        // reintroduce the feedback-loop instability the fixed-frame design
        // avoids for hover (see relayoutEdgePanel's doc comment).
        Publishers.CombineLatest(DockSettings.shared.$widgetOrder, DockSettings.shared.$disabledWidgets)
            .dropFirst()
            .sink { [weak self] _, _ in self?.relayoutEdgePanel() }
            .store(in: &cancellables)
    }

    /// A last-chance flush in case shutdown/restart cuts the process before
    /// the position from the last drag made it to disk.
    func applicationWillTerminate(_ notification: Notification) {
        savePosition()
    }

    /// No menu bar icon, so this is the only affordance to quit — reached via
    /// the dock's right-click menu (see `showMenu`).
    private func registerLoginItemIfNeeded() {
        guard SMAppService.mainApp.status != .enabled else { return }
        try? SMAppService.mainApp.register()
    }

    // MARK: - Mode switching

    @MainActor
    private func setupForCurrentMode(_ mode: AttachmentMode? = nil) {
        tearDownPanels()
        switch mode ?? DockSettings.shared.attachmentMode {
        case .floating: setupFloatingPanel()
        case .edgeAttached: setupEdgePanel()
        }
    }

    private func tearDownPanels() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        floatingPanel?.orderOut(nil)
        floatingPanel = nil
        hasPositionedOnce = false

        edgePanel?.orderOut(nil)
        edgePanel = nil
        edgeState = nil
    }

    // MARK: - Floating mode

    /// The dock's tiles are always the same square size, but its overall
    /// footprint still changes when the user flips orientation in Settings
    /// (a vertical stack vs. a horizontal row). Every layout — the initial
    /// one and any later resize — comes through `reportSize`, so this is the
    /// single place that sizes and positions the panel: first launch goes to
    /// the saved (or default) spot, every later resize keeps the dock's
    /// on-screen center fixed so it doesn't jump when it changes shape.
    @MainActor
    private func setupFloatingPanel() {
        let placeholderSize = CGSize(width: DockMetrics.tileSize, height: DockMetrics.tileSize)
        let content = DockView(onSizeChange: { [weak self] size in
            self?.layoutFloatingPanel(size: size)
        })
        let hosting = DraggableHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: placeholderSize)

        let panel = FloatingPanel(contentRect: NSRect(origin: initialOrigin(for: placeholderSize), size: placeholderSize))
        panel.contentView = hosting
        panel.onRightClick = { [weak self] event in self?.showMenu(with: event) }
        self.floatingPanel = panel
        panel.orderFrontRegardless()

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.savePosition()
        }
    }

    @MainActor
    private func layoutFloatingPanel(size: CGSize) {
        guard let panel = floatingPanel, size.width > 0, size.height > 0 else { return }
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
        // default if the saved spot is off the screen entirely.
        return screen.frame.intersects(bounds) ? origin : defaultOrigin
    }

    /// `UserDefaults` writes are normally batched to disk lazily, which is
    /// fine for a quit initiated by the user — but a system restart can kill
    /// the process before that happens, silently dropping the last drag's
    /// position. `synchronize()` forces it to disk immediately so a restart
    /// can't lose it.
    private func savePosition() {
        guard let origin = floatingPanel?.frame.origin else { return }
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: savedOriginKey)
        UserDefaults.standard.synchronize()
    }

    // MARK: - Edge-attached mode

    @MainActor
    private var edgePanelSize: CGSize {
        let count = max(CGFloat(DockSettings.shared.enabledWidgets.count), 1)
        let height = DockMetrics.tileSize * count
            + DockMetrics.tileSpacing * (count - 1)
            + DockMetrics.outerPadding * 2
        let width = DockMetrics.tileSize + DockMetrics.outerPadding * 2
        return CGSize(width: width, height: height)
    }

    /// The panel's frame is fixed for its whole lifetime *with respect to
    /// hover* — right edge flush with the screen, vertically centered.
    /// Collapse/expand is purely a SwiftUI content change (EdgeDockView swaps
    /// in the thin handle or the full tile stack) inside that same frame;
    /// the window itself never resizes in response to hover. Animating the
    /// *window* in response to hover on that same window is unstable:
    /// resizing while the mouse sits still perturbs the hover tracking area
    /// mid-animation, which flips isExpanded back and forth. The window
    /// doesn't move on hover, so there is nothing to destabilize.
    @MainActor
    private func setupEdgePanel() {
        guard let screen = NSScreen.main else { return }
        let state = EdgeDockState()
        self.edgeState = state

        let screenFrame = screen.frame
        let size = edgePanelSize
        let frame = NSRect(
            x: screenFrame.maxX - size.width,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        let hosting = NSHostingView(rootView: EdgeDockView(state: state))
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = EdgePanel(contentRect: frame)
        panel.contentView = hosting
        panel.onRightClick = { [weak self] event in self?.showMenu(with: event) }
        self.edgePanel = panel
        panel.orderFrontRegardless()
    }

    /// Re-sizes the edge-attached panel when the enabled widget list changes.
    /// Not hover-driven, so this can't reintroduce the tracking-area feedback
    /// loop the fixed-frame design avoids (see setupEdgePanel).
    @MainActor
    private func relayoutEdgePanel() {
        guard DockSettings.shared.attachmentMode == .edgeAttached, let panel = edgePanel else { return }
        let size = edgePanelSize
        let centerY = panel.frame.midY
        let newFrame = NSRect(
            x: (NSScreen.main?.frame.maxX ?? panel.frame.maxX) - size.width,
            y: centerY - size.height / 2,
            width: size.width,
            height: size.height
        )
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(newFrame, display: true)
    }

    // MARK: - Shared

    /// If the display configuration changes (monitor unplugged, resolution
    /// change), keep whichever panel is active reachable: snap the floating
    /// panel back to the default spot if it's now off-screen, or re-anchor
    /// the edge panel to the (possibly new) screen edge.
    @MainActor
    @objc private func screenParametersChanged() {
        switch DockSettings.shared.attachmentMode {
        case .floating:
            guard let panel = floatingPanel, let screen = NSScreen.main else { return }
            if !screen.frame.intersects(panel.frame) {
                let visibleFrame = screen.visibleFrame
                let size = panel.frame.size
                let origin = CGPoint(x: visibleFrame.minX + 16, y: visibleFrame.midY - size.height / 2)
                panel.setFrameOrigin(origin)
            }
        case .edgeAttached:
            relayoutEdgePanel()
        }
    }

    /// A native AppKit menu, shown by the active panel's own `rightMouseDown`
    /// override — deliberately not SwiftUI's `.contextMenu`, which makes its
    /// whole view hit-testable and would perturb both the floating panel's
    /// background-drag hit-testing and the edge panel's hover tracking.
    @MainActor
    private func showMenu(with event: NSEvent) {
        guard let contentView = floatingPanel?.contentView ?? edgePanel?.contentView else { return }

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "About SibilDock", action: #selector(openAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Support Me", action: #selector(openSupportLink), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SibilDock", action: #selector(quit), keyEquivalent: "").target = self

        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }

    @MainActor @objc private func openSupportLink() {
        if let url = URL(string: "https://buymeacoffee.com/farnoud") {
            NSWorkspace.shared.open(url)
        }
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
/// follows the user across Spaces and full-screen apps, and never steals
/// focus. Used in `.floating` mode — draggable via DraggableHostingView.
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

/// A borderless, non-activating panel pinned to the screen edge. Used in
/// `.edgeAttached` mode — never dragged, never becomes key (purely a hover
/// surface), and needs `acceptsMouseMovedEvents` for SwiftUI's `.onHover` to
/// fire at all (off by default on NSWindow).
final class EdgePanel: NSPanel {
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
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick {
            onRightClick(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}
