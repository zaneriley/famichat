---
name: research
description: Spawn parallel research agents to explore a topic from multiple angles. Creates structured output in .tmp/ for synthesis.
argument-hint: "<slug> [--agents N] [--angles 'a,b,c'] [--model haiku|sonnet]"
---

# Research

Spawn parallel agents to explore a topic from independent angles. Each agent reads the canonical project docs, writes a structured report, and the results feed into `/synthesize`.

## Invocation

```
/research <slug>                              # 3 agents, default angles
/research <slug> --agents 5                   # 5 agents, auto-assign angles
/research <slug> --angles "governance,ux,technical"  # explicit angles
/research <slug> --agents 5 --model haiku     # specify model (platform-dependent)
```

The slug is **required**. It determines the output directory and is how `/synthesize` finds the results.

## Directory Structure

Create the output directory:

```
.tmp/<YYYY-MM-DD>-<slug>/round-N/
  manifest.md
  01-<angle-slug>.md
  02-<angle-slug>.md
  ...
```

To determine N: glob for `.tmp/*-<slug>/round-*/` directories. Use max round number + 1. If none exist, N = 1.

Write `manifest.md` before spawning agents:

```markdown
# Round N Manifest

- **Topic:** <from conversation context>
- **Date:** <ISO 8601>
- **Slug:** <slug>
- **Angles:** <list with descriptions>
- **Agent count:** N
- **Model:** <if specified, else "default">
- **Status:** in-progress
```

Update manifest status to `complete` (or `partial` if agents failed) after all agents finish.

## Canonical Doc Injection

Every research agent reads these files. Always. All of them:

1. `docs/brand-positioning.md`
2. `docs/E2EE_INTEGRATION.md`
3. `docs/ia-boundary-guardrails.md`
4. `docs/ia-lexicon.md`
5. `docs/NOW.md`
6. `docs/SPEC.md`
7. `docs/BACKLOG.md`

If this is round 2+, also inject the previous round's `consensus.md` (if it exists) so agents can build on prior findings.

## Default Angles

If `--angles` is not specified, use these defaults (trim to match `--agents` count, or auto-generate additional angles if `--agents` exceeds 5):

| Angle | Slug | Focus |
|-------|------|-------|
| Technical Architecture | `technical` | System design, data model, migrations, performance, implementation feasibility |
| UX and Service Design | `ux` | User flows, copy, error states, multi-step interactions, empty states |
| Security and Abuse Resistance | `security` | Attack surfaces, rate limiting, trust model, edge cases |
| IA/DDD Compliance | `ia-ddd` | Naming, bounded contexts, ownership violations, lexicon drift |
| Product Strategy | `product` | Alignment with SPEC layers, feature scope, what to defer, what to cut |

If the user provides explicit angles via `--angles`, use those instead. Each angle string becomes both the agent's focus directive and the filename slug.

## Agent Prompt Template

Each agent gets this prompt structure (fill in the angle-specific parts):

```
You are a <angle name> analyst for Famichat.

READ these canonical docs first:
[list all 7 docs with full paths]

[If round 2+]: Also read the previous round's consensus:
[path to previous consensus.md]

[If user provided additional context files]: Also read:
[additional files from conversation context]

YOUR ANGLE: <angle name>. Think through:
<angle-specific focus questions from the table above, plus any the user specified>

Write your analysis to: <full path to output file>

## Required Output Structure

Use this exact structure:

# <Angle Name>: <Topic>

## Summary
<!-- 2-3 sentence executive summary -->

## Findings

### Finding 1: <title>
- **Severity:** blocker | should-fix | informational
- **Evidence:** <what was observed, with file:line references>
- **Recommendation:** <what to do>

### Finding 2: ...

## Recommendations (ordered by priority)
1. ...
2. ...

## Open Questions
<!-- Things this angle could not resolve; needs input from other angles or the user -->
```

## Spawning

Use the Task tool to spawn agents in parallel. Set `run_in_background: true` for all agents. If `--model` is specified, pass it as the `model` parameter.

If the Task tool is unavailable (platform limitation), degrade to running each angle sequentially in the main thread. Warn the user: "Parallel agents unavailable. Running angles sequentially — this will take longer."

## After All Agents Complete

1. Update `manifest.md` status to `complete` (or `partial` with notes on which agents failed).
2. Report to the user: which agents completed, any failures, and suggest running `/synthesize <slug>` next.

## Rules

- Do NOT synthesize or draw conclusions. That is `/synthesize`'s job.
- Do NOT edit any canonical docs. Research is read-only on project state.
- Do NOT produce an execution plan or DAG. That is a separate concern.
- Each agent writes exactly one file. No shared state between agents.
- If an agent fails, the round is still usable. Note the gap in the manifest.
- Check BACKLOG.md and BACKLOG-ARCHIVE.md before flagging something as new — note if a finding is already tracked or already done.
