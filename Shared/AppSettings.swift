import SwiftUI

enum SettingsKeys {
    static let autoRotate = "settings.preview.autoRotate"
    static let background = "settings.preview.background"
    static let playOnOpen = "settings.preview.playOnOpen"
    static let showStats = "settings.preview.showStats"
    static let showToolbar = "settings.preview.showToolbar"
    static let defaultCamera = "settings.preview.defaultCamera"
    static let appearance = "settings.general.appearance"
    static let quitWhenLastWindowCloses = "settings.general.quitWhenLastWindowCloses"
}

enum PreviewBackground: String, CaseIterable, Identifiable {
    case window
    case white
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .window: "Window"
        case .white: "White"
        case .dark: "Dark"
        }
    }

    var color: Color {
        switch self {
        case .window: .clear
        case .white: .white
        case .dark: Color(red: 38.0 / 255, green: 38.0 / 255, blue: 38.0 / 255)
        }
    }

    static func color(at index: Int) -> Color {
        allCases[index % allCases.count].color
    }

    /// White icons on dark surfaces; charcoal on light. Clear backdrop: OS setting first (QL `isDark` is flaky).
    static func useLightIcons(at index: Int, systemDark: Bool) -> Bool {
        switch allCases[index % allCases.count] {
        case .white:
            return false
        case .dark:
            return true
        case .window:
            if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
                return true
            }
            return systemDark
        }
    }

    static func iconColor(at index: Int, systemDark: Bool, active: Bool) -> Color {
        let base: Color = useLightIcons(at: index, systemDark: systemDark)
            ? .white
            : Color(red: 38.0 / 255, green: 38.0 / 255, blue: 38.0 / 255)
        return active ? base : base.opacity(0.4)
    }
}

enum PreviewDefaultCamera: String, CaseIterable, Identifiable {
    case fit
    case firstFile

    var id: Self { self }

    var title: String {
        switch self {
        case .fit: "Fit"
        case .firstFile: "First file camera"
        }
    }
}
