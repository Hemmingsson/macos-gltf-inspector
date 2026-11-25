# Development

[← README](../README.md)

## Setup

macOS 26+, Apple Silicon, Xcode, and XcodeGen (`brew install xcodegen`).

1. Set your Apple team ID in `project.yml`, `scripts/sparkle-lib.sh`, and
   `scripts/ExportOptions-DeveloperID.plist`.
2. Set a matching App Group ID in `project.yml` and `GLTFCore/AppGroupSettings.swift`.
3. Fetch the pinned Khronos samples: `./scripts/fetch-test-models.sh`.
4. Run `./scripts/dev.sh test`, then `./scripts/dev.sh run cube`.

![Contributor loop](../assets/docs/dev-loop.svg)

| Command | What it does |
| --- | --- |
| `./scripts/dev.sh build` | Generate the Xcode project and build |
| `./scripts/dev.sh install` | Build and install (`.build/`, and `/Applications` on `main`) |
| `./scripts/dev.sh test` | Unit and reference-image tests |
| `./scripts/dev.sh run <fixture>` | Install and open a fixture |
| `./scripts/dev.sh logs` | Tail `.build/logs/debug.log` |
| `./scripts/dev.sh fixtures` | List fixture IDs |
| `./scripts/dev.sh uitest` | Real-window UI tests (takes focus) |
| `./scripts/dev.sh bench` | Opt-in performance timings |

After `run`, expect `open start`, then `open ready` or `open failed`, and
`canvas ready` or `canvas failed` in the log.

Optional env vars: `DEVELOPER_DIR`, `GLTF_DERIVED_DATA`, `GLTF_SKIP_SYSTEM_INSTALL=1`,
`GLTF_FULLSCREEN=1`. Details are in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Reference images

![Reference-image tests](../assets/docs/reference-tests.svg)

Metal output must stay within the PixelDiff budgets in `TestModels/References/`.
See [provenance](../TestModels/References/README.md). Regenerate only for a new sample
or a deliberate renderer change, and look at the PNGs before committing.

## Release

![Release pipeline](../assets/docs/release.svg)

Maintainer only. Needs a Developer ID Application certificate, a `notarytool` keychain
profile (default `glb-preview-notary`), the Sparkle EdDSA private key in Keychain, and
`gh` logged in. Never put secrets in Git.

| Command | What it does |
| --- | --- |
| `./scripts/release.sh --preflight` | Check tools and credentials |
| `./scripts/archive.sh` | Archive, sign, notarize, staple, zip |
| `./scripts/appcast.sh dist/glTFInspector-<version>.zip` | Sign the update and write the appcast |
| `./scripts/release.sh` | Full release and GitHub upload |

Sparkle is off in Debug (`UpdateConfig.shouldStartUpdater`). Test updates with Release
builds. The public EdDSA key lives in `project.yml` as `SUPublicEDKey`.

More on Sparkle: [setup](https://sparkle-project.org/documentation/),
[publishing](https://sparkle-project.org/documentation/publishing/).
