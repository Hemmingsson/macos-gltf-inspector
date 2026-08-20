import SwiftUI

struct HostOutlinerView: View {
    var model: EntityLoader.LoadedModel?
    @Bindable var sidebar: HostSidebarModel
    @State private var expanded = Set<Int>()

    private var document: GLTFSessionDocument {
        model?.document ?? sidebar.document
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(layerRoots) { row in
                        LayerBranch(row: row, depth: 0, expanded: $expanded, sidebar: sidebar)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)

            if let facts = model?.stats.overlayFacts, !facts.isEmpty {
                PreviewOverlayFacts(facts: facts, tint: .primary, spread: true)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            expandDefaultLevels()
        }
        .onChange(of: sidebar.activeSceneIndex) { _, _ in
            expandDefaultLevels()
        }
    }

    private var layerRoots: [LayerRow] {
        let nodesByIndex = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.index, $0) })
        return sidebar.layerRootIndices().compactMap { LayerRow(index: $0, nodesByIndex: nodesByIndex) }
    }

    private func expandDefaultLevels() {
        expanded = defaultExpandedIDs(roots: layerRoots, maxDepth: 3)
    }
}

private struct LayerBranch: View {
    let row: LayerRow
    let depth: Int
    @Binding var expanded: Set<Int>
    @Bindable var sidebar: HostSidebarModel

    private var children: [LayerRow] { row.children }
    private var hasChildren: Bool { !children.isEmpty }
    private var isExpanded: Bool { expanded.contains(row.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LayerRowView(
                row: row,
                depth: depth,
                hasChildren: hasChildren,
                isExpanded: isExpanded,
                sidebar: sidebar,
                onToggleExpand: toggleExpand
            )
            if hasChildren, isExpanded {
                ForEach(children) { child in
                    LayerBranch(row: child, depth: depth + 1, expanded: $expanded, sidebar: sidebar)
                }
            }
        }
    }

    private func toggleExpand() {
        if isExpanded {
            expanded.remove(row.id)
        } else {
            expanded.insert(row.id)
        }
    }
}

private struct LayerRowView: View {
    let row: LayerRow
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    @Bindable var sidebar: HostSidebarModel
    let onToggleExpand: () -> Void

    @State private var isHovered = false

    private var isHidden: Bool {
        sidebar.hide.contains(row.id) || sidebar.soloHides(row.id)
    }

    private var showEye: Bool {
        isHovered || sidebar.hide.contains(row.id)
    }

    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(depth) * 8)

            if hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            } else if depth > 0 {
                // Align nested leaves under siblings that have chevrons; keep roots flush.
                Color.clear.frame(width: 12, height: 12)
            }

            Text(row.title)
                .lineLimit(1)
                .opacity(isHidden ? 0.45 : 1)
            Spacer(minLength: 8)

            if showEye {
                Button {
                    toggleHide()
                } label: {
                    Image(systemName: sidebar.hide.contains(row.id) ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(sidebar.hide.contains(row.id) ? "Show" : "Hide")
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func toggleHide() {
        if sidebar.hide.contains(row.id) {
            sidebar.hide.remove(row.id)
        } else {
            sidebar.hide.insert(row.id)
        }
        sidebar.overlayRevision += 1
    }
}

private struct LayerRow: Identifiable, Hashable {
    let id: Int
    let title: String
    let children: [LayerRow]

    init?(index: Int, nodesByIndex: [Int: GLTFSessionDocument.Node]) {
        guard let node = nodesByIndex[index] else { return nil }
        id = node.index
        title = node.name.isEmpty ? "Node \(node.index)" : node.name
        children = node.children.compactMap { LayerRow(index: $0, nodesByIndex: nodesByIndex) }
    }
}

private func defaultExpandedIDs(roots: [LayerRow], maxDepth: Int) -> Set<Int> {
    var ids = Set<Int>()
    func walk(_ row: LayerRow, depth: Int) {
        if depth < maxDepth {
            ids.insert(row.id)
        }
        for child in row.children {
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
