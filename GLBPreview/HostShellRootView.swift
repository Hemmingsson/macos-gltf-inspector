import RealityKit
import SwiftUI

/// Document window root: PreviewUI `ShellRootView` + engine adapters + real `PreviewView` canvas.
///
/// Pills / selection / screenshot / playback / scene+variant write through the engine adapters into
/// host session + `HostSidebarModel`. Settings-backed keys use `EngineSettingsStore` lazy overlay
/// (untouched keys track defaults live). Host canvas is bare (`showsInlineChrome == false`).
struct HostShellRootView: View {
    let documentURL: URL?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openDocument) private var openDocument
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var previewState: PreviewView.State = .loading
    @State private var interaction = PreviewInteraction()
    @State private var sidebar: HostSidebarModel?
    @State private var loadGeneration = 0
    @State private var loadingURL: URL?
    @State private var panels = ShellPanelChrome()
    @State private var placeholderSidebar = HostSidebarModel(document: GLTFSessionDocument())

    /// Per-window lazy overlay — not seed-once `@State` from UserDefaults.
    @State private var settings = EngineSettingsStore()
    @State private var engineViewport: EngineViewportController

    /// Session-only canvas extras (not SettingsStore keys yet).
    @State private var sessionExposureEV: Float = 0
    @State private var sessionDimStudioForFileLights = false
    @State private var sessionEnvironmentYaw: Float = 0
    @State private var sessionDoubleSided = false
    @State private var sessionShowSkeleton = false
    @State private var sessionFieldOfViewDegrees = PreviewCamera.defaultFieldOfViewDegrees
    @State private var sessionDebugModeIndex = 0
    /// Mirror of settings-backed + session-only keys for `PreviewView` / RealityKit.
    @State private var canvasAutoRotate = true
    @State private var canvasShowFloor = true
    @State private var canvasBackdropIndex = 0
    @State private var canvasCenterModel = true
    @State private var canvasOrthographic = false

    @State private var validation: GLTFValidationState?
    @State private var validationGeneration = 0
    @State private var validationTask: Task<Void, Never>?
    /// Inspector morph sliders — mirrored from `PreviewMorph` on the loaded entity.
    @State private var morphTargets: [MorphTargetControl] = []

    init(documentURL: URL?) {
        self.documentURL = documentURL
        let placeholder = HostSidebarModel(document: GLTFSessionDocument())
        _placeholderSidebar = State(wrappedValue: placeholder)
        _engineViewport = State(
            wrappedValue: EngineViewportController(sidebar: placeholder)
        )
    }

    var body: some View {
        shellRoot
            .focusedSceneValue(\.previewCommands, focusedPreviewCommands)
            .focusedSceneValue(\.engineViewport, loadedModel == nil ? nil : engineViewport)
            .focusedSceneValue(\.shellPanelChrome, panels)
            .onAppear {
                dismissWindow(id: WelcomeWindow.id)
                wireViewportHostSession()
                if let documentURL {
                    loadDocument(documentURL)
                } else {
                    previewState = .failed("The document URL is missing.")
                }
            }
            .onChange(of: documentURL) { _, url in
                if let url {
                    loadDocument(url)
                }
            }
            .onChange(of: sidebar?.activeSceneIndex) { previous, index in
                guard previous != nil else { return }
                reloadScene(index)
            }
            .onChange(of: sidebar?.selectedMaterialVariantIndex) { previous, _ in
                guard previous != nil || sidebar?.selectedMaterialVariantIndex != nil else { return }
                reloadMaterialVariant()
            }
            .onChange(of: settings.defaultsStore.revision) { _, _ in
                // Live-track canvas for keys that still have no session override.
                engineViewport.syncHostCanvasFromStored()
            }
            .onDrop(of: [.fileURL], isTargeted: nil) {
                GLBDocumentOpening.handleDrop($0, openDocument: openDocument)
            }
    }

    @ViewBuilder
    private var shellRoot: some View {
        let activeSidebar = sidebar ?? placeholderSidebar
        let model = engineSceneModel
        let availability = DerivedAvailability(
            model: model,
            channels: EngineSceneModel.mapDebugChannels(loadedDebugModes)
        )
        let playback: EngineAnimationPlaybackController = {
            if case .ready(let loaded) = previewState {
                return EngineAnimationPlaybackController(loaded: loaded)
            }
            return EngineAnimationPlaybackController(entity: Entity(), clips: [])
        }()

        ShellRootView(
            model: model,
            availability: availability,
            documentState: shellDocumentState,
            selection: EngineSelectionModel(sidebar: activeSidebar),
            viewport: engineViewport,
            settings: settings,
            playback: playback,
            panels: panels,
            morphTargets: morphTargets,
            onSetMorphWeight: applyMorphWeight,
            seedSession: seedSession
        ) {
            HostPreviewContainer(
                state: previewState,
                interaction: interaction,
                isDark: colorScheme == .dark,
                sidebar: sidebar,
                overlayRevision: sidebar?.overlayRevision ?? 0,
                session: previewSession
            )
        }
        // Remount adapters that capture sidebar/entity once; keep settings + viewport identity.
        .id(shellMountID)
    }

    private var shellMountID: String {
        switch previewState {
        case .loading:
            "loading-\(loadGeneration)"
        case .ready:
            "ready-\(loadGeneration)"
        case .failed(let message):
            "failed-\(loadGeneration)-\(message)"
        }
    }

    private var shellDocumentState: ShellDocumentState {
        if documentURL == nil {
            return .failed("The document URL is missing.")
        }
        switch previewState {
        case .loading:
            return .loading
        case .ready:
            return .ready
        case .failed(let message):
            return .failed(message)
        }
    }

    private var engineSceneModel: EngineSceneModel {
        let fileName = (loadingURL ?? documentURL)?.lastPathComponent ?? "Model"
        if case .ready(let loaded) = previewState {
            return EngineSceneModel(loaded: loaded, fileName: fileName, validation: validation)
        }
        return EngineSceneModel(
            fileName: fileName,
            document: GLTFSessionDocument(),
            stats: Self.emptyStats,
            dimensions: Dimensions(width: 0, height: 0, depth: 0, authoredOrigin: .zero),
            validation: validation,
            pipelineReport: PreparePipelineReport(),
            materialVariantNames: []
        )
    }

    private var loadedDebugModes: [PreviewDebugMode] {
        if case .ready(let loaded) = previewState {
            return loaded.debugModes
        }
        return []
    }

    private var loadedModel: EntityLoader.LoadedModel? {
        if case .ready(let model) = previewState { return model }
        return nil
    }

    private var previewSession: PreviewSessionBindings {
        PreviewSessionBindings(
            autoRotate: $canvasAutoRotate,
            showFloor: $canvasShowFloor,
            backdropIndex: $canvasBackdropIndex,
            centerModel: $canvasCenterModel,
            orthographic: $canvasOrthographic,
            exposureEV: $sessionExposureEV,
            dimStudioForFileLights: $sessionDimStudioForFileLights,
            environmentYaw: $sessionEnvironmentYaw,
            doubleSided: $sessionDoubleSided,
            showSkeleton: $sessionShowSkeleton,
            fieldOfViewDegrees: $sessionFieldOfViewDegrees,
            debugModeIndex: $sessionDebugModeIndex,
            debugModes: loadedDebugModes.isEmpty ? [.none] : loadedDebugModes
        )
    }

    private var focusedPreviewCommands: FocusedPreviewCommands? {
        guard loadedModel != nil else { return nil }
        return FocusedPreviewCommands(
            fit: { reframingCamera() },
            reset: resetPreviewView,
            applyCameraPreset: { reframingCamera(preset: $0) },
            screenshot: screenshotCurrentCameraPose
        )
    }

    /// Defaults → viewport → host canvas (AGENTS.md: never in `View.init`).
    @MainActor
    private func seedSession(settings: EngineSettingsStore) {
        engineViewport.sidebar = sidebar ?? placeholderSidebar
        wireViewportHostSession()
        engineViewport.applySession(from: settings)
    }

    private func wireViewportHostSession() {
        engineViewport.hostSession = previewSession
        engineViewport.settings = settings
        engineViewport.commands = focusedPreviewCommands
        engineViewport.screenshotHandler = screenshotCurrentCameraPose
    }

    private func reframingCamera(preset: PreviewCamera.CameraPreset? = nil) {
        sidebar?.selectedCameraIndex = nil
        guard let camera = interaction.camera,
              let entity = loadedModel?.entity
        else {
            interaction.markFitted()
            return
        }
        let bounds = PreviewCamera.modelBounds(of: entity, relativeTo: nil)
        guard !bounds.isEmpty else {
            interaction.markFitted()
            return
        }
        if let preset {
            PreviewCamera.applyFit(
                to: camera,
                bounds: bounds,
                orbitFocus: interaction.orbitFocus,
                orthographic: canvasOrthographic,
                preset: preset,
                fieldOfViewInDegrees: sessionFieldOfViewDegrees
            )
        } else {
            PreviewCamera.applyFit(
                to: camera,
                bounds: bounds,
                orbitFocus: interaction.orbitFocus,
                orthographic: canvasOrthographic,
                fieldOfViewInDegrees: sessionFieldOfViewDegrees
            )
        }
        interaction.markFitted()
        sidebar?.overlayRevision += 1
    }

    private func resetPreviewView() {
        sidebar?.selectedCameraIndex = nil
        if !canvasCenterModel {
            engineViewport.setCenter(true)
            sidebar?.overlayRevision += 1
            return
        }
        Task { @MainActor in
            interaction.requestOpeningFitReset()
            sidebar?.overlayRevision += 1
        }
    }

    private func screenshotCurrentCameraPose() {
        guard let camera = interaction.camera,
              let pivot = interaction.orbitFocus
        else {
            AppLog.error(AppLog.host, "screenshot skipped — no live camera pose")
            return
        }
        let suggested = (loadingURL ?? documentURL)?
            .deletingPathExtension()
            .lastPathComponent ?? "screenshot"
        ScreenshotCameraPose.capture(
            camera: camera,
            pivot: pivot,
            dimStudioForFileLights: sessionDimStudioForFileLights,
            exposureEV: sessionExposureEV,
            backdropIndex: canvasBackdropIndex,
            environmentYaw: sessionEnvironmentYaw,
            suggestedName: suggested
        )
    }

    private func loadDocument(_ url: URL) {
        guard GLBDocumentOpening.isGLBFile(url) else {
            let message = "Not a .glb / .gltf file"
            AppLog.error(AppLog.host, "open rejected \(url.lastPathComponent)")
            previewState = .failed(message)
            sidebar = nil
            loadingURL = url
            return
        }
        if loadingURL == url, case .loading = previewState { return }
        if case .ready = previewState, loadingURL == url, sidebar != nil { return }

        previewState = .loading
        sidebar = nil
        morphTargets = []
        validation = nil
        interaction = PreviewInteraction()
        loadingURL = url
        loadGeneration += 1
        // New document in this window: drop session overrides and re-track defaults.
        settings.clearSession()
        engineViewport.syncHostCanvasFromStored()
        let generation = loadGeneration
        AppLog.info(AppLog.host, "open start \(url.lastPathComponent) bytes=\(fileSize(url))")
        startValidation(of: url, generation: generation)
        Task {
            let state = await PreviewView.State.loaded(from: url)
            guard generation == loadGeneration else { return }
            previewState = state
            if case .ready(let model) = state {
                let dims = PreviewCamera.dimensions(of: model.entity, relativeTo: model.entity)
                let clips = PreviewClip.usable(on: model.entity, document: model.document)
                let clipSummary = clips.isEmpty
                    ? "none"
                    : clips.map { "\($0.title)(\(String(format: "%.3fs", $0.duration)))" }
                        .joined(separator: ",")
                AppLog.info(
                    AppLog.host,
                    "open ready \(url.lastPathComponent) nodes=\(model.document.nodes.count) cameras=\(model.document.cameras.count) triangles=\(model.stats.triangleCount) dimensions=\(dims?.readout ?? "empty") emptyBounds=\(dims == nil) clips=\(clipSummary)"
                )
                sessionDimStudioForFileLights = model.studioIBLExponent < 0
                sessionExposureEV = 0
                sessionEnvironmentYaw = 0
                sessionDebugModeIndex = 0
                let modelSidebar = HostSidebarModel(document: model.document)
                modelSidebar.materialVariantNames = model.materialVariantNames
                sidebar = modelSidebar
                engineViewport.sidebar = modelSidebar
                wireViewportHostSession()
                refreshMorphTargets(from: model.entity)
                AppLog.info(
                    AppLog.host,
                    "pipeline \(url.lastPathComponent) \(model.pipelineReport.entries.joined(separator: " | "))"
                )
            } else if case .failed(let message) = state {
                sidebar = nil
                morphTargets = []
                AppLog.error(AppLog.host, "open failed \(url.lastPathComponent): \(message)")
            }
        }
    }

    private func refreshMorphTargets(from entity: Entity) {
        morphTargets = PreviewMorph.targets(in: entity).map { target in
            MorphTargetControl(
                id: target.id,
                name: target.name,
                weight: Double(target.weight)
            )
        }
    }

    private func applyMorphWeight(id: String, value: Double) {
        guard let entity = loadedModel?.entity,
              let target = PreviewMorph.targets(in: entity).first(where: { $0.id == id })
        else { return }
        PreviewMorph.setWeight(
            nodeIndex: target.nodeIndex,
            targetIndex: target.targetIndex,
            value: Float(value),
            in: entity
        )
        if let index = morphTargets.firstIndex(where: { $0.id == id }) {
            morphTargets[index].weight = value
        }
    }

    private func startValidation(of url: URL, generation: Int) {
        validationTask?.cancel()
        validationGeneration += 1
        let validationGen = validationGeneration
        validationTask = Task {
            do {
                let report = try await GLTFValidator.validate(fileAt: url)
                try Task.checkCancellation()
                guard generation == loadGeneration, validationGen == validationGeneration else { return }
                validation = .success(report)
                AppLog.info(
                    AppLog.host,
                    "validation \(url.lastPathComponent) errors=\(report.errorCount) warnings=\(report.warningCount) validator=\(report.validatorVersion)"
                )
            } catch is CancellationError {
                return
            } catch let error as GLTFValidator.Error {
                guard !Task.isCancelled else { return }
                guard generation == loadGeneration, validationGen == validationGeneration else { return }
                if error.isSoftSkip {
                    let message = "Validation skipped: \(error.localizedDescription)"
                    validation = .skipped(message)
                    AppLog.info(AppLog.host, "validation skipped \(url.lastPathComponent): \(error.localizedDescription)")
                } else {
                    let message = "Validation unavailable: \(error.localizedDescription)"
                    validation = .failed(message)
                    AppLog.error(AppLog.host, "validation failed \(url.lastPathComponent): \(error.localizedDescription)")
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard generation == loadGeneration, validationGen == validationGeneration else { return }
                let message = "Validation unavailable: \(error.localizedDescription)"
                validation = .failed(message)
                AppLog.error(AppLog.host, "validation failed \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func reloadScene(_ index: Int?) {
        guard let url = documentURL, let index, let sidebar, sidebar.document.scenes.count > 1 else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let variantIndex = sidebar.selectedMaterialVariantIndex
        Task {
            do {
                let entity = try await EntityLoader.convertScene(
                    index: index,
                    from: url,
                    materialVariantIndex: variantIndex
                )
                guard generation == loadGeneration else { return }
                guard case .ready(let model) = previewState else { return }
                sidebar.showAll()
                interaction = PreviewInteraction()
                previewState = .ready(
                    EntityLoader.LoadedModel(
                        entity: entity,
                        stats: model.stats,
                        document: model.document,
                        debugModes: model.debugModes,
                        studioIBLExponent: PreviewEmissive.studioIBLExponent(
                            punctualLightCount: EntityLoader.punctualLightCount(in: entity)
                        ),
                        pipelineReport: model.pipelineReport,
                        materialVariantNames: model.materialVariantNames
                    )
                )
                if case .ready(let loaded) = previewState {
                    sessionDimStudioForFileLights = loaded.studioIBLExponent < 0
                    refreshMorphTargets(from: loaded.entity)
                }
                sidebar.overlayRevision += 1
            } catch {
                guard generation == loadGeneration else { return }
                let message = error.localizedDescription
                AppLog.error(AppLog.host, "scene switch failed: \(message)")
            }
        }
    }

    private func reloadMaterialVariant() {
        guard let url = documentURL, let sidebar else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let variantIndex = sidebar.selectedMaterialVariantIndex
        let sceneIndex = sidebar.activeSceneIndex
        Task {
            do {
                let model = try await EntityLoader.load(
                    from: url,
                    materialVariantIndex: variantIndex
                )
                guard generation == loadGeneration else { return }
                let entity: Entity
                if model.document.scenes.count > 1 {
                    entity = try await EntityLoader.convertScene(
                        index: sceneIndex,
                        from: url,
                        materialVariantIndex: variantIndex
                    )
                } else {
                    entity = model.entity
                }
                guard generation == loadGeneration else { return }
                interaction = PreviewInteraction()
                previewState = .ready(
                    EntityLoader.LoadedModel(
                        entity: entity,
                        stats: model.stats,
                        document: model.document,
                        debugModes: model.debugModes,
                        studioIBLExponent: model.studioIBLExponent,
                        pipelineReport: model.pipelineReport,
                        materialVariantNames: model.materialVariantNames
                    )
                )
                sidebar.materialVariantNames = model.materialVariantNames
                sessionDimStudioForFileLights = model.studioIBLExponent < 0
                refreshMorphTargets(from: entity)
                sidebar.overlayRevision += 1
                AppLog.info(
                    AppLog.host,
                    "variant reload \(url.lastPathComponent) index=\(variantIndex.map(String.init) ?? "default")"
                )
            } catch {
                guard generation == loadGeneration else { return }
                AppLog.error(AppLog.host, "variant reload failed: \(error.localizedDescription)")
            }
        }
    }

    private static let emptyStats = PreviewStats(
        triangleCount: 0,
        vertexCount: 0,
        materialCount: 0,
        pbrLabel: "—",
        animationCount: 0,
        textureCount: 0,
        maxTextureEdge: nil,
        hasVertexColors: false,
        isRigged: false,
        morphGeometryCount: 0,
        fileSizeBytes: nil
    )
}

private func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
}
