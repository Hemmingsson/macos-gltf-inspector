import Foundation
import Testing
@testable import GLBPreview

struct AppLookTests {
    @Test func defaultLookUsesStudioNeutralWithoutCustomFile() {
        let look = AppLook.default
        #expect(look.useEnvironmentMap)
        #expect(look.catalogRaw == KhronosEnvironments.studioNeutral.rawValue)
        #expect(look.catalog == .studioNeutral)
        #expect(look.customFileName == nil)
    }

    @Test func roundTripJSONInTempDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("applook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var look = AppLook.default
        look.useEnvironmentMap = false
        look.catalogRaw = KhronosEnvironments.field.rawValue
        look.customFileName = "studio.hdr"
        look.save(to: dir)

        let loaded = AppLook.load(from: dir)
        #expect(loaded == look)
        #expect(loaded.catalog == .field)
        #expect(FileManager.default.fileExists(atPath: AppLook.lookURL(in: dir).path))
    }

    @Test func corruptJSONFallsBackToDefault() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("applook-bad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("{not-json".utf8).write(to: AppLook.lookURL(in: dir))
        #expect(AppLook.load(from: dir) == .default)
    }

    @Test func unknownCatalogFallsBackToStudioNeutral() {
        var look = AppLook.default
        look.catalogRaw = "pisa"
        #expect(look.catalog == .studioNeutral)
    }

    @Test func unknownCatalogMigratesOnLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("applook-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var look = AppLook.default
        look.catalogRaw = "pisa"
        look.save(to: dir)

        let loaded = AppLook.load(from: dir)
        #expect(loaded.catalogRaw == KhronosEnvironments.studioNeutral.rawValue)
        #expect(loaded.catalog == .studioNeutral)
        #expect(AppLook.load(from: dir).catalogRaw == KhronosEnvironments.studioNeutral.rawValue)
    }

    @Test func customFileNameResolvesUnderIBL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("applook-ibl-\(UUID().uuidString)")
        let ibl = AppLook.iblDirectory(in: dir)
        try FileManager.default.createDirectory(at: ibl, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileName = "mine.hdr"
        let dest = ibl.appendingPathComponent(fileName)
        try Data("hdr".utf8).write(to: dest)

        var look = AppLook.default
        look.customFileName = fileName
        let resolved = try #require(look.resolvedHDRURL(in: dir))
        #expect(resolved.lastPathComponent == fileName)
        #expect(resolved.deletingLastPathComponent().lastPathComponent == "ibl")
        #expect(resolved.path == dest.path)
    }
}
