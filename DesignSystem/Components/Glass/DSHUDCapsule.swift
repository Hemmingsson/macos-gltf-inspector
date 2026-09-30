import SwiftUI

/// A non-interactive glass readout on the canvas: the dimensions readout, the playback bar.
///
/// One capsule of `DS.Glass.hud` (`Glass.regular`, not interactive — the capsule itself is not a
/// control). Buttons inside are borderless and the DS glass controls draw no glass of their own
/// (`DSGlassPlacement.inIsland`), which is what keeps the playback bar's play button from being
/// glass on glass. Separate groups with `DSGlassIslandDivider()`.
public struct DSHUDCapsule<Content: View>: View {
    private let height: CGFloat
    private let horizontalPadding: CGFloat
    private let spacing: CGFloat
    private let content: Content

    /// - Parameters:
    ///   - height: Capsule height. Defaults to `DS.Metrics.glassControl`.
    ///   - horizontalPadding: Inset from the capsule's ends. Defaults to `DS.Spacing.l`.
    ///   - spacing: Gap between items. Defaults to `DS.Spacing.m`.
    ///   - content: The readout.
    public init(
        height: CGFloat = DS.Metrics.glassControl,
        horizontalPadding: CGFloat = DS.Spacing.l,
        spacing: CGFloat = DS.Spacing.m,
        @ViewBuilder content: () -> Content
    ) {
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .buttonStyle(.borderless)
        .dsGlassPlacement(.inIsland)
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .glassEffect(DS.Glass.hud, in: .capsule)
    }
}

// MARK: - Previews

private struct DSHUDCapsulePreview: View {
    @State private var isPlaying = false
    @State private var playhead = 0.32

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            DSHUDCapsule(height: 30) {
                Image(systemName: "cube")
                    .foregroundStyle(DS.Color.textSecondary)
                Text("1.00 × 1.00 × 1.00 m")
                    .font(DS.Font.value)
                    .foregroundStyle(DS.Color.textPrimary)
            }

            DSHUDCapsule(height: 36, horizontalPadding: DS.Spacing.s) {
                DSGlassIconButton(
                    isPlaying ? "Pause" : "Play",
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                ) {
                    isPlaying.toggle()
                }
                Slider(value: $playhead)
                    .controlSize(.small)
                    .frame(width: 180)
                    .accessibilityLabel("Playhead")
                Text("0:01.2 / 0:03.7")
                    .font(DS.Font.value)
                    .foregroundStyle(DS.Color.textSecondary)
                DSGlassIslandDivider()
                DSGlassMenuButton("Animation clip", systemImage: "film", style: .titled("Idle")) {
                    Button("Idle") {}
                    Button("Walk") {}
                }
            }
        }
    }
}

#Preview("hud", traits: .sizeThatFitsLayout) {
    DSGlassPreviewBackdrops {
        DSHUDCapsulePreview()
    }
    .frame(width: 520)
}
