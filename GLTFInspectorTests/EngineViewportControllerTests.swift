import Foundation
import SwiftUI
import Testing
@testable import GLTFInspector

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
    }

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

        #expect(viewport.lighting.exposure == 1.5)
        #expect(viewport.lighting.usesFileLights == true)
        #expect(abs(viewport.lighting.environmentRotationDegrees - 90) < 0.0001)
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

    @Test func fileCameraSelectionDrivesSidebar() {
        var document = GLTFSessionDocument()
        document.cameras = [
            .init(name: "Cam", type: "perspective", yfov: 1, znear: 0.1, zfar: 100, xmag: nil, ymag: nil),
        ]
        document.nodes = [
            .init(index: 0, name: "CamNode", children: [], kind: .camera, cameraIndex: 0),
        ]
        let sidebar = HostSidebarModel(document: document)
        let viewport = EngineViewportController(sidebar: sidebar)

        viewport.setFileCamera(NodeID(kind: .camera, index: 0))
        #expect(sidebar.selectedCameraIndex == 0)

        viewport.setFileCamera(nil)
        #expect(sidebar.selectedCameraIndex == nil)

        viewport.setFileCamera(NodeID(kind: .camera, index: 0))
        viewport.fit()
        #expect(sidebar.selectedCameraIndex == nil)
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

    @Test func settingsOverlayTracksDefaultsInGetters() throws {
        let suite = "engine.viewport.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let lookDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-viewport-look-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lookDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: lookDir) }

        let defaultsStore = AppDefaultsStore(defaults: defaults)
        let lookStore = AppLookStore(directory: lookDir)
        let settings = EngineSettingsStore(defaultsStore: defaultsStore, lookStore: lookStore)
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        let viewport = EngineViewportController(sidebar: sidebar, settings: settings)

        defaultsStore.set(.dark, for: .backdrop)
        viewport.applySession(from: settings)
        #expect(viewport.backdrop == .dark)

        defaultsStore.set(.white, for: .backdrop)
        #expect(viewport.backdrop == .white)

        viewport.setBackdrop(.window)
        defaultsStore.set(.dark, for: .backdrop)
        #expect(viewport.backdrop == .window)

        settings.clearSession()
        #expect(viewport.backdrop == .dark)
    }

    @Test func hostSessionWriteThroughUpdatesBindings() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        var backdropIndex = 0
        var showFloor = true
        var autoRotate = true
        var centerModel = true
        var orthographic = false
        var exposureEV: Float = 0
        var dimStudio = false
        var environmentYaw: Float = 0
        var debugModeIndex = 0
        var doubleSided = false
        var showSkeleton = false
        var fieldOfView: Float = PreviewCamera.defaultFieldOfViewDegrees
        let host = PreviewSessionBindings(
            autoRotate: Binding(get: { autoRotate }, set: { autoRotate = $0 }),
            showFloor: Binding(get: { showFloor }, set: { showFloor = $0 }),
            backdropIndex: Binding(get: { backdropIndex }, set: { backdropIndex = $0 }),
            centerModel: Binding(get: { centerModel }, set: { centerModel = $0 }),
            orthographic: Binding(get: { orthographic }, set: { orthographic = $0 }),
            exposureEV: Binding(get: { exposureEV }, set: { exposureEV = $0 }),
            dimStudioForFileLights: Binding(get: { dimStudio }, set: { dimStudio = $0 }),
            environmentYaw: Binding(get: { environmentYaw }, set: { environmentYaw = $0 }),
            doubleSided: Binding(get: { doubleSided }, set: { doubleSided = $0 }),
            showSkeleton: Binding(get: { showSkeleton }, set: { showSkeleton = $0 }),
            fieldOfViewDegrees: Binding(get: { fieldOfView }, set: { fieldOfView = $0 }),
            debugModeIndex: Binding(get: { debugModeIndex }, set: { debugModeIndex = $0 }),
            debugModes: [.none, .wire]
        )
        let viewport = EngineViewportController(sidebar: sidebar, hostSession: host)

        viewport.setBackdrop(.dark)
        viewport.setFloor(false)
        viewport.setAutoRotate(false)
        viewport.setCenter(false)
        viewport.setProjection(.orthographic)
        viewport.setViewMode(.wireframe)
        viewport.setLighting(
            LightingSettings(
                exposure: 0.5,
                environmentRotationDegrees: 45,
                usesFileLights: true,
                usesStudioEnvironment: true
            )
        )

        #expect(backdropIndex == PreviewBackground.index(matchingRawValue: BackdropStyle.dark.rawValue))
        #expect(showFloor == false)
        #expect(autoRotate == false)
        #expect(centerModel == false)
        #expect(orthographic == true)
        #expect(debugModeIndex == 1)
        #expect(exposureEV == 0.5)
        #expect(dimStudio == true)
        #expect(abs(environmentYaw - Float.pi / 4) < 0.0001)
        #expect(viewport.showsFloor == false)
        #expect(viewport.viewMode == .wireframe)

        viewport.setDoubleSided(true)
        viewport.setShowSkeleton(true)
        viewport.setFieldOfViewDegrees(90)
        #expect(doubleSided == true)
        #expect(showSkeleton == true)
        #expect(fieldOfView == 90)
        #expect(viewport.doubleSided == true)
        #expect(viewport.showSkeleton == true)
        #expect(viewport.fieldOfViewDegrees == 90)

        viewport.setFieldOfViewDegrees(5)
        #expect(fieldOfView == PreviewCamera.clampedFieldOfView(5))
        viewport.reset()
        #expect(doubleSided == false)
        #expect(showSkeleton == false)
        #expect(fieldOfView == PreviewCamera.defaultFieldOfViewDegrees)
        #expect(exposureEV == 0)
    }

    @Test func applySessionRemountDoesNotClobberFileLightDim() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        var backdropIndex = 0
        var showFloor = true
        var autoRotate = true
        var centerModel = true
        var orthographic = false
        var exposureEV: Float = 0
        var dimStudio = false
        var environmentYaw: Float = 0
        var debugModeIndex = 0
        var doubleSided = false
        var showSkeleton = false
        var fieldOfView: Float = PreviewCamera.defaultFieldOfViewDegrees
        let host = PreviewSessionBindings(
            autoRotate: Binding(get: { autoRotate }, set: { autoRotate = $0 }),
            showFloor: Binding(get: { showFloor }, set: { showFloor = $0 }),
            backdropIndex: Binding(get: { backdropIndex }, set: { backdropIndex = $0 }),
            centerModel: Binding(get: { centerModel }, set: { centerModel = $0 }),
            orthographic: Binding(get: { orthographic }, set: { orthographic = $0 }),
            exposureEV: Binding(get: { exposureEV }, set: { exposureEV = $0 }),
            dimStudioForFileLights: Binding(get: { dimStudio }, set: { dimStudio = $0 }),
            environmentYaw: Binding(get: { environmentYaw }, set: { environmentYaw = $0 }),
            doubleSided: Binding(get: { doubleSided }, set: { doubleSided = $0 }),
            showSkeleton: Binding(get: { showSkeleton }, set: { showSkeleton = $0 }),
            fieldOfViewDegrees: Binding(get: { fieldOfView }, set: { fieldOfView = $0 }),
            debugModeIndex: Binding(get: { debugModeIndex }, set: { debugModeIndex = $0 }),
            debugModes: [.none]
        )
        let settings = EngineSettingsStore()
        let viewport = EngineViewportController(
            sidebar: sidebar,
            settings: settings,
            hostSession: host
        )

        // Convert-owned dim, as HostShellRootView does on punctual-light open.
        viewport.applyConvertedLighting(dimStudioForFileLights: true, resetExposureAndYaw: true)
        #expect(dimStudio == true)
        #expect(viewport.lighting.usesFileLights == true)

        // ShellRootView remount: applySession → syncHostCanvasFromStored.
        viewport.applySession(from: settings)
        #expect(dimStudio == true)
        #expect(viewport.lighting.usesFileLights == true)
        #expect(exposureEV == 0)

        viewport.applyConvertedLighting(dimStudioForFileLights: true, resetExposureAndYaw: false)
        #expect(dimStudio == true)
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
