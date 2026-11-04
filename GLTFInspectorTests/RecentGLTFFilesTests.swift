import Foundation
@testable import GLTFInspector
import Testing

struct RecentGLTFFilesTests {
    @Test func keepsGLTFAndCapsAtSix() {
        let urls = (1...8).map { URL(fileURLWithPath: "/tmp/model\($0).glb") }
            + [URL(fileURLWithPath: "/tmp/notes.txt"), URL(fileURLWithPath: "/tmp/scene.gltf")]
        let kept = RecentGLTFFiles.urls(from: urls)
        #expect(kept.count == 6)
        #expect(kept.allSatisfy(DocumentOpening.isGLTFFile))
        #expect(kept.first?.lastPathComponent == "model1.glb")
    }

    @Test func emptyWhenNothingMatches() {
        let kept = RecentGLTFFiles.urls(from: [URL(fileURLWithPath: "/tmp/notes.txt")])
        #expect(kept.isEmpty)
    }
}
