import Foundation

/// Single source of truth for on-disk test fixtures under `scripts/testdata/` (+ `scripts/tiny.glb`).
///
/// Tests read straight from the source tree via `#filePath` — fixtures are **not** bundled
/// resources, so dropping a new file under `scripts/testdata/` makes it available to tests *and*
/// to real-window / UI work with no `project.yml` change. Regenerate the adaptive-UI set with
/// `python3 scripts/testdata/make_fixtures.py`; catalogue in `scripts/testdata/README.md`.
enum TestFixtures {
    /// Repo root = two levels up from this file (`GLTFInspectorTests/TestFixtures.swift`).
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GLTFInspectorTests/
        .deletingLastPathComponent() // repo root

    /// A path relative to the repo root.
    static func url(_ relativeToRepo: String) -> URL {
        repoRoot.appendingPathComponent(relativeToRepo)
    }

    /// A path relative to `scripts/testdata/`.
    static func testdata(_ relative: String) -> URL {
        url("scripts/testdata/\(relative)")
    }

    // MARK: - Canonical fixtures (committed, hand-authored)

    /// Flat single-triangle GLB — the smallest loadable model. Plain static mesh.
    static let tiny = url("scripts/tiny.glb")
    /// Textured unit cube, multi-file `.gltf` sidecar (gltf + bin + png). Plain static mesh, loads
    /// through the skip-packing sidecar path. Regenerate: `scripts/testdata/cube/make_cube.py`.
    static let cube = testdata("cube/cube.gltf")
    /// Animated GLB (Khronos BoxAnimated). Playback bar + Animations section.
    static let boxAnimated = testdata("BoxAnimated/BoxAnimated.glb")
    /// Semantically invalid but parseable glTF (unresolved mesh ref). Validator reports errors.
    static let invalid = testdata("invalid/unresolved-mesh.gltf")
    /// Off-center authored origin. Origin gizmo when Center is off.
    static let offcenter = testdata("offcenter/cube-offset.gltf")

    // MARK: - Adaptive-UI matrix (make_fixtures.py — DESIGN.md "show only what the model has")

    /// Two scenes → Scene switcher appears.
    static let multiScene = testdata("multiscene/two-scenes.gltf")
    /// KHR_lights_punctual point + directional + spot → Lights section.
    static let lights = testdata("lights/punctual-lights.gltf")
    /// One perspective + one orthographic camera → Cameras section.
    static let cameras = testdata("cameras/persp-and-ortho.gltf")
    /// baseColor factor only, no maps → view-mode menu shortens, material chips omit absent maps.
    static let missingChannels = testdata("missing-channels/basecolor-only.gltf")
    /// Two-joint skin → skeleton controls.
    static let rigged = testdata("rigged/two-joint-skin.gltf")
    /// One named morph target → morph controls.
    static let morph = testdata("morph/morph-triangle.gltf")
    /// Byte-corrupt GLB (valid magic, lying chunk lengths, truncated body) — the hard-failure path,
    /// distinct from `invalid` (which parses). Loads must surface `.failed`, never a spinner.
    static let corrupt = testdata("corrupt/truncated.glb")

    /// True when the fixture exists on disk (guards against a missing regenerate step).
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
