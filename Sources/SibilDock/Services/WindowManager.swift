import AppKit
import SwiftUI

/// Owns the Settings and About windows. The dock's own panel is a
/// non-activating accessory-app window, so these regular windows need an
/// explicit activate to reliably come to the front and take keyboard focus.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?

    private init() {}

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "SibilDock Settings", view: SettingsView())
        }
        show(settingsWindow)
    }

    func showAbout() {
        if aboutWindow == nil {
            aboutWindow = makeWindow(title: "About SibilDock", view: AboutView())
        }
        show(aboutWindow)
    }

    private func show(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<V: View>(title: String, view: V) -> NSWindow {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
