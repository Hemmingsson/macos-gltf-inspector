import SwiftUI

/// Top of the right column: actions on the unified chrome baseline, identity on the row below.
///
/// Sketch / DESIGN.md: screenshot · Open in… share the window's top band with the
/// sidebar toggle and canvas pills; selection name sits under that cluster, not beside it.
struct NodeHeader: View {
    var name: String
    var kindTitle: String
    var kind: NodeKind
    var onScreenshot: () -> Void
    var onOpenIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActionRow(onScreenshot: onScreenshot, onOpenIn: onOpenIn)

            IdentityRow(name: name, kindTitle: kindTitle, kind: kind)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Action cluster on the unified chrome baseline (`chromeBandAligned()`).
///
/// Document actions (screenshot · Open in…) trail. When floating over the canvas (inspector
/// closed), the same cluster sits at the trailing edge.
struct ActionRow: View {
    var floating: Bool = false
    var onScreenshot: () -> Void
    var onOpenIn: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            screenshotButton
            openInButton
        }
        .frame(height: ChromeMetrics.buttonSize, alignment: .trailing)
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .chromeBandAligned()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector actions")
    }

    private var screenshotButton: some View {
        ChromeIconButton(symbol: "camera", title: "Screenshot", prominent: false, action: onScreenshot)
    }

    private var openInButton: some View {
        ChromeIconButton(symbol: "square.and.arrow.up", title: "Open in…", prominent: false, action: onOpenIn)
    }
}

/// Selection identity under the action cluster.
struct IdentityRow: View {
    var name: String
    var kindTitle: String
    var kind: NodeKind

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            NodeIcon(kind: kind)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(kindTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .accessibilityElement(children: .combine)
    }
}
