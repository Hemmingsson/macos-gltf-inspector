import Foundation

/// Static outliner trees for sidebar previews.
enum OutlinerFixtures {
  static let cubeScene: [OutlinerItem] = [
    OutlinerItem(
      id: NodeID(kind: .empty, index: 0),
      name: "Root",
      children: [
        OutlinerItem(id: NodeID(kind: .mesh, index: 0), name: "Cube")
      ]
    )
  ]
}
