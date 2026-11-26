import Foundation
import GLTFCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Typed digest of validation findings: AI headline when available, else the count summary.
/// Groups always come from deterministic collapse of the raw messages — never invented.
struct ValidationDigest: Sendable, Hashable, Codable {
    struct Group: Sendable, Hashable, Codable, Identifiable {
        var severity: String
        var code: String
        var message: String
        var count: Int

        var id: String { "\(severity)|\(code)|\(message)" }
    }

    /// One sentence for the card / inspector, or the count summary when the model is off.
    var headline: String
    /// True when `headline` came from Apple's on-device model.
    var isModelGenerated: Bool
    var groups: [Group]
    var errorCount: Int
    var warningCount: Int
    var noteCount: Int

    /// Stable JSON for copy/export; keys sorted for readable diffs.
    func jsonString(pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ValidationDigestError.encodingFailed
        }
        return text
    }

    /// Count-only digest — always available, no model required.
    static func fallback(from issues: [ValidationResult.Issue]) -> ValidationDigest {
        let grouped = ValidationIssueGrouping.group(issues)
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        let notes = issues.filter { $0.severity == .info || $0.severity == .hint }.count
        return ValidationDigest(
            headline: issueSummary(errors: errors, warnings: warnings, notes: notes),
            isModelGenerated: false,
            groups: grouped.map {
                Group(severity: $0.severity.rawValue, code: $0.code, message: $0.message, count: $0.count)
            },
            errorCount: errors,
            warningCount: warnings,
            noteCount: notes
        )
    }
}

enum ValidationDigestError: Error {
    case encodingFailed
    case unavailable
    case timeout
    case empty
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct GeneratedValidationDigest {
    @Guide(description: "One plain complete sentence, at most 20 words, naming the main validation problems.")
    var headline: String
}
#endif

/// Calls Apple's on-device Foundation Model when available; otherwise fails with `.unavailable`.
enum ValidationDigestGenerator {
    static func summarize(prompt: String) async throws -> String {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else { throw ValidationDigestError.unavailable }
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let session = LanguageModelSession()
                    let output = try await session.respond(
                        to: prompt,
                        generating: GeneratedValidationDigest.self
                    ).content
                    let headline = output.headline
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !headline.isEmpty else { throw ValidationDigestError.empty }
                    return headline
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw ValidationDigestError.timeout
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        }
#endif
        throw ValidationDigestError.unavailable
    }
}

/// Per-window cache of digests. Request is idempotent; UI reads `digest(for:)` / `headline(for:)`.
@MainActor
@Observable
final class ValidationDigestStore {
    private var values: [String: ValidationDigest] = [:]
    private var inFlight: [String: Task<Void, Never>] = [:]
    /// Keys that already failed this session — do not retry until the issue set changes.
    private var failed: Set<String> = []

    /// Injected for tests; production uses `ValidationDigestGenerator.summarize`.
    @ObservationIgnored
    var summarize: (String) async throws -> String = { try await ValidationDigestGenerator.summarize(prompt: $0) }

    func digest(for issues: [ValidationResult.Issue]) -> ValidationDigest? {
        guard !issues.isEmpty else { return nil }
        return values[ValidationIssueGrouping.digestKey(issues)]
    }

    /// Model headline when ready; nil while pending or when only the count fallback exists.
    func modelHeadline(for issues: [ValidationResult.Issue]) -> String? {
        guard let digest = digest(for: issues), digest.isModelGenerated else { return nil }
        return digest.headline
    }

    /// Display title: AI sentence when ready, otherwise the count summary.
    func title(for issues: [ValidationResult.Issue], fallback: String) -> String {
        modelHeadline(for: issues) ?? fallback
    }

    /// Sidebar / inspector card title: count summary for a single group; AI only when it adds value.
    func cardTitle(
        for issues: [ValidationResult.Issue],
        groups: [GroupedValidationIssue],
        fallback: String
    ) -> String {
        guard groups.count > 1,
              let headline = modelHeadline(for: issues),
              ValidationIssueGrouping.headlineAddsValue(headline, groups: groups)
        else { return fallback }
        return headline
    }

    func request(_ issues: [ValidationResult.Issue], scope: ValidationDigestScope) {
        guard !issues.isEmpty else { return }
        let key = ValidationIssueGrouping.digestKey(issues)
        if values[key]?.isModelGenerated == true { return }
        if failed.contains(key) { return }
        if inFlight[key] != nil { return }

        let fallback = ValidationDigest.fallback(from: issues)
        if values[key] == nil {
            values[key] = fallback
        }

        let groups = ValidationIssueGrouping.group(issues)
        let prompt = ValidationIssueGrouping.prompt(
            groups: groups,
            errorCount: fallback.errorCount,
            warningCount: fallback.warningCount,
            noteCount: fallback.noteCount,
            scope: scope
        )
        let summarize = self.summarize
        inFlight[key] = Task { [weak self] in
            defer { self?.inFlight[key] = nil }
            do {
                let headline = try await summarize(prompt)
                guard !Task.isCancelled else { return }
                var upgraded = fallback
                upgraded.headline = headline
                upgraded.isModelGenerated = true
                self?.values[key] = upgraded
                AppLog.info(AppLog.app, "validation digest ready scope=\(scope.rawValue) groups=\(groups.count)")
            } catch {
                guard !Task.isCancelled else { return }
                self?.failed.insert(key)
                AppLog.info(AppLog.app, "validation digest skipped scope=\(scope.rawValue)")
            }
        }
    }

    func cancelAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        values = [:]
        failed = []
    }
}
