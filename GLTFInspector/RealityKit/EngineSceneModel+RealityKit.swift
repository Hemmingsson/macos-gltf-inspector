import GLTFCore
import PreviewUI
import RendererRealityKit

/// `EngineSceneModel` from a RealityKit load: the same document, plus convert's pipeline and
/// problem reports and the converted entity's visual bounds.
extension EngineSceneModel {
    /// Pass `validation: nil` while the Khronos run is pending; call again with `.success` /
    /// `.failed` / `.skipped` when it resolves.
    @MainActor
    init(
        loaded: EntityLoader.LoadedModel,
        fileName: String? = nil,
        validation: GLTFValidationState? = nil
    ) {
        self.init(
            fileName: fileName ?? loaded.name,
            document: loaded.document,
            stats: loaded.stats,
            dimensions: Self.mapDimensions(loaded),
            validation: validation,
            pipelineReport: Self.mapPipelineReport(loaded.pipelineReport),
            convertProblems: Self.mapConvertProblems(loaded.convertProblems),
            materialVariantNames: loaded.materialVariantNames
        )
    }

    static func mapConvertProblems(_ report: ConvertProblemReport) -> ConvertProblemList {
        ConvertProblemList(
            entries: report.items.map { item in
                ConvertProblemList.Entry(
                    severity: item.severity == .error ? .error : .warning,
                    title: item.message,
                    code: item.code.rawValue
                )
            }
        )
    }

    static func mapPipelineReport(_ report: RealityPipelineReport) -> PipelineReport {
        var entries: [PipelineReport.Entry] = report.conversionEntries.map {
            PipelineReport.Entry(kind: .conversion, title: $0)
        }
        entries.append(PipelineReport.Entry(kind: .lighting, title: report.lightingEntry))
        for name in report.extensionsUsed {
            entries.append(
                PipelineReport.Entry(kind: .conversion, title: name)
            )
        }
        return PipelineReport(entries: entries)
    }

    /// Converted entity's visual AABB; the authored glTF origin (entity local 0) is reported
    /// relative to its centre.
    @MainActor
    static func mapDimensions(_ loaded: EntityLoader.LoadedModel) -> Dimensions {
        let (dims, center) = loaded.extent
        let authored = Vector3(
            x: Double(-center.x),
            y: Double(-center.y),
            z: Double(-center.z)
        )
        return Dimensions(
            width: Double(dims?.width ?? 0),
            height: Double(dims?.height ?? 0),
            depth: Double(dims?.depth ?? 0),
            authoredOrigin: authored
        )
    }
}
