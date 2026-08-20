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

    private static let sidebarMinWidth: CGFloat = 200
    private static let sidebarIdealWidth: CGFloat = 252
    private static let sidebarMaxWidth: CGFloat = 480

    var body: some View {
        documentRoot
            .focusedSceneValue(\.previewCommands, focusedPreviewCommands)
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
            .onChange(of: sidebar?.activeSceneIndex) { _, index in
                reloadScene(index)
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
                sidebar: sidebar,
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
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailColumn: some View {
        HostPreviewContainer(
            state: previewState,
            interaction: interaction,
            isDark: colorScheme == .dark,
            sidebar: sidebar
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadedModel: EntityLoader.LoadedModel? {
        if case .ready(let model) = previewState { return model }
        return nil
    }

    private var focusedPreviewCommands: FocusedPreviewCommands? {
        guard loadedModel != nil else { return nil }
        return FocusedPreviewCommands(fit: fitPreviewCamera)
    }

    private func fitPreviewCamera() {
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
        PreviewCamera.restoreFitPerspective(on: camera)
        PreviewCamera.applyFit(
            to: camera,
            bounds: bounds,
            orbitFocus: interaction.orbitFocus
        )
        interaction.markFitted()
        sidebar?.overlayRevision += 1
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
        interaction = PreviewInteraction()
        loadingURL = url
        loadGeneration += 1
        let generation = loadGeneration
        AppLog.info(AppLog.host, "open start \(url.lastPathComponent) bytes=\(fileSize(url))")
        Task {
            let state = await PreviewView.State.loaded(from: url)
            guard generation == loadGeneration else { return }
            previewState = state
            if case .ready(let model) = state {
                let bounds = PreviewCamera.modelBounds(of: model.entity, relativeTo: model.entity)
                let extent = bounds.max - bounds.min
                AppLog.info(
                    AppLog.host,
                    "open ready \(url.lastPathComponent) nodes=\(model.document.nodes.count) cameras=\(model.document.cameras.count) triangles=\(model.stats.triangleCount) extent=\(extent.x)x\(extent.y)x\(extent.z) emptyBounds=\(bounds.isEmpty)"
                )
                sidebar = HostSidebarModel(document: model.document)
            } else if case .failed(let message) = state {
                sidebar = nil
                AppLog.error(AppLog.host, "open failed \(url.lastPathComponent): \(message)")
            }
        }
    }

    private func reloadScene(_ index: Int?) {
        guard let url = documentURL, let index, let sidebar, sidebar.document.scenes.count > 1 else { return }
        loadGeneration += 1
        let generation = loadGeneration
        Task {
            do {
                let entity = try await EntityLoader.convertScene(index: index, from: url)
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
                        )
                    )
                )
                sidebar.overlayRevision += 1
            } catch {
                guard generation == loadGeneration else { return }
                let message = error.localizedDescription
                AppLog.error(AppLog.host, "scene switch failed: \(message)")
                previewState = .failed(message)
                self.sidebar = nil
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

    func makeNSView(context: Context) -> PreviewHostingView {
        let view = PreviewHostingView(
            rootView: PreviewView(
                state: state,
                interaction: interaction,
                isDark: isDark,
                sidebar: sidebar
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
            sidebar: sidebar
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PreviewHostingView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.bounds.width,
            height: proposal.height ?? nsView.bounds.height
        )
    }
}
