# QuotesDone Agent Runtime Connection Blueprint — v2026.08.14

## Purpose

This package is the **normative connection map** for the current QuotesDone autonomous-company runtime:

- **10 canonical departments**
- **90 accountable standing roles**
- **86 on-demand category knowledge overlays**
- **12 managers**: 6 persistent + 6 scheduled
- **33 event-driven operators**
- **35 on-demand functional specialists**
- **10 independent reviewers**

It addresses the failures exposed by the first V3 certification: disconnected tools, null decision traces, missing knowledge retrieval, cross-department errors, poor tool selection, truncated outputs, role identity collisions, weak revenue linkage and uncontrolled test cost.

## Give this ZIP to Claude Code

Use `CLAUDE_MASTER_IMPLEMENTATION_PROMPT.md` as the first instruction. Claude must compare this target with the current code:

- keep an existing implementation when it is demonstrably equivalent or better;
- repair partially connected implementations;
- build missing connections;
- remove conflicting duplicate runtime paths;
- never replace a better working design merely to match file names.

## Critical order

1. Canonical identity and organization resolution
2. Tool broker and real tool-result envelopes
3. Decision-trace coverage
4. Task-time knowledge retrieval
5. Model/task routing and cost control
6. Structured output and truncation protection
7. Cross-department handoffs
8. Deterministic smoke tests
9. Small model-based smoke tests
10. Targeted regression
11. Independent certification only after all gates pass

## Do not run the full 2,284-question certification yet

A full run is prohibited until the zero/low-cost readiness gates in `IMPLEMENTATION_ACCEPTANCE_GATES.md` pass. The certification runner must use a dedicated OpenRouter key with a hard budget guardrail.
