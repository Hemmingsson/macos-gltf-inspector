import Foundation
import Testing
@testable import GLBPreview

@MainActor
struct EngineViewportControllerTests {
    @Test func backdropFloorAndPresetSettersReflect() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        let viewport = EngineViewportController(sidebar: sidebar)

        viewport.setBackdrop(.dark)
        viewport.setFloor(false)
        viewport.setAutoRotate(false)
        viewport.setCenter(false)
        viewport.setProjection(.orthographic)
        viewport.applyCameraPreset(.front)

        #expect(viewport.backdrop == .dark)
        #expect(viewport.showsFloor == false)
        #expect(viewport.autoRotates == false)
        #expect(viewport.isCentered == false)
        #expect(viewport.projection == .orthographic)
        #expect(viewport.activeCameraPreset == .front)
        #expect(viewport.hostBackdropIndex == PreviewBackground.allCases.firstIndex(of: .dark))
        #expect(viewport.hostOrthographic == true)
    }

    @Test func lightingMapsDegreesRadiansAndFileLights() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        let viewport = EngineViewportController(sidebar: sidebar)

        viewport.setLighting(
            LightingSettings(
                exposure: 1.5,
                environmentRotationDegrees: 90,
                usesFileLights: true,
                usesStudioEnvironment: false
            )
        )

        #expect(viewport.hostExposureEV == 1.5)
        #expect(viewport.hostDimStudioForFileLights == true)
        #expect(abs(viewport.hostEnvironmentYawRadians - Float.pi / 2) < 0.0001)
        #expect(viewport.lighting.usesFileLights == true)
        // Studio flag mirrors AppLook; setter must not fight it.
        #expect(viewport.lighting.usesStudioEnvironment == AppLookStore.shared.look.useEnvironmentMap)
    }

    @Test func sceneAndMaterialVariantDriveSidebar() {
        var document = GLTFSessionDocument()
        document.scenes = [
            .init(name: "A", rootNodeIndices: [0]),
            .init(name: "B", rootNodeIndices: [0]),
        ]
        document.nodes = [
            .init(index: 0, name: "Root", children: [], kind: .empty),
        ]
        let sidebar = HostSidebarModel(document: document)
        let viewport = EngineViewportController(sidebar: sidebar)

        viewport.setScene(NodeID(kind: .scene, index: 1))
        #expect(sidebar.activeSceneIndex == 1)
        #expect(viewport.activeSceneID == NodeID(kind: .scene, index: 1))

        viewport.setMaterialVariant(0)
        #expect(sidebar.selectedMaterialVariantIndex == 0)
        #expect(viewport.selectedMaterialVariantIndex == 0)

        viewport.setMaterialVariant(nil)
        #expect(sidebar.selectedMaterialVariantIndex == nil)
    }

    @Test func screenshotHandlerWiresWithoutPanel() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        var shotCount = 0
        let viewport = EngineViewportController(
            sidebar: sidebar,
            screenshotHandler: { shotCount += 1 }
        )
        viewport.screenshot()
        #expect(shotCount == 1)
    }
}

@MainActor
struct EngineSelectionModelTests {
    @Test func cubeSelectionAndVisibilityRoundTrip() async throws {
        let url = TestFixtures.cube
        try #require(TestFixtures.exists(url))
        let loaded = try await EntityLoader.load(from: url, includeAnimations: false)
        let sidebar = HostSidebarModel(document: loaded.document)
        let selection = EngineSelectionModel(sidebar: sidebar)

        let rootIndex = try #require(sidebar.layerRootIndices().first)
        let id = NodeID(kind: Self.nodeKind(loaded.document, index: rootIndex), index: rootIndex)

        selection.select(id)
        #expect(selection.selected == id)
        #expect(sidebar.selectedNodeIndex == rootIndex)
        #expect(selection.detail != nil)
        #expect(selection.detail?.name.isEmpty == false)

        // Set-semantics: selecting the same id again must not toggle clear.
        selection.select(id)
        #expect(selection.selected == id)

        selection.setVisible(id, false)
        #expect(selection.isVisible(id) == false)
        #expect(sidebar.hide.contains(rootIndex))

        selection.setVisible(id, true)
        #expect(selection.isVisible(id) == true)

        selection.isolate(id)
        #expect(selection.isolated == id)
        // Set-semantics: isolating the same id again must not toggle clear.
        selection.isolate(id)
        #expect(selection.isolated == id)
        selection.isolate(nil)
        #expect(selection.isolated == nil)

        selection.select(nil)
        #expect(selection.selected == nil)
        #expect(sidebar.selectedNodeIndex == nil)
    }

    private static func nodeKind(_ document: GLTFSessionDocument, index: Int) -> NodeKind {
        guard let node = document.nodes.first(where: { $0.index == index }) else { return .empty }
        switch node.kind {
        case .empty: return .empty
        case .mesh: return .mesh
        case .camera: return .camera
        case .light: return .light
        case .skin: return .skin
        }
    }
}
