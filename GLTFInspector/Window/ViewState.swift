import AppKit
import GLTFCore
import Observation
import Renderer

/// How this window shows its file: stage, look, camera, scene, variant and selection
/// (DESIGN.md "this window" job). The toolbar, the menu bar and the sidebar all edit this one
/// object; `options` is what the canvas draws with, and the camera commands go to `canvas`.
///
/// Backdrop, floor and auto-rotate follow Settings until this window changes them. Nothing here
/// writes Settings.
@MainActor
@Observable
final class ViewState {
    static let defaultFieldOfView = 35.0
    static let fieldOfViewRange = 15.0...90.0
    /// One Zoom In step; Zoom Out is its inverse.
    static let zoomStep = 0.8

    @ObservationIgnored let settings: AppSettings
    /// The open file's JSON; drives material → mesh highlights in `options`.
    @ObservationIgnored var document = GLTFDocument() {
        didSet { nodeParents = document.nodeParents }
    }
    /// `document.nodeParents`, kept with the document so selection walks don't rebuild it.
    @ObservationIgnored private var nodeParents: [Int?] = []
    /// The renderer behind the canvas. Outlives SwiftUI remounts of the canvas view.
    let canvas = ModelCanvasController()
    /// Orbit preview in the inspector Shape section; one `ModelView` across selection changes.
    let shapePreview = ShapePreviewController()

    private var overrides = StageOverrides()

    var backdrop: BackdropStyle {
        get { overrides.backdrop ?? settings.backdrop }
        set { overrides.backdrop = newValue }
    }
    var showsFloor: Bool {
        get { overrides.showsFloor ?? settings.showsFloor }
        set { overrides.showsFloor = newValue }
    }
    var showsSceneGizmos = false
    var autoRotates: Bool {
        get { overrides.autoRotates ?? settings.autoRotates }
        set { overrides.autoRotates = newValue }
    }
    /// False frames the authored origin too.
    var isCentered = true
    /// Any explicit change (menu, toolbar) makes it the person's choice again.
    var isOrthographic = false {
        didSet { autoOrthographic = false }
    }
    /// True while orthographic is on only because an axis view was chosen (Blender's
    /// auto-perspective): the next orbit returns to perspective.
    private(set) var autoOrthographic = false
    /// Vertical field of view in degrees, kept within `fieldOfViewRange`.
    /// Stored separately so `@Observable` + `didSet` cannot re-enter on assign.
    var fieldOfView: Double {
        get { storedFieldOfView }
        set { storedFieldOfView = newValue.clamped(to: Self.fieldOfViewRange) }
    }
    private var storedFieldOfView = defaultFieldOfView
    var viewMode: RenderViewMode = .shaded
    /// The modes the open file has data for; `viewMode` is always one of them.
    var viewModes: [RenderViewMode] = [.shaded] {
        didSet { if !viewModes.contains(viewMode) { viewMode = .shaded } }
    }

    var exposure = 0.0
    /// Environment rotation in degrees; 0 is the Khronos Sample Viewer's view.
    var environmentYaw = 0.0
    var environment: LightingEnvironment
    var toneMapping: RenderLook.ToneMapping

