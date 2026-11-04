import Foundation
import Observation

/// Dev-time `SelectionModel` for `#Preview` — cube-like mesh selection by default.
@MainActor
@Observable
public final class MockSelectionModel: SelectionModel {
    public private(set) var selected: NodeID?

    private var detailsByID: [NodeID: NodeDetail]

    public var detail: NodeDetail? {
        guard let selected else { return nil }
        return detailsByID[selected]
    }

    public init(
        selected: NodeID? = NodeID(kind: .mesh, index: 0),
        details: [NodeDetail] = [NodeDetailFixtures.mesh]
    ) {
        self.selected = selected
        self.detailsByID = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
    }

    public func select(_ id: NodeID?) {
        selected = id
    }
}
