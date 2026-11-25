---
name: create-release
description: Prepare, sign, notarize, test, publish, and verify a glTF Inspector release, including its update feed, notes, and documentation. Use for release production, not a codebase audit alone.
---

# Create release

Finish the requested endpoint. A built app, notarized ZIP, GitHub draft, and publicly verified release are different states. Never call one another.

## 1. Establish ownership and resume

Read AGENTS.md, project.yml, docs/development.md, release scripts, Git status/remote/tags, latest GitHub release, and existing evidence. Use T3 history when continuing a handed-off run; verify historical claims against current files and services.

Keep one release owner for Git, version, artifact, and publication mutations. Assign parallel agents separate documentation/media/review files. Only one agent controls a desktop or runs app-hosted tests at a time; app launches, installs, and quits can terminate tests. Follow current delegation rules, discover available models when required, and never use Navisalma Claude. Do not delegate the whole job repeatedly without a clear continuing owner.

Reuse the session's approved version, build, publication authorization, and media choices. If no version is approved, propose one before publication. Builds must exceed published builds. “Prepare” leaves publication pending; “release and publish” includes upload and public verification. Repository visibility and history rewriting require explicit authorization; neither is routine release work. “Everywhere” means the configured GitHub release, stable ZIP, Sparkle feed, and documentation links—not invented distribution channels.

Resume `dist/release-evidence.md` (or the established evidence location). Record version/build, endpoint/authorization, owner, source SHA, artifact SHA-256, test host/source, completed gates, exact failures, and next command. Do not repeat a successful step unless its inputs changed. Reuse recent audits; invoke make-ready-for-release only for uncovered scope or unresolved blockers.

## 2. Prepare the candidate before expensive work

- Check credentials/tools early with `scripts/release.sh --preflight`; inspect blockers, not only exit status. Use existing secure credentials; never print/export keys or replace identities. Use the environment secret tool for missing secrets.
- Review actual changes since the last published tag. For the first release, describe the supported product. Update CHANGELOG.md and matching `dist/glTFInspector-<version>.md`; the appcast reads notes beside the ZIP. No generic “Build N” fallback. Keep GitHub and Sparkle notes consistent.
- Keep README short and relaxed: app, visuals, install, essential use, links. Put technical details in existing docs and operational evidence outside public prose. Install wording must match the actual install/relaunch flow. Prepare the final stable download link; verify it after publication.
- Check diagrams/wireframes against changed behavior using create-diagram/create-wireframe. Update affected sources/renders, not every visual by default.
- Preserve approved media and mockups. A release does not authorize replacing the gallery, wallpaper, models, or capture style. Recapture affected/outdated media; reuse accurate approved media with its provenance recorded. Disclose compositions accurately. If new media is explicitly requested, produce it. Use licensed assets and exclude private data/debug overlays.
- Finish runtime fixes and coordinate a source freeze before final tests/signing. Preserve unrelated work. Any subsequent runtime change invalidates affected tests/captures/artifacts; documentation-only changes do not justify rebuilding unchanged app code without a concrete source-matching need.

## 3. Test once against identified source

Use supported commands and required fixtures; missing samples fail. Run focused regressions while fixing, then the full required suite on the frozen candidate. Re-run only failed/interrupted or affected checks unless code changed or final acceptance requires a full run. An isolated retry does not turn an interrupted full run into a passing full run.

Follow macos-testing. If the user requires the linked Mac, arrange its exact source and artifact before testing; do not silently substitute local results or stop at “remote checkout is old.” Use supported isolated-checkout delegation, preserving the remote dirty tree. Record SHA, fixture availability, host/toolchain, commands, result bundles, and screenshots. Do not test stale source as the candidate.

Acceptance covers cold Launch Services opening (not only argv/XCUITest launch), valid GLB, sidecar glTF, invalid-file failure, relevant interaction changes, and actual Quick Look/Finder thumbnails. Test first-launch installation/relaunch when present. Ready logs alone do not prove a visible window or working extensions. See [macOS failure recovery](references/macos-recovery.md) only when these checks fail.

## 4. Archive, export, notarize, sign updates

Inspect script behavior before execution:

| Entry point | Effect |
| --- | --- |
| `scripts/release.sh --preflight` | Prerequisite checks |
| `scripts/archive.sh` | Release archive, Developer ID export, notarize, staple, final ZIP |
| `scripts/appcast.sh dist/glTFInspector-<version>.zip` | Sparkle signing and feed generation |
| `scripts/release.sh` | Full build/sign/publish pipeline; not a local preparation command |

Prefer one final archive/export/notarization. Do not run the full pipeline again merely to upload an already verified artifact. Reuse validated package/build caches; use a clean product directory when removed resources could linger. Finish media prep before this point where feasible. When capture requires the exported app, record its runtime source and avoid a circular rebuild/recapture loop for media-only changes; keep the tested runtime source unambiguous and the release tag tied to it.

A plain Release build is not a Developer ID export. Verify app, extensions, frameworks, and Sparkle helpers: configured team, hardened runtime, no ad-hoc executable signatures, no `get-task-allow`, no test bundles. Deep codesign verification alone is insufficient. Use archive/export to fix signing, never an ad-hoc re-signing pass.

Require Apple acceptance, staple and validate the ticket, assess Gatekeeper, then ZIP. Never edit a signed bundle (apart from supported stapling). Record final checksums and versions across app/extensions/ZIP/notes/tag/feed. Sign the final ZIP with the configured Sparkle key; independently verify against the configured public key. Apple notarization does not replace Sparkle signing.

Keep unpublished experiments/old candidates out of `dist/updates`; preserve them separately. Inspect generated appcast versions/builds, minimum OS, lengths, EdDSA signatures, HTTPS enclosure/notes/delta URLs. Upload every referenced generated notes file, including HTML when produced.

Test the extracted final ZIP, not only build products. Use the requested validation Mac. If transfer needs a GitHub draft, keep it unpublished until acceptance; inspect existing draft/tag state before retrying. Test a real prior public version's update when available. For a first release, record that two-version upgrading is not applicable; never fake an older signed bundle. Have an independent capable agent review final changes and evidence.

## 5. Publish and close

Publish only after the required gates pass, using the already authorized scope. Tag the exact committed/pushed candidate. Never overwrite an existing published release/tag. Inspect partial success before retrying; reuse the verified artifact rather than rebuilding unnecessarily. Include versioned ZIP, stable `glTFInspector.zip`, appcast, referenced notes/deltas, and checksums. No keys, DerivedData, intermediates, or private logs.

Verify anonymously after publication:

- Stable release page (not draft/prerelease unless requested), exact tag SHA, correct version/build.
- Versioned and `releases/latest/download/glTFInspector.zip` downloads match the verified SHA-256; downloaded app passes signatures, staple, and Gatekeeper.
- Published README install link reaches that artifact; no stale “unavailable” claim.
- Public Sparkle feed and every referenced archive/notes/delta URL resolve; versions, lengths, and signatures match. Check updates from the installed Release app.

Only then mark publication/public verification complete and report release URL, version/build, commit, artifact links, checks, and evidence link. If a specific external prerequisite blocks progress, record the exact failed gate, completed work, recovery command, and required input. Resolve routine/recoverable failures autonomously; do not silently finish at a local ZIP or repeat approval already granted.
