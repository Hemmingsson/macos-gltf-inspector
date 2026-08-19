import Foundation
import RealityKit

enum QAShotDump {
    @MainActor
    static func write(
        index: Int,
        url: URL,
        status: String,
        model: GLBEntityLoader.LoadedModel?,
        session: HostSidebarModel? = nil,
        loadError: String? = nil,
        logLines: [String] = [],
        shotName: String = "",
        shotSource: String = "",
        shotBytes: Int = 0
    ) {
        guard let root = QAShotLaunch.outputDirectory else { return }
        let folder = root.appendingPathComponent(String(format: "%02d-%@", index, url.lastPathComponent))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        writeText(readme, to: folder.appendingPathComponent("README.txt"))

        let gltf = readGLTFJSON(from: url)
        if let gltf {
            writeJSON(sanitize(gltf), to: folder.appendingPathComponent("gltf.json"))
            writeJSON(gltfHeader(gltf), to: folder.appendingPathComponent("gltf-header.json"))
            writeJSON(gltfPrimitives(gltf), to: folder.appendingPathComponent("gltf-primitives.json"))
            writeJSON(gltfImages(gltf), to: folder.appendingPathComponent("gltf-images.json"))
        } else {
            writeText("could not parse glTF JSON\n", to: folder.appendingPathComponent("gltf.json"))
        }

        if !logLines.isEmpty {
            writeText(logLines.joined(separator: "\n") + "\n", to: folder.appendingPathComponent("convert-log.txt"))
        }
        var issues: [String] = []
        if let loadError, !loadError.isEmpty {
            writeText(loadError + "\n", to: folder.appendingPathComponent("convert-error.txt"))
            issues.append("convert error: \(loadError)")
        }

        if let model {
            writeJSON(documentJSON(model.document), to: folder.appendingPathComponent("document.json"))
            writeText(entityTree(model.entity), to: folder.appendingPathComponent("entity-tree.txt"))
            writeJSON(entityJSON(model.entity), to: folder.appendingPathComponent("entity-tree.json"))
            writeText(cameraFit(model.entity), to: folder.appendingPathComponent("camera-fit.txt"))
            issues.append(contentsOf: collectIssues(model: model, gltf: gltf))
        } else if status != "ready" {
            issues.append("no LoadedModel status=\(status)")
        }
        writeJSON(sessionJSON(session), to: folder.appendingPathComponent("host-look.json"))
        writeText(
            openSummary(
                url: url,
                status: status,
                model: model,
                loadError: loadError,
                shotName: shotName,
                shotSource: shotSource,
                shotBytes: shotBytes
            ),
            to: folder.appendingPathComponent("open.txt")
        )
        if !shotName.isEmpty {
            let src = root.appendingPathComponent(shotName)
            let dest = folder.appendingPathComponent("shot.png")
            try? FileManager.default.copyItem(at: src, to: dest)
        }

        if let gltf {
            issues.append(contentsOf: gltfIssues(gltf))
        }
        writeText(issues.isEmpty ? "none\n" : issues.joined(separator: "\n") + "\n",
                  to: folder.appendingPathComponent("issues.txt"))
        QAShotLaunch.note("qa dump \(folder.lastPathComponent) status=\(status) issues=\(issues.count)")
    }

    private static let readme = """
        Per-file dump for a blank / partial / error render.

        README.txt            this list
        open.txt              load status, bounds, counts, shot source
        issues.txt            heuristics that usually explain black / missing / clipped
        convert-error.txt     thrown convert / load error (if any)
        convert-log.txt       GLBLog info/error lines for this file
        gltf.json             sanitized glTF JSON (data-URIs stripped)
        gltf-header.json      asset, extensions, buffer/image counts
        gltf-primitives.json  mode, attributes, material, Draco, morphs
        gltf-images.json      mimeType / uri kind / bufferView
        document.json         what our session kept after convert
        entity-tree.txt/.json RealityKit graph + materials + IBL / lights
        camera-fit.txt        near/far we would pick from mesh bounds
        host-look.json        IBL / hide / variant at capture time
        shot.png              copy of the QA PNG
        """

