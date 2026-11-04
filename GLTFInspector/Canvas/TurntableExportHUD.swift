import SwiftUI

/// Progress and Cancel while a turntable export runs. The layer covers the canvas so pointer
/// input cannot reach the model; the canvas also ignores it (`ModelCanvasController.inputLocked`).
struct TurntableExportHUD: View {
    var view: ViewState

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
            if let progress = view.turntableProgress {
                DSHUDCapsule(horizontalPadding: DS.Spacing.m) {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                        .frame(width: 120)
                    Text("Exporting frame \(min(progress.done + 1, progress.total)) of \(progress.total)")
                        .font(.callout)
                        .monospacedDigit()
                        .lineLimit(1)
                    Button("Cancel") { view.cancelTurntableExport() }
                        .keyboardShortcut(.cancelAction)
                }
                .fixedSize()
            }
        }
    }
}
