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
            if let openedFileName {
                HostViewerView(
                    state: previewState,
                    sidebar: sidebar,
                    fileName: openedFileName,
                    interaction: interaction,
                    isDark: colorScheme == .dark
                )
                .id(openedURL)
            } else {
                emptyState
            }
        }
        .frame(minWidth: QAShotLaunch.isActive ? 960 : 400, minHeight: QAShotLaunch.isActive ? 640 : 300)
        .navigationTitle("GLB Preview")
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

    private func openIfGLB(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "glb" || ext == "gltf" else { return }
        openedURL = url
        previewState = .loading
        sidebar = nil
        interaction = GLBPreviewInteraction()
        GLBLoadFailure.reset()
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
                        GLBEntityLoader.LoadedModel(entity: entity, stats: model.stats, document: model.document)
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
