import SwiftUI

/// Top of the right column: actions on the unified chrome baseline, identity on the row below.
///
/// Sketch / DESIGN.md: screenshot · Open in… · inspector share the window's top band with the
/// sidebar toggle and canvas pills; selection name sits under that cluster, not beside it.
struct NodeHeader: View {
    var name: String
    var kindTitle: String
    var kind: NodeKind
    /// When true the inspector-toggle renders as the wireframe's `.tbtn.on` (accent / prominent).
    var isInspectorVisible: Bool
    var onScreenshot: () -> Void
    var onOpenIn: () -> Void
    var onToggleInspector: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActionRow(
                isInspectorVisible: isInspectorVisible,
                onScreenshot: onScreenshot,
                onOpenIn: onOpenIn,
                onToggleInspector: onToggleInspector
            )

            IdentityRow(name: name, kindTitle: kindTitle, kind: kind)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Trailing action cluster — traffic-light baseline via `chromeBandAligned()`.
///
/// Also used as a floating overlay when the inspector column is collapsed so the toggle can
/// bring the panel back without a second title band.
struct ActionRow: View {
    var isInspectorVisible: Bool
    var onScreenshot: () -> Void
    var onOpenIn: () -> Void
    var onToggleInspector: () -> Void

    @Environment(\.previewHair) private var hair

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ChromeIconButton(
                    symbol: "camera",
                    title: "Screenshot",
                    prominent: false,
                    action: onScreenshot
                )
                ChromeIconButton(
                    symbol: "square.and.arrow.up",
                    title: "Open in…",
                    prominent: false,
                    action: onOpenIn
                )

                hair
                    .frame(width: Theme.hairlineWidth, height: 16)
                    .padding(.horizontal, 2)
                    .accessibilityHidden(true)

                ChromeIconButton(
                    symbol: "sidebar.trailing",
                    title: "Inspector",
                    prominent: isInspectorVisible,
                    action: onToggleInspector
                )
            }
            .frame(height: ChromeMetrics.buttonSize)
        }
        .frame(height: ChromeMetrics.buttonSize, alignment: .trailing)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .chromeBandAligned()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector actions")
    }
}

/// Selection (or file) identity under the action cluster.
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
