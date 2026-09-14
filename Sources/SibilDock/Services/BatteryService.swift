import Foundation
import IOKit.ps
import Combine

@MainActor
final class BatteryService: ObservableObject {
    @Published var percentage: Int = 100
    @Published var isCharging: Bool = false

    private var runLoopSource: CFRunLoopSource?

    init() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                service.refresh()
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: AnyObject]
        else { return }

        if let capacity = description[kIOPSCurrentCapacityKey] as? Int {
            percentage = capacity
        }
        if let state = description[kIOPSPowerSourceStateKey] as? String {
            isCharging = state == kIOPSACPowerValue
        }
    }
}
