# Launch Step 1 — org connectivity, workflow & approval chemistry

**Done 2026-08-31 on production `htdblwldjkcgjvmqkbeh`. Zero paid inference. Read-back verified. Under every hold.**

Step 1 of the launch plan: make the autonomous company *connect like a real company*, and prove it in
code. The founder sets one target (AED 1,000,000 by Aug 2027) and approves only refunds; everything
else the AI staff must do themselves. For that to be real, four signals must actually travel.

Every claim below was established by MEASUREMENT against the live database, and every write path is
proven with an aborted-transaction probe (do the write, count the effect, RAISE to roll it back), so
verification left no residue. The durable proof is `scripts/checks/org_connectivity_signal_path.test.mjs`
— it re-runs all four paths on demand and currently **PASSES all assertions**.

## What was already correct (confirmed, not assumed)

- **The AI-managerial approval tier** (built 28 Aug) is deployed and routes: every one of the 10 active
  departments resolves a real, active, entitled approver — medium risk to the department head, high
  risk escalating to the CEO. `required_authority='founder'` is on exactly one action class
  (`refund_within_window`) and nowhere else. Re-proven end-to-end by probe.
- **Reporting-line escalation** travels: 176 active roles, every one carries an escalation target, and
  a non-apex escalation lands on an active manager who outranks the escalator.
- **Every active department is reachable**: all 10 have at least one active employee to receive a
  handoff (exec 4 … marketplace 17).
- **The inter-department handoff contract** (`fn_handoff_open` → `agent_actions` queue →
  `fn_agent_handoff_inbox` → `fn_handoff_respond` → `fn_handoff_close`) was coherently wired but had
  never been exercised (0 contracts). Now proven end-to-end.

## Defects fixed (deployed + verified in the same turn)

| # | Requirement | Defect (measured) | Fix | File |
|---|---|---|---|---|
| A | Escalation | The CEO's escalation resolved **DOWN** to a subordinate (`brief`/chief_of_staff) via the exec fallback, because the apex has no `manager_key`. The founder's rule is that only the CEO's major-issue escalation reaches him. | `fn_should_escalate` gains an apex branch: an active actor with no `manager_key` routes to `founder` (`apex_to_founder`), resolved before any subordinate owner. | `scripts/sql/launch_step1_ceo_escalates_to_founder.sql` |
| B | Target cascade | Two founder-facing readers (`fn_company_state`, `fn_founder_brief`) counted `org_objectives` — a table with **0 rows and 0 writers** — so they reported 0 active objectives while 92 real ones sat in `department_objective`. | Repointed both to `department_objective` (surgical replacement on the live definition; the rest byte-identical). `open_objectives` now reads **92**. | `scripts/sql/launch_step1_founder_reports_read_live_objectives.sql` |
| C | Target cascade | `fn_org_task_assign` ranked agents per task and kept only `pick=1`, so with a department's agents idle it piled every task onto the single alphabetically-first agent, assigned at most one agent's cap per sweep, dropped the rest, and falsely logged an idle department as "oversubscribed". | Greedy per-department fill: one task at a time to the currently-least-loaded eligible colleague, recomputed each pick (in-transaction), so a sweep fills the department. Proven: 37/37 assigned in one sweep (was 17), spread 5/5/4/4/4/4 across customer_experience. | `scripts/sql/launch_step1_task_assign_fills_the_department.sql` |
| D | Target cascade | `trg_goal_cascade` fired AFTER UPDATE only and acted solely on goal *retirement*; a new or edited target propagated nothing downward (its weekly `fn_goal_decompose` driver is stood down). | Added a decompose arm (objectives only, never tasks — K31 stays honoured) and widened the trigger to AFTER INSERT OR UPDATE. Proven: inserting a new measurable target immediately creates its `department_objective`. | `scripts/sql/launch_step1_a_new_target_cascades.sql` |
| G | Escalation | The declared escalation graph carried six edges that did not resolve: three HR roles pointing at the *agent key* `hr_director` instead of the *role id* `agent_workforce_capability_director`; a `chief_of_staff` self-edge; `organization_designer` pointing at the retired `chief_performance_officer`; and `marketplace_director` carrying a duplicated target and omitting its manager. | Data-only corrections (no count change → Phase A freeze passes). After: 0 self-edges, 0 unresolved internal edges; only `ceo → founder` remains (by design). | `scripts/sql/launch_step1_escalation_targets_resolve.sql` |

Nothing touched a frozen subject (verified against `phase_c_frozen_subject`); Phase A and Phase B
baseline drift are both **0** after the change. `CREATE OR REPLACE` preserved the SECURITY DEFINER
ACLs (no new PUBLIC grants to revoke).

## Deliberately NOT done in Step 1, and why (honest disclosure)

These were measured and are real, but they are the wrong tool for a *connectivity* step, or belong to a
later stage the founder gated. They are recorded so the next step inherits them, not lost.

- **32 of 63 company goals have no `measure_sql`** so they cannot hand down. 27 carry
  `no_measure_reason = 'NO INSTRUMENT EXISTS'` (need a source table) and 5 are a founder business
  decision (numerator/denominator). This is an instrument-build backlog (Stage 2/3), not wiring.
- **29 unlinked department objectives / 29 orphan role KPIs.** Back-linking each needs a curation
  judgement (which goal it serves); forcing a wrong link is worse than an honest gap. Left for a
  curation pass rather than fabricated.
- **`org_tasks.objective_id` is 100% NULL** — the analytical task→objective backlink is written by
  ~16 task creators and populating it is Stage-3 work; the cascade *spine* (goal → dept objective →
  role KPI → owner) is proven regardless.
- **`escalate_founder` sits on the irreversible-no-compensation refuse floor**, so the founder-alert
  *action* cannot auto-dispatch unattended. That is the founder-notification channel, explicitly
  **Stage 4** ("make the founder's ONE channel flawless"); changing its flags risks his inbox and is
  his call. Step 1 fixes the escalation *routing* (CEO → founder), not the alert *delivery*.
- **The stood-down driver crons** (`fn_goal_decompose`, `fn_org_task_assign`, `fn_event_dispatch`,
  the measure jobs, the action-invoke sweeps) remain inactive. Re-activating automation spends money /
  fires effects — Stage 3, the founder's call. Step 1 proves each mechanism works by calling it
  directly; it does not turn the crons back on.
- **13 producer-less event subscriptions** (rfq.created, quote.received, invoice.received, …) await
  Phase D emitters or a product decision; they are the live-business flow (Stage 2/3), not Step-1
  plumbing. The `company_event → subscription → dispatch → task` backbone itself is live (2,142
  deliveries, latest today).
- **`fn_goal_attainment` horizon mismatch** (`year_1` vs `annual`) is latent — no current caller
  passes the mismatched literal (`fn_founder_brief` passes `'monthly'`). Noted, not fixed, to keep
  Step 1 on real plumbing.

## Verification summary

- `scripts/checks/org_connectivity_signal_path.test.mjs` → **PASS, 0 failures** (all four requirement
  paths + reachability, all by aborted-tx probe or read-only measurement, zero paid inference).
- Each of the 5 migrations applied via `scripts/apply_sql.mjs --apply` and **read back identical** to
  its file.
- Schema mirror regenerated (`export_from_either_source_is_identical.mjs --write`) → **identical: YES**,
  0 embedded project refs.
- `fn_phase_a_baseline_drift()` and `fn_phase_b_baseline_drift()` → **0 rows** each.
- `fn_os_portals_gates()` → unchanged by this work (the two `not_met` gates — model-call logging and
  monitoring crons — are pre-existing stand-down/no-traffic artifacts, not regressions).
