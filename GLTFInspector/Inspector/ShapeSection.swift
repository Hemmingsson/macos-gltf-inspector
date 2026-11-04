import AppKit
import GLTFCore
import Observation
import Renderer
import SwiftUI

/// Inspector Shape preview: isolated orbit view for mesh/empty nodes, file-camera still for cameras.
struct ShapeSection: View {
    @Bindable var view: ViewState
    let selection: NodeID

    private static let previewSize: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader("Shape")
            Group {
                if view.shapePreview.showsCameraStill, let image = view.shapePreview.cameraImage {
                    Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .accessibilityLabel("View through camera")
                } else if view.shapePreview.showsInteractivePreview {
                    ShapePreviewRepresentable(controller: view.shapePreview)
                }
            }
            .frame(width: Self.previewSize, height: Self.previewSize)
            .background(DS.Color.paneFill)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.m)
        }
        // One trigger: a change of scene, selection or window options re-runs the task (a new id
        // cancels the previous run), so each change syncs exactly once.
        .task(id: ShapePreviewTaskID(generation: view.canvas.sceneGeneration, selection: selection, options: view.options)) {
            await view.shapePreview.sync(canvas: view.canvas, windowOptions: view.options, selection: selection)
        }
    }
}

private struct ShapePreviewTaskID: Equatable {
    let generation: Int
    let kind: NodeKind
    let index: Int
    let options: ViewOptions

    init(generation: Int, selection: NodeID, options: ViewOptions) {
        self.generation = generation
        kind = selection.kind
        index = selection.index
        self.options = options
    }
}

private struct ShapePreviewRepresentable: NSViewRepresentable {
    let controller: ShapePreviewController

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        controller.mount(in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        controller.mount(in: container)
    }
}

/// One shared `ModelView` for the Shape section; adopts the canvas scene, never loads a file.
@MainActor
@Observable
final class ShapePreviewController {
    private(set) var showsInteractivePreview = false
    private(set) var showsCameraStill = false
    private(set) var cameraImage: CGImage?

    @ObservationIgnored private(set) var view: ModelView?
    @ObservationIgnored private var adoptedSceneGeneration = -1
    /// Scene adoptions (`show(scene:)`) so far; tests use it to prove a change did not re-adopt.
    @ObservationIgnored private(set) var adoptCount = 0
    /// The scene generation and orbit fit the preview last framed; a change of node or scene refits.
    @ObservationIgnored private var fitted: FitKey?
    /// The inputs of the last `sync`; an identical request repeats no work.
    @ObservationIgnored private var lastSync: SyncKey?

    private struct FitKey: Equatable {
        let node: Int
        let generation: Int
    }

    private struct SyncKey: Equatable {
        let kind: NodeKind
        let node: Int
        let generation: Int
        let options: ViewOptions
    }

    func sync(canvas: ModelCanvasController, windowOptions: ViewOptions, selection: NodeID?) async {
        guard canvas.phase == .ready, let scene = canvas.scene, let selection else {
            reset()
            return
        }

        let generation = canvas.sceneGeneration
        switch selection.kind {
        case .mesh, .empty:
            guard Self.nodeHasPreviewGeometry(nodeIndex: selection.index, canvas: canvas) else {
                reset()
                return
            }
            let options = Self.previewOptions(from: windowOptions, isolatedNode: selection.index)
            let key = SyncKey(kind: selection.kind, node: selection.index, generation: generation, options: options)
            guard key != lastSync else { return }
            lastSync = key
            showsInteractivePreview = true
            showsCameraStill = false
            cameraImage = nil
            await updateInteractive(scene: scene, generation: generation, options: options, nodeIndex: selection.index)
        case .camera:
            var options = Self.previewOptions(from: windowOptions, isolatedNode: nil)
            options.fileCameraNodeIndex = selection.index
            let key = SyncKey(kind: selection.kind, node: selection.index, generation: generation, options: options)
            guard key != lastSync else { return }
            lastSync = key
            showsInteractivePreview = false
            showsCameraStill = true
            updateCameraStill(scene: scene, generation: generation, options: options)
        default:
            reset()
        }
    }

    private static func nodeHasPreviewGeometry(nodeIndex: Int, canvas: ModelCanvasController) -> Bool {
        guard let bounds = canvas.bounds(ofNode: nodeIndex) else { return false }
        let eps: Float = 1e-5
        return bounds.max.x - bounds.min.x > eps
            || bounds.max.y - bounds.min.y > eps
            || bounds.max.z - bounds.min.z > eps
    }

    /// Drops the adopted scene and preview view (document reset or selection without drawable geometry).
    func reset() {
        view?.removeFromSuperview()
        view = nil
        adoptedSceneGeneration = -1
        fitted = nil
        lastSync = nil
        showsInteractivePreview = false
        showsCameraStill = false
        cameraImage = nil
    }

    func mount(in container: NSView) {
        guard showsInteractivePreview, let view else { return }
        if view.superview !== container {
            view.removeFromSuperview()
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        view.frame = container.bounds
    }

    private func ensureView(sharing scene: MetalScene) throws -> ModelView {
        if let view { return view }
        let view = ModelView(renderer: try MetalRenderer(sharing: scene))
        view.transmissionResolution = 256
        self.view = view
        return view
    }

    /// Adopts `scene` into the shared view once per scene generation.
    private func adoptIfNeeded(_ view: ModelView, scene: MetalScene, generation: Int) throws {
        guard generation != adoptedSceneGeneration else { return }
        try view.show(scene: scene)
        adoptedSceneGeneration = generation
        adoptCount += 1
    }

    private func updateInteractive(scene: MetalScene, generation: Int, options: ViewOptions, nodeIndex: Int) async {
        do {
            let preview = try ensureView(sharing: scene)
            try adoptIfNeeded(preview, scene: scene, generation: generation)
            // Exposure and other cheap look changes keep the orbit; only a new node or scene refits.
            try await preview.apply(options)
            let fit = FitKey(node: nodeIndex, generation: generation)
            if fitted != fit {
                preview.fit(nodeIndex: nodeIndex)
                fitted = fit
            }
        } catch {
            AppLog.error(AppLog.renderer, "shape preview failed: \(error.localizedDescription)")
        }
    }

    private func updateCameraStill(scene: MetalScene, generation: Int, options: ViewOptions) {
        do {
            let snapshotView = try ensureView(sharing: scene)
            try adoptIfNeeded(snapshotView, scene: scene, generation: generation)
            // The still re-frames the shared view's camera, so the next interactive sync must refit.
            fitted = nil
            try snapshotView.show(scene: scene, options: options)
            snapshotView.transmissionResolution = 256
            cameraImage = try snapshotView.image(width: 200, height: 200, transmissionResolution: 256)
        } catch {
            AppLog.error(AppLog.renderer, "camera still failed: \(error.localizedDescription)")
        }
    }

    static func previewOptions(from window: ViewOptions, isolatedNode: Int?) -> ViewOptions {
        var options = window
        options.look.background = .clear
        options.showsFloor = false
        options.showsSceneGizmos = false
        options.isCentered = true
        options.selectedNodeIndex = nil
        options.highlightedNodeIndices = []
        options.gizmoSelectedNodeIndex = nil
        options.selectedSkinIndex = nil
        options.hiddenNodeIndices = []
        options.soloNodeIndices = []
        options.selectedNodeIndices = []
        options.hoveredNodeIndex = nil
        options.useSilhouetteSelectionOutline = false
        options.isolatedNodeIndex = isolatedNode
        options.fileCameraNodeIndex = nil
        options.autoRotates = false
        return options
    }
}
