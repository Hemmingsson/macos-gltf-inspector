import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import Testing

/// The host View menu must not offer Double-Sided / Show Skeleton when the focused
/// window's renderer cannot drive them. WebKit's feature set lacks both.
@MainActor
struct HostViewMenuCommandsTests {
    @Test func viewMenuTogglesFollowRendererFeatures() {
        #expect(
            HostViewMenuAvailability.toggles(for: Set(RendererFeature.allCases))
                == [.doubleSided, .showSkeleton]
        )
        #expect(
            HostViewMenuAvailability.toggles(for: [
                .debugChannels, .wireframe, .materialVariants, .nodeSelection,
            ]) == []
        )
        #expect(HostViewMenuAvailability.toggles(for: [.doubleSided]) == [.doubleSided])
        #expect(HostViewMenuAvailability.toggles(for: [.skeletonOverlay]) == [.showSkeleton])
    }

    @Test func focusedWindowViewportCarriesRendererFeatures() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        let web = EngineViewportController(
            sidebar: sidebar,
            features: [.debugChannels, .wireframe, .orthographicProjection]
        )
        #expect(HostViewMenuAvailability.toggles(for: web.features).isEmpty)

        let reality = EngineViewportController(sidebar: sidebar)
        #expect(
            HostViewMenuAvailability.toggles(for: reality.features)
                == [.doubleSided, .showSkeleton]
        )
    }

    @Test func documentWindowViewportUsesMountedRendererFeatures() {
        let web = DocumentWindowModel(
            documentURL: TestFixtures.cube,
            features: [.debugChannels, .wireframe, .materialVariants, .nodeSelection]
        )
        #expect(HostViewMenuAvailability.toggles(for: web.engineViewport.features).isEmpty)

        let reality = DocumentWindowModel(documentURL: TestFixtures.cube)
        #expect(
            HostViewMenuAvailability.toggles(for: reality.engineViewport.features)
                == [.doubleSided, .showSkeleton]
        )
    }
}
