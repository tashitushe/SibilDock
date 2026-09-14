import Foundation
import Combine

enum DockOrientation: String, CaseIterable, Identifiable {
    case vertical, horizontal

    var id: String { rawValue }
    var label: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        }
    }
}

enum WidgetKind: String, CaseIterable, Identifiable {
    case battery, weather, nowPlaying, clock

    var id: String { rawValue }
    var label: String {
        switch self {
        case .battery: return "Battery & Wi-Fi"
        case .weather: return "Weather"
        case .nowPlaying: return "Now Playing"
        case .clock: return "Clock"
        }
    }
}

/// The dock's user-configurable layout: orientation and widget order, both
/// persisted so they survive relaunches. A single shared instance since the
/// floating panel, the dock's own content, and the Settings window all need
/// to read and react to the same state.
@MainActor
final class DockSettings: ObservableObject {
    static let shared = DockSettings()

    @Published var orientation: DockOrientation {
        didSet { UserDefaults.standard.set(orientation.rawValue, forKey: Keys.orientation) }
    }
    @Published var widgetOrder: [WidgetKind] {
        didSet { UserDefaults.standard.set(widgetOrder.map(\.rawValue), forKey: Keys.order) }
    }

    private enum Keys {
        static let orientation = "SibilDockOrientation"
        static let order = "SibilDockWidgetOrder"
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.orientation),
           let value = DockOrientation(rawValue: raw) {
            orientation = value
        } else {
            orientation = .vertical
        }

        if let savedRaw = UserDefaults.standard.array(forKey: Keys.order) as? [String] {
            let saved = savedRaw.compactMap(WidgetKind.init(rawValue:))
            let missing = WidgetKind.allCases.filter { !saved.contains($0) }
            widgetOrder = saved + missing
        } else {
            widgetOrder = WidgetKind.allCases
        }
    }
}
