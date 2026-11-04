import Foundation
@testable import RendererWebKit

/// One way to make a page-backed host in tests.
///
/// Swift Testing runs suites in parallel, so a dozen `WKWebView` pages and the pixel-diff suites
/// share the GPU. The product's 15 s per-call budget is right for a person waiting on a window,
/// too tight for a loaded test machine. Tests that exercise a timeout on purpose still build
/// their own host with a tiny budget.
@MainActor
enum WebKitTest {
    /// Per-call budget for test pages: generous, so machine load cannot flake a test, but finite,
    /// so a regression still fails instead of hanging the suite.
    nonisolated static let timeout: Duration = .seconds(60)

    static func host(_ mode: WebRendererMode = .still, size: Int = 512) throws -> WebRendererHost {
        try WebRendererHost(mode: mode, size: size, timeout: timeout)
    }

    /// A started still host with the default look applied, ready for `load`.
    static func stillHost(size: Int = 512) async throws -> WebRendererHost {
        let host = try host(.still, size: size)
        try await host.start()
        try await host.apply(WebPreviewCanvas.Look())
        return host
    }

    /// Polls `condition` until it holds or `limit` passes; returns whether it held. Wait on the
    /// state a test needs, never on a fixed sleep.
    static func waitUntil(
        within limit: Duration = timeout,
        _ condition: () -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + limit
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
