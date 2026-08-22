import Foundation
import RealityKit
import Testing
@testable import GLTFInspector

@MainActor
struct EngineSceneModelTests {
    @Test func cubeIsPlain() async throws {
        try requireFixture(TestFixtures.cube)
        let loaded = try await EntityLoader.load(from: TestFixtures.cube, includeAnimations: true)
        let model = EngineSceneModel(loaded: loaded, fileName: TestFixtures.cube.lastPathComponent)
        let availability = availability(for: model, debugModes: loaded.debugModes)

        #expect(!availability.hasAnimations)
        #expect(!availability.hasLights)
        #expect(!availability.hasCameras)
        #expect(!availability.hasSkin)
        #expect(!availability.hasMorphs)
        #expect(!availability.isMultiScene)
        #expect(model.scenes.count == 1)
        #expect(model.animations.isEmpty)
        #expect(model.convertProblems.isEmpty)
        #expect(!model.nodeTree.isEmpty)
        #expect(model.pipelineReport.entries.contains { $0.kind == .lighting })

        let sections = OutlinerSection.sections(of: model)
        #expect(!sections.contains { $0.title == "Scene" })
    }

    @Test func tinyIsPlain() async throws {
        try requireFixture(TestFixtures.tiny)
        let loaded = try await EntityLoader.load(from: TestFixtures.tiny, includeAnimations: true)
        let model = EngineSceneModel(loaded: loaded, fileName: "tiny.glb")
        let availability = availability(for: model, debugModes: loaded.debugModes)

        #expect(!availability.hasAnimations)
        #expect(!availability.hasLights)
        #expect(!availability.hasCameras)
        #expect(!availability.hasSkin)
        #expect(!availability.hasMorphs)
        #expect(!availability.isMultiScene)
        #expect(model.animations.isEmpty)
        #expect(model.convertProblems.isEmpty)
    }

    @Test func boxAnimatedHasClipsAndPlayback() async throws {
        try requireFixture(TestFixtures.boxAnimated)
        let loaded = try await EntityLoader.load(from: TestFixtures.boxAnimated, includeAnimations: true)
        let model = EngineSceneModel(loaded: loaded, fileName: "BoxAnimated.glb")
        let availability = availability(for: model, debugModes: loaded.debugModes)
        let playback = EngineAnimationPlaybackController(loaded: loaded)

        #expect(availability.hasAnimations)
        #expect(!model.animations.isEmpty)
        #expect(!playback.clips.isEmpty)
        #expect(playback.activeClip != nil)
        #expect(playback.duration > 0)

        playback.play()
        #expect(playback.isPlaying)
        playback.pause()
        #expect(!playback.isPlaying)
        playback.seek(0.1)
        #expect(abs(playback.time - 0.1) < 0.001)
    }

    @Test func lightsFixtureReportsLights() async throws {
        try requireFixture(TestFixtures.lights)
        let loaded = try await EntityLoader.load(from: TestFixtures.lights, includeAnimations: false)
        let model = EngineSceneModel(loaded: loaded, fileName: "punctual-lights.gltf")
        let availability = availability(for: model, debugModes: loaded.debugModes)

        #expect(availability.hasLights)
        #expect(model.lights.count >= 3)
        #expect(Set(model.lights.map(\.kind)).isSuperset(of: [.directional, .point, .spot]))
    }

    @Test func camerasFixtureReportsCamerasWithDegrees() async throws {
        try requireFixture(TestFixtures.cameras)
        let loaded = try await EntityLoader.load(from: TestFixtures.cameras, includeAnimations: false)
        let model = EngineSceneModel(loaded: loaded, fileName: "persp-and-ortho.gltf")
        let availability = availability(for: model, debugModes: loaded.debugModes)

        #expect(availability.hasCameras)
        #expect(model.cameras.count >= 2)
        let perspective = try #require(model.cameras.first { $0.projection == .perspective })
        let fov = try #require(perspective.fieldOfViewDegrees)
        // yfov is authored in radians; seam exposes degrees (typical ~40–90°).
        #expect(fov > 5 && fov < 180)
        #expect(model.cameras.contains { $0.projection == .orthographic })
    }

    @Test func multiSceneIsMultiScene() async throws {
        try requireFixture(TestFixtures.multiScene)
        let loaded = try await EntityLoader.load(from: TestFixtures.multiScene, includeAnimations: false)
        let model = EngineSceneModel(loaded: loaded, fileName: "two-scenes.gltf")
        let availability = availability(for: model, debugModes: loaded.debugModes)

        #expect(availability.isMultiScene)
        #expect(model.scenes.count >= 2)
        #expect(model.defaultSceneID != nil)
        #expect(OutlinerSection.sections(of: model).contains { $0.title == "Scene" })
    }

