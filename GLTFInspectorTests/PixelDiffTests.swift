import CoreGraphics
import Foundation
import Testing
@testable import GLTFInspector

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

// MARK: - The comparator itself

/// Pure image work — no renderer involved.
///
/// The comparator is the assertion. If it is capable of passing a wrong image then every model
/// test below is decoration, so its failure modes are tested directly rather than only being
/// demonstrated by hand once.
struct PixelDiffComparisonTests {
    /// The first web reference, with the web budget. The comparator is renderer-agnostic;
    /// one real reference is enough to exercise it.
    private func loadFirstReference() throws -> (PixelDiff.Tolerance, PixelDiff.Raster) {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first)
        return (
            try manifest.tolerance(for: .webkit),
            try PixelDiff.raster(contentsOf: entry.referenceURL(for: .webkit))
        )
    }

    /// Paints a solid block, in the corner opposite the origin so it lands on model or
    /// background depending on the sample — either way it is a real difference.
    private func damaged(_ raster: PixelDiff.Raster, blockEdge: Int) -> PixelDiff.Raster {
        var copy = raster
        for y in (raster.height / 2)..<(raster.height / 2 + blockEdge) {
            for x in (raster.width / 2)..<(raster.width / 2 + blockEdge) {
                let base = (y * raster.width + x) * 4
                copy.bytes[base] = 255
                copy.bytes[base + 1] = 0
                copy.bytes[base + 2] = 255
            }
        }
        return copy
    }

    @Test func anImageMatchesItself() throws {
        let (tolerance, reference) = try loadFirstReference()
        let (metrics, verdict) = try PixelDiff.compare(
            reference, to: reference, tolerance: tolerance
        )
        #expect(metrics.meanAbsoluteError == 0)
        #expect(metrics.maxChannelDifference == 0)
        #expect(verdict == .matches)
    }

    /// The tolerance exists for driver-level drift. If a one-step shift failed, the suite would
    /// flake on another machine and get switched off.
    @Test func aOneStepShiftAcrossTheWholeFrameStillMatches() throws {
        let (tolerance, reference) = try loadFirstReference()
        var drifted = reference
        for pixel in 0..<drifted.pixelCount {
            for channel in 0..<3 {
                let index = pixel * 4 + channel
                drifted.bytes[index] = drifted.bytes[index] &+ 1 > 255 ? 255 : drifted.bytes[index] &+ 1
            }
        }
        let (metrics, verdict) = try PixelDiff.compare(
            drifted, to: reference, tolerance: tolerance
        )
        #expect(metrics.meanAbsoluteError <= 1.0)
        #expect(verdict == .matches, "one-step drift must not fail the suite")
    }

    /// The other end of the same axis: a shift small enough to leave every *pixel* inside the
    /// bad-pixel threshold must still fail on the mean, or a uniform lighting or tone-mapping
    /// change would sail through.
    @Test func aUniformShiftTooLargeToBeDriftIsRejected() throws {
        let (tolerance, reference) = try loadFirstReference()
        var shifted = reference
        let step = UInt8(tolerance.badPixelChannelDelta - 1)
        for pixel in 0..<shifted.pixelCount {
            for channel in 0..<3 {
                let index = pixel * 4 + channel
                shifted.bytes[index] = UInt8(min(255, Int(shifted.bytes[index]) + Int(step)))
            }
        }
        let (metrics, verdict) = try PixelDiff.compare(
            shifted, to: reference, tolerance: tolerance
        )
        #expect(metrics.badPixelCount == 0, "no single pixel is over the structural threshold")
        #expect(metrics.meanAbsoluteError > tolerance.meanAbsoluteError)
        #expect(!verdict.isMatch, "a whole-frame brightness change must fail")
    }

    /// The case a mean absorbs. A block of 40x40 is 0.6% of a 512-pixel frame; averaged over
    /// the other 99.4% it barely registers, which is exactly why the bad-pixel count exists as
    /// a separate arm of the verdict.
    @Test func localDamageTooSmallToMoveTheMeanIsStillRejected() throws {
        let (tolerance, reference) = try loadFirstReference()
        let (metrics, verdict) = try PixelDiff.compare(
            damaged(reference, blockEdge: 40), to: reference, tolerance: tolerance
        )
        #expect(
            metrics.meanAbsoluteError <= tolerance.meanAbsoluteError,
            "block is small enough that the mean stays inside budget — \(metrics.summary())"
        )
        #expect(metrics.badPixelFraction > tolerance.badPixelFraction)
        #expect(!verdict.isMatch, "a mangled block must fail even when the mean is fine")
    }

    @Test func differentlySizedImagesThrowRatherThanCompare() throws {
        let (tolerance, reference) = try loadFirstReference()
        let cropped = PixelDiff.Raster(
            width: reference.width,
            height: reference.height - 1,
            bytes: Array(reference.bytes.dropLast(reference.width * 4))
        )
        #expect(throws: PixelDiff.Failure.self) {
            _ = try PixelDiff.compare(cropped, to: reference, tolerance: tolerance)
        }
    }

    /// A missing reference has to be an error, not an empty image that compares against
    /// whatever the renderer produced.
    @Test func aMissingImageFileThrows() {
        #expect(throws: PixelDiff.Failure.self) {
            _ = try PixelDiff.raster(contentsOf: PixelDiffPaths.reference("no-such-reference", renderer: .webkit))
        }
    }

    @Test func theDifferenceImageMarksWhereTheImagesDisagree() throws {
        let (_, reference) = try loadFirstReference()
        let broken = damaged(reference, blockEdge: 40)
        let diff = PixelDiff.differenceImage(actual: broken, expected: reference)

        let inside = ((reference.height / 2 + 5) * reference.width + reference.width / 2 + 5) * 4
        let outside = (4 * reference.width + 4) * 4
        #expect(diff.bytes[inside] > diff.bytes[inside + 1], "damage should read as red")
        #expect(diff.bytes[outside] == diff.bytes[outside + 1], "untouched area stays grey")
    }
}

