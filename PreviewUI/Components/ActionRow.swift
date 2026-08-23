import SwiftUI

/// Action cluster on the unified chrome baseline (`chromeBandAligned()`).
///
/// Document actions (Open in…) trail. When floating over the canvas (inspector closed), the same
/// cluster sits at the trailing edge.
public struct ActionRow: View {
    public let openInMenu: AnyView

    public var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            openInMenu
        }
        .frame(height: ChromeMetrics.buttonSize, alignment: .trailing)
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .chromeBandAligned()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector actions")
    }
}

// MARK: - Previews

private struct PreviewOpenInMenu: View {
    var body: some View {
        Menu {
            Button("Finder") {}
            Button("Blender") {}
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: ChromeMetrics.glyphSize))
                .frame(width: ChromeMetrics.buttonSize, height: ChromeMetrics.buttonSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}

#Preview("with menu") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        ActionRow(openInMenu: AnyView(PreviewOpenInMenu()))
    }
}
