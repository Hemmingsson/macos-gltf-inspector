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
    private(set) var phase: DocumentState
    /// What the file contains, for the outliner and inspector. Empty until the JSON is read.
    private(set) var document = GLTFDocument()
    private(set) var validationState: GLTFValidationState?
    /// Resolved once when `document` or `validationState` changes — not on every window body pass.
    private(set) var validation = ValidationResult(status: .pending)
    /// On-device (and count-only) digests for the sidebar card and inspector issues.
    let validationDigests = ValidationDigestStore()
    private(set) var loadGeneration = 0
    private(set) var loadingURL: URL?
    let view: ViewState
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    @ObservationIgnored private var summaryTask: Task<Void, Never>?

    /// Tests replace this so scheduling can be asserted without running JavaScriptCore.
    @ObservationIgnored
    var validateFile: @Sendable (URL) async throws -> GLTFValidationReport = {
        try await GLTFValidator.validate(fileAt: $0)
    }

    init(documentURL: URL?, settings: AppSettings? = nil) {
        self.documentURL = documentURL
        phase = documentURL == nil ? .empty : .loading
        view = ViewState(settings: settings ?? .shared)
        view.document = document
        view.canvas.onPick = { [weak self] index in self?.view.pick(index) }
        view.canvas.onTogglePick = { [weak self] index in self?.view.toggleSelection(ofNode: index) }
        view.canvas.onOrbitStart = { [weak self] in self?.view.canvasDidOrbit() }
    }

    /// The file currently loading or open; chrome prefers the in-flight URL.
    var openURL: URL? { loadingURL ?? documentURL }

    var fileName: String { openURL?.lastPathComponent ?? "Model" }

    var exportName: String {
        openURL?.deletingPathExtension().lastPathComponent ?? "export"
    }

    /// Resets the window for `url`; the caller then loads the panels with `openSummary`.
    /// Validation starts from `noteCanvasReady` after first paint, not here.
    func beginOpen(_ url: URL) -> OpenStart {
        if DocumentOpening.isGLTFFile(url),
           loadingURL == url,
           phase == .loading || phase == .ready,
           loadGeneration > 0 {
            return .unchanged
        }

        invalidateOpen()
        guard DocumentOpening.isGLTFFile(url) else {
            AppLog.error(AppLog.app, "open rejected \(url.lastPathComponent)")
            phase = .failed("Not a .glb / .gltf file")
            documentURL = url
            loadingURL = url
            return .rejected
        }

        phase = .loading
        documentURL = url
        loadingURL = url
        AppLog.info(AppLog.app, "open start \(url.lastPathComponent) bytes=\(fileSize(url)) uptimeMs=\(AppLog.uptimeMs())")
        return .started(generation: loadGeneration)
    }

    /// Starts and retains the panel load so closing the window can cancel it.
    func startSummaryLoad(
        _ url: URL,
        generation: Int,
        load: @escaping (URL) async throws -> GLTFDocument = GLTFDocument.load
    ) {
        summaryTask?.cancel()
        summaryTask = Task { [weak self] in
            await self?.openSummary(url, generation: generation, load: load)
        }
    }

    /// Invalidates all work for the current document before a new open or a close.
    func close() {
        invalidateOpen()
        loadingURL = nil
        documentURL = nil
        phase = .empty
    }

    /// The panels, from the file's JSON alone. `load` is injectable for tests.
    func openSummary(
        _ url: URL,
        generation: Int,
        load: (URL) async throws -> GLTFDocument = GLTFDocument.load
    ) async {
        do {
            let document = try await load(url)
            guard generation == loadGeneration else { return }
            applyDocument(document)
            view.sceneIndex = document.defaultSceneIndex
            view.viewModes = document.viewModes
            phase = .ready
            let size = document.bounds.map { "\($0.size.x)x\($0.size.y)x\($0.size.z)" } ?? "empty"
            AppLog.info(
                AppLog.app,
                "open ready \(url.lastPathComponent) nodes=\(document.nodes.count) materials=\(document.materials.count) triangles=\(document.nodes.reduce(0) { $0 + $1.triangleCount }) bounds=\(size) uptimeMs=\(AppLog.uptimeMs())"
            )
        } catch {
            guard generation == loadGeneration else { return }
            AppLog.error(AppLog.app, "open failed \(url.lastPathComponent)")
            resetDocument()
            phase = .failed("The model could not be opened. Check that it is a valid glTF or GLB file.")
        }
    }

    /// Khronos validation is CPU-heavy (a JSContext and the whole file as base64), so it starts
    /// once the canvas settles — ready after first paint, or failed when Metal cannot draw —
    /// and does not compete with the first frame.
    func noteCanvasReady() {
        guard let url = loadingURL, validationState == nil, validationTask == nil else { return }
        let generation = loadGeneration
        let validateFile = validateFile
        validationTask = Task { [weak self] in
            let state: GLTFValidationState
            do {
                let work = Task.detached(priority: .utility) {
                    try await validateFile(url)
                }
                let report = try await withTaskCancellationHandler(operation: {
                    try await work.value
                }, onCancel: {
                    work.cancel()
                })
                state = .success(report)
                AppLog.info(AppLog.app, "validation \(url.lastPathComponent) errors=\(report.errorCount) warnings=\(report.warningCount) validator=\(report.validatorVersion)")
            } catch is CancellationError {
                return
            } catch let error as GLTFValidator.Error where error.isSoftSkip {
                state = .skipped("Validation skipped for this file because it is too large.")
                AppLog.info(AppLog.app, "validation skipped \(url.lastPathComponent)")
            } catch {
                state = .failed("Validation is unavailable right now.")
                AppLog.error(AppLog.app, "validation failed \(url.lastPathComponent)")
            }
            guard !Task.isCancelled, let self, generation == self.loadGeneration else { return }
            self.applyValidationState(state)
        }
    }

    private func invalidateOpen() {
        loadGeneration += 1
        summaryTask?.cancel()
        summaryTask = nil
        validationTask?.cancel()
        validationTask = nil
        validationDigests.cancelAll()
        resetDocument()
        applyValidationState(nil)
        view.reset()
    }

    private func resetDocument() {
        applyDocument(GLTFDocument())
    }

    /// Keeps `validation` in step with the panels' document; subjects resolve against this JSON.
    private func applyDocument(_ document: GLTFDocument) {
        self.document = document
        view.document = document
        validation = ValidationResult(validationState, document: document)
    }

    /// Keeps `validation` in step with the Khronos run; avoids re-resolving on every body pass.
    private func applyValidationState(_ state: GLTFValidationState?) {
        validationState = state
        validation = ValidationResult(state, document: document)
        // File-scope digest: faults only; infos/hints use the inspector selection request.
        let faults = validation.issues.filter { $0.severity == .error || $0.severity == .warning }
        if !faults.isEmpty {
            validationDigests.request(faults, scope: .file)
        }
    }

    deinit {
        summaryTask?.cancel()
        validationTask?.cancel()
    }
}

private func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
}
