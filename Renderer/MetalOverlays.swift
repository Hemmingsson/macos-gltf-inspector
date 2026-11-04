import GLTFKit2
import Metal
import simd

/// Inspector chrome drawn after the Khronos frame, as the former viewer page's `drawOverlays` did:
/// the polar floor, the authored-origin gizmo and the selected subtree's box. Same geometry,
/// colours and pass:
/// opaque 1-pixel lines, soft-tested against the stored scene depth so they sit behind the model,
/// the user camera even while a file camera draws the model, and the viewer's antialiased
/// canvas — 4× MSAA, seeded with the tonemapped frame.
struct MetalOverlayOptions: Sendable {
    var floor: Bool
    /// Authored-origin RGB tripod when the view is not centred on the scene.
    var origin: Bool
    /// When true, draws every authored camera and punctual-light gizmo except `skipCameraNodeIndex`.
    var sceneGizmos: Bool
    var selectedNode: Int?
    /// glTF mesh nodes using the selected material (muted AABB each).
    var highlightedNodeIndices: Set<Int>
    /// Every selected mesh or empty node (multi-select), each with the selection box.
    var selectedNodes: Set<Int> = []
    /// Node under the pointer: thin muted box.
    var hoveredNode: Int?
    /// Index into `asset.skins` when a skin row is selected.
    var selectedSkinIndex: Int?
    /// glTF node index of the file camera the canvas looks through; its frustum is omitted.
    var skipCameraNodeIndex: Int?
    /// Canvas aspect when a perspective camera has no authored `aspectRatio`.
    var canvasAspect: Float
    /// Nodes (or ancestors) whose scene gizmos are omitted unless that node is selected.
    var hiddenNodeIndices: Set<Int>
    /// `camera.sceneExtents`: what the viewer sizes the floor and gizmo by. When centring is off it
    /// includes the origin. Nil uses the scene's drawn bounds.
    var extents: (min: SIMD3<Float>, max: SIMD3<Float>)?
    var useSilhouetteSelectionOutline: Bool
    init(floor: Bool = false, origin: Bool = false, sceneGizmos: Bool = false, selectedNode: Int? = nil,
         highlightedNodeIndices: Set<Int> = [], selectedSkinIndex: Int? = nil, skipCameraNodeIndex: Int? = nil,
         canvasAspect: Float = 1, hiddenNodeIndices: Set<Int> = [], extents: (min: SIMD3<Float>, max: SIMD3<Float>)? = nil,
         useSilhouetteSelectionOutline: Bool = true) {
        self.floor = floor
        self.origin = origin
        self.sceneGizmos = sceneGizmos
        self.selectedNode = selectedNode
        self.highlightedNodeIndices = highlightedNodeIndices
        self.selectedSkinIndex = selectedSkinIndex
        self.skipCameraNodeIndex = skipCameraNodeIndex
        self.canvasAspect = canvasAspect
        self.hiddenNodeIndices = hiddenNodeIndices
        self.extents = extents
        self.useSilhouetteSelectionOutline = useSilhouetteSelectionOutline
    }
}

extension MetalOverlayOptions {
    /// What a frame drawn with `options` overlays; the live draw and gizmo picking share it.
    init(_ options: ViewOptions, canvasAspect: Float, extents: (min: SIMD3<Float>, max: SIMD3<Float>)?) {
        self.init(floor: options.showsFloor, origin: !options.isCentered, sceneGizmos: options.showsSceneGizmos,
                  selectedNode: options.gizmoSelectedNodeIndex ?? options.selectedNodeIndex,
                  highlightedNodeIndices: options.highlightedNodeIndices,
                  selectedSkinIndex: options.selectedSkinIndex, skipCameraNodeIndex: options.fileCameraNodeIndex,
                  canvasAspect: canvasAspect, hiddenNodeIndices: options.hiddenNodeIndices, extents: extents,
                  useSilhouetteSelectionOutline: options.useSilhouetteSelectionOutline)
        selectedNodes = options.selectedNodeIndices
        hoveredNode = options.hoveredNodeIndex
    }
}

