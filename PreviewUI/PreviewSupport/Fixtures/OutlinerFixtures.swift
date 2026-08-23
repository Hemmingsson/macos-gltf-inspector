import Foundation

/// Static outliner trees for sidebar previews — mirrors `OutlinerTreeTests` structure.
public enum OutlinerFixtures {
  /// Root → Mesh → Child (depth 0/1/2) for fold/unfold previews.
  public static let nestedScene: OutlinerItem = OutlinerItem(
    id: NodeID(kind: .empty, index: 0),
    name: "Root",
    depth: 0,
    children: [
      OutlinerItem(
        id: NodeID(kind: .mesh, index: 0),
        name: "Mesh",
        depth: 1,
        children: [
          OutlinerItem(
            id: NodeID(kind: .mesh, index: 1),
            name: "Child",
            depth: 2
          )
        ]
      )
    ]
  )

  public static let cubeScene: [OutlinerItem] = [
    OutlinerItem(
      id: NodeID(kind: .empty, index: 0),
      name: "Root",
      depth: 0,
      children: [
        OutlinerItem(id: NodeID(kind: .mesh, index: 0), name: "Cube", depth: 1)
      ]
    )
  ]

  public static let riggedScene: [OutlinerItem] = [
    OutlinerItem(
      id: NodeID(kind: .empty, index: 0),
      name: "Armature",
      depth: 0,
      children: [
        OutlinerItem(
          id: NodeID(kind: .empty, index: 1),
          name: "Hip",
          depth: 1,
          children: [
            OutlinerItem(id: NodeID(kind: .mesh, index: 0), name: "Body", depth: 2),
            OutlinerItem(id: NodeID(kind: .empty, index: 2), name: "Head", depth: 2)
          ]
        )
      ]
    )
  ]

  public static let lightsScene: [OutlinerItem] = [
    OutlinerItem(id: NodeID(kind: .light, index: 0), name: "Key", depth: 0),
    OutlinerItem(id: NodeID(kind: .light, index: 1), name: "Fill", depth: 0),
    OutlinerItem(id: NodeID(kind: .light, index: 2), name: "Rim", depth: 0)
  ]

  public static let multiScenePicker: [OutlinerItem] = [
    OutlinerItem(id: NodeID(kind: .scene, index: 0), name: "Overview"),
    OutlinerItem(id: NodeID(kind: .scene, index: 1), name: "Detail")
  ]

  public static let defaultExpandedNested = OutlinerTree.defaultExpandedIDs(roots: [nestedScene], maxDepth: 2)

  public static let nestedPreorderIdentity: [NodeID] = OutlinerTree.treeIdentity([nestedScene])
}
