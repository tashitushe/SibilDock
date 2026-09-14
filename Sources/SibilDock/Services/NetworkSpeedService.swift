import Foundation
import Darwin
import Combine

/// Samples per-interface byte counters once a second and reports the delta
/// as throughput, the same technique used by most menu-bar network monitors
/// (no special entitlements needed).
@MainActor
final class NetworkSpeedService: ObservableObject {
    @Published var downloadBytesPerSecond: Double = 0
    @Published var uploadBytesPerSecond: Double = 0

    private var timer: Timer?
    private var lastBytesIn: UInt64?
    private var lastBytesOut: UInt64?
    private var lastSampleTime: Date?

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func sample() {
        let (bytesIn, bytesOut) = Self.readInterfaceCounters()
        let now = Date()
        defer {
            lastBytesIn = bytesIn
            lastBytesOut = bytesOut
            lastSampleTime = now
        }

        guard let lastIn = lastBytesIn, let lastOut = lastBytesOut, let lastTime = lastSampleTime else { return }
        let elapsed = now.timeIntervalSince(lastTime)
        guard elapsed > 0 else { return }

        // Counters can drop (interface reset); ignore negative deltas rather than showing garbage.
        if bytesIn >= lastIn {
            downloadBytesPerSecond = Double(bytesIn - lastIn) / elapsed
        }
        if bytesOut >= lastOut {
            uploadBytesPerSecond = Double(bytesOut - lastOut) / elapsed
        }
    }

    private static func readInterfaceCounters() -> (UInt64, UInt64) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let name = String(cString: interface.ifa_name)
            guard name != "lo0",
                  interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPtr = interface.ifa_data
            else { continue }

            let ifData = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            bytesIn += UInt64(ifData.ifi_ibytes)
            bytesOut += UInt64(ifData.ifi_obytes)
        }
        return (bytesIn, bytesOut)
    }
}
