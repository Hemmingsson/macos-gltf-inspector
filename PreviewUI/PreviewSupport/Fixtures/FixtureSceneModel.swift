import Foundation

/// In-memory `SceneModel` snapshots for `#Preview` — no disk I/O.
public struct FixtureSceneModel: SceneModel {
  public var fileName: String
  public var scenes: [SceneInfo]
  public var defaultSceneID: NodeID?
  public var nodeTree: [SceneNode]
  public var cameras: [CameraInfo]
  public var lights: [LightInfo]
  public var materials: [MaterialInfo]
  public var animations: [AnimationInfo]
  public var skins: [SkinInfo]
  public var morphs: [MorphInfo]
  public var materialVariantNames: [String]
  public var stats: Stats
  public var dimensions: Dimensions
  public var validation: ValidationResult
  public var pipelineReport: PipelineReport
  public var convertProblems: ConvertProblemList

  public init(
    fileName: String,
    scenes: [SceneInfo],
    defaultSceneID: NodeID? = nil,
    nodeTree: [SceneNode],
    cameras: [CameraInfo] = [],
    lights: [LightInfo] = [],
    materials: [MaterialInfo] = [],
    animations: [AnimationInfo] = [],
    skins: [SkinInfo] = [],
    morphs: [MorphInfo] = [],
    materialVariantNames: [String] = [],
    stats: Stats,
    dimensions: Dimensions,
    validation: ValidationResult = ValidationFixtures.clean,
    pipelineReport: PipelineReport = PipelineReport(entries: [
      PipelineReport.Entry(kind: .lighting, title: "Studio environment", detail: "Bundled IBL")
    ]),
    convertProblems: ConvertProblemList = ConvertProblemList()
  ) {
    self.fileName = fileName
    self.scenes = scenes
    self.defaultSceneID = defaultSceneID ?? scenes.first?.id
    self.nodeTree = nodeTree
    self.cameras = cameras
    self.lights = lights
    self.materials = materials
    self.animations = animations
    self.skins = skins
    self.morphs = morphs
    self.materialVariantNames = materialVariantNames
    self.stats = stats
    self.dimensions = dimensions
    self.validation = validation
    self.pipelineReport = pipelineReport
    self.convertProblems = convertProblems
  }

  private static let cubeScene = SceneInfo(
    index: 0,
    name: "Scene",
    rootNodeIDs: [NodeID(kind: .empty, index: 0)]
  )

  private static let cubeNodeTree: [SceneNode] = [
    SceneNode(
      kind: .empty,
      index: 0,
      name: "Root",
      children: [
        SceneNode(kind: .mesh, index: 0, name: "Cube")
      ]
    )
  ]

  public static let cube = FixtureSceneModel(
    fileName: "Cube.glb",
    scenes: [cubeScene],
    nodeTree: cubeNodeTree,
    materials: [MaterialFixtures.cube],
    stats: Stats(
      triangleCount: 12,
      vertexCount: 24,
      meshCount: 1,
      materialCount: 1,
      textureCount: 2,
      maxTextureDimension: 256,
      fileSizeBytes: 4_096
    ),
    dimensions: Dimensions(width: 1, height: 1, depth: 1)
  )

  public static let multiScene = FixtureSceneModel(
    fileName: "TwoScenes.gltf",
    scenes: [
      SceneInfo(index: 0, name: "Overview", rootNodeIDs: [NodeID(kind: .empty, index: 0)]),
      SceneInfo(index: 1, name: "Detail", rootNodeIDs: [NodeID(kind: .empty, index: 1)])
    ],
    nodeTree: [
      SceneNode(kind: .empty, index: 0, name: "Overview Root", children: [
        SceneNode(kind: .mesh, index: 0, name: "Landscape")
      ]),
      SceneNode(kind: .empty, index: 1, name: "Detail Root", children: [
        SceneNode(kind: .mesh, index: 1, name: "Hero")
      ])
    ],
    materials: [MaterialFixtures.cube, MaterialFixtures.fullPBR],
    stats: Stats(
      triangleCount: 8_420,
      vertexCount: 12_640,
      meshCount: 2,
      materialCount: 2,
      textureCount: 6,
      maxTextureDimension: 2048,
      fileSizeBytes: 1_048_576
    ),
    dimensions: Dimensions(width: 12, height: 4, depth: 8)
  )

