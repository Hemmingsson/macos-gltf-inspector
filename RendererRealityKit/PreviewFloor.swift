import AppKit
import RealityKit
import simd

/// Procedural polar grid under the turntable (rings + radials only — no filled disc).
enum PreviewFloor {
    static let entityName = "previewFloor"
    static let selectionBoxName = "selectionBox"
    static let ringCount = 4
    static let radialCount = 8
    /// Tessellation for circular ring meshes (true annuli, not chord boxes).
    static let circleSegments = 64
    /// 2× prior plate; keeps polar grid readable under large assets.
    static let diameterScale: Float = 2.7
    /// Lift just under the model so the grid does not z-fight the mesh.
    static let yBias: Float = 0.001
    /// Fraction of floor radius — kept tiny to mimic screen-space hairlines.
    private static let lineThickness: Float = 0.0007

    /// Helper names skipped by Fit framing (`modelBounds`) and selection dim walks.
    static func isHelperName(_ name: String) -> Bool {
        name == entityName
            || name == selectionBoxName
            || name == PreviewCamera.worldOriginGizmoName
            || PreviewSkeletonOverlay.isHelperName(name)
    }

    /// Floor root named `previewFloor`, parented under the turntable in pivot space.
    @MainActor
    static func make(bounds: BoundingBox, lineColor: NSColor = NSColor(srgbRed: 0x88 / 255, green: 0x88 / 255, blue: 0x88 / 255, alpha: 1)) -> Entity {
        let extent = bounds.max - bounds.min
        let diameter = diameterScale * max(extent.x, extent.z)
        let radius = max(diameter * 0.5, 0.001)

        let root = Entity()
        root.name = entityName
        root.position = SIMD3(0, bounds.min.y - yBias, 0)
        root.addChild(makePolarGrid(radius: radius, lineColor: lineColor))
        return root
    }

    /// Retint every line mesh when the preview backdrop cycles.
    @MainActor
    static func applyLineColor(_ color: NSColor, to floor: Entity) {
        guard floor.name == entityName else { return }
        let material = lineMaterial(color: color)
        func walk(_ node: Entity) {
            if var model = node.components[ModelComponent.self] {
                model.materials = [material]
                node.components.set(model)
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(floor)
    }

    /// Contact shadows: model meshes cast (no floor catcher disc).
    @MainActor
    static func enableCastingShadows(on root: Entity) {
        func walk(_ node: Entity) {
            if isHelperName(node.name) { return }
            if node.components[ModelComponent.self] != nil {
                node.components.set(GroundingShadowComponent(castsShadow: true))
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(root)
    }

    @MainActor
    private static func makePolarGrid(radius: Float, lineColor: NSColor) -> Entity {
        let grid = Entity()
        grid.name = "polarGrid"
        let material = lineMaterial(color: lineColor)
        let thickness = max(lineThickness * radius, 0.0001)

        for ring in 1...ringCount {
            let r = radius * Float(ring) / Float(ringCount)
            if let mesh = makeCircleRingMesh(
                radius: r,
                halfWidth: thickness * 0.5,
                segments: circleSegments
            ) {
                let entity = ModelEntity(mesh: mesh, materials: [material])
                entity.name = "polarRing\(ring)"
                grid.addChild(entity)
            }
        }

        let inner = max(radius * 0.03, 0.002)
        for i in 0..<radialCount {
            let angle = Float(i) / Float(radialCount) * (.pi * 2)
            let dir = SIMD3(cos(angle), 0, sin(angle))
            grid.addChild(
                thinSegment(
                    from: dir * inner,
                    to: dir * radius,
                    thickness: thickness,
                    material: material
                )
            )
        }
        return grid
    }

    private static func lineMaterial(color: NSColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: 0.5)
        material.faceCulling = .none
        return material
    }

    @MainActor
    private static func thinSegment(
        from: SIMD3<Float>,
        to: SIMD3<Float>,
        thickness: Float,
        material: UnlitMaterial
    ) -> ModelEntity {
        let delta = to - from
        let length = max(simd_length(delta), 0.0001)
        let mid = (from + to) * 0.5
        // Flat ribbon in XZ (no Y extrusion) so top/bottom match.
        let entity = ModelEntity(
            mesh: .generatePlane(width: length, depth: thickness),
            materials: [material]
        )
        entity.position = mid
        let flat = SIMD3(delta.x, 0, delta.z)
        if simd_length(flat) > 1e-5 {
            entity.orientation = simd_quatf(from: SIMD3(1, 0, 0), to: normalize(flat))
        }
        return entity
    }

    /// Flat circular annulus (no thickness / underside).
    private static func makeCircleRingMesh(
        radius: Float,
        halfWidth: Float,
        segments: Int
    ) -> MeshResource? {
        let count = max(segments, 8)
        let rIn = max(radius - halfWidth, 0.00001)
        let rOut = radius + halfWidth

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(count * 2)
        for i in 0..<count {
            let angle = Float(i) / Float(count) * (.pi * 2)
            let c = cos(angle)
            let s = sin(angle)
            positions.append(SIMD3(c * rIn, 0, s * rIn))
            positions.append(SIMD3(c * rOut, 0, s * rOut))
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(count * 6)
        for i in 0..<count {
            let i0 = UInt32(i * 2)
            let j0 = UInt32(((i + 1) % count) * 2)
            indices.append(contentsOf: [i0, i0 + 1, j0 + 1, i0, j0 + 1, j0])
        }

        var descriptor = MeshDescriptor(name: "polarCircleRing")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
