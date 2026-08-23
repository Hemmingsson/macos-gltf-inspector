import SwiftUI

/// Quiet inspector filler when there is no ready document.
public struct InspectorStatusView: View {
    public var state: ShellDocumentState

    public var body: some View {
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

// MARK: - Previews

#Preview("empty", traits: .fixedLayout(width: Theme.inspectorWidth, height: 200)) {
    PreviewCanvas(width: Theme.inspectorWidth, height: 200) {
        InspectorStatusView(state: .empty)
    }
}

#Preview("loading", traits: .fixedLayout(width: Theme.inspectorWidth, height: 200)) {
    PreviewCanvas(width: Theme.inspectorWidth, height: 200) {
        InspectorStatusView(state: .loading)
    }
}

#Preview("failed", traits: .fixedLayout(width: Theme.inspectorWidth, height: 200)) {
    PreviewCanvas(width: Theme.inspectorWidth, height: 200) {
        InspectorStatusView(state: .failed(ShellStatusCopy.invalidFileDetail))
    }
}