    private static func readGLTFJSON(from url: URL) -> [String: Any]? {
        do {
            if url.pathExtension.lowercased() == "gltf" {
                return try GLBBox.parseJSON(Data(contentsOf: url, options: [.mappedIfSafe]))
            }
            return try GLBBox.peekJSON(from: url)
        } catch {
            return nil
        }
    }

    private static func gltfHeader(_ json: [String: Any]) -> [String: Any] {
        [
            "asset": json["asset"] as Any,
            "scene": json["scene"] as Any,
            "scenes": (json["scenes"] as? [Any])?.count as Any,
            "nodes": (json["nodes"] as? [Any])?.count as Any,
            "meshes": (json["meshes"] as? [Any])?.count as Any,
            "materials": (json["materials"] as? [Any])?.count as Any,
            "textures": (json["textures"] as? [Any])?.count as Any,
            "images": (json["images"] as? [Any])?.count as Any,
            "accessors": (json["accessors"] as? [Any])?.count as Any,
            "buffers": json["buffers"] as Any,
            "skins": (json["skins"] as? [Any])?.count as Any,
            "animations": (json["animations"] as? [Any])?.count as Any,
            "cameras": (json["cameras"] as? [Any])?.count as Any,
            "extensionsUsed": json["extensionsUsed"] as Any,
            "extensionsRequired": json["extensionsRequired"] as Any,
        ]
    }

    private static func gltfIssues(_ json: [String: Any]) -> [String] {
        var issues: [String] = []
        let required = json["extensionsRequired"] as? [String] ?? []
        let used = json["extensionsUsed"] as? [String] ?? []
        let known = Set([
            "KHR_materials_unlit", "KHR_materials_clearcoat", "KHR_materials_sheen",
            "KHR_materials_variants", "KHR_lights_punctual", "KHR_texture_transform",
            "KHR_materials_emissive_strength", "KHR_draco_mesh_compression",
            "KHR_mesh_quantization", "EXT_mesh_gpu_instancing", "EXT_texture_webp",
            "KHR_materials_ior", "KHR_materials_specular", "KHR_materials_transmission",
            "KHR_materials_volume", "KHR_materials_iridescence",
            "KHR_materials_pbrSpecularGlossiness",
        ])
        for ext in required where !known.contains(ext) {
            issues.append("extensionsRequired unknown to our notes: \(ext)")
        }
        if required.contains("KHR_materials_transmission") || used.contains("KHR_materials_transmission") {
            issues.append("transmission / volume glass often looks opaque or invisible in RealityKit")
        }
        let materials = json["materials"] as? [[String: Any]] ?? []
        let blendMetal = materials.filter {
            ($0["alphaMode"] as? String) == "BLEND"
                && number(($0["pbrMetallicRoughness"] as? [String: Any])?["metallicFactor"]) == 1
        }
        if !blendMetal.isEmpty {
            issues.append("\(blendMetal.count) BLEND materials with metallicFactor=1 (host-invisible if texture alpha is empty)")
        }
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        var prims = 0
        var noPos = 0
        for mesh in meshes {
            for prim in mesh["primitives"] as? [[String: Any]] ?? [] {
                prims += 1
                let attrs = prim["attributes"] as? [String: Any] ?? [:]
                if attrs["POSITION"] == nil { noPos += 1 }
            }
        }
        if noPos > 0 { issues.append("\(noPos)/\(prims) primitives have no POSITION") }
        if required.contains("KHR_draco_mesh_compression") || used.contains("KHR_draco_mesh_compression") {
            issues.append("Draco mesh compression — convert fails if the decompressor drops the primitive")
        }
        if (json["skins"] as? [Any])?.isEmpty == false {
            issues.append("has skins — T-pose / missing joints look like a broken mesh")
        }
        return issues
    }

