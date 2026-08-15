# Phase B change request — PBCR-nnn

Phase B was approved by the founder on 15 Aug 2026 and frozen. A change to workflow ownership,
workflow order, states or transitions, gates, business rules, handoff accountability,
category-overlay authority or founder boundaries requires this document completed, and its
identifier stated in the same transaction as the change:

```sql
set local app.phase_b_change_reason = 'PBCR-nnn: <summary, evidence, approver>';
```

The setting is the audit trail, not the obstacle. A sentence typed to get past the guard is not a
change request, and `fn_phase_b_baseline_drift()` will report the subject that moved regardless of
what was typed.

---

## 1. Observed problem

*What is actually wrong. A symptom, not a proposed fix.*

## 2. Evidence

*The measurement. Include the query or command and its output. "It seems" is not evidence; a
count, a failing assertion or a production row is.*

```sql
-- the query that shows the problem, and what it returned
```

## 3. Current workflow and step

*Which of the 30 workflows and which of the 257 steps. Quote the live rows:*

```sql
select * from public.phase_b_workflow_step where step_id = 'Wnn-Snn';
```

## 4. Proposed change

*Exactly what changes, field by field. Before and after.*

## 5. Affected owners

*Which accountable roles gain, lose or change responsibility. Name them by canonical `role_id`,
not by title — a title is an alias and aliases are input compatibility only.*

## 6. State-machine impact

*Does this add, remove or re-route a state or transition? Does any existing run become
unreachable or stuck? A workflow already in flight is the case to think about.*

## 7. Gate and rule impact

*Which of the 32 gates and 54 business rules are affected. If a gate becomes weaker, say so in
those words. A gate that passes when the thing it checks is broken is worse than no gate.*

## 8. Customer and supplier impact

*What a customer or supplier would experience differently. "None" is an acceptable answer only
when the change is invisible to both.*

## 9. Privacy, legal and financial impact

*Identity reveal, terms acceptance, money movement, refund authority, data retention. If the
change touches any of these, name the founder-reserved boundary (FDR-001…FDR-010) it comes near.*

## 10. Backward compatibility

*What happens to records created under the current architecture. History is never deleted:
completed decisions, reviews, acceptances, revisions and attempts are superseded, not overwritten.*

## 11. Founder approval requirement

*Does this need the founder, and why? It does if it touches a founder-reserved boundary, changes
commercial or pricing policy, or contradicts stated vision or commercial intent. It does **not**
need him for a technical mechanism — that is an engineering decision to make and report.*

---

## Verification plan

*How the change will be proved after deployment. At minimum:*

```bash
node scripts/checks/phase_b_invariants.test.mjs
node scripts/checks/phase_b_guards_reject_injected_defects.test.mjs
```

```sql
select * from public.fn_phase_b_baseline_drift();   -- expected rows, and why each is expected
select * from public.fn_phase_a_baseline_drift();   -- must be 0
```

## After the change

Re-record the baseline so the freeze protects the new architecture rather than the old one:

```bash
node scripts/phase_b/freeze.mjs --emit
```

An approved change that leaves the baseline stale means every subsequent statement trips the
guard, and a guard that fires constantly is a guard people learn to bypass.
