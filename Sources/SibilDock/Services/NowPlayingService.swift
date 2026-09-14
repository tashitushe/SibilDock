import Foundation
import AppKit
import Combine

/// Reads now-playing state from Music and Spotify over AppleScript (the public,
/// documented automation API both apps expose), and drives playback the same way.
///
/// An earlier version of this used the private `MediaRemote` framework, the same
/// one behind Control Center's system-wide Now Playing widget. That would have
/// covered any app, not just Music/Spotify — but on this machine `mediaremoted`
/// silently returns empty now-playing info to any locally-built binary that isn't
/// signed with Apple's private `com.apple.private.mediaremote` entitlement (which
/// isn't obtainable outside Apple); it only works for it if the AppleScript
/// approach fails.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published var title: String?
    @Published var artist: String?
    @Published var artwork: NSImage?
    @Published var isPlaying: Bool = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0

    private enum Source: String {
        case music = "Music"
        case spotify = "Spotify"
    }

    private var activeSource: Source?
    private var pollTimer: Timer?
    private var lastArtworkKey: String?
    private let artworkPath = NSTemporaryDirectory() + "floatingdock_artwork.jpg"

    init() {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if let state = Self.queryApp(.music) ?? Self.queryApp(.spotify) {
                await self.apply(state)
            } else {
                await self.clear()
            }
        }
    }

    func togglePlayPause() {
        guard let activeSource else { return }
        isPlaying.toggle()
        Task.detached(priority: .utility) {
            _ = Self.runAppleScript("tell application \"\(activeSource.rawValue)\" to playpause")
        }
    }

    func next() {
        guard let activeSource else { return }
        Task.detached(priority: .utility) {
            _ = Self.runAppleScript("tell application \"\(activeSource.rawValue)\" to next track")
        }
    }

    func previous() {
        guard let activeSource else { return }
        Task.detached(priority: .utility) {
            _ = Self.runAppleScript("tell application \"\(activeSource.rawValue)\" to previous track")
        }
    }

    // MARK: - Applying results back on the main actor

    private func apply(_ state: TrackState) {
        activeSource = state.source
        title = state.title
        artist = state.artist
        duration = state.duration
        elapsed = state.position
        isPlaying = state.isPlaying

        let artworkKey = "\(state.source.rawValue)|\(state.title)|\(state.artist)"
        guard artworkKey != lastArtworkKey else { return }
        lastArtworkKey = artworkKey

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let image = Self.fetchArtwork(for: state, path: self.artworkPath)
            await MainActor.run {
                guard self.lastArtworkKey == artworkKey else { return }
                self.artwork = image
            }
        }
    }

    private func clear() {
        activeSource = nil
        title = nil
        artist = nil
        artwork = nil
        isPlaying = false
        elapsed = 0
        duration = 0
        lastArtworkKey = nil
    }

    // MARK: - AppleScript plumbing (safe to call off the main actor)

    private struct TrackState {
        let source: Source
        let title: String
        let artist: String
        let duration: Double
        let position: Double
        let isPlaying: Bool
    }

    private nonisolated static func isRunning(_ source: Source) -> Bool {
        let script = "tell application \"System Events\" to (name of processes) contains \"\(source.rawValue)\""
        return runAppleScript(script) == "true"
    }

    private nonisolated static func queryApp(_ source: Source) -> TrackState? {
        guard isRunning(source) else { return nil }

        let script: String
        switch source {
        case .music:
            script = """
            tell application "Music"
                set ps to player state as string
                if ps is "playing" or ps is "paused" then
                    return ps & "|||" & (name of current track) & "|||" & (artist of current track) & "|||" & (duration of current track) & "|||" & (player position)
                else
                    return "stopped"
                end if
            end tell
            """
        case .spotify:
            script = """
            tell application "Spotify"
                set ps to player state as string
                if ps is "playing" or ps is "paused" then
                    return ps & "|||" & (name of current track) & "|||" & (artist of current track) & "|||" & ((duration of current track) / 1000) & "|||" & (player position)
                else
                    return "stopped"
                end if
            end tell
            """
        }

        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        guard parts.count == 5 else { return nil }

        return TrackState(
            source: source,
            title: parts[1],
            artist: parts[2],
            duration: Double(parts[3]) ?? 0,
            position: Double(parts[4]) ?? 0,
            isPlaying: parts[0] == "playing"
        )
    }

    private nonisolated static func fetchArtwork(for state: TrackState, path: String) -> NSImage? {
        switch state.source {
        case .music:
            let script = """
            tell application "Music"
                try
                    set artData to data of artwork 1 of current track
                    set fp to open for access POSIX file "\(path)" with write permission
                    set eof fp to 0
                    write artData to fp
                    close access fp
                    return "ok"
                on error
                    return "error"
                end try
            end tell
            """
            guard runAppleScript(script) == "ok" else { return nil }
            return NSImage(contentsOfFile: path)

        case .spotify:
            let script = "tell application \"Spotify\" to artwork url of current track"
            guard let urlString = runAppleScript(script), let url = URL(string: urlString) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        }
    }

    private nonisolated static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
