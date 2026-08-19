import RealityKit
import GLTFKit2

extension GLBRealityKitConvert {
    func convert(camera: GLTFCamera) -> (any Component)? {
        if let perspectiveParams = camera.perspective {
            return PerspectiveCameraComponent(near: camera.zNear,
                                              far: camera.zFar,
                                              fieldOfViewInDegrees: GLTFDegFromRad(perspectiveParams.yFOV))
        }
        if let orthographicParams = camera.orthographic {
            var orthographic = OrthographicCameraComponent()
            orthographic.near = camera.zNear
            orthographic.far = camera.zFar
            orthographic.scale = orthographicParams.yMag
            return orthographic
        }
        return nil
    }
}
