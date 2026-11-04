import Foundation
import Metal
import simd
import Testing
@testable import Renderer

/// GPU morph against hand-written base + weight·delta, not values copied out of the loader.
@Suite struct MetalMorphTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    private func renderer(_ url: URL) async throws -> MetalRenderer {
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        return try MetalRenderer(sharing: scene)
    }

    /// `morph-triangle.gltf`: positions (0,0,0), (1,0,0), (0,1,0); target 0 moves the first by (0,0,1).
    @Test func morphFixtureMatchesCpuOracle() async throws {
        let base: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0]]
        let delta = SIMD3<Float>(0, 0, 1)
        func oracle(_ weight: Float) -> SIMD3<Float> { base[0] + delta * weight }

        let gpu = try await renderer(TestFixtures.morph)
        let draw = try #require(gpu.scene?.draws.first)
        let stored = vertices(draw)
        #expect(stored.count == 3)
        for index in 0..<3 { expectNear(stored[index].position.xyz, base[index]) }

        let rest = try gpu.captureMorphedVertices(drawIndex: 0, pose: nil)
        let zero = try gpu.captureMorphedVertices(drawIndex: 0, pose: AnimationPose(meshWeights: [0: [0]]))
        let half = try gpu.captureMorphedVertices(drawIndex: 0, pose: AnimationPose(meshWeights: [0: [0.5]]))
        let full = try gpu.captureMorphedVertices(drawIndex: 0, pose: AnimationPose(meshWeights: [0: [1]]))
        expectNear(rest[0].position.xyz, oracle(0))
        expectNear(zero[0].position.xyz, oracle(0))
        expectNear(half[0].position.xyz, oracle(0.5))
        expectNear(full[0].position.xyz, oracle(1))
        expectNear(full[1].position.xyz, base[1])
        expectNear(full[2].position.xyz, base[2])

        let weighted = try write(MorphFile(
            positions: base,
            targets: [MorphFile.Target(position: [delta, .zero, .zero])],
            meshWeights: [1]
        ))
        defer { try? FileManager.default.removeItem(at: weighted) }
        let posed = try await renderer(weighted)
        let baked = try #require(posed.scene?.draws.first)
        for index in 0..<3 { expectNear(vertices(baked)[index].position.xyz, base[index]) }
        let applied = try posed.captureMorphedVertices(drawIndex: 0, pose: nil)
        expectNear(applied[0].position.xyz, oracle(1))
    }

    /// Shared corners are split for face normals. Each expanded vertex keeps its source deltas.
    @Test func deindexedVerticesReceiveSourceDeltas() async throws {
        let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        let target0 = MorphFile.Target(
            position: [[0, 0, 1], [0, 0, 0], [0, 0, 0], [0, 0, 2]],
            normal: [[0, 1, 0], [0, 0, 0], [0, 0, 0], [1, 0, 0]],
            tangent: [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 0, 0]],
            uv0: [[0.5, 0.25], [0, 0], [0, 0], [0.125, 0]],
            uv1: [[0, 0.5], [0, 0], [0, 0], [0, 0]],
            color: [[0.5, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0.25]]
        )
        let target1 = MorphFile.Target(
            position: [[0, 0, 0], [0, 0, 3], [0, 0, 0], [0, 0, 0]],
            normal: [[0, 0, 0], [0, 0.5, 0], [0, 0, 0], [0, 0, 0]],
            uv1: [[0, 0], [0.25, 0.25], [0, 0], [0, 0]],
            color: [[0, 0.25, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
        )
        let url = try write(MorphFile(positions: positions, indices: indices, targets: [target0, target1], meshWeights: [0, 0]))
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        let draw = try #require(scene.draws.first)
        #expect(draw.morphVertexCount == indices.count)
        #expect(draw.morphTargetCount == 2)
        #expect(draw.morphMask & (1 << MorphSlot.position) != 0)
        #expect(draw.morphMask & (1 << MorphSlot.tangent) != 0)
        #expect(draw.morphMask & (1 << MorphSlot.texCoord0) != 0)
        #expect(draw.morphMask & (1 << MorphSlot.color0) != 0)

        for (emitted, source) in indices.enumerated() {
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.position, target: 0, vertex: emitted)), pad(target0.position![Int(source)]))
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.normal, target: 0, vertex: emitted)), pad(target0.normal![Int(source)]))
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.tangent, target: 0, vertex: emitted)), pad(target0.tangent![Int(source)]))
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.texCoord0, target: 0, vertex: emitted)), pad(target0.uv0![Int(source)]))
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.texCoord1, target: 0, vertex: emitted)), pad(target0.uv1![Int(source)]))
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.color0, target: 0, vertex: emitted)), target0.color![Int(source)])
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.position, target: 1, vertex: emitted)), pad(target1.position![Int(source)]))
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.normal, target: 1, vertex: emitted)), pad(target1.normal![Int(source)]))
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.tangent, target: 1, vertex: emitted)), .zero)
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.texCoord0, target: 1, vertex: emitted)), .zero)
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.texCoord1, target: 1, vertex: emitted)), pad(target1.uv1![Int(source)]))
            expectNear(try #require(draw.morphDelta(slot: MorphSlot.color0, target: 1, vertex: emitted)), target1.color![Int(source)])
        }
        let shared = try #require(draw.morphDelta(slot: MorphSlot.position, target: 0, vertex: 0))
        let alsoShared = try #require(draw.morphDelta(slot: MorphSlot.position, target: 0, vertex: 3))
        expectNear(shared, alsoShared)
        expectNear(shared, SIMD4<Float>(0, 0, 1, 0))
        let other = try #require(draw.morphDelta(slot: MorphSlot.position, target: 0, vertex: 5))
        expectNear(other, SIMD4<Float>(0, 0, 2, 0))
    }

    @Test func weightsUpdateWithoutReloadAndBaseNormalsStay() async throws {
        let gpu = try await renderer(TestFixtures.morph)
        let buffer = try #require(gpu.scene?.draws.first?.vertexBuffer)
        let before = try gpu.captureMorphedVertices(drawIndex: 0, pose: AnimationPose(meshWeights: [0: [0]]))
        let after = try gpu.captureMorphedVertices(drawIndex: 0, pose: AnimationPose(meshWeights: [0: [1]]))
        #expect(gpu.scene?.draws.first?.vertexBuffer === buffer)
        expectNear(before[0].position.xyz, [0, 0, 0])
        expectNear(after[0].position.xyz, [0, 0, 1])
        expectNear(after[0].normal.xyz, [0, 0, 1])
        let morphedGeometric = simd_normalize(simd_cross(SIMD3<Float>(1, 0, -1), SIMD3<Float>(0, 1, -1)))
        #expect(simd_distance(after[0].normal.xyz, morphedGeometric) > 0.2)
        expectNear(after[0].color, SIMD4<Float>(repeating: 1))
        expectNear(after[0].uv0, .zero)
        expectNear(after[0].uv1, .zero)

        let node = try gpu.captureMorphedVertices(
            drawIndex: 0,
            pose: AnimationPose(nodeWeights: [0: [0]], meshWeights: [0: [1]])
        )
        expectNear(node[0].position.xyz, [0, 0, 0])

        let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        let url = try write(MorphFile(
            positions: positions,
            indices: indices,
            targets: [
                MorphFile.Target(position: [[0, 0, 1], .zero, .zero, [0, 0, 4]], uv0: [[0.5, -0.25], .zero, .zero, .zero]),
                MorphFile.Target(position: [.zero, [0, 0, 2], .zero, .zero]),
            ],
            meshWeights: [0, 0]
        ))
        defer { try? FileManager.default.removeItem(at: url) }
        let shared = try await renderer(url)
        let mixed = try shared.captureMorphedVertices(drawIndex: 0, pose: AnimationPose(meshWeights: [0: [0.5, 0.25]]))
        expectNear(mixed[0].position.xyz, [0, 0, 0.5])
        expectNear(mixed[1].position.xyz, [1, 0, 0.5])
        expectNear(mixed[5].position.xyz, [0, 1, 2])
        expectNear(mixed[0].uv0, SIMD2<Float>(0.5, -0.25) * 0.5)
        expectNear(mixed[0].normal.xyz, [0, 0, 1])
        expectNear(mixed[0].color, SIMD4<Float>(repeating: 1))

        try await expectTangentsStayOnTheBaseShape()
    }

    /// Rest weight 1 must not change the tangent MikkTSpace builds from the unmorphed triangle.
    private func expectTangentsStayOnTheBaseShape() async throws {
        let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0]]
        let uvs: [SIMD2<Float>] = [[0, 0], [1, 0], [0, 1]]
        let weighted = try write(MorphFile(
            positions: positions, uv0: uvs,
            targets: [MorphFile.Target(position: [.zero, [0, 1, 0], .zero])],
            meshWeights: [1]
        ))
        let moved = try write(MorphFile(
            positions: [[0, 0, 0], [1, 1, 0], [0, 1, 0]], uv0: uvs,
            targets: [], meshWeights: []
        ))
        defer {
            try? FileManager.default.removeItem(at: weighted)
            try? FileManager.default.removeItem(at: moved)
        }
        let gpu = try device()
        let baseScene = try await MetalSceneLoader.load(url: weighted, device: gpu)
        let tiltedScene = try await MetalSceneLoader.load(url: moved, device: gpu)
        let base = try #require(baseScene.draws.first)
        let tilted = try #require(tiltedScene.draws.first)
        expectNear(vertices(base)[0].tangent.xyz, [1, 0, 0], tolerance: 1e-3)
        #expect(abs(vertices(tilted)[0].tangent.y) > 0.4)
    }
}

