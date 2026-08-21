import AppKit
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
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
    /// P34 per-window session — seeded from Settings; never written back.
    @State private var sessionAutoRotate =
        UserDefaults.standard.object(forKey: SettingsKeys.autoRotate) as? Bool ?? true
    @State private var sessionShowFloor =
        UserDefaults.standard.object(forKey: SettingsKeys.showFloor) as? Bool ?? true
    @State private var sessionBackdropIndex = PreviewBackground.storedIndex
    /// P1 — Center on by default; per-window only, never UserDefaults.
    @State private var sessionCenterModel = true
    /// P2 — Orthographic preview projection; session-only, never UserDefaults.
    @State private var sessionOrthographic = false
    /// P5 — session lighting; never UserDefaults.
    @State private var sessionExposureEV: Float = 0
    @State private var sessionDimStudioForFileLights = false
    @State private var sessionEnvironmentYaw: Float = 0
    /// P6 — force double-sided materials; session-only, never UserDefaults.
    @State private var sessionDoubleSided = false
    /// P16 — skeleton overlay; session-only, never UserDefaults.
    @State private var sessionShowSkeleton = false
    /// P8 — perspective FOV; session-only, never UserDefaults.
    @State private var sessionFieldOfViewDegrees = PreviewCamera.defaultFieldOfViewDegrees
    /// P17 — filled async after open; never blocks first paint.
    @State private var validation: GLTFValidationState?
    @State private var validationGeneration = 0
    @State private var validationTask: Task<Void, Never>?

    private static let sidebarMinWidth: CGFloat = 200
    private static let sidebarIdealWidth: CGFloat = 252
    private static let sidebarMaxWidth: CGFloat = 480

    var body: some View {
        documentRoot
            .focusedSceneValue(\.previewCommands, focusedPreviewCommands)
            .focusedSceneValue(\.previewSession, loadedModel == nil ? nil : previewSession.focusedMenu)
            .frame(minWidth: 560, minHeight: 360)
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
                }
            }
            .onChange(of: documentURL) { _, url in
                if let url {
                    loadDocument(url)
                }
            }
            .onChange(of: sidebar?.activeSceneIndex) { previous, index in
                // Initial sidebar assign is nil → defaultSceneIndex; that must not re-convert.
                guard previous != nil else { return }
                reloadScene(index)
            }
            .onChange(of: sidebar?.selectedMaterialVariantIndex) { previous, _ in
                // Skip the initial sidebar assign (nil → nil) and only reload after user picks.
                guard previous != nil || sidebar?.selectedMaterialVariantIndex != nil else { return }
                reloadMaterialVariant()
            }
            .onDrop(of: [.fileURL], isTargeted: nil) {
                GLBDocumentOpening.handleDrop($0, openDocument: openDocument)
            }
    }

    @ViewBuilder
    private var documentRoot: some View {
        if documentURL != nil {
            hostViewer
                .id(documentURL)
        } else {
            missingDocumentState
        }
    }

    private var missingDocumentState: some View {
        VStack(spacing: 12) {
            Text("Couldn’t open this file")
                .font(.title2)
            Text("The document URL is missing.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
    }

    private var hostViewer: some View {
        NavigationSplitView {
            sidebarColumn
                .navigationSplitViewColumnWidth(
                    min: Self.sidebarMinWidth,
                    ideal: Self.sidebarIdealWidth,
                    max: Self.sidebarMaxWidth
                )
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(documentURL?.lastPathComponent ?? "GLB Preview")
    }

    @ViewBuilder
    private var sidebarColumn: some View {
        if let sidebar {
            HostOutlinerView(
                model: loadedModel,
                documentURL: documentURL,
                validation: validation,
                sidebar: sidebar,
                showSkeleton: $sessionShowSkeleton,
                fieldOfViewDegrees: $sessionFieldOfViewDegrees,
                orthographic: sessionOrthographic,
                onBlenderError: { blenderLaunchError = $0 }
            )
        } else if case .failed(let message) = previewState {
            VStack(spacing: 6) {
                Text("Couldn’t load model")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let validation {
                    validationSidebarBadge(validation)
                        .padding(.top, 8)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func validationSidebarBadge(_ state: GLTFValidationState) -> some View {
        let style = validationBadgeStyle(state)
        HStack(spacing: 6) {
            Image(systemName: style.symbol)
                .foregroundStyle(style.color)
            Text(state.badgeTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(style.color)
                .lineLimit(3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(style.color.opacity(0.12))
        )
    }

    private func validationBadgeStyle(_ state: GLTFValidationState) -> (symbol: String, color: Color) {
        switch state {
        case .success(let report):
            report.isClean
                ? ("checkmark.seal.fill", Color.green)
                : ("exclamationmark.triangle.fill", Color.orange)
        case .failed:
            ("exclamationmark.circle.fill", Color.secondary)
        case .skipped:
            ("slash.circle.fill", Color.secondary)
        }
    }

    private var detailColumn: some View {
        HostPreviewContainer(
            state: previewState,
            interaction: interaction,
            isDark: colorScheme == .dark,
            sidebar: sidebar,
            // Read revision here so `@Observable` selection/hide invalidates this representable
            // (passing the model reference alone does not).
            overlayRevision: sidebar?.overlayRevision ?? 0,
            session: previewSession
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadedModel: EntityLoader.LoadedModel? {
        if case .ready(let model) = previewState { return model }
        return nil
    }

    /// Single P34 bag for RealityView (seed from Settings; never write back).
    /// View menu uses `focusedMenu` (no backdrop).
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

    /// Fit or P3 preset — session-only camera (never UserDefaults).
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

    /// P4 — restore opening front-3/4 framing. Session Center is turned back on when
    /// off (remount rebuilds the turntable); otherwise PreviewScene clears pan/yaw + fit.
    private func resetPreviewView() {
        sidebar?.selectedCameraIndex = nil
        if !sessionCenterModel {
            // Remount via `.id(centerModel)` — make zeros yaw and layout-fits.
            sessionCenterModel = true
            sidebar?.overlayRevision += 1
            return
        }
        Task { @MainActor in
            interaction.requestOpeningFitReset()
            sidebar?.overlayRevision += 1
        }
    }

    /// P19 — offscreen re-render at the live camera pose + NSSavePanel.
    /// Clones the turntable pivot; does **not** grab the RealityView framebuffer.
    private func screenshotCurrentCameraPose() {
        Task { @MainActor in
            guard let camera = interaction.camera,
                  let pivot = interaction.orbitFocus,
                  let pose = StillCameraPose.capturing(from: camera)
            else {
                AppLog.error(AppLog.host, "screenshot skipped — no live camera pose")
                return
            }
            let root = pivot.clone(recursive: true)
            let intensity = PreviewEmissive.sessionIBLExponent(
                dimStudioForFileLights: sessionDimStudioForFileLights,
                exposureEV: sessionExposureEV
            )
            let background = PreviewBackground.at(sessionBackdropIndex).stillBackgroundCGColor
            let suggested = (loadingURL ?? documentURL)?
                .deletingPathExtension()
                .lastPathComponent ?? "screenshot"
            let aspect: Float = {
                if let view = NSApp.keyWindow?.contentView, view.bounds.height > 1 {
                    return Float(view.bounds.width / view.bounds.height)
                }
                return 16 / 9
            }()
            do {
                let url = try await StillRenderer.exportPNGViaSavePanel(
                    root: root,
                    cameraPose: pose,
                    background: background,
                    intensityExponent: intensity,
                    environmentYaw: sessionEnvironmentYaw,
                    suggestedName: suggested,
                    aspect: aspect
                )
                if let url {
                    AppLog.info(
                        AppLog.host,
                        "screenshot wrote \(url.path) (offscreen re-render at live camera pose)"
                    )
                }
            } catch {
                AppLog.error(AppLog.host, "screenshot failed: \(error.localizedDescription)")
            }
        }
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
        // Tab/chrome remounts can re-fire onAppear — don't restart an in-flight or finished open.
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
        // P17: validate in parallel with convert — do not wait on open / first paint.
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
                // P5: seed file-vs-studio from the auto-dim the loader already computed.
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
                // Keep the current mesh and sidebar so the user can pick another scene.
            }
        }
    }

    /// P40 spike — re-convert with `KHR_materials_variants` mapping stamped onto primitives.
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

}

private func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
}

private struct HostPreviewContainer: NSViewRepresentable {
    var state: PreviewView.State
    var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: HostSidebarModel?
    /// Mirrors `HostSidebarModel.overlayRevision` so selection/hide triggers `updateNSView`.
    var overlayRevision: Int
    var session: PreviewSessionBindings

    func makeNSView(context: Context) -> PreviewHostingView {
        let view = PreviewHostingView(
            rootView: PreviewView(
                state: state,
                interaction: interaction,
                isDark: isDark,
                sidebar: sidebar,
                overlayRevision: overlayRevision,
                session: session
            )
        )
        view.interaction = interaction
        return view
    }

    func updateNSView(_ nsView: PreviewHostingView, context: Context) {
        nsView.interaction = interaction
        nsView.rootView = PreviewView(
            state: state,
            interaction: interaction,
            isDark: isDark,
            sidebar: sidebar,
            overlayRevision: overlayRevision,
            session: session
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PreviewHostingView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.bounds.width,
            height: proposal.height ?? nsView.bounds.height
        )
    }
}