struct MetalLineVertex { var position: SIMD4<Float>; var color: SIMD4<Float> }

private enum OverlayGizmoColors {
    /// Selected camera / light frustum (DS warning-adjacent orange).
    static let selectedScene = SIMD3<Float>(1, 0.65, 0.2)
    static let mutedScene = SIMD3<Float>(0.45, 0.45, 0.45)
    static let axisBlue = SIMD3<Float>(0.25, 0.45, 1)
    static let selectionHighlight = SIMD3<Float>(0.15, 0.75, 1)
    static let materialUsageHighlight = SIMD3<Float>(0.35, 0.55, 0.65)
    /// Pre-selection under the pointer: the selection hue, dimmed.
    static let hover = SIMD3<Float>(0.45, 0.62, 0.72)
}

private func lightIsHidden(nodeIndex: Int, scene: MetalScene, hidden: Set<Int>) -> Bool {
    guard !hidden.isEmpty else { return false }
    return scene.ancestors(ofNode: nodeIndex).contains { hidden.contains($0) }
}

private func sceneLightGizmoColor(light: GLTFLight, selected: Bool) -> SIMD3<Float> {
    if selected { return OverlayGizmoColors.selectedScene }
    var c = SIMD3<Float>(light.color.x, light.color.y, light.color.z)
    let peak = max(c.x, c.y, c.z, 1e-6)
    c /= peak
    return c * 0.5 + SIMD3(repeating: 0.5)
}

func overlayVertices(scene: MetalScene, options: MetalOverlayOptions) -> [MetalLineVertex] {
    var vertices: [MetalLineVertex] = []
    func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ color: SIMD3<Float>) {
        vertices.append(MetalLineVertex(position: SIMD4(a, 1), color: SIMD4(color, 1)))
        vertices.append(MetalLineVertex(position: SIMD4(b, 1), color: SIMD4(color, 1)))
    }
    let (extent, span) = overlayExtentAndSpan(scene: scene, options: options)
    if options.floor {
        // Polar floor centred on the world origin, just under the scene.
        let radius = max(2.7 * max(extent.x, extent.z) * 0.5, 0.001)
        let y = (options.extents?.min ?? scene.boundsMin).y - 0.001
        let color = SIMD3<Float>(0.53, 0.53, 0.53)
        let rings = 4, radials = 8, segments = 64
        for ring in 1...rings {
            let r = radius * Float(ring) / Float(rings)
            var previous: SIMD3<Float>?
            for i in 0...segments {
                let a = Double(i) / Double(segments) * .pi * 2
                let p = SIMD3(Float(cos(a)) * r, y, Float(sin(a)) * r)
                if let previous { line(previous, p, color) }
                previous = p
            }
        }
        let inner = max(radius * 0.03, 0.002)
        for i in 0..<radials {
            let a = Double(i) / Double(radials) * .pi * 2
            let c = Float(cos(a)), s = Float(sin(a))
            line(SIMD3(c * inner, y, s * inner), SIMD3(c * radius, y, s * radius), color)
        }
    }
    if options.origin {
        let size = 0.18 * max(extent.x, extent.y, extent.z, 0.05)
        line(.zero, SIMD3(size, 0, 0), SIMD3(1, 0.2, 0.2))
        line(.zero, SIMD3(0, size, 0), SIMD3(0.2, 1, 0.2))
        line(.zero, SIMD3(0, 0, size), OverlayGizmoColors.axisBlue)
    }

    var drawnSceneGizmos = Set<Int>()
    if options.sceneGizmos {
        for (index, node) in scene.asset.nodes.enumerated() {
            guard node.camera != nil || node.light != nil else { continue }
            if index == options.skipCameraNodeIndex, node.camera != nil { continue }
            if index != options.selectedNode, lightIsHidden(nodeIndex: index, scene: scene,
                                                            hidden: options.hiddenNodeIndices) { continue }
            let selected = index == options.selectedNode
            collectSceneNodeGizmo(scene: scene, nodeIndex: index, span: span, canvasAspect: options.canvasAspect,
                                  selected: selected, line: line)
            drawnSceneGizmos.insert(index)
        }
    }
    if let index = options.selectedNode, !drawnSceneGizmos.contains(index) {
        collectSelectionGizmo(scene: scene, nodeIndex: index, span: span, canvasAspect: options.canvasAspect,
                              useSilhouetteSelectionOutline: options.useSilhouetteSelectionOutline, line: line)
    }
    collectSkeletonOverlay(scene: scene, selectedSkinIndex: options.selectedSkinIndex,
                           selectedNode: options.selectedNode, span: span,
                           hidden: options.hiddenNodeIndices, line: line)
    let selectionBoxNode = options.selectedNode
    let boxed = options.selectedNodes.union(selectionBoxNode.map { [$0] } ?? [])
    for index in options.selectedNodes.sorted() where index != selectionBoxNode {
        collectSelectionGizmo(scene: scene, nodeIndex: index, span: span, canvasAspect: options.canvasAspect,
                              useSilhouetteSelectionOutline: options.useSilhouetteSelectionOutline, line: line)
    }
    for index in options.highlightedNodeIndices.sorted() {
        if boxed.contains(index) { continue }
        collectNodeAABB(scene: scene, nodeIndex: index, color: OverlayGizmoColors.materialUsageHighlight, line: line)
    }
    if let index = options.hoveredNode, !boxed.contains(index),
       scene.asset.nodes.indices.contains(index), scene.asset.nodes[index].mesh != nil {
        collectNodeAABB(scene: scene, nodeIndex: index, color: OverlayGizmoColors.hover, line: line)
    }
    return vertices
}

