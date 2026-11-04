import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import Testing

/// The host View menu must not offer Double-Sided / Show Skeleton when the focused
/// window's renderer cannot drive them. WebKit's feature set lacks both.
@MainActor
struct HostViewMenuCommandsTests {
    @Test func documentWindowViewportUsesMountedRendererFeatures() {
        let web = DocumentWindowModel(
            documentURL: TestFixtures.cube,
            features: [.debugChannels, .wireframe, .materialVariants, .nodeSelection]
        )
        #expect(!web.engineViewport.features.contains(.doubleSided) && !web.engineViewport.features.contains(.skeletonOverlay))

        let reality = DocumentWindowModel(documentURL: TestFixtures.cube)
        #expect(reality.engineViewport.features.contains(.doubleSided) && reality.engineViewport.features.contains(.skeletonOverlay))
    }
}
