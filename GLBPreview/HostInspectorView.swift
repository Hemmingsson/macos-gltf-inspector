import AppKit
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct HostInspectorView: View {
    var session: ViewerSession?

    var body: some View {
        Group {
            if let session {
                InspectorForm(session: session)
            } else {
                Text("Inspector")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(HostColumnChrome())
    }
}

private struct InspectorForm: View {
    @Bindable var session: ViewerSession

    var body: some View {
        Form {
            if let inspectorError = session.inspectorError {
                Text(inspectorError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Section("Background") {
                Toggle("Environment Map", isOn: $session.showEnvironmentMap)
                Toggle("Blur", isOn: $session.blurEnvironment)
                ColorPicker("Background Color", selection: $session.backgroundColor, supportsOpacity: false)
                Picker("Environment Rotation", selection: $session.environmentRotation) {
                    ForEach(ViewerSession.EnvironmentRotation.allCases, id: \.self) { rotation in
                        Text(rotation.rawValue).tag(rotation)
                    }
                }
                Picker("Active Environment", selection: activeEnvironment) {
                    ForEach(GLBKhronosEnvironments.all, id: \.self) { environment in
                        Text(environment.title).tag("catalog:" + environment.rawValue)
                    }
                    ForEach(session.userHDRs, id: \.self) { url in
                        Text(url.lastPathComponent).tag("user:" + url.absoluteString)
                    }
                }
                Button("Add New HDR") {
                    addHDR()
                }
            }

            Section("Lighting") {
                Toggle("Image Based", isOn: $session.imageBased)
                Toggle("Punctual", isOn: $session.punctualLights)
                Slider(value: iblLogIntensity, in: log10(0.01)...log10(10_000)) {
                    Text("IBL Intensity")
                }
                Slider(value: $session.exposure, in: 0...64) {
                    Text("Exposure")
                }
                .disabled(!exposureEnabled)
                Picker("Tone Map", selection: $session.toneMap) {
                    ForEach(ViewerSession.ToneMap.allCases, id: \.self) { toneMap in
                        Text(toneMap.title).tag(toneMap)
                    }
                }
                .disabled(!toneMapEnabled)
            }

            Section("Debug") {
                Picker("Mode", selection: $session.debug) {
                    ForEach(ViewerSession.DebugMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            if case .node(let index) = session.selected, let node = session.node(at: index) {
                NodeDetailSection(session: session, node: node)
            }

            if case .animation(let index) = session.selected,
               session.document.animations.indices.contains(index)
            {
                AnimationDetailSection(animation: session.document.animations[index], index: index)
            }
        }
        .formStyle(.grouped)
        .onChange(of: session.imageBased) { _, _ in session.applyIfBound() }
        .onChange(of: session.punctualLights) { _, _ in session.applyIfBound() }
        .onChange(of: session.iblIntensity) { _, _ in session.applyIfBound() }
        .onChange(of: session.environment) { _, _ in session.applyIfBound() }
        .onChange(of: session.environmentRotation) { _, _ in session.applyIfBound() }
        .onChange(of: session.selectedUserHDR) { _, _ in session.applyIfBound() }
        .onChange(of: session.debug) { _, _ in session.applyIfBound() }
    }

    private var exposureEnabled: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    private var toneMapEnabled: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    private var iblLogIntensity: Binding<Float> {
        Binding(
            get: { log10(max(session.iblIntensity, 0.01)) },
            set: { session.iblIntensity = pow(10, $0) }
        )
    }

    private var activeEnvironment: Binding<String> {
        Binding(
            get: {
                if let url = session.selectedUserHDR {
                    return "user:" + url.absoluteString
                }
                return "catalog:" + session.environment.rawValue
            },
            set: { newValue in
                if newValue.hasPrefix("user:") {
                    let raw = String(newValue.dropFirst(5))
                    session.selectedUserHDR = session.userHDRs.first { $0.absoluteString == raw }
                } else if newValue.hasPrefix("catalog:"),
                          let environment = GLBKhronosEnvironments(rawValue: String(newValue.dropFirst(8)))
                {
                    session.environment = environment
                    session.selectedUserHDR = nil
                }
            }
        )
    }

    private func addHDR() {
        let panel = NSOpenPanel()
        panel.title = "Add New HDR"
        panel.allowedContentTypes = [UTType(filenameExtension: "hdr") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        guard GLBPreviewLighting.canDecodeHDR(at: url) else {
            session.inspectorError = "Could not load HDR"
            return
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-hdr-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            session.userHDRs.append(dest)
            session.selectedUserHDR = dest
            session.inspectorError = nil
        } catch {
            session.inspectorError = "Could not load HDR"
        }
    }
}

private struct NodeDetailSection: View {
    var session: ViewerSession
    var node: GLTFSessionDocument.Node

    var body: some View {
        Section("Node") {
            LabeledContent("Name", value: node.name.isEmpty ? "Node \(node.index)" : node.name)
            LabeledContent("Translation", value: format3(node.translation))
            LabeledContent("Rotation", value: format4(node.rotation))
            LabeledContent("Scale", value: format3(node.scale))
            LabeledContent("Children", value: "\(node.children.count)")
            if let meshIndex = node.meshIndex, session.document.meshes.indices.contains(meshIndex) {
                let mesh = session.document.meshes[meshIndex]
                LabeledContent("Triangles", value: "\(mesh.triangleCount)")
                LabeledContent("Vertices", value: "\(mesh.vertexCount)")
                if let aabb = worldAABB {
                    LabeledContent("World AABB", value: "\(format3(aabb.min)) … \(format3(aabb.max))")
                }
                MaterialCard(material: resolvedMaterial(for: mesh))
            }
        }
    }

    private var worldAABB: BoundingBox? {
        guard let root = session.boundRoot,
              let entity = session.entity(nodeIndex: node.index, in: root)
        else { return nil }
        return GLBPreviewCamera.modelBounds(of: entity)
    }

    private func resolvedMaterial(for mesh: GLTFSessionDocument.Mesh) -> GLTFSessionDocument.Material {
        let index = mesh.materialIndices.first ?? 0
        if session.document.materials.indices.contains(index) {
            return session.document.materials[index]
        }
        return .init(
            name: "Default",
            baseColorFactor: SIMD4<Float>(1, 1, 1, 1),
            metallicFactor: 1,
            roughnessFactor: 1,
            emissiveFactor: .zero,
            alphaMode: "OPAQUE",
            hasBaseColorTexture: false,
            hasMetallicRoughnessTexture: false,
            hasNormalTexture: false,
            hasOcclusionTexture: false,
            hasEmissiveTexture: false
        )
    }
}

private struct AnimationDetailSection: View {
    var animation: GLTFSessionDocument.Animation
    var index: Int

    var body: some View {
        Section("Animation") {
            LabeledContent("Name", value: animation.name.isEmpty ? "Animation \(index)" : animation.name)
            LabeledContent("Duration", value: String(format: "%.3f s", animation.duration))
        }
    }
}

private struct MaterialCard: View {
    var material: GLTFSessionDocument.Material

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(material.name.isEmpty ? "Default" : material.name)
                .font(.headline)
            LabeledContent("Metallic", value: format1(material.metallicFactor))
            LabeledContent("Roughness", value: format1(material.roughnessFactor))
            LabeledContent(
                "Base Color",
                value: String(
                    format: "%.2f %.2f %.2f %.2f",
                    material.baseColorFactor.x,
                    material.baseColorFactor.y,
                    material.baseColorFactor.z,
                    material.baseColorFactor.w
                )
            )
        }
        .padding(.vertical, 4)
    }
}

private func format1(_ value: Float) -> String {
    String(format: "%.2f", value)
}

private func format3(_ value: SIMD3<Float>) -> String {
    String(format: "%.3f %.3f %.3f", value.x, value.y, value.z)
}

private func format4(_ value: SIMD4<Float>) -> String {
    String(format: "%.3f %.3f %.3f %.3f", value.x, value.y, value.z, value.w)
}
