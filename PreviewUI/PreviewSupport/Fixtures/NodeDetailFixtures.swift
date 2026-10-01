import Foundation

/// Synthetic `NodeDetail` values for `#Preview` — no disk I/O.
public enum NodeDetailFixtures {
    public static let mesh = NodeDetail(
        id: NodeID(kind: .mesh, index: 0),
        name: "Cube",
        transform: TransformInfo(
            position: Vector3(x: 0, y: 0.5, z: 0),
            rotationDegrees: .zero,
            scale: .one
        ),
        geometry: GeometryInfo(triangleCount: 12, vertexCount: 24, uvSetCount: 1)
    )

    public static let material = NodeDetail(
        id: NodeID(kind: .material, index: 0),
        name: "Default Material",
        material: MaterialInfo(
            index: 0,
            name: "Default Material",
            maps: [.baseColor, .normal, .metallicRoughness],
            textures: [
                MaterialTextureInfo(map: .baseColor, width: 512, height: 512),
                MaterialTextureInfo(map: .normal, width: 512, height: 512),
                MaterialTextureInfo(map: .metallicRoughness, width: 512, height: 512)
            ],
            baseColorFactor: .white,
            metallicFactor: 0,
            roughnessFactor: 0.5,
            usedByMeshNames: ["Cube"]
        )
    )

    public static let camera = NodeDetail(
        id: NodeID(kind: .camera, index: 0),
        name: "Main Camera",
        transform: .identity,
        camera: CameraInfo(
            index: 0,
            name: "Main Camera",
            projection: .perspective,
            fieldOfViewDegrees: 45,
            zNear: 0.1,
            zFar: 100
        )
    )

    public static let light = NodeDetail(
        id: NodeID(kind: .light, index: 0),
        name: "Key Light",
        transform: .identity,
        light: LightInfo(
            index: 0,
            name: "Key Light",
            kind: .directional,
            color: .white,
            intensity: 3.14
        )
    )

    public static let animation = NodeDetail(
        id: NodeID(kind: .animation, index: 0),
        name: "Spin",
        animation: AnimationInfo(index: 0, name: "Spin", duration: 2.5)
    )

    public static let skin = NodeDetail(
        id: NodeID(kind: .skin, index: 0),
        name: "Armature",
        skin: SkinInfo(index: 0, name: "Armature", jointCount: 24)
    )

    public static let morph = NodeDetail(
        id: NodeID(kind: .morph, index: 0),
        name: "Smile",
        morph: MorphInfo(index: 0, meshName: "Face", targetNames: ["Smile", "Blink"])
    )
}
