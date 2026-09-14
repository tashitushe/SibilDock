import AppKit
import SwiftUI

/// `NSHostingView` that also drags its own window on mouse-drag.
///
/// `NSPanel.isMovableByWindowBackground` alone isn't reliable here: SwiftUI's
/// hosting view claims hit-testing across its entire bounds (so its internal
/// gesture system can work anywhere in the tree), which means the window
/// never sees an "unclaimed" mouseDown to treat as background — even over
/// plain, non-interactive content. Tracking the drag manually sidesteps that
/// entirely instead of depending on AppKit's hit-testing heuristics.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    private var mouseDownScreenLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?

    override func mouseDown(with event: NSEvent) {
        mouseDownScreenLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        defer { super.mouseDragged(with: event) }
        guard let window, let mouseDownScreenLocation, let windowOriginAtMouseDown else { return }

        let current = NSEvent.mouseLocation
        let origin = NSPoint(
            x: windowOriginAtMouseDown.x + (current.x - mouseDownScreenLocation.x),
            y: windowOriginAtMouseDown.y + (current.y - mouseDownScreenLocation.y)
        )
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownScreenLocation = nil
        windowOriginAtMouseDown = nil
        super.mouseUp(with: event)
    }
}
