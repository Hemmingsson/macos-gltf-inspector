import DesignSystem
import SwiftUI

/// Quick Look canvas chrome: backdrop cycle + auto-rotate only.
/// Host windows use PreviewUI overlays; do not reuse this in the host path.
struct PreviewQuickLookChrome: View {
    @Binding var backdropIndex: Int
    @Binding var autoRotate: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Metrics.clusterSpacing) {
            DSGlassIconButton(
                "Backdrop",
                systemImage: "circle.lefthalf.filled",
                isEngaged: backdropIndex != 0
            ) {
                cycleBackdrop()
            }
            .buttonBorderShape(.circle)
            .help(PreviewBackground.at(backdropIndex).shortTitle)
            .accessibilityValue(PreviewBackground.at(backdropIndex).shortTitle)

            DSGlassToggleButton(
                "Auto-rotate",
                systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                isOn: $autoRotate,
                shortcut: DS.Shortcuts.action(.autoRotate)
            )
            .buttonBorderShape(.circle)
        }
        .padding(.top, DS.Spacing.l)
        .padding(.trailing, DS.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func cycleBackdrop() {
        let count = PreviewBackground.allCases.count
        guard count > 0 else { return }
        backdropIndex = (backdropIndex + 1) % count
    }
}
