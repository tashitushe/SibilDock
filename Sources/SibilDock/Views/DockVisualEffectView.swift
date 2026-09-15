import SwiftUI
import AppKit

/// Wraps a real `NSVisualEffectView` instead of SwiftUI's generic `.material`
/// modifiers, using `.hudWindow` — the closest public material to the actual
/// system Dock's dark frosted-glass look (behind-window blending, so it
/// genuinely blurs whatever's on screen beneath the panel, like the real Dock).
struct DockVisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
