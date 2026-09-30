import Foundation
import GLTFCore

/// Convert/render losses — “did we drop or fake something?”, not Khronos spec validity.
public struct ConvertProblem: Equatable, Sendable {
    public enum Code: String, Equatable, Sendable {
        case missingTexture
        case defaultMaterial
        case droppedPrimitive
        case missingTexCoord
        case ignoredExtension
        case approximatedTransmission
        case forcedOpaqueBlend
        case blendAsCutout
    }

    public enum Severity: String, Equatable, Sendable {
        case error
        case warning
    }

    public var severity: Severity
    public var code: Code
    public var message: String
    public var materialName: String?
}

public struct ConvertProblemReport: Equatable, Sendable {
    public var items: [ConvertProblem] = []

    public init() {}

    var isEmpty: Bool { items.isEmpty }
    var errorCount: Int { items.filter { $0.severity == .error }.count }
    var warningCount: Int { items.filter { $0.severity == .warning }.count }

    /// Source `extensionsUsed` names we do not honor in RealityKit convert.
    static let ignoredExtensions: Set<String> = [
        "KHR_materials_volume",
        "KHR_materials_iridescence",
        "KHR_materials_anisotropy",
        "KHR_materials_dispersion",
        "KHR_materials_diffuse_transmission",
    ]

    mutating func append(
        _ code: ConvertProblem.Code,
        severity: ConvertProblem.Severity,
        message: String,
        materialName: String? = nil
    ) {
        let problem = ConvertProblem(
            severity: severity,
            code: code,
            message: message,
            materialName: materialName
        )
        if items.contains(problem) { return }
        items.append(problem)
        let material = materialName.map { " material='\($0)'" } ?? ""
        let line = "convert problem: code=\(code.rawValue) severity=\(severity.rawValue)\(material)"
        if severity == .error {
            AppLog.error(AppLog.load, line)
        } else {
            AppLog.info(AppLog.load, line)
        }
    }

    func mergingIgnoredExtensions(from used: [String]) -> ConvertProblemReport {
        var copy = self
        for name in used where Self.ignoredExtensions.contains(name) {
            copy.append(
                .ignoredExtension,
                severity: .warning,
                message: "\(name) is not rendered"
            )
        }
        return copy
    }

    public var hostSummary: String {
        if isEmpty { return "open convert-problems none" }
        return "open convert-problems errors=\(errorCount) warnings=\(warningCount)"
    }
}
