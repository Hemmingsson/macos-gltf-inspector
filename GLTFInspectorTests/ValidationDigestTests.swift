import Foundation
@testable import GLTFInspector
import Testing

struct ValidationDigestTests {
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

    @Test func digestKeyIgnoresOrder() {
        let a = [
            issue(.warning, "A", code: "CODE_A", pointer: "/a"),
            issue(.error, "B", code: "CODE_B", pointer: "/b"),
        ]
        let b = [
            issue(.error, "B", code: "CODE_B", pointer: "/b"),
            issue(.warning, "A", code: "CODE_A", pointer: "/a"),
        ]
        #expect(ValidationIssueGrouping.digestKey(a) == ValidationIssueGrouping.digestKey(b))
        #expect(ValidationIssueGrouping.digestKey(a) != ValidationIssueGrouping.digestKey([issue(.warning, "A")]))
    }

    @Test func fallbackDigestBuildsCodableJSON() throws {
        let issues = [
            issue(.warning, "Same", pointer: "/0"),
            issue(.warning, "Same", pointer: "/1"),
            issue(.info, "Note"),
        ]
        let digest = ValidationDigest.fallback(from: issues)
        #expect(digest.isModelGenerated == false)
        #expect(digest.headline == "2 warnings · 1 note")
        #expect(digest.groups.count == 2)
        #expect(digest.groups[0].count == 2)

        let json = try digest.jsonString()
        #expect(json.contains("\"headline\""))
        #expect(json.contains("\"isModelGenerated\" : false"))
        #expect(json.contains("Same"))
    }

    @Test func promptIncludesGroupedFindings() {
        let groups = [
            GroupedValidationIssue(
                severity: .warning,
                code: "BUFFER_VIEW_TARGET_MISSING",
                message: "Buffer view has no target defined.",
                count: 5
            ),
        ]
        let prompt = ValidationIssueGrouping.prompt(
            groups: groups,
            errorCount: 0,
            warningCount: 5,
            noteCount: 0,
            scope: .file
        )
        #expect(prompt.contains("SCOPE: file"))
        #expect(prompt.contains("warning ×5: Buffer view has no target (vertex/index)."))
        #expect(prompt.contains("5 warnings"))
    }

    @Test @MainActor func storeUpgradesHeadlineFromModel() async throws {
        let store = ValidationDigestStore()
        store.summarize = { _ in "Five buffer views lack targets." }
        let bufferMessage = "Buffer view has no target defined."
        let issues = [
            issue(.warning, bufferMessage, code: "BUFFER_VIEW_TARGET_MISSING", pointer: "/bufferViews/0"),
            issue(.warning, bufferMessage, code: "BUFFER_VIEW_TARGET_MISSING", pointer: "/bufferViews/1"),
        ]
        store.request(issues, scope: .file)

        #expect(try await waitUntil(within: .seconds(2)) {
            store.modelHeadline(for: issues) == "Five buffer views lack targets."
        })
        let groups = ValidationIssueGrouping.group(issues)
        #expect(store.cardTitle(for: issues, groups: groups, fallback: "2 warnings") == "2 warnings")
        #expect(store.title(for: issues, fallback: "2 warnings") == "Five buffer views lack targets.")
        let digest = try #require(store.digest(for: issues))
        #expect(digest.isModelGenerated)
        #expect(digest.groups.count == 1)
        #expect(digest.groups[0].count == 2)
    }

    @Test @MainActor func storeKeepsFallbackWhenModelFails() async throws {
        let store = ValidationDigestStore()
        var calls = 0
        store.summarize = { _ in
            calls += 1
            throw ValidationDigestError.unavailable
        }
        let issues = [issue(.error, "Unresolved mesh.", code: "UNRESOLVED_REFERENCE")]
        store.request(issues, scope: .selection)

        #expect(try await waitUntil(within: .seconds(2)) { calls == 1 })
        store.request(issues, scope: .selection)
        try await Task.sleep(for: .milliseconds(30))
        #expect(calls == 1)
        #expect(store.modelHeadline(for: issues) == nil)
        #expect(store.title(for: issues, fallback: "1 error") == "1 error")
        #expect(store.digest(for: issues)?.isModelGenerated == false)
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

    @Test func redundantHeadlineDoesNotAddValue() {
        let skinned = "Node with a skinned mesh is not root. Parent transforms will not affect a skinned mesh."
        let groups = [
            GroupedValidationIssue(
                severity: .warning,
                code: "NODE_SKINNED_MESH_NON_ROOT",
                message: skinned,
                count: 1
            ),
        ]
        let truncated = "Node with a skinned mesh is not..."
        #expect(!ValidationIssueGrouping.headlineAddsValue(truncated, groups: groups))
        #expect(!ValidationIssueGrouping.headlineAddsValue(skinned, groups: groups))
    }

    @Test func multiGroupHeadlineCanAddValue() {
        let groups = [
            GroupedValidationIssue(severity: .error, code: "UNRESOLVED_REFERENCE", message: "Unresolved mesh.", count: 1),
            GroupedValidationIssue(
                severity: .warning,
                code: "BUFFER_VIEW_TARGET_MISSING",
                message: "Buffer view has no target defined.",
                count: 3
            ),
        ]
        #expect(ValidationIssueGrouping.headlineAddsValue("One error and three buffer-view warnings.", groups: groups))
    }
}