/// "N errors · M warnings" title for the validation and convert-problem cards.
func issueSummary(errors: Int, warnings: Int) -> String {
    if errors > 0 && warnings > 0 {
        return "\(errors) errors · \(warnings) warnings"
    }
    if errors > 0 {
        return errors == 1 ? "1 error" : "\(errors) errors"
    }
    return warnings == 1 ? "1 warning" : "\(warnings) warnings"
}
