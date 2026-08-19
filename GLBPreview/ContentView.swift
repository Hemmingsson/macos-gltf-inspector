import AppKit
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var openedFileName: String?
    @State private var previewState: GLBPreviewView.State = .loading
    @State private var interaction = GLBPreviewInteraction()
    @State private var session: ViewerSession?

    var body: some View {
        Group {
            if openedFileName != nil {
                HostViewerView(
                    state: previewState,
                    session: session,
                    interaction: interaction,
                    isDark: colorScheme == .dark
                )
            } else {
                emptyState
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle(openedFileName ?? "GLB Preview")
        .onAppear(perform: applyWindowTitle)
        .onChange(of: openedFileName) { _, _ in applyWindowTitle() }
        .onOpenURL(perform: openIfGLB)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    private func applyWindowTitle() {
        let title = openedFileName ?? "GLB Preview"
        for window in NSApp.windows where window.isVisible {
            window.title = title
        }
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
        openedFileName = url.lastPathComponent
        previewState = .loading
        session = nil
        interaction = GLBPreviewInteraction()
        Task {
            let state = await GLBPreviewView.State.loaded(from: url)
            previewState = state
            if case .ready(let model) = state {
                session = ViewerSession(
                    document: model.document,
                    defaultExponent: hasFileLights(model) ? -2 : 0
                )
            } else {
                session = nil
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

private func hasFileLights(_ model: GLBEntityLoader.LoadedModel) -> Bool {
    if !model.document.lights.isEmpty { return true }
    return hasPunctualLight(model.entity)
}

private func hasPunctualLight(_ entity: Entity) -> Bool {
    if entity.components.has(PointLightComponent.self)
        || entity.components.has(SpotLightComponent.self)
        || entity.components.has(DirectionalLightComponent.self)
    {
        return true
    }
    return entity.children.contains { hasPunctualLight($0) }
}
