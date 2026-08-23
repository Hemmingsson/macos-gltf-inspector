import Foundation

/// Static glTF-validator snapshots for section previews — no disk I/O.
public enum ValidationFixtures {
  public static let clean = ValidationResult(
    issues: [],
    formatLabel: "glTF 2.0",
    status: .ready
  )

  public static let pending = ValidationResult(
    issues: [],
    formatLabel: "glTF 2.0",
    status: .pending
  )

  public static let unavailable = ValidationResult(
    issues: [
      ValidationResult.Issue(
        severity: .warning,
        message: "Validation unavailable: offline preview fixture"
      )
    ],
    formatLabel: "glTF 2.0",
    status: .unavailable
  )

  public static let withWarnings = ValidationResult(
    issues: [
      ValidationResult.Issue(
        severity: .warning,
        message: "Material base color factor is out of recommended range",
        pointer: "/materials/0/pbrMetallicRoughness/baseColorFactor"
      ),
      ValidationResult.Issue(
        severity: .info,
        message: "Unused accessor",
        pointer: "/accessors/3"
      )
    ],
    formatLabel: "glTF 2.0",
    status: .ready
  )

  public static let withErrors = ValidationResult(
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
    formatLabel: "glTF 2.0",
    status: .ready
  )

  public static let convertProblems = ConvertProblemList(
    entries: [
      ConvertProblemList.Entry(
        severity: .error,
        title: "Texture did not load",
        code: "missingTexture"
      ),
      ConvertProblemList.Entry(
        severity: .warning,
        title: "Ignored extension KHR_materials_iridescence",
        code: "ignoredExtension"
      )
    ]
  )
}
