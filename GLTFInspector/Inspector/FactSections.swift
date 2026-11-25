import GLTFCore
import simd
import Renderer
import SwiftUI

// Read-only fact blocks for the inspector, one per glTF entry type.

struct CameraSection: View {
    var camera: GLTFDocument.Camera

    var body: some View {
        FactBlock("Camera") {
            DSFactRow("Projection", value: camera.type == "orthographic" ? "Orthographic" : "Perspective")
            if let yfov = camera.yfov {
                DSFactRow("Field of view", value: String(format: "%.1f°", yfov * 180 / .pi))
            }
            if let xmag = camera.xmag {
                DSFactRow("X mag", value: String(format: "%.2f", xmag))
            }
            if let ymag = camera.ymag {
                DSFactRow("Y mag", value: String(format: "%.2f", ymag))
            }
            DSFactRow("Near", value: String(format: "%.2f", camera.znear))
            if let zfar = camera.zfar {
                DSFactRow("Far", value: String(format: "%.1f", zfar))
            }
        }
    }
}

struct LightSection: View {
    var light: GLTFDocument.Light

    var body: some View {
        FactBlock("Light") {
            DSFactRow("Kind", value: light.type.capitalized)
            DSFactRow("Intensity", value: Double(light.intensity).formatted())
            if let range = light.range {
                DSFactRow("Range", value: String(format: "%.1f", range))
            }
            if let inner = light.innerCone {
                DSFactRow("Inner cone", value: String(format: "%.1f°", inner * 180 / .pi))
            }
            if let outer = light.outerCone {
                DSFactRow("Outer cone", value: String(format: "%.1f°", outer * 180 / .pi))
            }
        }
    }
}

struct AnimationSection: View {
    var animation: GLTFDocument.Animation
    var document: GLTFDocument
    var onSelect: ((NodeID) -> Void)?

    var body: some View {
        FactBlock("Animation") {
            DSFactRow("Duration", value: Self.durationText(animation.duration))
            if animation.keyframeCount > 0 {
                DSFactRow("Keyframes", value: animation.keyframeCount.formatted())
            }
            if !animation.paths.isEmpty {
                DSFactRow("Drives", value: animation.paths.map(\.title).joined(separator: ", "))
            }
            if !animation.interpolations.isEmpty {
                DSFactRow("Interpolation",
                          value: animation.interpolations.map(\.title).joined(separator: ", "))
            }
            if animation.channelCount > 0 {
                DSFactRow("Channels", value: animation.channelCount.formatted())
            }
            if !animation.targetNodeIndices.isEmpty {
                DSFactRow("Targets", value: animation.targetNodeIndices.count.formatted())
                NodeLinkList(document: document, nodeIndices: animation.targetNodeIndices, onSelect: onSelect)
            }
        }
    }

    private static func durationText(_ seconds: Double) -> String {
        seconds >= 60
            ? "\(Int(seconds) / 60)m \(Int(seconds) % 60)s"
            : String(format: "%.1fs", seconds)
    }
}

struct SkinSection: View {
    var skin: GLTFDocument.Skin
    var document: GLTFDocument
    var onSelect: ((NodeID) -> Void)?

    var body: some View {
        FactBlock("Skin") {
            DSFactRow("Joints", value: skin.jointNames.count.formatted())
            NodeLinkList(document: document, nodeIndices: skin.jointNodeIndices,
                         fallbackNames: skin.jointNames, onSelect: onSelect)
            if let root = skin.skeletonNodeIndex, let id = document.id(ofNode: root) {
                DSFactRow("Skeleton root", value: document.displayName(of: id))
            }
            if skin.influenceSetCount > 0 {
                DSFactRow("Influences", value: "\(skin.influencesPerVertex.formatted()) per vertex")
            }
            // Identity bind matrices are legal but rare; saying which one the file uses explains a
            // skin that draws in the wrong place.
            DSFactRow("Bind matrices", value: skin.storesInverseBindMatrices ? "Stored" : "Identity")
            if !skin.skinnedMeshNames.isEmpty {
                DSFactRow("Deforms", value: skin.skinnedMeshNames.joined(separator: ", "))
            }
        }
    }
}