/// Nearest ancestor glTF node index that is also a joint of the same skin, or nil.
func nearestJointAncestor(of nodeIndex: Int, jointSet: Set<Int>, nodeParents: [Int]) -> Int? {
    guard nodeParents.indices.contains(nodeIndex) else { return nil }
    var current = nodeIndex
    while nodeParents[current] >= 0 {
        let parent = nodeParents[current]
        if jointSet.contains(parent) { return parent }
        guard nodeParents.indices.contains(parent) else { return nil }
        current = parent
    }
    return nil
}

private func isSkinJoint(_ nodeIndex: Int, scene: MetalScene) -> Bool {
    scene.asset.skins.contains { skin in
        skin.joints.contains { joint in scene.asset.nodes.firstIndex(of: joint) == nodeIndex }
    }
}

/// Screen-space silhouette replaces the AABB for mesh nodes; groups and non-mesh selections keep the box.
func usesSilhouetteSelectionOutline(nodeIndex: Int, scene: MetalScene) -> Bool {
    guard scene.asset.nodes.indices.contains(nodeIndex) else { return false }
    let node = scene.asset.nodes[nodeIndex]
    guard node.mesh != nil, node.camera == nil, node.light == nil else { return false }
    return !isSkinJoint(nodeIndex, scene: scene)
}

func silhouetteOutlineNodeIndices(options: MetalOverlayOptions, scene: MetalScene) -> Set<Int> {
    var nodes = options.selectedNodes
    if let primary = options.selectedNode { nodes.insert(primary) }
    return Set(nodes.filter { usesSilhouetteSelectionOutline(nodeIndex: $0, scene: scene) })
}

private func jointNodeIndices(in scene: MetalScene, skin: GLTFSkin) -> [Int] {
    skin.joints.compactMap { scene.asset.nodes.firstIndex(of: $0) }
}

