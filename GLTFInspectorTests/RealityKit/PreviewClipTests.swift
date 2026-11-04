import CoreGraphics
import Foundation
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

struct PreviewClipTests {
    @MainActor
    @Test func boxAnimatedExposesUsableClips() async throws {
        let url = TestFixtures.boxAnimated
        #expect(FileManager.default.fileExists(atPath: url.path))

        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        let usable = PreviewClip.usable(on: model.entity, document: model.document)

        #expect(!usable.isEmpty)
        #expect(usable.count == model.document.animations.filter { $0.duration > 0 }.count)
        #expect(usable.allSatisfy { $0.duration > 0 })
    }

    /// PreviewScene poses clip 0 paused; the host player must replace that controller, not blend.
    @MainActor
    @Test func hostPlayReplacesPausedPoseController() async throws {
        let url = try writeTempTwoClipGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        let clips = PreviewClip.usable(on: model.entity, document: model.document)
        let first = try #require(clips.first)
        let second = try #require(clips.dropFirst().first)
        #expect(first.id != second.id)

        let pose = model.entity.playAnimation(first.resource.repeat(), startsPaused: true)
        pose.time = first.duration
        #expect(!pose.isComplete)
        #expect(pose.isPaused)

        let player = RealityClipPlayer(model: model)
        #expect(player.start(clipID: second.id, playing: false))
        player.time = second.duration
        #expect(pose.isComplete)

        let root = try #require(namedEntity("Root", in: model.entity))
        _ = try await StillRenderer.render(
            root: model.entity,
            cameraPose: StillCameraPose(
                position: [0, 0, 5],
                orientation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                projection: .perspective(fieldOfViewDegrees: 45, near: 0.1, far: 100)
            ),
            width: 16,
            height: 16,
            background: CGColor(gray: 0.5, alpha: 1)
        )
        let p = root.position(relativeTo: nil)
        #expect(abs(p.x) < 0.05, "expected clip B end (0,1,0), got \(p)")
        #expect(abs(p.y - 1) < 0.05, "expected clip B end (0,1,0), got \(p)")
        #expect(abs(p.z) < 0.05, "expected clip B end (0,1,0), got \(p)")
    }
}
