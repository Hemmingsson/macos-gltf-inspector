import Foundation

enum GLBPreviewError {
    static let domain = "GLBPreview"

    static func make(_ code: Int, _ message: String) -> NSError {
        NSError(
            domain: domain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

enum GLBTry {
    static func run(_ work: () -> Void) throws {
        var error: NSError?
        if !GLBCatchNSException(work, error: &error) {
            throw error ?? GLBPreviewError.make(1023, "Unknown exception")
        }
    }
}
