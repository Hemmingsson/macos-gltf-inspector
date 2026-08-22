import AppKit
import SwiftUI

/// UserDefaults keys. **Writable from Settings only** for canvas defaults
/// (`autoRotate` / `showFloor` / `background`). Open windows seed once and never write these
/// back (DESIGN.md three-job rule). `appearance` and `showToolbar` remain app-wide.
enum SettingsKeys {
    static let autoRotate = "settings.preview.autoRotate"
    static let background = "settings.preview.background"
    static let showToolbar = "settings.preview.showToolbar"
    static let showFloor = "settings.preview.showFloor"
    static let appearance = "settings.general.appearance"
}

enum PreviewBackground: String, CaseIterable, Identifiable {
    case window
    case white
    case dark

    var id: Self { self }

    private static let charcoal = (r: 38.0 / 255, g: 38.0 / 255, b: 38.0 / 255)

    var shortTitle: String {
        switch self {
        case .window: "None"
        case .white: "Light"
        case .dark: "Dark"
        }
    }

    var color: Color {
        switch self {
        case .window: .clear
        case .white: .white
        case .dark: Color(red: Self.charcoal.r, green: Self.charcoal.g, blue: Self.charcoal.b)
        }
    }

    /// Opaque clear-color for `StillRenderer` / `RealityRenderer` (window/clear → light gray).
    var stillBackgroundCGColor: CGColor {
        switch self {
        case .window:
            return CGColor(gray: 0.94, alpha: 1)
        case .white:
            return CGColor(gray: 1, alpha: 1)
        case .dark:
            return CGColor(
                srgbRed: Self.charcoal.r,
                green: Self.charcoal.g,
                blue: Self.charcoal.b,
                alpha: 1
            )
        }
    }

    /// Polar grid hairlines — contrast against this backdrop (no filled disc).
    func gridLineNSColor(systemDark: Bool) -> NSColor {
        switch self {
        case .white:
            return NSColor(srgbRed: 0.42, green: 0.42, blue: 0.42, alpha: 1)
        case .dark:
            return NSColor(srgbRed: 0.62, green: 0.62, blue: 0.62, alpha: 1)
        case .window:
            if Self.windowUsesLightIcons(systemDark: systemDark) {
                return NSColor(srgbRed: 0.58, green: 0.58, blue: 0.58, alpha: 1)
            }
            return NSColor(srgbRed: 0.42, green: 0.42, blue: 0.42, alpha: 1)
        }
    }

    static func at(_ index: Int) -> PreviewBackground {
        allCases[index % allCases.count]
    }

    /// `BackdropStyle` / Settings raw value → `allCases` index (unknown → `.window`).
    static func index(matchingRawValue rawValue: String) -> Int {
        allCases.firstIndex(of: PreviewBackground(rawValue: rawValue) ?? .window) ?? 0
    }

    static var stored: PreviewBackground {
        let raw = UserDefaults.standard.string(forKey: SettingsKeys.background) ?? window.rawValue
        return PreviewBackground(rawValue: raw) ?? .window
    }

    static var storedIndex: Int {
        allCases.firstIndex(of: stored) ?? 0
    }

    static func useLightIcons(at index: Int, systemDark: Bool) -> Bool {
        switch at(index) {
        case .white: return false
        case .dark: return true
        case .window: return windowUsesLightIcons(systemDark: systemDark)
        }
    }

    private static func windowUsesLightIcons(systemDark: Bool) -> Bool {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            return true
        }
        return systemDark
    }

    static let inactiveIconOpacity = 0.55

    static func iconColor(at index: Int, systemDark: Bool, active: Bool) -> Color {
        let base: Color = useLightIcons(at: index, systemDark: systemDark)
            ? .white
            : Color(red: charcoal.r, green: charcoal.g, blue: charcoal.b)
        return active ? base : base.opacity(inactiveIconOpacity)
    }
}