private struct MorphFile {
    struct Target {
        var position: [SIMD3<Float>]? = nil
        var normal: [SIMD3<Float>]? = nil
        var tangent: [SIMD3<Float>]? = nil
        var uv0: [SIMD2<Float>]? = nil
        var uv1: [SIMD2<Float>]? = nil
        var color: [SIMD4<Float>]? = nil
    }

    var positions: [SIMD3<Float>]
    var color: [SIMD4<Float>]? = nil
    var uv0: [SIMD2<Float>]? = nil
    var indices: [UInt16]? = nil
    var targets: [Target]
    var meshWeights: [Float]
    var nodeWeights: [Float]? = nil
}

private func write(_ file: MorphFile) throws -> URL {
    var bin = Data()
    var views: [[String: Any]] = []
    var accessors: [[String: Any]] = []

    func align() {
        let padding = (4 - bin.count % 4) % 4
        if padding > 0 { bin.append(Data(count: padding)) }
    }
    func add(_ floats: [Float], type: String, components: Int) -> Int {
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
    func vec3(_ values: [SIMD3<Float>]) -> Int {
        add(values.flatMap { [$0.x, $0.y, $0.z] }, type: "VEC3", components: 3)
    }
    func vec2(_ values: [SIMD2<Float>]) -> Int {
        add(values.flatMap { [$0.x, $0.y] }, type: "VEC2", components: 2)
    }
    func vec4(_ values: [SIMD4<Float>]) -> Int {
        add(values.flatMap { [$0.x, $0.y, $0.z, $0.w] }, type: "VEC4", components: 4)
    }

    var attributes: [String: Int] = ["POSITION": vec3(file.positions)]
    if let color = file.color { attributes["COLOR_0"] = vec4(color) }
    if let uv0 = file.uv0 { attributes["TEXCOORD_0"] = vec2(uv0) }
    var targetJSON: [[String: Int]] = []
    for target in file.targets {
        var entry: [String: Int] = [:]
        if let position = target.position { entry["POSITION"] = vec3(position) }
        if let normal = target.normal { entry["NORMAL"] = vec3(normal) }
        if let tangent = target.tangent { entry["TANGENT"] = vec3(tangent) }
        if let uv0 = target.uv0 { entry["TEXCOORD_0"] = vec2(uv0) }
        if let uv1 = target.uv1 { entry["TEXCOORD_1"] = vec2(uv1) }
        if let color = target.color { entry["COLOR_0"] = vec4(color) }
        targetJSON.append(entry)
    }
    var primitive: [String: Any] = ["attributes": attributes]
    if !targetJSON.isEmpty { primitive["targets"] = targetJSON }
    if let indices = file.indices {
        align()
        let offset = bin.count
        for index in indices {
            var bits = index.littleEndian
            Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
        }
        let view = views.count
        views.append(["buffer": 0, "byteOffset": offset, "byteLength": indices.count * 2])
        let accessor = accessors.count
        accessors.append([
            "bufferView": view, "componentType": 5123, "count": indices.count, "type": "SCALAR",
        ])
        primitive["indices"] = accessor
    }
    var node: [String: Any] = ["mesh": 0]
    if let nodeWeights = file.nodeWeights { node["weights"] = nodeWeights.map(Double.init) }
    var mesh: [String: Any] = ["primitives": [primitive]]
    if !file.meshWeights.isEmpty { mesh["weights"] = file.meshWeights.map(Double.init) }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": views,
        "accessors": accessors,
        "meshes": [mesh],
        "nodes": [node],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: "metal-morph")
}

