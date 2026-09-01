# PBCR-003 — the security stop-authority owns the security workflow (with PACR-003)

**Status: APPLIED 1 Sep 2026.** `public.fn_phase_a_baseline_drift()` = 0 rows and
`public.fn_phase_b_baseline_drift()` = 0 rows after the re-record. This is a combined change request:
workflow ownership is frozen in BOTH the Phase A registry (`registry:workflow_ownership` over
`org_workflow_ownership`) and the Phase B structure (`structure:workflow_ownership` over
`phase_b_workflow`), so it carries both `app.phase_a_change_reason` (PACR-003) and
`app.phase_b_change_reason` (PBCR-003). Applied by `scripts/sql/pbcr_003_the_security_role_owns_the_security_workflow.sql`.

## 1. Observed problem

W29 "Security incident and reliability recovery" was accountable to `it_operations_engineer` (a
reliability role) and reviewed by `risk_and_governance_manager`. The stop-authority security role
`cybersecurity_engineer` — the `security` agent that subscribes to `security.event` and owns incident
response, department `assurance`, `authority_level = stop_authority` — owned and reviewed **nothing**
across all 30 workflows; it appeared only as a W29 contributor. The security workflow was run by an
ops role while the security stop-authority carried no accountability for it.

## 2. Evidence

```sql
-- before
select accountable_role_id, independent_reviewer, contributors from org_workflow_ownership where workflow_id='W29';
--  it_operations_engineer | risk_and_governance_manager | {cybersecurity_engineer,engineering_manager,quality_and_release_director}
select count(*) from org_workflow_ownership where accountable_role_id='cybersecurity_engineer' or independent_reviewer='cybersecurity_engineer';
--  0
select agent_key, reason from event_subscription where event_type='security.event' and agent_key='security';
--  security | Owns incident response
```

## 3. Current workflow and step

W29 in `phase_b_workflow` / `org_workflow_ownership`. Domain `assurance`, criticality `critical`,
start_event "Incident/security signal", required_end_state "Contained incident, restored service and
evidence". Steps are unchanged by this request; only workflow-level ownership moves.

## 4. Proposed change

| field | before | after |
|---|---|---|
| `accountable_role_id` | `it_operations_engineer` | `cybersecurity_engineer` |
| `contributors` | `cybersecurity_engineer; engineering_manager; quality_and_release_director` | `it_operations_engineer; engineering_manager; quality_and_release_director` |
| `independent_reviewer` | `risk_and_governance_manager` | *(unchanged)* |

Applied to both `org_workflow_ownership` (Phase A registry) and `phase_b_workflow` (Phase B spec), and
to `docs/phase-a/PHASE_A_WORKFLOW_OWNERSHIP.csv` and `docs/phase-b/PHASE_B_WORKFLOW_REGISTRY.csv`.

## 5. Affected owners

`cybersecurity_engineer` gains accountability for W29 (was a contributor). `it_operations_engineer`
loses workflow accountability and becomes a contributor (reliability-recovery execution stays with it).
`risk_and_governance_manager` keeps the independent review. Owner department `assurance`, reviewer
department `legal` — the review remains **cross-department**, so no reviewer-independence regression.

## 6. State-machine impact

None. No state, transition, step, gate or handoff is added, removed or re-routed. In-flight W29 runs
keep their steps; only the accountable role label changes.

## 7. Gate and rule impact

None weakened. A stop-authority role owning a workflow is already the architecture (W08 →
`marketplace_content_privacy_reviewer`, W10 → `supplier_verification`, both independent_reviewer/
stop_authority). `fn_phase_a_organization_violations()` stays 0.

## 8. Customer and supplier impact

None. Invisible to customers and suppliers.

## 9. Privacy, legal and financial impact

None. No founder-reserved boundary (FDR-001…FDR-010), no money, no identity reveal, no terms.

## 10. Backward compatibility

History is preserved: prior W29 records, reviews and the 15 Aug baseline note are retained. The
baseline `note` is appended, not overwritten; both digests are re-recorded from live, not deleted.

## 11. Founder approval requirement

This is a technical governance mechanism (which AI role is accountable for the security workflow), not
a change to commercial policy, pricing, or a founder-reserved boundary. Per the session conduct rule it
is an engineering decision to make and report, aligned with the founder's intent that security be owned
by the security function.

---

## Verification

```
node scripts/apply_sql.mjs scripts/sql/pbcr_003_the_security_role_owns_the_security_workflow.sql --apply --ddl
select * from public.fn_phase_a_baseline_drift();   -- 0 rows
select * from public.fn_phase_b_baseline_drift();   -- 0 rows
select * from public.fn_phase_c_reporting_map_drift();  -- 0 rows
```

Rehearsed in an aborted transaction before applying: both drift checks returned 0 and
`fn_phase_a_organization_violations()` stayed 0. Applied and re-verified: pa_drift=0, pb_drift=0,
pa_violations=0, W29 owner=cybersecurity_engineer in both tables, phase_c map drift=0.
