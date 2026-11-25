---
name: create-release
description: Create a glTF Inspector release with signing, notarization, a changelog, release notes, new media, current diagrams and wireframes, and version-matched documentation. Use for release production and publication, not a codebase audit alone.
---

# Create release

Produce one coherent release: code, signed archive, update feed, notes, media, and documentation must describe the same version and commit. Use short, direct wording.

## Establish the release

Read repository instructions, `project.yml`, `docs/development.md`, and the current release scripts. Inspect Git status, remote, tags, and the last release. Preserve unrelated work.

Use the requested version. If none is given, propose a version from the changes and confirm it before publication. Keep the build number newer than published builds. Check version values across the app, extensions, archive, notes, tag, and update feed.

Create or resume a durable release checklist in the existing release evidence location (use `dist/release-evidence.md` if none exists). Record the approved version/build, exact source commit, requested endpoint (prepare or publish), authorization already given, artifact paths/checksums, and each remaining step. Update it as evidence arrives so a handoff can resume without guessing. Keep local archive, notarization, update signing, publication, and public verification as separate completion states.

Check recent release-readiness evidence. Use [make-ready-for-release](../make-ready-for-release/SKILL.md) if a full audit is needed. Resolve known release blockers. Do not repeat a completed audit without a reason.

## Assign work

Use parallel agents for documentation, media, and release checks. Assign separate files. Use GitHub Copilot, Cursor, Codex, or private Claude according to current availability and remaining tokens. Never use Navisalma Claude, including Claude models routed through a Navisalma provider.

Discover providers and exact model IDs through the required delegation tools; do not guess IDs or token balances. Prefer Haiku or Luna for implementation, tests, and routine validation when available. Use more capable models for evaluation, difficult problems, architecture, and large context. If a provider or model fails, is rate-limited, or has exhausted its tokens, report the failure and continue with another working option from the allowed providers without asking again. Cancel any replaced run. If none works, report the blocker and ask how to proceed. Have a capable agent independently review the final changes and evidence.

## Compile the changelog

Review commits, merged changes, and the source diff since the last published tag. For the first release, describe the supported product. Verify each entry; do not copy commit subjects without review.

Update the existing changelog. If none exists, create `CHANGELOG.md`. Add the version, release date, and relevant sections: Added, Changed, Fixed, Deprecated, Removed, and Security. Omit empty sections. State user impact, breaking changes, migration steps, supported macOS versions, and known issues. Do not disclose sensitive security details before an agreed disclosure.

Create matching GitHub and Sparkle notes from this entry. Check the paths expected by the scripts; the current appcast script reads Markdown beside the zip with the same base name. Do not let the release fall back to generic “Build N” notes. Preserve older entries and add comparison links where useful. Use a prerelease label and channel when appropriate; do not promote a prerelease as stable.

## Update documentation and visuals

- Compare all user and developer docs with the release code. Check feature claims, requirements, setup, shortcuts, limitations, links, licenses, version references, and release instructions. Write notes from actual changes since the last release.
- Check all diagrams against current code. Use [create-diagram](../create-diagram/SKILL.md). Update changed diagrams and render their editable sources. Verify retained diagrams remain correct.
- Check all wireframes against current UI and states. Use [create-wireframe](../create-wireframe/SKILL.md). Keep editable sources, rendered files, and documentation embeds consistent.
- Capture new app screenshots and render new demo videos for this release. Inspect existing tools and media conventions first. Cover the main app, Quick Look, and Finder thumbnails where relevant. Update documentation embeds, posters, and derived formats when used.
- Use release-built behavior and assets with verified distribution rights. Exclude personal data, secrets, private paths, and debug overlays. Record the version, commit, capture settings, and commands in the release evidence.
- Distinguish real captures from rendered compositions. Preserve accurate disclosure: a simulated Quick Look or Finder scene is not a recording. A wireframe is not an app screenshot. Check existing disclosures in `README.md`.
- Inspect screenshots at their displayed size. Play every video through. Check framing, labels, timing, motion, image quality, and light/dark readability. Do not substitute old media without reporting the gap.

