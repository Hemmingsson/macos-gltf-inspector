import CoreGraphics
import Foundation
import Testing

/// The renderer-neutral half of the pixel-diff harness: every loop the per-renderer suites run
/// (`RealityKit/PixelDiffRealityKitTests.swift`, `WebKit/PixelDiffWebKitTests.swift`), given a
/// render function. Generation and verification both go through ``Render``. If they did not, a
/// difference between the two paths — a host reused in one and not the other, a command sent in
/// a different order — would show up as every model failing, and the natural response would be
/// to widen the tolerance until it stopped.
@MainActor
enum PixelDiffRun {
    /// Renders one manifest entry at the manifest look, from its recorded camera.
    typealias Render = @MainActor (PixelDiffManifest.Entry) async throws -> CGImage

    enum Failure: Error, CustomStringConvertible {
        case noCamera(String)

        var description: String {
            switch self {
            case .noCamera(let name):
                "\(name) has no recorded camera pose. Regenerate with: \(PixelDiffManifest.regenerationCommand)"
            }
        }
    }

    static func camera(of entry: PixelDiffManifest.Entry) throws -> PixelDiffManifest.Camera {
        guard let camera = entry.camera else { throw Failure.noCamera(entry.name) }
        return camera
    }

    // MARK: - Verification

    /// Every pinned sample through `render`, compared against `renderer`'s committed PNG.
    static func expectEverySampleMatches(
        _ renderer: PixelDiffRendererKind,
        manifest: PixelDiffManifest,
        render: Render
    ) async throws {
        try #require(!manifest.entries.isEmpty, "nothing to compare — the manifest is empty")
        let tolerance = try manifest.tolerance(for: renderer)
        let size = manifest.look.canvasSize
        var failures: [String] = []

        for entry in manifest.entries {
            guard FileManager.default.fileExists(atPath: entry.modelURL.path) else {
                Issue.record(Comment(rawValue: """
                    \(entry.name): model missing at \(entry.modelURL.path). \
                    Fetch with ./scripts/fetch-test-models.sh
                    """))
                failures.append(entry.name)
                continue
            }
            let expected = try PixelDiff.raster(contentsOf: entry.referenceURL(for: renderer))
            let image = try await render(entry)

            // Still mode sets canvas.width directly, so a devicePixelRatio creeping in would
            // change the size rather than merely blur the result.
            #expect(
                image.width == size && image.height == size,
                "\(entry.name): rendered \(image.width)x\(image.height)"
            )

            let actual = try PixelDiff.raster(from: image)
            let (metrics, verdict) = try PixelDiff.compare(actual, to: expected, tolerance: tolerance)
            print("pixel diff \(renderer.rawValue) \(entry.name): \(metrics.summary())")

            if case .differs(let reasons) = verdict {
                failures.append(entry.name)
                let report = try PixelDiffReport.write(
                    name: entry.name, renderer: renderer, actual: actual, expected: expected
                )
                Issue.record(Comment(rawValue: """
                    \(entry.name) does not match its \(renderer.rawValue) reference.
                    \(reasons.joined(separator: "\n"))
                    \(metrics.summary())
                    \(report)
                    If this change is intended, regenerate: \
                    \(PixelDiffManifest.regenerationCommand) \(renderer.rawValue)
                    """))
            }
        }

