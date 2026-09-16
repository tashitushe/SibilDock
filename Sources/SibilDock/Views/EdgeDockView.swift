import SwiftUI

/// Content for `.edgeAttached` mode: a thin collapsed handle flush against
/// the screen edge that expands into the full tile stack on hover, and
/// collapses again when the mouse leaves. The panel's own frame never
/// changes size in response to hover — only this content does, right-aligned
/// within it — so the hover tracking area stays put and doesn't destabilize
/// itself mid-transition (see AppDelegate).
struct EdgeDockView: View {
    @ObservedObject var state: EdgeDockState
    @ObservedObject private var settings = DockSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                if state.isExpanded {
                    VStack(spacing: DockMetrics.tileSpacing) {
                        ForEach(settings.enabledWidgets) { tile(for: $0) }
                    }
                    .padding(DockMetrics.outerPadding)
                } else {
                    CollapsedHandle()
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: state.isExpanded)
        .contentShape(Rectangle())
        .onHover { hovering in
            state.isExpanded = hovering
        }
    }

    @ViewBuilder
    private func tile(for kind: WidgetKind) -> some View {
        switch kind {
        case .battery: BatteryTileWidget()
        case .weather: WeatherTileWidget()
        case .nowPlaying: NowPlayingTileWidget()
        case .clock: ClockTileWidget()
        case .network: NetworkTileWidget()
        case .memory: MemoryTileWidget()
        }
    }
}

private struct CollapsedHandle: View {
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            ZStack {
                DockVisualEffectView()
                Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(Capsule())
            .frame(width: 8, height: 90)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .padding(.trailing, 3)
    }
}
