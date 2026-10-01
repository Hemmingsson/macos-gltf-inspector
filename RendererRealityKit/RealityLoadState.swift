import Foundation

/// Convert state shared by the document window and Quick Look. Loading and failure chrome
/// stay at each host: PreviewUI's `CanvasRegion` for the window, `QuickLookRealityView` for QL.
public enum RealityLoadState {
    case loading
    case ready(EntityLoader.LoadedModel)
    /// User-visible reason. Open never waits on IBL — lighting is applied later by `PreviewScene`.
    case failed(String)

    /// Model bytes → RealityKit only. No HDR / EnvironmentResource on this path.
    public static func loaded(from url: URL) async -> RealityLoadState {
        do {
            return .ready(try await EntityLoader.load(from: url))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
