import Cocoa
import QuickLookUI
import SwiftUI

class PreviewViewController: NSViewController, QLPreviewingController {
    private let interaction = GLBPreviewInteraction()
    private var hostingView: GLBPreviewHostingView!

    override func loadView() {
        GLBLog.processBanner("ql-loadView")
        GLBWindowLog.start()
        let dark = Self.systemIsDark()
        let backdrop = GLBPreviewBackdrop.cgColor(dark: dark)
        GLBLog.event(GLBLog.preview, "QL loadView dark=\(dark)")

        hostingView = GLBPreviewHostingView(
            rootView: GLBPreviewView(state: .loading, interaction: interaction, isDark: dark)
        )
        hostingView.interaction = interaction
        hostingView.wantsLayer = true
        hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hostingView.layer?.backgroundColor = backdrop
        hostingView.autoresizingMask = [.width, .height]

        let root = GLBPreviewEventView(frame: .zero)
        root.interaction = interaction
        root.wantsLayer = true
        root.layer?.backgroundColor = backdrop
        root.addSubview(hostingView)
        view = root
        GLBLog.event(GLBLog.window, "QL root view created hosting=\(hostingView.frame)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        GLBLog.event(GLBLog.window, "QL viewDidLoad bounds=\(NSStringFromRect(view.bounds))")
        GLBWindowLog.dumpWindows("ql-viewDidLoad")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        GLBLog.event(GLBLog.window, "QL viewDidAppear")
        if let window = view.window {
            GLBLog.event(GLBLog.window, "QL window \(GLBWindowLog.describe(index: nil, window: window))")
        } else {
            GLBLog.event(GLBLog.window, "QL viewDidAppear with no window yet")
        }
        GLBWindowLog.dumpWindows("ql-viewDidAppear")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        hostingView.frame = view.bounds
        GLBWindowLog.layoutIfChanged(view, reason: "ql-layout")
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        GLBLog.event(GLBLog.window, "QL viewWillDisappear")
        GLBWindowLog.dumpWindows("ql-viewWillDisappear")
    }

    func preparePreviewOfFile(at url: URL) async throws {
        GLBLog.event(GLBLog.preview, "QL preparePreviewOfFile \(GLBLog.describeURL(url))")
        let dark = Self.systemIsDark()
        let state = await GLBPreviewView.State.loaded(from: url)
        let failed: Bool
        if case .failed = state { failed = true } else { failed = false }
        GLBLog.event(GLBLog.preview, "QL prepare finished failed=\(failed) dark=\(dark)")
        await MainActor.run {
            hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            hostingView.rootView = GLBPreviewView(state: state, interaction: interaction, isDark: dark)
            GLBWindowLog.dumpWindows("ql-after-prepare")
        }
    }

    private static func systemIsDark() -> Bool {
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        }
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}
