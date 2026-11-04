import Foundation
import GLTFCore
import Observation

/// One document window: which file it shows, the panels read from that file's JSON, its
/// validation, and how it is shown (`view`). The renderer loads the file itself, in parallel
/// with the panels (`DocumentWindow`).
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
    /// The panels' state. The canvas region has its own (`DocumentWindow.canvasState`).
    private(set) var phase: ShellDocumentState
    /// The file's contents for the outliner and inspector. Nil until the JSON is read.
    private(set) var contents: EngineSceneModel?
    private(set) var validation: GLTFValidationState?
    private(set) var loadGeneration = 0
    private(set) var loadingURL: URL?
    let view: ViewState
    let panels = ShellPanelChrome()
    @ObservationIgnored private var validationTask: Task<Void, Never>?

    /// Tests replace this so scheduling can be asserted without running JavaScriptCore.
    @ObservationIgnored
    var validateFile: @Sendable (URL) async throws -> GLTFValidationReport = {
        try await GLTFValidator.validate(fileAt: $0)
    }

    init(documentURL: URL?, settings: AppSettings? = nil) {
        self.documentURL = documentURL
        phase = documentURL == nil ? .empty : .loading
        view = ViewState(settings: settings ?? .shared)
    }

    /// The panels' snapshot, with validation folded in; an empty one while the file opens.
    var sceneModel: EngineSceneModel {
        let base = contents ?? EngineSceneModel(
            fileName: (loadingURL ?? documentURL)?.lastPathComponent ?? "Model",
            document: GLTFSessionDocument(),
            dimensions: Dimensions(width: 0, height: 0, depth: 0)
        )
        return base.replacingValidation(validation)
    }

    var exportName: String {
        (loadingURL ?? documentURL)?.deletingPathExtension().lastPathComponent ?? "export"
    }

    /// Resets the window for `url`; the caller then loads the panels with `openSummary`.
    /// Validation starts from `noteCanvasReady` after first paint, not here.
    func beginOpen(_ url: URL) -> OpenStart {
        guard DocumentOpening.isGLTFFile(url) else {
            AppLog.error(AppLog.app, "open rejected \(url.lastPathComponent)")
            phase = .failed("Not a .glb / .gltf file")
            contents = nil
            loadingURL = url
            return .rejected
        }
        if loadingURL == url, phase == .loading || phase == .ready, loadGeneration > 0 { return .unchanged }

        phase = .loading
        contents = nil
        validation = nil
        loadingURL = url
        loadGeneration += 1
        view.reset()
        validationTask?.cancel()
        validationTask = nil
        AppLog.info(AppLog.app, "open start \(url.lastPathComponent) bytes=\(fileSize(url)) uptimeMs=\(AppLog.uptimeMs())")
        return .started(generation: loadGeneration)
    }

    /// Panels from the file's JSON alone (`GLTFDocumentSummary`). `load` is injectable for tests.
    func openSummary(
        _ url: URL,
        generation: Int,
        load: (URL) async throws -> GLTFDocumentSummary = GLTFDocumentSummary.load
    ) async {
        do {
            let summary = try await load(url)
            guard generation == loadGeneration else { return }
            contents = EngineSceneModel(summary: summary, fileName: url.lastPathComponent)
            view.sceneIndex = summary.document.defaultSceneIndex
            view.viewModes = summary.viewModes.isEmpty ? [.shaded] : summary.viewModes
            phase = .ready
            let size = summary.bounds.map { "\($0.size.x)x\($0.size.y)x\($0.size.z)" } ?? "empty"
            AppLog.info(
                AppLog.app,
                "open ready \(url.lastPathComponent) nodes=\(summary.document.nodes.count) cameras=\(summary.document.cameras.count) triangles=\(summary.stats.triangleCount) bounds=\(size) uptimeMs=\(AppLog.uptimeMs())"
            )
        } catch {
            guard generation == loadGeneration else { return }
            AppLog.error(AppLog.app, "open failed \(url.lastPathComponent): \(error.localizedDescription)")
            contents = nil
            phase = .failed(error.localizedDescription)
        }
    }

    /// Khronos validation is CPU-heavy (a JSContext and the whole file as base64), so it starts
    /// once the canvas shows the model and does not compete with the first frame.
    func noteCanvasReady() {
        guard let url = loadingURL, validation == nil, validationTask == nil else { return }
        let generation = loadGeneration
        validationTask = Task {
            let state: GLTFValidationState
            do {
                let report = try await validateFile(url)
                state = .success(report)
                AppLog.info(AppLog.app, "validation \(url.lastPathComponent) errors=\(report.errorCount) warnings=\(report.warningCount) validator=\(report.validatorVersion)")
            } catch is CancellationError {
                return
            } catch let error as GLTFValidator.Error where error.isSoftSkip {
                state = .skipped("Validation skipped: \(error.localizedDescription)")
                AppLog.info(AppLog.app, "validation skipped \(url.lastPathComponent): \(error.localizedDescription)")
            } catch {
                state = .failed("Validation unavailable: \(error.localizedDescription)")
                AppLog.error(AppLog.app, "validation failed \(url.lastPathComponent): \(error.localizedDescription)")
            }
            guard !Task.isCancelled, generation == loadGeneration else { return }
            validation = state
        }
    }
}

private func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
}
