import Foundation
import Darwin
import Combine

/// Approximates Activity Monitor's "Memory Used" percentage: active + wired +
/// compressed pages over total physical memory.
@MainActor
final class MemoryService: ObservableObject {
    @Published var usedPercentage: Int = 0

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { statsPtr -> kern_return_t in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let used = usedPages * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return }

        usedPercentage = Int((Double(used) / Double(total) * 100).rounded())
    }
}
