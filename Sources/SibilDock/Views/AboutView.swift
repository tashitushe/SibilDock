import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }

            VStack(spacing: 2) {
                Text("SibilDock")
                    .font(.system(size: 18, weight: .bold))
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("Developed by Farnoud Najari")
                    .font(.system(size: 12, weight: .medium))
                Link("farnoud.net", destination: URL(string: "https://farnoud.net")!)
                    .font(.system(size: 12))
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 260)
    }
}
