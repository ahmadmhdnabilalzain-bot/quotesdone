-- PACR-003 / PBCR-003 — THE SECURITY ROLE OWNS THE SECURITY WORKFLOW (org audit A3).
--
-- THE PROBLEM, MEASURED. W29 "Security incident and reliability recovery" was accountable to
-- it_operations_engineer (a reliability role) and reviewed by risk_and_governance_manager. The
-- stop-authority security role cybersecurity_engineer (runtime_mode independent_reviewer, department
-- assurance, the 'security' agent that subscribes to security.event and owns incident response) owned
-- and reviewed NOTHING — it appeared only as a W29 contributor. The security workflow was run by an
-- ops role while the security stop-authority had no accountability for it.
--
-- THE CHANGE. Promote cybersecurity_engineer from contributor to ACCOUNTABLE on W29, demote
-- it_operations_engineer to contributor (reliability recovery keeps its executor), keep
-- risk_and_governance_manager (department legal) as the independent reviewer — so the review stays
-- CROSS-DEPARTMENT (assurance owner, legal reviewer). Precedent: W08 and W10 are already accountable to
-- independent_reviewer/stop_authority roles (marketplace_content_privacy_reviewer, supplier_verification),
-- so a stop-authority owning a workflow is the existing architecture, not a new pattern.
--
-- WHY BOTH A PACR AND A PBCR. Workflow ownership is frozen in TWO baselines: the Phase A registry
-- (registry:workflow_ownership, a digest over org_workflow_ownership.accountable_role_id/contributors/
-- independent_reviewer) and the Phase B structure (structure:workflow_ownership, a digest over
-- phase_b_workflow via fn_phase_b_structure_digest). This file changes both source tables, sets both
-- change reasons (z90_phase_b_freeze requires app.phase_b_change_reason to accept the phase_b_workflow
-- write), and re-records the 'database' digest in BOTH baselines IN PLACE, dropping and recreating the
-- append-only guard in the same transaction — the recipe pacr_002 uses. No count moves (30 workflows
-- unchanged), so only these two digests move. Verified by aborted-tx rehearsal:
-- fn_phase_a_baseline_drift()=0 and fn_phase_b_baseline_drift()=0 after the recompute, and
-- fn_phase_a_organization_violations() stays 0.
--
-- Founder decision: assign the security stop-authority accountability for the security workflow, a
-- technical governance mechanism (no founder-reserved boundary, no money, no vision conflict).
-- Change-request record: docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-003.md.
--
--   node scripts/apply_sql.mjs scripts/sql/pbcr_003_the_security_role_owns_the_security_workflow.sql --apply --ddl

begin;

set local app.phase_a_change_reason =
  'PACR-003: W29 accountability moves from it_operations_engineer to cybersecurity_engineer (the '
  'security stop-authority); it_operations_engineer becomes a contributor; reviewer unchanged '
  '(risk_and_governance_manager, cross-department). registry:workflow_ownership re-recorded in place. '
  'Approver: founder, security governance. See docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-003.md.';
set local app.phase_b_change_reason =
  'PBCR-003: W29 accountable_role_id it_operations_engineer -> cybersecurity_engineer, contributors '
  'swap it_operations_engineer in for cybersecurity_engineer, reviewer unchanged. structure:'
  'workflow_ownership re-recorded in place. See docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-003.md.';

-- 1. THE PHASE A REGISTRY (operational ownership table) and 2. THE PHASE B SPEC.
update public.org_workflow_ownership
   set accountable_role_id = 'cybersecurity_engineer',
       contributors = array['it_operations_engineer','engineering_manager','quality_and_release_director']
 where workflow_id = 'W29';

update public.phase_b_workflow
   set accountable_role_id = 'cybersecurity_engineer',
       contributors = array['it_operations_engineer','engineering_manager','quality_and_release_director']
 where workflow_id = 'W29';

-- 3. RE-RECORD BOTH BASELINES IN PLACE. Drop the append-only guard, recompute the two moved digests
-- exactly as fn_phase_a_baseline_drift() / fn_phase_b_structure_digest() compute them, recreate the
-- guard. Both digests are read from the NEW live state (the updates above), so the drift checks read 0.
drop trigger a00_org_phase_baseline_append_only on public.org_phase_baseline;

update public.org_phase_baseline b
   set registry_sha256 = jsonb_set(b.registry_sha256, '{workflow_ownership,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select o.workflow_id sortkey,
                                  o.workflow_id||'|'||o.workflow_name||'|'||o.accountable_role_id||'|'
                                  ||array_to_string(o.contributors, ';')||'|'||coalesce(o.independent_reviewer,'') x
                             from public.org_workflow_ownership o) s))),
       note = b.note || E'\n\nAMENDED under PACR-003: W29 accountability moved from it_operations_engineer to '
              'cybersecurity_engineer (the security stop-authority), it_operations_engineer demoted to '
              'contributor, reviewer unchanged. Counts unchanged (30 workflows). registry:workflow_ownership '
              'digest re-recorded from live. A founder governance decision through the Phase A change request.',
       recorded_at = now()
 where b.phase = 'A';

update public.org_phase_baseline b
   set registry_sha256 = jsonb_set(b.registry_sha256, '{structure,workflow_ownership,database}',
         to_jsonb((select sha256 from public.fn_phase_b_structure_digest() where subject = 'workflow_ownership'))),
       note = b.note || E'\n\nAMENDED under PBCR-003: W29 accountable_role_id it_operations_engineer -> '
              'cybersecurity_engineer, contributors swapped, reviewer unchanged. Counts unchanged. '
              'structure:workflow_ownership digest re-recorded from live.',
       recorded_at = now()
 where b.phase = 'B';

create trigger a00_org_phase_baseline_append_only
  before update or delete on public.org_phase_baseline
  for each row execute function public.fn_org_phase_baseline_append_only();

commit;