    /// The scene drawn and listed. Changing it drops a node selection and the file camera, which
    /// belong to the previous scene.
    var sceneIndex = 0 {
        didSet {
            guard sceneIndex != oldValue else { return }
            if let selection, selection.kind.isSceneNode { self.selection = nil }
            fileCameraNodeIndex = nil
            hiddenNodes = []
            soloNodes = []
        }
    }
    /// Scene-graph nodes hidden in this window (glTF node indices). Hiding a node hides its subtree.
    var hiddenNodes: Set<Int> = []
    /// When non-empty, only these nodes' subtrees are drawn.
    var soloNodes: Set<Int> = []
    /// `KHR_materials_variants` index, or nil for the file's default materials.
    var materialVariantIndex: Int?
    /// The node of the file camera the canvas looks through, or nil for the orbit camera.
    var fileCameraNodeIndex: Int? {
        didSet { if fileCameraNodeIndex != nil { activeCameraPreset = nil } }
    }
    /// The primary selection: the row the inspector shows. A mesh or empty node is also outlined
    /// on the canvas. Assigning it replaces the whole selection with this one row.
    var selection: NodeID? {
        get { primarySelection }
        set {
            primarySelection = newValue
            storedSelectedIDs = newValue.map { [$0] } ?? []
        }
    }
    /// Every selected row (outliner ⌘/⇧-click, canvas ⌘/⇧-click). Contains `selection` when
    /// that is non-nil. Assigning makes a newly added row the primary; when only rows were
    /// removed the primary stays if it is still selected.
    var selectedIDs: Set<NodeID> {
        get { storedSelectedIDs }
        set {
            let added = newValue.subtracting(storedSelectedIDs)
            let anchor = primarySelection
            storedSelectedIDs = newValue
            if let next = Self.primaryAfterAdding(added, anchor: anchor, document: document) {
                primarySelection = next
            } else if primarySelection.map(newValue.contains) != true {
                primarySelection = newValue.min(by: { Self.outlinerOrder($0, $1, document: document) })
            }
        }
    }
    private var primarySelection: NodeID?
    private var storedSelectedIDs: Set<NodeID> = []
    /// Selected glTF scene nodes (mesh, empty, camera, light), primary first.
    var selectedSceneNodes: [Int] {
        let nodes = storedSelectedIDs.filter(\.kind.isSceneNode).map(\.index).sorted()
        guard let primary = primarySelection, primary.kind.isSceneNode else { return nodes }
        return [primary.index] + nodes.filter { $0 != primary.index }
    }
    /// The last canvas hit and the selection it produced, so a repeated click on the same spot
    /// walks up the hierarchy instead of reselecting the part.
    @ObservationIgnored private var lastPick: (hit: Int, selection: NodeID?)?
    /// The canned angle last chosen; cleared by Fit, zoom and file cameras.
    private(set) var activeCameraPreset: CameraPreset?

    init(settings: AppSettings) {
        self.settings = settings
        environment = settings.environment
        toneMapping = settings.toneMapping
    }

    /// What the canvas draws with.
    var options: ViewOptions {
        ViewOptions(
            look: RenderLook(exposureEV: exposure, environmentIntensity: 1, environmentYawDegrees: environmentYaw,
                             environment: environment, toneMapping: toneMapping, background: backdrop.color),
            viewMode: viewMode,
            autoRotates: autoRotates,
            isOrthographic: isOrthographic,
            fieldOfView: fieldOfView,
            fileCameraNodeIndex: fileCameraNodeIndex,
            materialVariantIndex: materialVariantIndex,
            sceneIndex: sceneIndex,
            showsFloor: showsFloor,
            showsSceneGizmos: showsSceneGizmos,
            isCentered: isCentered,
            selectedNodeIndex: selection.flatMap { $0.kind == .mesh || $0.kind == .empty ? $0.index : nil },
            selectedNodeIndices: Set(storedSelectedIDs.filter { $0.kind == .mesh || $0.kind == .empty }.map(\.index)),
            orbitsAroundSelection: settings.orbitsAroundSelection,
            zoomsTowardPointer: settings.zoomsTowardPointer,
            highlightedNodeIndices: materialHighlightNodeIndices.nodes,
            materialHighlightMaterialIndex: materialHighlightNodeIndices.materialIndex,
            gizmoSelectedNodeIndex: selection.flatMap { $0.kind.isSceneNode ? $0.index : nil },
            selectedSkinIndex: selection.flatMap { $0.kind == .skin ? $0.index : nil },
            hiddenNodeIndices: hiddenNodes,
            soloNodeIndices: soloNodes
        )
    }

    /// A new document in this window: Settings' lighting and every other choice back to how a
    /// new window starts. The document's scene and view modes follow once its JSON is read.
    func reset() {
        restoreStageAndLook()
        viewModes = [.shaded]
        sceneIndex = 0
        materialVariantIndex = nil
        fileCameraNodeIndex = nil
        selection = nil
        activeCameraPreset = nil
        showsSceneGizmos = false
        lastPick = nil
        shapePreview.reset()
        showAll()
        canvas.stopPlayback()
    }

    // MARK: - Selection

