import Foundation
import GLTFCore
import Observation
import PreviewUI

/// Per-window state both renderer windows share: sidebar, settings overlay, viewport, the
/// open / validation lifecycle and the chrome snapshot. Renderer state (convert result, page
/// controller) lives in the window root under `RealityKit/` or `WebKit/`.
@MainActor
@Observable
final class DocumentWindowModel {
    enum OpenStart {
        /// Load `url` for this generation; drop the result if `generation` moved on.
        case started(generation: Int)
        /// Not a glTF file: the window already shows the failure.
        case rejected
        /// Already open or opening.
        case unchanged
    }

    var documentURL: URL?
    /// Panel state (sidebar / inspector); the renderer root decides the canvas region's.
    private(set) var phase: ShellDocumentState = .loading
    private(set) var sidebar: HostSidebarModel?
    let placeholderSidebar = HostSidebarModel(document: GLTFSessionDocument())
    private(set) var loadGeneration = 0
    private(set) var loadingURL: URL?
    let panels = ShellPanelChrome()
    /// Per-window lazy overlay — not seed-once `@State` from UserDefaults.
    let settings = EngineSettingsStore()
    let previewSession = PreviewSession()
    let engineViewport: EngineViewportController
    private(set) var validation: GLTFValidationState?
    @ObservationIgnored private var validationGeneration = 0
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    /// Built once per loaded document, not per render; async validation is folded in by
    /// `sceneModel`.
    private var loadedSceneModel: EngineSceneModel?

    init(documentURL: URL?) {
        self.documentURL = documentURL
        engineViewport = EngineViewportController(sidebar: placeholderSidebar, previewSession: previewSession)
    }

    var activeSidebar: HostSidebarModel { sidebar ?? placeholderSidebar }

    var hasLoadedDocument: Bool { loadedSceneModel != nil }

    var sceneModel: EngineSceneModel {
        if let loadedSceneModel {
            return loadedSceneModel.replacingValidation(validation)
        }
        let fileName = (loadingURL ?? documentURL)?.lastPathComponent ?? "Model"
        return EngineSceneModel(
            fileName: fileName,
            document: GLTFSessionDocument(),
            stats: PreviewStats.empty,
            dimensions: Dimensions(width: 0, height: 0, depth: 0, authoredOrigin: .zero),
            validation: validation
        )
    }

    /// Remounts the shell adapters that capture sidebar / playback once.
    var mountID: String {
        switch phase {
        case .empty, .loading: "loading-\(loadGeneration)"
        case .ready: "ready-\(loadGeneration)"
        case .failed(let message): "failed-\(loadGeneration)-\(message)"
        }
    }

    var exportName: String {
        (loadingURL ?? documentURL)?.deletingPathExtension().lastPathComponent ?? "export"
    }

    /// Wires the viewport to this window's session, settings and save panel. Idempotent.
    func wire() {
        engineViewport.previewSession = previewSession
        engineViewport.settings = settings
        engineViewport.saveScreenshot = { [weak self] image in
            await ScreenshotCameraPose.save(image, suggestedName: self?.exportName ?? "export")
        }
    }

    /// Defaults → viewport → host canvas (AGENTS.md: never in `View.init`).
    func seedSession(settings: EngineSettingsStore) {
        engineViewport.sidebar = activeSidebar
        wire()
        engineViewport.applySession(from: settings)
    }

    func failMissingURL() {
        phase = .failed("The document URL is missing.")
    }

    /// Resets the window for `url` and starts validation. The caller loads its renderer's chrome
    /// and ends with `finishOpen`.
    func beginOpen(_ url: URL) -> OpenStart {
        guard DocumentOpening.isGLTFFile(url) else {
            AppLog.error(AppLog.host, "open rejected \(url.lastPathComponent)")
            phase = .failed("Not a .glb / .gltf file")
            sidebar = nil
            loadingURL = url
            loadedSceneModel = nil
            return .rejected
        }
        if loadingURL == url, case .loading = phase, loadGeneration > 0 { return .unchanged }
        if case .ready = phase, loadingURL == url, sidebar != nil { return .unchanged }

        phase = .loading
        sidebar = nil
        validation = nil
        loadedSceneModel = nil
        previewSession.viewModes = [.shaded]
        loadingURL = url
        loadGeneration += 1
        // New document in this window: drop session overrides and re-track defaults.
        settings.clearSession()
        engineViewport.applySession(from: settings)
        AppLog.info(AppLog.host, "open start \(url.lastPathComponent) bytes=\(fileSize(url)) uptimeMs=\(uptimeMs())")
        startValidation(of: url, generation: loadGeneration)
        return .started(generation: loadGeneration)
    }