// MARK: - Fixtures and references

/// These deliberately carry no `.enabled(if:)` gate.
///
/// A switched-off suite reports green. The manifest is the pinned sample list, so a sample it
/// names that is not on disk is a failure, not a skip — otherwise an empty run is
/// indistinguishable from a passing one.
struct PixelDiffCoverageTests {
    @Test func everyPinnedSampleIsOnDisk() throws {
        let manifest = try PixelDiffManifest.load()
        #expect(!manifest.entries.isEmpty, "the manifest lists no models")
        let missing = manifest.entries.flatMap { entry in
            entry.files
                .map { entry.modelURL.deletingLastPathComponent().appendingPathComponent($0) }
                .filter { !FileManager.default.fileExists(atPath: $0.path) }
                .map { "\(entry.name)/\($0.lastPathComponent)" }
        }
        #expect(
            missing.isEmpty,
            """
            \(missing.count) pinned sample file(s) missing: \(missing.joined(separator: ", ")). \
            Fetch with ./scripts/fetch-test-models.sh
            """
        )
    }

    @Test func everyEntryIsMeasuredAndUniquelyNamed() throws {
        let manifest = try PixelDiffManifest.load()
        let names = manifest.entries.map(\.name)
        #expect(Set(names).count == names.count, "duplicate manifest names")
        for entry in manifest.entries {
            #expect(!entry.files.isEmpty, "\(entry.name): no files")
            #expect(
                entry.camera?.isFinite == true,
                "\(entry.name): no finite camera pose. Regenerate with: \(PixelDiffManifest.regenerationCommand)"
            )
        }
    }

    /// `requires` is a record, not a guess: it must say what the file actually uses.
    @Test func recordedFeaturesMatchTheFiles() throws {
        let manifest = try PixelDiffManifest.load()
        for entry in manifest.entries {
            let json = try PixelDiffSampleFeatures.json(of: entry.modelURL)
            #expect(
                entry.requires == PixelDiffSampleFeatures.derive(from: json),
                "\(entry.name): manifest requires \(entry.requires)"
            )
        }
    }

    @Test(arguments: PixelDiffRendererKind.allCases)
    func everyReferenceImageIsPresentAndTheRightShape(_ renderer: PixelDiffRendererKind) throws {
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
}

// MARK: - Rendering

/// The safety net itself: every pinned sample rendered through each renderer and compared
/// against that renderer's committed PNG.
@MainActor
@Suite(.serialized)
struct PixelDiffHarness {
    @Test(arguments: PixelDiffRendererKind.allCases)
    func everySampleMatchesItsReference(_ renderer: PixelDiffRendererKind) async throws {
        let manifest = try PixelDiffManifest.load()
        try #require(!manifest.entries.isEmpty, "nothing to compare — the manifest is empty")
        let tolerance = try manifest.tolerance(for: renderer)
        let render = try await PixelDiffRendering.make(renderer, manifest: manifest)
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

    /// The premise of the whole harness. If the renderer does not produce the same pixels twice
    /// in a row, no committed reference means anything.
    @Test func renderingTheSameModelTwiceProducesTheSamePixels() async throws {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first)
        let host = try await PixelDiffRenderer.makeHost(manifest: manifest)

        let first = try PixelDiff.raster(from: try await PixelDiffRenderer.render(entry, on: host))
        let second = try PixelDiff.raster(from: try await PixelDiffRenderer.render(entry, on: host))

        let (metrics, _) = try PixelDiff.compare(
            first, to: second, tolerance: try manifest.tolerance(for: .webkit)
        )
        #expect(metrics.maxChannelDifference == 0, "renderer is not deterministic: \(metrics.summary())")
    }

