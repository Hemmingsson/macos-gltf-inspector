import Foundation
import Observation

/// Sidebar ↔ canvas selection for one window.
@MainActor
public protocol SelectionModel: AnyObject, Observable {
    /// Nil when nothing is selected — the inspector column is closed.
    var selected: NodeID? { get }
    /// Everything the inspector can show about `selected`.
    var detail: NodeDetail? { get }

    /// Pass nil to clear the selection.
    func select(_ id: NodeID?)
}
