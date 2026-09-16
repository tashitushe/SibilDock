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

enum AttachmentMode: String, CaseIterable, Identifiable {
    case floating, edgeAttached

    var id: String { rawValue }
    var label: String {
        switch self {
        case .floating: return "Floating"
        case .edgeAttached: return "Edge-Attached"
        }
    }
}

enum WidgetKind: String, CaseIterable, Identifiable {
    case battery, weather, nowPlaying, clock, network, memory

    var id: String { rawValue }
    var label: String {
        switch self {
        case .battery: return "Battery & Wi-Fi"
        case .weather: return "Weather"
        case .nowPlaying: return "Now Playing"
        case .clock: return "Clock"
        case .network: return "Network Speed"
        case .memory: return "Memory"
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
    @Published var attachmentMode: AttachmentMode {
        didSet { UserDefaults.standard.set(attachmentMode.rawValue, forKey: Keys.attachmentMode) }
    }
    @Published var widgetOrder: [WidgetKind] {
        didSet { UserDefaults.standard.set(widgetOrder.map(\.rawValue), forKey: Keys.order) }
    }
    @Published var disabledWidgets: Set<WidgetKind> {
        didSet { UserDefaults.standard.set(disabledWidgets.map(\.rawValue), forKey: Keys.disabled) }
    }

    /// Widgets in `widgetOrder` order, minus the ones the user turned off —
    /// what the dock should actually render.
    var enabledWidgets: [WidgetKind] {
        widgetOrder.filter { !disabledWidgets.contains($0) }
    }

    private enum Keys {
        static let orientation = "SibilDockOrientation"
        static let attachmentMode = "SibilDockAttachmentMode"
        static let order = "SibilDockWidgetOrder"
        static let disabled = "SibilDockDisabledWidgets"
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.orientation),
           let value = DockOrientation(rawValue: raw) {
            orientation = value
        } else {
            orientation = .vertical
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.attachmentMode),
           let value = AttachmentMode(rawValue: raw) {
            attachmentMode = value
        } else {
            attachmentMode = .floating
        }

        if let savedRaw = UserDefaults.standard.array(forKey: Keys.order) as? [String] {
            let saved = savedRaw.compactMap(WidgetKind.init(rawValue:))
            let missing = WidgetKind.allCases.filter { !saved.contains($0) }
            widgetOrder = saved + missing
        } else {
            widgetOrder = WidgetKind.allCases
        }

        if let savedDisabled = UserDefaults.standard.array(forKey: Keys.disabled) as? [String] {
            disabledWidgets = Set(savedDisabled.compactMap(WidgetKind.init(rawValue:)))
        } else {
            disabledWidgets = []
        }
    }
}
