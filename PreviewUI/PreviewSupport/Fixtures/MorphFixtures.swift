import Foundation

/// Static morph metadata and runtime controls for section previews — no disk I/O.
public enum MorphFixtures {
  public static let triangle = MorphInfo(
    index: 0,
    meshName: "Triangle",
    targetNames: ["Smile", "Blink"]
  )

  public static let face = MorphInfo(
    index: 1,
    meshName: "Face",
    targetNames: ["Smile", "Frown", "Blink Left", "Blink Right", "Jaw Open"]
  )

  public static let triangleControls: [MorphTargetControl] = [
    MorphTargetControl(id: "morph-0-smile", name: "Smile", weight: 0.35),
    MorphTargetControl(id: "morph-0-blink", name: "Blink", weight: 0)
  ]

  public static let faceControls: [MorphTargetControl] = [
    MorphTargetControl(id: "morph-1-smile", name: "Smile", weight: 0.2),
    MorphTargetControl(id: "morph-1-frown", name: "Frown", weight: 0),
    MorphTargetControl(id: "morph-1-blink-left", name: "Blink Left", weight: 0.65),
    MorphTargetControl(id: "morph-1-blink-right", name: "Blink Right", weight: 0.65),
    MorphTargetControl(id: "morph-1-jaw-open", name: "Jaw Open", weight: 0.1)
  ]
}
