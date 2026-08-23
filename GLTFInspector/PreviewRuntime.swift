import Foundation

/// True while Xcode is hosting a SwiftUI canvas preview (`XCODE_RUNNING_FOR_PREVIEWS=1`).
enum PreviewRuntime {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
