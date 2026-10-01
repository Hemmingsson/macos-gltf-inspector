import DesignSystem
import SwiftUI

/// Toolbar appearance choice. Applied with `.preferredColorScheme` on the detail.
enum CatalogAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// One of the three grounds glass must stay legible on.
enum CatalogBackdrop: String, CaseIterable, Identifiable {
    case lightCanvas, darkCanvas, checkerboard

    var id: Self { self }

    var title: String {
        switch self {
        case .lightCanvas: "Light canvas"
        case .darkCanvas: "Dark canvas"
        case .checkerboard: "Checkerboard"
        }
    }

    /// The ground itself. Canvas grounds resolve their dynamic colours in a fixed scheme, so the
    /// "light canvas" stays light when the catalog runs dark — as a white backdrop does in the app.
    @ViewBuilder
    var ground: some View {
        switch self {
        case .lightCanvas:
            DS.Color.Canvas.gradient.environment(\.colorScheme, .light)
        case .darkCanvas:
            DS.Color.Canvas.gradient.environment(\.colorScheme, .dark)
        case .checkerboard:
            DSCheckerboard(cell: 8)
        }
    }
}

/// Toolbar "Backdrop" filter — one ground at a time so glass can be judged at real size.
enum CatalogBackdropFilter: String, CaseIterable, Identifiable {
    case lightCanvas, darkCanvas, checkerboard

    var id: Self { self }

    var title: String {
        CatalogBackdrop(rawValue: rawValue)?.title ?? rawValue
    }

    var backdrop: CatalogBackdrop {
        CatalogBackdrop(rawValue: rawValue) ?? .lightCanvas
    }
}

extension DynamicTypeSize {
    var catalogTitle: String {
        switch self {
        case .xSmall: "Extra Small"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large (default)"
        case .xLarge: "Extra Large"
        case .xxLarge: "XX Large"
        case .xxxLarge: "XXX Large"
        case .accessibility1: "Accessibility 1"
        case .accessibility2: "Accessibility 2"
        case .accessibility3: "Accessibility 3"
        case .accessibility4: "Accessibility 4"
        case .accessibility5: "Accessibility 5"
        @unknown default: "Other"
        }
    }
}

extension EnvironmentValues {
    /// Which backdrops each state row renders over (toolbar filter).
    @Entry var catalogBackdrop: CatalogBackdrop = .lightCanvas
}

/// Launch arguments, read once (`-page colors -appearance dark -backdrop darkCanvas`), so pages can
/// be opened and captured without driving the UI.
enum CatalogLaunchOptions {
    static var page: CatalogPage? {
        UserDefaults.standard.string(forKey: "page").flatMap(CatalogPage.init(rawValue:))
    }

    static var appearance: CatalogAppearance {
        UserDefaults.standard.string(forKey: "appearance").flatMap(CatalogAppearance.init(rawValue:))
            ?? .system
    }

    static var backdrop: CatalogBackdropFilter {
        UserDefaults.standard.string(forKey: "backdrop").flatMap(CatalogBackdropFilter.init(rawValue:))
            ?? .lightCanvas
    }
}
