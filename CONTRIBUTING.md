# Contributing

Branch from `main`, use `./scripts/dev.sh`, follow [`AGENTS.md`](AGENTS.md).
Architecture: [`docs/architecture.md`](docs/architecture.md). Setup: [`docs/development.md`](docs/development.md).

## Requirements

- macOS 26+, Xcode (macOS 26 SDK), Apple Silicon
- XcodeGen (`brew install xcodegen`) — `project.yml` is the source of truth
- `python3` for fixture lookup

```bash
./scripts/fetch-test-models.sh   # required before tests; samples stay out of Git
./scripts/dev.sh test
./scripts/dev.sh run cube
```

## Commands

```bash
./scripts/dev.sh build      # xcodegen + build
./scripts/dev.sh install    # into .build/ (and /Applications on main)
./scripts/dev.sh test       # unit + reference images
./scripts/dev.sh run cube   # install + open a fixture
./scripts/dev.sh logs       # tail .build/logs/debug.log
```

`uitest` and `bench` are opt-in. `./scripts/dev.sh help` lists everything.

| Variable | Effect |
| --- | --- |
| `DEVELOPER_DIR` | Xcode path (default `/Applications/Xcode.app/Contents/Developer`) |
| `GLTF_DERIVED_DATA` | DerivedData dir (default `/tmp/GLTFInspector-<branch>-dd`) |
| `GLTF_SKIP_SYSTEM_INSTALL=1` | Skip the `/Applications` copy on main |
| `GLTF_FULLSCREEN=1` | Full-screen the window after `run` |
| `GLTF_BENCH_RUNS` | Runs for `bench` (default 3) |

## Signing

Builds use the maintainer’s team (`DEVELOPMENT_TEAM` in `project.yml`) and App Group
`94A9N4B67S.lol.mattias.gltf-inspector`. To use another team, change `project.yml`, the
entitlements, and `GLTFCore/AppGroupSettings.swift`. Those IDs are not env-configurable.
Do not commit a personal team ID. Unsigned builds fail `dev.sh install`’s codesign check.

Release scripts (`archive.sh`, `release.sh`, …) are maintainer-only.

## Pull requests

- Focused commits on a branch from `main`
- Run `./scripts/dev.sh test` before opening a PR
- Only regenerate `TestModels/References/` for a new sample or intentional renderer change —
  look at the PNGs first
