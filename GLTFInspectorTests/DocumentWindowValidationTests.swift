import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import Testing

/// Validation starts once the canvas shows the model, not beside the renderer's load
/// (`GLTFValidator` is CPU heavy).
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
        #expect(window.validationState == nil)
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

        #expect(try await waitUntil { window.validationState != nil })
        #expect(log.all == [url])
        guard case .success(let report) = window.validationState else {
            Issue.record("expected success, got \(String(describing: window.validationState))")
            return
        }
        #expect(report.errorCount == 0)
        #expect(window.validation.status == .ready)
    }

    @Test
    func canvasFailureStillStartsValidation() async throws {
        let url = TestFixtures.invalid
        let window = DocumentWindowModel(documentURL: url)
        let log = ValidationLog()
        window.validateFile = { validated in
            log.add(validated)
            return GLTFValidationReport(
                validatorVersion: "test",
                errorCount: 1,
                warningCount: 0,
                messages: [
                    GLTFValidationIssue(
                        code: "MESH_NOT_FOUND",
                        message: "Unresolved mesh.",
                        severity: 0,
                        pointer: "/nodes/0/mesh"
                    ),
                ]
            )
        }

        guard case .started = window.beginOpen(url) else {
            Issue.record("open did not start")
            return
        }
        // DocumentWindow calls noteCanvasReady for .failed as well as .ready.
        window.noteCanvasReady()

        #expect(try await waitUntil { window.validationState != nil })
        #expect(log.all == [url])
        #expect(window.validation.errorCount == 1)
        #expect(window.validationDigests.digest(for: window.validation.issues) != nil)
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
        #expect(try await waitUntil { window.validationState != nil })
        #expect(log.all == [second])
    }

    @Test
    func rejectedOpenInvalidatesAnEarlierSummaryAndClearsBothDocuments() async throws {
        let valid = TestFixtures.cube
        let rejected = URL(fileURLWithPath: "/tmp/not-a-model.txt")
        let window = DocumentWindowModel(documentURL: valid)
        let gate = AsyncGate()

        guard case .started(let generation) = window.beginOpen(valid) else {
            Issue.record("valid open did not start")
            return
        }
        let task = Task {
            await window.openSummary(valid, generation: generation) { _ in
                await gate.wait()
                return GLTFDocument()
            }
        }

        _ = window.beginOpen(rejected)
        gate.open()
        await task.value

        #expect(window.document.nodes.isEmpty)
        #expect(window.view.document.nodes.isEmpty)
        #expect(window.phase == .failed("Not a .glb / .gltf file"))
        #expect(window.loadGeneration > generation)
    }

    @Test
    func closingCancelsValidation() async throws {
        let window = DocumentWindowModel(documentURL: TestFixtures.cube)
        let cancelled = CancellationLog()
        window.validateFile = { _ in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                cancelled.mark()
                throw error
            }
            return Self.report
        }

        _ = window.beginOpen(TestFixtures.cube)
        window.noteCanvasReady()
        window.close()

        #expect(try await waitUntil { cancelled.value })
        #expect(window.phase == .empty)
        #expect(window.document.nodes.isEmpty)
    }

    private nonisolated static let report = GLTFValidationReport(
        validatorVersion: "test",
        errorCount: 0,
        warningCount: 0,
        messages: []
    )
}

private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let waiters = self.waiters
        self.waiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume() }
    }
}

private final class CancellationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var didCancel = false

    func mark() {
        lock.lock()
        didCancel = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didCancel
    }
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
