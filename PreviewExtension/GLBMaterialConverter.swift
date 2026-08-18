import Foundation

enum GLBMaterialConverter {
    /// model-viewer does not apply KHR_materials_pbrSpecularGlossiness.
    /// Rewrite those materials to metallic-roughness so diffuse maps show.
    static func prepareForWebPreview(_ data: Data) -> Data {
        guard data.count >= 20, data.prefix(4) == Data("glTF".utf8) else { return data }

        let jsonLength = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
        let jsonType = data.subdata(in: 16..<20)
        guard jsonType == Data("JSON".utf8) else { return data }

        let jsonStart = 20
        let jsonEnd = jsonStart + Int(jsonLength)
        guard jsonEnd <= data.count else { return data }

        guard var root = try? JSONSerialization.jsonObject(with: data.subdata(in: jsonStart..<jsonEnd)) as? [String: Any] else {
            return data
        }

        var materials = root["materials"] as? [[String: Any]] ?? []
        var converted = false
        for i in materials.indices {
            var material = materials[i]
            guard var extensions = material["extensions"] as? [String: Any],
                  let specGloss = extensions["KHR_materials_pbrSpecularGlossiness"] as? [String: Any] else {
                continue
            }

            var pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            if let diffuseTexture = specGloss["diffuseTexture"] {
                pbr["baseColorTexture"] = diffuseTexture
            }
            if let diffuseFactor = specGloss["diffuseFactor"] {
                pbr["baseColorFactor"] = diffuseFactor
            }
            if let gloss = specGloss["glossinessFactor"] as? Double {
                pbr["roughnessFactor"] = max(0, min(1, 1 - gloss))
            } else {
                pbr["roughnessFactor"] = 0
            }
            pbr["metallicFactor"] = 0
            material["pbrMetallicRoughness"] = pbr

            extensions.removeValue(forKey: "KHR_materials_pbrSpecularGlossiness")
            if extensions.isEmpty {
                material.removeValue(forKey: "extensions")
            } else {
                material["extensions"] = extensions
            }
            materials[i] = material
            converted = true
        }

        guard converted else { return data }

        root["materials"] = materials
        if var used = root["extensionsUsed"] as? [String] {
            used.removeAll { $0 == "KHR_materials_pbrSpecularGlossiness" }
            if used.isEmpty { root.removeValue(forKey: "extensionsUsed") } else { root["extensionsUsed"] = used }
        }
        if var required = root["extensionsRequired"] as? [String] {
            required.removeAll { $0 == "KHR_materials_pbrSpecularGlossiness" }
            if required.isEmpty { root.removeValue(forKey: "extensionsRequired") } else { root["extensionsRequired"] = required }
        }

        guard var jsonData = try? JSONSerialization.data(withJSONObject: root, options: []) else { return data }
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }

        let binStart = jsonEnd
        let rest = data.subdata(in: binStart..<data.count)

        var out = Data()
        out.append(Data("glTF".utf8))
        out.append(contentsOf: withUnsafeBytes(of: UInt32(2)) { Data($0) })
        let total = 12 + 8 + jsonData.count + rest.count
        out.append(contentsOf: withUnsafeBytes(of: UInt32(total)) { Data($0) })
        out.append(contentsOf: withUnsafeBytes(of: UInt32(jsonData.count)) { Data($0) })
        out.append(Data("JSON".utf8))
        out.append(jsonData)
        out.append(rest)
        return out
    }
}
