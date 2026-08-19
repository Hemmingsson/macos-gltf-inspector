import SwiftUI

struct HostViewerView: View {
    var state: GLBPreviewView.State
    var session: ViewerSession?
    var interaction: GLBPreviewInteraction
    var isDark: Bool
    @State private var hostScene = GLBHostSceneController()

    var body: some View {
        NavigationSplitView {
            HostOutlinerView(model: loadedModel, session: session)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            HostPreviewContainer(
                state: state,
                interaction: interaction,
                isDark: isDark,
                hostBridge: hostScene.bridge,
                lookRevision: hostScene.bridge.lookRevision
            )
        } detail: {
            HostInspectorView(session: session)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        }
        .modifier(HostSessionEnvironment(session: session))
        .toolbar {
            Button("Frame") {
                hostScene.frameSelection()
            }
            .keyboardShortcut("f", modifiers: [])
            .help("Frame selected (F). Nothing selected fits the active scene.")
            .disabled(session == nil)
        }
        .onAppear { hostScene.bind(session: session) }
        .onChange(of: sessionIdentity) { _, _ in
            hostScene.bind(session: session)
        }
        .onChange(of: lookFingerprint) { _, _ in
            hostScene.sessionDidChange()
        }
    }

    private var sessionIdentity: ObjectIdentifier? {
        session.map { ObjectIdentifier($0) }
    }

    private var lookFingerprint: Int {
        guard let session else { return 0 }
        var hasher = Hasher()
        hasher.combine(session.imageBased)
        hasher.combine(session.punctualLights)
        hasher.combine(session.iblIntensity)
        hasher.combine(session.environment)
        hasher.combine(session.environmentRotation)
        hasher.combine(session.showEnvironmentMap)
        hasher.combine(session.blurEnvironment)
        hasher.combine(session.selectedUserHDR)
        hasher.combine(session.userHDRs.count)
        hasher.combine(session.toneMap)
        hasher.combine(session.exposure)
        hasher.combine(String(describing: session.backgroundColor))
        hasher.combine(session.hide)
        hasher.combine(session.soloRoot)
        hasher.combine(session.frameNonce)
        return hasher.finalize()
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
    var hostBridge: GLBPreviewHostSceneBridge?
    var lookRevision: Int

    func makeNSView(context: Context) -> GLBPreviewHostingView {
        let view = GLBPreviewHostingView(
            rootView: GLBPreviewView(
                state: state,
                interaction: interaction,
                isDark: isDark,
                hostBridge: hostBridge
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
            hostBridge: hostBridge
        )
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
