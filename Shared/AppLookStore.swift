import Foundation

@MainActor
@Observable
final class AppLookStore {
    static let shared = AppLookStore(directory: AppLook.supportDirectory())

    private let directory: URL
    var look: AppLook

    init(directory: URL) {
        self.directory = directory
        self.look = AppLook.load(from: directory)
    }

    func apply(_ look: AppLook) {
        self.look = look
        look.save(to: directory)
    }

    func reloadFromDisk() {
        look = AppLook.load(from: directory)
    }
}
