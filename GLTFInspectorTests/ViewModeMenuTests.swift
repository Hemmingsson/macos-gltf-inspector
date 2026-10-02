import PreviewUI
import Testing

/// The Look cluster's view-mode title. A settled change must show one name — interpolate
/// / numericText on "Shaded"→"Wireframe" painted both strings at once ("Swiaredame").
@MainActor
struct ViewModeMenuTests {
    @Test func settledChangeShowsOneTitle() {
        let viewport = MockViewportController(viewMode: .shaded)
        #expect(ViewModeMenuChrome.settledTitle(for: viewport.viewMode) == "Shaded")

        viewport.setViewMode(.wireframe)
        let title = ViewModeMenuChrome.settledTitle(for: viewport.viewMode)
        #expect(title == "Wireframe")
        #expect(!title.contains("Shaded"))
        #expect(title == ViewMode.wireframe.title)
    }

    @Test func titledChipDoesNotInterpolateModeNames() {
        #expect(!ViewModeMenuChrome.interpolatesTitle)
    }
}
