import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import GLTFInspector

/// Image comparison for the reference-render harness.
///
/// Exact equality is not usable here: GPU drivers and renderer versions move pixels by a bit or
/// two, and a suite that flakes gets switched off, which is worse than not having one. So the
/// verdict is perceptual — a mean error budget for uniform drift, plus a separate count of
/// pixels that are *obviously* wrong, because a mean over 262,144 pixels happily absorbs a
/// mangled corner.
enum PixelDiff {
    /// Both sides are flattened onto this before comparing.
    ///
    /// A render that changes only its transparency would otherwise compare equal in RGB, and
    /// the colour under a fully transparent pixel is undefined to begin with. Mid grey rather
    /// than black or white so a difference in either direction stays visible.
    static let backdrop: (r: UInt8, g: UInt8, b: UInt8) = (128, 128, 128)

    /// An opaque 8-bit RGBA image, normalised so that two images are comparable byte for byte.
    ///
    /// Reference PNGs are written from this representation, not from the renderer's own
    /// `CGImage` — the file on disk is then exactly the thing the assertion compares against,
    /// with no colour space or alpha handling left to differ between writing and reading.
    struct Raster: Equatable, Sendable {
        var width: Int
        var height: Int
        /// RGBA, row-major, `width * height * 4` bytes. Alpha is always 255.
        var bytes: [UInt8]

        var pixelCount: Int { width * height }
    }

    /// How far apart two rasters are, and by which measure.
    struct Metrics: Sendable {
        /// Mean absolute difference over every RGB channel of every pixel, in 0...255.
        var meanAbsoluteError: Double
        /// Largest single-channel difference anywhere, in 0...255.
        var maxChannelDifference: Int
        /// Share of pixels whose worst channel differs by more than the bad-pixel threshold.
        var badPixelFraction: Double
        var badPixelCount: Int
        var pixelCount: Int

        func summary() -> String {
            String(
                format: "mean %.3f, max %d, bad %d/%d (%.4f%%)",
                meanAbsoluteError,
                maxChannelDifference,
                badPixelCount,
                pixelCount,
                badPixelFraction * 100
            )
        }
    }

    /// The budget a comparison has to stay inside. Committed in the manifest so a later
    /// loosening shows up in review rather than in a test file nobody reads.
    struct Tolerance: Equatable, Codable, Sendable {
        /// Absorbs uniform driver-level drift across the whole frame.
        var meanAbsoluteError: Double
        /// A channel difference above this makes a pixel "obviously wrong".
        var badPixelChannelDelta: Int
        /// How many obviously-wrong pixels are still acceptable, as a fraction.
        var badPixelFraction: Double

        static let `default` = Tolerance(
            meanAbsoluteError: 2.0,
            badPixelChannelDelta: 24,
            badPixelFraction: 0.005
        )
    }

    enum Verdict: Equatable, Sendable {
        case matches
        case differs(reasons: [String])

        var isMatch: Bool { self == .matches }
    }

    enum Failure: Error, CustomStringConvertible {
        case sizeMismatch(expected: (Int, Int), actual: (Int, Int))
        case undecodable(URL)
        case unwritable(URL)

        var description: String {
            switch self {
            case .sizeMismatch(let expected, let actual):
                "image is \(actual.0)x\(actual.1), expected \(expected.0)x\(expected.1)"
            case .undecodable(let url):
                "could not decode an image at \(url.path)"
            case .unwritable(let url):
                "could not write an image to \(url.path)"
            }
        }
    }

    // MARK: - Normalising

    /// Flattens a rendered frame onto ``backdrop`` in sRGB at 8 bits per channel.
    static func raster(from image: CGImage) throws -> Raster {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw Failure.unwritable(URL(fileURLWithPath: "/dev/null")) }

            context.setFillColor(
                red: CGFloat(backdrop.r) / 255,
                green: CGFloat(backdrop.g) / 255,
                blue: CGFloat(backdrop.b) / 255,
                alpha: 1
            )
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return Raster(width: width, height: height, bytes: bytes)
    }

    static func raster(contentsOf url: URL) throws -> Raster {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.undecodable(url) }
        return try raster(from: image)
    }

    // MARK: - Comparing

    static func compare(_ actual: Raster, to expected: Raster, tolerance: Tolerance) throws
        -> (metrics: Metrics, verdict: Verdict)
    {
        guard actual.width == expected.width, actual.height == expected.height else {
            throw Failure.sizeMismatch(
                expected: (expected.width, expected.height),
                actual: (actual.width, actual.height)
            )
        }

        var total = 0
        var worst = 0
        var bad = 0
        let count = expected.pixelCount

        for pixel in 0..<count {
            let base = pixel * 4
            var pixelWorst = 0
            for channel in 0..<3 {
                let delta = abs(Int(actual.bytes[base + channel]) - Int(expected.bytes[base + channel]))
                total += delta
                if delta > pixelWorst { pixelWorst = delta }
            }
            if pixelWorst > worst { worst = pixelWorst }
            if pixelWorst > tolerance.badPixelChannelDelta { bad += 1 }
        }

        let metrics = Metrics(
            meanAbsoluteError: Double(total) / Double(count * 3),
            maxChannelDifference: worst,
            badPixelFraction: Double(bad) / Double(count),
            badPixelCount: bad,
            pixelCount: count
        )

        var reasons: [String] = []
        if metrics.meanAbsoluteError > tolerance.meanAbsoluteError {
            reasons.append(String(
                format: "mean absolute error %.3f exceeds %.3f",
                metrics.meanAbsoluteError, tolerance.meanAbsoluteError
            ))
        }
        if metrics.badPixelFraction > tolerance.badPixelFraction {
            reasons.append(String(
                format: "%d pixels differ by more than %d (%.4f%% of the frame, budget %.4f%%)",
                metrics.badPixelCount,
                tolerance.badPixelChannelDelta,
                metrics.badPixelFraction * 100,
                tolerance.badPixelFraction * 100
            ))
        }

        return (metrics, reasons.isEmpty ? .matches : .differs(reasons: reasons))
    }

    /// How much a difference is brightened in the written diff image.
    static let differenceAmplification = 8

    /// Differences glowing red over a dimmed copy of the reference.
    ///
    /// A bare difference image is hard to read — a red smear on black says something moved but
    /// not what. Keeping the reference underneath says *which part of the model* moved, which
    /// is the question anyone opening the file actually has.
    static func differenceImage(actual: Raster, expected: Raster) -> Raster {
        var bytes = [UInt8](repeating: 255, count: expected.bytes.count)
        for pixel in 0..<expected.pixelCount {
            let base = pixel * 4
            var worst = 0
            var reference = 0
            for channel in 0..<3 {
                let e = Int(expected.bytes[base + channel])
                reference += e
                let delta = abs(Int(actual.bytes[base + channel]) - e)
                if delta > worst { worst = delta }
            }
            let dim = UInt8(reference / 3 / 4)
            bytes[base] = UInt8(min(255, Int(dim) + worst * differenceAmplification))
            bytes[base + 1] = dim
            bytes[base + 2] = dim
            bytes[base + 3] = 255
        }
        return Raster(width: expected.width, height: expected.height, bytes: bytes)
    }

    // MARK: - Files

    static func write(_ raster: Raster, to url: URL) throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var bytes = raster.bytes
        let image: CGImage? = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: raster.width,
                height: raster.height,
                bitsPerComponent: 8,
                bytesPerRow: raster.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard
            let image,
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            )
        else { throw Failure.unwritable(url) }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unwritable(url) }
    }
}
