import Foundation
import Observation

/// Dev-time `SelectionModel` for `#Preview` — cube-like mesh selection by default.
@MainActor
@Observable
public final class MockSelectionModel: SelectionModel {
    public private(set) var selected: NodeID?
    public private(set) var isolated: NodeID?

    private var detailsByID: [NodeID: NodeDetail]
    private var visibility: [NodeID: Bool]

    public var detail: NodeDetail? {
        guard let selected else { return nil }
        return detailsByID[selected]
    }

    public init(
        selected: NodeID? = NodeID(kind: .mesh, index: 0),
        isolated: NodeID? = nil,
        details: [NodeDetail] = [NodeDetailFixtures.mesh],
        visibility: [NodeID: Bool] = [:]
    ) {
        self.selected = selected
        self.isolated = isolated
        self.detailsByID = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
        self.visibility = visibility
    }

    public func select(_ id: NodeID?) {
        selected = id
    }

    public func setVisible(_ id: NodeID, _ isVisible: Bool) {
        visibility[id] = isVisible
    }

    public func isVisible(_ id: NodeID) -> Bool {
        visibility[id] ?? true
    }

    public func isolate(_ id: NodeID?) {
        isolated = id
    }
}
