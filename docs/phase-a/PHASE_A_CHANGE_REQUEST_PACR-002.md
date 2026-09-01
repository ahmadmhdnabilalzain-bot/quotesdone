# PHASE A CHANGE REQUEST — PACR-002

**The organisation takes a real-company reporting shape.**

Status: APPLIED 1 Sep 2026 · Approver: founder · Migration: `scripts/sql/pacr_002_the_real_company_reporting_shape.sql`

---

### 1. Subject
`registry:reporting_graph` — the Phase A frozen reporting graph (`org_role.manager_role_id` over active canonical roles), its runtime mirror (`org_agents.manager_key`), the Phase C reporting authority (`public.phase_c_reporting_authority`), and the executive-committee membership (`public.org_role_committee`).

### 2. What is frozen today
The 15 Aug baseline (`org_phase_baseline` where `phase='A'`) fixes the reporting-graph digest = sha256 over `role_id | coalesce(manager_role_id,'founder') | primary_department_id` for every active, non-overlay canonical role. On that graph the CEO carried **12** direct reports, and `marketplace_director`, `customer_success_director`, `corporate_performance_director` and `strategy_director` all reported to the CEO. Counts: 10 departments / 90 canonical roles / 86 category overlays.

### 3. What is proposed
Move exactly four manager edges so the organisation has the shape a real company has:

| Role | From | To |
|---|---|---|
| `marketplace_director` | `ceo` | `chief_operating_officer` |
| `customer_success_director` | `ceo` | `chief_operating_officer` |
| `corporate_performance_director` | `ceo` | `chief_of_staff` |
| `strategy_director` | `ceo` | `chief_of_staff` |

After the move the CEO chairs an **eight-seat executive committee** — `cfo`, `chief_of_staff`, `chief_operating_officer`, `chief_revenue_officer`, `cto`, `data_intelligence_director`, `general_counsel`, `quality_and_release_director`. The **COO** (`chief_operating_officer`) owns all of operations (marketplace + customer success + its own people/ops, six direct reports). **Independent Assurance** (`quality_and_release_director`) and **Legal** (`general_counsel`) report to the CEO for independence. The **Chief of Staff** runs the **Office of the CEO** (`corporate_performance_director` + `strategy_director`) instead of line-managing the C-suite. `marketplace_director` and `customer_success_director` leave the executive committee (the COO represents operations on it); the Office of the CEO stays as standing advisers.

### 4. Why
The founder's instruction: restructure the org to a real-company shape. In the frozen graph the COO did not own operations — the marketplace and customer directors reported straight to the CEO — and the CEO had twelve direct reports, which is not an executive committee. This is the missing half of the real-company shape the 15 Aug baseline began.

### 5. Evidence
- Frozen graph before: CEO had 12 direct reports (`select count(*) from org_role where manager_role_id='ceo' and status='active'` = 12).
- After the four edges: CEO = 8, COO = 6, Chief of Staff = 2 (verified by aborted-transaction probe and again post-apply).
- No role reports to `corporate_performance_director` or `strategy_director`; 13 roles (5 under customer success, 8 under marketplace) have their `reporting_path` re-walked because it now runs through the COO.

### 6. Phase A impact
`registry:reporting_graph` digest moves to the new graph and is **re-recorded in place** in `org_phase_baseline` from the same expression `fn_phase_a_baseline_drift()` uses — never a transcribed hash. The organisation fingerprint (`organization_sha256`) is recomputed with the same six sources `scripts/phase_a/freeze.mjs` uses. Counts unchanged at **10 / 90 / 86**. `fn_phase_a_organization_violations()` = 0. `fn_phase_a_baseline_drift()` = 0 after apply.

### 7. Phase B impact
**None.** No workflow, workflow order, state, transition, gate, business rule, handoff accountability, category-overlay authority or founder boundary changes. `fn_phase_b_baseline_drift()` = 0 after apply; `z90_phase_b_freeze` not touched.

### 8. Phase C / D impact
`public.phase_c_reporting_authority` is re-recorded: the four `manager_role_id` values and every `reporting_path` re-walked from the new live graph, so `fn_phase_c_reporting_map_drift()` = 0 (the walk in this migration is byte-identical to the walk the drift check uses). The Phase C autonomous-routing rule keys on `phase_c_step_binding.accountable_role_id`, which no role's manager change touches, so it is unaffected. The Phase D dispatch gate still reaches EXECUTED (reporting-line moves do not change step ownership).

### 9. Backward compatibility
`org_agents.manager_key` is moved edge-for-edge with the canonical graph, so the runtime escalation walk (`fn_should_escalate`, `fn_org_task_assign`) stays consistent: no agent is managed by an inactive or missing manager, no self-management, the apex is still `ceo`, and only the CEO points at the founder (all re-verified by `org_connectivity_scenarios`). The executive-committee membership is read only by `fn_agent_context_v3` (an agent's context), so removing two members simply removes those two agents' committee context — correct, since they no longer sit on it.

### 10. Rollback
Restore the four `org_role.manager_role_id` and `org_agents.manager_key` edges to `ceo` / their prior runtime managers, restore the two `org_role_committee` rows, and re-record the baseline digests in place (drop → update → recreate the append-only guard). A down script mirroring the reverted commit `461ec61` restores the exact 15 Aug values.

### 11. Change-reason string
```
set local app.phase_a_change_reason =
  'PACR-002: real-company reporting shape — marketplace_director and customer_success_director to '
  'chief_operating_officer, corporate_performance_director and strategy_director to chief_of_staff. '
  'The CEO chairs an 8-seat executive committee; the COO owns operations; the Office of the CEO sits '
  'under the Chief of Staff. Counts unchanged at 10/90/86. Approver: founder, 1 Sep 2026.';
```
