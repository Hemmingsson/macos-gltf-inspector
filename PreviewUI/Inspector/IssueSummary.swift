/// "1 error · 2 warnings · 3 notes" — only the counts that are non-zero.
func issueSummary(errors: Int, warnings: Int, notes: Int = 0) -> String {
    var parts: [String] = []
    if errors > 0 { parts.append(errors == 1 ? "1 error" : "\(errors) errors") }
    if warnings > 0 { parts.append(warnings == 1 ? "1 warning" : "\(warnings) warnings") }
    if notes > 0 { parts.append(notes == 1 ? "1 note" : "\(notes) notes") }
    return parts.isEmpty ? "No issues" : parts.joined(separator: " · ")
}
