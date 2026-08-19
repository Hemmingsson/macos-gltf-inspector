import SwiftUI

struct HostViewerView: View {
    var state: GLBPreviewView.State
    var session: ViewerSession?
    var interaction: GLBPreviewInteraction
    var isDark: Bool

    var body: some View {
        NavigationSplitView {
            HostOutlinerView(model: loadedModel, session: session)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            HostPreviewContainer(state: state, interaction: interaction, isDark: isDark)
        } detail: {
            HostInspectorView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        }
        .modifier(HostSessionEnvironment(session: session))
    }

    private var loadedModel: GLBEntityLoader.LoadedModel? {
        if case .ready(let model) = state { return model }
        return nil
    }
}

private struct HostSessionEnvironment: ViewModifier {
    var session: ViewerSession?

    func body(content: Content) -> some View {
        if let session {
            content.environment(session)
        } else {
            content
        }
    }
}

struct HostPreviewContainer: NSViewRepresentable {
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

/// Liquid glass on macOS 26 (same availability as host toolbar glass); plain column on 15.
struct HostColumnChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .padding(8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
        }
    }
}