  public static let rigged = FixtureSceneModel(
    fileName: "Rigged.gltf",
    scenes: [cubeScene],
    nodeTree: [
      SceneNode(kind: .empty, index: 0, name: "Armature", children: [
        SceneNode(kind: .empty, index: 1, name: "Hip", children: [
          SceneNode(kind: .mesh, index: 0, name: "Body"),
          SceneNode(kind: .empty, index: 2, name: "Head")
        ])
      ])
    ],
    materials: [MaterialFixtures.fullPBR],
    skins: [
      SkinInfo(
        index: 0,
        name: "Armature",
        jointCount: 24,
        jointNames: ["Hip", "Spine", "Chest", "Head", "Shoulder.L", "Shoulder.R"]
      )
    ],
    stats: Stats(
      triangleCount: 18_240,
      vertexCount: 21_600,
      meshCount: 1,
      materialCount: 1,
      textureCount: 5,
      maxTextureDimension: 2048,
      isRigged: true
    ),
    dimensions: Dimensions(width: 0.6, height: 1.8, depth: 0.35)
  )

  public static let morph = FixtureSceneModel(
    fileName: "MorphTriangle.gltf",
    scenes: [cubeScene],
    nodeTree: [
      SceneNode(kind: .empty, index: 0, name: "Root", children: [
        SceneNode(kind: .mesh, index: 0, name: "Triangle")
      ])
    ],
    materials: [MaterialFixtures.baseColorOnly],
    morphs: [MorphFixtures.triangle, MorphFixtures.face],
    stats: Stats(
      triangleCount: 1,
      vertexCount: 3,
      meshCount: 1,
      materialCount: 1,
      morphTargetCount: 7
    ),
    dimensions: Dimensions(width: 1, height: 1, depth: 0.01)
  )

  public static let lights = FixtureSceneModel(
    fileName: "PunctualLights.gltf",
    scenes: [cubeScene],
    nodeTree: [
      SceneNode(kind: .empty, index: 0, name: "Stage", children: [
        SceneNode(kind: .mesh, index: 0, name: "Subject"),
        SceneNode(kind: .light, index: 0, name: "Key"),
        SceneNode(kind: .light, index: 1, name: "Fill"),
        SceneNode(kind: .light, index: 2, name: "Rim")
      ])
    ],
    lights: [
      LightInfo(index: 0, name: "Key", kind: .directional, intensity: 3.5),
      LightInfo(index: 1, name: "Fill", kind: .point, intensity: 120, range: 8),
      LightInfo(
        index: 2,
        name: "Rim",
        kind: .spot,
        intensity: 800,
        range: 12,
        innerConeDegrees: 18,
        outerConeDegrees: 32
      )
    ],
    materials: [MaterialFixtures.cube],
    stats: Stats(
      triangleCount: 2_400,
      vertexCount: 4_800,
      meshCount: 1,
      materialCount: 1,
      textureCount: 2,
      maxTextureDimension: 512
    ),
    dimensions: Dimensions(width: 0.8, height: 1.2, depth: 0.8),
    pipelineReport: PipelineReport(entries: [
      PipelineReport.Entry(kind: .lighting, title: "File lights", detail: "3 punctual lights")
    ])
  )

  public static let cameras = FixtureSceneModel(
    fileName: "PerspAndOrtho.gltf",
    scenes: [cubeScene],
    nodeTree: [
      SceneNode(kind: .empty, index: 0, name: "Stage", children: [
        SceneNode(kind: .mesh, index: 0, name: "Subject"),
        SceneNode(kind: .camera, index: 0, name: "Hero"),
        SceneNode(kind: .camera, index: 1, name: "Ortho")
      ])
    ],
    cameras: [
      CameraInfo(
        index: 0,
        name: "Hero",
        projection: .perspective,
        fieldOfViewDegrees: 50,
        zNear: 0.05,
        zFar: 200
      ),
      CameraInfo(
        index: 1,
        name: "Ortho",
        projection: .orthographic,
        xMag: 4,
        yMag: 3,
        zNear: 0.1,
        zFar: 100
      )
    ],
    materials: [MaterialFixtures.cube],
    stats: Stats(
      triangleCount: 2_400,
      vertexCount: 4_800,
      meshCount: 1,
      materialCount: 1
    ),
    dimensions: Dimensions(width: 2, height: 1.5, depth: 1)
  )
}
