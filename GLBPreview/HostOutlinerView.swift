import AppKit
import SwiftUI

struct HostOutlinerView: View {
    var model: EntityLoader.LoadedModel?
    var documentURL: URL?
    @Bindable var sidebar: HostSidebarModel
    var onBlenderError: (String) -> Void = { _ in }
    @State private var expanded = Set<Int>()

    private static let finderMenuIcon: NSImage = {
        let url =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
            ?? URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        return BlenderLauncher.menuIcon(for: url)
    }()

    private var document: GLTFSessionDocument {
        model?.document ?? sidebar.document
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let documentURL {
                openInMenu(documentURL)
            }
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
            List {
                ForEach(layerRoots) { row in
                    LayerOutlineBranch(row: row, depth: 0, expanded: $expanded, sidebar: sidebar)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)

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

    @ViewBuilder
    private func openInMenu(_ documentURL: URL) -> some View {
        Menu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([documentURL])
            } label: {
                openInMenuRow(title: "Finder", icon: Self.finderMenuIcon)
            }
            if BlenderLauncher.isInstalled, let blenderIcon = BlenderLauncher.applicationIcon {
                Button {
                    do {
                        try BlenderLauncher.openInNewBlenderInstance(documentURL)
                    } catch {
                        AppLog.error(AppLog.host, "blender open failed \(error.localizedDescription)")
                        onBlenderError(error.localizedDescription)
                    }
                } label: {
                    openInMenuRow(title: "Blender", icon: blenderIcon)
                }
            }
        } label: {
            Label("Open in…", systemImage: "arrow.up.forward.app")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .help("Open in…")
    }

    @ViewBuilder
    private func openInMenuRow(title: String, icon: NSImage) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            Text(title)
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

private struct LayerOutlineBranch: View {
    let row: LayerRow
    let depth: Int
    @Binding var expanded: Set<Int>
    @Bindable var sidebar: HostSidebarModel

    private var children: [LayerRow] { row.children }
    private var hasChildren: Bool { !children.isEmpty }
    private var isExpanded: Bool { expanded.contains(row.id) }

    var body: some View {
        LayerRowLabel(
            row: row,
            depth: depth,
            hasChildren: hasChildren,
            isExpanded: isExpanded,
            sidebar: sidebar,
            onToggleExpand: toggleExpand
        )
        if hasChildren, isExpanded {
            ForEach(children) { child in
                LayerOutlineBranch(row: child, depth: depth + 1, expanded: $expanded, sidebar: sidebar)
            }
        }
    }

    /// Figma Layers: plain click toggles this node; Option-click expands/collapses all descendants.
    /// If the row is open but some descendants are still collapsed, Option-click finishes expanding
    /// (defaults only open to depth 3) instead of collapsing.
    private func toggleExpand(recursive: Bool) {
        if recursive {
            if isExpanded, isFullyExpanded(row) {
                collapseSubtree(row)
            } else {
                expandSubtree(row)
            }
        } else if isExpanded {
            expanded.remove(row.id)
        } else {
            expanded.insert(row.id)
        }
    }

    private func isFullyExpanded(_ node: LayerRow) -> Bool {
        guard !node.children.isEmpty else { return true }
        guard expanded.contains(node.id) else { return false }
        return node.children.allSatisfy(isFullyExpanded)
    }

    private func expandSubtree(_ node: LayerRow) {
        guard !node.children.isEmpty else { return }
        expanded.insert(node.id)
        for child in node.children {
            expandSubtree(child)
        }
    }

    private func collapseSubtree(_ node: LayerRow) {
        expanded.remove(node.id)
        for child in node.children {
            collapseSubtree(child)
        }
    }
}

/// One indent step = one disclosure column (arrow + gap to label), so a child's
/// chevron left edge lines up with the parent's title.
private enum LayerOutlineMetrics {
    static let arrow: CGFloat = 14
    static let gap: CGFloat = 4
    static var step: CGFloat { arrow + gap }
}

private struct LayerRowLabel: View {
    let row: LayerRow
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    @Bindable var sidebar: HostSidebarModel
    let onToggleExpand: (_ recursive: Bool) -> Void

    @State private var isHovered = false

    private var isHidden: Bool {
        sidebar.hide.contains(row.id) || sidebar.soloHides(row.id)
    }

    private var isSelected: Bool {
        sidebar.selectedNodeIndex == row.id
    }

    private var showEye: Bool {
        isHovered || sidebar.hide.contains(row.id)
    }

    private static var isOptionDown: Bool {
        let eventFlags = NSApp.currentEvent?.modifierFlags ?? []
        return eventFlags.contains(.option) || NSEvent.modifierFlags.contains(.option)
    }

    var body: some View {
        HStack(spacing: 0) {
            leadingGutter

            Group {
                if hasChildren {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(.secondary)
                        .help("Click to expand or collapse. Option-click to expand or collapse all nested layers.")
                        .onTapGesture {
                            onToggleExpand(Self.isOptionDown)
                        }
                } else {
                    Color.clear
                }
            }
            .frame(width: LayerOutlineMetrics.arrow, height: LayerOutlineMetrics.arrow)
            .contentShape(Rectangle())

            Text(row.title)
                .lineLimit(1)
                .opacity(isHidden ? 0.45 : 1)
                .padding(.leading, LayerOutlineMetrics.gap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { sidebar.selectNode(row.id) }

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
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowSeparator(.hidden)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    /// Ancestor indent + faint vertical guides through each parent arrow center.
    private var leadingGutter: some View {
        let step = LayerOutlineMetrics.step
        let arrow = LayerOutlineMetrics.arrow
        return ZStack(alignment: .leading) {
            Color.clear.frame(width: CGFloat(depth) * step)
            ForEach(0..<depth, id: \.self) { level in
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1)
                    .padding(.leading, CGFloat(level) * step + arrow / 2 - 0.5)
            }
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
}

private struct LayerRow: Identifiable, Hashable {
    let id: Int
    let title: String
    let children: [LayerRow]

    init?(index: Int, nodesByIndex: [Int: GLTFSessionDocument.Node]) {
        guard let node = nodesByIndex[index] else { return nil }
        id = node.index
        title = titled(node.name, fallback: "Node \(node.index)")
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
    titled(scene.name, fallback: "Scene \(index)")
}

private func cameraTitle(_ camera: GLTFSessionDocument.Camera, index: Int) -> String {
    titled(camera.name, fallback: "Camera \(index)")
}

private func titled(_ name: String, fallback: String) -> String {
    name.isEmpty ? fallback : name
}
