---
name: a-documented-impossibility-is-still-a-claim
description: "A comment saying \"NO TABLE IN THIS ESTATE HOLDS THESE\" reads as diligence and was wrong about three of four keys; an impossibility claim needs measuring like any other."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ba4ede58-946f-4477-8042-69cef19ee057
  modified: 2026-08-20T04:17:09.036Z
---

`fn_phase_d_step_inputs` ended with an `else` branch and this comment:

> `-- external_and_internal_evidence, current_cash_budget_and_commitments, budget_envelope,`
> `-- resource_envelope. NO TABLE IN THIS ESTATE HOLDS THESE. Naming them here as unresolved is the`
> `-- honest answer; filling them with a placeholder would make the step complete on a fact it never had.`

The second sentence is right. **The first was wrong for at least three of the four**, measured
20 Aug 2026: `department_budget` 10 rows (monthly_aed, spent_aed, degrade/halt thresholds),
`org_agents` 90 active over 10 active departments, `gl_journal` 73 posted entries, `company_event`
1,452/30d, `company_index` 60/90d, `decision_trace` 114/30d.

Because the comment was careful, honest-sounding and self-aware, it read as a closed question. It had
kept every W01 step at `INPUTS_UNRESOLVED` since it was written.

**Why:** a claim phrased as a *limitation* invites agreement, not testing. "We can't, and here is why
we won't fake it" sounds like the end of an investigation; it is often the start of one.

**How to apply:** when code or a document says something is impossible, unavailable, or has no
source, treat it as a measurement to redo — name the candidate relations and count their rows. Then,
if it really is unavailable, say so **as a field in the payload** rather than as a silence:
`cash_position_available: false`, `external_available: false`. And keep the good half of the original
instinct — refuse on an empty source rather than passing an empty object, or you land on
[[absent-input-scores-as-satisfied]]. Related: [[specs-are-upgrades-not-repairs]],
[[finished-capability-with-no-entry-point]], [[guarded-by-a-condition-that-cannot-occur]].
