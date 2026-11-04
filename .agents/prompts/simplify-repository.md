# Simplify glTF Inspector until every file can be defended

You are taking over glTF Inspector: a macOS 26+ app for looking at `.glb` / `.gltf` files. It
has a document window, a Quick Look preview, and Finder thumbnails. The code got here through
many iterations: a WebKit page that hosted the Khronos glTF Sample Renderer, a Filament spike,
a design-system/catalog effort, and finally a native Metal port of the Khronos renderer that
became the default renderer on every surface. Each step left layers behind, and the structure
still reflects the history more than the product.

**The product we have today is roughly what we want. The implementation is not.**

Your job is to find out what this app actually is, decide what the simplest honest
implementation of it looks like, and then make the repository look like that. Keep working
through the loop below until you could defend every file, type and line to a senior macOS
developer whose only goal is a simple, fast, accurate preview app.

## What we know we want

This is deliberately short. Anything not listed here is up to you to justify from the code.

- **Fast, accurate rendering.** The native Metal port draws the window, Quick Look and the
  Finder thumbnail. Accuracy is measured against the committed Khronos reference images in
  `TestModels/References/`; speed is measured by load and first-frame time. Neither may regress.
- **Inspection.** The user can look at what the file contains: the scene tree, meshes,
  materials, the parts a file is built from, and validation problems. Work out from the code and
  the running app which inspection features carry real weight.
- **macOS-native and quiet.** System controls, menus with shortcuts, Settings, Quick Look and
  thumbnails behave like the platform expects.
- **Everything else is negotiable.** If something exists only because of a past renderer, a past
  architecture or a hypothetical future, it is a candidate for removal.

## How to work

Work in this worktree on its own branch. Never touch other worktrees or uncommitted work in the
main checkout. Commit in coherent steps with messages that say what changed and why.

### 1. Understand before you judge

Read the repository as if you had inherited it today. Do not trust the docs, the handoffs in
`.agents/`, or the comments: verify them against code and the running app.

Trace the real paths end to end:

- Opening a file in the window, through to the first rendered frame and the filled sidebar.
- Quick Look opening a file. Finder asking for a thumbnail.
- A user action (orbit, fit, change view mode, select a node, export a PNG) through to pixels or
  panel content.
- A file that fails to load, a file with validation errors, a `.gltf` with sidecar files.
- Settings: where they are written, who reads them, and how the sandboxed extensions see them.

For each path, write down what data exists, who owns it, what shape it is in, and how it is
transformed. Note every place where the same fact is computed twice, stored twice, named twice,
or passed through a layer that adds nothing.

Establish the baseline before changing anything: build, the full test suite, the strict Metal
pixel-parity gate, and a look at the running app. Record existing failures separately so you
never confuse them with regressions you caused.

### 2. Decide what the app should be

From what you found, write a short target description (a few sentences, not a plan document):
the modules, what each owns, and how a file becomes pixels and panel content. Questions worth
answering with evidence:

- How many renderers does the product need, and how many do the tests need?
- Which module boundaries correspond to a real constraint (an app extension, a sandbox, a
  separately shipped binary), and which are leftovers?
- Which protocols have exactly one real conformer plus mocks that only exist for previews?
- Which types merely rename, forward or re-shape another type's data?
- Does the design system earn its weight in an app this size?
- Which scripts, docs, test suites, benchmarks, entitlements and dependencies still matter?
- Where do names still describe an old implementation (`Web…`, `Engine…`, `Seam`, `page`)?

Keep this description in `.agents/handoffs/` and update it as your understanding changes.

### 3. Change it

Make the repository match the target, in reviewable steps. You decide what to merge, move,
rename, rewrite or delete. Some guidance on judgement:

- Prefer deletion to rearrangement and rearrangement to new structure.
- Prefer direct code over protocols, adapters and wrappers unless a second real implementation
  or a hard boundary demands one.
- One concept, one name, one owner. Rename consistently through code, tests, scripts and docs.
- Keep related code together; do not split a simple thing across many files.
- Keep data flow visible: a developer should be able to follow a value from the file to the
  screen without guessing. Failures should be explicit (`.failed(message)`), not silent.
- Do not trade readability for line count, and do not introduce a new architecture for its
  own sake.
- Finish every migration. No parallel old and new paths, no dead shims.
- When removing something that ships (an entitlement, a setting key in the App Group, a bundle
  resource), check whether installed users or the extensions depend on it.

### 4. Verify every step

After each meaningful change:

- `./scripts/dev.sh test` passes, with the same or fewer known failures.
- The strict pixel gate passes without touching references, the manifest or tolerances:
  `TEST_RUNNER_GLTF_METAL_PARITY=1 ./scripts/dev.sh test -only-testing:GLTFInspectorTests/PixelDiffMetalTests`
- When UI or rendering changed, look at the real app (`./scripts/dev.sh run <fixture>`, logs in
  `.build/logs/debug.log`): one "open start", one "open ready"/"open failed", no
  "Modifying state during view update". Check Quick Look and the thumbnail path too.
- Do not weaken or delete a valid test to get green. Delete tests only together with the code
  they test, and say so.

### 5. Look again

After each pass, re-read the result with fresh eyes. Did the change reveal more dead code, a
layer that is now pointless, a name that no longer fits? Did you add complexity anywhere? Repeat
steps 2–5.

Stop only when a complete re-read finds nothing you would still remove, merge or rename, and you
can explain the whole architecture in a few sentences.

## Report

When done, give a short report:

1. The resulting architecture in a few sentences.
2. What changed, what was removed, and why.
3. How a file becomes pixels and panel content now.
4. Verification: builds, tests, pixel gate, real-app checks, before/after numbers (files, lines,
   targets, dependencies, load and first-frame time).
5. Behaviour changes and breaking changes, explicitly.
6. Anything left undone and why.
