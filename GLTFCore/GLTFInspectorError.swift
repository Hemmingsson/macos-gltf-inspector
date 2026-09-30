import Foundation

/// `NSError` factory for load / convert failures, in the app's one error domain.
public enum GLTFInspectorError {
    public static let domain = "lol.mattias.gltf-inspector"

    public static func make(_ code: Int, _ message: String) -> NSError {
        NSError(
            domain: domain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