    /// The canvas reported a plain click on `nodeIndex` (nil = background). Clicking the part
    /// that was just picked again selects its parent, up to the root, then the part again.
    func pick(_ nodeIndex: Int?) {
        guard let nodeIndex, let hit = document.id(ofNode: nodeIndex) else {
            selection = nil
            lastPick = nil
            return
        }
        var next = hit
        if let lastPick, lastPick.hit == nodeIndex, lastPick.selection == selection,
           let current = selection, current.kind.isSceneNode {
            next = parent(of: current.index) ?? hit
        }
        selection = next
        lastPick = (nodeIndex, next)
    }

    /// ⌘- or ⇧-click on the canvas: adds the node under the pointer, or removes it.
    func toggleSelection(ofNode nodeIndex: Int) {
        guard let id = document.id(ofNode: nodeIndex) else { return }
        lastPick = nil
        if storedSelectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Edit ▸ Select Parent: the primary scene node's parent.
    func selectParent() {
        if let parentID { selection = parentID }
    }

    /// Edit ▸ Select Children: every direct child of the primary scene node.
    func selectChildren() {
        let children = childIDs
        guard let first = children.first else { return }
        storedSelectedIDs = Set(children)
        primarySelection = first
    }

    var canSelectParent: Bool { parentID != nil }
    var canSelectChildren: Bool { !childIDs.isEmpty }

    /// The primary scene node's parent row.
    private var parentID: NodeID? {
        guard let current = selection, current.kind.isSceneNode else { return nil }
        return parent(of: current.index)
    }

    /// The primary scene node's direct child rows.
    private var childIDs: [NodeID] {
        guard let current = selection, current.kind.isSceneNode, document.nodes.indices.contains(current.index) else { return [] }
        return document.nodes[current.index].children.compactMap { document.id(ofNode: $0) }
    }

    private func parent(of nodeIndex: Int) -> NodeID? {
        guard nodeParents.indices.contains(nodeIndex), let parent = nodeParents[nodeIndex] else { return nil }
        return document.id(ofNode: parent)
    }

    /// Depth-first sidebar order; tie-break by glTF index only.
    private static func outlinerOrder(_ a: NodeID, _ b: NodeID, document: GLTFDocument) -> Bool {
        let ranks = outlinerRanks(in: document)
        let ra = ranks[a] ?? Int.max
        let rb = ranks[b] ?? Int.max
        if ra != rb { return ra < rb }
        return a.index < b.index
    }

    /// New primary after a range or toggle add: the added row farthest from the previous primary
    /// in outliner order (the clicked end of the range).
    private static func primaryAfterAdding(
        _ added: Set<NodeID>,
        anchor: NodeID?,
        document: GLTFDocument
    ) -> NodeID? {
        guard !added.isEmpty else { return nil }
        let ranks = outlinerRanks(in: document)
        guard let anchor, let anchorRank = ranks[anchor] else {
            return added.max(by: { outlinerOrder($0, $1, document: document) })
        }
        return added.max { a, b in
            let da = abs((ranks[a] ?? anchorRank) - anchorRank)
            let db = abs((ranks[b] ?? anchorRank) - anchorRank)
            if da != db { return da < db }
            return outlinerOrder(a, b, document: document)
        }
    }

    private static func outlinerRanks(in document: GLTFDocument) -> [NodeID: Int] {
        var ranks: [NodeID: Int] = [:]
        var rank = 0
        func walk(_ items: [OutlinerItem]) {
            for item in items {
                ranks[item.id] = rank
                rank += 1
                walk(item.children)
            }
        }
        for section in OutlinerSection.sections(of: document) {
            walk(section.items)
        }
        return ranks
    }

    // MARK: - Layer visibility

    /// Hide Selection: hides every selected scene node, or shows them when all are hidden.
    func toggleHiddenSelection() {
        let nodes = Set(selectedSceneNodes)
        guard !nodes.isEmpty else { return }
        if selectionIsHidden { hiddenNodes.subtract(nodes) } else { hiddenNodes.formUnion(nodes) }
    }

    /// Solo Selection: solos exactly the selected scene nodes; again clears the solo.
    func toggleSoloSelection() {
        let nodes = Set(selectedSceneNodes)
        guard !nodes.isEmpty else { return }
        soloNodes = selectionIsSoloed ? [] : nodes
    }

    /// Every selected scene node is hidden (the menu then offers Show Selection).
    var selectionIsHidden: Bool {
        let nodes = Set(selectedSceneNodes)
        return !nodes.isEmpty && nodes.isSubset(of: hiddenNodes)
    }

    /// Exactly the selected scene nodes are soloed.
    var selectionIsSoloed: Bool {
        let nodes = Set(selectedSceneNodes)
        return !nodes.isEmpty && soloNodes == nodes
    }

    /// Hide or show one scene node in this window; the file is not touched.
    func toggleHidden(_ node: Int) {
        if hiddenNodes.contains(node) {
            hiddenNodes.remove(node)
        } else {
            hiddenNodes.insert(node)
        }
    }

    /// Solo one node; soloing the only soloed node clears the solo.
    func toggleSolo(_ node: Int) {
        soloNodes = soloNodes == [node] ? [] : [node]
    }

    /// Clears every hidden and soloed node.
    func showAll() {
        hiddenNodes = []
        soloNodes = []
    }

    // MARK: - Camera commands

    func fit() {
        fileCameraNodeIndex = nil
        activeCameraPreset = nil
        canvas.fit()
    }

    /// Frames every selected scene node at the current orbit angle. No-op without one.
    func frameSelection() {
        let nodes = selectedSceneNodes
        guard !nodes.isEmpty else { return }
        fileCameraNodeIndex = nil
        activeCameraPreset = nil
        canvas.frame(nodeIndices: nodes)
    }

    func zoom(by factor: Double) {
        activeCameraPreset = nil
        canvas.zoom(by: factor)
    }

    func orbit(dx: Double, dy: Double) {
        canvasDidOrbit()
        canvas.orbit(dx: dx, dy: dy)
    }

    /// An orbit leaves the canned angle; an axis view's automatic orthographic ends with it.
    func canvasDidOrbit() {
        activeCameraPreset = nil
        if autoOrthographic { isOrthographic = false }
    }

    func show(_ preset: CameraPreset) {
        fileCameraNodeIndex = nil
        activeCameraPreset = preset
        let wasOrthographic = isOrthographic && !autoOrthographic
        isOrthographic = preset != .isometric || wasOrthographic
        autoOrthographic = preset != .isometric && !wasOrthographic
        canvas.show(preset)
    }

    /// Reset View: this window's stage, look and camera back to how it opened, then Fit.
    func resetView() {
        restoreStageAndLook()
        fit()
    }

    /// Share ▸ Export Turntable: one orbit as a video or GIF, through a save panel. Ignored while
    /// one is already being written.
    func exportTurntable(_ format: TurntableExport.Format, suggestedName: String) {
        guard !isExportingTurntable, canvas.phase == .ready else { return }
        isExportingTurntable = true
        Task {
            await TurntableExport.save(format, from: canvas, suggestedName: suggestedName)
            isExportingTurntable = false
        }
    }
    private(set) var isExportingTurntable = false

    /// File ▸ Export PNG: the canvas at its pixel size, through a save panel.
    func exportPNG(suggestedName: String) {
        do {
            let image = try canvas.snapshot()
            Task { await PNGExport.save(image, suggestedName: suggestedName) }
        } catch {
            AppLog.error(AppLog.app, "PNG export failed: \(error.localizedDescription)")
        }
    }

    private var materialHighlightNodeIndices: (nodes: Set<Int>, materialIndex: Int?) {
        guard let selection, selection.kind == .material else { return ([], nil) }
        let nodes = Set(document.nodeIndices(usingMaterial: selection.index,
                                              materialVariantIndex: materialVariantIndex))
            .subtracting(hiddenNodes)
        return (nodes, nodes.isEmpty ? nil : selection.index)
    }

    private func restoreStageAndLook() {
        overrides = StageOverrides()
        isCentered = true
        isOrthographic = false
        fieldOfView = Self.defaultFieldOfView
        viewMode = .shaded
        exposure = 0
        environmentYaw = 0
        environment = settings.environment
        toneMapping = settings.toneMapping
    }
}

/// Window overrides of Settings-seeded stage knobs. `nil` means “follow Settings”.
private struct StageOverrides {
    var backdrop: BackdropStyle?
    var showsFloor: Bool?
    var autoRotates: Bool?
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
