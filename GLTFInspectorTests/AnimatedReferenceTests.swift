import CoreGraphics
import Foundation
import GLTFKit2
import Testing
@testable import Renderer

/// Khronos stills of animated poses. Rest PNGs stay in `TestModels/References/`; these live in
/// `Animated/` and were rendered by the pinned Sample Renderer at a fixed time (`t > 0`).
@MainActor
@Suite(.serialized)
struct AnimatedReferenceTests {
    private static let captureCommand = "./scripts/capture-khronos-animated-references.mjs"

    @Test func twoTimesEvaluateDifferentPoses() throws {
        let manifest = try AnimatedReferenceManifest.load()
        let times = manifest.entries
            .filter { $0.sample == "AnimatedMorphCube" }
            .compactMap(\.animation?.time)
        #expect(Set(times) == [0.5, 1.0])

        let model = TestModels.khronosDirectory
            .appendingPathComponent("AnimatedMorphCube/AnimatedMorphCube.glb")
        let asset = try Self.loadAsset(model)
        let clips = try AnimationClipLoader.loadClips(from: asset)
        let half = AnimationPose(clips: [clips[0]], at: 0.5)
        let one = AnimationPose(clips: [clips[0]], at: 1)
        // The clip targets the node, and the node has no weights array, so Khronos (and the
        // loader) write the mesh's weights. Those two times are not the rest pose.
        #expect(half != one)
        #expect(half.meshWeights[0] != one.meshWeights[0])
        #expect(half.nodeWeights.isEmpty)
        #expect(half != AnimationPose())
        #expect(one != AnimationPose())
    }

    @Test func skinnedPoseAtFixedTimeIsNotRest() throws {
        let manifest = try AnimatedReferenceManifest.load()
        let entry = try #require(manifest.entries.first { $0.sample == "SimpleSkin" })
        let animation = try #require(entry.animation)
        #expect(animation.time > 0)

        let asset = try Self.loadAsset(entry.modelURL)
        let clips = try AnimationClipLoader.loadClips(from: asset)
        let pose = AnimationPose(clips: [clips[animation.index]], at: Float(animation.time))
        #expect(pose.nodeOverrides[2]?.rotation != nil)
        #expect(pose != AnimationPose())
    }

    @Test func twoTimesRenderDifferentFrames() async throws {
        let manifest = try AnimatedReferenceManifest.load()
        let entries = manifest.entries.filter { $0.sample == "AnimatedMorphCube" }
        try #require(entries.count == 2)
        let renderer = try await Self.renderer(manifest)
        let first = try PixelDiff.raster(from: try await Self.image(entries[0], manifest: manifest, renderer: renderer))
        let second = try PixelDiff.raster(from: try await Self.image(entries[1], manifest: manifest, renderer: renderer))
        let (metrics, verdict) = try PixelDiff.compare(first, to: second, tolerance: manifest.tolerance)
        #expect(!verdict.isMatch, "t=0.5 and t=1.0 rendered one pose: \(metrics.summary())")
    }

    @Test func anEntryWithoutAnimationRendersTheRestReference() async throws {
        let animated = try AnimatedReferenceManifest.load()
        var entry = try #require(animated.entries.first { $0.sample == "AnimatedMorphCube" })
        entry.animation = nil
        let renderer = try await Self.renderer(animated)
        let actual = try PixelDiff.raster(from: try await Self.image(entry, manifest: animated, renderer: renderer))
        let expected = try PixelDiff.raster(contentsOf: PixelDiffPaths.reference("AnimatedMorphCube"))
        let (metrics, verdict) = try PixelDiff.compare(actual, to: expected, tolerance: animated.tolerance)
        if case .differs(let reasons) = verdict {
            let report = try PixelDiffReport.write(name: "animated-rest-unchanged", actual: actual, expected: expected)
            Issue.record(Comment(rawValue: """
                A manifest entry with no animation time changed the rest still.
                \(reasons.joined(separator: "; "))
                \(metrics.summary())
                \(report)
                """))
        }
        #expect(verdict.isMatch)
    }

    @Test func posedFramesMatchKhronosReferences() async throws {
        let manifest = try AnimatedReferenceManifest.load()
        let renderer = try await Self.renderer(manifest)
        var failures: [String] = []
        for entry in manifest.entries {
            guard entry.animation != nil else {
                failures.append(entry.name)
                Issue.record(Comment(rawValue: "\(entry.name) has no animation time. Animated/ is posed frames only."))
                continue
            }
            let reference = entry.referenceURL
            guard FileManager.default.fileExists(atPath: reference.path) else {
                failures.append(entry.name)
                Issue.record(Comment(rawValue: """
                    \(entry.name): Khronos reference missing at \(reference.path).
                    Produce it with \(Self.captureCommand)
                    """))
                continue
            }
            let expected = try PixelDiff.raster(contentsOf: reference)
            let actual = try PixelDiff.raster(from: try await Self.image(entry, manifest: manifest, renderer: renderer))
            let (metrics, verdict) = try PixelDiff.compare(actual, to: expected, tolerance: manifest.tolerance)
            print("animated \(entry.name): \(metrics.summary())")
            if case .differs(let reasons) = verdict {
                failures.append(entry.name)
                let report = try PixelDiffReport.write(name: "animated-\(entry.name)", actual: actual, expected: expected)
                Issue.record(Comment(rawValue: """
                    \(entry.name) does not match its Khronos animated reference.
                    \(reasons.joined(separator: "\n"))
                    \(metrics.summary())
                    \(report)
                    """))
            }
        }
        #expect(failures.isEmpty, "\(failures.count) animated poses differ: \(failures.joined(separator: ", "))")
    }

