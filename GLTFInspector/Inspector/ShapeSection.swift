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
        .task(id: ShapePreviewTaskID(generation: view.canvas.sceneGeneration, selection: selection)) {
            await view.shapePreview.sync(canvas: view.canvas, windowOptions: view.options, selection: selection)
        }
        .onChange(of: view.options) { _, _ in
            Task {
                await view.shapePreview.sync(canvas: view.canvas, windowOptions: view.options, selection: selection)
            }
        }
    }
}

private struct ShapePreviewTaskID: Equatable {
    let generation: Int
    let kind: NodeKind
    let index: Int

    init(generation: Int, selection: NodeID) {
        self.generation = generation
        kind = selection.kind
        index = selection.index
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

    func sync(canvas: ModelCanvasController, windowOptions: ViewOptions, selection: NodeID?) async {
        showsInteractivePreview = false
        showsCameraStill = false
        cameraImage = nil

        guard canvas.phase == .ready, let scene = canvas.scene, let selection else { return }

        switch selection.kind {
        case .mesh, .empty:
            showsInteractivePreview = true
            await updateInteractive(canvas: canvas, scene: scene, windowOptions: windowOptions, nodeIndex: selection.index)
        case .camera:
            showsCameraStill = true
            updateCameraStill(canvas: canvas, scene: scene, windowOptions: windowOptions, nodeIndex: selection.index)
        default:
            break
        }
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

    private func updateInteractive(
        canvas: ModelCanvasController,
        scene: MetalScene,
        windowOptions: ViewOptions,
        nodeIndex: Int
    ) async {
        do {
            let preview = try ensureView(sharing: scene)
            if canvas.sceneGeneration != adoptedSceneGeneration {
                try preview.show(scene: scene)
                adoptedSceneGeneration = canvas.sceneGeneration
            }
            let options = Self.previewOptions(from: windowOptions, isolatedNode: nodeIndex)
            try await preview.apply(options)
            preview.fit(nodeIndex: nodeIndex)
        } catch {
            AppLog.error(AppLog.renderer, "shape preview failed: \(error.localizedDescription)")
        }
    }

    private func updateCameraStill(
        canvas: ModelCanvasController,
        scene: MetalScene,
        windowOptions: ViewOptions,
        nodeIndex: Int
    ) {
        do {
            let snapshotView = try ensureView(sharing: scene)
            if canvas.sceneGeneration != adoptedSceneGeneration {
                try snapshotView.show(scene: scene)
                adoptedSceneGeneration = canvas.sceneGeneration
            }
            var options = Self.previewOptions(from: windowOptions, isolatedNode: nil)
            options.fileCameraNodeIndex = nodeIndex
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
        options.isolatedNodeIndex = isolatedNode
        options.fileCameraNodeIndex = nil
        options.autoRotates = false
        return options
    }
}
