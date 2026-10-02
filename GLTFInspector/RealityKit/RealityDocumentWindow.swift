import AppKit
import GLTFCore
import PreviewUI
import RendererRealityKit
import SwiftUI

/// Document window on the RealityKit renderer: one convert (`EntityLoader`) feeds both the canvas
/// (`RealityPreviewCanvas`) and the RealityKit-only chrome — clips, morph sliders, debug modes,
/// the pipeline and convert-problem reports. Scene and variant switches re-run convert.
struct RealityDocumentWindow: View {
    let documentURL: URL?

    @Environment(\.colorScheme) private var colorScheme

    @State private var window: DocumentWindowModel
    @State private var convert: RealityCanvasView.State = .loading
    @State private var interaction = PreviewInteraction()
    /// Inspector morph sliders — mirrored from `PreviewMorph` on the loaded entity.
    @State private var morphTargets: [MorphTargetControl] = []
    /// Built once per loaded model: rebuilding it re-touches the live entity's animations. An empty
    /// controller (no clips) while nothing is loaded.
    @State private var playbackController = EngineAnimationPlaybackController()
    /// App Group poster or bounding-box proxy while convert runs.
    @State private var firstPixelImage: NSImage?

    init(documentURL: URL?) {
        self.documentURL = documentURL
        _window = State(
            wrappedValue: DocumentWindowModel(
                documentURL: documentURL,
                features: RealityPreviewCanvas.features
            )
        )
    }

