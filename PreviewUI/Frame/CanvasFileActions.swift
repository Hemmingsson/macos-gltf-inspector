import Foundation
import SwiftUI

/// Recent `.glb` / `.gltf` URLs for the empty canvas. The host fills this; an empty list hides the section.
private struct RecentGLTFURLsKey: EnvironmentKey {
    static let defaultValue: [URL] = []
}

/// Opens a file from the empty canvas. The host performs the document open.
public struct OpenGLTFFileAction {
    public var call: @MainActor (URL) -> Void

    public init(call: @escaping @MainActor (URL) -> Void) {
        self.call = call
    }

    @MainActor public func callAsFunction(_ url: URL) {
        call(url)
    }
}

private struct OpenGLTFFileKey: EnvironmentKey {
    static let defaultValue = OpenGLTFFileAction { _ in }
}

/// Shows the system Open panel.
public struct OpenFilePanelAction {
    public var call: @MainActor () -> Void

    public init(call: @escaping @MainActor () -> Void) {
        self.call = call
    }

    @MainActor public func callAsFunction() {
        call()
    }
}

private struct OpenFilePanelKey: EnvironmentKey {
    static let defaultValue = OpenFilePanelAction {}
}

/// Presents the Open Recent menu. SwiftUI `Menu` does not open inside `ContentUnavailableView`.
public struct OpenRecentMenuAction {
    public var call: @MainActor () -> Void

    public init(call: @escaping @MainActor () -> Void) {
        self.call = call
    }

    @MainActor public func callAsFunction() {
        call()
    }
}

private struct OpenRecentMenuKey: EnvironmentKey {
    static let defaultValue = OpenRecentMenuAction {}
}

/// Clears the Open Recent menu and tells the host to drop its list.
public struct ClearRecentFilesAction {
    public var call: @MainActor () -> Void

    public init(call: @escaping @MainActor () -> Void) {
        self.call = call
    }

    @MainActor public func callAsFunction() {
        call()
    }
}

private struct ClearRecentFilesKey: EnvironmentKey {
    static let defaultValue = ClearRecentFilesAction {}
}

/// Accepts a file drop on the canvas. Returning false rejects the drop.
public struct CanvasFileDropAction {
    public var call: @MainActor ([NSItemProvider]) -> Bool

    public init(call: @escaping @MainActor ([NSItemProvider]) -> Bool) {
        self.call = call
    }

    @MainActor public func callAsFunction(_ providers: [NSItemProvider]) -> Bool {
        call(providers)
    }
}

private struct CanvasFileDropKey: EnvironmentKey {
    static let defaultValue = CanvasFileDropAction { _ in false }
}

public extension EnvironmentValues {
    var recentGLTFURLs: [URL] {
        get { self[RecentGLTFURLsKey.self] }
        set { self[RecentGLTFURLsKey.self] = newValue }
    }

    var openGLTFFile: OpenGLTFFileAction {
        get { self[OpenGLTFFileKey.self] }
        set { self[OpenGLTFFileKey.self] = newValue }
    }

    var canvasFileDrop: CanvasFileDropAction {
        get { self[CanvasFileDropKey.self] }
        set { self[CanvasFileDropKey.self] = newValue }
    }

    var openFilePanel: OpenFilePanelAction {
        get { self[OpenFilePanelKey.self] }
        set { self[OpenFilePanelKey.self] = newValue }
    }

    var openRecentMenu: OpenRecentMenuAction {
        get { self[OpenRecentMenuKey.self] }
        set { self[OpenRecentMenuKey.self] = newValue }
    }

    var clearRecentFiles: ClearRecentFilesAction {
        get { self[ClearRecentFilesKey.self] }
        set { self[ClearRecentFilesKey.self] = newValue }
    }
}
