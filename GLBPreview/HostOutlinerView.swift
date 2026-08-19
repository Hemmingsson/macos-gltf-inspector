import SwiftUI

struct HostOutlinerView: View {
    var model: GLBEntityLoader.LoadedModel?
    var session: ViewerSession?

    var body: some View {
        Group {
            if let session {
                OutlinerContent(model: model, session: session)
            } else {
                Text("Outliner")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(HostColumnChrome())
    }
}

private struct OutlinerContent: View {
    var model: GLBEntityLoader.LoadedModel?
    @Bindable var session: ViewerSession

    private var document: GLTFSessionDocument {
        model?.document ?? session.document
    }

    private var statRows: [String] {
        if let model {
            return model.stats.previewRows
        }
        return documentPreviewRows(document)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model")
                .font(.headline)
            ForEach(statRows, id: \.self) { row in
                Text(row)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !document.scenes.isEmpty {
                Picker("Scene", selection: $session.activeSceneIndex) {
                    ForEach(document.scenes.indices, id: \.self) { index in
                        Text(sceneTitle(document.scenes[index], index: index)).tag(index)
                    }
                }
            }
            Picker("Camera", selection: $session.selectedCameraIndex) {
                Text("Fit").tag(Optional<Int>.none)
                ForEach(document.cameras.indices, id: \.self) { index in
                    Text(cameraTitle(document.cameras[index], index: index)).tag(Optional(index))
                }
            }
            Text("Layer List")
                .font(.headline)
            List(selection: layerSelection) {
                OutlineGroup(layerRoots, children: \.children) { row in
                    Text(row.title)
                        .tag(row.id)
                }
            }
            .listStyle(.sidebar)
        }
        .onChange(of: session.activeSceneIndex) { _, _ in
            session.selected = .none
        }
    }

    private var layerSelection: Binding<Int?> {
        Binding(
            get: {
                if case .node(let index) = session.selected { return index }
                return nil
            },
            set: { newValue in
                if let newValue {
                    session.selected = .node(newValue)
                } else {
                    session.selected = .none
                }
            }
        )
    }

    private var layerRoots: [LayerRow] {
        session.layerRootIndices().compactMap { LayerRow(index: $0, nodes: document.nodes) }
    }
}

private func sceneTitle(_ scene: GLTFSessionDocument.Scene, index: Int) -> String {
    scene.name.isEmpty ? "Scene \(index)" : scene.name
}

private func cameraTitle(_ camera: GLTFSessionDocument.Camera, index: Int) -> String {
    camera.name.isEmpty ? "Camera \(index)" : camera.name
}

private func documentPreviewRows(_ document: GLTFSessionDocument) -> [String] {
    var rows: [String] = []
    if !document.meshes.isEmpty { rows.append("Meshes \(document.meshes.count)") }
    if !document.materials.isEmpty { rows.append("Materials \(document.materials.count)") }
    if !document.animations.isEmpty { rows.append("Animations \(document.animations.count)") }
    if !document.nodes.isEmpty { rows.append("Nodes \(document.nodes.count)") }
    return rows
}

private struct LayerRow: Identifiable, Hashable {
    let id: Int
    let title: String
    let children: [LayerRow]?

    init?(index: Int, nodes: [GLTFSessionDocument.Node]) {
        guard let node = nodes.first(where: { $0.index == index }) ?? nodes[safe: index] else {
            return nil
        }
        id = node.index
        title = node.name.isEmpty ? "Node \(node.index)" : node.name
        let childRows = node.children.compactMap { LayerRow(index: $0, nodes: nodes) }
        children = childRows.isEmpty ? nil : childRows
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
