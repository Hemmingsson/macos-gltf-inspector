# Contributing

Short version: work on a branch, use `./scripts/dev.sh`, and read [`AGENTS.md`](AGENTS.md) for the
rules. How the code fits together is in [`docs/architecture.md`](docs/architecture.md).

## Requirements

- macOS 26 or later, Xcode with the macOS 26 SDK
- XcodeGen: `brew install xcodegen` (`project.yml` is the project; `.xcodeproj` is generated)
- `python3` (fixture lookup)

Before running tests, fetch the pinned Khronos models:

```bash
./scripts/fetch-test-models.sh
```

Missing models fail the reference tests. The model files stay outside Git.

## Commands

```bash
./scripts/dev.sh build                 # xcodegen + xcodebuild into the DerivedData dir
./scripts/dev.sh install               # build, then copy to .build/glTF Inspector.app
./scripts/dev.sh test                  # unit + reference-image tests
./scripts/dev.sh run cube              # install + open a fixture; `./scripts/dev.sh fixtures` lists ids
./scripts/dev.sh logs                  # tail .build/logs/debug.log
```

`uitest` (steals focus) and `bench` are opt-in. Run `./scripts/dev.sh help` for the full list.

## Environment variables

All optional.

| Variable | Effect |
| --- | --- |
| `DEVELOPER_DIR` | Xcode used for `xcodebuild`. If set, it is respected. If unset, `/Applications/Xcode.app/Contents/Developer` is used. |
| `GLTF_DERIVED_DATA` | DerivedData directory. Default: `/tmp/GLTFInspector-<branch>-dd`. Give each concurrent build its own path, because `xcodebuild` locks `build.db` per DerivedData directory. |
| `GLTF_SKIP_SYSTEM_INSTALL=1` | On the main checkout, `install` and `run` also copy to `/Applications`. Set this to skip that copy. Linked worktrees never copy to `/Applications`. |
| `GLTF_FULLSCREEN=1` | With `run`, the document window goes full screen once it is up. |
| `GLTF_BENCH_RUNS` | Number of runs for `bench` (default 3). |

Example for parallel validation without touching `/Applications`:

```bash
GLTF_DERIVED_DATA=/tmp/gltf-dd-check GLTF_SKIP_SYSTEM_INSTALL=1 ./scripts/dev.sh test
```

## Signing, team, and App Group: current limits

The project is **not** portable as-is. Builds are signed with the maintainer's team, and there is
no supported unsigned or ad-hoc build path.

- `project.yml` sets `DEVELOPMENT_TEAM: 94A9N4B67S` with `CODE_SIGN_STYLE: Automatic`.
- The App Group `94A9N4B67S.lol.mattias.gltf-inspector` is listed in the entitlements of the app
  and both extensions. Bundle IDs use the `lol.mattias` prefix.
- `GLTFCore/AppGroupSettings.swift` hardcodes the same group ID.
- Building with a different team therefore needs changes in `project.yml` (team, bundle prefix,
  App Group entitlements) and in `AppGroupSettings.groupID`. Those are not env-configurable.
- If the App Group suite is unavailable, the app logs an error and falls back to standard
  `UserDefaults`. It still runs, but Settings are not shared with the Quick Look and Thumbnail
  extensions.
- `dev.sh install` runs `codesign --verify --deep --strict` on the copied app, so an unsigned build
  fails that check. Nothing in this repo has been verified with `CODE_SIGNING_ALLOWED=NO`.

Do not commit a personal team ID or a signing identity. Keep local signing changes out of commits.

## Maintainer-only

`scripts/build.sh` (ship check), `scripts/archive.sh`, `scripts/release.sh`, and the Developer ID
export are for the maintainer. They need the Developer ID identity and release secrets. Contributors
do not need them.

## Pull requests

- Branch from `main`. Keep commits focused.
- Run `./scripts/dev.sh test` before opening a PR, and note any reference-image changes in it.
- Do not regenerate `TestModels/References/` unless the change is a new sample or a deliberate
  renderer change. Look at the PNGs before committing them.
