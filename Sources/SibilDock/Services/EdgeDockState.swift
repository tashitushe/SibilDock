import Combine

/// Whether the edge-attached dock is showing its full tile stack or just the
/// thin collapsed handle. Shared between the SwiftUI content (which sets it
/// via hover) and the AppDelegate (which resizes the actual panel in
/// response). Only relevant in `.edgeAttached` attachment mode.
@MainActor
final class EdgeDockState: ObservableObject {
    @Published var isExpanded = false
}
