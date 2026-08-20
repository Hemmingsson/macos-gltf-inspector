import Combine
import Foundation
import Sparkle
import SwiftUI

enum GLBUpdateConfig {
    static let githubRepo = "Hemmingsson/macos-gltf-preview"
    static let placeholderPublicEdKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

    static let githubURL = URL(string: "https://github.com/\(githubRepo)")!
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

@Observable
final class CheckForUpdatesViewModel {
    var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }
}

struct CheckForUpdatesView: View {
    @State private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = State(initialValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
