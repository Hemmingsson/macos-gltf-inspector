import Foundation

enum MetalResourceLimits {
    static let maxSingleAllocationBytes = 256 * 1024 * 1024
    static let maxDecodedImageBytes = 128 * 1024 * 1024
    static let maxStillBytes = 256 * 1024 * 1024
    static let maxImageDimension = 16_384

    static func product(_ lhs: Int, _ rhs: Int, label: String, limit: Int? = nil) throws -> Int {
        guard lhs >= 0, rhs >= 0 else {
            throw MetalSceneError.invalid("\(label) is negative")
        }
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow, limit.map({ value <= $0 }) ?? true else {
            throw MetalSceneError.invalid("\(label) is too large")
        }
        return value
    }

    static func sum(_ lhs: Int, _ rhs: Int, label: String, limit: Int? = nil) throws -> Int {
        guard lhs >= 0, rhs >= 0 else {
            throw MetalSceneError.invalid("\(label) is negative")
        }
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, limit.map({ value <= $0 }) ?? true else {
            throw MetalSceneError.invalid("\(label) is too large")
        }
        return value
    }
}
