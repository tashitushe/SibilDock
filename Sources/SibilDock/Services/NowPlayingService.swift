import Foundation
import Combine

/// Reads and controls system-wide now-playing state.
///
/// Primary path: the bundled mediaremote-adapter (github.com/ungive/mediaremote-adapter,
/// BSD-3-Clause) — it loads Apple's private MediaRemote framework inside `/usr/bin/perl`
/// (an Apple-signed process), which sidesteps the private entitlement that blocks calling
/// it directly from our own unsigned binary. This covers *any* app that publishes
/// now-playing info system-wide (Music, Spotify, browsers, third-party players — the same
/// set Control Center's Now Playing widget shows).
///
/// Fallback: if the adapter isn't available or fails its self-test (Apple could close this
/// loophole in a future macOS release), this falls back to driving Music and Spotify
/// directly over AppleScript, same as before.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published var title: String?
    @Published var artist: String?
    @Published var isPlaying: Bool = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0

    private nonisolated static let perlURL = URL(fileURLWithPath: "/usr/bin/perl")

    private let adapterResources: MediaRemoteAdapterResources?
    private var usesAdapter = false
    private let decoder = JSONDecoder()

    private var streamProcess: Process?
    private var streamOutputPipe: Pipe?
    private var streamOutputBuffer = ""

    private enum AppleScriptSource: String {
        case music = "Music"
        case spotify = "Spotify"
    }
    private var activeAppleScriptSource: AppleScriptSource?
    private var pollTimer: Timer?

    init() {
        adapterResources = MediaRemoteAdapterResources.resolve()

        // Start with the AppleScript fallback right away — it's just scheduling a
        // timer, no blocking work — then probe the adapter off the main thread and
        // switch over if it's available. Never do the (synchronous, subprocess-
        // spawning) adapter self-test inside init(): a @StateObject's init runs
        // during SwiftUI's view-graph update, and any resulting state mutation that
        // lands back on the main thread before that update finishes crashes
        // AttributeGraph ("Publishing changes from within view updates").
        startAppleScriptPolling()

        if let adapterResources {
            Task.detached(priority: .utility) { [weak self] in
                guard Self.testAdapter(resources: adapterResources), let self else { return }
                await MainActor.run {
                    self.usesAdapter = true
                    self.stopAppleScriptPolling()
                    self.startAdapterStream()
                }
            }
        }
    }

    private func startAppleScriptPolling() {
        refreshAppleScript()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAppleScript() }
        }
    }

    private func stopAppleScriptPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit {
        streamOutputPipe?.fileHandleForReading.readabilityHandler = nil
        streamProcess?.terminationHandler = nil
        streamProcess?.terminate()
        pollTimer?.invalidate()
    }

    func togglePlayPause() {
        if usesAdapter {
            runAdapterCommand(["send", "2"])
        } else {
            guard let activeAppleScriptSource else { return }
            isPlaying.toggle()
            Task.detached(priority: .utility) {
                _ = Self.runAppleScript("tell application \"\(activeAppleScriptSource.rawValue)\" to playpause")
            }
        }
    }

    func next() {
        if usesAdapter {
            runAdapterCommand(["send", "4"])
        } else {
            guard let activeAppleScriptSource else { return }
            Task.detached(priority: .utility) {
                _ = Self.runAppleScript("tell application \"\(activeAppleScriptSource.rawValue)\" to next track")
            }
        }
    }

    func previous() {
        if usesAdapter {
            runAdapterCommand(["send", "5"])
        } else {
            guard let activeAppleScriptSource else { return }
            Task.detached(priority: .utility) {
                _ = Self.runAppleScript("tell application \"\(activeAppleScriptSource.rawValue)\" to previous track")
            }
        }
    }

    // MARK: - Adapter (universal) path

    private nonisolated static func testAdapter(resources: MediaRemoteAdapterResources) -> Bool {
        let process = Process()
        process.executableURL = perlURL
        process.arguments = resources.invocationArguments(for: ["test"])
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func runAdapterCommand(_ arguments: [String]) {
        guard let adapterResources else { return }
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = Self.perlURL
            process.arguments = adapterResources.invocationArguments(for: arguments)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }

    private func startAdapterStream() {
        guard let adapterResources else { return }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = Self.perlURL
        process.arguments = adapterResources.invocationArguments(for: ["stream", "--no-diff", "--debounce=150", "--no-artwork"])
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.scheduleAdapterStreamRestart() }
        }

        do {
            try process.run()
        } catch {
            return
        }

        streamProcess = process
        streamOutputPipe = pipe
        streamOutputBuffer = ""

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consumeAdapterOutput(data) }
        }
    }

    private func scheduleAdapterStreamRestart() {
        streamOutputPipe?.fileHandleForReading.readabilityHandler = nil
        streamProcess = nil
        streamOutputPipe = nil

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run { self.startAdapterStream() }
        }
    }

    private func consumeAdapterOutput(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        streamOutputBuffer += chunk

        while let newlineIndex = streamOutputBuffer.firstIndex(of: "\n") {
            let line = String(streamOutputBuffer[..<newlineIndex])
            streamOutputBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }
            processAdapterLine(line)
        }
    }

    private struct AdapterMessage: Decodable {
        let type: String?
        let payload: AdapterPayload?
    }

    private struct AdapterPayload: Decodable {
        let playing: Bool?
        let title: String?
        let artist: String?
        let duration: Double?
        let elapsedTime: Double?

        var isActive: Bool {
            !(title?.isEmpty ?? true) || !(artist?.isEmpty ?? true) || (duration ?? 0) > 0
        }
    }

    private func processAdapterLine(_ line: String) {
        if line == "null" {
            applyAdapter(payload: nil)
            return
        }
        guard let data = line.data(using: .utf8),
              let message = try? decoder.decode(AdapterMessage.self, from: data),
              message.type == nil || message.type == "data"
        else { return }
        applyAdapter(payload: message.payload)
    }

    private func applyAdapter(payload: AdapterPayload?) {
        guard let payload, payload.isActive else {
            title = nil
            artist = nil
            isPlaying = false
            elapsed = 0
            duration = 0
            return
        }
        title = payload.title
        artist = payload.artist
        isPlaying = payload.playing ?? false
        elapsed = payload.elapsedTime ?? 0
        duration = payload.duration ?? 0
    }

    // MARK: - AppleScript fallback (Music/Spotify only)

    private func refreshAppleScript() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if let state = Self.queryApp(.music) ?? Self.queryApp(.spotify) {
                await self.applyAppleScript(state)
            } else {
                await self.clearAppleScript()
            }
        }
    }

    private func applyAppleScript(_ state: TrackState) {
        activeAppleScriptSource = state.source
        title = state.title
        artist = state.artist
        duration = state.duration
        elapsed = state.position
        isPlaying = state.isPlaying
    }

    private func clearAppleScript() {
        activeAppleScriptSource = nil
        title = nil
        artist = nil
        isPlaying = false
        elapsed = 0
        duration = 0
    }

    private struct TrackState {
        let source: AppleScriptSource
        let title: String
        let artist: String
        let duration: Double
        let position: Double
        let isPlaying: Bool
    }

    private nonisolated static func isRunning(_ source: AppleScriptSource) -> Bool {
        let script = "tell application \"System Events\" to (name of processes) contains \"\(source.rawValue)\""
        return runAppleScript(script) == "true"
    }

    private nonisolated static func queryApp(_ source: AppleScriptSource) -> TrackState? {
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
