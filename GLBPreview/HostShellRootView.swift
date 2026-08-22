import AppKit
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

/// Document window root: PreviewUI `ShellRootView` + engine adapters + real `PreviewView` canvas.
///
/// Pills / selection / settings wiring lands in follow-up tasks — this checkpoint proves open →
/// shell chrome → RealityKit canvas. Old `HostOutlinerView` stays in the tree unused.
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
    @State private var blenderLaunchError: String?
    @State private var panels = ShellPanelChrome()
    @State private var placeholderSidebar = HostSidebarModel(document: GLTFSessionDocument())

    /// P34 per-window session for the RealityKit canvas — seeded from Settings; never written back.
    /// Not yet driven by `EngineViewportController` (next subtask).
    @State private var sessionAutoRotate =
        UserDefaults.standard.object(forKey: SettingsKeys.autoRotate) as? Bool ?? true
    @State private var sessionShowFloor =
        UserDefaults.standard.object(forKey: SettingsKeys.showFloor) as? Bool ?? true
    @State private var sessionBackdropIndex = PreviewBackground.storedIndex
    @State private var sessionCenterModel = true
    @State private var sessionOrthographic = false
    @State private var sessionExposureEV: Float = 0
    @State private var sessionDimStudioForFileLights = false
    @State private var sessionEnvironmentYaw: Float = 0
    @State private var sessionDoubleSided = false
    @State private var sessionShowSkeleton = false
    @State private var sessionFieldOfViewDegrees = PreviewCamera.defaultFieldOfViewDegrees

    @State private var validation: GLTFValidationState?
    @State private var validationGeneration = 0
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        shellRoot
            .focusedSceneValue(\.previewCommands, focusedPreviewCommands)
            .focusedSceneValue(\.previewSession, loadedModel == nil ? nil : previewSession.focusedMenu)
            .alert(
                "Couldn’t open in Blender",
                isPresented: Binding(
                    get: { blenderLaunchError != nil },
                    set: { if !$0 { blenderLaunchError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(blenderLaunchError ?? "")
            }
            .onAppear {
                dismissWindow(id: WelcomeWindow.id)
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
            .onDrop(of: [.fileURL], isTargeted: nil) {
                GLBDocumentOpening.handleDrop($0, openDocument: openDocument)
            }
    }

    @ViewBuilder
    private var shellRoot: some View {
        let activeSidebar = sidebar ?? placeholderSidebar
        let model = engineSceneModel
        let availability = EngineAvailability.make(model: model, debugModes: loadedDebugModes)
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
            viewport: EngineViewportController(
                sidebar: activeSidebar,
                backdrop: sessionBackdropStyle,
                showsFloor: sessionShowFloor,
                autoRotates: sessionAutoRotate,
                isCentered: sessionCenterModel,
                projection: sessionOrthographic ? .orthographic : .perspective,
                exposureEV: sessionExposureEV,
                dimStudioForFileLights: sessionDimStudioForFileLights,
                environmentYawRadians: sessionEnvironmentYaw,
                commands: focusedPreviewCommands
            ),
            settings: EngineSettingsStore(),
            playback: playback,
            panels: panels,
            seedSession: seedSession,
            onScreenshot: { screenshotCurrentCameraPose() }
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
        // Remount when open settles so `@State` adapters bind the real sidebar / entity
        // (ShellRootView only takes the autoclosure initial value once).
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

    private var sessionBackdropStyle: BackdropStyle {
        let background = PreviewBackground.at(sessionBackdropIndex)
        return BackdropStyle(rawValue: background.rawValue) ?? .window
    }

    private var loadedModel: EntityLoader.LoadedModel? {
        if case .ready(let model) = previewState { return model }
        return nil
    }

    private var previewSession: PreviewSessionBindings {
        PreviewSessionBindings(
            autoRotate: $sessionAutoRotate,
            showFloor: $sessionShowFloor,
            backdropIndex: $sessionBackdropIndex,
            centerModel: $sessionCenterModel,
            orthographic: $sessionOrthographic,
            exposureEV: $sessionExposureEV,
            dimStudioForFileLights: $sessionDimStudioForFileLights,
            environmentYaw: $sessionEnvironmentYaw,
            doubleSided: $sessionDoubleSided,
            showSkeleton: $sessionShowSkeleton,
            fieldOfViewDegrees: $sessionFieldOfViewDegrees
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

    /// Defaults → viewport only (AGENTS.md: never in `View.init`). Canvas session stays separate
    /// until the interaction-wiring subtask.
    @MainActor
    private func seedSession(settings: EngineSettingsStore, viewport: EngineViewportController) {
        viewport.setAutoRotate(settings.sessionValue(for: .autoRotate))
        viewport.setFloor(settings.sessionValue(for: .showFloor))
        viewport.setBackdrop(settings.sessionValue(for: .backdrop))
        viewport.setCenter(settings.sessionValue(for: .center))
        viewport.setProjection(settings.sessionValue(for: .projection))
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
                orthographic: sessionOrthographic,
                preset: preset,
                fieldOfViewInDegrees: sessionFieldOfViewDegrees
            )
        } else {
            PreviewCamera.applyFit(
                to: camera,
                bounds: bounds,
                orbitFocus: interaction.orbitFocus,
                orthographic: sessionOrthographic,
                fieldOfViewInDegrees: sessionFieldOfViewDegrees
            )
        }
        interaction.markFitted()
        sidebar?.overlayRevision += 1
    }

    private func resetPreviewView() {
        sidebar?.selectedCameraIndex = nil
        if !sessionCenterModel {
            sessionCenterModel = true
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
            backdropIndex: sessionBackdropIndex,
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
        validation = nil
        interaction = PreviewInteraction()
        loadingURL = url
        loadGeneration += 1
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
                sidebar = HostSidebarModel(document: model.document)
                sidebar?.materialVariantNames = model.materialVariantNames
                AppLog.info(
                    AppLog.host,
                    "pipeline \(url.lastPathComponent) \(model.pipelineReport.entries.joined(separator: " | "))"
                )
            } else if case .failed(let message) = state {
                sidebar = nil
                AppLog.error(AppLog.host, "open failed \(url.lastPathComponent): \(message)")
            }
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
