import AppKit
import SwiftUI

/// Trailing Open-in control on the traffic-light line: over the canvas while the inspector is
/// closed, over the inspector while it is open, so it never moves vertically and lines up with the
/// toolbar clusters. Callers let it ignore the top safe area.
struct OpenInButton: View {
    let documentURL: URL?

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Spacer(minLength: 0)
            DSGlassMenuButton("Open in", systemImage: "square.and.arrow.up") {
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
                        NSWorkspace.shared.open([documentURL], withApplicationAt: blenderURL, configuration: NSWorkspace.OpenConfiguration())
                    } label: {
                        appLabel("Open in Blender", appURL: blenderURL, fallbackSymbol: "cube")
                    }
                    .disabled(documentURL == nil)
                }
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
