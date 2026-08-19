import Foundation

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
