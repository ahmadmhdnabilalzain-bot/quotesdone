> **Archived 16 Nov 2026** (simplification wave B, it_engineer): it describes the V3 certification and remediation programme of Aug 2026; the agent_brain, agent_train and os_api functions it ran on are gone from supabase/functions. 4 of the 11 routines it names are gone from production (SELECT pg_proc, 16 Nov 2026). History, not the build today.

# V3 remediation — Stage 5: role identity and runtime isolation

**Measured against** Supabase project `pglpqrhvozwepymcuunn` (staging) on 2026-08-14, and against
`scripts/sql/v3_repair_06_role_isolation.sql`, `scripts/checks/v3_remediation_regression.mjs` and
`docs/knowledge/certification/V3_CERTIFICATION_RESULTS_BY_ROLE.csv`.

**Nothing here certifies anything.** Certification is an independent evaluator's judgement; this is
internal repair work and internal measurement. No role, department or category named below is
certified, and the sealed result of record `V3-COR-0A782DA90B10` (56.97% overall, 0 of 96 roles
certified) is unchanged by any of it.

---

## 1. The distinction this stage draws

Sharing an execution **service** is allowed: one Deno process, one model route, one context
assembler. Sharing **role identity, authority, evidence, KPI context or approval responsibility**
is not. Against those five:

| Dimension | State today | Measurement |
|---|---|---|
| Identity | **shared** | `fn_agent_context_v3` takes `p_agent_key` and no role argument; it emits `packaged_role_ids` as an array of every role the agent holds and `readiness` as `jsonb_agg(distinct readiness)` — a set, not a value |
| Authority | **shared** | 90 agents have exactly 1 active `org_role` row and 0 have more than one, so each shared agent carries one `authority_level` for 2–3 roles (`qa_manager` = `stop_authority` for director, analyst-controller *and* operations-specialist) |
| Evidence | **shared in practice** | `agent_tool_call` has a `role_id` column; 0 of 83 recorded calls populate it. All 10 registered tools are role-open (`authorised_roles` `{}` or `*`); 0 are role-scoped. `fn_agent_tool_allowed` keys on the agent, and `fn_agent_tools` grants the **union** of its roles (`me.role_ids && t.authorised_roles`) |
| KPI context | **shared** | `employee_kpi` has no role column at all; 122 active KPIs across 94 agents; 20 of the 26 colliding agents hold exactly 1 active KPI for 2–3 roles; `decision_trace.relevant_kpi` is null on all 30 traces |
| Approval responsibility | **recorded, not routed** | `runtime_reviewer` is set on 54 of 67 `role_isolation_decision` rows, but only three routines reference that table — the guard, the status reporter and `fn_role_readiness_recompute`. `fn_pick_reviewer` does not read it |

The one dimension that genuinely moved is **trace attribution**: 22 of 30 `decision_trace` rows
carry `role_id`, across 12 distinct roles — the first place in this runtime where a role, not an
agent, is the subject of a record.

---

## 2. Every shared runtime agent

`v_role_identity_collision` returns **26 collisions** covering **62 distinct packaged roles**.
`org_role_identity` holds 133 rows over 96 roles and 94 agent keys. By exclusivity: 17 roles are
exclusive 1:1 (one agent, holding no other role); 57 have a single agent that also serves other
roles; 17 have several agents, none shared; 5 have several agents of which at least one is shared.
68 agents serve 1 role, 13 serve 2, 13 serve 3.

Every collision spans seniority tiers except two (`knowledge_validator`, `supplier_analyst` — both
reviewer/analyst pairs across two packaged departments). `required_verdict` is `split` on 25 of 26
and `isolate` on `supplier_analyst`. Creator/reviewer conflict is flagged on 17 of 26;
manager/subordinate on 15 of 26. Thirteen agents carry three roles each on one authority level and
one KPI: `ai_director`, `analytics_director`, `bd`, `ceo`, `comms_manager`, `doc_intel_manager`,
`eng_manager`, `followup`, `hr_director`, `payments_manager`, `qa_manager`, `sales_director`,
`trust_safety_mgr`. Eleven carry both conflict classes; `qa_manager` and `trust_safety_mgr` are
manager/subordinate only, because none of their archetypes is `reviewer-auditor`.
`analytics_director` holds three roles while `active = false`.

**Knowledge difference, measured.** Every packaged role has exactly 5 `role_specific` rows in
`ops_knowledge`. `fn_context_slice` filters `role_key = any(p_role_ids)` and `fn_agent_context_v3`
passes *all* of the agent's roles at `budget/3` — 8,000 chars by default, each record capped at
1,800, so at most 4 survive. Run for the three QA roles on "review the quarterly test evidence and
close the open defects", it returned **2 records from `qa-and-testing-director`, 2 from
`qa-and-testing-operations-specialist`, 0 from `qa-and-testing-analyst-controller`**. A single-role
agent competes 5 rows for that budget; a three-role agent competes 15. The role knowledge an answer
receives is not the role's own.

