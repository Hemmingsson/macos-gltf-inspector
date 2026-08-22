import Foundation
import JavaScriptCore

/// Issue from the Khronos glTF-Validator report (`issues.messages[]`).
struct GLTFValidationIssue: Sendable, Equatable, Identifiable {
    var id: String { "\(severity)-\(code)-\(pointer ?? "")-\(message)" }
    var code: String
    var message: String
    /// 0 = error, 1 = warning, 2 = info, 3 = hint (Khronos severity).
    var severity: Int
    var pointer: String?

    var isError: Bool { severity == 0 }
    var isWarning: Bool { severity == 1 }
}

/// Mapped Khronos validation report for inspector honesty (P17).
struct GLTFValidationReport: Sendable, Equatable {
    var validatorVersion: String
    var errorCount: Int
    var warningCount: Int
    var infoCount: Int
    var hintCount: Int
    var messages: [GLTFValidationIssue]

    /// Green badge when there are no errors or warnings (infos/hints OK).
    var isClean: Bool { errorCount == 0 && warningCount == 0 }

    /// Orange badge count — errors + warnings (matches Inspect mock “N warnings”).
    var badgeCount: Int { errorCount + warningCount }

    var badgeTitle: String {
        if isClean { return "Valid glTF 2.0" }
        if errorCount > 0 {
            return badgeCount == 1 ? "1 issue" : "\(badgeCount) issues"
        }
        return warningCount == 1 ? "1 warning" : "\(warningCount) warnings"
    }
}

/// Host sidebar outcome for P17 — success report, soft failure, or intentional skip.
enum GLTFValidationState: Sendable, Equatable {
    case success(GLTFValidationReport)
    case failed(String)
    case skipped(String)

    var badgeTitle: String {
        switch self {
        case .success(let report): report.badgeTitle
        case .failed(let message): message
        case .skipped(let message): message
        }
    }

    var report: GLTFValidationReport? {
        if case .success(let report) = self { return report }
        return nil
    }
}

/// Runs the official Khronos `gltf-validator` (Dart→JS) inside `JavaScriptCore`.
/// Does not block model open — call after first paint.
enum GLTFValidator {
    private static let scriptName = "gltf_validator.dart.js"
    private static let queue = DispatchQueue(label: "com.laurie.GLBPreview.gltf-validator", qos: .utility)

    /// Raw file/byte ceiling before base64→JavaScriptCore.
    /// Above this we soft-skip: Dart validator expands the asset via `atob` into a `Uint8Array`
    /// (~4/3 of raw size as base64 string, then another full copy as bytes), which can OOM.
    static let maxRawAssetBytes = 48 * 1024 * 1024

    enum Error: Swift.Error, LocalizedError, Equatable {
        case scriptMissing
        case contextFailed
        case invalidReport
        case assetTooLarge(byteCount: Int, limit: Int)
        case validator(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing:
                return "Khronos glTF-Validator script missing from the app bundle."
            case .contextFailed:
                return "Could not create a JavaScriptCore context for validation."
            case .invalidReport:
                return "Validator returned an unreadable report."
            case .assetTooLarge(let byteCount, let limit):
                let mb = Double(byteCount) / (1024 * 1024)
                let limitMB = limit / (1024 * 1024)
                return String(
                    format: "File is too large to validate in-process (%.1f MB; limit %d MB).",
                    mb,
                    limitMB
                )
            case .validator(let message):
                return message
            }
        }

