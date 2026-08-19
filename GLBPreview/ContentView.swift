import AppKit
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var openedURL: URL?
    @State private var previewState: GLBPreviewView.State = .loading
    @State private var interaction = GLBPreviewInteraction()
    @State private var sidebar: HostSidebarModel?

    private var openedFileName: String? { openedURL?.lastPathComponent }

    var body: some View {
        Group {
            if openedURL != nil {
                hostViewer
                    .id(openedURL)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle(openedFileName ?? "GLB Preview")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear { showTrafficLights() }
        .onChange(of: sidebar?.activeSceneIndex) { _, index in
            reloadScene(index)
        }
        .onOpenURL(perform: openIfGLB)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
            Text("GLB Preview")
                .font(.title)
            Text("Quick Look preview and thumbnails for .glb and .gltf files are installed.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
    }

    private var hostViewer: some View {
        ZStack(alignment: .topLeading) {
            HostPreviewContainer(
                state: previewState,
                interaction: interaction,
                isDark: colorScheme == .dark,
                sidebar: sidebar
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            HostOutlinerView(model: loadedModel, sidebar: sidebar)
                .frame(width: 252)
                .frame(maxHeight: .infinity)
                .padding(.leading, 10)
                .padding(.trailing, 0)
                .padding(.bottom, 10)
                .padding(.top, 8)
        }
        .onAppear { applyDefaultCamera() }
    }

    private var loadedModel: GLBEntityLoader.LoadedModel? {
        if case .ready(let model) = previewState { return model }
        return nil
    }

    private func showTrafficLights() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
    }

    private func applyDefaultCamera() {
        guard let sidebar, !sidebar.document.cameras.isEmpty else { return }
        let raw = UserDefaults.standard.string(forKey: SettingsKeys.defaultCamera)
            ?? PreviewDefaultCamera.fit.rawValue
        if raw == PreviewDefaultCamera.firstFile.rawValue {
            sidebar.selectedCameraIndex = 0
            sidebar.overlayRevision += 1
        }
    }

    private func openIfGLB(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "glb" || ext == "gltf" else { return }
        openedURL = url
        previewState = .loading
        sidebar = nil
        interaction = GLBPreviewInteraction()
        GLBLog.info(GLBLog.host, "open start \(url.lastPathComponent) bytes=\(fileSize(url))")
        Task {
            let state = await GLBPreviewView.State.loaded(from: url)
            previewState = state
            if case .ready(let model) = state {
                let bounds = model.entity.visualBounds(relativeTo: nil)
                let extent = bounds.max - bounds.min
                GLBLog.info(
                    GLBLog.host,
                    "open ready \(url.lastPathComponent) meshes=\(model.document.meshes.count) nodes=\(model.document.nodes.count) lights=\(model.document.lights.count) cameras=\(model.document.cameras.count) extent=\(extent.x)x\(extent.y)x\(extent.z) emptyBounds=\(bounds.isEmpty)"
                )
                sidebar = HostSidebarModel(document: model.document)
            } else {
                sidebar = nil
                GLBLog.error(GLBLog.host, "open failed \(url.lastPathComponent)")
            }
        }
    }

    private func reloadScene(_ index: Int?) {
        guard let url = openedURL, let index, let sidebar, sidebar.document.scenes.count > 1 else { return }
        Task {
            do {
                let entity = try await GLBEntityLoader.convertScene(index: index, from: url)
                if case .ready(let model) = previewState {
                    sidebar.showAll()
                    previewState = .ready(
                        GLBEntityLoader.LoadedModel(
                            entity: entity,
                            stats: model.stats,
                            document: model.document
                        )
                    )
                    sidebar.overlayRevision += 1
                }
            } catch {
                GLBLog.error(GLBLog.host, "scene switch failed \(error)")
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            if let error {
                GLBLog.error(GLBLog.host, "drop URL load failed \(error)")
            }
            guard let url else { return }
            Task { @MainActor in
                openIfGLB(url)
            }
        }
        return true
    }

}

private func fileSize(_ url: URL) -> Int64 {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
}

private struct HostPreviewContainer: NSViewRepresentable {
    var state: GLBPreviewView.State
    var interaction: GLBPreviewInteraction
    var isDark: Bool
    var sidebar: HostSidebarModel?

    func makeNSView(context: Context) -> GLBPreviewHostingView {
        let view = GLBPreviewHostingView(
            rootView: GLBPreviewView(
                state: state,
                interaction: interaction,
                isDark: isDark,
                sidebar: sidebar
            )
        )
        view.interaction = interaction
        return view
    }

    func updateNSView(_ nsView: GLBPreviewHostingView, context: Context) {
        nsView.interaction = interaction
        nsView.rootView = GLBPreviewView(
            state: state,
            interaction: interaction,
            isDark: isDark,
            sidebar: sidebar
        )
    }
}
