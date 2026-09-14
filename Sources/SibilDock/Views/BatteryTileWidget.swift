import SwiftUI

/// Battery ring with a small Wi-Fi badge in the corner, matching the combined
/// battery/connectivity tile from the reference lock-screen widget stack.
struct BatteryTileWidget: View {
    @StateObject private var battery = BatteryService()
    @StateObject private var wifi = WiFiService()

    private var ringColor: Color {
        if battery.isCharging { return .blue }
        if battery.percentage <= 20 { return .orange }
        return .white
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(battery.percentage) / 100)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if battery.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text("\(battery.percentage)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Image(systemName: wifi.isConnected ? "wifi" : "wifi.slash")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(wifi.isConnected ? .white.opacity(0.9) : .white.opacity(0.3))
                        .padding(3)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                Spacer()
            }
        }
        .frame(width: 38, height: 38)
        .tileBackground()
    }
}
