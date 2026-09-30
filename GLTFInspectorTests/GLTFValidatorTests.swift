import Foundation
@testable import GLTFCore
import Testing
@testable import GLTFInspector

struct GLTFValidatorTests {
    @Test func invalidUnresolvedMeshReportsErrors() async throws {
        let url = TestFixtures.invalid
        let report = try await GLTFValidator.validate(fileAt: url)
        #expect(report.errorCount >= 1)
        #expect(report.badgeCount >= 1)
        #expect(!report.isClean)
        #expect(report.messages.contains { $0.code == "UNRESOLVED_REFERENCE" })
        #expect(report.validatorVersion.contains("2.0.0"))
    }

    @Test func cubeFixtureIsCleanOrInfoOnly() async throws {
        let url = TestFixtures.cube
        let report = try await GLTFValidator.validate(fileAt: url)
        #expect(report.errorCount == 0)
        #expect(report.isClean || report.warningCount == 0)
    }

    @Test func oversizedAssetSoftFailsWithoutEnteringJSC() async {
        let overLimit = GLTFValidator.maxRawAssetBytes + 1
        let data = Data(count: overLimit)
        do {
            _ = try await GLTFValidator.validate(data: data, uri: "huge.glb", externalBase: nil)
            Issue.record("Expected assetTooLarge soft-fail")
        } catch let error as GLTFValidator.Error {
            #expect(error.isSoftSkip)
            #expect(error == .assetTooLarge(byteCount: overLimit, limit: GLTFValidator.maxRawAssetBytes))
            #expect(error.localizedDescription.contains("too large"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

/// The embedded Khronos validator over every committed fixture and every pinned sample.
///
/// A file the validator rejects is a bad input, not a renderer bug; this keeps the test corpus
/// honest so a golden never enshrines an invalid file. Warnings and infos are allowed (e.g. an
/// extension newer than the validator is reported as unsupported). Errors fail unless the file
/// is on ``expectedErrors`` with a reason. No `.enabled(if:)` gate: a missing pinned sample
/// fails here like it does in the pixel harness.
struct GLTFValidatorCorpusTests {
    /// Fixtures that are broken on purpose, keyed by path relative to `TestModels/Fixture Models`.
    static let expectedErrors: [String: String] = [
        "invalid/unresolved-mesh.gltf": "deliberately references a mesh that does not exist",
        "corrupt/truncated.glb": "deliberately truncated GLB",
        "missing-texture/missing-image.gltf": "deliberately points at an image that is not on disk",
    ]

    static var fixtures: [URL] {
        let root = TestFixtures.url("TestModels/Fixture Models")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        return (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { ["gltf", "glb"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
    }

    @Test func everyFixtureValidatesOrIsAnExpectedFailure() async throws {
        let root = TestFixtures.url("TestModels/Fixture Models").path + "/"
        let files = Self.fixtures
        #expect(files.count >= 10, "fixture enumeration found only \(files.count) files")
        for url in files {
            let relative = url.path.replacingOccurrences(of: root, with: "")
            let errors: [String]
            do {
                let report = try await GLTFValidator.validate(fileAt: url)
                errors = report.messages.filter(\.isError).map { "\($0.code) \($0.pointer ?? "")" }
            } catch {
                errors = ["validator threw: \(error)"]
            }
            if let reason = Self.expectedErrors[relative] {
                #expect(!errors.isEmpty, "\(relative) is allow-listed (\(reason)) but now validates clean")
            } else {
                #expect(errors.isEmpty, "\(relative): \(errors.joined(separator: "; "))")
            }
        }
    }

    @Test func everyPinnedSampleValidates() async throws {
        let manifest = try PixelDiffManifest.load()
        try #require(!manifest.entries.isEmpty)
        for entry in manifest.entries {
            let report = try await GLTFValidator.validate(fileAt: entry.modelURL)
            let errors = report.messages.filter(\.isError).map { "\($0.code) \($0.pointer ?? "")" }
            #expect(report.errorCount == 0, "\(entry.name): \(errors.joined(separator: "; "))")
            print("validator \(entry.name): \(report.errorCount) errors, \(report.warningCount) warnings")
        }
    }
}
