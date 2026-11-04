import Combine
import Foundation
import Sparkle
import SwiftUI

/// Sparkle reads its feed and key from the `SU*` Info.plist keys (`project.yml`); the app only
/// decides whether to start the updater.
enum UpdateConfig {
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
