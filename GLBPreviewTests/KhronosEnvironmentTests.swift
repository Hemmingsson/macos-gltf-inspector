import Testing
@testable import GLBPreview

struct KhronosEnvironmentTests {
    @Test func catalogHasExactViewerTitles() {
        let titles = GLBKhronosEnvironments.allCases.map(\.title)
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

    @Test func studioNeutralHDRIsInBundle() {
        let url = Bundle.main.url(forResource: "neutral", withExtension: "hdr")
            ?? Bundle.main.url(forResource: "neutral", withExtension: "hdr", subdirectory: "khronos")
        #expect(url != nil)
    }
}
