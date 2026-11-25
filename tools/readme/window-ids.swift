// Read-only inventory for finder-mockups.py. Use window IDs, not process IDs.
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard let id = window[kCGWindowNumber as String],
          let owner = window[kCGWindowOwnerName as String] as? String,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          (bounds["Width"] as? Double ?? 0) > 200,
          (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
    let title = window[kCGWindowName as String] as? String ?? "(untitled)"
    print("\(id)\t\(owner)\t\(title)")
}