private func collectSkeletonOverlay(
    scene: MetalScene,
    selectedSkinIndex: Int?,
    selectedNode: Int?,
    span: Float,
    hidden: Set<Int>,
    line: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void
) {
    let resolved: (skin: GLTFSkin, highlightedJoint: Int?)?
    if let skinIndex = selectedSkinIndex, scene.asset.skins.indices.contains(skinIndex) {
        resolved = (scene.asset.skins[skinIndex], nil)
    } else if let nodeIndex = selectedNode, isSkinJoint(nodeIndex, scene: scene),
              let skinIndex = scene.asset.skins.firstIndex(where: { skin in
                  jointNodeIndices(in: scene, skin: skin).contains(nodeIndex)
              }) {
        resolved = (scene.asset.skins[skinIndex], nodeIndex)
    } else {
        resolved = nil
    }
    guard let (skin, highlightedJoint) = resolved else { return }

    let joints = jointNodeIndices(in: scene, skin: skin)
    let jointSet = Set(joints)
    let cross = span * 0.03

    for jointIndex in joints {
        if lightIsHidden(nodeIndex: jointIndex, scene: scene, hidden: hidden) { continue }
        guard let world = scene.worldMatrix(ofNode: jointIndex) else { continue }
        let p = SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
        let jointColor = jointIndex == highlightedJoint
            ? OverlayGizmoColors.selectionHighlight
            : OverlayGizmoColors.mutedScene
        line(p - SIMD3(cross, 0, 0), p + SIMD3(cross, 0, 0), jointColor)
        line(p - SIMD3(0, cross, 0), p + SIMD3(0, cross, 0), jointColor)
        line(p - SIMD3(0, 0, cross), p + SIMD3(0, 0, cross), jointColor)

        guard let parentJoint = nearestJointAncestor(of: jointIndex, jointSet: jointSet,
                                                     nodeParents: scene.nodeParents),
              !lightIsHidden(nodeIndex: parentJoint, scene: scene, hidden: hidden),
              let parentWorld = scene.worldMatrix(ofNode: parentJoint) else { continue }
        let parentPos = SIMD3(parentWorld.columns.3.x, parentWorld.columns.3.y, parentWorld.columns.3.z)
        let boneColor = jointIndex == highlightedJoint
            ? OverlayGizmoColors.selectionHighlight
            : OverlayGizmoColors.mutedScene
        line(parentPos, p, boneColor)
    }
}

/// Pick segments for camera and light gizmos when `sceneGizmos` is on (same nodes as the global
/// gizmo overlay pass, not selection-only AABB / skeleton lines).
private func overlayExtentAndSpan(
    scene: MetalScene,
    options: MetalOverlayOptions
) -> (extent: SIMD3<Float>, span: Float) {
    let low = options.extents?.min ?? scene.boundsMin
    let high = options.extents?.max ?? scene.boundsMax
    let extent = simd_max(high - low, SIMD3(repeating: 1e-4))
    return (extent, max(extent.x, extent.y, extent.z, 0.05))
}

func overlayGizmoSegments(scene: MetalScene, options: MetalOverlayOptions) -> [MetalGizmoSegment] {
    guard options.sceneGizmos else { return [] }
    var segments: [MetalGizmoSegment] = []
    let span = overlayExtentAndSpan(scene: scene, options: options).span
    for (index, node) in scene.asset.nodes.enumerated() {
        guard node.camera != nil || node.light != nil else { continue }
        if index == options.skipCameraNodeIndex, node.camera != nil { continue }
        if index != options.selectedNode, lightIsHidden(nodeIndex: index, scene: scene,
                                                        hidden: options.hiddenNodeIndices) { continue }
        let selected = index == options.selectedNode
        appendSceneNodeGizmoSegments(scene: scene, nodeIndex: index, span: span, canvasAspect: options.canvasAspect,
                                     selected: selected, into: &segments)
    }
    return segments
}

