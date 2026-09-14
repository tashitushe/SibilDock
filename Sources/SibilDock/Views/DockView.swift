import SwiftUI

struct DockView: View {
    @ObservedObject private var settings = DockSettings.shared
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        Group {
            if settings.orientation == .vertical {
                VStack(spacing: DockMetrics.tileSpacing) {
                    ForEach(settings.enabledWidgets) { tile(for: $0) }
                }
            } else {
                HStack(spacing: DockMetrics.tileSpacing) {
                    ForEach(settings.enabledWidgets) { tile(for: $0) }
                }
            }
        }
        .padding(DockMetrics.outerPadding)
        .fixedSize()
        .reportSize(onSizeChange)
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
