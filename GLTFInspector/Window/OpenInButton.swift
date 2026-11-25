import AppKit
import GLTFCore
import SwiftUI

/// Trailing Open-in control on the traffic-light line: over the canvas while the inspector is
/// closed, over the inspector while it is open, so it never moves vertically and lines up with the
/// toolbar clusters. Callers let it ignore the top safe area.
struct OpenInButton: View {
    let documentURL: URL?
    /// The window whose canvas the turntable exports draw; nil hides them.
    var view: ViewState?
    var exportName = "export"

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Spacer(minLength: 0)
            DSGlassMenuButton("Open in", systemImage: DSGlyphs.openIn.symbol,
                              assetImage: DSGlyphs.openIn.assetImage) {
                Button {
                    guard let documentURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([documentURL])
                } label: {
                    appLabel("Reveal in Finder", appURL: Self.finderURL, fallbackSymbol: "folder")
                }
                .disabled(documentURL == nil)

                if let blenderURL = Self.blenderURL {
                    Button {
                        guard let documentURL else { return }
                        Self.openInBlender(documentURL, blenderURL: blenderURL)
                    } label: {
                        appLabel("Open in Blender", appURL: blenderURL, fallbackSymbol: "cube")
                    }
                    .disabled(documentURL == nil)
                }

                if let view {
                    Divider()
                    TurntableExportButtons(view: view, suggestedName: exportName)
                }

                Divider()
                CopyGLBButton(url: documentURL)
            }
            .dsGlassPlacement(.standalone)
        }
        .padding(.horizontal, DS.Spacing.l)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector actions")
        .dsChromeBandAligned()
    }

    private static var finderURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
    }

    private static var blenderURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.blenderfoundation.blender")
    }

    /// Blender cannot *open* a glTF: `File ▸ Open` takes `.blend` only and answers "File format is
    /// not supported", so handing it the document URL fails. Launch a new instance that imports the
    /// file into an empty scene — the result a person would get from `File ▸ Import ▸ glTF 2.0`,
    /// without Blender's startup cube, camera and light in the way. A new instance every time
    /// because a running Blender would otherwise just come forward and drop the arguments.
    static func openInBlender(_ documentURL: URL, blenderURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--python-expr", blenderImportScript]
        configuration.environment = [blenderPathVariable: documentURL.path]
        NSWorkspace.shared.openApplication(at: blenderURL, configuration: configuration) { _, error in
            if error != nil {
                AppLog.error(AppLog.app, "open in Blender failed")
            }
        }
    }

    /// The path travels in the environment, so no quoting or escaping in the expression can break
    /// on spaces, quotes or non-ASCII in a file name.
    static let blenderPathVariable = "GLTF_INSPECTOR_IMPORT_PATH"

    /// `use_preferences_save = False` first, so turning the splash off for this launch is not
    /// written back to the person's Blender preferences.
    static let blenderImportScript = """
        import bpy, os
        bpy.context.preferences.use_preferences_save = False
        bpy.context.preferences.view.show_splash = False
        bpy.ops.wm.read_homefile(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=os.environ["\(blenderPathVariable)"])
        """

    @ViewBuilder
    private func appLabel(_ title: String, appURL: URL?, fallbackSymbol: String) -> some View {
        if let appURL, let icon = NSWorkspace.shared.icon(forFile: appURL.path).copy() as? NSImage {
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
