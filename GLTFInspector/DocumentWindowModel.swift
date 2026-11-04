import Foundation
import GLTFCore
import Observation
import PreviewUI

/// Per-window state: sidebar, settings overlay, viewport, the open / validation lifecycle and the
/// chrome snapshot. The web page controller lives in the window root (`DocumentWindow`).
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
    /// Panel state (sidebar / inspector); `DocumentWindow` decides the canvas region's.
    private(set) var phase: ShellDocumentState = .loading
    private(set) var sidebar: HostSidebarModel? {
        didSet {
            selection = EngineSelectionModel(sidebar: activeSidebar)
            engineViewport.sidebar = activeSidebar
        }
    }
    let placeholderSidebar = HostSidebarModel(document: GLTFSessionDocument())
    /// Window-owned selection adapter over `activeSidebar`, rebuilt only when the sidebar is
    /// replaced (open / adopt / failure) — never in a view body, so `ShellRootView` keeps it.
    /// The viewport follows the same sidebar.
    private(set) var selection: EngineSelectionModel
    private(set) var loadGeneration = 0
    private(set) var loadingURL: URL?
    let panels = ShellPanelChrome()
    /// Per-window lazy overlay — not seed-once `@State` from UserDefaults.
    let settings = EngineSettingsStore()
    let previewSession: PreviewSession
    let engineViewport: EngineViewportController
    private(set) var validation: GLTFValidationState?
    @ObservationIgnored private var validationGeneration = 0
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    /// Built once per loaded document, not per render; async validation is folded in by
    /// `sceneModel`.
    private var loadedSceneModel: EngineSceneModel?

    init(documentURL: URL?) {
        self.documentURL = documentURL
        selection = EngineSelectionModel(sidebar: placeholderSidebar)
        previewSession = PreviewSession(settings: settings)
        engineViewport = EngineViewportController(sidebar: placeholderSidebar, previewSession: previewSession)
        engineViewport.saveScreenshot = { [weak self] image in
            await ScreenshotCameraPose.save(image, suggestedName: self?.exportName ?? "export")
        }
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

    var exportName: String {
        (loadingURL ?? documentURL)?.deletingPathExtension().lastPathComponent ?? "export"
    }

    func failMissingURL() {
        phase = .failed("The document URL is missing.")
    }

    /// Resets the window for `url`; the caller then loads the panels with `openSummary`.
    /// Validation starts from `noteCanvasReady` after first paint — not here.
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
        engineViewport.applySession()
        AppLog.info(AppLog.host, "open start \(url.lastPathComponent) bytes=\(fileSize(url)) uptimeMs=\(AppLog.uptimeMs())")
        validationTask?.cancel()
        return .started(generation: loadGeneration)
    }

    /// Khronos validation is CPU-heavy (new JSContext + whole-file base64). Call once the
    /// page reports `.ready`, so it does not compete with the first frame.
    func noteCanvasReady() {
        guard let url = loadingURL, validation == nil else { return }
        startValidation(of: url, generation: loadGeneration)
    }

    private func finish(_ phase: ShellDocumentState) {
        if case .failed = phase {
            sidebar = nil
            loadedSceneModel = nil
        }
        self.phase = phase
    }

    /// Panels from the file's JSON alone (`GLTFDocumentSummary`); the page loads the file itself.
    /// `load` is injectable for tests.
    func openSummary(
        _ url: URL,
        generation: Int,
        load: (URL) async throws -> GLTFDocumentSummary = GLTFDocumentSummary.load
    ) async {
        do {
            let summary = try await load(url)
            guard generation == loadGeneration else { return }
            let modelSidebar = HostSidebarModel(document: summary.document)
            modelSidebar.materialVariantNames = summary.materialVariantNames
            sidebar = modelSidebar
            previewSession.viewModes = summary.viewModes.isEmpty ? [.shaded] : summary.viewModes
            engineViewport.setViewMode(.shaded)
            loadedSceneModel = EngineSceneModel(
                summary: summary,
                fileName: url.lastPathComponent,
                validation: validation
            )
            let size = summary.bounds.map { "\($0.size.x)x\($0.size.y)x\($0.size.z)" } ?? "empty"
            AppLog.info(
                AppLog.host,
                "open ready \(url.lastPathComponent) nodes=\(summary.document.nodes.count) cameras=\(summary.document.cameras.count) triangles=\(summary.stats.triangleCount) bounds=\(size) uptimeMs=\(AppLog.uptimeMs())"
            )
            finish(.ready)
        } catch {
            guard generation == loadGeneration else { return }
            AppLog.error(AppLog.host, "open failed \(url.lastPathComponent): \(error.localizedDescription)")
            finish(.failed(error.localizedDescription))
        }
    }

    /// Tests replace this so scheduling can be asserted without running JavaScriptCore.
    @ObservationIgnored
    var validateFile: @Sendable (URL) async throws -> GLTFValidationReport = {
        try await GLTFValidator.validate(fileAt: $0)
    }

    private func startValidation(of url: URL, generation: Int) {
        if validationTask != nil, validationGeneration == generation { return }
        validationTask?.cancel()
        validationGeneration = generation
        let validationGen = validationGeneration
        validationTask = Task {
            do {
                let report = try await validateFile(url)
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

private func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
}
