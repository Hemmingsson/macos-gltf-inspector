import AppKit
import AVFoundation
import GLTFCore
import ImageIO
import Renderer
import UniformTypeIdentifiers

/// Share ▸ Export Turntable: one 360° orbit of the canvas at its current pose, as an MP4 video
/// or a looping GIF. The renderer draws each frame (`ModelCanvasController.turntable`); this
/// owns the size, the encoders and the save panel.
enum TurntableExport {
    enum Format: String, CaseIterable, Identifiable, Sendable {
        case mp4, gif

        var id: Self { self }
        var title: String { self == .mp4 ? "Export Turntable Video" : "Export Turntable GIF" }
        var menuTitle: String { title + "…" }
        var contentType: UTType { self == .mp4 ? .mpeg4Movie : .gif }
        /// A smooth 4-second loop for video; GIF trades smoothness for file size.
        var frameCount: Int { self == .mp4 ? 120 : 60 }
        var framesPerSecond: Int { self == .mp4 ? 30 : 15 }
        /// Longest edge in pixels. H.264 wants even sizes; GIFs stay small.
        var maxEdge: Int { self == .mp4 ? 1080 : 540 }
    }

    /// Output size for a canvas of `pixelSize`: aspect kept, long edge capped, both sides even.
    static func frameSize(for pixelSize: CGSize, format: Format) -> (width: Int, height: Int) {
        let width = max(pixelSize.width, 2), height = max(pixelSize.height, 2)
        let scale = min(1, Double(format.maxEdge) / Double(max(width, height)))
        func even(_ value: Double) -> Int { max(2, Int((value * scale / 2).rounded()) * 2) }
        return (even(width), even(height))
    }

    // MARK: - Writing

    /// Streams frames to a file; `finish` closes it. `cancel` drops a half-written file's
    /// writer after a failed `append`, before the temp file is removed.
    protocol Encoder: AnyObject {
        func append(_ image: CGImage) async throws
        func finish() async throws
        func cancel()
    }

    static func encoder(_ format: Format, url: URL, width: Int, height: Int) throws -> any Encoder {
        switch format {
        case .mp4: try MP4Encoder(url: url, width: width, height: height, framesPerSecond: format.framesPerSecond)
        case .gif: try GIFEncoder(url: url, frameCount: format.frameCount, framesPerSecond: format.framesPerSecond)
        }
    }

    /// Renders the orbit from `canvas` into `url`. The frames go to a temp file beside `url`,
    /// which replaces `url` only once the encoder finishes: a failure or cancel leaves `url` as it
    /// was and no temp file behind. `progress` gets the number of frames written so far. Throws
    /// when the canvas is not ready; a cancelled task throws `CancellationError`.
    @MainActor
    static func write(_ format: Format, from canvas: ModelCanvasController, to url: URL,
                      progress: (Int) -> Void = { _ in }) async throws {
        try await write(format, from: canvas, to: url, makeEncoder: encoder, progress: progress)
    }

    /// `write` with the encoder factory injected (tests).
    @MainActor
    static func write(_ format: Format, from canvas: ModelCanvasController, to url: URL,
                      makeEncoder: (Format, URL, Int, Int) throws -> any Encoder,
                      progress: (Int) -> Void = { _ in }) async throws {
        guard let pixelSize = canvas.pixelSize else { throw CocoaError(.fileWriteUnknown) }
        let size = frameSize(for: pixelSize, format: format)
        let temp = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        var encoder: (any Encoder)?
        do {
            let made = try makeEncoder(format, temp, size.width, size.height)
            encoder = made
            try await canvas.turntable(count: format.frameCount, width: size.width, height: size.height) { index, image in
                try await made.append(image)
                progress(index + 1)
            }
            try await made.finish()
            try AtomicFile.replace(url, with: temp)
        } catch {
            encoder?.cancel()
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// Save panel, then the export. Cancel writes nothing; a cancelled export is silent and a
    /// failure shows an alert.
    @MainActor
    static func save(_ format: Format, from canvas: ModelCanvasController, suggestedName: String,
                     progress: (Int) -> Void = { _ in }) async {
        guard let url = await SavePanel.choose(format.contentType, name: "\(suggestedName) turntable.\(format.rawValue)",
                                               title: format.title,
                                               message: "One full turn around the model from the current camera.")
        else { return }
        let started = ContinuousClock.now
        do {
            try await write(format, from: canvas, to: url, progress: progress)
            AppLog.info(AppLog.app, "turntable export wrote \(url.lastPathComponent) in \(started.duration(to: .now))")
        } catch is CancellationError {
            AppLog.info(AppLog.app, "turntable export cancelled")
        } catch {
            AppLog.error(AppLog.app, "turntable export failed: \(error.localizedDescription)")
            SavePanel.reportFailure(title: "Turntable export failed", error: error)
        }
    }
}

/// Replaces a destination with a finished temp file, or moves it into place when there is none.
enum AtomicFile {
    static func replace(_ url: URL, with temp: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}

/// Looping GIF through ImageIO; keeps the canvas's transparency.
private final class GIFEncoder: TurntableExport.Encoder {
    private let destination: CGImageDestination
    private let data: NSMutableData
    private let url: URL

    /// Encoded in memory and written to `url` by `finish`: ImageIO creates a file as soon as it is
    /// given a URL and cannot be told to cancel, so a stopped export would leave that file behind.
    init(url: URL, frameCount: Int, framesPerSecond: Int) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString,
                                                                 frameCount, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.destination = destination
        self.data = data
        self.url = url
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / Double(framesPerSecond)],
        ] as CFDictionary
    }

    private let frameProperties: CFDictionary

    func append(_ image: CGImage) async throws {
        CGImageDestinationAddImage(destination, image, frameProperties)
    }

    func finish() async throws {
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }

    /// Nothing is on disk before `finish`, so there is nothing to stop.
    func cancel() {}
}

/// H.264 MP4 through AVAssetWriter. Video has no alpha: a transparent canvas is flattened onto
/// white, like a PNG pasted into a slide.
private final class MP4Encoder: TurntableExport.Encoder {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let width: Int, height: Int
    private let frameDuration: CMTime
    private var frameIndex: Int64 = 0

    init(url: URL, width: Int, height: Int, framesPerSecond: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        self.width = width
        self.height = height
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage) async throws {
        // Yield to the run loop while the encoder catches up instead of blocking the main thread.
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
        guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
        guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        frameIndex += 1
    }

    func finish() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
    }
}
