import Foundation
import Network
import Combine

/// Tracks whether the Mac currently has a working Wi-Fi connection, using
/// NWPathMonitor rather than CoreWLAN so no location permission is needed.
@MainActor
final class WiFiService: ObservableObject {
    @Published var isConnected: Bool = false

    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "com.floatingdock.wifimonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
