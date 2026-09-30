import Foundation
import GLTFKit2
@testable import RendererRealityKit
import Testing

/// GLTFKit2 finds our Draco decoder by class name only (no Swift reference), so nothing else
/// fails if the class stops being reachable from the framework.
@Suite("Draco decompressor")
struct DracoDecompressorTests {
    @Test func decoderClassResolvesByName() async throws {
        // `EntityLoader` registers the name before every load.
        _ = try? await EntityLoader.load(from: URL(fileURLWithPath: "/nonexistent.glb"))
        let decoder: AnyClass = try #require(NSClassFromString(GLTFAsset.dracoDecompressorClassName))
        #expect(class_conformsToProtocol(decoder, GLTFDracoMeshDecompressor.self))
    }
}
