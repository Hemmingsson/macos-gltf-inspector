---
name: n-brainstorm
description: Find out what the user actually wants and write it down as an approved spec. Use before building a feature, a change in behaviour, or anything with open decisions; or when the user asks to brainstorm, grill, or write a spec.
---

# n-brainstorm

You build what you believe the user wants, and that belief is usually thinner than it feels. This skill turns an ask into a **spec** the user has approved.

## 0. What do you know?

Everything that matters is in the ask ("make the icon cornflower blue")? Skip this skill: put a task on the board (`n-backlog`) and use `n-tdd`. Otherwise go on.

## 1. Look before you ask

Read the ask, everything it points at (spec, plan, handoff, files), and the code it touches, until you can say how it works today and what the change touches. Facts are your job: dispatch a fresh subagent for a fact you lack. Never ask what the repo answers.

## 2. Why, in their words

Until you know *why* they want it, ask **one open question at a time**, in their terms, with no options attached, and say what the answer changes. Their words carry intent your options would steer away.

The user says "just dive in"? Stop here: state each how-it-gets-made choice in one line and go to `n-breakdown` or `n-tdd`.

## 3. Grill the design tree

Once the why is clear, map the open decisions as a **design tree** and ask the **frontier** in rounds — numbered, each with your recommended answer ([grilling.md](references/grilling.md)). After each round, play back what is settled: their words as theirs, your fills as proposals.

A question about how something *looks* (a layout, a flow, side-by-side options)? Offer the **visual companion** once, in a message of its own: "This might be easier if I show you. Want me to open a browser tab with some mockups?" On yes, read [visual-companion.md](references/visual-companion.md).

## 4. Approaches

In a message of its own: the 2–3 real ways to build it, grounded in what the repo does, each with its trade-off; your pick and why. One sensible way? Say so and why the others don't fit.

## 5. Write the spec

Say the size: **small** (one task) or **project** (an epic). The spec lives on the board, not in a file: create the L0 epic (or, for small, the single task) with the spec as its description, status *draft* — [epic template](../n-backlog/references/epic-template.md). It opens with a picture of how it will work: send `n-visualizer` (background) for the diagram or wireframe as soon as the shape is clear, and keep writing. Every behaviour gets an **acceptance example**; these become the red tests.

Project size: dispatch `n-spec-reviewer` with the epic id. Answer what the spec already answers, settle minor points yourself (mark them "my call"), and bring the user only the questions that change what gets built — one message, most important first.

## 6. Approval

Hand over the epic id, its picture, and the list of your calls. On approval, set its status to *approved*.

**Done when** the user approves the spec. Until then, build nothing: no product code, scaffolding, or installs. A spike the user said yes to is the exception: it gets a spike task on the board and stays throwaway.

Next: `n-breakdown`.
