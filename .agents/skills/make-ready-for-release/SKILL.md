---
name: make-ready-for-release
description: Audit and prepare glTF Inspector for public release. Check Swift code, security, documentation, renderer claims, asset rights, and builds. Use for a full release review, not routine feature work.
---

# Make ready for release

Prepare a simple, predictable Swift codebase and a signed, versioned build plan. Fix confirmed problems. Keep intended behavior and unrelated work.

Do not push, publish, tag, distribute builds, change signing identities, access signing secrets, or rewrite Git history without separate authorization.

## Plan and assign

Read repository instructions, status, and diff. Check the code, `docs/architecture.md`, `docs/design.md`, and developer scripts. Verify previous findings against current files.

Use parallel agents for separate review areas:
- Swift behavior and structure.
- Renderer accuracy and source attribution.
- Documentation and asset rights.
- Security, builds, and tests.

Give each agent relevant files, a bounded task, acceptance criteria, and evidence requirements. Assign separate files for edits. Review the combined changes. Resolve disagreements with code and observed behavior.

## Select models

Use GitHub Copilot, Cursor, Codex, or private Claude according to current availability and remaining tokens. Never use Navisalma Claude, including Claude models routed through a Navisalma provider.

Discover providers and exact model IDs through the required delegation tools; do not guess IDs or token balances. Prefer Haiku or Luna for implementation, tests, and routine validation when available. Use more capable models for evaluation, review, difficult problems, architecture, and large context. If a provider or model fails, is rate-limited, or has exhausted its tokens, report the failure and continue with another working option from the allowed providers without asking again. Cancel any replaced run. If none works, report the blocker and ask how to proceed.

## Check and fix

- **Behavior:** crashes, failed loads, state, concurrency, actor isolation, memory, errors, and edge cases. Cover the app and both extensions.
- **Structure:** duplicate logic, dead code, experiments, unclear names, and excess complexity. Make focused, idiomatic Swift changes. Avoid unrelated features and speculative rewrites.
- **Security:** secrets, personal data, sensitive logs, and unwanted generated files in tracked files and Git history. Report exposure without secret values. Identify required revocation or history repair.
- **Build:** dependencies and their sources, settings, permissions, entitlements, extension safety, versions, and clean-checkout setup. Distinguish signing configuration checks from a tested signed build.
- **Documentation:** setup, architecture, features, screenshots, demos, licenses, and release steps. Remove unsupported claims. Keep text short and factual.

For renderer claims and asset rights, read [renderer-and-assets.md](references/renderer-and-assets.md).

Record each actionable finding: severity, file and line, impact, evidence, and proposed fix. Separate defects, hypotheses, and style preferences. Fix release blockers and behavior first. Use small batches; validate each batch. Change approach or escalate after repeated failures.

## Validate and finish

Use supported repository commands. Run relevant unit tests, image comparisons, static checks, and manual checks. Verify documented setup in an isolated clean checkout when feasible. Preserve ongoing work. Report missing prerequisites and checks not run.

Have a capable review agent independently inspect material changes and test evidence. Give it source access, not only the implementer's conclusions. Fix confirmed findings and repeat affected checks.

Finish when the scope is covered, relevant checks pass, and unresolved blockers are recorded. Report changes, test results, risks, blockers, and remaining release steps. Separate verified results from assumptions. Do not claim that the app has no bugs or present source inspection as a runtime test.
