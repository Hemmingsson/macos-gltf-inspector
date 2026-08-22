import Foundation

/// What our prepare/convert pipeline did to this file (inspector honesty).
/// Flags are set while transforms run — not re-inferred from post-prepare JSON
/// (those extensions are stripped).
struct PreparePipelineReport: Equatable, Sendable {
    var dequantized = false
    var webpToPng = false
    var gpuInstancesExpanded = false
    var specGlossToMetalRough = false
    var bakedSpecGlossTextures = false
    var droppedBakedEmissive = false
    var dimmedStudioIBL = false
    var decompressedDraco = false
    /// Source `extensionsUsed` captured before prepare rewrites strip them.
    var extensionsUsed: [String] = []

    var isEmpty: Bool {
        !(dequantized || webpToPng || gpuInstancesExpanded || specGlossToMetalRough
            || bakedSpecGlossTextures || droppedBakedEmissive || dimmedStudioIBL
            || decompressedDraco)
    }

    /// Host sidebar shows transform honesty and/or source extensions.
    var showsInSidebar: Bool { !entries.isEmpty || !extensionEntries.isEmpty }

    /// Sidebar / Inspect-mock style lines.
    var entries: [String] {
        var lines: [String] = []
        if specGlossToMetalRough {
            lines.append(
                bakedSpecGlossTextures
                    ? "Converted from KHR spec-gloss (baked textures)"
                    : "Converted from KHR spec-gloss"
            )
        }
        if dequantized { lines.append("Dequantized mesh (KHR_mesh_quant.)") }
        if webpToPng { lines.append("Converted WebP textures → PNG") }
        if gpuInstancesExpanded { lines.append("Expanded GPU instances") }
        if decompressedDraco { lines.append("Decompressed Draco meshes") }
        if droppedBakedEmissive { lines.append("Dropped baked / boost emissive") }
        lines.append(
            dimmedStudioIBL
                ? "File lights: on · Studio IBL: dimmed"
                : "File lights: off · Studio IBL: on"
        )
        return lines
    }

    /// Throwaway "what's in this file" list. Same source as prepare gates.
    var extensionEntries: [String] { extensionsUsed }

    static func captureExtensions(from json: [String: Any]) -> [String] {
        Array(Set(stringArray(json, key: "extensionsUsed"))).sorted()
    }

    static func sourceHadDraco(_ json: [String: Any]) -> Bool {
        let name = "KHR_draco_mesh_compression"
        return stringArray(json, key: "extensionsUsed").contains(name)
            || stringArray(json, key: "extensionsRequired").contains(name)
    }

    private static func stringArray(_ json: [String: Any], key: String) -> [String] {
        (json[key] as? [String]) ?? []
    }
}
