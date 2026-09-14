import SwiftUI

struct WeatherTileWidget: View {
    @StateObject private var weather = WeatherService()

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: weather.currentSymbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            if let temp = weather.currentTemp {
                Text("\(temp)°")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(width: 48, height: 38)
        .tileBackground()
        .task { weather.start() }
    }
}
