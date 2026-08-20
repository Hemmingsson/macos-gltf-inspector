import AppKit
import RealityKit
import simd

/// Host-only selection affordances: dim non-selected meshes, AABB wire box, HoverEffect.
enum PreviewSelectionVisuals {
    static let dimOpacity: Float = 0.28

    @MainActor
    static func apply(selectedNodeIndex: Int?, to root: Entity) {
        clearSelectionChrome(in: root)

        guard let selectedNodeIndex,
              let selected = GLTFNodeLookup.entity(nodeIndex: selectedNodeIndex, in: root)
        else {
            clearDim(in: root)
            return
        }

        applyDim(selectedRoot: selected, under: root)
        let bounds = selected.visualBounds(recursive: true, relativeTo: selected)
        guard !bounds.isEmpty else { return }
        attachSelectionBox(to: selected, bounds: bounds)
        attachHover(to: selected, bounds: bounds)
    }

    // MARK: - Dim

    @MainActor
    private static func clearDim(in root: Entity) {
        walk(root) { entity in
            entity.components.remove(OpacityComponent.self)
        }
    }

    @MainActor
    private static func applyDim(selectedRoot: Entity, under root: Entity) {
        var selectedSubtree = Set<ObjectIdentifier>()
        func collect(_ entity: Entity) {
            selectedSubtree.insert(ObjectIdentifier(entity))
            for child in entity.children {
                collect(child)
            }
        }
        collect(selectedRoot)

        walk(root) { entity in
            guard entity.components[ModelComponent.self] != nil else {
                entity.components.remove(OpacityComponent.self)
                return
            }
            if selectedSubtree.contains(ObjectIdentifier(entity)) {
                entity.components.remove(OpacityComponent.self)
            } else if entity.isEnabled {
                entity.components.set(OpacityComponent(opacity: dimOpacity))
            } else {
                entity.components.remove(OpacityComponent.self)
            }
        }
    }

    // MARK: - Selection box

    @MainActor
    private static func attachSelectionBox(to selected: Entity, bounds: BoundingBox) {
        selected.addChild(makeWireBox(bounds: bounds))
    }

    @MainActor
    private static func makeWireBox(bounds: BoundingBox) -> Entity {
        let parent = Entity()
        parent.name = PreviewFloor.selectionBoxName
        let min = bounds.min
        let max = bounds.max
        let extent = max - min
        let longest = Swift.max(extent.x, Swift.max(extent.y, extent.z))
        // Visible wire: ~0.4% of longest, floored so small nodes still read (~1 mm).
        let thickness = Swift.min(Swift.max(longest * 0.004, 0.001), 0.012)
        let material = UnlitMaterial(color: NSColor.systemYellow.withAlphaComponent(0.95))

        let corners: [SIMD3<Float>] = [
            SIMD3(min.x, min.y, min.z),
            SIMD3(max.x, min.y, min.z),
            SIMD3(min.x, max.y, min.z),
            SIMD3(max.x, max.y, min.z),
            SIMD3(min.x, min.y, max.z),
            SIMD3(max.x, min.y, max.z),
            SIMD3(min.x, max.y, max.z),
            SIMD3(max.x, max.y, max.z),
        ]
        let edges: [(Int, Int)] = [
            (0, 1), (1, 3), (3, 2), (2, 0),
            (4, 5), (5, 7), (7, 6), (6, 4),
            (0, 4), (1, 5), (2, 6), (3, 7),
        ]
        for (a, b) in edges {
            parent.addChild(edgeEntity(from: corners[a], to: corners[b], thickness: thickness, material: material))
        }
        return parent
    }

    @MainActor
    private static func edgeEntity(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        thickness: Float,
        material: UnlitMaterial
    ) -> Entity {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 1e-8 else { return Entity() }
        let size: SIMD3<Float>
        if abs(delta.x) >= abs(delta.y), abs(delta.x) >= abs(delta.z) {
            size = SIMD3(length, thickness, thickness)
        } else if abs(delta.y) >= abs(delta.x), abs(delta.y) >= abs(delta.z) {
            size = SIMD3(thickness, length, thickness)
        } else {
            size = SIMD3(thickness, thickness, length)
        }
        let entity = Entity()
        entity.components.set(ModelComponent(mesh: .generateBox(size: size), materials: [material]))
        entity.position = (start + end) * 0.5
        return entity
    }

    // MARK: - Hover

    @MainActor
    private static func attachHover(to selected: Entity, bounds: BoundingBox) {
        let size = bounds.max - bounds.min
        let shape = ShapeResource.generateBox(size: size).offsetBy(translation: bounds.center)
        selected.components.set(InputTargetComponent())
        selected.components.set(CollisionComponent(shapes: [shape]))
        selected.components.set(
            HoverEffectComponent(
                .highlight(HoverEffectComponent.HighlightHoverEffectStyle(strength: 1.25))
            )
        )
    }

    // MARK: - Clear / walk

    @MainActor
    private static func clearSelectionChrome(in root: Entity) {
        var remove: [Entity] = []
        func visit(_ entity: Entity) {
            if entity.name == PreviewFloor.selectionBoxName {
                remove.append(entity)
                return
            }
            if entity.components.has(HoverEffectComponent.self)
                || entity.components.has(InputTargetComponent.self)
            {
                entity.components.remove(HoverEffectComponent.self)
                entity.components.remove(InputTargetComponent.self)
                entity.components.remove(CollisionComponent.self)
            }
            for child in entity.children {
                visit(child)
            }
        }
        visit(root)
        for entity in remove {
            entity.removeFromParent()
        }
    }

    @MainActor
    private static func walk(_ entity: Entity, visit: (Entity) -> Void) {
        if PreviewFloor.isHelperName(entity.name) { return }
        visit(entity)
        for child in entity.children {
            walk(child, visit: visit)
        }
    }
}
