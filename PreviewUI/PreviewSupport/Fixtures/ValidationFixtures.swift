import Foundation

/// Static glTF-validator snapshots for section previews — no disk I/O.
public enum ValidationFixtures {
  static let clean = ValidationResult(
    issues: [],
    status: .ready
  )

  static let pending = ValidationResult(
    issues: [],
    status: .pending
  )

  static let withErrors = ValidationResult(
    issues: [
      ValidationResult.Issue(
        severity: .error,
        message: "Mesh primitive missing required POSITION attribute",
        pointer: "/meshes/0/primitives/0/attributes"
      ),
      ValidationResult.Issue(
        severity: .warning,
        message: "Normal vectors are not unit length",
        pointer: "/meshes/0/primitives/0/attributes/NORMAL"
      )
    ],
    status: .ready
  )

  /// The same findings as a file-wide report, for previews that resolve them per selection.
  public static var materialReport: ValidationResult {
    ValidationResult(issues: materialIssues, status: .ready)
  }

  /// What a material with a missing-tangent warning and an NPOT texture shows inline.
  static let materialIssues = [
    ValidationResult.Issue(
      severity: .warning,
      message: "Material requires a tangent space but the mesh primitive does not provide it. Runtime-generated tangent space may be non-portable across implementations.",
      pointer: "/meshes/0/primitives/0",
      subjects: [NodeID(kind: .material, index: 0)]
    ),
    ValidationResult.Issue(
      severity: .info,
      message: "Image has non-power-of-two dimensions: 1024x576.",
      pointer: "/images/0",
      subjects: [NodeID(kind: .material, index: 0)]
    ),
  ]
}
