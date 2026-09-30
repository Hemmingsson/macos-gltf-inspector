import Foundation
import Testing

/// The renderer-neutral pixel-diff tests: the comparator and the manifest. Rendering and each
/// renderer's goldens are checked in `RealityKit/PixelDiffRealityKitTests.swift` and
/// `WebKit/PixelDiffWebKitTests.swift`.

// MARK: - The comparator itself

/// Pure image work — no renderer involved.
///
/// The comparator is the assertion. If it is capable of passing a wrong image then every model
/// test below is decoration, so its failure modes are tested directly rather than only being
/// demonstrated by hand once.
struct PixelDiffComparisonTests {
    /// The first reference on disk, with its renderer's budget. The comparator is
    /// renderer-agnostic; one real reference is enough to exercise it.
    private func loadFirstReference() throws -> (PixelDiff.Tolerance, PixelDiff.Raster) {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first)
        let renderer = try #require(PixelDiffRendererKind.allCases.first {
            FileManager.default.fileExists(atPath: entry.referenceURL(for: $0).path)
        }, "no reference PNG for \(entry.name)")
        return (
            try manifest.tolerance(for: renderer),
            try PixelDiff.raster(contentsOf: entry.referenceURL(for: renderer))
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
}
