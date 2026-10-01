import CoreGraphics
import Foundation
import GLTFCore
import RealityKit
import Testing
@testable import RendererRealityKit

/// RealityKit half of the opt-in bench.
///
/// `rk.window` is the document window / Quick Look open: `EntityLoader.load`, split into parse,
/// meshes (convert nodes minus textures), textures and clips, then an offscreen `StillRenderer`
/// frame as the first-frame proxy (the live app logs `rk first frame` instead). `tex cgimage` is
/// only the lazy `CGImage` wrapper; the pixel decode runs inside `TextureResource`, so it lands
/// in `tex decode+upload`. `load rest` is load minus convert; `json …` time its JSON-side parts.
/// `rk.thumb` is the Finder icon path (`RealityThumbnail.render`, split). `rk.mode` times
/// `PreviewDebugMode.apply` per transition plus the first offscreen frame after each new mode;
/// `rk.skeleton` times the overlay on rigged files.
extension PerfBench {
    @MainActor
    @Suite struct RealityKitBench {
        private static let background = CGColor(gray: 0.94, alpha: 1)

        @Test func firstPixel() async throws {
            // Static per process: the first window / icon pays the HDR decode, later ones do not.
            let iblStart = ContinuousClock.now
            await PreviewLighting.prefetchLook(.current)
            BenchReport.row("rk.ibl", "studio", "prefetch (cold)", [BenchClock.ms(since: iblStart)])

            for file in BenchCorpus.files {
                var samples: [String: [Double]] = [:]
                func add(_ metric: String, _ value: Double) { samples[metric, default: []].append(value) }
                for _ in 0..<PerfBench.runs {
                    try await window(file.url, add)
                    try await thumbnail(file.url, add)
                }
                for metric in Self.metricOrder {
                    guard let values = samples[metric] else { continue }
                    let section = metric.hasPrefix("thumb ") ? "rk.thumb" : "rk.window"
                    let name = metric.hasPrefix("thumb ") ? String(metric.dropFirst(6)) : metric
                    BenchReport.row(section, file.name, name, values)
                }
            }
        }

        private static let metricOrder = [
            "parse", "meshes", "tex cgimage", "tex decode+upload", "clips", "load", "load rest", "json document",
            "json stats", "first frame", "total",
            "thumb load", "thumb still", "thumb total",
        ]

        private func window(_ url: URL, _ add: (String, Double) -> Void) async throws {
            let start = ContinuousClock.now
            let model = try await EntityLoader.load(from: url)
            let loaded = ContinuousClock.now
            let timings = model.timings
            let textures = timings.textureDecode + timings.textureUpload
            add("parse", BenchClock.ms(timings.parse))
            add("meshes", BenchClock.ms(timings.nodes - textures))
            add("tex cgimage", BenchClock.ms(timings.textureDecode))
            add("tex decode+upload", BenchClock.ms(timings.textureUpload))
            add("clips", BenchClock.ms(timings.clips))
            add("load", BenchClock.ms(loaded - start))
            add("load rest", BenchClock.ms(loaded - start - timings.parse - timings.nodes - timings.clips))
            jsonSide(url, add)
            let assembled = PreviewCamera.makeTurntable(for: model.entity)
            let still = try await StillRenderer(
                root: assembled.pivot,
                bounds: assembled.bounds,
                width: PerfBench.stillSize,
                height: PerfBench.stillSize,
                background: Self.background,
                padding: PreviewCamera.previewFitPadding,
                intensityExponent: model.studioIBLExponent
            )
            _ = try await still.capture()
            add("first frame", BenchClock.ms(since: loaded))
            add("total", BenchClock.ms(since: start))
        }

        /// The JSON-side work `load` does besides convert (sidebar document, overlay stats,
        /// debug-mode list), timed on their own to explain `load rest`.
        private func jsonSide(_ url: URL, _ add: (String, Double) -> Void) {
            guard let json = try? GLBBox.peekJSON(from: url) else { return }
            var start = ContinuousClock.now
            _ = GLTFDocumentJSON.makeDocument(json: json, fileURL: url)
            add("json document", BenchClock.ms(since: start))
            start = ContinuousClock.now
            _ = PreviewStats.from(json: json, animationCount: 0, resourceURL: url)
            add("json stats", BenchClock.ms(since: start))
        }

