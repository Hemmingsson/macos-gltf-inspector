import GLTFCore
import SwiftUI

#if DEBUG
/// Debug-only Develop menu: the hidden renderer switch. Writes the App Group suite (the only
/// process that can — `defaults write` from a shell lands in another domain), so the next
/// document window, Quick Look preview and Finder thumbnail use the chosen renderer. Open windows
/// keep theirs.
struct DevelopMenuCommands: View {
    @State private var kind = RendererKind.stored()

    var body: some View {
        Picker("Renderer", selection: $kind) {
            ForEach(RendererKind.allCases, id: \.self) { kind in
                Text(Self.title(kind)).tag(kind)
            }
        }
        .onChange(of: kind) { _, kind in
            RendererKind.store(kind)
            AppLog.info(AppLog.host, "renderer switch \(kind.rawValue) (new windows)")
        }
    }

    private static func title(_ kind: RendererKind) -> String {
        let name = switch kind {
        case .realityKit: "RealityKit"
        case .webKit: "WebKit"
        }
        return RendererRouter.available.contains(kind) ? name : "\(name) (not linked)"
    }
}
#endif