    private static func gltfPrimitives(_ json: [String: Any]) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        for (mi, mesh) in meshes.enumerated() {
            for (pi, prim) in (mesh["primitives"] as? [[String: Any]] ?? []).enumerated() {
                let attrs = prim["attributes"] as? [String: Any] ?? [:]
                let ext = prim["extensions"] as? [String: Any] ?? [:]
                rows.append([
                    "mesh": mi,
                    "prim": pi,
                    "name": mesh["name"] as Any,
                    "mode": prim["mode"] as Any,
                    "material": prim["material"] as Any,
                    "attributes": Array(attrs.keys).sorted(),
                    "targets": (prim["targets"] as? [Any])?.count as Any,
                    "draco": ext["KHR_draco_mesh_compression"] != nil,
                    "gpuInstancing": ext["EXT_mesh_gpu_instancing"] != nil,
                    "extensions": Array(ext.keys).sorted(),
                ])
            }
        }
        return rows
    }

    private static func gltfImages(_ json: [String: Any]) -> [[String: Any]] {
        (json["images"] as? [[String: Any]] ?? []).enumerated().map { index, image in
            let uri = image["uri"] as? String
            return [
                "index": index,
                "name": image["name"] as Any,
                "mimeType": image["mimeType"] as Any,
                "bufferView": image["bufferView"] as Any,
                "uriKind": uri.map { $0.hasPrefix("data:") ? "data-uri" : "file" } as Any,
                "uriChars": uri?.count as Any,
            ]
        }
    }

    @MainActor
    private static func collectIssues(model: GLBEntityLoader.LoadedModel, gltf: [String: Any]?) -> [String] {
        var issues: [String] = []
        let bounds = GLBPreviewCamera.modelBounds(of: model.entity)
        let extent = bounds.max - bounds.min
        if bounds.isEmpty || !extent.x.isFinite {
            issues.append("modelBounds empty or non-finite")
        }
        let longest = max(extent.x, max(extent.y, extent.z))
        if longest > 500 { issues.append("huge world extent \(fmt(extent)) — default far clip used to eat this") }
        if longest > 0, longest < 0.001 { issues.append("tiny world extent \(fmt(extent))") }

        var models = 0
        var disabledModels = 0
        var zeroScale = 0
        var noMats = 0
        var unlit = 0
        var iblReceivers = 0
        func walk(_ entity: Entity) {
            if entity.scale.x == 0 || entity.scale.y == 0 || entity.scale.z == 0 { zeroScale += 1 }
            if entity.components.has(ImageBasedLightReceiverComponent.self) { iblReceivers += 1 }
            if let model = entity.components[ModelComponent.self] {
                models += 1
                if !entity.isEnabled { disabledModels += 1 }
                if model.materials.isEmpty { noMats += 1 }
                if model.materials.contains(where: { $0 is UnlitMaterial }) { unlit += 1 }
            }
            for child in entity.children { walk(child) }
        }
        walk(model.entity)
        if models == 0 { issues.append("RealityKit tree has zero ModelComponents") }
        if disabledModels > 0 { issues.append("\(disabledModels) disabled ModelComponents") }
        if zeroScale > 0 { issues.append("\(zeroScale) entities with a 0 scale axis") }
        if noMats > 0 { issues.append("\(noMats) ModelComponents with no materials") }
        if unlit > 0 { issues.append("\(unlit) unlit materials — IBL receivers on these used to go black") }
        if iblReceivers == 0, models > 0 {
            issues.append("no ImageBasedLightReceiverComponent on the tree (PBR will be black without punctual lights)")
        }
        if model.entity.availableAnimations.isEmpty, !model.document.animations.isEmpty {
            issues.append("document has animations but entity.availableAnimations is empty")
        }
        return issues
    }

    @MainActor
    private static func openSummary(
        url: URL,
        status: String,
        model: GLBEntityLoader.LoadedModel?,
        loadError: String?,
        shotName: String,
        shotSource: String,
        shotBytes: Int
    ) -> String {
        var lines = [
            "status=\(status)",
            "file=\(url.path)",
            "bytes=\((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)",
            "shot=\(shotName) source=\(shotSource) shotBytes=\(shotBytes)",
        ]
        if let loadError { lines.append("convertError=\(loadError)") }
        if let model {
            let bounds = GLBPreviewCamera.modelBounds(of: model.entity)
            let extent = bounds.max - bounds.min
            lines += [
                "meshes=\(model.document.meshes.count) nodes=\(model.document.nodes.count)",
                "lights=\(model.document.lights.count) cameras=\(model.document.cameras.count)",
                "materials=\(model.document.materials.count) animations=\(model.document.animations.count)",
                "variants=\(model.document.variants.count)",
                "rkAnimations=\(model.entity.availableAnimations.count)",
                "visualBounds min=\(fmt(bounds.min)) max=\(fmt(bounds.max))",
                "extent=\(fmt(extent)) empty=\(bounds.isEmpty)",
                "stats=\(model.stats.previewLines.joined(separator: " | "))",
            ]
        } else {
            lines.append("LoadedModel=nil")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func documentJSON(_ document: GLTFSessionDocument) -> [String: Any] {
        [
            "defaultSceneIndex": document.defaultSceneIndex,
            "scenes": document.scenes.map { ["name": $0.name, "roots": $0.rootNodeIndices] },
            "nodes": document.nodes.map {
                [
                    "index": $0.index,
                    "name": $0.name,
                    "children": $0.children,
                    "mesh": $0.meshIndex as Any,
                    "camera": $0.cameraIndex as Any,
                    "light": $0.lightIndex as Any,
                    "translation": [$0.translation.x, $0.translation.y, $0.translation.z],
                    "rotation": [$0.rotation.x, $0.rotation.y, $0.rotation.z, $0.rotation.w],
                    "scale": [$0.scale.x, $0.scale.y, $0.scale.z],
                ]
            },
            "meshes": document.meshes.map {
                [
                    "name": $0.name,
                    "primitives": $0.primitiveCount,
                    "triangles": $0.triangleCount,
                    "vertices": $0.vertexCount,
                    "materials": $0.materialIndices,
                ]
            },
            "materials": document.materials.map {
                [
                    "name": $0.name,
                    "baseColor": [$0.baseColorFactor.x, $0.baseColorFactor.y, $0.baseColorFactor.z, $0.baseColorFactor.w],
                    "metallic": $0.metallicFactor,
                    "roughness": $0.roughnessFactor,
                    "emissive": [$0.emissiveFactor.x, $0.emissiveFactor.y, $0.emissiveFactor.z],
                    "alphaMode": $0.alphaMode,
                    "texBaseColor": $0.hasBaseColorTexture,
                    "texMR": $0.hasMetallicRoughnessTexture,
                    "texNormal": $0.hasNormalTexture,
                    "texOcclusion": $0.hasOcclusionTexture,
                    "texEmissive": $0.hasEmissiveTexture,
                ]
            },
            "lights": document.lights.map {
                [
                    "name": $0.name,
                    "type": $0.type,
                    "color": [$0.color.x, $0.color.y, $0.color.z],
                    "intensity": $0.intensity,
                ]
            },
            "cameras": document.cameras.map { ["name": $0.name, "type": $0.type] },
            "animations": document.animations.map { ["name": $0.name, "duration": $0.duration] },
            "variants": document.variants.map { ["name": $0.name, "mapping": $0.mapping] },
        ]
    }

    @MainActor
    private static func entityTree(_ entity: Entity, indent: String = "") -> String {
        var line = "\(indent)- name=\(entity.name.isEmpty ? "(anon)" : entity.name)"
        line += " enabled=\(entity.isEnabled)"
        line += " children=\(entity.children.count)"
        line += " pos=\(fmt(entity.position)) scale=\(fmt(entity.scale))"
        if let id = entity.components[GLTFNodeIDComponent.self]?.nodeIndex {
            line += " nodeId=\(id)"
        }
        if entity.components.has(ImageBasedLightReceiverComponent.self) { line += " iblReceiver" }
        if entity.components.has(ImageBasedLightComponent.self) { line += " iblLight" }
        if entity.components.has(PointLightComponent.self) { line += " pointLight" }
        if entity.components.has(SpotLightComponent.self) { line += " spotLight" }
        if entity.components.has(DirectionalLightComponent.self) { line += " dirLight" }
        if entity.components.has(PerspectiveCameraComponent.self) { line += " camera" }
        if let model = entity.components[ModelComponent.self] {
            line += " model mats=\(model.materials.count)"
            for (i, material) in model.materials.enumerated() {
                line += "\n\(indent)    mat[\(i)] \(describe(material))"
            }
        }
        var text = line + "\n"
        for child in entity.children {
            text += entityTree(child, indent: indent + "  ")
        }
        return text
    }

    @MainActor
    private static func entityJSON(_ entity: Entity) -> [String: Any] {
        var node: [String: Any] = [
            "name": entity.name,
            "enabled": entity.isEnabled,
            "position": [entity.position.x, entity.position.y, entity.position.z],
            "scale": [entity.scale.x, entity.scale.y, entity.scale.z],
            "children": entity.children.map { entityJSON($0) },
        ]
        if let id = entity.components[GLTFNodeIDComponent.self]?.nodeIndex {
            node["nodeId"] = id
        }
        if let model = entity.components[ModelComponent.self] {
            node["model"] = [
                "materials": model.materials.map(describe),
            ]
        }
        var flags: [String] = []
        if entity.components.has(ImageBasedLightReceiverComponent.self) { flags.append("iblReceiver") }
        if entity.components.has(ImageBasedLightComponent.self) { flags.append("iblLight") }
        if entity.components.has(PointLightComponent.self) { flags.append("pointLight") }
        if entity.components.has(SpotLightComponent.self) { flags.append("spotLight") }
        if entity.components.has(DirectionalLightComponent.self) { flags.append("dirLight") }
        if entity.components.has(PerspectiveCameraComponent.self) { flags.append("camera") }
        if !flags.isEmpty { node["flags"] = flags }
        return node
    }

    private static func describe(_ material: RealityKit.Material) -> String {
        switch material {
        case let pbr as PhysicallyBasedMaterial:
            return "PBR metal=\(pbr.metallic.scale) rough=\(pbr.roughness.scale) blend=\(String(describing: pbr.blending)) cull=\(String(describing: pbr.faceCulling)) baseTex=\(pbr.baseColor.texture != nil)"
        case let unlit as UnlitMaterial:
            return "Unlit blend=\(String(describing: unlit.blending)) tex=\(unlit.color.texture != nil)"
        case let simple as SimpleMaterial:
            return "Simple \(String(describing: simple.roughness))"
        default:
            return String(describing: type(of: material))
        }
    }

    private static func sanitize(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues(sanitize)
        case let array as [Any]:
            return array.map(sanitize)
        case let string as String where string.hasPrefix("data:"):
            return "[data-uri chars=\(string.count)]"
        default:
            return value
        }
    }

    private static func writeJSON(_ object: Any, to url: URL) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            writeText("invalid json object\n", to: url)
            return
        }
        try? data.write(to: url)
    }

    private static func writeText(_ text: String, to url: URL) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func cameraFit(_ entity: Entity) -> String {
        let bounds = GLBPreviewCamera.modelBounds(of: entity)
        let extent = bounds.max - bounds.min
        let center = (bounds.min + bounds.max) * 0.5
        let pad: Float = GLBPreviewCamera.previewFitPadding
        let radius = max(extent.x, max(extent.y, extent.z)) * 0.5 * pad
        let distance = max(radius / tanf(.pi / 180 * 17.5), 0.001)
        var camera = PerspectiveCameraComponent()
        GLBPreviewCamera.applyFitClip(to: &camera, eye: center + SIMD3(0, 0, distance), target: center)
        return """
            bounds min=\(fmt(bounds.min)) max=\(fmt(bounds.max))
            extent=\(fmt(extent)) empty=\(bounds.isEmpty)
            estimatedDistance=\(distance)
            near=\(camera.near) far=\(camera.far)
            """
    }

    @MainActor
    private static func sessionJSON(_ session: HostSidebarModel?) -> [String: Any] {
        guard let session else { return ["session": "nil"] }
        return [
            "hide": Array(session.hide).sorted(),
            "soloRoot": session.soloRoot as Any,
            "debug": session.debug.rawValue,
            "activeSceneIndex": session.activeSceneIndex,
            "look": [
                "useEnvironmentMap": AppLook.current.useEnvironmentMap,
                "catalog": AppLook.current.catalogRaw,
                "customFileName": AppLook.current.customFileName as Any,
            ],
        ]
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    private static func fmt(_ v: SIMD3<Float>) -> String {
        String(format: "%.4g,%.4g,%.4g", v.x, v.y, v.z)
    }
}
