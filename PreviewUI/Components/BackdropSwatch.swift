import SwiftUI

/// One backdrop choice: a colour disc that takes an accent ring when it is the current one.
public struct BackdropSwatch: View {
    public var style: BackdropStyle
    public var isActive: Bool
    public var select: () -> Void

    @Environment(\.previewBorder) private var border

    public var body: some View {
        Button(action: select) {
            fill
                .frame(width: PillMetrics.swatchSize, height: PillMetrics.swatchSize)
                .clipShape(.circle)
                .overlay { Circle().strokeBorder(border, lineWidth: 1) }
                .overlay { activeRing }
                .contentShape(.circle)
        }
        .buttonStyle(BackdropSwatchButtonStyle())
        .help(style.title)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    @ViewBuilder
    private var activeRing: some View {
        if isActive {
            ZStack {
                Circle()
                    .strokeBorder(Theme.card, lineWidth: 2)
                    .frame(width: 24, height: 24)
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .frame(width: 27, height: 27)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var fill: some View {
        switch style {
        case .window: BackdropCheckerboard()
        case .white: Theme.backdropWhite
        case .dark: Theme.backdropDark
        }
    }
}

// MARK: - Previews

#Preview("window inactive") {
    BackdropSwatch(style: .window, isActive: false) {}
        .padding(24)
}

#Preview("window active") {
    BackdropSwatch(style: .window, isActive: true) {}
        .padding(24)
}

#Preview("white active") {
    BackdropSwatch(style: .white, isActive: true) {}
        .padding(24)
}

#Preview("dark active") {
    BackdropSwatch(style: .dark, isActive: true) {}
        .padding(24)
}

#Preview("backdrop row") {
    HStack(spacing: 7) {
        ForEach(BackdropStyle.allCases) { style in
            BackdropSwatch(style: style, isActive: style == .white) {}
        }
    }
    .padding(24)
}
