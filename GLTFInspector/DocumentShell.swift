import AppKit
import GLTFCore
import PreviewUI
import SwiftUI

/// Document window chrome: PreviewUI `ShellRootView` + engine adapters around one renderer's
/// canvas. Renderer-neutral — the window roots in `RealityKit/` and `WebKit/` own loading and
/// the canvas, and pass in what their renderer offers (`features`, playback, morph sliders).
///
/// Pills / selection / export / playback / scene+variant write through the engine adapters into
/// the window's `DocumentWindowModel`. Settings-backed keys use `EngineSettingsStore` lazy overlay
/// (untouched keys track defaults live).
struct DocumentShell<Playback: ClipPlaybackController, Canvas: View>: View {
    let window: DocumentWindowModel
    /// Canvas region state; the panels follow `window.phase`.
    let canvasState: ShellDocumentState
    let features: Set<RendererFeature>
    let playback: Playback
    var morphTargets: [MorphTargetControl] = []
    var onSetMorphWeight: (String, Double) -> Void = { _, _ in }
    @ViewBuilder let canvas: () -> Canvas

    @Environment(\.openDocument) private var openDocument
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let viewport = window.engineViewport
        shellRoot
            .focusedSceneValue(\.previewCommands, viewport.commands)
            // A canvas can take View-menu commands before (or without) the panels' document.
            .focusedSceneValue(
                \.engineViewport,
                !window.hasLoadedDocument && viewport.commands == nil ? nil : viewport
            )
            .onAppear {
                dismissWindow(id: WelcomeWindow.id)
            }
            .onChange(of: window.settings.defaultsStore.revision) { _, _ in
                // Live-track canvas for keys that still have no session override.
                viewport.syncFromSettings()
            }
            .onDrop(of: [.fileURL], isTargeted: nil) {
                DocumentOpening.handleDrop($0, openDocument: openDocument)
            }
    }

    @ViewBuilder
    private var shellRoot: some View {
        let availability = RendererAvailability(
            model: window.sceneModel,
            viewModes: window.previewSession.viewModes,
            features: features
        )
        ShellRootView(
            model: window.sceneModel,
            availability: availability,
            documentState: window.phase,
            canvasState: canvasState,
            selection: window.selection,
            viewport: window.engineViewport,
            settings: window.settings,
            playback: playback,
            panels: window.panels,
            morphTargets: morphTargets,
            onSetMorphWeight: onSetMorphWeight,
            openInMenu: AnyView(OpenInMenuItems(documentURL: window.loadingURL ?? window.documentURL))
        ) {
            // A new document (or a RealityKit scene / variant reload) remounts the canvas only;
            // the split view, settings and viewport keep their identity.
            canvas()
                .id(window.loadGeneration)
        }
    }
}

/// Finder / Blender items only — `ActionRow` wraps them in `DSGlassMenuButton`.
private struct OpenInMenuItems: View {
    let documentURL: URL?

    private var blenderAppURL: URL? {
        let workspace = NSWorkspace.shared
        if let bundleIDURL = workspace.urlForApplication(withBundleIdentifier: "org.blenderfoundation.blender") {
            return bundleIDURL
        }
        if let known = workspace
            .urlsForApplications(withBundleIdentifier: "org.blenderfoundation.blender")
            .first {
            return known
        }
        return nil
    }

    var body: some View {
        Button {
            guard let documentURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([documentURL])
        } label: {
            appMenuLabel(title: "Reveal in Finder", appURL: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder"), fallbackSymbol: "folder")
        }
        .disabled(documentURL == nil)

        if let blenderAppURL {
            Button {
                guard let documentURL else { return }
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([documentURL], withApplicationAt: blenderAppURL, configuration: config)
            } label: {
                appMenuLabel(title: "Open in Blender", appURL: blenderAppURL, fallbackSymbol: "cube")
            }
            .disabled(documentURL == nil)
        }
    }

    @ViewBuilder
    private func appMenuLabel(title: String, appURL: URL?, fallbackSymbol: String) -> some View {
        if let appURL,
           let icon = NSWorkspace.shared.icon(forFile: appURL.path).copy() as? NSImage {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text(title)
            }
        } else {
            Label(title, systemImage: fallbackSymbol)
        }
    }
}
