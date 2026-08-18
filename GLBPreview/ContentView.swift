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
        .onAppear {
            GLBLog.event(
                GLBLog.host,
                "ContentView appear file=\(openedFileName ?? "nil") dark=\(colorScheme == .dark)"
            )
            applyWindowTitle()
            GLBWindowLog.dumpWindows("contentview-appear")
        }
        .onChange(of: openedFileName) { _, name in
            GLBLog.event(GLBLog.host, "openedFileName=\(name ?? "nil")")
            applyWindowTitle()
        }
        .onChange(of: colorScheme) { _, scheme in
            GLBLog.event(GLBLog.window, "colorScheme=\(scheme)")
        }
        .onOpenURL(perform: openIfGLB)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    private func applyWindowTitle() {
        let title = openedFileName ?? "GLB Preview"
        let windows = NSApp.windows
        GLBLog.event(GLBLog.window, "applyWindowTitle \(title.debugDescription) windows=\(windows.count)")
        for window in windows where window.isVisible {
            window.title = title
            GLBLog.event(GLBLog.window, "titled \(GLBWindowLog.describe(index: nil, window: window))")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("GLB Quick Look")
                .font(.title)
            Text("Quick Look preview and thumbnails for .glb and .gltf files are installed.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
        .onAppear { GLBLog.event(GLBLog.host, "empty state appear") }
    }

    private func openIfGLB(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        GLBLog.event(GLBLog.host, "openIfGLB \(GLBLog.describeURL(url))")
        guard ext == "glb" || ext == "gltf" else {
            GLBLog.event(GLBLog.host, "ignored non-gltf URL ext=\(ext)")
            return
        }
        openedFileName = url.lastPathComponent
        previewState = .loading
        interaction = GLBPreviewInteraction()
        Task {
            let state = await GLBPreviewView.State.loaded(from: url)
            GLBLog.event(GLBLog.host, "host load finished file=\(url.lastPathComponent) failed=\(isFailed(state))")
            previewState = state
            GLBWindowLog.dumpWindows("after-host-load")
        }
    }

    private func isFailed(_ state: GLBPreviewView.State) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        GLBLog.event(GLBLog.host, "drop providers=\(providers.count)")
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            GLBLog.event(GLBLog.host, "drop ignored: no file URL")
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            if let error {
                GLBLog.error(GLBLog.host, "drop URL load failed \(error)")
            }
            guard let url else { return }
            Task { @MainActor in
                GLBLog.event(GLBLog.host, "drop opened \(url.path)")
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
        GLBLog.event(GLBLog.window, "HostPreviewContainer.makeNSView dark=\(isDark)")
        let view = GLBPreviewHostingView(
            rootView: GLBPreviewView(state: state, interaction: interaction, isDark: isDark)
        )
        view.interaction = interaction
        return view
    }

    func updateNSView(_ nsView: GLBPreviewHostingView, context: Context) {
        nsView.interaction = interaction
        nsView.rootView = GLBPreviewView(state: state, interaction: interaction, isDark: isDark)
        if nsView.window != nil {
            GLBWindowLog.layoutIfChanged(nsView, reason: "host-update")
        }
    }
}