    /// `everySampleMatchesItsReference` renders every model through one web view to keep the
    /// suite quick. That only holds if a model leaves no trace on the next one — otherwise the
    /// references would encode the sample ordering, and reordering the manifest would break
    /// every test downstream of the change.
    @Test func aHostThatAlreadyDrewAnotherModelDrawsTheSame() async throws {
        let manifest = try PixelDiffManifest.load()
        try #require(manifest.entries.count >= 2)
        let subject = try #require(manifest.entries.last)
        let predecessor = try #require(manifest.entries.first)

        let clean = try await PixelDiffRenderer.makeHost(manifest: manifest)
        let alone = try PixelDiff.raster(from: try await PixelDiffRenderer.render(subject, on: clean))

        let reused = try await PixelDiffRenderer.makeHost(manifest: manifest)
        _ = try await PixelDiffRenderer.render(predecessor, on: reused)
        let afterAnother = try PixelDiff.raster(
            from: try await PixelDiffRenderer.render(subject, on: reused)
        )

        let (metrics, _) = try PixelDiff.compare(
            afterAnother, to: alone, tolerance: try manifest.tolerance(for: .webkit)
        )
        #expect(
            metrics.maxChannelDifference == 0,
            "\(subject.name) renders differently after \(predecessor.name): \(metrics.summary())"
        )
    }
}

// MARK: - Regeneration

/// Rewrites reference PNGs (and, for WebKit, the recorded camera poses and features). Off unless
/// asked for — this is a generator, not an assertion, and running it as part of a normal suite
/// would make the tests agree with whatever the renderer currently does.
///
///     ./scripts/regenerate-pixel-references.sh [webkit|realitykit]
///
/// The manifest's entry list is the pinned sample set: the generator never adds or drops
/// entries. Add a sample by adding `name`/`source`/`files` to the manifest, fetch, regenerate.
/// Then look at the PNGs before committing them. They are the assertions; a wrong one bakes in
/// a wrong answer for good.
@MainActor
struct PixelDiffReferenceRegeneration {
    @Test(.enabled(if: PixelDiffRegeneration.isRequested))
    func regenerate() async throws {
        var manifest = try PixelDiffManifest.load()
        try #require(!manifest.entries.isEmpty, "no pinned samples to render")
        let renderers = PixelDiffRegeneration.requestedRenderers

        // WebKit first: it records the poses every renderer then replays.
        if renderers.contains(.webkit) {
            let host = try await PixelDiffRenderer.makeHost(manifest: manifest)
            for index in manifest.entries.indices {
                let model = manifest.entries[index].modelURL
                manifest.entries[index].camera = try await PixelDiffRenderer.recordPose(
                    for: model, on: host
                )
                manifest.entries[index].requires = PixelDiffSampleFeatures.derive(
                    from: try PixelDiffSampleFeatures.json(of: model)
                )
            }
            try manifest.write()
        }

        for renderer in renderers {
            let render = try await PixelDiffRendering.make(renderer, manifest: manifest)
            for entry in manifest.entries {
                // Rendered through the same call the comparison uses, so a reference can never
                // describe a path that verification does not take.
                let raster = try PixelDiff.raster(from: try await render(entry))
                let url = entry.referenceURL(for: renderer)
                try PixelDiff.write(raster, to: url)

                // Read it straight back. A lossy write would produce references that disagree
                // with the renderer from the moment they are committed.
                let reread = try PixelDiff.raster(contentsOf: url)
                #expect(reread == raster, "\(entry.name): PNG round trip changed the image")
                print("regenerated \(url.path)")
            }
        }
        print("regenerated \(renderers.map(\.rawValue)) for \(manifest.entries.count) entries")
    }
}

/// Measures the run-to-run noise floor the tolerances are set from. Off unless asked for:
///
///     ./scripts/regenerate-pixel-references.sh --measure-noise
///
/// Every sample is rendered ``rounds`` times per renderer, each round from a freshly built
/// renderer, and compared with the first round and with the committed reference (which was
/// rendered in another process). Prints one line per sample and a per-renderer maximum.
@MainActor
struct PixelDiffNoiseFloor {
    static let rounds = 3

    @Test(.enabled(if: PixelDiffRegeneration.isNoiseMeasurementRequested))
    func measure() async throws {
        let manifest = try PixelDiffManifest.load()
        for renderer in PixelDiffRendererKind.allCases {
            let tolerance = try manifest.tolerance(for: renderer)
            var renders: [[PixelDiff.Raster]] = []
            for _ in 0..<Self.rounds {
                let render = try await PixelDiffRendering.make(renderer, manifest: manifest)
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
                renderer.rawValue, Self.rounds, worstMean, worstChannel,
                tolerance.badPixelChannelDelta, worstBad * 100
            ))
        }
    }
}
