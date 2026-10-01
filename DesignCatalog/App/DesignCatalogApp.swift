import SwiftUI

/// Showcase app for the design system: tokens, every DS component, and the PreviewUI composites
/// built from PreviewSupport mocks — rendered with real Liquid Glass.
@main
struct DesignCatalogApp: App {
    var body: some Scene {
        WindowGroup("Design Catalog") {
            CatalogRootView()
        }
        .defaultSize(width: 1320, height: 900)
    }
}
