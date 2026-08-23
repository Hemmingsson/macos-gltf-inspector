import SwiftUI

/// Centered status over the canvas (empty / loading / failed).
public struct CanvasStatusView: View {
    public var state: ShellDocumentState

    public var body: some View {
        ZStack {
            Theme.canvasGradient

            switch state {
            case .empty:
                statusStack(
                    symbol: "cube",
                    title: ShellStatusCopy.emptyTitle,
                    detail: ShellStatusCopy.emptyDetail,
                    spinning: false
                )
            case .loading:
                statusStack(
                    symbol: nil,
                    title: ShellStatusCopy.loadingTitle,
                    detail: nil,
                    spinning: true
                )
            case .failed(let message):
                statusStack(
                    symbol: "exclamationmark.triangle",
                    title: ShellStatusCopy.failedTitle,
                    detail: message,
                    spinning: false
                )
            case .ready:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .empty:
            "\(ShellStatusCopy.emptyTitle). \(ShellStatusCopy.emptyDetail)"
        case .loading:
            ShellStatusCopy.loadingTitle
        case .failed(let message):
            "\(ShellStatusCopy.failedTitle). \(message)"
        case .ready:
            "Canvas"
        }
    }

    private func statusStack(
        symbol: String?,
        title: String,
        detail: String?,
        spinning: Bool
    ) -> some View {
        VStack(spacing: 12) {
            if spinning {
                ProgressView()
                    .controlSize(.regular)
                    .accessibilityHidden(true)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(Theme.text3)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)

            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .padding(24)
    }
}

// MARK: - Previews

#Preview("empty", traits: .fixedLayout(width: 480, height: 320)) {
    PreviewCanvas(width: 480, height: 320, background: .canvas) {
        CanvasStatusView(state: .empty)
    }
}

#Preview("loading", traits: .fixedLayout(width: 480, height: 320)) {
    PreviewCanvas(width: 480, height: 320, background: .canvas) {
        CanvasStatusView(state: .loading)
    }
}

#Preview("failed", traits: .fixedLayout(width: 480, height: 320)) {
    PreviewCanvas(width: 480, height: 320, background: .canvas) {
        CanvasStatusView(state: .failed(ShellStatusCopy.invalidFileDetail))
    }
}
