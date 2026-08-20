import Foundation
import Sparkle
import SwiftUI

enum GLBUpdateConfig {
    static let githubRepo = "Hemmingsson/macos-gltf-preview"
    static let placeholderPublicEdKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    static let feedURL = URL(
        string: "https://github.com/\(githubRepo)/releases/latest/download/appcast.xml"
    )!

    /// Ed25519 public key from `generate_keys`. Same string as `SUPublicEDKey`.
    static let publicEdKey = placeholderPublicEdKey

#if DEBUG
    static let shouldStartUpdater = false
#else
    static let shouldStartUpdater = true
#endif
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}
