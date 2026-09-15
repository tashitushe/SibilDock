import Foundation
import AppKit

/// Checks GitHub Releases for a newer SibilDock version, on explicit user
/// request from the dock's right-click menu. Never downloads or installs
/// automatically — just points the user at the release to grab it themselves.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let apiURL = URL(string: "https://api.github.com/repos/tashitushe/SibilDock/releases/latest")!
    private let fallbackReleasesURL = URL(string: "https://github.com/tashitushe/SibilDock/releases/latest")!

    private init() {}

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    func checkForUpdates() {
        Task {
            do {
                var request = URLRequest(url: apiURL)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, _) = try await URLSession.shared.data(for: request)
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

                let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

                if Self.isVersion(latestVersion, newerThan: currentVersion) {
                    let releaseURL = URL(string: release.htmlURL) ?? fallbackReleasesURL
                    showUpdateAvailable(latestVersion: latestVersion, releaseURL: releaseURL)
                } else {
                    showUpToDate()
                }
            } catch {
                showCheckFailed()
            }
        }
    }

    private static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let x = i < partsA.count ? partsA[i] : 0
            let y = i < partsB.count ? partsB[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func showUpdateAvailable(latestVersion: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "SibilDock \(latestVersion) is available. Download it from GitHub?"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        present(alert) { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releaseURL)
            }
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "SibilDock is on the latest version."
        alert.addButton(withTitle: "OK")
        present(alert)
    }

    private func showCheckFailed() {
        let alert = NSAlert()
        alert.messageText = "Couldn't Check for Updates"
        alert.informativeText = "Check your internet connection and try again."
        alert.addButton(withTitle: "OK")
        present(alert)
    }

    private func present(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        completion?(response)
    }
}
