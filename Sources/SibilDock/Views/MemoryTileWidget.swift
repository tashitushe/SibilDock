import SwiftUI

struct MemoryTileWidget: View {
    @StateObject private var memory = MemoryService()

    private var ringColor: Color {
        if memory.usedPercentage >= 85 { return .red }
        if memory.usedPercentage >= 65 { return .orange }
        return .white
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(memory.usedPercentage) / 100)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(memory.usedPercentage)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("RAM")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: 38, height: 38)
        .tileBackground()
    }
}
