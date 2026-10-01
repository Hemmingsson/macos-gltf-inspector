import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import Testing

/// Host validation must start after the canvas is ready / first paint — not beside convert
/// or page compile (`GLTFValidator` says call after first paint).
@MainActor
struct DocumentWindowValidationTests {
    @Test
    func beginOpenDoesNotStartValidation() async throws {
        let url = TestFixtures.cube
        let window = DocumentWindowModel(documentURL: url)
        let log = ValidationLog()
        window.validateFile = { url in
            log.add(url)
            return Self.report
        }

        guard case .started = window.beginOpen(url) else {
            Issue.record("open did not start")
            return
        }
        try await Task.sleep(for: .milliseconds(40))
        #expect(log.all.isEmpty)
        #expect(window.validation == nil)
    }

    @Test
    func canvasReadyStartsValidationOnce() async throws {
        let url = TestFixtures.cube
        let window = DocumentWindowModel(documentURL: url)
        let log = ValidationLog()
        window.validateFile = { validated in
            log.add(validated)
            return Self.report
        }

        guard case .started = window.beginOpen(url) else {
            Issue.record("open did not start")
            return
        }
        window.noteCanvasReady()
        window.noteCanvasReady()

        _ = try await waitUntil { window.validation != nil }
        #expect(log.all == [url])
        guard case .success(let report) = window.validation else {
            Issue.record("expected success, got \(String(describing: window.validation))")
            return
        }
        #expect(report.errorCount == 0)
        #expect(window.sceneModel.validation.status == .ready)
    }

    @Test
    func newOpenCancelsAndWaitsForTheNextCanvas() async throws {
        let first = TestFixtures.cube
        let second = TestFixtures.tiny
        let window = DocumentWindowModel(documentURL: first)
        let log = ValidationLog()
        window.validateFile = { url in
            log.add(url)
            return Self.report
        }

        _ = window.beginOpen(first)
        _ = window.beginOpen(second)
        try await Task.sleep(for: .milliseconds(40))
        #expect(log.all.isEmpty)

        window.noteCanvasReady()
        _ = try await waitUntil { window.validation != nil }
        #expect(log.all == [second])
    }

    private static let report = GLTFValidationReport(
        validatorVersion: "test",
        errorCount: 0,
        warningCount: 0,
        infoCount: 0,
        hintCount: 0,
        messages: []
    )
}

private final class ValidationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func add(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    var all: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

@MainActor
private func waitUntil(
    within limit: Duration = .seconds(2),
    _ predicate: () -> Bool
) async throws -> Bool {
    let deadline = ContinuousClock.now + limit
    while ContinuousClock.now < deadline {
        if predicate() { return true }
        await Task.yield()
    }
    if predicate() { return true }
    Issue.record("timed out waiting for validation")
    return false
}
