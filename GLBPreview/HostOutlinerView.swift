import AppKit
import SwiftUI

struct HostOutlinerView: View {
    var model: EntityLoader.LoadedModel?
    var documentURL: URL?
    var validation: GLTFValidationState?
    @Bindable var sidebar: HostSidebarModel
    @Binding var showSkeleton: Bool
    @Binding var fieldOfViewDegrees: Float
    var orthographic: Bool = false
    var onBlenderError: (String) -> Void = { _ in }
    @State private var expanded = Set<Int>()
    @State private var validationExpanded = false
    /// P16 — live morph weights mirrored from the entity (session-only).
    @State private var morphWeights: [PreviewMorph.Target] = []

    private static let finderMenuIcon: NSImage = {
        let url =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
            ?? URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        return BlenderLauncher.menuIcon(for: url)
    }()

    private var document: GLTFSessionDocument {
        model?.document ?? sidebar.document
    }

    /// Same entity-local bounds as ContentView's open-ready dimensions log.
    private var modelDimensions: ModelDimensions? {
        guard let entity = model?.entity else { return nil }
        return PreviewCamera.dimensions(of: entity, relativeTo: entity)
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
            if !sidebar.materialVariantNames.isEmpty {
                Picker("Variant", selection: $sidebar.selectedMaterialVariantIndex) {
                    Text("Default").tag(Optional<Int>.none)
                    ForEach(sidebar.materialVariantNames.indices, id: \.self) { index in
                        Text(sidebar.materialVariantNames[index]).tag(Optional(index))
                    }
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

            if let detail = selectionDetail {
                SelectionDetailPanel(detail: detail)
            }

            if let dims = modelDimensions {
                HStack(spacing: 6) {
                    Image(systemName: "cube")
                        .foregroundStyle(.secondary)
                    Text(dims.readout)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityLabel("Model dimensions \(dims.readout)")
            }

            if !document.skins.isEmpty {
                Toggle("Skeleton", isOn: $showSkeleton)
                    .font(.caption)
                    .accessibilityLabel("Show skeleton overlay")
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("FOV")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("\(Int(fieldOfViewDegrees.rounded()))°")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $fieldOfViewDegrees,
                    in: PreviewCamera.fieldOfViewRange
                )
                .controlSize(.small)
                .disabled(orthographic)
                .accessibilityLabel("Field of view")
            }

            if !morphWeights.isEmpty {
                Text("Morphs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(morphWeights.enumerated()), id: \.element.id) { index, target in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Slider(
                            value: Binding(
                                get: { morphWeights[index].weight },
                                set: { applyMorphWeight(morphWeights[index], value: $0) }
                            ),
                            in: 0...1
                        )
                        .controlSize(.small)
                        .accessibilityLabel("Morph \(target.name)")
                    }
                }
            }

            if let facts = model?.stats.overlayFacts, !facts.isEmpty {
                PreviewOverlayFacts(facts: facts, tint: .primary, spread: true)
            }

            if let validation {
                validationBadge(validation)
            }

            if let report = model?.pipelineReport, report.showsInSidebar {
                pipelineBadge(report)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            expandDefaultLevels()
            refreshMorphWeights()
        }
        .onChange(of: sidebar.activeSceneIndex) { _, _ in
            expandDefaultLevels()
            refreshMorphWeights()
        }
        .onChange(of: model?.stats.morphGeometryCount) { _, _ in
            refreshMorphWeights()
        }
    }

    private func refreshMorphWeights() {
        guard let entity = model?.entity else {
            morphWeights = []
            return
        }
        morphWeights = PreviewMorph.targets(in: entity)
    }

    private func applyMorphWeight(_ target: PreviewMorph.Target, value: Float) {
        guard let entity = model?.entity else { return }
        PreviewMorph.setWeight(
            nodeIndex: target.nodeIndex,
            targetIndex: target.targetIndex,
            value: value,
            in: entity
        )
        if let index = morphWeights.firstIndex(where: { $0.id == target.id }) {
            morphWeights[index].weight = value
        }
    }

    @ViewBuilder
    private func validationBadge(_ state: GLTFValidationState) -> some View {
        switch state {
        case .success(let report):
            validationReportBadge(report)
        case .failed(let message):
            validationSoftBadge(title: message, symbol: "exclamationmark.circle.fill")
        case .skipped(let message):
            validationSoftBadge(title: message, symbol: "slash.circle.fill")
        }
    }

