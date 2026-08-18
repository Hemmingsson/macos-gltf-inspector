# CLAUDE.md

Project map, build, and constraints: [AGENTS.md](AGENTS.md).

Quick Look is native RealityKit, not a web view. Verify with `qlmanage`, not a browser.

Do not change `GLBPreviewCamera.makeTurntable`’s `(pivot, bounds)` return type. Do not add outlier AABB framing. Do not set `content.environment` on the preview. Do not spawn a `Task` per RealityView `update`.