        /// Soft-skip (size guard) vs hard unavailable (script/JSC/report failures).
        var isSoftSkip: Bool {
            if case .assetTooLarge = self { return true }
            return false
        }
    }

    static func validate(fileAt url: URL, maxIssues: Int = 100) async throws -> GLTFValidationReport {
        try rejectIfTooLarge(url: url)
        let data = try Data(contentsOf: url)
        let base = url.deletingLastPathComponent()
        return try await validate(data: data, uri: url.lastPathComponent, externalBase: base, maxIssues: maxIssues)
    }

    static func validate(
        data: Data,
        uri: String,
        externalBase: URL?,
        maxIssues: Int = 100
    ) async throws -> GLTFValidationReport {
        try rejectIfTooLarge(byteCount: data.count)
        try Task.checkCancellation()
        // Cancellation does not abort in-flight JSC work on `queue`; callers cancel their
        // Task and ignore stale generations / CancellationError after resume.
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let report = try validateSync(
                        data: data,
                        uri: uri,
                        externalBase: externalBase,
                        maxIssues: maxIssues
                    )
                    continuation.resume(returning: report)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func rejectIfTooLarge(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize {
            try rejectIfTooLarge(byteCount: size)
        }
    }

    private static func rejectIfTooLarge(byteCount: Int) throws {
        if byteCount > maxRawAssetBytes {
            throw Error.assetTooLarge(byteCount: byteCount, limit: maxRawAssetBytes)
        }
    }

    private static func validateSync(
        data: Data,
        uri: String,
        externalBase: URL?,
        maxIssues: Int
    ) throws -> GLTFValidationReport {
        guard let ctx = JSContext() else { throw Error.contextFailed }
        var lastException: String?
        ctx.exceptionHandler = { _, value in
            lastException = value?.toString()
        }

        ctx.evaluateScript(preludeSource)
        if let lastException { throw Error.validator(lastException) }

        let script = try loadScriptSource()
        ctx.evaluateScript(script)
        if let lastException { throw Error.validator(lastException) }

        let hasValidate = ctx.evaluateScript("typeof exports.validateBytes === 'function'")?.toBool() ?? false
        guard hasValidate else { throw Error.contextFailed }

        let base64 = data.base64EncodedString()
        ctx.setObject(base64, forKeyedSubscript: "__assetB64" as NSString)
        ctx.setObject(uri, forKeyedSubscript: "__assetURI" as NSString)
        ctx.setObject(maxIssues, forKeyedSubscript: "__maxIssues" as NSString)

        if let externalBase {
            let load: @convention(block) (String) -> String? = { relative in
                let decoded = relative.removingPercentEncoding ?? relative
                let fileURL = externalBase.appendingPathComponent(decoded)
                guard let bytes = try? Data(contentsOf: fileURL) else { return nil }
                return bytes.base64EncodedString()
            }
            ctx.setObject(load, forKeyedSubscript: "__loadExternalBase64" as NSString)
            ctx.evaluateScript("__hasExternalLoader = true;")
        } else {
            ctx.evaluateScript("__hasExternalLoader = false;")
        }

        ctx.evaluateScript(runnerSource)
        if let lastException { throw Error.validator(lastException) }

        // Dart schedules work via setTimeout/setImmediate — drain our queue until done.
        for _ in 0..<2_000 {
            ctx.evaluateScript("__drain()")
            if ctx.evaluateScript("__done")?.toBool() == true { break }
            Thread.sleep(forTimeInterval: 0.002)
        }

        if let err = ctx.evaluateScript("__err")?.toString(), err != "null", !err.isEmpty, err != "<null>" {
            throw Error.validator(err)
        }
        guard let json = ctx.evaluateScript("__out")?.toString(),
              json != "null",
              let payload = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else {
            throw Error.invalidReport
        }
        return try parseReport(root)
    }

    private static func loadScriptSource() throws -> String {
        if let url = Bundle.main.url(forResource: "gltf_validator.dart", withExtension: "js")
            ?? Bundle.main.url(forResource: scriptName, withExtension: nil)
            ?? Bundle(for: BundleToken.self).url(forResource: "gltf_validator.dart", withExtension: "js")
        {
            return try String(contentsOf: url, encoding: .utf8)
        }
        // Worktree / test without copied resource: Vendor path next to sources.
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Vendor/gltf-validator/\(scriptName)"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/gltf-validator/\(scriptName)"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        throw Error.scriptMissing
    }

    private static func parseReport(_ root: [String: Any]) throws -> GLTFValidationReport {
        let issues = root["issues"] as? [String: Any] ?? [:]
        let messagesJSON = issues["messages"] as? [[String: Any]] ?? []
        let messages: [GLTFValidationIssue] = messagesJSON.map { item in
            GLTFValidationIssue(
                code: item["code"] as? String ?? "UNKNOWN",
                message: item["message"] as? String ?? "",
                severity: item["severity"] as? Int ?? 2,
                pointer: item["pointer"] as? String
            )
        }
        return GLTFValidationReport(
            validatorVersion: root["validatorVersion"] as? String ?? "unknown",
            errorCount: issues["numErrors"] as? Int ?? messages.filter(\.isError).count,
            warningCount: issues["numWarnings"] as? Int ?? messages.filter(\.isWarning).count,
            infoCount: issues["numInfos"] as? Int ?? 0,
            hintCount: issues["numHints"] as? Int ?? 0,
            messages: messages
        )
    }

    private static let preludeSource = """
    var exports = {};
    var module = { exports: exports };
    var process = { env: {}, versions: {}, cwd: function() { return "/"; } };
    var self = this;
    var window = this;
    var globalThis = this;
    var document = { currentScript: { src: "gltf_validator.dart.js" }, scripts: [] };
    var __macrotasks = [];
    function setTimeout(fn, ms) { __macrotasks.push(fn); return __macrotasks.length; }
    function clearTimeout(id) {}
    function setImmediate(fn) { __macrotasks.push(fn); }
    function __drain() {
      var n = 0;
      while (__macrotasks.length && n < 256) {
        var fn = __macrotasks.shift();
        n++;
        try { fn(); } catch (e) { __err = String(e); __done = true; break; }
      }
    }
    function atob(input) {
      var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
      var str = String(input).replace(/=+$/, "");
      var output = "";
      if (str.length % 4 === 1) throw new Error("atob failed");
      for (var bc = 0, bs, buffer, idx = 0; buffer = str.charAt(idx++);
           ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4)
             ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
        buffer = chars.indexOf(buffer);
      }
      return output;
    }
    function __bytesFromBase64(b64) {
      var bin = atob(b64);
      var arr = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
      return arr;
    }
    """

    private static let runnerSource = """
    var __done = false;
    var __out = null;
    var __err = null;
    var __options = {
      uri: __assetURI,
      writeTimestamp: false,
      maxIssues: __maxIssues
    };
    if (__hasExternalLoader) {
      __options.externalResourceFunction = function(uri) {
        return new Promise(function(resolve, reject) {
          var b64 = __loadExternalBase64(uri);
          if (!b64) { reject("Missing external resource: " + uri); return; }
          resolve(__bytesFromBase64(b64));
        });
      };
    }
    try {
      exports.validateBytes(__bytesFromBase64(__assetB64), __options)
        .then(function(report) { __out = JSON.stringify(report); __done = true; })
        .catch(function(e) { __err = String(e); __done = true; });
    } catch (e) {
      __err = String(e);
      __done = true;
    }
    """
}

private final class BundleToken {}
