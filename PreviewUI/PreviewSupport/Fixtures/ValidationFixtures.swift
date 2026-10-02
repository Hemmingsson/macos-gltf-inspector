import Foundation

/// Static glTF-validator snapshots for section previews — no disk I/O.
enum ValidationFixtures {
  static let clean = ValidationResult(
    issues: [],
    formatLabel: "glTF 2.0",
    status: .ready
  )

  static let pending = ValidationResult(
    issues: [],
    formatLabel: "glTF 2.0",
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
    formatLabel: "glTF 2.0",
    status: .ready
  )

  static let convertProblems = ConvertProblemList(
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
