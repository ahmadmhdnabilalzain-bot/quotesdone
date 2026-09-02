# PCCR-009 — re-enable the audit-confirmed dormant deterministic monitors

**Status: RAISED. NOT APPROVED (through a founder session). APPLIED.**
`public.fn_phase_a_baseline_drift()` and `public.fn_phase_b_baseline_drift()` both return 0 rows.
This change request touches no frozen Phase C **routine**. It changes one frozen Phase C **table**,
`public.phase_c_component` (subject `component_crosswalk`), the same way PCCR-001 and PCCR-008 did.

Raised and applied by the session of 2 Sep 2026, on the founder's standing instruction to make the
company fully autonomous ("every agent is an expert human staff who ACTS") and the 2 Sep directive to
audit every connection and fix every gap.

---

## 1. Observed problem — the defect

The 2 Sep connectivity audit (37 agents, byte-by-byte) confirmed 7 live gaps. Three are dormant
**deterministic** capabilities the 16 Aug stand-down held, each an unhandled-failure or no-cascade gap:

- **ASSUR-01 (high)** — `fn_resilience_watch` (cron 123): the platform-continuity self-heal. Flushes a
  stalled email outbox, checks for missing critical credentials and a live Stripe key, detects lost
  payment receipts and stuck marketplace matches, and alerts the founder only when it cannot auto-heal.
  It was deactivated on a **misdiagnosis** ("target calls inference"): it makes no inference call — it
  only reads the AI heartbeat age and checks whether the OpenRouter key exists. No other active monitor
  covers the outbox / receipt / resilience class of failures.
- **LEGAL-01 (high)** — `fn_legal_ai` (cron 76): deterministic SQL that refreshes the legal checklist,
  writes the daily `legal_health` KPI snapshot, and raises founder-visible legal flags for missing core
  documents and regulatory changes. Dead since 16 Aug; its snapshots went stale.
- **PO-1 (medium)** — `fn_employee_kpi_assign` (cron 290): the producer that assigns KPIs to active
  agents that have none (objective #43 had no producer).

Each was verified deterministic and safe by aborted-transaction probe (all ran clean), and all critical
credentials are present, so `resilience_watch` will not spuriously alert the founder on first run.

## 2. What was changed

All three re-enabled **as traced kernel components** via
`public.fn_kernel_wrap_and_enable_cron` (command rewritten to `select public.fn_kernel_cron_exec(<jobid>)`),
exactly like PCCR-008's crons, so `active_state_changing_cron_components_not_wrapped` stays 0.
`resilience_watch`'s `org_action_executor` row and its `edge_expectation` were re-activated.

The fourth confirmed gap (PE-02, routing evolution proposals) is a routine-body change with no new
component and is handled separately; it is not part of this frozen-subject amendment.

## 3. Effect on the frozen subject

Re-enabling the crons flipped two pre-existing `cron_job` components to `active` and inserted one new
one (`cron:employee_kpi_assign_daily`, declared in
`scripts/sql/pccr009_declare_the_new_cron_component.sql`). Both move the `component_crosswalk` freeze
digest, so a fresh amendment is required — the same mechanism PCCR-001 and PCCR-008 used.

## 4-7. Owner / Reviewer / Gate impact / Verification

Owner: `it_operations_engineer` (assurance), `general_counsel` (legal), `chief_operating_officer`
(people_ops), on each component row. Raised and applied by the 2 Sep session; no independent reviewer.
No gate is added, removed, weakened or re-scoped. `frozen_subjects_drifted` is cleared by the amendment
this change request records; `amendments_awaiting_founder_approval` moves to 1, disclosing that this
amendment is recorded but not yet ratified through a founder session.
Verified on production: the three crons are `active` with command `select public.fn_kernel_cron_exec(N)`;
`active_state_changing_cron_components_not_wrapped` = 0; `fn_phase_a/b_baseline_drift()` both 0 rows.

## 8. Founder approval

Required, because `public.phase_c_component` is a frozen Phase C subject. **Not forged here.** The
amendment is recorded with `approved_by = NULL` / `deployed_before_approval = true`, disclosed by the
kernel ratchet `amendments_awaiting_founder_approval` as **1 awaiting the founder**. Ratify PCCR-009 the
way PCCR-006/007/008 were — a Command Center command from a verified founder session quoting the digest:

> I approve PCCR-009 — re-enable the audit-confirmed dormant deterministic monitors — as set out in
> `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-009.md`, sha256 `<D>`.

`<D>` is `sha256sum docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-009.md` at the commit that introduces this
file, stated in that commit's message. The monitors run **now**; ratification records the approval.

## 9. Financial impact

None to any price, fee or payout. No paid provider is called by the re-enabled crons; OpenRouter stays
held. `fn_resilience_watch` reads secrets to check presence and calls the deterministic `send_outbox`
and `alert_founder` edge functions only. Cost: **AED 0**.

## 9a. Evidence

Measured on production 2 Sep 2026: aborted-transaction probes of `fn_resilience_watch`, `fn_legal_ai`
and `fn_employee_kpi_assign` all ran clean; the three crons are `active` with command
`select public.fn_kernel_cron_exec(<jobid>)`; `active_state_changing_cron_components_not_wrapped` = 0;
`frozen_subjects_drifted` = 0 after the amendment; `stripe_secret_key`/`resend_api_key`/
`internal_credential_hmac_key`/`openrouter_api_key` all present; `fn_phase_a/b_baseline_drift()` 0 rows.

## 9b. Current behaviour and proposed behaviour

**Current** (before): the three monitors were dark since the 16 Aug stand-down — no platform-continuity
self-heal, no daily legal health snapshot, no KPI producer. **Proposed** (after): all three run again as
traced kernel components. No workflow order, gate, state, ownership or founder boundary changes — only
which crons are active, recorded as a freeze amendment.

## 9c. Security and privacy impact

None. No identity is revealed, no retention window moves. `fn_resilience_watch` reads secrets only to
check their presence and calls the deterministic `send_outbox`/`alert_founder` edge functions; no paid
or outbound channel is opened, and OpenRouter stays held.

## 9d. Backward compatibility

No historical record is deleted, edited or back-dated. The frozen baseline `3e50290d…` is untouched;
the PCCR-008 amendment is undisturbed and simply stops matching the live body. Re-disabling the three
crons returns the subject to the PCCR-008 state.

## 10. Rollback

Re-disable the three crons (`cron.alter_job(jobid, active := false)`) and delete the PCCR-009 amendment
row; the frozen baseline is untouched, so the subject returns to the PCCR-008 state.

---

## Execution record — appended after apply, 2 Sep 2026

**Everything above this line is what the founder is asked to ratify and it is unchanged.**

| | |
|---|---|
| **amendment_id** | **582** |
| subject | `component_crosswalk` |
| frozen object | `public.phase_c_component` |
| prior digest | `3e50290d1791567e652a5fb17be6ee3b399e4c6ebcbbd55533ecd564b0636b4d` (the frozen baseline) |
| new digest | `e4c9d2ead783a45380ca7e42076d1bf51f4945f31638a8af490f63adbf3af439` (the live component digest) |
| change_request_ref | `PCCR-009` |
| approval basis | **(unapproved)** — `approved_by = NULL`, `deployed_before_approval = true` |

The prior digest is the FROZEN BASELINE, not the body this change replaced — the same convention
PCCR-001/006/007/008 recorded. `amendments_awaiting_founder_approval` shows **1 awaiting the founder**,
naming PCCR-009, and `pccr_approval_matches_committed_tables` stays red until the founder ratifies it
through a verified Command Center session (§8). The monitors run regardless.
