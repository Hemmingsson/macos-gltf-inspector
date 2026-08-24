import CoreGraphics
import Foundation
import Testing
@testable import GLTFInspector

/// Writes the three files a failure needs: what was rendered, what was expected, and where they
/// disagree.
enum PixelDiffReport {
    static func write(
        name: String,
        actual: PixelDiff.Raster,
        expected: PixelDiff.Raster
    ) throws -> String {
        let directory = PixelDiffPaths.outputDirectory
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
    private func loadFirstReference() throws -> (PixelDiffManifest, PixelDiff.Raster) {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first)
        return (manifest, try PixelDiff.raster(contentsOf: entry.referenceURL))
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
        let (manifest, reference) = try loadFirstReference()
        let (metrics, verdict) = try PixelDiff.compare(
            reference, to: reference, tolerance: manifest.tolerance
        )
        #expect(metrics.meanAbsoluteError == 0)
        #expect(metrics.maxChannelDifference == 0)
        #expect(verdict == .matches)
    }

    /// The tolerance exists for driver-level drift. If a one-step shift failed, the suite would
    /// flake on another machine and get switched off.
    @Test func aOneStepShiftAcrossTheWholeFrameStillMatches() throws {
        let (manifest, reference) = try loadFirstReference()
        var drifted = reference
        for pixel in 0..<drifted.pixelCount {
            for channel in 0..<3 {
                let index = pixel * 4 + channel
                drifted.bytes[index] = drifted.bytes[index] &+ 1 > 255 ? 255 : drifted.bytes[index] &+ 1
            }
        }
        let (metrics, verdict) = try PixelDiff.compare(
            drifted, to: reference, tolerance: manifest.tolerance
        )
        #expect(metrics.meanAbsoluteError <= 1.0)
        #expect(verdict == .matches, "one-step drift must not fail the suite")
    }

    /// The other end of the same axis: a shift small enough to leave every *pixel* inside the
    /// bad-pixel threshold must still fail on the mean, or a uniform lighting or tone-mapping
    /// change would sail through.
    @Test func aUniformShiftTooLargeToBeDriftIsRejected() throws {
        let (manifest, reference) = try loadFirstReference()
        var shifted = reference
        let step = UInt8(manifest.tolerance.badPixelChannelDelta - 1)
        for pixel in 0..<shifted.pixelCount {
            for channel in 0..<3 {
                let index = pixel * 4 + channel
                shifted.bytes[index] = UInt8(min(255, Int(shifted.bytes[index]) + Int(step)))
            }
        }
        let (metrics, verdict) = try PixelDiff.compare(
            shifted, to: reference, tolerance: manifest.tolerance
        )
        #expect(metrics.badPixelCount == 0, "no single pixel is over the structural threshold")
        #expect(metrics.meanAbsoluteError > manifest.tolerance.meanAbsoluteError)
        #expect(!verdict.isMatch, "a whole-frame brightness change must fail")
    }

