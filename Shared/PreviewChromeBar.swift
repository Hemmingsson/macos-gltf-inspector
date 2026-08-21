import SwiftUI

/// Top-trailing overlay: backdrop / debug cycle menus, auto-rotate, floor toggle.
struct PreviewChromeBar: View {
    @Binding var backdropIndex: Int
    @Binding var debugModeIndex: Int
    @Binding var autoRotate: Bool
    @Binding var showFloor: Bool
    var debugModes: [PreviewDebugMode]
    var isDark: Bool
    var isHost: Bool

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .trailing, spacing: 10) {
                PreviewCycleMenu(
                    options: PreviewBackground.allCases.map(\.shortTitle),
                    index: $backdropIndex,
                    tint: { active in
                        PreviewBackground.iconColor(
                            at: backdropIndex,
                            systemDark: isDark,
                            active: active
                        )
                    }
                ) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 14, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(chromeTint(active: backdropIndex != 0))
                }
                PreviewCycleMenu(
                    options: debugModes.map(\.shortTitle),
                    index: $debugModeIndex,
                    tint: { active in
                        chromeTint(active: active)
                    }
                ) {
                    Image(systemName: "square.3.layers.3d", variableValue: 1)
                        .font(.system(size: 14, weight: .regular))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(chromeTint(active: debugModeIndex != 0), .yellow)
                }
                Button {
                    autoRotate.toggle()
                } label: {
                    Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 14, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(chromeTint(active: autoRotate))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .previewGlassButtonStyle(prominent: autoRotate)
                .help("Auto-rotate")
                Button {
                    showFloor.toggle()
                } label: {
                    Image(systemName: "circle.grid.2x2")
                        .font(.system(size: 14, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(chromeTint(active: showFloor))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .previewGlassButtonStyle(prominent: showFloor)
                .help(showFloor ? "Hide polar floor" : "Show polar floor")
            }
        }
        .padding(.top, isHost ? 12 : 14)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func chromeTint(active: Bool) -> Color {
        PreviewBackground.iconColor(at: backdropIndex, systemDark: isDark, active: active)
    }
}

struct PreviewPlaybackBar: View {
    @Binding var isPlaying: Bool
    @Binding var isSeeking: Bool
    @Binding var currentTime: TimeInterval
    @Binding var clipIndex: Int
    var clipTitles: [String]
    var clipDuration: TimeInterval
    var tint: Color
    var onSeek: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if clipTitles.count > 1 {
                Picker("Animation clip", selection: $clipIndex) {
                    ForEach(Array(clipTitles.enumerated()), id: \.offset) { index, title in
                        Text(title).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .foregroundStyle(tint)
                .help("Animation clip")
            }

            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .previewGlassButtonStyle(prominent: isPlaying)
            .help(isPlaying ? "Pause" : "Play")

            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { onSeek($0) }
                ),
                in: 0...max(clipDuration, 0.001)
            ) { editing in
                isSeeking = editing
            }
            .controlSize(.small)
            .tint(tint)

            Text(String(format: "%.2f", currentTime))
                .font(.system(size: 11, weight: .regular).monospacedDigit())
                .foregroundStyle(tint)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule(style: .continuous))
    }
}

extension View {
    @ViewBuilder
    func previewGlassButtonStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }
}
