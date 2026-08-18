import QuickLookThumbnailing
import SceneKit
import GLTFKit2
import ImageIO
import UniformTypeIdentifiers
import AppKit

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let scale = max(request.scale, 1)
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * scale))

        let accessed = request.fileURL.startAccessingSecurityScopedResource()
        let stopAccess = {
            if accessed { request.fileURL.stopAccessingSecurityScopedResource() }
        }

        GLTFAsset.load(with: request.fileURL, options: [:]) { [weak self] (_, status, maybeAsset, maybeError, _) in
            defer { stopAccess() }
            guard let self else { return }
            if status == .complete, let asset = maybeAsset {
                self.finish(scene: SCNScene(gltfAsset: asset), pixel: pixel, handler: handler)
            } else if let error = maybeError {
                handler(nil, error)
            }
        }
    }

    private func finish(scene: SCNScene, pixel: Int, handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            scene.background.contents = NSColor.white
            scene.rootNode.enumerateChildNodes { node, _ in
                if node.camera != nil { node.camera = nil }
            }

            let cameraNode = makeCameraForScene(scene)
            scene.rootNode.addChildNode(cameraNode)

            let view = SCNView(frame: NSRect(x: 0, y: 0, width: pixel, height: pixel))
            view.wantsLayer = true
            view.layer?.contentsScale = 1
            view.backgroundColor = .white
            view.antialiasingMode = .multisampling4X
            view.autoenablesDefaultLighting = true
            view.scene = scene
            view.pointOfView = cameraNode
            view.layoutSubtreeIfNeeded()

            let snapshot = view.snapshot()
            guard
                let raw = bitmapImage(snapshot),
                let filled = cropToContentAndFill(raw, output: pixel)
            else {
                handler(nil, NSError(domain: "GLBThumbnail", code: 1))
                return
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("glb-thumb-\(UUID().uuidString).png")
            try writePNG(filled, to: url)
            handler(QLThumbnailReply(imageFileURL: url), nil)
        } catch {
            handler(nil, error)
        }
    }

    /// Front 3/4, Y-up. glTF models face +Z, so the camera stands on -Z.
    private func makeCameraForScene(_ scene: SCNScene) -> SCNNode {
        let (minBound, maxBound) = geometryBounds(of: scene.rootNode) ?? scene.rootNode.boundingBox
        let center = SCNVector3(
            (minBound.x + maxBound.x) / 2,
            (minBound.y + maxBound.y) / 2,
            (minBound.z + maxBound.z) / 2
        )
        let extent = SCNVector3(
            maxBound.x - minBound.x,
            maxBound.y - minBound.y,
            maxBound.z - minBound.z
        )
        let radius = max(
            0.0001,
            CGFloat(sqrt(extent.x * extent.x + extent.y * extent.y + extent.z * extent.z)) * 0.5
        )

        let fovDegrees: CGFloat = 35
        let distance = (radius / tan(fovDegrees * .pi / 360)) * 1.02
        let yaw = 35.0 * .pi / 180.0
        let pitch = 18.0 * .pi / 180.0

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera!.fieldOfView = fovDegrees
        cameraNode.camera!.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(
            center.x + distance * sin(yaw) * cos(pitch),
            center.y + distance * sin(pitch),
            center.z - distance * cos(yaw) * cos(pitch)
        )
        cameraNode.look(at: center)
        return cameraNode
    }

    private func geometryBounds(of root: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var minB = SCNVector3(CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude)
        var maxB = SCNVector3(-CGFloat.greatestFiniteMagnitude, -CGFloat.greatestFiniteMagnitude, -CGFloat.greatestFiniteMagnitude)
        var found = false

        func accumulate(_ node: SCNNode) {
            guard node.geometry != nil, node.light == nil, node.camera == nil else { return }
            let (localMin, localMax) = node.boundingBox
            let corners = [
                SCNVector3(localMin.x, localMin.y, localMin.z),
                SCNVector3(localMin.x, localMin.y, localMax.z),
                SCNVector3(localMin.x, localMax.y, localMin.z),
                SCNVector3(localMin.x, localMax.y, localMax.z),
                SCNVector3(localMax.x, localMin.y, localMin.z),
                SCNVector3(localMax.x, localMin.y, localMax.z),
                SCNVector3(localMax.x, localMax.y, localMin.z),
                SCNVector3(localMax.x, localMax.y, localMax.z),
            ]
            for corner in corners {
                let world = node.convertPosition(corner, to: root)
                minB.x = min(minB.x, world.x)
                minB.y = min(minB.y, world.y)
                minB.z = min(minB.z, world.z)
                maxB.x = max(maxB.x, world.x)
                maxB.y = max(maxB.y, world.y)
                maxB.z = max(maxB.z, world.z)
                found = true
            }
        }

        accumulate(root)
        root.enumerateChildNodes { node, _ in accumulate(node) }
        return found ? (minB, maxB) : nil
    }

    private func bitmapImage(_ image: NSImage) -> CGImage? {
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           let cg = bitmap.cgImage {
            return cg
        }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func cropToContentAndFill(_ image: CGImage, output: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = 0, maxY = 0
        var found = false
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2], a = pixels[i + 3]
                if a > 8 && (r < 250 || g < 250 || b < 250) {
                    found = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard found else { return image }

        let pad = max(4, Int(CGFloat(max(maxX - minX, maxY - minY)) * 0.06))
        minX = max(0, minX - pad)
        minY = max(0, minY - pad)
        maxX = min(width - 1, maxX + pad)
        maxY = min(height - 1, maxY + pad)

        let cropW = max(1, maxX - minX + 1)
        let cropH = max(1, maxY - minY + 1)
        guard let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: cropW, height: cropH)) else {
            return image
        }

        let side = CGFloat(max(cropW, cropH))
        guard let out = CGContext(
            data: nil,
            width: output,
            height: output,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cropped }

        out.setFillColor(NSColor.white.cgColor)
        out.fill(CGRect(x: 0, y: 0, width: output, height: output))
        let scale = CGFloat(output) / side
        let drawW = CGFloat(cropW) * scale
        let drawH = CGFloat(cropH) * scale
        out.interpolationQuality = .high
        out.draw(cropped, in: CGRect(
            x: (CGFloat(output) - drawW) / 2,
            y: (CGFloat(output) - drawH) / 2,
            width: drawW,
            height: drawH
        ))
        return out.makeImage()
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "GLBThumbnail", code: 4)
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            throw NSError(domain: "GLBThumbnail", code: 5)
        }
    }
}
