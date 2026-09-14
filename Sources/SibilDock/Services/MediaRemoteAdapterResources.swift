import Foundation

/// Locates the bundled mediaremote-adapter.pl script and MediaRemoteAdapter.framework
/// (github.com/ungive/mediaremote-adapter, BSD-3-Clause) — either inside the packaged
/// .app bundle, or next to this source file when running the raw debug binary.
struct MediaRemoteAdapterResources {
    let scriptURL: URL
    let frameworkURL: URL

    func invocationArguments(for commandArguments: [String]) -> [String] {
        [scriptURL.path, frameworkURL.path] + commandArguments
    }

    static func resolve(bundle: Bundle = .main, fileManager: FileManager = .default) -> MediaRemoteAdapterResources? {
        let candidateDirectories = [
            bundle.resourceURL?.appendingPathComponent(directoryName),
            sourceResourceDirectoryURL
        ].compactMap { $0 }

        for directory in candidateDirectories {
            let script = directory.appendingPathComponent("mediaremote-adapter.pl")
            let framework = directory.appendingPathComponent("MediaRemoteAdapter.framework")
            let frameworkBinary = framework.appendingPathComponent("MediaRemoteAdapter")

            if fileManager.fileExists(atPath: script.path), fileManager.fileExists(atPath: frameworkBinary.path) {
                return MediaRemoteAdapterResources(scriptURL: script, frameworkURL: framework)
            }
        }
        return nil
    }

    private static let directoryName = "MediaRemoteAdapter"

    /// Dev-time fallback so this resolves when running `.build/debug/SibilDock`
    /// directly, before the resources are copied into an .app bundle.
    private static let sourceResourceDirectoryURL: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent(directoryName)
    }()
}
