import SwiftUI

/// Quick Look canvas chrome: backdrop cycle + auto-rotate only.
/// Host windows use PreviewUI overlays; do not reuse this in the host path.
struct PreviewQuickLookChrome: View {
    @Binding var backdropIndex: Int
    @Binding var autoRotate: Bool
    var isDark: Bool

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    cycleBackdrop()
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 14, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(tint(active: backdropIndex != 0))
                        .opacity(backdropIndex == 0 ? PreviewBackground.inactiveIconOpacity : 1)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .quickLookGlassButtonStyle(prominent: backdropIndex != 0)
                .help(PreviewBackground.at(backdropIndex).shortTitle)

                Button {
                    autoRotate.toggle()
                } label: {
                    Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 14, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(tint(active: autoRotate))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .quickLookGlassButtonStyle(prominent: autoRotate)
                .help("Auto-rotate")
            }
        }
        .padding(.top, 14)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func cycleBackdrop() {
        let count = PreviewBackground.allCases.count
        guard count > 0 else { return }
        backdropIndex = (backdropIndex + 1) % count
    }

    private func tint(active: Bool) -> Color {
        PreviewBackground.iconColor(at: backdropIndex, systemDark: isDark, active: active)
    }
}

extension View {
    /// QL glass button style. Named apart from PreviewUI's `previewGlassButtonStyle`
    /// so both can compile into the GLBPreview target.
    @ViewBuilder
    func quickLookGlassButtonStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }
}