## Build and validate

Run supported builds, tests, reference comparisons, and relevant manual checks. Test installation, opening a model, Quick Look, and thumbnails. Check documentation links and generated visual files.

Inspect script side effects before running them. Current entry points include:
- `scripts/release.sh --preflight`: checks release prerequisites; inspect reported blockers even if it exits successfully.
- `scripts/archive.sh`: archives, signs, submits for notarization, staples, and creates a zip.
- `scripts/appcast.sh`: signs updates and creates the feed.
- `scripts/release.sh`: runs the pipeline and publishes a GitHub release. It is not a local preparation command.

Use existing signing credentials through supported secure tools. Never print or commit secrets. Request missing secrets through the environment's secret tool. Do not replace signing identities or keys without authorization.

Produce a Release archive. Sign the app, extensions, and nested executable code with the configured Developer ID identity and required entitlements. Verify the expected team, hardened runtime, and absence of debug-only entitlements or test bundles. Use the existing archive/export pipeline; do not repair signatures with an ad hoc signing pass.

Submit for Apple notarization, check the accepted result, and staple and validate the ticket. Create the final distribution zip after stapling. Sign the final update archive with Sparkle's configured key. Apple code signing and Sparkle update signing are separate requirements. Never publish an unsigned or unnotarized substitute when credentials or services fail.

Verify the exported version, app and extension signatures, notarization, staple, Gatekeeper assessment, archive contents, and Sparkle signatures and URLs. Record artifact checksums. Do not edit a signed bundle; rebuild it after changes. If release code changes after capture or testing, repeat affected work.

Test the extracted distribution archive, not only the development build. Check a fresh install and, when a prior release exists, an update from that release. If an update cannot be tested, record the gap. Record the commit, Xcode/SDK versions, dependency revisions, commands, checksums, and signing results without secrets.

## Publish and verify

Prepare reviewable notes, artifacts, evidence, and the exact target commit before any required approval. Follow the user's authorization: a request to publish authorizes publication; a request to prepare leaves it pending. Creating this skill does not authorize a release. Honor publication and version approval already given in the session; do not ask again for the same authorized step. A prepare-only request leaves publication pending. Never change repository visibility implicitly; if public hosting requires a visibility change, use existing explicit authorization or report that specific remaining prerequisite.

Ensure the tag points to the tested source. Check remote state before publishing. Do not overwrite an existing release or tag. After a partial failure, inspect what succeeded before retrying.

Publish only the verified final archives, notes, feed, and required update files. Keep private keys, credentials, DerivedData, and intermediate build files out of the release. Verify checksums against downloaded assets. Retain the prior release and a recovery plan; do not attempt to downgrade users by lowering the build number.

After publication, verify anonymously, without GitHub credentials:
- The public release page is stable (not draft/prerelease unless requested), and its tag resolves to the tested commit.
- Download both the versioned ZIP and `releases/latest/download/glTFInspector.zip`; compare their SHA-256 values with the verified archive. Check the downloaded app's signatures, stapled ticket, and Gatekeeper result.
- Open every install/download link in the published README and confirm it reaches the intended public artifact. Remove “not available yet” text only as part of the authorized publication, and verify the final public README.
- Download the public appcast and its referenced archive, notes, and delta assets. Check version/build, minimum OS, lengths, signatures and HTTPS URLs against the final artifacts.

A notarized local archive is not a published release. For an authorized publication request, continue through upload and these public checks; do not silently stop at a signed ZIP or describe it as shipped. Mark the durable checklist complete only when the requested endpoint is verified. For prepare-only requests, mark publication pending explicitly.

If blocked, record the failed step, exact prerequisite or error, what succeeded, and the next safe command in the evidence. Resolve recoverable failures within existing authorization; inspect partial publication before retrying and never recreate or overwrite an existing release blindly. Hand back only a specific blocker requiring user input or an external change, with completed artifacts available. Do not claim publication or verification that has not happened.

Report the release URL, version/build, exact commit, downloadable artifacts, checks, and any remaining gaps. Link the evidence checklist.
