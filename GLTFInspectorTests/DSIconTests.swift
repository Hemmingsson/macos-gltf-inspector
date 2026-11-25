import AppKit
import Testing
@testable import GLTFInspector

@MainActor
struct DSIconTests {
    @Test func inspectorIconWinsWhenTheCatalogHasIt() {
        #expect(DSIcon.source("inspector.zoom-in", fallback: "magnifyingglass") == .catalog("inspector.zoom-in"))
    }

    @Test func missingInspectorIconFallsBackToTheSymbol() {
        #expect(DSIcon.source("inspector.no-such-icon", fallback: "magnifyingglass") == .system("magnifyingglass"))
    }

    @Test func noAssetNameMeansTheSymbol() {
        #expect(DSIcon.source(nil, fallback: "cube") == .system("cube"))
    }

    /// The catalog is generated (`assets/icons/inspector/build-catalog.mjs`); every icon must load
    /// as a template image so SwiftUI can tint it.
    @Test(arguments: ["hidden", "visible", "node-shared-mesh", "loop", "auto-rotate", "play", "settings"])
    func catalogIconsLoadAsTemplates(_ name: String) throws {
        let image = try #require(NSImage(named: "inspector.\(name)"))
        #expect(image.isTemplate)
        #expect(image.size.width > 0)
    }
}
