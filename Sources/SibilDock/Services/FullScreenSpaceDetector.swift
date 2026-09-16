import Foundation

/// Whether the currently active Space is a full-screen Space. There's no
/// public AppKit API for this — collectionBehavior/level tricks (omitting
/// `.fullScreenAuxiliary`, dropping window level, disabling
/// `isFloatingPanel`) all turned out not to exclude an accessory app's
/// panels from full-screen Spaces on this system, verified empirically.
/// This uses the private but long-stable SkyLight Spaces API instead (the
/// same one tools like yabai and Hammerspoon's `hs.spaces` use) to ask
/// directly. If the symbols are ever missing on some future macOS, this
/// fails safe by reporting "not full screen" — the dock just stops hiding
/// rather than misbehaving.
enum FullScreenSpaceDetector {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW
    )

    private static let mainConnectionID: MainConnectionIDFn? = {
        guard let handle, let symbol = dlsym(handle, "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(symbol, to: MainConnectionIDFn.self)
    }()

    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn? = {
        guard let handle, let symbol = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyManagedDisplaySpacesFn.self)
    }()

    /// A Space dictionary's "type" is 4 for a full-screen tile Space, 0 for
    /// an ordinary desktop Space.
    private static let fullScreenSpaceType = 4

    static func isCurrentSpaceFullScreen() -> Bool {
        guard let mainConnectionID, let copyManagedDisplaySpaces else { return false }
        let cid = mainConnectionID()
        guard let displays = copyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        return displays.contains { display in
            guard let currentSpace = display["Current Space"] as? [String: Any],
                  let type = currentSpace["type"] as? Int else { return false }
            return type == fullScreenSpaceType
        }
    }
}
