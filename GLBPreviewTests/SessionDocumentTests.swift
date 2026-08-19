import Testing
import RealityKit
@testable import GLBPreview

struct SessionDocumentTests {
    @Test func nodeIDComponentRoundTrips() {
        let entity = Entity()
        entity.components.set(GLTFNodeIDComponent(nodeIndex: 3))
        #expect(entity.components[GLTFNodeIDComponent.self]?.nodeIndex == 3)
    }

    @Test func emptyDocumentHasNoScenes() {
        let doc = GLTFSessionDocument()
        #expect(doc.scenes.isEmpty)
        #expect(doc.defaultSceneIndex == 0)
    }
}
