# PBCR-004 — independent review is cross-department (with PACR-004)

**Status: APPLIED 1 Sep 2026.** `fn_phase_a_baseline_drift()` = 0 and `fn_phase_b_baseline_drift()` = 0
after the re-record. Combined change request: workflow ownership (including the reviewer) is frozen in
BOTH the Phase A registry (`registry:workflow_ownership` over `org_workflow_ownership`) and the Phase B
structure (`structure:workflow_ownership` over `phase_b_workflow`), so it carries both change reasons.
Applied by `scripts/sql/pbcr_004_reviewers_are_independent_across_departments.sql`.

## 1. Observed problem

10 of 30 workflows had their independent reviewer in the SAME department as the accountable owner — and
twice the reviewer was the owner's own department head (W11 → marketplace_director, W21 →
chief_revenue_officer). W05/W06/W09/W11/W19 were all marketplace reviewing marketplace. A reviewer
inside the owner's own department is not a second pair of eyes.

## 2. Evidence

```sql
select o.workflow_id, r1.primary_department_id owner_dept, r2.primary_department_id reviewer_dept
from org_workflow_ownership o
join org_role r1 on r1.role_id=o.accountable_role_id
join org_role r2 on r2.role_id=o.independent_reviewer
where r1.primary_department_id = r2.primary_department_id;
-- before: 10 rows (W02,W05,W06,W08,W09,W11,W17,W19,W21,W26); after: 0 rows.
```

`fn_kernel_reviewer_independent` compared role IDENTITY only, never department, so a different-role
same-department reviewer passed.

## 3. Current workflow and step

The 10 workflows above, in `phase_b_workflow` / `org_workflow_ownership`. Steps, states, gates and
handoffs are unchanged; only the workflow-level independent reviewer moves.

## 4. Proposed change

Reassign `independent_reviewer` to an independent-function role in a DIFFERENT department than the owner:

| wf | owner dept | new reviewer | dept |
|---|---|---|---|
| W02 | exec | quality_and_release_director | assurance |
| W05 | marketplace | quality_and_release_director | assurance |
| W06 | marketplace | quality_and_release_director | assurance |
| W08 | legal | cybersecurity_engineer | assurance |
| W09 | marketplace | compliance_and_privacy_officer | legal |
| W11 | marketplace | quality_and_release_director | assurance |
| W17 | legal | cybersecurity_engineer | assurance |
| W19 | marketplace | compliance_and_privacy_officer | legal |
| W21 | growth | general_counsel | legal |
| W26 | data_intel | quality_and_release_director | assurance |

Applied to both `org_workflow_ownership` (Phase A registry) and `phase_b_workflow` (Phase B spec).
W01 keeps the FOUNDER as reviewer (the human apex, above every department) and is untouched.

## 5. Affected owners

No accountable owner changes. Ten reviewers change to Assurance (quality_and_release_director,
cybersecurity_engineer) and Legal (compliance_and_privacy_officer, general_counsel) roles — independent
functions that report to the CEO for independence, so each reviewer is outside the owner's chain. The
prior reviewers (strategy_director, inquiry_quality_analyst, supplier_verification, marketplace_director,
compliance_and_privacy_officer, risk_and_governance_manager, chief_revenue_officer, knowledge_validator)
remain in the org, just no longer as these reviewers.

## 6. State-machine impact

None. No state, transition, step, gate or handoff added, removed or re-routed. In-flight runs keep
their steps; only the reviewer label changes.

## 7. Gate and rule impact

None weakened. Review is now STRICTER — cross-department, not merely different-role. A CI invariant
(`org_connectivity_scenarios.test.mjs`) now fails on any workflow whose owner and reviewer resolve to
the same primary department.

## 8. Customer and supplier impact

None. Invisible to customers and suppliers.

## 9. Privacy, legal and financial impact

None. No founder-reserved boundary, no money, no identity reveal, no terms.

## 10. Backward compatibility

History preserved: prior reviews and the baseline notes are retained; the baseline `note` is appended,
both moved digests re-recorded from live, none deleted.

## 11. Founder approval requirement

A technical governance mechanism strengthening reviewer independence — not commercial policy, pricing,
or a founder-reserved boundary. An engineering decision to make and report.

---

## Verification

```
node scripts/apply_sql.mjs scripts/sql/pbcr_004_reviewers_are_independent_across_departments.sql --apply --ddl
select * from public.fn_phase_a_baseline_drift();   -- 0 rows
select * from public.fn_phase_b_baseline_drift();   -- 0 rows
```

Rehearsed in an aborted transaction before applying: both drift checks returned 0,
`fn_phase_a_organization_violations()` stayed 0, and 0 workflows had owner and reviewer in the same
department. Applied and re-verified: pa_drift=0, pb_drift=0, violations=0, same-department workflows=0,
77/77 Phase B invariants pass.

## CSV note

The frozen digests the drift checks read are recomputed from the LIVE tables, so
`fn_phase_a/b_baseline_drift` = 0 without touching the docs CSVs. The docs
`PHASE_A_WORKFLOW_OWNERSHIP.csv` and `PHASE_B_WORKFLOW_REGISTRY.csv` are also updated to the new
reviewers so the committed spec matches the live registry.
