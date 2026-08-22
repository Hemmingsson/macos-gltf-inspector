import Foundation
import RealityKit

/// Usable RealityKit animation clip for preview playback / seam Availability.
/// Document mirror is `GLTFSessionDocument.Animation` (name + duration only — no re-parse).
struct PreviewClip: Identifiable {
    let id: Int
    let resource: AnimationResource
    /// Raw clip name from `AnimationResource` (may be empty). Feeds `documentAnimation`.
    let name: String
    /// Picker / playback-bar label — empty names become `Clip N` among usable clips.
    let title: String
    let duration: TimeInterval

    var documentAnimation: GLTFSessionDocument.Animation {
        GLTFSessionDocument.Animation(name: name, duration: duration)
    }

    /// Sendable name/duration view for PreviewUI when `AnimationResource` is not needed.
    var info: PreviewClipInfo {
        PreviewClipInfo(id: id, title: title, duration: duration)
    }

    /// Clips with positive finite duration from `entity.availableAnimations`.
    /// `id` is the index in that array (skipped unusable entries leave gaps).
    /// When `document` is provided, empty RealityKit names fall back to
    /// `document.animations[id].name` (convert stamps names; RK often drops them).
    @MainActor
    static func usable(on entity: Entity, document: GLTFSessionDocument? = nil) -> [PreviewClip] {
        var result: [PreviewClip] = []
        for (offset, resource) in entity.availableAnimations.enumerated() {
            guard let duration = EntityLoader.clipDuration(resource, on: entity) else { continue }
            var name = resource.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty,
               let document,
               document.animations.indices.contains(offset) {
                name = document.animations[offset].name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Fallback index is among *usable* clips (not the raw animation index).
            result.append(
                PreviewClip(
                    id: offset,
                    resource: resource,
                    name: name,
                    title: displayTitle(name: name, emptyFallbackIndex: result.count + 1),
                    duration: duration
                )
            )
        }
        return result
    }

    /// From `GLTFSessionDocument.animations` — no entity / no re-parse.
    static func list(from document: GLTFSessionDocument) -> [PreviewClipInfo] {
        document.animations.enumerated().compactMap { offset, animation in
            guard animation.duration > 0 else { return nil }
            // Fallback index is the document animation index (1-based), including skipped zeros.
            let title = displayTitle(
                name: animation.name,
                emptyFallbackIndex: offset + 1
            )
            return PreviewClipInfo(id: offset, title: title, duration: animation.duration)
        }
    }

    private static func displayTitle(name: String, emptyFallbackIndex: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Clip \(emptyFallbackIndex)" : trimmed
    }
}

/// Sendable clip metadata for PreviewUI / Availability (no `AnimationResource`).
struct PreviewClipInfo: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let duration: TimeInterval
}
