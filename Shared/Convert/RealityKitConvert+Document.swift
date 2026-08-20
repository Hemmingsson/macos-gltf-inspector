import GLTFKit2

extension RealityKitConvert {
    static func makeDocument(from asset: GLTFAsset) -> GLTFSessionDocument {
        var document = GLTFSessionDocument()
        document.defaultSceneIndex = asset.scenes.firstIndex(where: { $0 === asset.defaultScene }) ?? 0
        document.scenes = asset.scenes.map { scene in
            GLTFSessionDocument.Scene(
                name: scene.name ?? "",
                rootNodeIndices: scene.nodes.compactMap { node in
                    asset.nodes.firstIndex(where: { $0 === node })
                }
            )
        }
        document.nodes = asset.nodes.enumerated().map { index, node in
            makeNode(node, index: index, asset: asset)
        }
        document.cameras = asset.cameras.map(makeCamera)
        document.animations = asset.animations.map(makeAnimation).filter { $0.duration > 0 }
        return document
    }

    static func makeNode(_ node: GLTFNode, index: Int, asset: GLTFAsset) -> GLTFSessionDocument.Node {
        GLTFSessionDocument.Node(
            index: index,
            name: node.name ?? "",
            children: node.childNodes.compactMap { child in
                asset.nodes.firstIndex(where: { $0 === child })
            },
            cameraIndex: node.camera.flatMap { camera in
                asset.cameras.firstIndex(where: { $0 === camera })
            }
        )
    }

    static func makeCamera(_ camera: GLTFCamera) -> GLTFSessionDocument.Camera {
        let zfar = camera.zFar.isFinite ? camera.zFar : nil
        if let perspective = camera.perspective {
            return GLTFSessionDocument.Camera(
                name: camera.name ?? "",
                type: "perspective",
                yfov: perspective.yFOV,
                znear: camera.zNear,
                zfar: zfar,
                xmag: nil,
                ymag: nil
            )
        }
        return GLTFSessionDocument.Camera(
            name: camera.name ?? "",
            type: "orthographic",
            yfov: nil,
            znear: camera.zNear,
            zfar: zfar,
            xmag: camera.orthographic?.xMag,
            ymag: camera.orthographic?.yMag
        )
    }

    static func makeAnimation(_ animation: GLTFAnimation) -> GLTFSessionDocument.Animation {
        GLTFSessionDocument.Animation(
            name: animation.name ?? "",
            duration: AnimationSampling.documentedDuration(animation)
        )
    }
}
