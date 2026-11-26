import Foundation
@testable import GLTFInspector
import Testing

struct ValidationIssueGroupingTests {
    private func issue(
        _ severity: ValidationResult.Issue.Severity,
        _ message: String,
        code: String = "",
        pointer: String? = nil
    ) -> ValidationResult.Issue {
        ValidationResult.Issue(severity: severity, message: message, code: code, pointer: pointer)
    }

    @Test func groupingCollapsesIdenticalMessages() {
        let bufferMessage = "Buffer view has no target defined."
        let issues = [
            issue(.warning, bufferMessage, code: "BUFFER_VIEW_TARGET_MISSING", pointer: "/bufferViews/0"),
            issue(.warning, bufferMessage, code: "BUFFER_VIEW_TARGET_MISSING", pointer: "/bufferViews/1"),
            issue(.warning, bufferMessage, code: "BUFFER_VIEW_TARGET_MISSING", pointer: "/bufferViews/2"),
            issue(.hint, "Unused object."),
            issue(.error, "Unresolved mesh.", code: "UNRESOLVED_REFERENCE"),
        ]
        let groups = ValidationIssueGrouping.group(issues)
        #expect(groups.map(\.severity) == [.error, .warning, .hint])
        #expect(groups.map(\.count) == [1, 3, 1])
        #expect(groups[1].summaryLine.hasSuffix("(×3)"))
        #expect(groups[1].detailText == bufferMessage)
        #expect(!groups[1].detailText.contains("×"))
        #expect(groups[1].skim == "Buffer view has no target (vertex/index).")
        #expect(groups[0].summaryLine == "Points at a missing mesh/object.")
        #expect(!groups[0].showsDetailBelowSkim)
    }

    @Test func longMessagesSplitShortSummaryFromFullDetail() {
        let long = "Material requires a tangent space but the mesh primitive does not provide it. Runtime-generated tangent space may be non-portable across implementations."
        let group = GroupedValidationIssue(
            severity: .warning,
            code: "MESH_PRIMITIVE_GENERATED_TANGENT_SPACE",
            message: long,
            count: 4
        )
        #expect(group.summaryLine == "Mesh is missing tangents this material needs. (×4)")
        #expect(group.detailText == long)
        #expect(!group.detailText.hasSuffix("(×4)"))
        #expect(group.showsDetailBelowSkim)
    }

    @Test func copyMapUsesKhronosSkimForKnownCodes() {
        let skinned = "Node with a skinned mesh is not root. Parent transforms will not affect a skinned mesh."
        #expect(ValidationIssueCopy.skim(code: "NODE_SKINNED_MESH_NON_ROOT", message: skinned) ==
            "Skinned mesh isn’t at the root — parent transforms won’t apply.")
        #expect(ValidationIssueCopy.skim(code: "UNKNOWN_CODE", message: skinned) == skinned)
    }

    @Test func skinnedMeshGroupCollapsesSkimAndDetailToOneLine() {
        let skinned = "Node with a skinned mesh is not root. Parent transforms will not affect a skinned mesh."
        let group = GroupedValidationIssue(
            severity: .warning,
            code: "NODE_SKINNED_MESH_NON_ROOT",
            message: skinned,
            count: 1
        )
        #expect(!group.showsDetailBelowSkim)
        #expect(group.summaryLine == "Skinned mesh isn’t at the root — parent transforms won’t apply.")
    }
}