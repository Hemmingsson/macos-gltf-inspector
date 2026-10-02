import GLTFCore
import GLTFKit2
import RealityKit

/// Holds the convert-time raster placeholders so the same `TextureResource` instances can be
/// replaced after the first RealityKit frame. Retains the parsed asset so `GLTFImage` buffers
/// stay valid until replace finishes.
@MainActor
final class DeferredTextureReplace {
    private let context: RealityKitResourceContext
    private let asset: GLTFAsset
    private var inFlight: Task<Void, Never>?

    var hasPending: Bool { context.hasPendingRasters }

    init(context: RealityKitResourceContext, asset: GLTFAsset) {
        self.context = context
        self.asset = asset
        _ = DeferredTextureReplaceComponent.register
    }

    func replaceRemaining(isLive: @escaping @MainActor () -> Bool) async {
        if let inFlight {
            await inFlight.value
            return
        }
        guard context.hasPendingRasters else { return }
        let count = context.pendingRasterCount
        let work = Task { @MainActor in
            let interval = AppLog.signposter.beginInterval("convert.textures")
            defer { AppLog.signposter.endInterval("convert.textures", interval) }
            await self.context.replacePendingRasters(shouldContinue: isLive)
            if !self.context.hasPendingRasters {
                AppLog.info(
                    AppLog.preview,
                    "rk textures final count=\(count) uptimeMs=\(AppLog.uptimeMs())"
                )
            }
        }
        inFlight = work
        await work.value
        inFlight = nil
        withExtendedLifetime(asset) {}
    }

    static func attachIfNeeded(
        context: RealityKitResourceContext,
        asset: GLTFAsset,
        onto entity: Entity
    ) {
        guard context.hasPendingRasters else { return }
        entity.components.set(
            DeferredTextureReplaceComponent(job: DeferredTextureReplace(context: context, asset: asset))
        )
    }

    static func job(on root: Entity) -> DeferredTextureReplace? {
        if let job = root.components[DeferredTextureReplaceComponent.self]?.job {
            return job
        }
        for child in root.children {
            if let found = job(on: child) { return found }
        }
        return nil
    }

    static func finalize(
        attachedTo root: Entity,
        isLive: @escaping @MainActor () -> Bool = { true }
    ) async {
        guard let job = job(on: root) else { return }
        await job.replaceRemaining(isLive: isLive)
    }
}

/// Not `Codable` — the job holds Metal / GLTFKit2 objects that must not persist.
private struct DeferredTextureReplaceComponent: TransientComponent {
    var job: DeferredTextureReplace

    static let register: Void = {
        DeferredTextureReplaceComponent.registerComponent()
    }()
}
