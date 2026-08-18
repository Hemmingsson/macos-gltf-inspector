import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var openedFileName: String?
    @State private var previewState: GLBPreviewView.State = .loading
    @State private var interaction = GLBPreviewInteraction()

    var body: some View {
        Group {
            if openedFileName != nil {
                HostPreviewContainer(
                    state: previewState,
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
            Text("GLB Quick Look")
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
        interaction = GLBPreviewInteraction()
        Task {
            previewState = await GLBPreviewView.State.loaded(from: url)
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

private struct HostPreviewContainer: NSViewRepresentable {
    var state: GLBPreviewView.State
    var interaction: GLBPreviewInteraction
    var isDark: Bool

    func makeNSView(context: Context) -> GLBPreviewHostingView {
        let view = GLBPreviewHostingView(
            rootView: GLBPreviewView(state: state, interaction: interaction, isDark: isDark)
        )
        view.interaction = interaction
        return view
    }

    func updateNSView(_ nsView: GLBPreviewHostingView, context: Context) {
        nsView.interaction = interaction
        nsView.rootView = GLBPreviewView(state: state, interaction: interaction, isDark: isDark)
    }
}