---

## 3. `fn_role_isolation_status()` in full

Measured 2026-08-14T14:11:10.067485+00:00:

| Field | Value | What it actually counts |
|---|---|---|
| `collisions` | 26 | rows in `v_role_identity_collision` — agents serving >1 packaged role |
| `roles_in_collision` | 65 | `sum(roles_served)`. **These are role-slots, not roles.** The distinct count is 62; three roles are served by two colliding agents each and counted twice |
| `unresolved_cross_seniority_collisions` | 1 | spans tiers *and* `roles_without_decision > 0`. The one is `intel_director` (director + operations-specialist, `data_analytics`) |
| `unresolved_self_approval_conflicts` | 0 | creator-vs-reviewer identities with no decision row. 47 such identities exist; all 47 are dispositioned |
| `decisions` | split 30, isolate 19, block 13, restrict_to_advisory 5 | 67 rows, all `decided_by = 'v3_repair_06_role_isolation'`, all at 13:52:01.69972+00 |
| `roles_with_no_decision_and_no_conflict` | 66 | **misnamed twice.** It counts `org_role_identity` *rows* (133 total) with no matching decision, and never tests for absence of conflict. 133 − 67 = 66 |
| `certification_dispositions` | NOT_CONNECTED 5, BLOCKED_CRITICAL_FAILURE 13 | 18 rows over 14 role ids; `marketplace-operations-operations-specialist` maps to 5 spec agents |
| `certification_role_ids_dispositioned` | 14 | 5 + 9, all accounted for in §4 |
| the three `guard_*_installed` flags | all true | `a00_role_identity_isolation_guard`, `review_chain_no_self_approval_ck`, `a00_artifact_review_author_is_not_reviewer` |
| `review_chain_legacy_self_rows` / `_approvals` | 6 / 2 | measured directly: `review_chain` has 44 rows, 6 self-authored, 2 of those approved. The constraint is `NOT VALID`, so they are exempt and were not rewritten |
| `mapping_type_drift` / `readiness_drift` | 0 / 0 | `fn_role_readiness_recompute` honours `isolation_resolution` above every other rung, so it cannot silently undo a `block` |

---

## 4. Disposition of all 14 certification-status roles

**5 NOT_CONNECTED → `restrict_to_advisory`**, `readiness = restricted_to_advisory` confirmed on
every one in `org_role_identity`:

| Role | Agent | Recorded reviewer | Conflict classes |
|---|---|---|---|
| `customer-success-analyst-controller` | `followup` | `brief` (escalated up the chain; no independent reviewer in department) | creator_reviewer, manager_subordinate, cross_seniority, certification_not_connected |
| `customer-success-director` | `followup` | `brief` | same |
| `customer-success-reviewer-auditor` | `followup` | `brief` | same |
| `marketing-director` | `marketing` | `sales_director` (escalated up the chain) | creator_reviewer, cross_seniority, certification_not_connected |
| `marketing-reviewer-auditor` | `marketing` | `sales_director` | same |

**9 BLOCKED_CRITICAL_FAILURE → `block`**, `readiness = blocked` confirmed on every one:

| Role | Agent(s) | Recorded reviewer |
|---|---|---|
| `legal-and-compliance-director` | `legal` | `compliance_mgr` (independent reviewer in department) |
| `qa-and-testing-analyst-controller` | `qa_manager` | `ai_qa_specialist` |
| `qa-and-testing-director` | `qa_manager` | `ai_qa_specialist` |
| `qa-and-testing-operations-specialist` | `qa_manager` | `ai_qa_specialist` |
| `trust-and-safety-operations-specialist` | `trust_safety_mgr` | `legal` (escalated up the chain) |
| `marketplace-operations-operations-specialist` | `spec_commercial`, `spec_construction`, `spec_fitout`, `spec_industrial`, `spec_mep` | none recorded |
| `marketplace-operations-reviewer-auditor` | `supplier_verification` | none recorded |
| `supplier-knowledge-operations-specialist` | `category_curator` | none recorded |
| `supplier-success-operations-specialist` | `supplier_retention` | none recorded |

15 packaged roles are `blocked` in total — the 9 above plus the three
`data-analytics-and-intelligence-*` roles, `marketing-operations-specialist`,
`notification-and-communications-operations-specialist` and `supplier-knowledge-analyst-controller`,
blocked by the readiness rungs rather than by a certification status. `readiness` distinguishes
15 blocked / 76 advisory / 8 tools_connected roles (they sum above 96 because a role with several
agent rows can hold two readiness values). **Nothing enforces it.** `fn_agent_context_v3` publishes
`readiness` in the identity blob with zero refusal branches keyed on it; `fn_agent_autonomy_blocked`
reports it and refuses nothing. A blocked role that is invoked still gets a full context.

