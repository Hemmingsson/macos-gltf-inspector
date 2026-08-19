import SwiftUI

struct HostOutlinerView: View {
    var model: GLBEntityLoader.LoadedModel?
    var sidebar: HostSidebarModel?

    var body: some View {
        Group {
            if let sidebar {
                OutlinerContent(model: model, sidebar: sidebar)
            } else {
                Text("No file")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(HostColumnChrome())
    }
}

private struct OutlinerContent: View {
    var model: GLBEntityLoader.LoadedModel?
    @Bindable var sidebar: HostSidebarModel
    @State private var expanded = Set<Int>()

    private var document: GLTFSessionDocument {
        model?.document ?? sidebar.document
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statsBlock
            if document.scenes.count > 1 {
                Picker("Scene", selection: $sidebar.activeSceneIndex) {
                    ForEach(document.scenes.indices, id: \.self) { index in
                        Text(sceneTitle(document.scenes[index], index: index)).tag(index)
                    }
                }
            }
            if !document.cameras.isEmpty {
                Picker("Camera", selection: $sidebar.selectedCameraIndex) {
                    Text("Fit").tag(Optional<Int>.none)
                    ForEach(document.cameras.indices, id: \.self) { index in
                        Text(cameraTitle(document.cameras[index], index: index)).tag(Optional(index))
                    }
                }
                .onChange(of: sidebar.selectedCameraIndex) { _, _ in
                    sidebar.overlayRevision += 1
                }
            }
            Text("Layers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(layerRoots) { row in
                        LayerDisclosure(row: row, expanded: $expanded, sidebar: sidebar)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            Picker("Debug", selection: $sidebar.debug) {
                ForEach(HostSidebarModel.DebugMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: sidebar.debug) { _, _ in
                sidebar.overlayRevision += 1
            }
        }
        .onAppear {
            expandDefaultLevels()
        }
        .onChange(of: sidebar.activeSceneIndex) { _, _ in
            expandDefaultLevels()
        }
    }

    @ViewBuilder
    private var statsBlock: some View {
        if let rows = model?.stats.previewRows {
            ForEach(rows, id: \.label) { row in
                LabeledContent(row.label, value: row.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var layerRoots: [LayerRow] {
        sidebar.layerRootIndices().compactMap { LayerRow(index: $0, nodes: document.nodes) }
    }

    private func expandDefaultLevels() {
        expanded = defaultExpandedIDs(roots: layerRoots, maxDepth: 3)
    }
}

private struct LayerDisclosure: View {
    let row: LayerRow
    @Binding var expanded: Set<Int>
    @Bindable var sidebar: HostSidebarModel

    var body: some View {
        if let children = row.children, !children.isEmpty {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(children) { child in
                    LayerDisclosure(row: child, expanded: $expanded, sidebar: sidebar)
                }
            } label: {
                LayerRowView(row: row, sidebar: sidebar)
            }
        } else {
            LayerRowView(row: row, sidebar: sidebar)
        }
    }

    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { expanded.contains(row.id) },
            set: { isOpen in
                if isOpen {
                    expanded.insert(row.id)
                } else {
                    expanded.remove(row.id)
                }
            }
        )
    }
}

private struct LayerRowView: View {
    let row: LayerRow
    @Bindable var sidebar: HostSidebarModel

    var body: some View {
        HStack(spacing: 6) {
            Text(row.title)
                .lineLimit(1)
                .opacity(sidebar.hide.contains(row.id) || sidebar.soloHides(row.id) ? 0.45 : 1)
            Spacer(minLength: 8)
            Button {
                toggleHide()
            } label: {
                Image(systemName: sidebar.hide.contains(row.id) ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(sidebar.hide.contains(row.id) ? "Show" : "Hide")

            Button {
                toggleSolo()
            } label: {
                Image(systemName: sidebar.soloRoot == row.id ? "circle.inset.filled" : "circle")
            }
            .buttonStyle(.borderless)
            .help(sidebar.soloRoot == row.id ? "Clear solo" : "Solo")
        }
    }

    private func toggleHide() {
        if sidebar.hide.contains(row.id) {
            sidebar.hide.remove(row.id)
        } else {
            sidebar.hide.insert(row.id)
        }
        sidebar.overlayRevision += 1
    }

    private func toggleSolo() {
        sidebar.soloRoot = sidebar.soloRoot == row.id ? nil : row.id
        sidebar.overlayRevision += 1
    }
}

private struct LayerRow: Identifiable, Hashable {
    let id: Int
    let title: String
    let children: [LayerRow]?

    init?(index: Int, nodes: [GLTFSessionDocument.Node]) {
        guard let node = nodes.first(where: { $0.index == index }) else {
            return nil
        }
        id = node.index
        title = node.name.isEmpty ? "Node \(node.index)" : node.name
        let childRows = node.children.compactMap { LayerRow(index: $0, nodes: nodes) }
        children = childRows.isEmpty ? nil : childRows
    }
}

private func defaultExpandedIDs(roots: [LayerRow], maxDepth: Int) -> Set<Int> {
    var ids = Set<Int>()
    func walk(_ row: LayerRow, depth: Int) {
        if depth < maxDepth {
            ids.insert(row.id)
        }
        for child in row.children ?? [] {
            walk(child, depth: depth + 1)
        }
    }
    roots.forEach { walk($0, depth: 0) }
    return ids
}

private func sceneTitle(_ scene: GLTFSessionDocument.Scene, index: Int) -> String {
    scene.name.isEmpty ? "Scene \(index)" : scene.name
}

private func cameraTitle(_ camera: GLTFSessionDocument.Camera, index: Int) -> String {
    camera.name.isEmpty ? "Camera \(index)" : camera.name
}

/// Liquid glass on macOS 26; plain column on 15.
struct HostColumnChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .padding(EdgeInsets(top: 36, leading: 10, bottom: 10, trailing: 10))
                .frame(maxHeight: .infinity, alignment: .top)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
                .padding(EdgeInsets(top: 36, leading: 10, bottom: 10, trailing: 10))
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

