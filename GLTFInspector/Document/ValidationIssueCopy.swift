import Foundation

/// Deterministic one-line skims for Khronos validator codes. Detail text always stays the
/// original `message` from the report — never invented here.
enum ValidationIssueCopy {
    static func skim(code: String, message: String) -> String {
        switch code {
        case "EMPTY_ENTITY":
            return "This part of the file is empty where data is required."
        case "UNRESOLVED_REFERENCE":
            if let range = message.range(of: #"\d+"#, options: .regularExpression) {
                return "Points at a missing mesh/object (\(message[range]))."
            }
            return "Points at a missing mesh/object."
        case "MESH_PRIMITIVE_GENERATED_TANGENT_SPACE":
            return "Mesh is missing tangents this material needs."
        case "NODE_SKINNED_MESH_NON_ROOT":
            return "Skinned mesh isn’t at the root — parent transforms won’t apply."
        case "UNUSED_MESH_TANGENT":
            return "Tangents aren’t used (no normal map)."
        case "NODE_EMPTY":
            return "Empty node (no mesh, camera, light, or children)."
        case "BUFFER_VIEW_TARGET_MISSING":
            return "Buffer view has no target (vertex/index)."
        default:
            return message
        }
    }

    private static let mappedCodes: Set<String> = [
        "EMPTY_ENTITY",
        "UNRESOLVED_REFERENCE",
        "MESH_PRIMITIVE_GENERATED_TANGENT_SPACE",
        "NODE_SKINNED_MESH_NON_ROOT",
        "UNUSED_MESH_TANGENT",
        "NODE_EMPTY",
        "BUFFER_VIEW_TARGET_MISSING",
    ]

    /// Khronos messages that carry a second sentence worth showing under the UX skim.
    private static let codesWithExpandableDetail: Set<String> = [
        "MESH_PRIMITIVE_GENERATED_TANGENT_SPACE",
    ]

    static func hasMappedSkim(code: String) -> Bool { mappedCodes.contains(code) }

    /// True when the full Khronos message adds information beyond the skim line.
    static func detailAddsBeyondSkim(skim: String, message: String, code: String) -> Bool {
        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = skim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return false }
        if head == detail { return false }
        if detail.hasPrefix(head) { return false }
        if head.hasPrefix(detail) { return false }
        if hasMappedSkim(code: code) {
            return codesWithExpandableDetail.contains(code)
        }
        let sentences = detail.split(separator: ".", omittingEmptySubsequences: true)
        return sentences.count > 1
    }
}