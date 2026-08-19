import Foundation

/// Cheap glTF JSON stats for the in-viewer overlay. JSON chunk only — no BIN.
struct GLBPreviewStats: Equatable {
    let meshCount: Int
    let materialCount: Int
    let animationCount: Int
    let nodeCount: Int
    let textureCount: Int
    let durationSeconds: Double?

    static func from(json: [String: Any]) -> GLBPreviewStats {
        let animations = json["animations"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        return GLBPreviewStats(
            meshCount: arrayCount(json["meshes"]),
            materialCount: arrayCount(json["materials"]),
            animationCount: animations.count,
            nodeCount: arrayCount(json["nodes"]),
            textureCount: arrayCount(json["textures"]),
            durationSeconds: maxAnimationDuration(animations: animations, accessors: accessors)
        )
    }

    /// Non-zero counts only — for the preview corner list.
    var previewLines: [String] {
        previewRows
    }

    /// Same rows as `previewLines`; host outliner Model block uses this name.
    var previewRows: [String] {
        var lines: [String] = []
        if meshCount > 0 { lines.append("Meshes \(meshCount)") }
        if materialCount > 0 { lines.append("Materials \(materialCount)") }
        if animationCount > 0 { lines.append("Animations \(animationCount)") }
        if nodeCount > 0 { lines.append("Nodes \(nodeCount)") }
        if textureCount > 0 { lines.append("Textures \(textureCount)") }
        if let durationSeconds, durationSeconds > 0 {
            lines.append(String(format: "%.2fs", durationSeconds))
        }
        return lines
    }

    private static func arrayCount(_ value: Any?) -> Int {
        (value as? [Any])?.count ?? 0
    }

    /// Longest animation end time from sampler TIME accessor `max` when present.
    private static func maxAnimationDuration(
        animations: [[String: Any]],
        accessors: [[String: Any]]
    ) -> Double? {
        var duration: Double?
        for animation in animations {
            let samplers = animation["samplers"] as? [[String: Any]] ?? []
            for sampler in samplers {
                guard let index = GLBBox.intValue(sampler["input"]),
                      accessors.indices.contains(index),
                      let maxValues = accessors[index]["max"] as? [Any],
                      let end = GLBBox.doubleValue(maxValues.first)
                else { continue }
                duration = max(duration ?? end, end)
            }
        }
        return duration
    }
}
