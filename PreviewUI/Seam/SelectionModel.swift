import Foundation
import Observation

/// Sidebar ↔ canvas selection, visibility and isolation for one window.
@MainActor
protocol SelectionModel: AnyObject, Observable {
    /// Nil when nothing is selected — the inspector column is closed.
    var selected: NodeID? { get }
    /// Everything the inspector can show about `selected`.
    var detail: NodeDetail? { get }
    /// Set while one node is isolated (Option-click the eye).
    var isolated: NodeID? { get }

    /// Pass nil to clear the selection.
    func select(_ id: NodeID?)
    func setVisible(_ id: NodeID, _ isVisible: Bool)
    func isVisible(_ id: NodeID) -> Bool
    /// Pass nil to leave isolation.
    func isolate(_ id: NodeID?)
}
