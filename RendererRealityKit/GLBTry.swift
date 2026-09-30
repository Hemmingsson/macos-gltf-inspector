import Foundation
import GLTFCore

enum GLBTry {
    static func run(_ work: () -> Void) throws {
        var error: NSError?
        if !GLBCatchNSException(work, error: &error) {
            throw error ?? GLTFInspectorError.make(1023, "Unknown exception")
        }
    }
}