    func isCurrent(_ generation: Int) -> Bool { generation == loadGeneration }

    /// A scene / variant reload of the same document: invalidates in-flight loads.
    func beginReload() -> Int {
        loadGeneration += 1
        return loadGeneration
    }

    /// The loaded document's chrome. Resets exposure / yaw and the view mode, as a fresh open does.
    func adopt(
        document: GLTFSessionDocument,
        materialVariantNames: [String],
        sceneModel: EngineSceneModel,
        viewModes: [RenderViewMode],
        dimStudioForFileLights: Bool
    ) {
        let modelSidebar = HostSidebarModel(document: document)
        modelSidebar.materialVariantNames = materialVariantNames
        sidebar = modelSidebar
        engineViewport.sidebar = modelSidebar
        wire()
        previewSession.viewModes = viewModes.isEmpty ? [.shaded] : viewModes
        engineViewport.applyConvertedLighting(
            dimStudioForFileLights: dimStudioForFileLights,
            resetExposureAndYaw: true
        )
        engineViewport.setViewMode(.shaded)
        loadedSceneModel = sceneModel
    }

    /// A reload of the open document (scene / variant) keeps the sidebar and session.
    func replaceSceneModel(
        _ sceneModel: EngineSceneModel,
        viewModes: [RenderViewMode],
        dimStudioForFileLights: Bool
    ) {
        loadedSceneModel = sceneModel
        previewSession.viewModes = viewModes.isEmpty ? [.shaded] : viewModes
        engineViewport.applyConvertedLighting(
            dimStudioForFileLights: dimStudioForFileLights,
            resetExposureAndYaw: false
        )
    }

    func finishOpen(_ phase: ShellDocumentState) {
        if case .failed = phase {
            sidebar = nil
            loadedSceneModel = nil
        }
        self.phase = phase
    }

    /// Panels from the file's JSON alone (`GLTFDocumentSummary`) — no renderer convert. Used by
    /// a canvas that loads the file itself. `load` is injectable for tests.
    func openSummary(
        _ url: URL,
        generation: Int,
        renderer: RendererKind,
        load: (URL) async throws -> GLTFDocumentSummary = GLTFDocumentSummary.load
    ) async {
        do {
            let summary = try await load(url)
            guard isCurrent(generation) else { return }
            adopt(
                document: summary.document,
                materialVariantNames: summary.materialVariantNames,
                sceneModel: EngineSceneModel(summary: summary, fileName: url.lastPathComponent, validation: validation),
                viewModes: summary.viewModes,
                dimStudioForFileLights: !summary.document.lights.isEmpty
            )
            let size = summary.bounds.map { "\($0.size.x)x\($0.size.y)x\($0.size.z)" } ?? "empty"
            AppLog.info(
                AppLog.host,
                "open ready \(url.lastPathComponent) renderer=\(renderer.rawValue) nodes=\(summary.document.nodes.count) cameras=\(summary.document.cameras.count) triangles=\(summary.stats.triangleCount) bounds=\(size) uptimeMs=\(uptimeMs())"
            )
            finishOpen(.ready)
        } catch {
            guard isCurrent(generation) else { return }
            AppLog.error(AppLog.host, "open failed \(url.lastPathComponent): \(error.localizedDescription)")
            finishOpen(.failed(error.localizedDescription))
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
            } catch {
                guard !Task.isCancelled else { return }
                guard generation == loadGeneration, validationGen == validationGeneration else { return }
                if let error = error as? GLTFValidator.Error, error.isSoftSkip {
                    validation = .skipped("Validation skipped: \(error.localizedDescription)")
                    AppLog.info(AppLog.host, "validation skipped \(url.lastPathComponent): \(error.localizedDescription)")
                } else {
                    validation = .failed("Validation unavailable: \(error.localizedDescription)")
                    AppLog.error(AppLog.host, "validation failed \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }
}

/// Process uptime in ms, for ordering host and canvas log lines (the log stamps are seconds).
func uptimeMs() -> Int {
    Int(ProcessInfo.processInfo.systemUptime * 1000)
}

private func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
}
