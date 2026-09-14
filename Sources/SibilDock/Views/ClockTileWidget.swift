import SwiftUI

struct ClockTileWidget: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 1) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
            Text(now, format: .dateTime.weekday(.abbreviated))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(width: 48, height: 38)
        .tileBackground()
        .onReceive(timer) { now = $0 }
    }
}
