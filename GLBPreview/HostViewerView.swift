import SwiftUI

struct HostViewerView: View {
    var state: GLBPreviewView.State
    var sidebar: HostSidebarModel?
    var fileName: String?
    var interaction: GLBPreviewInteraction
    var isDark: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            HostPreviewContainer(
                state: state,
                interaction: interaction,
                isDark: isDark,
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
        .navigationTitle(windowTitle)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear {
            showTrafficLights()
            applyDefaultCamera()
        }
    }

    private var windowTitle: String {
        fileName ?? "GLB Preview"
    }

    private var loadedModel: GLBEntityLoader.LoadedModel? {
        if case .ready(let model) = state { return model }
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
}

struct HostPreviewContainer: NSViewRepresentable {
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

/// Liquid glass on macOS 26 (same availability as host toolbar glass); plain column on 15.
struct HostColumnChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .padding(EdgeInsets(top: 36, leading: 10, bottom: 10, trailing: 10))
                .frame(maxHeight: .infinity, alignment: .top)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
                .padding(EdgeInsets(top: 36, leading: 10, bottom: 10, trailing: 10))
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
