import Foundation
import GLTFCore
import QuickLookThumbnailing
import Renderer

/// Finder thumbnail principal class: the same renderer as the window and Quick Look, so a file's
/// Finder icon matches how it opens.
class ThumbnailProvider: QLThumbnailProvider {
    @MainActor private static let renderer = ThumbnailRenderer()
    private static let outputPrefix = "glb-thumb-"
    private static let timeout: Duration = .seconds(15)

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * max(request.scale, 1)))
        let url = request.fileURL
        // Quick Look copies the image from the handed-off URL but never deletes it, and the
        // extension gets no completion callback, so clear files left by earlier requests.
        Self.sweepStaleThumbnails()

        let completion = ThumbnailCompletion(handler)
        let work = Task { @MainActor in
            var fileURL: URL?
            do {
                let started = ContinuousClock.now
                let image = try await Self.renderer.render(url: url, pixel: pixel)
                try Task.checkCancellation()
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(Self.outputPrefix)\(UUID().uuidString).png")
                fileURL = outputURL
                try await Task.detached(priority: .utility) {
                    try PNGWriter.write(image, to: outputURL)
                }.value
                AppLog.info(AppLog.thumbnail, "thumbnail \(url.lastPathComponent) \(pixel)px in \(started.duration(to: .now))")
                // Finder reliably consumes `imageFileURL`. The CGContext drawing reply works
                // under `qlmanage -x` but fails in Finder with QLThumbnailError 102.
                if !completion.finish(QLThumbnailReply(imageFileURL: outputURL), nil) {
                    try? FileManager.default.removeItem(at: outputURL)
                }
            } catch {
                if let fileURL {
                    try? FileManager.default.removeItem(at: fileURL)
                }
                AppLog.error(AppLog.thumbnail, "thumbnail failed \(url.lastPathComponent)")
                completion.finish(nil, error)
            }
        }
        let timer = Task {
            do {
                try await Task.sleep(for: Self.timeout)
            } catch {
                return  // Cancelled: the work finished first.
            }
            work.cancel()
            completion.finish(nil, ThumbnailError.timedOut)
        }
        Task {
            _ = await work.result
            timer.cancel()
        }
    }

    /// Removes reply files older than a minute. The age guard keeps a concurrent request's
    /// just-written file until Quick Look has read it.
    private static func sweepStaleThumbnails() {
        let directory = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date(timeIntervalSinceNow: -60)
        for entry in entries where entry.lastPathComponent.hasPrefix(outputPrefix) {
            let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}

private final class ThumbnailCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private let handler: (QLThumbnailReply?, Error?) -> Void

    init(_ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        self.handler = handler
    }

    @discardableResult
    func finish(_ reply: QLThumbnailReply?, _ error: Error?) -> Bool {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return false
        }
        didFinish = true
        lock.unlock()
        handler(reply, error)
        return true
    }
}

private enum ThumbnailError: Error {
    case timedOut
}
