import Foundation
import GLTFCore
import SwiftUI

/// The one host spot that picks a renderer. Everything renderer-specific lives in the adapter
/// folders `RealityKit/` and `WebKit/`; each case here is guarded by `canImport`, so deleting a
/// renderer (framework target + adapter folders) needs no edit in this file.
enum RendererRouter {
    /// Renderers linked into this build.
    static var available: [RendererKind] {
        var kinds: [RendererKind] = []
        #if canImport(RendererRealityKit)
        kinds.append(.realityKit)
        #endif
        #if canImport(RendererWebKit)
        kinds.append(.webKit)
        #endif
        return kinds
    }

    /// Debug builds take a `-GLTFRenderer realitykit|webkit` launch argument over the stored switch,
    /// so a scripted real-window check can pick a renderer without writing the App Group.
    static var launchOverride: RendererKind? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "GLTFRenderer").flatMap(RendererKind.init(rawValue:))
        #else
        nil
        #endif
    }

    /// What a window opening now uses: override, else the App Group switch, limited to what is linked.
    static func current(stored: RendererKind = RendererKind.stored()) -> RendererKind {
        resolve(launchOverride ?? stored)
    }

    static func resolve(_ kind: RendererKind) -> RendererKind {
        available.contains(kind) ? kind : (available.first ?? kind)
    }
}

/// Document window root: reads the renderer once, when the window opens, and mounts that
/// renderer's window. Switching affects windows opened afterwards.
struct DocumentWindowRouter: View {
    let documentURL: URL?
    @State private var kind: RendererKind

    init(documentURL: URL?, kind: RendererKind = RendererRouter.current()) {
        self.documentURL = documentURL
        _kind = State(initialValue: kind)
    }

    var body: some View {
        switch kind {
        case .realityKit:
            #if canImport(RendererRealityKit)
            RealityDocumentWindow(documentURL: documentURL)
            #else
            EmptyView()
            #endif
        case .webKit:
            #if canImport(RendererWebKit)
            WebDocumentWindow(documentURL: documentURL)
            #else
            EmptyView()
            #endif
        }
    }
}
