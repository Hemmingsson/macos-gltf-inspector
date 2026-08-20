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
    @State private var blenderLaunchError: String?

    private static let sidebarMinWidth: CGFloat = 200
    private static let sidebarIdealWidth: CGFloat = 252
    private static let sidebarMaxWidth: CGFloat = 480

    private static let finderMenuIcon: NSImage = {
        let url =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
            ?? URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        return BlenderLauncher.menuIcon(for: url)
    }()

    @ViewBuilder
    private func openInMenuRow(title: String, icon: NSImage) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            Text(title)
        }
    }

    var body: some View {
        documentRoot
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
                GLBDocumentOpening.closeWelcomeWindows()
                if let documentURL {
                    loadDocument(documentURL)
                }
            }
            .background(DocumentWindowTabbing())
            .onChange(of: documentURL) { _, url in
                if let url {
                    loadDocument(url)
                }
            }
            .onChange(of: sidebar?.activeSceneIndex) { _, index in
                reloadScene(index)
            }
            .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
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
    }

    @ViewBuilder
    private var sidebarColumn: some View {
        if let sidebar {
            HostOutlinerView(model: loadedModel, sidebar: sidebar)
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
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(documentURL?.lastPathComponent ?? "GLB Preview")
        .toolbar {
            if let documentURL {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([documentURL])
                        } label: {
                            openInMenuRow(title: "Finder", icon: Self.finderMenuIcon)
                        }
                        if BlenderLauncher.isInstalled, let blenderIcon = BlenderLauncher.applicationIcon {
                            Button {
                                do {
                                    try BlenderLauncher.openInNewBlenderInstance(documentURL)
                                } catch {
                                    AppLog.error(AppLog.host, "blender open failed \(error.localizedDescription)")
                                    blenderLaunchError = error.localizedDescription
                                }
                            } label: {
                                openInMenuRow(title: "Blender", icon: blenderIcon)
                            }
                        }
                    } label: {
                        Label("Open in…", systemImage: "arrow.up.forward.app")
                    }
                    .labelStyle(.iconOnly)
                    .help("Open in…")
                }
            }
        }
    }

    private var loadedModel: EntityLoader.LoadedModel? {
        if case .ready(let model) = previewState { return model }
        return nil
    }


    private func loadDocument(_ url: URL) {
        guard GLBDocumentOpening.isGLBFile(url) else { return }
        previewState = .loading
        sidebar = nil
        interaction = PreviewInteraction()
        loadGeneration += 1
        let generation = loadGeneration
        AppLog.info(AppLog.host, "open start \(url.lastPathComponent) bytes=\(fileSize(url))")
        Task {
            let state = await PreviewView.State.loaded(from: url)
            guard generation == loadGeneration else { return }
            previewState = state
            if case .ready(let model) = state {
                let bounds = model.entity.visualBounds(relativeTo: nil)
                let extent = bounds.max - bounds.min
                AppLog.info(
                    AppLog.host,
                    "open ready \(url.lastPathComponent) meshes=\(model.document.meshes.count) nodes=\(model.document.nodes.count) lights=\(model.document.lights.count) cameras=\(model.document.cameras.count) extent=\(extent.x)x\(extent.y)x\(extent.z) emptyBounds=\(bounds.isEmpty)"
                )
                sidebar = HostSidebarModel(document: model.document)
            } else {
                sidebar = nil
                AppLog.error(AppLog.host, "open failed \(url.lastPathComponent)")
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
                if case .ready(let model) = previewState {
                    sidebar.showAll()
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
                }
            } catch {
                AppLog.error(AppLog.host, "scene switch failed \(error)")
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        GLBDocumentOpening.handleDrop(providers) { url in
            try await openDocument(at: url)
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
