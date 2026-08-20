import Testing
@testable import GLBPreview

struct KhronosEnvironmentTests {
    @Test func catalogHasExactViewerTitles() {
        let titles = KhronosEnvironments.allCases.map(\.title)
        #expect(titles == [
            "Field",
            "Studio Neutral",
            "Colorful Studio",
        ])
        #expect(KhronosEnvironments.defaultLook == .studioNeutral)
        #expect(KhronosEnvironments.defaultLook.title == "Studio Neutral")
    }

    @Test func studioNeutralHDRIsInBundle() {
        let url = Bundle.main.url(forResource: "neutral", withExtension: "hdr")
            ?? Bundle.main.url(forResource: "neutral", withExtension: "hdr", subdirectory: "khronos")
        #expect(url != nil)
    }
}
