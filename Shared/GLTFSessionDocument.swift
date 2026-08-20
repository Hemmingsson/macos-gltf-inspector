import Foundation

/// Host outliner + file-camera graph produced during convert.
/// Not a full glTF mirror — mesh/material/light payloads live on the RealityKit entity / PreviewStats.
struct GLTFSessionDocument: Sendable, Equatable {
    var defaultSceneIndex: Int = 0
    var scenes: [Scene] = []
    var nodes: [Node] = []
    var cameras: [Camera] = []
    var animations: [Animation] = []

    struct Scene: Sendable, Equatable {
        var name: String
        var rootNodeIndices: [Int]
    }

    struct Node: Sendable, Equatable {
        var index: Int
        var name: String
        var children: [Int]
        var cameraIndex: Int?
    }

    struct Camera: Sendable, Equatable {
        var name: String
        var type: String
        var yfov: Float?
        var znear: Float
        var zfar: Float?
        var xmag: Float?
        var ymag: Float?
    }

    struct Animation: Sendable, Equatable {
        var name: String
        var duration: Double
    }
}