        #expect(
            failures.isEmpty,
            "\(renderer.rawValue): \(failures.count) of \(manifest.entries.count) samples differ: \(failures.joined(separator: ", "))"
        )
    }

    /// One reference per manifest entry, at the manifest size, and no stray PNGs.
    nonisolated static func expectEveryReferenceIsPresent(_ renderer: PixelDiffRendererKind) throws {
        let manifest = try PixelDiffManifest.load()
        _ = try manifest.tolerance(for: renderer)
        for entry in manifest.entries {
            let url = entry.referenceURL(for: renderer)
            guard FileManager.default.fileExists(atPath: url.path) else {
                Issue.record(Comment(rawValue: """
                    \(entry.name): \(renderer.rawValue) reference missing at \(url.path). \
                    Regenerate with: \(PixelDiffManifest.regenerationCommand) \(renderer.rawValue)
                    """))
                continue
            }
            let raster = try PixelDiff.raster(contentsOf: url)
            let size = manifest.look.canvasSize
            #expect(
                raster.width == size && raster.height == size,
                "\(entry.name): \(renderer.rawValue) reference is \(raster.width)x\(raster.height), manifest says \(size)"
            )
        }

        // A reference nobody asserts against is dead weight that looks like coverage.
        let directory = PixelDiffPaths.referencesDirectory
            .appendingPathComponent(renderer.rawValue, isDirectory: true)
        let onDisk = Set(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".png") })
        let stray = onDisk.subtracting(manifest.entries.map { "\($0.name).png" }).sorted()
        #expect(stray.isEmpty, "\(renderer.rawValue) references with no manifest entry: \(stray)")
    }

    // MARK: - Regeneration

    /// Rewrites `renderer`'s reference PNGs from `render`, the same call verification uses, so a
    /// reference can never describe a path that verification does not take.
    static func regenerate(
        _ renderer: PixelDiffRendererKind,
        manifest: PixelDiffManifest,
        render: Render
    ) async throws {
        for entry in manifest.entries {
            let raster = try PixelDiff.raster(from: try await render(entry))
            let url = entry.referenceURL(for: renderer)
            try PixelDiff.write(raster, to: url)

            // Read it straight back. A lossy write would produce references that disagree
            // with the renderer from the moment they are committed.
            let reread = try PixelDiff.raster(contentsOf: url)
            #expect(reread == raster, "\(entry.name): PNG round trip changed the image")
            print("regenerated \(url.path)")
        }
        print("regenerated \(renderer.rawValue) for \(manifest.entries.count) entries")
    }

    /// Renders every sample ``noiseRounds`` times, each round from a fresh `makeRender()`, and
    /// compares with the first round and with the committed reference (rendered in another
    /// process). Prints one line per sample and the renderer's maximum.
    static let noiseRounds = 3

    static func measureNoise(
        _ renderer: PixelDiffRendererKind,
        manifest: PixelDiffManifest,
        makeRender: @MainActor () async throws -> Render
    ) async throws {
        let tolerance = try manifest.tolerance(for: renderer)
        var renders: [[PixelDiff.Raster]] = []
        for _ in 0..<noiseRounds {
            let render = try await makeRender()
            var round: [PixelDiff.Raster] = []
            for entry in manifest.entries {
                round.append(try PixelDiff.raster(from: try await render(entry)))
            }
            renders.append(round)
        }

        var worstMean = 0.0
        var worstChannel = 0
        var worstBad = 0.0
        for (index, entry) in manifest.entries.enumerated() {
            let golden = try PixelDiff.raster(contentsOf: entry.referenceURL(for: renderer))
            var others = renders.dropFirst().map { $0[index] }
            others.append(golden)
            var mean = 0.0, channel = 0, bad = 0.0
            for other in others {
                let (m, _) = try PixelDiff.compare(other, to: renders[0][index], tolerance: tolerance)
                mean = max(mean, m.meanAbsoluteError)
                channel = max(channel, m.maxChannelDifference)
                bad = max(bad, m.badPixelFraction)
            }
            worstMean = max(worstMean, mean)
            worstChannel = max(worstChannel, channel)
            worstBad = max(worstBad, bad)
            print(String(
                format: "noise %@ %@: mean %.4f, max %d, bad(>%d) %.4f%%",
                renderer.rawValue, entry.name, mean, channel,
                tolerance.badPixelChannelDelta, bad * 100
            ))
        }
        print(String(
            format: "noise floor %@ over %d rounds + golden: mean %.4f, max %d, bad(>%d) %.4f%%",
            renderer.rawValue, noiseRounds, worstMean, worstChannel,
            tolerance.badPixelChannelDelta, worstBad * 100
        ))
    }
}

/// Writes the three files a failure needs: what was rendered, what was expected, and where they
/// disagree.
enum PixelDiffReport {
    static func write(
        name: String,
        renderer: PixelDiffRendererKind,
        actual: PixelDiff.Raster,
        expected: PixelDiff.Raster
    ) throws -> String {
        let directory = PixelDiffPaths.outputDirectory
            .appendingPathComponent(renderer.rawValue, isDirectory: true)
        let actualURL = directory.appendingPathComponent("\(name)-actual.png")
        let expectedURL = directory.appendingPathComponent("\(name)-expected.png")
        let diffURL = directory.appendingPathComponent("\(name)-diff.png")

        try PixelDiff.write(actual, to: actualURL)
        try PixelDiff.write(expected, to: expectedURL)
        try PixelDiff.write(PixelDiff.differenceImage(actual: actual, expected: expected), to: diffURL)

        return """
            actual:   \(actualURL.path)
            expected: \(expectedURL.path)
            diff:     \(diffURL.path) (differences amplified \(PixelDiff.differenceAmplification)x, red)
            """
    }
}
