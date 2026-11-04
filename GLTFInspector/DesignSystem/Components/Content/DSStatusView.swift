import SwiftUI

/// Pane-filling status for "there is no content here yet": empty, loading or failed.
///
/// Empty and failed are a system `ContentUnavailableView` (symbol, title, description), so the
/// typography, spacing and VoiceOver grouping are the platform's and the view scales from a
/// narrow sidebar to the canvas. Loading is a quiet `ProgressView` over a secondary caption — a
/// spinner, never a big title, because it should be gone before anyone reads it. Every failure
/// carries its message (AGENTS.md: never a silent spinner on reject).
struct DSStatusView: View {
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
    static func empty(_ title: String, systemImage: String, message: String? = nil) -> Self {
        Self(.empty(title: title, systemImage: systemImage, message: message))
    }

    /// Work in progress ("Loading model…").
    static func loading(_ title: String) -> Self {
        Self(.loading(title: title))
    }

    /// The load or check failed; `message` says why.
    static func failed(_ title: String, message: String) -> Self {
        Self(.failed(title: title, message: message))
    }

    var body: some View {
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
