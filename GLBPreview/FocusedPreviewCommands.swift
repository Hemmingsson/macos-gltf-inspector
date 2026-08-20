import SwiftUI

@MainActor
struct FocusedPreviewCommands {
    let fit: () -> Void
}

extension FocusedValues {
    @Entry var previewCommands: FocusedPreviewCommands?
}