    /// The case a mean absorbs. A block of 40x40 is 0.6% of a 512-pixel frame; averaged over
    /// the other 99.4% it barely registers, which is exactly why the bad-pixel count exists as
    /// a separate arm of the verdict.
    @Test func localDamageTooSmallToMoveTheMeanIsStillRejected() throws {
        let (manifest, reference) = try loadFirstReference()
        let (metrics, verdict) = try PixelDiff.compare(
            damaged(reference, blockEdge: 40), to: reference, tolerance: manifest.tolerance
        )
        #expect(
            metrics.meanAbsoluteError <= manifest.tolerance.meanAbsoluteError,
            "block is small enough that the mean stays inside budget — \(metrics.summary())"
        )
        #expect(metrics.badPixelFraction > manifest.tolerance.badPixelFraction)
        #expect(!verdict.isMatch, "a mangled block must fail even when the mean is fine")
    }

    @Test func differentlySizedImagesThrowRatherThanCompare() throws {
        let (manifest, reference) = try loadFirstReference()
        let cropped = PixelDiff.Raster(
            width: reference.width,
            height: reference.height - 1,
            bytes: Array(reference.bytes.dropLast(reference.width * 4))
        )
        #expect(throws: PixelDiff.Failure.self) {
            _ = try PixelDiff.compare(cropped, to: reference, tolerance: manifest.tolerance)
        }
    }

    /// A missing reference has to be an error, not an empty image that compares against
    /// whatever the renderer produced.
    @Test func aMissingImageFileThrows() {
        #expect(throws: PixelDiff.Failure.self) {
            _ = try PixelDiff.raster(contentsOf: PixelDiffPaths.reference("no-such-reference.png"))
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
/// `TestModels.hasKhronosSamples` switches the rendering tests off when the samples have not
/// been fetched, and a switched-off suite reports green. Something has to fail in that
/// situation or an empty run is indistinguishable from a passing one.
struct PixelDiffCoverageTests {
    @Test func khronosSamplesAreOnDisk() {
        let samples = TestModels.khronosGLBs
        #expect(
            !samples.isEmpty,
            """
            No Khronos samples under \(TestModels.khronosDirectory.path). \
            The pixel-diff harness cannot run without them; fetch with ./scripts/fetch-test-models.sh
            """
        )
    }

    @Test func theManifestCoversEverySampleAndNothingElse() throws {
        let manifest = try PixelDiffManifest.load()
        #expect(!manifest.entries.isEmpty, "the manifest lists no models")

        let listed = Set(manifest.entries.map(\.model))
        let onDisk = Set(TestModels.khronosGLBs.map {
            $0.path.replacingOccurrences(of: TestFixtures.repoRoot.path + "/", with: "")
        })

        let unreferenced = onDisk.subtracting(listed).sorted()
        #expect(
            unreferenced.isEmpty,
            """
            \(unreferenced.count) sample(s) have no reference render: \(unreferenced.joined(separator: ", ")). \
            Regenerate with: \(PixelDiffManifest.regenerationCommand)
            """
        )

        let vanished = listed.subtracting(onDisk).sorted()
        #expect(
            vanished.isEmpty,
            "the manifest names model(s) that are not on disk: \(vanished.joined(separator: ", "))"
        )
    }

    @Test func everyReferenceImageIsPresentAndTheRightShape() throws {
        let manifest = try PixelDiffManifest.load()
        for entry in manifest.entries {
            guard FileManager.default.fileExists(atPath: entry.referenceURL.path) else {
                Issue.record(Comment(rawValue: """
                    \(entry.name): reference image missing at \(entry.referenceURL.path). \
                    Regenerate with: \(PixelDiffManifest.regenerationCommand)
                    """))
                continue
            }
            let raster = try PixelDiff.raster(contentsOf: entry.referenceURL)
            #expect(
                raster.width == manifest.canvasSize && raster.height == manifest.canvasSize,
                "\(entry.name): reference is \(raster.width)x\(raster.height), manifest says \(manifest.canvasSize)"
            )
            #expect(entry.camera.isFinite, "\(entry.name): recorded camera pose is not finite")
        }
    }
}

// MARK: - Rendering

