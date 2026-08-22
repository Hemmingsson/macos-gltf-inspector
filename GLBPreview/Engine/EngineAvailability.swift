import Foundation

/// Availability for an `EngineSceneModel`, fed from `EntityLoader.LoadedModel.debugModes`
/// (not raw JSON on the document).
enum EngineAvailability {
    static func make(
        model: EngineSceneModel,
        debugModes: [PreviewDebugMode]
    ) -> DerivedAvailability<EngineSceneModel> {
        DerivedAvailability(
            model: model,
            channels: EngineSceneModel.mapDebugChannels(debugModes)
        )
    }

    @MainActor
    static func make(from loaded: EntityLoader.LoadedModel, fileName: String? = nil) -> DerivedAvailability<EngineSceneModel> {
        let model = EngineSceneModel(loaded: loaded, fileName: fileName)
        return make(model: model, debugModes: loaded.debugModes)
    }
}
