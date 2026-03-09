---
name: orient
description: Load Famichat's core product, brand, IA, and E2EE docs when the user asks for /orient, wants onboarding to the repo, or needs a concise grounding in the current project direction before implementation or review work.
disable-model-invocation: false
allowed-tools: Read, Glob, Grep
---

# Orient

Use this skill when the user asks for `/orient`, wants project onboarding, or needs a quick reset on Famichat's current intent, boundaries, and implementation state.

## Read These Docs

Read these files directly from the repo:

1. `docs/brand-positioning.md`
2. `docs/E2EE_INTEGRATION.md`
3. `docs/ia-boundary-guardrails.md`
4. `docs/ia-lexicon.md`
5. `docs/NOW.md`
6. `docs/SPEC.md`

## What To Extract

After reading, synthesize the repo around these axes:

1. Current product reality and near-term priorities from `docs/NOW.md`
2. Stable product intent and out-of-scope areas from `docs/SPEC.md`
3. Brand and positioning language from `docs/brand-positioning.md`
4. Canonical IA and naming boundaries from `docs/ia-lexicon.md` and `docs/ia-boundary-guardrails.md`
5. E2EE target architecture, promises, and non-negotiable invariants from `docs/E2EE_INTEGRATION.md`

## Response Shape

Keep the orientation concise and practical. Cover:

- what Famichat is trying to be
- what is true right now versus merely planned
- which names and boundaries are locked
- which security and architecture promises cannot be violated
- the most important implementation constraints a contributor should keep in mind

Reference the source file paths when summarizing decisions or constraints.

## Priority Rules

- Treat `docs/NOW.md` as the source of current execution state and active bugs.
- Treat `docs/SPEC.md` as the source of product intent, scope, and deferred work.
- Treat `docs/ia-lexicon.md` and `docs/ia-boundary-guardrails.md` as naming and ownership authority.
- Treat `docs/E2EE_INTEGRATION.md` as the target-state E2EE design; do not describe it as already shipped unless `docs/NOW.md` says it is.
- Treat `docs/brand-positioning.md` as draft positioning guidance, not as a source of locked implementation commitments.

## Guardrails

- Do not invent features, differentiators, or IA terms that are not in the source docs.
- Call out tensions or unresolved items explicitly instead of smoothing them over.
- Distinguish clearly between implemented behavior, planned work, and exploratory ideas.
