import Foundation

/// Convert/render losses — “did we drop or fake something?”, not Khronos spec validity.
struct ConvertProblem: Equatable, Sendable {
    enum Code: String, Equatable, Sendable {
        case missingTexture
        case defaultMaterial
        case droppedPrimitive
        case missingTexCoord
        case ignoredExtension
        case approximatedTransmission
        case forcedOpaqueBlend
    }

    enum Severity: String, Equatable, Sendable {
        case error
        case warning
    }

    var severity: Severity
    var code: Code
    var message: String
    var materialName: String?
}

struct ConvertProblemReport: Equatable, Sendable {
    var items: [ConvertProblem] = []

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

    var hostSummary: String {
        if isEmpty { return "open convert-problems none" }
        return "open convert-problems errors=\(errorCount) warnings=\(warningCount)"
    }
}