private func appendSceneNodeGizmoSegments(
    scene: MetalScene,
    nodeIndex: Int,
    span: Float,
    canvasAspect: Float,
    selected: Bool,
    into segments: inout [MetalGizmoSegment]
) {
    guard scene.asset.nodes.indices.contains(nodeIndex),
          let world = scene.worldMatrix(ofNode: nodeIndex) else { return }
    let node = scene.asset.nodes[nodeIndex]
    func emit(_ a: SIMD3<Float>, _ b: SIMD3<Float>) {
        segments.append(MetalGizmoSegment(a: a, b: b, nodeIndex: nodeIndex))
    }
    if let camera = node.camera {
        collectCameraFrustum(world: world, camera: camera, span: span, canvasAspect: canvasAspect,
                             selected: selected, line: { a, b, _ in emit(a, b) })
        return
    }
    if let light = node.light {
        collectLightGizmo(world: world, light: light, span: span, color: .zero, line: { a, b, _ in emit(a, b) })
    }
}

private func collectSceneNodeGizmo(
    scene: MetalScene,
    nodeIndex: Int,
    span: Float,
    canvasAspect: Float,
    selected: Bool,
    line: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void
) {
    guard scene.asset.nodes.indices.contains(nodeIndex),
          let world = scene.worldMatrix(ofNode: nodeIndex) else { return }
    let node = scene.asset.nodes[nodeIndex]
    if let camera = node.camera {
        collectCameraFrustum(world: world, camera: camera, span: span, canvasAspect: canvasAspect,
                             selected: selected, line: line)
        return
    }
    if let light = node.light {
        collectLightGizmo(world: world, light: light, span: span,
                          color: sceneLightGizmoColor(light: light, selected: selected), line: line)
    }
}

private func collectSelectionGizmo(
    scene: MetalScene,
    nodeIndex: Int,
    span: Float,
    canvasAspect: Float,
    useSilhouetteSelectionOutline: Bool,
    line: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void
) {
    guard scene.asset.nodes.indices.contains(nodeIndex),
          let world = scene.worldMatrix(ofNode: nodeIndex) else { return }
    let node = scene.asset.nodes[nodeIndex]

    if let camera = node.camera {
        collectCameraFrustum(world: world, camera: camera, span: span, canvasAspect: canvasAspect,
                             selected: true, line: line)
        return
    }

    if let light = node.light {
        collectLightGizmo(world: world, light: light, span: span, color: OverlayGizmoColors.selectedScene, line: line)
        return
    }

    if isSkinJoint(nodeIndex, scene: scene) { return }

    if useSilhouetteSelectionOutline,
       usesSilhouetteSelectionOutline(nodeIndex: nodeIndex, scene: scene) { return }

    if node.mesh == nil, scene.nodeParents.indices.contains(nodeIndex), scene.nodeParents[nodeIndex] >= 0 {
        let parent = scene.nodeParents[nodeIndex]
        if let parentWorld = scene.worldMatrix(ofNode: parent) {
            let a = SIMD3(parentWorld.columns.3.x, parentWorld.columns.3.y, parentWorld.columns.3.z)
            let b = SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
            line(a, b, OverlayGizmoColors.selectionHighlight)
            return
        }
    }

    collectNodeAABB(scene: scene, nodeIndex: nodeIndex, color: OverlayGizmoColors.selectionHighlight, line: line)
}

private func collectNodeAABB(
    scene: MetalScene,
    nodeIndex: Int,
    color: SIMD3<Float>,
    line: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void
) {
    guard let box = scene.bounds(ofNode: nodeIndex) else { return }
    let size = box.max - box.min
    let pad = 0.01 * max(size.x, size.y, size.z, 0.01)
    let a = box.min - pad, b = box.max + pad
    let corners: [SIMD3<Float>] = [
        SIMD3(a.x, a.y, a.z), SIMD3(b.x, a.y, a.z), SIMD3(a.x, b.y, a.z), SIMD3(b.x, b.y, a.z),
        SIMD3(a.x, a.y, b.z), SIMD3(b.x, a.y, b.z), SIMD3(a.x, b.y, b.z), SIMD3(b.x, b.y, b.z),
    ]
    let edges = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
    for (i, j) in edges { line(corners[i], corners[j], color) }
}