    var body: some View {
        DocumentShell(
            window: window,
            canvasState: canvasState,
            playback: playbackController,
            morphTargets: morphTargets,
            onSetMorphWeight: applyMorphWeight
        ) {
            // Mounted by `CanvasRegion` only while `canvasState` is `.ready`, i.e. convert landed.
            if let loadedModel {
                HostPreviewContainer(
                    model: loadedModel,
                    interaction: interaction,
                    isDark: colorScheme == .dark,
                    sidebar: window.sidebar,
                    overlayRevision: window.sidebar?.overlayRevision ?? 0,
                    session: window.previewSession.bindings(debugModes: loadedModel.debugModes),
                    commands: realityCommands,
                    registerCommands: { window.engineViewport.commands = $0 }
                )
                .canvasReadyMarker(renderer: .realityKit, isReady: true)
                .onAppear { window.noteCanvasReady() }
            } else if let firstPixelImage {
                Image(nsImage: firstPixelImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .onAppear {
            if let documentURL {
                loadDocument(documentURL)
            } else {
                window.failMissingURL()
                convert = .failed("The document URL is missing.")
            }
        }
        .onChange(of: documentURL) { _, url in
            window.documentURL = url
            if let url {
                loadDocument(url)
            }
        }
        .onChange(of: window.sidebar?.activeSceneIndex) { previous, index in
            guard previous != nil else { return }
            reloadScene(index)
        }
        .onChange(of: window.sidebar?.selectedMaterialVariantIndex) { previous, _ in
            guard previous != nil || window.sidebar?.selectedMaterialVariantIndex != nil else { return }
            reloadMaterialVariant()
        }
    }

    /// Convert ready is the live canvas. During convert a poster / proxy is enough to leave
    /// the spinner-only status view — first pixel, not first Metal frame.
    private var canvasState: ShellDocumentState {
        switch convert {
        case .loading: firstPixelImage == nil ? .loading : .ready
        case .ready: .ready
        case .failed(let message): .failed(message)
        }
    }

    private var loadedModel: EntityLoader.LoadedModel? {
        if case .ready(let model) = convert { return model }
        return nil
    }

    /// Registered by `RealityCanvasView` while the RealityKit canvas is mounted.
    private var realityCommands: FocusedPreviewCommands? {
        guard loadedModel != nil else { return nil }
        return FocusedPreviewCommands(
            fit: { reframingCamera() },
            reset: resetPreviewView,
            applyCameraPreset: { reframingCamera(preset: $0) },
            screenshot: renderRealityStill
        )
    }

    private func reframingCamera(preset: GLTFCore.CameraPreset? = nil) {
        let session = window.previewSession
        window.sidebar?.selectedCameraIndex = nil
        guard interaction.reframe(
            on: loadedModel,
            orthographic: session.orthographic,
            preset: preset,
            fieldOfViewDegrees: session.fieldOfViewDegrees
        ) else { return }
        window.sidebar?.overlayRevision += 1
    }

    private func resetPreviewView() {
        window.sidebar?.selectedCameraIndex = nil
        if !window.previewSession.centerModel {
            window.engineViewport.setCenter(true)
            window.sidebar?.overlayRevision += 1
            return
        }
        Task { @MainActor in
            interaction.requestOpeningFitReset()
            window.sidebar?.overlayRevision += 1
        }
    }

    private func renderRealityStill() async throws -> CGImage {
        let session = window.previewSession
        return try await ScreenshotCameraPose.renderReality(
            interaction: interaction,
            dimStudioForFileLights: session.dimStudioForFileLights,
            exposureEV: session.exposureEV,
            backdrop: session.backdrop.rawValue,
            environmentYaw: session.environmentYaw
        )
    }

    private func loadDocument(_ url: URL) {
        let generation: Int
        switch window.beginOpen(url) {
        case .unchanged:
            return
        case .rejected:
            convert = .failed("Not a .glb / .gltf file")
            morphTargets = []
            playbackController = EngineAnimationPlaybackController()
            return
        case .started(let started):
            generation = started
        }
        firstPixelImage = firstPixelNSImage(for: url, renderer: .realityKit)
        Task { await PreviewLighting.prefetchLook(AppLook.current) }
        convert = .loading
        morphTargets = []
        playbackController = EngineAnimationPlaybackController()
        interaction = PreviewInteraction()
        Task {
            let state = await RealityCanvasView.State.loaded(from: url)
            guard window.isCurrent(generation) else { return }
            switch state {
            case .ready(let model):
                window.adopt(
                    document: model.document,
                    materialVariantNames: model.materialVariantNames,
                    sceneModel: EngineSceneModel(loaded: model, fileName: url.lastPathComponent, validation: window.validation),
                    viewModes: model.debugModes.map(\.renderViewMode),
                    dimStudioForFileLights: model.studioIBLExponent < 0
                )
                refreshMorphTargets(from: model)
                playbackController = EngineAnimationPlaybackController(loaded: model)
                logOpenReady(model, url: url)
                AppLog.info(
                    AppLog.host,
                    "pipeline \(url.lastPathComponent) \(model.pipelineReport.entries.joined(separator: " | "))"
                )
                AppLog.info(AppLog.host, model.convertProblems.hostSummary)
                window.finishOpen(.ready)
            case .failed(let message):
                morphTargets = []
                playbackController = EngineAnimationPlaybackController()
                AppLog.error(AppLog.host, "open failed \(url.lastPathComponent): \(message)")
                window.finishOpen(.failed(message))
            case .loading:
                break
            }
            convert = state
        }
    }

    private func logOpenReady(_ model: EntityLoader.LoadedModel, url: URL) {
        let dims = model.extent.dimensions
        let clips = playbackController.clips
        let clipSummary = clips.isEmpty
            ? "none"
            : clips.map { "\($0.name)(\(String(format: "%.3fs", $0.duration)))" }
                .joined(separator: ",")
        AppLog.info(
            AppLog.host,
            "open ready \(url.lastPathComponent) renderer=realitykit nodes=\(model.document.nodes.count) cameras=\(model.document.cameras.count) triangles=\(model.stats.triangleCount) dimensions=\(dims?.readout ?? "empty") emptyBounds=\(dims == nil) clips=\(clipSummary) uptimeMs=\(AppLog.uptimeMs())"
        )
    }

    private func refreshMorphTargets(from model: EntityLoader.LoadedModel) {
        morphTargets = model.morphTargets().map { target in
            MorphTargetControl(
                id: target.id,
                name: target.name,
                weight: Double(target.weight)
            )
        }
    }

    private func applyMorphWeight(id: String, value: Double) {
        guard let model = loadedModel,
              let target = model.morphTargets().first(where: { $0.id == id })
        else { return }
        model.setMorphWeight(nodeIndex: target.nodeIndex, targetIndex: target.targetIndex, value: Float(value))
        if let index = morphTargets.firstIndex(where: { $0.id == id }) {
            morphTargets[index].weight = value
        }
    }

    /// Shared tail of both reload paths: publish the new model, rebuild the per-load caches,
    /// reapply lighting, and refresh morph sliders.
    private func applyReloaded(
        _ reloaded: EntityLoader.LoadedModel,
        fileName: String,
        sidebar: HostSidebarModel
    ) {
        convert = .ready(reloaded)
        window.replaceSceneModel(
            EngineSceneModel(loaded: reloaded, fileName: fileName, validation: window.validation),
            viewModes: reloaded.debugModes.map(\.renderViewMode),
            dimStudioForFileLights: reloaded.studioIBLExponent < 0
        )
        playbackController = EngineAnimationPlaybackController(loaded: reloaded)
        refreshMorphTargets(from: reloaded)
        sidebar.overlayRevision += 1
    }

    private func reloadScene(_ index: Int?) {
        guard let url = documentURL, let index, let sidebar = window.sidebar,
              sidebar.document.scenes.count > 1
        else { return }
        let generation = window.beginReload()
        let variantIndex = sidebar.selectedMaterialVariantIndex
        Task {
            do {
                guard case .ready(let model) = convert else { return }
                let reloaded = try await model.switchingScene(
                    to: index,
                    from: url,
                    materialVariantIndex: variantIndex
                )
                guard window.isCurrent(generation) else { return }
                sidebar.showAll()
                interaction = PreviewInteraction()
                applyReloaded(reloaded, fileName: url.lastPathComponent, sidebar: sidebar)
            } catch {
                guard window.isCurrent(generation) else { return }
                AppLog.error(AppLog.host, "scene switch failed: \(error.localizedDescription)")
            }
        }
    }

    private func reloadMaterialVariant() {
        guard let url = documentURL, let sidebar = window.sidebar else { return }
        let generation = window.beginReload()
        let variantIndex = sidebar.selectedMaterialVariantIndex
        let sceneIndex = sidebar.activeSceneIndex
        let isMultiScene = sidebar.document.scenes.count > 1
        Task {
            do {
                let model = try await EntityLoader.load(
                    from: url,
                    materialVariantIndex: variantIndex,
                    sceneIndex: isMultiScene ? sceneIndex : nil
                )
                guard window.isCurrent(generation) else { return }
                interaction = PreviewInteraction()
                sidebar.materialVariantNames = model.materialVariantNames
                applyReloaded(model, fileName: url.lastPathComponent, sidebar: sidebar)
                AppLog.info(
                    AppLog.host,
                    "variant reload \(url.lastPathComponent) index=\(variantIndex.map(String.init) ?? "default")"
                )
            } catch {
                guard window.isCurrent(generation) else { return }
                AppLog.error(AppLog.host, "variant reload failed: \(error.localizedDescription)")
            }
        }
    }
}
