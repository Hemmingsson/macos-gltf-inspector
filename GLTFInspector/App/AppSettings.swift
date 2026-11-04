import AppKit
import GLTFCore
import Observation

/// The app's Settings, stored in the App Group suite (`AppGroupSettings`) so Quick Look and the
/// Finder thumbnail read what Settings writes. New windows start from these; a window's own
/// changes never write back (DESIGN.md three-job rule).
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: AppGroupSettings.defaults)

    @ObservationIgnored private let defaults: UserDefaults
    private typealias Key = AppGroupSettings.Key

    var backdrop: BackdropStyle { didSet { defaults.set(backdrop.rawValue, forKey: Key.background) } }
    var showsFloor: Bool { didSet { defaults.set(showsFloor, forKey: Key.showFloor) } }
    var autoRotates: Bool { didSet { defaults.set(autoRotates, forKey: Key.autoRotate) } }
    var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            appearance.apply()
        }
    }
    /// Lighting for new windows, Quick Look and thumbnails.
    var environment: LightingEnvironment { didSet { defaults.set(environment.rawValue, forKey: Key.environment) } }
    var toneMapping: RenderLook.ToneMapping { didSet { defaults.set(toneMapping.rawValue, forKey: Key.toneMapping) } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        AppGroupSettings.registerDefaults(in: defaults)
        let look = AppGroupSettings.look(defaults: defaults)
        backdrop = defaults.string(forKey: Key.background).flatMap(BackdropStyle.init) ?? .window
        showsFloor = defaults.bool(forKey: Key.showFloor)
        autoRotates = defaults.bool(forKey: Key.autoRotate)
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init) ?? .system
        environment = look.environment
        toneMapping = look.toneMapping
    }
}

/// The canvas background: the window behind a transparent canvas, or a solid colour.
enum BackdropStyle: String, CaseIterable, Identifiable {
    case window, white, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .window: "None"
        case .white: "White"
        case .dark: "Dark"
        }
    }

    var color: RenderLook.Color {
        switch self {
        case .window: .clear
        case .white: RenderLook.Color(red: 1, green: 1, blue: 1, alpha: 1)
        case .dark: RenderLook.Color(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