    @ViewBuilder
    private func validationSoftBadge(title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(Color.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func validationReportBadge(_ report: GLTFValidationReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                guard !report.isClean else { return }
                validationExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: report.isClean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(report.isClean ? Color.green : Color.orange)
                    Text(report.badgeTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(report.isClean ? Color.green : Color.orange)
                    Spacer(minLength: 0)
                    if !report.isClean {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .rotationEffect(.degrees(validationExpanded ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((report.isClean ? Color.green : Color.orange).opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(report.isClean)
            .accessibilityLabel(report.badgeTitle)

            if validationExpanded, !report.isClean {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(report.messages.filter { $0.severity <= 1 }.enumerated()), id: \.offset) { _, issue in
                        let pointer = issue.pointer.map { ptr -> String in
                            ptr.hasPrefix("/") ? String(ptr.dropFirst()) : ptr
                        }
                        Text(pointer.map { "\($0) — \(issue.message)" } ?? issue.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private func pipelineBadge(_ report: PreparePipelineReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !report.entries.isEmpty {
                pipelineSection(title: "This model, our pipeline", lines: report.entries)
            }
            if !report.extensionEntries.isEmpty {
                pipelineSection(title: "Extensions used", lines: report.extensionEntries)
            }
        }
    }

    @ViewBuilder
    private func pipelineSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(line.contains("Studio IBL") ? Color.secondary.opacity(0.5) : Color.green)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
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

    private var selectionDetail: SelectionDetail? {
        guard let index = sidebar.selectedNodeIndex else { return nil }
        return SelectionDetail.resolve(nodeIndex: index, in: document)
    }

    private func expandDefaultLevels() {
        expanded = defaultExpandedIDs(roots: layerRoots, maxDepth: 3)
    }
}

/// Host throwaway inspector for the selected layer (P32).
private struct SelectionDetailPanel: View {
    let detail: SelectionDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(detail.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail.kindLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            sectionTitle("Transform · authored")
            transformRow(label: "P", values: detail.translation)
            transformRow(label: "R", values: detail.rotationEulerDegrees)
            transformRow(label: "S", values: detail.scale)

            if !detail.geometryChips.isEmpty {
                sectionTitle("Geometry")
                FlowChips(labels: detail.geometryChips)
            }

            if !detail.materials.isEmpty {
                sectionTitle("Materials")
                ForEach(Array(detail.materials.enumerated()), id: \.offset) { _, material in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(material.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if material.maps.isEmpty {
                            Text("No maps")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            FlowChips(labels: material.maps)
                        }
                    }
                }
            }

            if let camera = detail.camera {
                sectionTitle("Camera")
                detailLine("Type", camera.type)
                if let yfov = camera.yfovDegrees {
                    detailLine("Y fov", format(yfov) + "°")
                }
                if let xmag = camera.xmag {
                    detailLine("X mag", format(xmag))
                }
                if let ymag = camera.ymag {
                    detailLine("Y mag", format(ymag))
                }
                detailLine("Near", format(camera.znear))
                if let zfar = camera.zfar {
                    detailLine("Far", format(zfar))
                }
            }

            if let light = detail.light {
                sectionTitle("Light")
                detailLine("Type", light.type)
                detailLine(
                    "Color",
                    "\(format(light.color.x))  \(format(light.color.y))  \(format(light.color.z))"
                )
                detailLine("Intensity", format(light.intensity))
                if let range = light.range {
                    detailLine("Range", format(range))
                }
                if let inner = light.innerConeDegrees {
                    detailLine("Inner", format(inner) + "°")
                }
                if let outer = light.outerConeDegrees {
                    detailLine("Outer", format(outer) + "°")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection \(detail.name), \(detail.kindLabel)")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func transformRow(label: String, values: SIMD3<Float>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)
            transformCell(values.x)
            transformCell(values.y)
            transformCell(values.z)
        }
    }

    private func transformCell(_ value: Float) -> some View {
        Text(format(value))
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    @ViewBuilder
    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}

private struct FlowChips: View {
    let labels: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72), spacing: 4)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                    )
            }
        }
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
        isHovered
            || sidebar.hide.contains(row.id)
            || sidebar.soloHides(row.id)
            || sidebar.soloRoot == row.id
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
                    // Option+eye isolates; plain eye toggles hide (Option+chevron stays expand).
                    if Self.isOptionDown {
                        sidebar.isolate(row.id)
                    } else {
                        toggleHide()
                    }
                } label: {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(eyeHelp)
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

    private var eyeHelp: String {
        if sidebar.soloRoot == row.id {
            return "Isolated. Option-click to exit isolate."
        }
        if sidebar.hide.contains(row.id) {
            return "Show. Option-click to isolate."
        }
        if sidebar.soloHides(row.id) {
            return "Hidden by isolate. Option-click this row to isolate it, or show all."
        }
        return "Hide. Option-click to isolate."
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