private func cameraAxes(from world: simd_float4x4) -> (eye: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>, right: SIMD3<Float>) {
    let eye = SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    let forward = simd_normalize(-SIMD3(world.columns.2.x, world.columns.2.y, world.columns.2.z))
    let up = simd_normalize(SIMD3(world.columns.1.x, world.columns.1.y, world.columns.1.z))
    let right = simd_normalize(SIMD3(world.columns.0.x, world.columns.0.y, world.columns.0.z))
    return (eye, forward, up, right)
}

private func rectangleCorners(center: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>,
                              halfWidth: Float, halfHeight: Float) -> [SIMD3<Float>] {
    [
        center - right * halfWidth - up * halfHeight,
        center + right * halfWidth - up * halfHeight,
        center + right * halfWidth + up * halfHeight,
        center - right * halfWidth + up * halfHeight,
    ]
}

private func collectCameraFrustum(
    world: simd_float4x4,
    camera: GLTFCamera,
    span: Float,
    canvasAspect: Float,
    selected: Bool,
    line: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void
) {
    let (eye, forward, up, right) = cameraAxes(from: world)
    let znear = camera.zNear
    let distance = max(znear, 0.15 * span)
    let color = selected ? OverlayGizmoColors.selectedScene : OverlayGizmoColors.mutedScene

    if let perspective = camera.perspective {
        let halfHeight = distance * Float(tan(perspective.yFOV / 2))
        let aspect = perspective.aspectRatio > 0 ? Float(perspective.aspectRatio) : canvasAspect
        let halfWidth = halfHeight * aspect
        let center = eye + forward * distance
        let corners = rectangleCorners(center: center, right: right, up: up, halfWidth: halfWidth, halfHeight: halfHeight)
        for corner in corners { line(eye, corner, color) }
        for i in 0..<4 { line(corners[i], corners[(i + 1) % 4], color) }
        if selected {
            let topLeft = corners[2], topRight = corners[3]
            let mid = (topLeft + topRight) * 0.5
            let edge = simd_distance(topLeft, topRight)
            let triHalf = edge / 6
            let baseLeft = mid - right * triHalf
            let baseRight = mid + right * triHalf
            let apex = mid + up * triHalf
            line(baseLeft, baseRight, OverlayGizmoColors.axisBlue)
            line(baseLeft, apex, OverlayGizmoColors.axisBlue)
            line(baseRight, apex, OverlayGizmoColors.axisBlue)
        }
        return
    }

    if let orthographic = camera.orthographic {
        let halfWidth = orthographic.xMag
        let halfHeight = orthographic.yMag
        let nearCenter = eye + forward * znear
        let farCenter = eye + forward * distance
        let near = rectangleCorners(center: nearCenter, right: right, up: up, halfWidth: halfWidth, halfHeight: halfHeight)
        let far = rectangleCorners(center: farCenter, right: right, up: up, halfWidth: halfWidth, halfHeight: halfHeight)
        for i in 0..<4 { line(near[i], near[(i + 1) % 4], color) }
        for i in 0..<4 { line(far[i], far[(i + 1) % 4], color) }
        for i in 0..<4 { line(near[i], far[i], color) }
    }
}

