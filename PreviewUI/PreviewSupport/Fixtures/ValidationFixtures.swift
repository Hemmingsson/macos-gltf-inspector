import Foundation

/// Static glTF-validator snapshots for section previews — no disk I/O.
enum ValidationFixtures {
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
}
