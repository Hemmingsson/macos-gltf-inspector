import CoreGraphics
import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import PreviewUI
@testable import RendererRealityKit
import SwiftUI
import Testing

/// The RealityKit backdrop list behind the viewport's backdrop picker.
struct EngineViewportBackdropTests {
    @Test func backdropRawValueIndexFallsBackToWindow() {
        #expect(
            PreviewBackground.index(matchingRawValue: BackdropStyle.dark.rawValue)
                == PreviewBackground.allCases.firstIndex(of: .dark)
        )
        #expect(
            PreviewBackground.index(matchingRawValue: "not-a-backdrop")
                == PreviewBackground.allCases.firstIndex(of: .window)
        )
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
        #expect((selection.detail?.geometry?.triangleCount ?? 0) > 0)

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

    @Test func materialSelectionClearsMeshHighlight() async throws {
        let url = TestFixtures.cube
        try #require(TestFixtures.exists(url))
        let loaded = try await EntityLoader.load(from: url, includeAnimations: false)
        try #require(!loaded.document.materials.isEmpty)
        let sidebar = HostSidebarModel(document: loaded.document)
        let selection = EngineSelectionModel(sidebar: sidebar)

        let rootIndex = try #require(sidebar.layerRootIndices().first)
        selection.select(NodeID(kind: .mesh, index: rootIndex))
        #expect(sidebar.selectedNodeIndex == rootIndex)

        let materialID = NodeID(kind: .material, index: 0)
        selection.select(materialID)
        #expect(selection.selected == materialID)
        #expect(sidebar.selectedNodeIndex == nil)
        #expect(selection.detail?.kind == .material)
        #expect(selection.detail?.material != nil)

        selection.select(materialID)
        #expect(selection.selected == materialID)
    }

    @Test func cameraAndAnimationAndMorphAndSceneAndSkinSelection() async throws {
        try #require(TestFixtures.exists(TestFixtures.cameras))
        let cameras = try await EntityLoader.load(from: TestFixtures.cameras, includeAnimations: false)
        let cameraSidebar = HostSidebarModel(document: cameras.document)
        let cameraSelection = EngineSelectionModel(sidebar: cameraSidebar)
        try #require(!cameras.document.cameras.isEmpty)
        let camID = NodeID(kind: .camera, index: 0)
        cameraSelection.select(camID)
        #expect(cameraSelection.selected == camID)
        #expect(cameraSelection.detail?.camera != nil)

        try #require(TestFixtures.exists(TestFixtures.boxAnimated))
        let animated = try await EntityLoader.load(from: TestFixtures.boxAnimated, includeAnimations: true)
        let animSidebar = HostSidebarModel(document: animated.document)
        let animSelection = EngineSelectionModel(sidebar: animSidebar)
        try #require(!animated.document.animations.isEmpty)
        let animID = NodeID(kind: .animation, index: 0)
        animSelection.select(animID)
        #expect(animSelection.detail?.animation != nil)

        try #require(TestFixtures.exists(TestFixtures.morph))
        let morph = try await EntityLoader.load(from: TestFixtures.morph, includeAnimations: false)
        let morphSidebar = HostSidebarModel(document: morph.document)
        let morphSelection = EngineSelectionModel(sidebar: morphSidebar)
        try #require(!morph.document.morphs.isEmpty)
        morphSelection.select(NodeID(kind: .morph, index: 0))
        #expect(morphSelection.detail?.morph != nil)

        try #require(TestFixtures.exists(TestFixtures.multiScene))
        let multi = try await EntityLoader.load(from: TestFixtures.multiScene, includeAnimations: false)
        let multiSidebar = HostSidebarModel(document: multi.document)
        let multiSelection = EngineSelectionModel(sidebar: multiSidebar)
        try #require(multi.document.scenes.count > 1)
        multiSelection.select(NodeID(kind: .scene, index: 0))
        #expect(multiSelection.detail?.sceneRootCount != nil)

        try #require(TestFixtures.exists(TestFixtures.rigged))
        let rigged = try await EntityLoader.load(from: TestFixtures.rigged, includeAnimations: false)
        let skinSidebar = HostSidebarModel(document: rigged.document)
        let skinSelection = EngineSelectionModel(sidebar: skinSidebar)
        try #require(!rigged.document.skins.isEmpty)
        skinSelection.select(NodeID(kind: .skin, index: 0))
        #expect(skinSelection.detail?.skin != nil)
        #expect(!(skinSelection.detail?.skin?.jointNames.isEmpty ?? true))
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
