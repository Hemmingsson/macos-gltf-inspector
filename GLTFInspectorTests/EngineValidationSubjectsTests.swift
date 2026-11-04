import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import Testing

/// Validator findings land on the outliner rows they are about, and the inspector reads them back
/// per selection.
struct EngineValidationSubjectsTests {
    private let document = GLTFDocumentJSON.makeDocument(json: [
        "scenes": [["nodes": [0]]],
        "nodes": [["mesh": 0]],
        "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
        "materials": [["pbrMetallicRoughness": ["baseColorTexture": ["index": 0]]]],
        "textures": [["source": 0]],
        "images": [["uri": "a.png"]],
    ])

    private func report(_ messages: [GLTFValidationIssue]) -> GLTFValidationState {
        .success(GLTFValidationReport(
            validatorVersion: "test",
            errorCount: messages.filter(\.isError).count,
            warningCount: messages.filter(\.isWarning).count,
            messages: messages
        ))
    }

    @Test func issuesResolveToTheRowsTheyAreAbout() throws {
        let tangent = GLTFValidationIssue(
            code: "MESH_PRIMITIVE_GENERATED_TANGENT_SPACE",
            message: "Material requires a tangent space…",
            severity: 1,
            pointer: "/meshes/0/primitives/0"
        )
        let npot = GLTFValidationIssue(
            code: "IMAGE_NPOT_DIMENSIONS",
            message: "Image has non-power-of-two dimensions: 1024x576.",
            severity: 3,
            pointer: "/images/0"
        )
        let accessor = GLTFValidationIssue(
            code: "ACCESSOR_NOTE",
            message: "Accessor note",
            severity: 2,
            pointer: "/accessors/0"
        )
        let result = EngineSceneModel.mapValidation(report([tangent, npot, accessor]), document: document)

        let mesh = NodeID(kind: .mesh, index: 0)
        let material = NodeID(kind: .material, index: 0)

        // The material shows both, faults first. The mesh node shows only the tangent warning.
        #expect(result.issues(for: material).map(\.severity) == [.warning, .hint])
        #expect(result.issues(for: mesh).map(\.severity) == [.warning])
        // An accessor has no row, so it stays in the file-wide list only.
        #expect(result.issues.count == 3)
        #expect(result.issues.last?.subjects.isEmpty == true)

        #expect(result.worstSeverity(for: material) == .warning)
        #expect(result.worstSeverity(for: NodeID(kind: .scene, index: 0)) == nil)
        // The header counts warnings and notes apart.
        #expect(result.warningCount == 1)
        #expect(result.noteCount == 2)
    }

    @Test func summaryCountsOnlyWhatIsPresent() {
        #expect(issueSummary(errors: 0, warnings: 2, notes: 0) == "2 warnings")
        #expect(issueSummary(errors: 1, warnings: 0, notes: 1) == "1 error · 1 note")
        #expect(issueSummary(errors: 2, warnings: 1, notes: 3) == "2 errors · 1 warning · 3 notes")
    }
}
