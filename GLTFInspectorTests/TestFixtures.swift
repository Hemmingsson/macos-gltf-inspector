import Foundation

/// Single source of truth for on-disk models under `TestModels/`.
///
/// Tests read straight from the source tree via `#filePath` — fixtures are **not** bundled
/// resources. Regenerators: `python3 scripts/testdata/make_fixtures.py` and
/// `python3 scripts/testdata/cube/make_cube.py`. Khronos samples: `./scripts/fetch-test-models.sh`.
enum TestFixtures {
    /// Repo root = two levels up from this file (`GLTFInspectorTests/TestFixtures.swift`).
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GLTFInspectorTests/
        .deletingLastPathComponent() // repo root

    static func url(_ relativeToRepo: String) -> URL {
        repoRoot.appendingPathComponent(relativeToRepo)
    }

    static func fixture(_ relative: String) -> URL {
        url("TestModels/Fixture Models/\(relative)")
    }

    static let tiny = fixture("tiny.glb")
    static let cube = fixture("cube/cube.gltf")
    static let boxAnimated = fixture("BoxAnimated/BoxAnimated.glb")
    static let invalid = fixture("invalid/unresolved-mesh.gltf")
    static let offcenter = fixture("offcenter/cube-offset.gltf")
    static let multiScene = fixture("multiscene/two-scenes.gltf")
    static let lights = fixture("lights/punctual-lights.gltf")
    static let cameras = fixture("cameras/persp-and-ortho.gltf")
    static let missingChannels = fixture("missing-channels/basecolor-only.gltf")
    static let rigged = fixture("rigged/two-joint-skin.gltf")
    static let morph = fixture("morph/morph-triangle.gltf")
    static let animatedMorphCube = url("TestModels/Khronos samples/AnimatedMorphCube/AnimatedMorphCube.glb")
    static let corrupt = fixture("corrupt/truncated.glb")

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

enum TestModels {
    static let khronosDirectory = TestFixtures.url("TestModels/Khronos samples")
}
