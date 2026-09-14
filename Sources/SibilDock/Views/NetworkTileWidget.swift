import SwiftUI

struct NetworkTileWidget: View {
    @StateObject private var network = NetworkSpeedService()

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
                Text(Self.format(network.downloadBytesPerSecond))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                Text(Self.format(network.uploadBytesPerSecond))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 48, height: 38)
        .tileBackground()
    }

    private static func format(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        if kb < 1 { return "0K" }
        if kb < 1000 { return String(format: "%.0fK", kb) }
        let mb = kb / 1024
        return String(format: "%.1fM", mb)
    }
}