private func vertices(_ draw: MetalDraw) -> [MetalVertex] {
    let count = draw.vertexBuffer.length / MemoryLayout<MetalVertex>.stride
    let pointer = draw.vertexBuffer.contents().bindMemory(to: MetalVertex.self, capacity: max(count, 1))
    return Array(UnsafeBufferPointer(start: pointer, count: count))
}

private func pad(_ value: SIMD3<Float>) -> SIMD4<Float> { SIMD4(value, 0) }
private func pad(_ value: SIMD2<Float>) -> SIMD4<Float> { SIMD4(value.x, value.y, 0, 0) }

private func expectNear(_ value: SIMD3<Float>, _ expected: SIMD3<Float>, tolerance: Float = 1e-5) {
    let delta = abs(value - expected)
    #expect(delta.x <= tolerance && delta.y <= tolerance && delta.z <= tolerance, "\(value) != \(expected)")
}

private func expectNear(_ value: SIMD4<Float>, _ expected: SIMD4<Float>, tolerance: Float = 1e-5) {
    let delta = abs(value - expected)
    #expect(delta.x <= tolerance && delta.y <= tolerance && delta.z <= tolerance && delta.w <= tolerance, "\(value) != \(expected)")
}

private func expectNear(_ value: SIMD2<Float>, _ expected: SIMD2<Float>, tolerance: Float = 1e-5) {
    let delta = abs(value - expected)
    #expect(delta.x <= tolerance && delta.y <= tolerance, "\(value) != \(expected)")
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