    @Test func aMissingAnimatedReferenceFails() {
        let url = AnimatedReferenceManifest.directory.appendingPathComponent("not-a-real-animated-pose.png")
        #expect(throws: AnimatedReferenceFailure.self) {
            try AnimatedReferenceManifest.requireReference(at: url)
        }
    }

    private static func renderer(_ manifest: AnimatedReferenceManifest) async throws -> MetalRenderer {
        let renderer = try MetalRenderer()
        _ = try PixelDiffMetal.renderLook(manifest.look)
        return renderer
    }

    private static func image(
        _ entry: AnimatedReferenceManifest.Entry,
        manifest: AnimatedReferenceManifest,
        renderer: MetalRenderer
    ) async throws -> CGImage {
        guard FileManager.default.fileExists(atPath: entry.modelURL.path) else {
            throw AnimatedReferenceFailure.missingModel(entry.modelURL)
        }
        guard let camera = entry.camera, camera.isFinite else {
            throw AnimatedReferenceFailure.missingCamera(entry.name)
        }
        let options = ViewOptions(look: try PixelDiffMetal.renderLook(manifest.look))
        try await renderer.load(url: entry.modelURL)
        guard let scene = renderer.scene else { throw AnimatedReferenceFailure.missingModel(entry.modelURL) }
        let pose = try animationPose(entry, scene: scene)
        let size = manifest.look.canvasSize
        return try renderer.image(options, pose: MetalCameraPose(camera), width: size, height: size, animationPose: pose)
    }

    private static func animationPose(
        _ entry: AnimatedReferenceManifest.Entry,
        scene: MetalScene
    ) throws -> AnimationPose? {
        guard let animation = entry.animation else { return nil }
        let clips = try AnimationClipLoader.loadClips(from: scene.asset)
        guard clips.indices.contains(animation.index) else {
            throw AnimatedReferenceFailure.badClip(entry.name, animation.index, clips.count)
        }
        let matrixNodes = AnimationClipLoader.matrixAuthoredNodeIndices(sourceURL: entry.modelURL)
        return AnimationPose(
            clips: [clips[animation.index]],
            at: Float(animation.time),
            matrixAuthoredNodes: matrixNodes
        )
    }

    private static func loadAsset(_ url: URL) throws -> GLTFAsset {
        GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"
        let options: [GLTFAssetLoadingOption: Any] = [.assetDirectoryURLKey: url.deletingLastPathComponent()]
        return try GLTFAsset(url: url, options: options)
    }
}

enum AnimatedReferenceFailure: Error, CustomStringConvertible, Equatable {
    case missingPNG(URL)
    case missingModel(URL)
    case missingCamera(String)
    case badClip(String, Int, Int)

    var description: String {
        switch self {
        case .missingPNG(let url):
            "Khronos animated reference missing at \(url.path). Produce with ./scripts/capture-khronos-animated-references.mjs"
        case .missingModel(let url):
            "Model missing at \(url.path). Fetch with ./scripts/fetch-test-models.sh"
        case .missingCamera(let name):
            "\(name) has no recorded camera. Capture with ./scripts/capture-khronos-animated-references.mjs"
        case .badClip(let name, let index, let count):
            "\(name) animation index \(index) is outside \(count) clips"
        }
    }
}

struct AnimatedReferenceManifest: Codable, Sendable {
    static let currentVersion = 1
    static let directory = TestFixtures.url("TestModels/References/Animated")
    static let manifestURL = directory.appendingPathComponent("manifest.json")

    var version: Int
    var samples: PixelDiffManifest.SampleSource
    var look: PixelDiffManifest.Look
    var tolerance: PixelDiff.Tolerance
    var entries: [Entry]

    struct Entry: Codable, Sendable {
        var name: String
        /// Folder under `TestModels/Khronos samples`. Differs from `name` when one file has several times.
        var sample: String
        var source: String
        var files: [String]
        /// Nil renders the rest pose. Posed goldens always set this, with `time > 0`.
        var animation: Animation?
        var camera: PixelDiffManifest.Camera?

        struct Animation: Codable, Sendable, Equatable {
            var index: Int
            var time: Double
        }

        var modelURL: URL {
            TestModels.khronosDirectory
                .appendingPathComponent(sample, isDirectory: true)
                .appendingPathComponent(files.first ?? "\(sample).glb")
        }

        var referenceURL: URL {
            AnimatedReferenceManifest.directory.appendingPathComponent("\(name).png")
        }
    }

    static func load() throws -> Self {
        let url = manifestURL
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard manifest.version == currentVersion else {
            throw PixelDiffManifest.LoadFailure.wrongVersion(found: manifest.version, expected: currentVersion)
        }
        return manifest
    }

    static func requireReference(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AnimatedReferenceFailure.missingPNG(url)
        }
    }
}