private func collectLightGizmo(
    world: simd_float4x4,
    light: GLTFLight,
    span: Float,
    color: SIMD3<Float>,
    line: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void
) {
    let origin = SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    let emission = world * SIMD4(0, 0, -1, 0)
    let direction = simd_normalize(SIMD3(emission.x, emission.y, emission.z))

    switch light.type {
    case .directional:
        let axis: SIMD3<Float> = abs(direction.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let plateRight = simd_normalize(simd_cross(direction, axis))
        let plateUp = simd_normalize(simd_cross(plateRight, direction))
        let half = span * 0.02
        let plate = [
            origin + plateRight * half + plateUp * half,
            origin - plateRight * half + plateUp * half,
            origin - plateRight * half - plateUp * half,
            origin + plateRight * half - plateUp * half,
        ]
        for i in 0..<4 { line(plate[i], plate[(i + 1) % 4], color) }
        line(origin, origin + direction * span * 0.5, color)
    case .point:
        let size = span * 0.03
        let tips: [SIMD3<Float>] = [
            origin + SIMD3(size, 0, 0), origin - SIMD3(size, 0, 0),
            origin + SIMD3(0, size, 0), origin - SIMD3(0, size, 0),
            origin + SIMD3(0, 0, size), origin - SIMD3(0, 0, size),
        ]
        let pairs = [(0, 2), (0, 3), (0, 4), (0, 5), (1, 2), (1, 3), (1, 4), (1, 5), (2, 4), (2, 5), (3, 4), (3, 5)]
        for (a, b) in pairs { line(tips[a], tips[b], color) }
    case .spot:
        let range = light.range > 0 ? light.range : span * 0.25
        let outerRadius = range * Float(tan(light.outerConeAngle))
        let innerRadius = range * Float(tan(light.innerConeAngle))
        let end = origin + direction * range
        let axis: SIMD3<Float> = abs(direction.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let coneRight = simd_normalize(simd_cross(direction, axis))
        let coneUp = simd_normalize(simd_cross(coneRight, direction))
        line(origin, origin + direction * (range * 0.92), color)
        let segments = 32
        let innerColor = color * 0.55
        func ring(at center: SIMD3<Float>, r: Float, ringColor: SIMD3<Float>) {
            var previous: SIMD3<Float>?
            for i in 0...segments {
                let a = Double(i) / Double(segments) * .pi * 2
                let c = Float(cos(a)), s = Float(sin(a))
                let p = center + coneRight * (c * r) + coneUp * (s * r)
                if let previous { line(previous, p, ringColor) }
                previous = p
            }
        }
        ring(at: end, r: outerRadius, ringColor: color)
        ring(at: end, r: innerRadius, ringColor: innerColor)
        for i in 0..<4 {
            let a = Double(i) / 4 * .pi * 2
            let c = Float(cos(a)), s = Float(sin(a))
            let edge = end + coneRight * (c * outerRadius) + coneUp * (s * outerRadius)
            line(origin, edge, color)
        }
    @unknown default:
        break
    }
}

extension MetalRenderer {
    /// Draws `lines` over the tonemapped `output` the way the viewer draws them over its canvas.
    /// `viewProjection` is the user camera's WebGL clip transform; `viewport` the Khronos one.
    /// `sceneDepth` is the stored main-pass depth; with `occlude`, lines behind the model are
    /// discarded. Skip that when a file camera drew the model: the depths would not match.
    func encodeOverlays(_ lines: [MetalLineVertex], command: any MTLCommandBuffer, output: any MTLTexture,
                        viewProjection: simd_float4x4, viewport: MTLViewport,
                        sceneDepth: any MTLTexture, occlude: Bool,
                        selectionIDs: (any MTLTexture)? = nil) throws {
        let samples = 4
        if overlayPipeline == nil || overlayCopyPipeline == nil || (selectionIDs != nil && selectionOutlinePipeline == nil) {
            let line = MTLRenderPipelineDescriptor()
            line.vertexFunction = library.makeFunction(name: "khronos_line_vertex")
            line.fragmentFunction = library.makeFunction(name: "khronos_line_fragment")
            line.colorAttachments[0].pixelFormat = output.pixelFormat
            line.rasterSampleCount = samples
            overlayPipeline = try device.makeRenderPipelineState(descriptor: line)
            let copy = MTLRenderPipelineDescriptor()
            copy.vertexFunction = library.makeFunction(name: "khronos_tonemap_vertex")
            copy.fragmentFunction = library.makeFunction(name: "khronos_overlay_copy_fragment")
            copy.colorAttachments[0].pixelFormat = output.pixelFormat
            copy.rasterSampleCount = samples
            overlayCopyPipeline = try device.makeRenderPipelineState(descriptor: copy)
        }
        if selectionIDs != nil, selectionOutlinePipeline == nil {
            let outline = MTLRenderPipelineDescriptor()
            outline.vertexFunction = library.makeFunction(name: "khronos_tonemap_vertex")
            outline.fragmentFunction = library.makeFunction(name: "khronos_selection_outline_fragment")
            outline.colorAttachments[0].pixelFormat = output.pixelFormat
            outline.rasterSampleCount = samples
            outline.colorAttachments[0].isBlendingEnabled = true
            outline.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            outline.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            outline.colorAttachments[0].sourceAlphaBlendFactor = .one
            outline.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            selectionOutlinePipeline = try device.makeRenderPipelineState(descriptor: outline)
        }
        guard let linePipeline = overlayPipeline, let copyPipeline = overlayCopyPipeline else {
            throw MetalRendererError.resource("overlay pipelines")
        }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DMultisample
        descriptor.pixelFormat = output.pixelFormat
        descriptor.width = output.width
        descriptor.height = output.height
        descriptor.sampleCount = samples
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget]
        guard let multisample = device.makeTexture(descriptor: descriptor) else {
            throw MetalRendererError.resource("overlay MSAA target")
        }
        // The frame is resolved back into `output`, so read a copy of it.
        let copyDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: output.pixelFormat,
            width: output.width, height: output.height, mipmapped: false)
        copyDescriptor.storageMode = .private
        copyDescriptor.usage = [.shaderRead]
        guard let frame = device.makeTexture(descriptor: copyDescriptor), let blit = command.makeBlitCommandEncoder() else {
            throw MetalRendererError.resource("overlay frame copy")
        }
        blit.copy(from: output, to: frame)
        blit.endEncoding()
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = multisample
        pass.colorAttachments[0].resolveTexture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .multisampleResolve
        // WebGL draws its canvas bottom-up, so the standard 4× pattern lands mirrored in the
        // image the viewer reads back. Mirror it here so line coverage matches sample for sample.
        if device.areProgrammableSamplePositionsSupported {
            pass.setSamplePositions(device.getDefaultSamplePositions(sampleCount: samples).map {
                MTLSamplePosition(x: $0.x, y: 1 - $0.y)
            })
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw MetalRendererError.resource("overlays")
        }
        let lineBuffer = lines.withUnsafeBytes { raw -> (any MTLBuffer)? in
            guard raw.count > 0, let base = raw.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
        if !lines.isEmpty, lineBuffer == nil { throw MetalRendererError.resource("overlay line buffer") }
        encoder.label = "Overlays"
        encoder.setRenderPipelineState(copyPipeline)
        encoder.setFragmentTexture(frame, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if let selectionIDs, let outlinePipeline = selectionOutlinePipeline {
            encoder.setRenderPipelineState(outlinePipeline)
            encoder.setFragmentTexture(selectionIDs, index: 0)
            var accent = Self.selectionOutlineAccent
            encoder.setFragmentBytes(&accent, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if let lineBuffer {
            encoder.setViewport(viewport)
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBuffer(lineBuffer, offset: 0, index: 0)
            var matrix = viewProjection
            encoder.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.stride, index: 1)
            var occludeFlag: UInt32 = occlude ? 1 : 0
            encoder.setFragmentBytes(&occludeFlag, length: MemoryLayout<UInt32>.stride, index: 0)
            encoder.setFragmentTexture(sceneDepth, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lines.count)
        }
        encoder.endEncoding()
    }
}
