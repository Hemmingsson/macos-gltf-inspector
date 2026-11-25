import Foundation

enum GLTFResourceLimits {
    static let maxSourceBytes = 256 * 1024 * 1024
    static let maxJSONBytes = 16 * 1024 * 1024
    static let maxBufferBytes = 256 * 1024 * 1024
    static let maxImageBytes = 32 * 1024 * 1024
    static let maxDataURIBytes = 32 * 1024 * 1024
    static let maxAccessorElements = 10_000_000
}

enum GLTFResourceIO {
    static func read(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit.addingReportingOverflow(1).partialValue) ?? Data()
        guard data.count <= limit else {
            throw GLTFResourceError.tooLarge(limit: limit)
        }
        return data
    }

    static func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size >= 0 else {
            throw GLTFResourceError.unreadable
        }
        return size
    }
}

enum GLTFResourceError: Swift.Error, LocalizedError, Equatable {
    case tooLarge(limit: Int)
    case unreadable
    case invalidURI

    var errorDescription: String? {
        switch self {
        case .tooLarge(let limit):
            return "A referenced glTF resource exceeds the \(limit / (1024 * 1024)) MB safety limit."
        case .unreadable:
            return "A glTF resource could not be read."
        case .invalidURI:
            return "A glTF resource URI is invalid or escapes the model directory."
        }
    }
}