---

## 5. The guard, and exactly what it covers

`fn_role_identity_isolation_guard` (`scripts/sql/v3_repair_06_role_isolation.sql:384`), fired by
`a00_role_identity_isolation_guard` BEFORE INSERT OR UPDATE OF `agent_key`, `packaged_role_id`,
`packaged_department`, `archetype`. Two **aborted-transaction probes** (each ended with
`raise exception`, so both rolled back; no row survives):

* **A** — insert `cfo` as a `reviewer-auditor` in `finance`, where it already holds
  `finance-director`, with no decision recorded. **Refused**, errcode 23514: *"agent cfo would be
  both producer and independent reviewer of finance"*.
* **B** — the same insert preceded by a `role_isolation_decision` row for that exact
  (agent, role, archetype). **Permitted**, 1 row inserted. The escape hatch is keyed on the
  archetype, not just the role id.

**Its scope is one conflict class.** The predicate only pairs `reviewer-auditor` against
`director | operations-specialist | analyst-controller` *within the same packaged department*. It
covers neither manager/subordinate sharing nor one agent holding roles in two packaged departments.
That is not a theory — it is visible in the drift. Three `org_role_identity` rows were written at
**14:09:07**, after the stage-6 script (13:52:01) and after the regression run (14:02), creating
three undispositioned collisions: `intel_director` (director + operations-specialist, one
department), `knowledge_validator` and `supplier_analyst` (same archetype, two departments each).
The guard passed all three because none is a creator-vs-reviewer pair. Between the harness run and
my measurement, `collisions` went 23 → 26, `roles_in_collision` 59 → 65, `roles_with_no_decision`
63 → 66 and `unresolved_cross_seniority_collisions` 0 → 1.

### What it adds on top of the pre-existing guards

* `fn_pick_reviewer` — when the author is the department head, routes to an in-department
  `independent_reviewer`, then one level up, then refuses. Acts **when a review is assigned**.
* `review_chain_no_self_approval_ck` — `CHECK (reviewer_agent <> author_agent)`, `NOT VALID`, so it
  binds new rows only. Acts **when a review row is written**.
* `fn_artifact_review_valid` — refuses `verdict = 'pass'` when reviewer equals author. Acts **when a
  verdict is recorded**.

All three act after the identity exists. The new guard acts **when the identity is defined**: an
agent cannot be given a conflicting second role unless someone signed for the conflict first. That
is the only genuinely new property in this stage.

---

## 6. Still broken or unverified

1. **A split is a decision, not a role.** 30 `split` decisions across 20 agents. `org_agents` holds
   94 rows, 90 active, **0 created on 2026-08-14** — and the same 94 keys appear in
   `org_role_identity`. **0 of the 30 splits exist in the runtime.** Roles actually isolated today:
   **17 of 96**. 79 are not.
2. **Evidence is still agent-attributed.** 83 tool calls, 0 with `role_id`. Until
   `fn_record_tool_call` receives the role, a shared agent's tool history cannot be split.
3. **Tool grants are the union of the roles.** All 10 tools are role-open, so the union costs
   nothing today — but the moment one is role-scoped, a 3-role agent inherits it for all three.
4. **KPI context cannot be isolated without a schema change.** `employee_kpi` is keyed on agent only.
5. **The recorded reviewer is not routed**, and **`readiness` is advisory**: 54 `runtime_reviewer`
   values and 15 blocked roles, with no routine on the answering path reading either.
6. **The regression harness cannot pass STR-ROLE-003.** `scripts/checks/v3_remediation_regression.mjs:205`
   reads `s.s?.unresolved_cross_seniority ?? 1`; the function emits
   `unresolved_cross_seniority_collisions`. The key never resolves, `?? 1` applies, and the check
   fails whatever the value is. It failed at 14:02 while its own printed payload read `0`.
7. **STR-ROLE-002's label does not match its query.** Lines 193–196 count *agents* holding both
   `director` and `reviewer-auditor` anywhere, ignoring department; the label says "self-approval
   identities". Both are real and different: 18 agents, 47 identities.
8. **Unverifiable here.** `fn_pick_reviewer`'s comment cites "285 of 1,882 review_chain rows".
   Staging holds 44 rows, 6 self-authored, 2 self-approved. I did not measure production and cannot
   reconcile the 1,882.
9. **Nothing in this stage was re-certified.** The defects it addresses (`ROLE_MAPPING_ERROR` on 59
   roles, 5 NOT_CONNECTED, 9 BLOCKED) can only be cleared by an independent re-run.
