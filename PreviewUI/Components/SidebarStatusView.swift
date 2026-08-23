import SwiftUI

/// Quiet sidebar filler when there is no ready document.
public struct SidebarStatusView: View {
    public var state: ShellDocumentState

    public var body: some View {
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

// MARK: - Previews

#Preview("empty", traits: .fixedLayout(width: Theme.sidebarWidth, height: 200)) {
    PreviewCanvas(width: Theme.sidebarWidth, height: 200) {
        SidebarStatusView(state: .empty)
    }
}

#Preview("loading", traits: .fixedLayout(width: Theme.sidebarWidth, height: 200)) {
    PreviewCanvas(width: Theme.sidebarWidth, height: 200) {
        SidebarStatusView(state: .loading)
    }
}

#Preview("failed", traits: .fixedLayout(width: Theme.sidebarWidth, height: 200)) {
    PreviewCanvas(width: Theme.sidebarWidth, height: 200) {
        SidebarStatusView(state: .failed(ShellStatusCopy.invalidFileDetail))
    }
}
