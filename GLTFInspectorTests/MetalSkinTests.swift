import Foundation
import Metal
import simd
import Testing
@testable import Renderer

/// GPU skin against a hand-written linear blend. Expectations are not read back from the loader.
@Suite struct MetalSkinTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    private func renderer(_ file: SkinGLB) async throws -> MetalRenderer {
        let url = try file.write()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        return try MetalRenderer(sharing: scene)
    }

    private func renderer(_ url: URL) async throws -> MetalRenderer {
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        return try MetalRenderer(sharing: scene)
    }

    @Test func skinVertexMatchesTheShaderLayout() {
        #expect(MemoryLayout<MetalSkinVertex>.stride == 48)
        #expect(MemoryLayout<MetalSkinVertex>.offset(of: \.joints1) == 8)
        #expect(MemoryLayout<MetalSkinVertex>.offset(of: \.weights0) == 16)
        #expect(MemoryLayout<MetalSkinVertex>.offset(of: \.weights1) == 32)
        #expect(MemoryLayout<GPUJointPair>.stride == 128)
    }

    /// Identity skin, so the old CPU bake and the Khronos blend are the same triangle.
    @Test func riggedBoundsAndRestPositionsMatchTheBindTriangle() async throws {
        let scene = try await MetalSceneLoader.load(url: TestFixtures.rigged, device: device())
        expectNear(scene.boundsMin, [0, 0, 0])
        expectNear(scene.boundsMax, [1, 1, 0])
        let draw = try #require(scene.draws.first)
        #expect(draw.skinBuffer != nil)
        let stored = vertices(draw)
        expectNear(stored[0].position.xyz, [0, 0, 0])
        expectNear(stored[1].position.xyz, [1, 0, 0])
        expectNear(stored[2].position.xyz, [0, 1, 0])
        let captured = try await renderer(TestFixtures.rigged).captureMorphedVertices(drawIndex: 0, pose: nil)
        expectNear(captured[0].position.xyz, [0, 0, 0])
        expectNear(captured[1].position.xyz, [1, 0, 0])
        expectNear(captured[2].position.xyz, [0, 1, 0])
    }

    @Test func rigidDrawsStayUnskinned() async throws {
        let scene = try await MetalSceneLoader.load(url: TestFixtures.cube, device: device())
        #expect(scene.draws.allSatisfy { $0.skinBuffer == nil && $0.skinIndex == nil })
    }

    /// Weight 1 agrees with the old bake. Weight 0.5 is not renormalized. An unweighted vertex stays.
    @Test func posingAJointMovesOnlyWeightedVertices() async throws {
        let restJoint = matrix_identity_float4x4
        let file = SkinGLB(vertices: [
            SkinGLB.Vertex(position: [1, 0, 0], joints0: SIMD4(0, 1, 0, 0), weights0: SIMD4(0.25, 0.75, 0, 0)),
            SkinGLB.Vertex(position: [0, 0, 0], weights0: SIMD4(0.5, 0, 0, 0)),
            SkinGLB.Vertex(position: [2, 0, 0], weights0: .zero),
        ], jointMatrices: [restJoint, restJoint], inverseBinds: [restJoint, restJoint], poseableJoints: true)
        let gpu = try await renderer(file)
        let rest = try gpu.captureMorphedVertices(drawIndex: 0, pose: nil)
        expectNear(rest[0].position.xyz, [1, 0, 0])
        expectNear(rest[1].position.xyz, [0, 0, 0])
        expectNear(rest[2].position.xyz, [2, 0, 0])

        let pose = AnimationPose(nodeOverrides: [
            1: NodePoseOverride(translation: SIMD3(0, 2, 0)),
            2: NodePoseOverride(translation: SIMD3(0, 4, 0)),
        ])
        let moved = try gpu.captureMorphedVertices(drawIndex: 0, pose: pose)
        let joint0 = translation(SIMD3(0, 2, 0))
        let joint1 = translation(SIMD3(0, 4, 0))
        expectNear(moved[0].position.xyz, blend([1, 0, 0], [(joint0, 0.25), (joint1, 0.75)]))
        // 0.5 * (0, 2, 0), not the renormalized (0, 2, 0).
        expectNear(moved[1].position.xyz, [0, 1, 0])
        expectNear(moved[2].position.xyz, [2, 0, 0])
        #expect(simd_distance(moved[1].position.xyz, SIMD3(0, 2, 0)) > 0.5)
    }

    /// Unit weight and a non-identity joint: GPU matches `world * IBM` within 1e-5 (the old bake too).
    @Test func unitWeightMatchesTheLinearBlend() async throws {
        let joint = translation(SIMD3(0, 2, 0))
        let file = SkinGLB(
            vertices: [SkinGLB.Vertex(position: [1, 0, 0], normal: [0, 1, 0])],
            jointMatrices: [joint],
            inverseBinds: [matrix_identity_float4x4]
        )
        let captured = try await renderer(file).captureMorphedVertices(drawIndex: 0, pose: nil)
        expectNear(captured[0].position.xyz, blend([1, 0, 0], [(joint, 1)]))
        expectNear(captured[0].position.xyz, [1, 2, 0])
    }

    /// Blended normal matrices, not the inverse of the blended matrix. Nonuniform scales.
    @Test func normalsUseBlendedNormalMatrices() async throws {
        let joint0 = scale(SIMD3(2, 0.5, 1))
        let joint1 = scale(SIMD3(1, 2, 1))
        let file = SkinGLB(vertices: [
            SkinGLB.Vertex(position: [1, 1, 0], normal: [0, 1, 0], weights0: SIMD4(1, 0, 0, 0)),
            SkinGLB.Vertex(position: [1, 1, 0], normal: [1, 0, 0], joints0: SIMD4(0, 1, 0, 0), weights0: SIMD4(0.5, 0.5, 0, 0)),
        ], jointMatrices: [joint0, joint1], inverseBinds: [matrix_identity_float4x4, matrix_identity_float4x4])
        let captured = try await renderer(file).captureMorphedVertices(drawIndex: 0, pose: nil)
        expectNear(captured[0].position.xyz, [2, 0.5, 0])
        expectNear(captured[0].normal.xyz, [0, 2, 0])
        expectNear(captured[1].position.xyz, [1.5, 1.25, 0])
        expectNear(captured[1].normal.xyz, [0.75, 0, 0])
        #expect(abs(captured[1].normal.x - (1.0 / 1.5)) > 0.05)
    }

    /// One joint at 90° about Z, delta (0, 1, 0), weight 1. Captured vertex is R·(v+d) = (−1, 1, 0).
    @Test func morphIsAppliedBeforeSkin() async throws {
        let file = SkinGLB(
            vertices: [
                SkinGLB.Vertex(position: [1, 0, 0]),
                SkinGLB.Vertex(position: [0, 0, 0]),
                SkinGLB.Vertex(position: [0, 0, 1]),
            ],
            jointMatrices: [rotZ90],
            inverseBinds: [matrix_identity_float4x4],
            morphDelta: [[0, 1, 0], [0, 0, 0], [0, 0, 0]],
            morphWeight: 1
        )
        let gpu = try await renderer(file)
        let stored = vertices(try #require(gpu.scene?.draws.first))
        expectNear(stored[0].position.xyz, [1, 0, 0])
        let captured = try gpu.captureMorphedVertices(drawIndex: 0, pose: nil)
        expectNear(captured[0].position.xyz, [-1, 1, 0])
        #expect(simd_distance(captured[0].position.xyz, SIMD3(0, 2, 0)) > 0.5)
    }

    /// The mesh node's own transform is not applied to a skinned position.
    @Test func meshNodeTransformIsIgnored() async throws {
        let file = SkinGLB(
            vertices: [SkinGLB.Vertex(position: [1, 0, 0])],
            jointMatrices: [matrix_identity_float4x4],
            inverseBinds: [matrix_identity_float4x4],
            meshTranslation: SIMD3(4, 0, 0),
            poseableJoints: true
        )
        let gpu = try await renderer(file)
        let stored = vertices(try #require(gpu.scene?.draws.first))
        expectNear(stored[0].position.xyz, [1, 0, 0])
        let captured = try gpu.captureMorphedVertices(drawIndex: 0, pose: nil)
        expectNear(captured[0].position.xyz, [1, 0, 0])
        let posed = try gpu.captureMorphedVertices(
            drawIndex: 0,
            pose: AnimationPose(nodeOverrides: [0: NodePoseOverride(translation: SIMD3(9, 0, 0))])
        )
        expectNear(posed[0].position.xyz, [1, 0, 0])
    }

    @Test func joints1AndMoreThanThirtyTwoJoints() async throws {
        var joints = Array(repeating: matrix_identity_float4x4, count: 33)
        joints[32] = translation(SIMD3(0, 5, 0))
        var vertex = SkinGLB.Vertex(position: [1, 0, 0], weights0: .zero)
        vertex.joints0 = SIMD4(32, 0, 0, 0)
        vertex.weights0 = SIMD4(1, 0, 0, 0)
        let wide = SkinGLB(vertices: [vertex], jointMatrices: joints, inverseBinds: joints.map { _ in matrix_identity_float4x4 })
        let wideCaptured = try await renderer(wide).captureMorphedVertices(drawIndex: 0, pose: nil)
        expectNear(wideCaptured[0].position.xyz, [1, 5, 0])

        var joints1 = Array(repeating: matrix_identity_float4x4, count: 6)
        joints1[5] = translation(SIMD3(3, 0, 0))
        var second = SkinGLB.Vertex(position: [1, 0, 0], weights0: .zero, weights1: SIMD4(1, 0, 0, 0))
        second.joints1 = SIMD4(5, 0, 0, 0)
        let extra = SkinGLB(
            vertices: [second],
            jointMatrices: joints1,
            inverseBinds: joints1.map { _ in matrix_identity_float4x4 },
            includeJoints1: true
        )
        let gpu = try await renderer(extra)
        #expect(gpu.scene?.draws.first?.hasJoints1 == true)
        let captured = try gpu.captureMorphedVertices(drawIndex: 0, pose: nil)
        expectNear(captured[0].position.xyz, [4, 0, 0])
    }

    @Test func pickUsesThePosedSilhouette() async throws {
        let file = SkinGLB(vertices: [
            SkinGLB.Vertex(position: [-0.4, -0.4, 0], normal: [0, 0, 1]),
            SkinGLB.Vertex(position: [0.4, -0.4, 0], normal: [0, 0, 1]),
            SkinGLB.Vertex(position: [0, 0.4, 0], normal: [0, 0, 1]),
        ], jointMatrices: [matrix_identity_float4x4], inverseBinds: [matrix_identity_float4x4], poseableJoints: true)
        let gpu = try await renderer(file)
        let size = 128
        let pose = frontPose()
        let center = SIMD2(size / 2, size / 2)
        let posedPixel = pixel(of: SIMD3(2, 0, 0), size: size, pose: pose)
        #expect(try gpu.pick(ViewOptions(), pose: pose, width: size, height: size, point: center) == 0)
        #expect(try gpu.pick(ViewOptions(), pose: pose, width: size, height: size, point: posedPixel) == nil)
        let moved = AnimationPose(nodeOverrides: [1: NodePoseOverride(translation: SIMD3(2, 0, 0))])
        #expect(try gpu.pick(ViewOptions(), pose: pose, width: size, height: size, point: center, animationPose: moved) == nil)
        #expect(try gpu.pick(ViewOptions(), pose: pose, width: size, height: size, point: posedPixel, animationPose: moved) == 0)
    }

    private func frontPose() -> MetalCameraPose {
        MetalCameraPose(azimuth: 0, elevation: 0, distance: 5, target: .zero, yfov: .pi / 3, znear: 0.1, zfar: 100)
    }

    /// NDC +x is the right side of the pick target. The point sits on the camera's horizontal centre.
    private func pixel(of world: SIMD3<Float>, size: Int, pose: MetalCameraPose) -> SIMD2<Int> {
        let camera = MetalCamera(pose: pose, isOrthographic: false, aspect: 1)
        let clip = camera.openGLProjectionMatrix * camera.viewMatrix * SIMD4(world, 1)
        let x = Int((clip.x / clip.w + 1) * 0.5 * Float(size))
        return SIMD2(min(max(x, 0), size - 1), size / 2)
    }
}

private struct SkinGLB {
    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float> = SIMD3(0, 0, 1)
        var joints0: SIMD4<UInt16> = .zero
        var weights0: SIMD4<Float> = SIMD4(1, 0, 0, 0)
        var joints1: SIMD4<UInt16> = .zero
        var weights1: SIMD4<Float> = .zero
    }

    var vertices: [Vertex]
    var jointMatrices: [simd_float4x4]
    var inverseBinds: [simd_float4x4]
    var morphDelta: [SIMD3<Float>]? = nil
    var morphWeight: Float = 0
    var meshMatrix: simd_float4x4 = matrix_identity_float4x4
    var meshTranslation: SIMD3<Float>? = nil
    var includeJoints1 = false
    /// TRS joints, so an `AnimationPose` can move them. Matrix joints stay on the authored matrix.
    var poseableJoints = false

    func write() throws -> URL {
        var bin = Data()
        var views: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        func align() {
            let padding = (4 - bin.count % 4) % 4
            if padding > 0 { bin.append(Data(count: padding)) }
        }
        func addFloats(_ floats: [Float], type: String, components: Int) -> Int {
            align()
            let offset = bin.count
            appendFloats(floats, to: &bin)
            let view = views.count
            views.append(["buffer": 0, "byteOffset": offset, "byteLength": floats.count * 4])
            let index = accessors.count
            accessors.append([
                "bufferView": view, "componentType": 5126, "count": floats.count / components, "type": type,
            ])
            return index
        }
        func addJoints(_ values: [SIMD4<UInt16>]) -> Int {
            align()
            let offset = bin.count
            for value in values {
                for component in 0..<4 {
                    var bits = value[component].littleEndian
                    Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
                }
            }
            let view = views.count
            views.append(["buffer": 0, "byteOffset": offset, "byteLength": values.count * 8])
            let index = accessors.count
            accessors.append([
                "bufferView": view, "componentType": 5123, "count": values.count, "type": "VEC4",
            ])
            return index
        }

        var attributes: [String: Int] = [
            "POSITION": addFloats(vertices.flatMap { [$0.position.x, $0.position.y, $0.position.z] }, type: "VEC3", components: 3),
            "NORMAL": addFloats(vertices.flatMap { [$0.normal.x, $0.normal.y, $0.normal.z] }, type: "VEC3", components: 3),
            "JOINTS_0": addJoints(vertices.map(\.joints0)),
            "WEIGHTS_0": addFloats(vertices.flatMap { [$0.weights0.x, $0.weights0.y, $0.weights0.z, $0.weights0.w] }, type: "VEC4", components: 4),
        ]
        if includeJoints1 {
            attributes["JOINTS_1"] = addJoints(vertices.map(\.joints1))
            attributes["WEIGHTS_1"] = addFloats(vertices.flatMap { [$0.weights1.x, $0.weights1.y, $0.weights1.z, $0.weights1.w] }, type: "VEC4", components: 4)
        }
        var primitive: [String: Any] = ["attributes": attributes]
        if let morphDelta {
            let accessor = addFloats(morphDelta.flatMap { [$0.x, $0.y, $0.z] }, type: "VEC3", components: 3)
            primitive["targets"] = [["POSITION": accessor]]
        }
        let ibm = addFloats(inverseBinds.flatMap(matrixFloats), type: "MAT4", components: 16)
        var mesh: [String: Any] = ["primitives": [primitive]]
        if morphDelta != nil { mesh["weights"] = [Double(morphWeight)] }
        var meshNode: [String: Any] = ["mesh": 0, "skin": 0]
        if let meshTranslation {
            meshNode["translation"] = [Double(meshTranslation.x), Double(meshTranslation.y), Double(meshTranslation.z)]
            meshNode["rotation"] = [0.0, 0.0, 0.0, 1.0]
            meshNode["scale"] = [1.0, 1.0, 1.0]
        } else {
            meshNode["matrix"] = matrixJSON(meshMatrix)
        }
        var nodes: [[String: Any]] = [meshNode]
        for matrix in jointMatrices {
            if poseableJoints {
                nodes.append([
                    "translation": [0.0, 0.0, 0.0],
                    "rotation": [0.0, 0.0, 0.0, 1.0],
                    "scale": [1.0, 1.0, 1.0],
                ])
            } else {
                nodes.append(["matrix": matrixJSON(matrix)])
            }
        }
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": bin.count]],
            "bufferViews": views,
            "accessors": accessors,
            "meshes": [mesh],
            "skins": [["joints": Array(1...jointMatrices.count), "inverseBindMatrices": ibm]],
            "nodes": nodes,
            "scenes": [["nodes": Array(0..<nodes.count)]],
            "scene": 0,
        ]
        return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "metal-skin")
    }
}