        /// `RealityThumbnail.render`, step by step.
        private func thumbnail(_ url: URL, _ add: (String, Double) -> Void) async throws {
            let start = ContinuousClock.now
            let model = try await EntityLoader.loadThumbnail(from: url, maxTextureEdge: RealityThumbnail.maxTextureEdge)
            let loaded = ContinuousClock.now
            add("thumb load", BenchClock.ms(loaded - start))
            let assembled = PreviewCamera.makeTurntable(for: model.entity)
            let still = try await StillRenderer(
                root: assembled.pivot,
                bounds: assembled.bounds,
                width: PerfBench.stillSize,
                height: PerfBench.stillSize,
                background: Self.background,
                padding: PreviewCamera.thumbnailFitPadding,
                intensityExponent: model.studioIBLExponent
            )
            _ = try await still.capture()
            add("thumb still", BenchClock.ms(since: loaded))
            add("thumb total", BenchClock.ms(since: start))
        }

        /// The switches a person makes from the view-mode menu, in order, ending where it began.
        private static let transitions: [(String, PreviewDebugMode)] = [
            ("shaded>wire", .wire),
            ("wire>shaded", .none),
            ("shaded>normals", .visualization(.normal)),
            ("normals>uv", .visualization(.textureCoordinates)),
            ("uv>base", .visualization(.baseColor)),
            ("base>shaded", .none),
        ]

        @Test func viewModes() async throws {
            for file in BenchCorpus.files where file.viewModes {
                let model = try await EntityLoader.load(from: file.url)
                let assembled = PreviewCamera.makeTurntable(for: model.entity)
                let still = try await StillRenderer(
                    root: assembled.pivot,
                    bounds: assembled.bounds,
                    width: PerfBench.stillSize,
                    height: PerfBench.stillSize,
                    background: Self.background,
                    padding: PreviewCamera.previewFitPadding,
                    intensityExponent: model.studioIBLExponent
                )
                let store = DebugMaterialStore()
                _ = try await still.capture()
                let steadyStart = ContinuousClock.now
                _ = try await still.capture()
                BenchReport.row("rk.mode", file.name, "shaded frame", [BenchClock.ms(since: steadyStart)])

                var apply: [String: [Double]] = [:]
                for round in 0..<PerfBench.runs {
                    for (name, mode) in Self.transitions {
                        let start = ContinuousClock.now
                        PreviewDebugMode.apply(mode, doubleSided: false, to: model.entity, store: store)
                        apply[name, default: []].append(BenchClock.ms(since: start))
                        // First visit of each mode may build materials / pipelines in RealityKit.
                        if round == 0 {
                            let frameStart = ContinuousClock.now
                            _ = try await still.capture()
                            BenchReport.row("rk.mode", file.name, "\(name) 1st frame", [BenchClock.ms(since: frameStart)])
                        }
                    }
                }
                for (name, _) in Self.transitions {
                    BenchReport.row("rk.mode", file.name, "\(name) apply", apply[name] ?? [])
                }
                skeleton(file.name, model: model, pivot: assembled.pivot)
            }
        }

        /// The overlay as the live canvas drives it: one `apply`, then `updateBones` on every
        /// RealityView update.
        private func skeleton(_ name: String, model: EntityLoader.LoadedModel, pivot: Entity) {
            let skins = model.document.skins
            guard !skins.isEmpty else { return }
            var show: [Double] = [], update: [Double] = []
            for _ in 0..<PerfBench.runs {
                let start = ContinuousClock.now
                PreviewSkeletonOverlay.apply(show: true, skins: skins, to: model.entity, relativeTo: pivot)
                show.append(BenchClock.ms(since: start))
                for _ in 0..<10 {
                    let updateStart = ContinuousClock.now
                    PreviewSkeletonOverlay.updateBones(skins: skins, root: model.entity, pivot: pivot)
                    update.append(BenchClock.ms(since: updateStart))
                }
                PreviewSkeletonOverlay.clear(from: model.entity, pivot: pivot)
            }
            BenchReport.row("rk.skeleton", name, "show", show)
            BenchReport.row("rk.skeleton", name, "update", update)
        }
    }
}
