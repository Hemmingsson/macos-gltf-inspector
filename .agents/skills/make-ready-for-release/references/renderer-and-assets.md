# Renderer claims and asset rights

## Source and scope

Verify `UPSTREAM.md`, the upstream commit, licenses, shader mappings, and local changes.

Distinguish the Khronos shading port from original Swift scene loading, animation, skinning, morphing, camera, overlays, and Metal pipeline code. Check GLTFKit2's role. Distinguish pre-baked IBL from runtime filtering.

Use precise claims, such as “the shading core is hand-ported from…”. Do not imply that the whole engine was ported.

## Test evidence

Check reference-image generation, comparisons, and tolerances. Passing cases show agreement for those cases. They do not prove full glTF conformance, exact lighting equivalence, or correct output for every asset.

Follow repository rules for baseline changes. Do not replace baselines only to remove failures.

Verify animation, shortcuts, loading, lighting setup, validation, and feature limits. Distinguish asset validation from viewer limits. Do not equate rest-pose rendering with exact reproduction of authored geometry.

## Distribution

Check rights and attribution for models, textures, environments, screenshots, and demos. Public access does not establish permission to redistribute.

Recheck two previous reports: unclear Spline asset origins and a noncommercial restriction on the Field environment. Confirm their current status with evidence.

Unresolved or incompatible rights for release assets block publication. Propose replacement, exclusion, or permission from the rights holder.