/// The safety net itself: every Khronos sample rendered through the shipping renderer and
/// compared against a committed PNG.
@MainActor
struct PixelDiffHarness {
    @Test func everySampleMatchesItsReference() async throws {
        let manifest = try PixelDiffManifest.load()
        try #require(!manifest.entries.isEmpty, "nothing to compare — the manifest is empty")

        let host = try await PixelDiffRenderer.makeHost(manifest: manifest)
        var failures: [String] = []

        for entry in manifest.entries {
            guard FileManager.default.fileExists(atPath: entry.modelURL.path) else {
                Issue.record(Comment(rawValue: "\(entry.name): model missing at \(entry.modelURL.path)"))
                failures.append(entry.name)
                continue
            }
            let expected = try PixelDiff.raster(contentsOf: entry.referenceURL)
            let image = try await PixelDiffRenderer.render(entry, on: host)

            // Still mode sets canvas.width directly, so a devicePixelRatio creeping in would
            // change the size rather than merely blur the result.
            #expect(
                image.width == manifest.canvasSize && image.height == manifest.canvasSize,
                "\(entry.name): rendered \(image.width)x\(image.height)"
            )

            let actual = try PixelDiff.raster(from: image)
            let (metrics, verdict) = try PixelDiff.compare(
                actual, to: expected, tolerance: manifest.tolerance
            )
            print("pixel diff \(entry.name): \(metrics.summary())")

            if case .differs(let reasons) = verdict {
                failures.append(entry.name)
                let report = try PixelDiffReport.write(
                    name: entry.name, actual: actual, expected: expected
                )
                Issue.record(Comment(rawValue: """
                    \(entry.name) does not match its reference.
                    \(reasons.joined(separator: "\n"))
                    \(metrics.summary())
                    \(report)
                    If this change is intended, regenerate: \(PixelDiffManifest.regenerationCommand)
                    """))
            }
        }

        #expect(
            failures.isEmpty,
            "\(failures.count) of \(manifest.entries.count) samples differ: \(failures.joined(separator: ", "))"
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

        let (metrics, _) = try PixelDiff.compare(first, to: second, tolerance: manifest.tolerance)
        #expect(metrics.maxChannelDifference == 0, "renderer is not deterministic: \(metrics.summary())")
    }

    /// `everySampleMatchesItsReference` renders twelve models through one web view to keep the
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
            afterAnother, to: alone, tolerance: manifest.tolerance
        )
        #expect(
            metrics.maxChannelDifference == 0,
            "\(subject.name) renders differently after \(predecessor.name): \(metrics.summary())"
        )
    }
}

// MARK: - Regeneration

/// Rewrites every reference PNG and the manifest. Off unless asked for — this is a generator,
/// not an assertion, and running it as part of a normal suite would make the tests agree with
/// whatever the renderer currently does.
///
///     ./scripts/regenerate-pixel-references.sh
///
/// Then look at the PNGs under `TestModels/References/` before committing them. They are the
/// assertions; a wrong one bakes in a wrong answer for good.
@MainActor
struct PixelDiffReferenceRegeneration {
    @Test(.enabled(if: PixelDiffRegeneration.isRequested))
    func regenerate() async throws {
        let models = TestModels.khronosGLBs
        try #require(!models.isEmpty, "no Khronos samples to render")

        var manifest = PixelDiffManifest(
            version: PixelDiffManifest.currentVersion,
            canvasSize: PixelDiffRenderer.canvasSize,
            environment: PixelDiffRenderer.environment,
            toneMapping: PixelDiffRenderer.toneMapping,
            tolerance: .default,
            entries: []
        )
        let host = try await PixelDiffRenderer.makeHost(manifest: manifest)

        for model in models {
            let name = model.deletingPathExtension().lastPathComponent
            let entry = PixelDiffManifest.Entry(
                name: name,
                model: model.path.replacingOccurrences(
                    of: TestFixtures.repoRoot.path + "/", with: ""
                ),
                reference: "\(name).png",
                camera: try await PixelDiffRenderer.recordPose(for: model, on: host)
            )

            // Rendered through the same call the comparison uses, so a reference can never
            // describe a path that verification does not take.
            let raster = try PixelDiff.raster(
                from: try await PixelDiffRenderer.render(entry, on: host)
            )
            try PixelDiff.write(raster, to: entry.referenceURL)

            // Read it straight back. A lossy write would produce references that disagree with
            // the renderer from the moment they are committed.
            let reread = try PixelDiff.raster(contentsOf: entry.referenceURL)
            #expect(reread == raster, "\(name): PNG round trip changed the image")

            manifest.entries.append(entry)
            print("regenerated \(entry.referenceURL.path)")
        }

        try manifest.write()
        print("regenerated \(PixelDiffPaths.manifestURL.path) with \(manifest.entries.count) entries")
    }
}
