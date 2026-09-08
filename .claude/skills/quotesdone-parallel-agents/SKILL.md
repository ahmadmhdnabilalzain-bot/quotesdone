---
name: quotesdone-parallel-agents
description: The founder's standing rule of 8 Sep 2026 — use as many agents as possible, in parallel, to speed the work up. Fan out by default; work serially only when a step genuinely depends on the one before it.
---

# Use as many agents as possible

Founder's instruction, 8 September 2026: **"use multiple agents. its taking ages for every task"**
and **"use as many agents possible to speed up the process"**.

This is a standing rule about HOW the session runs, not a suggestion for one task. It sits beside
`quotesdone-session` (conduct) and `quotesdone-build-until-done` (do not stop).

---

## 1. Fan out by default

Before starting anything that takes more than a couple of minutes, ask: **how many independent
pieces does this split into?** Then start them all at once.

- **Independent tool calls go in ONE message.** Two greps, three reads, a database query and a
  `gh` call with no dependency between them are one message with five tool calls, never five
  messages. This alone removes most of the waiting.
- **Independent investigations go to subagents**, launched together in a single message so they run
  concurrently. The Agent tool's own guidance: multiple agents in one message run in parallel; one
  per message runs them in series and wastes the point.
- **Long work goes to the background**, and you pick up different work while it runs. Never idle
  against a clock. A full `npm test`, a CI run, an import, a scorer — background it, then keep going.

## 2. What this repository splits into naturally

These have all been done serially at least once and should not be again:

| Work | The split |
|---|---|
| A sweep over the estate | one agent per family (phase, kernel, marketplace, knowledge, messaging) |
| Reading a failing suite | one agent per failing check file, each reporting cause + verdict |
| An audit question | one agent per source: database, edge functions, the app, scripts, CI |
| A build with N requirements | one agent per requirement, then one to reconcile |
| "Is X still referenced?" | repo / database / cron / views / data — four agents, one answer |
| Verifying a claim | one agent to prove it, one to refute it, and believe the one with the measurement |

## 3. What must NOT be parallelised

Parallel is for reading, searching, measuring and drafting. It is not for these:

- **Writes to production.** One applier, in order. Two agents applying SQL to
  `htdblwldjkcgjvmqkbeh` at once is how a half-applied migration happens.
- **Anything with a dependency.** A callee must exist before its caller is created; a schema mirror
  is regenerated AFTER the last apply, not beside it.
- **git commits, pushes and merges.** One writer to the index.

When a step genuinely depends on the previous one, say so and run it in order. Speed is the goal;
a corrupted apply is not faster.

## 4. Reporting

Subagent output is not shown to the founder — **relay the conclusion, not the transcript.** Ten
agents reporting back is still one short answer to him. Do not narrate the fan-out while it is
running; that is the check-in `quotesdone-session` forbids.

---

**Why he asked.** On 8 Sep a single dead-routine sweep ran as one long serial chain — closure, then
dependency check, then generate, then apply, then a full suite, then attribution — each step waiting
on the last, several of them minutes long, when the measuring steps were independent of each other
and could all have started at once.
