import Foundation
import Testing
@testable import GLBPreview

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
