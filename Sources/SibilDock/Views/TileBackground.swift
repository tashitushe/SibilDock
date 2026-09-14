import SwiftUI

/// Shared sizing for the dock: every tile is the same square size, stacked
/// with the same spacing regardless of orientation, so the dock reads as one
/// uniform module whether it's arranged vertically or horizontally.
enum DockMetrics {
    static let tileSize: CGFloat = 56
    static let cornerRadius: CGFloat = 20
    static let tileSpacing: CGFloat = 10
    static let outerPadding: CGFloat = 8
}

/// Shared "floating glass tile" chrome used by every widget in the vertical dock.
struct TileBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: DockMetrics.tileSize, height: DockMetrics.tileSize)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DockMetrics.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: DockMetrics.cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                    RoundedRectangle(cornerRadius: DockMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DockMetrics.cornerRadius, style: .continuous))
    }
}

extension View {
    func tileBackground() -> some View {
        modifier(TileBackground())
    }
}