    @Test func riggedHasSkin() async throws {
        try requireFixture(TestFixtures.rigged)
        let loaded = try await EntityLoader.load(from: TestFixtures.rigged, includeAnimations: false)
        let model = EngineSceneModel(loaded: loaded, fileName: "two-joint-skin.gltf")
        let availability = availability(for: model, debugModes: loaded.debugModes)

        #expect(availability.hasSkin)
        #expect(!model.skins.isEmpty)
        #expect(model.skins[0].jointCount >= 2)
        #expect(OutlinerSection.sections(of: model).contains { $0.title == "Skins" })
    }

    @Test func morphHasMorphs() async throws {
        try requireFixture(TestFixtures.morph)
        let loaded = try await EntityLoader.load(from: TestFixtures.morph, includeAnimations: false)
        let model = EngineSceneModel(loaded: loaded, fileName: "morph-triangle.gltf")
        let availability = availability(for: model, debugModes: loaded.debugModes)

        #expect(availability.hasMorphs)
        #expect(!model.morphs.isEmpty)
        #expect(!model.morphs[0].targetNames.isEmpty)
    }

    @Test func missingChannelsShortensDebugMenu() async throws {
        try requireFixture(TestFixtures.missingChannels)
        let loaded = try await EntityLoader.load(from: TestFixtures.missingChannels, includeAnimations: false)
        let model = EngineSceneModel(loaded: loaded, fileName: "basecolor-only.gltf")
        let availability = availability(for: model, debugModes: loaded.debugModes)

        let full = DerivedAvailability(
            model: model,
            channels: DebugChannel.allCases
        )
        #expect(availability.availableDebugChannels.count < full.availableDebugChannels.count)
        #expect(availability.availableDebugChannels.contains(.shaded))
        #expect(availability.availableDebugChannels.contains(.wireframe))

        if let material = model.materials.first {
            #expect(material.maps.contains(.baseColor) || material.maps.isEmpty || !material.maps.contains(.occlusion))
            #expect(!material.maps.contains(.emissive) || material.maps == [.baseColor])
        }
    }

    @Test func invalidSurfacesValidationIssues() async throws {
        try requireFixture(TestFixtures.invalid)
        try requireFixture(TestFixtures.cube)
        // `.invalid` fails GLTFKit2 convert; map validation onto a loadable document snapshot.
        let loaded = try await EntityLoader.load(from: TestFixtures.cube, includeAnimations: false)
        let report = try await GLTFValidator.validate(fileAt: TestFixtures.invalid)
        let pending = EngineSceneModel(loaded: loaded, fileName: "unresolved-mesh.gltf", validation: nil)
        #expect(pending.validation.status == .pending)
        #expect(!pending.validation.isClean)
        #expect(pending.validation.issues.isEmpty)

        let model = EngineSceneModel(
            loaded: loaded,
            fileName: "unresolved-mesh.gltf",
            validation: .success(report)
        )
        #expect(!model.validation.issues.isEmpty)
        #expect(model.validation.errorCount >= 1)
        #expect(model.validation.status == .ready)

        let failed = pending.replacingValidation(.failed("Validation unavailable: test"))
        #expect(failed.validation.status == .unavailable)
        #expect(!failed.validation.isClean)
        #expect(failed.validation.issues.contains { $0.severity == .warning && $0.message.contains("unavailable") })

        let skipped = pending.replacingValidation(.skipped("Validation skipped: test"))
        #expect(skipped.validation.status == .unavailable)
        #expect(skipped.validation.issues.contains { $0.severity == .warning && $0.message.contains("skipped") })
    }

    @Test func offcenterAuthoredOriginIsNonZero() async throws {
        try requireFixture(TestFixtures.offcenter)
        let loaded = try await EntityLoader.load(from: TestFixtures.offcenter, includeAnimations: false)
        let model = EngineSceneModel(loaded: loaded, fileName: "cube-offset.gltf")

        #expect(model.dimensions.authoredOrigin != .zero)
        #expect(abs(model.dimensions.authoredOrigin.x) > 0.1)
    }

    @Test func materialMapsOmitAbsentChannelsOnMissingChannels() async throws {
        try requireFixture(TestFixtures.missingChannels)
        let loaded = try await EntityLoader.load(from: TestFixtures.missingChannels, includeAnimations: false)
        let model = EngineSceneModel(loaded: loaded, fileName: "basecolor-only.gltf")
        let material = try #require(model.materials.first)
        #expect(!material.maps.contains(.normal))
        #expect(!material.maps.contains(.occlusion))
        #expect(!material.maps.contains(.emissive))
        #expect(!material.maps.contains(.clearcoat))
    }
}

private func availability(
    for model: EngineSceneModel,
    debugModes: [PreviewDebugMode]
) -> DerivedAvailability<EngineSceneModel> {
    DerivedAvailability(model: model, channels: EngineSceneModel.mapDebugChannels(debugModes))
}

private func requireFixture(_ url: URL) throws {
    guard TestFixtures.exists(url) else {
        throw FixtureMissing(path: url.path)
    }
}

private struct FixtureMissing: Error, CustomStringConvertible {
    var path: String
    var description: String { "Missing test fixture at \(path)" }
}
