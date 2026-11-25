# Develop and release macOS glTF Inspector

[← README](../README.md)

## What do I need?

Use macOS 26 or newer on Apple Silicon. Install Xcode and XcodeGen.

## What is the contributor loop?

![Contributor loop from clone to tests, fixture run, and debug log](../assets/docs/dev-loop.svg)

1. Clone the repository.
2. Run `brew install xcodegen`.
3. Set your team ID in `project.yml`, `scripts/sparkle-lib.sh`, and
   `scripts/ExportOptions-DeveloperID.plist`.
4. Set a matching App Group ID in `project.yml` and `GLTFCore/AppGroupSettings.swift`.
5. Run `./scripts/fetch-test-models.sh`.
6. Run `./scripts/dev.sh test`.
7. Run `./scripts/dev.sh run <fixture>`.
8. Check `.build/logs/debug.log` for `open start`, `open ready|failed`, and `canvas ready|failed`.

| Command | Use |
| --- | --- |
| `./scripts/dev.sh build` | Build the app |
| `./scripts/dev.sh install` | Build and install the app |
| `./scripts/dev.sh test` | Run unit and reference-image tests |
| `./scripts/dev.sh uitest` | Run real-window UI tests |
| `./scripts/dev.sh run <fixture>` | Install and open a fixture |
| `./scripts/dev.sh logs` | Tail the debug log |
| `./scripts/dev.sh fixtures` | List fixture IDs |
| `./scripts/dev.sh bench` | Run the opt-in performance test |

## How do reference-image tests work?

![Reference-image test cycle from Khronos output to PixelDiff verdict](../assets/docs/reference-tests.svg)

The Metal renderer must stay within both PixelDiff budgets of the recorded references.
See [reference provenance](../TestModels/References/README.md).

Regenerate references only for a new sample or a deliberate renderer change. Inspect changed PNGs before committing.

## How do I release glTF Inspector?

![Release pipeline from version bump to GitHub release](../assets/docs/release.svg)

| Command | Use |
| --- | --- |
| `./scripts/release.sh --preflight` | Check release tools and credentials |
| `./scripts/archive.sh` | Archive, sign, notarize, staple, and zip the app |
| `./scripts/appcast.sh dist/glTFInspector-<version>.zip` | Sign updates and build the appcast |
| `./scripts/release.sh` | Run the full release and create the GitHub release |

| Prerequisite | Where it is used |
| --- | --- |
| Developer ID Application certificate | Archive export and code signing |
| `notarytool` keychain profile | Notarization; default name `glb-preview-notary` |
| Sparkle EdDSA key pair | Update signing and `SUPublicEDKey` |
| GitHub CLI login | GitHub release upload |

Keep the Sparkle private key in the macOS Keychain. Never store it in Git.

### Sparkle readiness and first release

The main app is not sandboxed; Sparkle's sandbox XPC entitlements are not required.
`UpdateConfig.shouldStartUpdater` deliberately disables the updater in Debug. Use
Release builds for update tests. The public key in `project.yml` is
`OQrffRwGjVoW1aFeEKHsEcYco5WgZo1qH7syaZmjoQ8=`. Keep its private counterpart in
Keychain; do not regenerate or export it during readiness checks.

Before publication (no upload):

1. Store the privately supplied notarization credentials in the
   `glb-preview-notary` profile. Do not put credentials in shell history or Git.
2. Run `python3 scripts/sparkle-readiness-test.py`,
   `bash scripts/rewrite-appcast-urls-test.sh`, and `./scripts/release.sh --preflight`.
   Preflight exits nonzero for blocking failures. It reads GitHub release metadata
   and, when a stable release exists, downloads the public appcast anonymously.
   A feed/network failure is a blocker, not evidence of a first release.
3. Confirm marketing version/tag are unused and the integer build number exceeds
   both local and published appcast builds. Current candidate is 1.0, build 4.
4. Run `./scripts/archive.sh` only once notarization is authorized and credentials
   are ready. It archives Release, exports Developer ID (including Sparkle helpers),
   checks built key/feed/versions against `project.yml`, verifies signatures,
   notarizes, staples, re-zips and assesses Gatekeeper.
5. Run `./scripts/appcast.sh dist/glTFInspector-1.0.zip`. This accesses the signing
   key through Sparkle and creates signatures; it does not publish. Inspect
   `dist/appcast.xml`: build 4, correct minimum OS, EdDSA signature and length,
   HTTPS enclosure/notes/delta URLs under the intended release tag. Preserve
   `dist/updates` archives for future genuine delta generation.

At explicitly authorized publication only, make the existing
`Hemmingsson/macos-gltf-inspector` repository public after reviewing its history
and contents. Do not create a separate hosting repository. Upload the prepared
versioned zip, appcast, notes (if present), and generated deltas to stable release
`v1.0`, plus the stable-name `glTFInspector.zip` asset. `release.sh` performs the
whole archive/sign/publish pipeline, so do not use it for readiness alone or rerun
it against an existing tag. Confirm anonymous downloads of the feed and every
referenced asset work; GitHub private release URLs cannot serve public Sparkle
clients. Verify downloaded ZIP signatures and Gatekeeper assessment on a clean
Mac/account, install in `/Applications`, launch and manually check for updates.
The first release should report up to date; that alone does not prove updating.

### Two-version update acceptance test

1. Keep an untouched, notarized, stapled Release A (initially 1.0/build 4), installed
   in `/Applications`. Record its version and signing identity. Do not edit its
   Info.plist to fake an older build; that breaks its signature and delta checksum.
2. Prepare Release B with a new marketing version/tag (for example 1.2) and a
   strictly larger build (5 or greater). Retain the same bundle ID, feed, EdDSA key
   and Developer ID team. Run preflight: it must compare against the published A
   feed even on a clean checkout without `dist/updates/appcast.xml`.
3. Archive/notarize/staple B and generate its appcast alongside A's original ZIP.
   Inspect full and delta enclosures and publish B only with explicit permission.
   Verify anonymous feed and referenced assets before launching A.
4. From A choose **Check for Updates…**, confirm B is offered, download/install,
   permit relaunch, then verify B's version/build, valid code signature, opening
   a model, and Quick Look preview/thumbnail operation. A second update check
   must say up to date. Record any Sparkle errors from Console.
5. Repeat from a fresh untouched A for delta testing if a delta was generated;
   inspect Sparkle logs to establish whether the delta was used. Separately test
   full-archive fallback (a test feed without deltas is suitable). For an isolated
   prepublication test, build and notarize both versions with a separate HTTPS
   test feed in `project.yml`, restoring the production URL before production
   builds; never mutate signed bundles. Test automatic checking with the configured
   preferences and schedule, as well as the manual command.

Readiness status (2026-11-25): Developer ID identity is present. The
`glb-preview-notary` Keychain profile is configured and authenticated with Apple.
Release preflight passes. Public hosting is intentionally pending
publication. No notarized two-version installation/relaunch test has been run;
end-to-end updates remain unverified. An unsigned Release build and config check
validate compilation and embedded public values only, not notarization, Keychain
signing access, helper signing, Gatekeeper, or installation.

References: [Sparkle setup and distribution](https://sparkle-project.org/documentation/),
[programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/),
[publishing an update](https://sparkle-project.org/documentation/publishing/).
