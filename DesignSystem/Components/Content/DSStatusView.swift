import SwiftUI

/// Pane-filling status for "there is no content here yet": empty, loading or failed.
///
/// Empty and failed are a system `ContentUnavailableView` (symbol, title, description), so the
/// typography, spacing and VoiceOver grouping are the platform's and the view scales from a
/// narrow sidebar to the canvas. Loading is a quiet `ProgressView` over a secondary caption — a
/// spinner, never a big title, because it should be gone before anyone reads it. Every failure
/// carries its message (AGENTS.md: never a silent spinner on reject).
public struct DSStatusView: View {
    private enum Phase {
        case empty(title: String, systemImage: String, message: String?)
        case loading(title: String)
        case failed(title: String, message: String)
    }

    private let state: Phase

    private init(_ state: Phase) {
        self.state = state
    }

    /// Nothing to show yet ("Open a glTF file").
    public static func empty(_ title: String, systemImage: String, message: String? = nil) -> Self {
        Self(.empty(title: title, systemImage: systemImage, message: message))
    }

    /// Work in progress ("Loading model…").
    public static func loading(_ title: String) -> Self {
        Self(.loading(title: title))
    }

    /// The load or check failed; `message` says why.
    public static func failed(_ title: String, message: String) -> Self {
        Self(.failed(title: title, message: message))
    }

    public var body: some View {
        switch state {
        case let .empty(title, systemImage, message):
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let message {
                    Text(message)
                }
            }
        case let .failed(title, message):
            ContentUnavailableView {
                Label(title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case let .loading(title):
            VStack(spacing: DS.Spacing.m) {
                ProgressView()
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.Font.callout)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Previews

#Preview("Status view", traits: .fixedLayout(width: 720, height: 280)) {
    HStack(spacing: 0) {
        DSStatusView.empty("Open a glTF file", systemImage: "cube", message: "Drop a .glb or .gltf here.")
        Divider()
        DSStatusView.loading("Loading model…")
        Divider()
        DSStatusView.failed("Couldn't open file", message: "The file is not valid glTF 2.0.")
    }
    .background(DS.Color.windowBackground)
}

#Preview("Status view sidebar, long text, dark", traits: .fixedLayout(width: 248, height: 320)) {
    DSStatusView.failed(
        "Couldn't open file",
        message: "The buffer view at index 3 points past the end of the binary chunk, so the mesh data cannot be read."
    )
    .background(DS.Color.windowBackground)
    .preferredColorScheme(.dark)
}

#Preview("Status view empty, no message", traits: .fixedLayout(width: 248, height: 200)) {
    DSStatusView.empty("Nothing to inspect", systemImage: "sidebar.right")
        .background(DS.Color.windowBackground)
}
