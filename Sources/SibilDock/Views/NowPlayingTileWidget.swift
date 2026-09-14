import SwiftUI

/// Play/pause control with a playback-progress ring, tap to toggle.
struct NowPlayingTileWidget: View {
    @StateObject private var nowPlaying = NowPlayingService()

    private var progress: Double {
        guard nowPlaying.duration > 0 else { return 0 }
        return min(max(nowPlaying.elapsed / nowPlaying.duration, 0), 1)
    }

    var body: some View {
        Button {
            nowPlaying.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: nowPlaying.title != nil ? progress : 0)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: nowPlaying.title == nil ? "music.note" : (nowPlaying.isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(nowPlaying.title == nil ? .white.opacity(0.35) : .white)
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .disabled(nowPlaying.title == nil)
        .tileBackground()
    }
}
