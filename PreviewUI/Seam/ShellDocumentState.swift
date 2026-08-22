import Foundation

/// Load lifecycle — empty / loading / ready / failed.
///
/// Host drives this from `EntityLoader` / open. Never leave a failed URL as a spinner
/// (AGENTS.md pitfall 2).
enum ShellDocumentState: Equatable, Sendable, Hashable {
    /// No document yet — drop / Open invite.
    case empty
    /// Bytes are in flight. Canvas may spin; panels stay quiet.
    case loading
    /// Model is available; chrome shows adaptive sections.
    case ready
    /// Open rejected. Always show the message — never a spinner.
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Sidebar / inspector header when there is no ready document name to show.
    var panelDocumentTitle: String {
        switch self {
        case .empty: "No file"
        case .loading: "Opening…"
        case .failed: "Unavailable"
        case .ready: ""
        }
    }
}
