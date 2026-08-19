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
            if !document.variants.isEmpty {
                Picker("Variant", selection: $session.variantIndex) {
                    ForEach(document.variants.indices, id: \.self) { index in
                        Text(variantTitle(document.variants[index], index: index)).tag(index)
                    }
                }
            }
            if !document.animations.isEmpty {
                animationTransport
            }
            HStack {
                Text("Layer List")
                    .font(.headline)
                Spacer()
                Button("Show all") {
                    session.showAll()
                    session.applyIfBound()
                }
                .disabled(session.hide.isEmpty && session.soloRoot == nil)
            }
            List(selection: layerSelection) {
                OutlineGroup(layerRoots, children: \.children) { row in
                    LayerRowView(row: row, session: session)
                        .tag(row.id)
                }
            }
            .listStyle(.sidebar)
        }
        .onChange(of: session.activeSceneIndex) { _, _ in
            session.selected = .none
        }
        .onChange(of: session.variantIndex) { _, _ in
            session.applyIfBound()
        }
        .task(id: session.isPlaying) {
            guard session.isPlaying else { return }
            while !Task.isCancelled {
                session.syncPlaybackTime()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private var animationTransport: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    session.togglePlay()
                } label: {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                }
                .help(session.isPlaying ? "Pause" : "Play")
                Slider(
                    value: playbackTime,
                    in: 0...max(session.clipDuration, 0.001)
                )
                .disabled(session.clipDuration <= 0)
            }
            ForEach(document.animations.indices, id: \.self) { index in
                HStack {
                    Toggle(isOn: clipEnabled(index)) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .help("Enable clip")
                    Button(animationTitle(document.animations[index], index: index)) {
                        session.selected = .animation(index)
                    }
                    .buttonStyle(.plain)
                    .fontWeight(isSelectedAnimation(index) ? .semibold : .regular)
                }
            }
        }
    }

    private var playbackTime: Binding<TimeInterval> {
        Binding(
            get: { session.currentTime },
            set: { session.seek(to: $0) }
        )
    }

    private func clipEnabled(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { session.enabledClipIndices.contains(index) },
            set: { session.setClipEnabled(index, enabled: $0) }
        )
    }

    private func isSelectedAnimation(_ index: Int) -> Bool {
        if case .animation(let selected) = session.selected {
            return selected == index
        }
        return false
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
                } else if case .node = session.selected {
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

private func animationTitle(_ animation: GLTFSessionDocument.Animation, index: Int) -> String {
    animation.name.isEmpty ? "Animation \(index)" : animation.name
}

private func variantTitle(_ variant: GLTFSessionDocument.Variant, index: Int) -> String {
    variant.name.isEmpty ? "Variant \(index)" : variant.name
}

private func documentPreviewRows(_ document: GLTFSessionDocument) -> [String] {
    var rows: [String] = []
    if !document.meshes.isEmpty { rows.append("Meshes \(document.meshes.count)") }
    if !document.materials.isEmpty { rows.append("Materials \(document.materials.count)") }
    if !document.animations.isEmpty { rows.append("Animations \(document.animations.count)") }
    if !document.nodes.isEmpty { rows.append("Nodes \(document.nodes.count)") }
    return rows
}

private struct LayerRowView: View {
    let row: LayerRow
    @Bindable var session: ViewerSession

    var body: some View {
        HStack(spacing: 6) {
            Button {
                toggleHide()
            } label: {
                Image(systemName: session.hide.contains(row.id) ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(session.hide.contains(row.id) ? "Show" : "Hide")

            Button {
                toggleSolo()
            } label: {
                Image(systemName: session.soloRoot == row.id ? "circle.inset.filled" : "circle")
            }
            .buttonStyle(.borderless)
            .help(session.soloRoot == row.id ? "Clear solo" : "Solo")

            Text(row.title)
                .opacity(session.hide.contains(row.id) || session.soloHides(row.id) ? 0.45 : 1)
        }
    }

    private func toggleHide() {
        if session.hide.contains(row.id) {
            session.hide.remove(row.id)
        } else {
            session.hide.insert(row.id)
        }
        session.applyIfBound()
    }

    private func toggleSolo() {
        session.soloRoot = session.soloRoot == row.id ? nil : row.id
        session.applyIfBound()
    }
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
