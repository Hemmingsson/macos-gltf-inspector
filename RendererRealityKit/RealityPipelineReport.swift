import Foundation

/// What convert and the RealityKit policy did to this file (inspector honesty): spec-gloss
/// conversion, Draco, the baked-emissive drop and the studio dim. Read from the authored JSON
/// plus the convert-time results; there is no rewritten file any more.
public struct RealityPipelineReport: Equatable, Sendable {
    var specGlossToMetalRough = false
    var bakedSpecGlossTextures = false
    var droppedBakedEmissive = false
    var dimmedStudioIBL = false
    var decompressedDraco = false
    /// Source `extensionsUsed`.
    public internal(set) var extensionsUsed: [String] = []

    public init() {}

    /// Spec-gloss, Draco, and the baked-emissive drop — everything except the studio-IBL line.
    public var conversionEntries: [String] {
        var lines: [String] = []
        if specGlossToMetalRough {
            lines.append(
                bakedSpecGlossTextures
                    ? "Converted from KHR spec-gloss (baked textures)"
                    : "Converted from KHR spec-gloss"
            )
        }
        if decompressedDraco { lines.append("Decompressed Draco meshes") }
        if droppedBakedEmissive { lines.append("Dropped baked / boost emissive") }
        return lines
    }

    /// Studio dim vs full IBL. Always present so the host can tag it `.lighting`.
    public var lightingEntry: String {
        dimmedStudioIBL
            ? "File lights: on · Studio IBL: dimmed"
            : "File lights: off · Studio IBL: on"
    }

    /// Sidebar / Inspect-mock style lines.
    public var entries: [String] {
        conversionEntries + [lightingEntry]
    }

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
