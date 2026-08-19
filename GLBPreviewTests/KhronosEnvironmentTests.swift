import Testing
@testable import GLBPreview

struct KhronosEnvironmentTests {
    @Test func catalogHasExactViewerTitles() {
        let titles = GLBKhronosEnvironments.all.map(\.title)
        #expect(titles == [
            "Cannon Exterior",
            "Footprint Court",
            "Pisa",
            "Doge's palace",
            "Dining room",
            "Field",
            "Helipad Goldenhour",
            "Papermill Ruins",
            "Studio Neutral",
            "Colorful Studio",
            "Wide Street",
        ])
        #expect(GLBKhronosEnvironments.defaultLook == .studioNeutral)
        #expect(GLBKhronosEnvironments.defaultLook.title == "Studio Neutral")
    }
}
