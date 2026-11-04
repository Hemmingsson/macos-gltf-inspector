import CoreGraphics
import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import PreviewUI
import SwiftUI
import Testing

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

    @Test func lightingMapsDegreesToRadians() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        let viewport = EngineViewportController(sidebar: sidebar)

        viewport.setLighting(LightingSettings(exposure: 1.5, environmentRotationDegrees: 90))

        #expect(viewport.lighting.exposure == 1.5)
        #expect(abs(viewport.lighting.environmentRotationDegrees - 90) < 0.0001)
        #expect(abs(viewport.previewSession.environmentYaw - Float.pi / 2) < 0.0001)
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
        #expect(sidebar.selectedCameraNodeIndex == 0)

        viewport.setFileCamera(nil)
        #expect(sidebar.selectedCameraNodeIndex == nil)

        viewport.setFileCamera(NodeID(kind: .camera, index: 0))
        viewport.fit()
        #expect(sidebar.selectedCameraNodeIndex == nil)
    }

    /// Fit / reset / presets / export land on whatever canvas registered its commands.
    @Test func commandsForwardToTheRegisteredCanvas() async throws {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        var calls: [String] = []
        let image = try #require(
            CGContext(
                data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        )
        var saved: [CGImage] = []
        let viewport = EngineViewportController(
            sidebar: sidebar,
            saveScreenshot: { saved.append($0) }
        )

        // Nothing mounted yet: every command is a harmless no-op.
        viewport.fit()
        viewport.reset()
        viewport.applyCameraPreset(.top)
        await viewport.exportScreenshot()
        #expect(saved.isEmpty)

        viewport.commands = FocusedPreviewCommands(
            fit: { calls.append("fit") },
            reset: { calls.append("reset") },
            applyCameraPreset: { calls.append("preset \($0.rawValue)") },
            zoom: { calls.append("zoom \($0)") },
            screenshot: {
                calls.append("screenshot")
                return image
            }
        )
        viewport.fit()
        viewport.applyCameraPreset(.left)
        viewport.zoom(by: 0.5)
        viewport.reset()
        await viewport.exportScreenshot()

        #expect(calls == ["fit", "preset left", "zoom 0.5", "reset", "screenshot"])
        #expect(saved.count == 1)
        #expect(saved.first?.width == 4)
        #expect(viewport.activeCameraPreset == nil)
    }

    /// A capture failure (the page not ready, say).
    private struct NoCameraPose: Error {}

    @Test func failedScreenshotSavesNothing() async {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        var saved = 0
        let viewport = EngineViewportController(sidebar: sidebar, saveScreenshot: { _ in saved += 1 })
        viewport.commands = FocusedPreviewCommands(
            fit: {}, reset: {}, applyCameraPreset: { _ in }, zoom: { _ in },
            screenshot: { throw NoCameraPose() }
        )
        await viewport.exportScreenshot()
        #expect(saved == 0)
    }

    @Test func settingsOverlayTracksDefaultsInGetters() throws {
        let suite = "engine.viewport.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let defaultsStore = AppDefaultsStore(defaults: defaults)
        let settings = EngineSettingsStore(defaultsStore: defaultsStore)
        let session = PreviewSession(settings: settings)
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        let viewport = EngineViewportController(sidebar: sidebar, previewSession: session)

        // The canvas reads the session; the pills read the viewport. Both follow the default.
        defaultsStore.set(.dark, for: .backdrop)
        #expect(session.backdrop == .dark)
        #expect(viewport.backdrop == .dark)

        defaultsStore.set(.white, for: .backdrop)
        #expect(session.backdrop == .white)

        viewport.setBackdrop(.window)
        defaultsStore.set(.dark, for: .backdrop)
        #expect(session.backdrop == .window)
        #expect(viewport.backdrop == .window)

        settings.clearSession()
        #expect(session.backdrop == .dark)
    }

    @Test func hostSessionWriteThroughUpdatesBindings() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        let session = PreviewSession()
        session.viewModes = [.shaded, .wireframe]
        let viewport = EngineViewportController(sidebar: sidebar, previewSession: session)

        viewport.setBackdrop(.dark)
        viewport.setFloor(false)
        viewport.setAutoRotate(false)
        viewport.setCenter(false)
        viewport.setProjection(.orthographic)
        viewport.setViewMode(.wireframe)
        viewport.setLighting(
            LightingSettings(exposure: 0.5, environmentRotationDegrees: 45)
        )

        #expect(session.backdrop == .dark)
        #expect(session.showFloor == false)
        #expect(session.autoRotate == false)
        #expect(session.centerModel == false)
        #expect(session.orthographic == true)
        #expect(session.viewMode == .wireframe)
        #expect(session.exposureEV == 0.5)
        #expect(abs(session.environmentYaw - Float.pi / 4) < 0.0001)
        #expect(viewport.showsFloor == false)
        #expect(viewport.viewMode == .wireframe)

        viewport.setFieldOfViewDegrees(90)
        #expect(session.fieldOfViewDegrees == 90)
        #expect(viewport.fieldOfViewDegrees == 90)

        viewport.setFieldOfViewDegrees(5)
        #expect(session.fieldOfViewDegrees == RenderCamera.clampedFieldOfView(5))
        viewport.reset()
        #expect(session.fieldOfViewDegrees == RenderCamera.defaultFieldOfViewDegrees)
        #expect(session.exposureEV == 0)
    }

    /// Reset View is "back to this app's defaults", not a hard-coded Neutral IBL / tone curve.
    @Test func resetRestoresAppDefaultEnvironmentAndToneMapping() throws {
        let suite = "engine.viewport.reset-look.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let defaultsStore = AppDefaultsStore(defaults: defaults)
        let settings = EngineSettingsStore(defaultsStore: defaultsStore)
        let session = PreviewSession(settings: settings)
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        let viewport = EngineViewportController(sidebar: sidebar, previewSession: session)

        settings.appDefaults.set(StudioEnvironment.field.rawValue, for: .environmentCatalog)
        settings.appDefaults.set(ToneMapping.acesHill.khronosName, for: .toneMapping)

        viewport.setLighting(
            LightingSettings(
                exposure: 1,
                environmentRotationDegrees: 45,
                environment: .colorfulStudio,
                toneMapping: .linear
            )
        )
        #expect(viewport.lighting.environment == .colorfulStudio)
        #expect(viewport.lighting.toneMapping == .linear)

        viewport.reset()

        #expect(viewport.lighting.environment == .field)
        #expect(viewport.lighting.toneMapping == .acesHill)
        #expect(viewport.lighting.exposure == 0)
        #expect(abs(viewport.lighting.environmentRotationDegrees) < 0.0001)
    }

    /// A new document starts from the app defaults with exposure and yaw at zero.
    @Test func applySessionResetsExposureAndYaw() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        let session = PreviewSession()
        let viewport = EngineViewportController(sidebar: sidebar, previewSession: session)

        viewport.setLighting(LightingSettings(exposure: 1, environmentRotationDegrees: 45))
        viewport.applySession()

        #expect(session.exposureEV == 0)
        #expect(session.environmentYaw == 0)
    }
}
