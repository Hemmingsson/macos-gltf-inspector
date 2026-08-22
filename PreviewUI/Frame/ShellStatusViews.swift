import SwiftUI

/// Canvas / panel copy for non-ready document states.
///
/// Quiet chrome, Theme tokens, no fake progress on `.failed` (AGENTS.md).
enum ShellStatusCopy {
    static let emptyTitle = "Open a glTF file"
    static let emptyDetail = "Drop a .glb or .gltf here, or choose File → Open…"
    static let loadingTitle = "Loading model…"
    static let failedTitle = "Couldn’t load model"
    /// Debug fixture for `.failed` — keep one string so previews and tests stay in sync.
    static let invalidFileDetail = "The file isn’t a valid glTF / GLB."
}

/// Centered status over the canvas (empty / loading / failed).
struct CanvasStatusView: View {
    var state: ShellDocumentState

    var body: some View {
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

/// Quiet sidebar filler when there is no ready document.
struct SidebarStatusView: View {
    var state: ShellDocumentState

    var body: some View {
        VStack(spacing: 10) {
            switch state {
            case .empty:
                Text(ShellStatusCopy.emptyTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("No file open")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
            case .loading:
                ProgressView()
                    .controlSize(.small)
                Text(ShellStatusCopy.loadingTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
            case .failed(let message):
                Text(ShellStatusCopy.failedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

/// Quiet inspector filler when there is no ready document.
struct InspectorStatusView: View {
    var state: ShellDocumentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .empty:
                Text("Nothing to inspect")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Open a file to see node and file details.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(ShellStatusCopy.loadingTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                }
            case .failed(let message):
                Text(ShellStatusCopy.failedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}