private func matrixFloats(_ matrix: simd_float4x4) -> [Float] {
    (0..<4).flatMap { column in (0..<4).map { row in matrix[column][row] } }
}

private func matrixJSON(_ matrix: simd_float4x4) -> [Double] {
    matrixFloats(matrix).map(Double.init)
}

private func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.3 = SIMD4(t, 1)
    return matrix
}

private func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
    simd_float4x4(diagonal: SIMD4(s, 1))
}

/// 90° about Z. (1, 0, 0) goes to (0, 1, 0); (1, 1, 0) goes to (−1, 1, 0).
private let rotZ90 = simd_float4x4(columns: (
    SIMD4(0, 1, 0, 0),
    SIMD4(-1, 0, 0, 0),
    SIMD4(0, 0, 1, 0),
    SIMD4(0, 0, 0, 1)
))

/// Khronos blend: no renormalization. A zero weight sum leaves the vertex where it is.
private func blend(_ position: SIMD3<Float>, _ influences: [(simd_float4x4, Float)]) -> SIMD3<Float> {
    var skin = simd_float4x4(0)
    var sum: Float = 0
    for (matrix, weight) in influences where weight != 0 {
        skin += matrix * weight
        sum += weight
    }
    guard sum != 0 else { return position }
    let point = skin * SIMD4(position, 1)
    return SIMD3(point.x, point.y, point.z)
}

private func vertices(_ draw: MetalDraw) -> [MetalVertex] {
    let count = draw.vertexBuffer.length / MemoryLayout<MetalVertex>.stride
    let pointer = draw.vertexBuffer.contents().bindMemory(to: MetalVertex.self, capacity: max(count, 1))
    return Array(UnsafeBufferPointer(start: pointer, count: count))
}

private func expectNear(_ value: SIMD3<Float>, _ expected: SIMD3<Float>, tolerance: Float = 1e-5) {
    let delta = abs(value - expected)
    #expect(delta.x <= tolerance && delta.y <= tolerance && delta.z <= tolerance, "\(value) != \(expected)")
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