/// Node names as rows that select the node, falling back to plain text for a node the outliner
/// has no row for.
private struct NodeLinkList: View {
    var document: GLTFDocument
    var nodeIndices: [Int]
    var fallbackNames: [String] = []
    var onSelect: ((NodeID) -> Void)?

    /// A rig can list hundreds of joints; past this the list stops being readable and the
    /// outliner is the better place to browse them.
    private static let limit = 24

    var body: some View {
        FlexibleChipRow {
            ForEach(Array(nodeIndices.prefix(Self.limit).enumerated()), id: \.offset) { offset, nodeIndex in
                let id = document.id(ofNode: nodeIndex)
                let name = id.map { document.displayName(of: $0) }
                    ?? (fallbackNames.indices.contains(offset) ? fallbackNames[offset] : "Node \(nodeIndex)")
                if let id, let onSelect {
                    // Same contract as `UsedBySection`: VoiceOver reads the name, and selecting is
                    // an action — a label of "Select Hip" would be read as the joint's name.
                    Button { onSelect(id) } label: { DSChip(name) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Select \(name)") { onSelect(id) }
                } else {
                    DSChip(name)
                }
            }
            if nodeIndices.count > Self.limit {
                DSChip("+\((nodeIndices.count - Self.limit).formatted()) more")
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}

struct PrimitivesSection: View {
    var document: GLTFDocument
    var node: GLTFDocument.Node
    var onSelect: ((NodeID) -> Void)?

    var body: some View {
        FactBlock("Primitives") {
            ForEach(Array(node.meshPrimitives.enumerated()), id: \.offset) { index, primitive in
                primitiveRow(index: index, primitive: primitive)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primitives")
    }

    @ViewBuilder
    private func primitiveRow(index: Int, primitive: GLTFDocument.MeshPrimitive) -> some View {
        let label = "Primitive \(index + 1)"
        if let materialIndex = primitive.materialIndex, document.materials.indices.contains(materialIndex) {
            let material = document.materials[materialIndex]
            let materialName = document.displayName(of: NodeID(kind: .material, index: materialIndex))
            let triLabel = "\(primitive.triangleCount.formatted()) tris"
            Button {
                onSelect?(NodeID(kind: .material, index: materialIndex))
            } label: {
                DSFactRow(label) {
                    HStack(spacing: DS.Spacing.s) {
                        MaterialSwatch(color: swatchColor(for: material), size: 12)
                        Text("\(materialName) · \(triLabel)")
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label), \(materialName), \(triLabel)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Select \(materialName)") {
                onSelect?(NodeID(kind: .material, index: materialIndex))
            }
        } else {
            DSFactRow(label, value: "\(primitive.triangleCount.formatted()) tris")
        }
    }

    private func swatchColor(for material: GLTFDocument.Material) -> Color {
        if let factor = material.baseColorFactor {
            return Color(.sRGB,
                         red: Double(simd_clamp(factor.x, 0, 1)),
                         green: Double(simd_clamp(factor.y, 0, 1)),
                         blue: Double(simd_clamp(factor.z, 0, 1)))
        }
        return Color(.quaternaryLabelColor)
    }
}

struct JointOfSection: View {
    var document: GLTFDocument
    var skinIndices: [Int]

    var body: some View {
        FactBlock("Skin") {
            ForEach(skinIndices, id: \.self) { skinIndex in
                DSFactRow("Joint of", value: document.displayName(of: NodeID(kind: .skin, index: skinIndex)))
            }
        }
    }
}

struct MorphSection: View {
    var morph: GLTFDocument.Morph
    var meshName: String
    var document: GLTFDocument
    @Bindable var canvas: ModelCanvasController

    var body: some View {
        FactBlock("Morph") {
            DSFactRow("Mesh", value: meshName)
            DSFactRow("Targets", value: morph.targetNames.count.formatted())
            if !morph.targetAttributes.isEmpty {
                DSFactRow("Displaces", value: morph.targetAttributes
                    .map { $0.capitalized }
                    .joined(separator: ", "))
            }
            if morph.primitiveCount > 1 {
                DSFactRow("Primitives", value: morph.primitiveCount.formatted())
            }
            MorphLiveWeightRows(morph: morph, document: document, canvas: canvas)
        }
    }
}

/// Live morph weights read from the canvas pose without re-rendering the whole inspector.
struct MorphLiveWeightRows: View {
    var morph: GLTFDocument.Morph
    var document: GLTFDocument
    @Bindable var canvas: ModelCanvasController
    @State private var liveWeights: [Float]?

    var body: some View {
        Group {
            if let pose {
                DSSectionHeader(pose.header)
                    .padding(.top, DS.Spacing.m)
                    .padding(.bottom, DS.Spacing.xxs)
                ForEach(Array(pose.values.enumerated()), id: \.offset) { index, weight in
                    let name = morph.targetNames.indices.contains(index) ? morph.targetNames[index] : "Target \(index + 1)"
                    DSFactRow(name, value: String(format: "%.3f", weight))
                }
            } else {
                NameList(names: morph.targetNames)
            }
        }
        .task(id: morph.meshIndex) {
            while !Task.isCancelled {
                let next = Self.weights(for: morph, document: document, canvas: canvas)
                if next != liveWeights { liveWeights = next }
                do {
                    try await Task.sleep(for: .milliseconds(80))
                } catch {
                    return
                }
            }
        }
    }

    /// The live pose while an animation drives the targets; at rest the file's own
    /// `meshes[].weights`, which is what the viewer draws until one does.
    private var pose: (header: String, values: [Float])? {
        if let live = liveWeights, !live.isEmpty {
            return ("Weights", live)
        }
        return morph.defaultWeights.isEmpty ? nil : ("Rest weights", morph.defaultWeights)
    }

    static func weights(for morph: GLTFDocument.Morph, document: GLTFDocument,
                        canvas: ModelCanvasController) -> [Float]? {
        guard let pose = canvas.currentAnimationPose() else { return nil }
        for nodeIndex in document.nodes.indices where document.nodes[nodeIndex].meshIndex == morph.meshIndex {
            if let weights = pose.nodeWeights[nodeIndex], !weights.isEmpty {
                return weights
            }
        }
        if document.morphs.count == 1, let weights = pose.nodeWeights.values.first(where: { !$0.isEmpty }) {
            return weights
        }
        if let meshWeights = pose.meshWeights[morph.meshIndex], !meshWeights.isEmpty {
            return meshWeights
        }
        return nil
    }
}

/// A section header over fact rows, with the inspector's insets.
struct FactBlock<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.m)
        }
    }
}

private struct NameList: View {
    var names: [String]

    var body: some View {
        if !names.isEmpty {
            Text(names.joined(separator: ", "))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, DS.Spacing.xs)
        }
    }
}

/// Left-to-right wrap of chips. How many fit depends on the pane width. A chip with an action
/// selects what it names; one without is a plain tag.
struct FlexibleChipRow<Chips: View>: View {
    @ViewBuilder var chips: Chips

    var body: some View {
        DSFlowLayout { chips }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension FlexibleChipRow where Chips == ForEach<[String], String, DSChip> {
    /// Plain tags.
    init(items: [String]) {
        self.init { ForEach(items, id: \.self) { DSChip($0) } }
    }
}

/// Small colour tile for material factor readouts and map thumbnails.
struct MaterialSwatch: View {
    var color: Color
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        shape
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                shape.strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline)
            }
            .accessibilityHidden(true)
    }
}

/// `DSSectionHeader` with the inspector's section rhythm: `l` sides, `xs` below, `xl` above
/// (`m` for the sidebar-footer sections). Section bodies keep their own padding.
struct InspectorSectionHeader: View {
    var title: String
    var top: CGFloat = DS.Spacing.xl

    init(_ title: String, top: CGFloat = DS.Spacing.xl) {
        self.title = title
        self.top = top
    }

    var body: some View {
        DSSectionHeader(title)
            .padding(.top, top)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.xs)
    }
}
