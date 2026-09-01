-- PACR-004 / PBCR-004 — INDEPENDENT REVIEW IS CROSS-DEPARTMENT (org audit E14).
--
-- MEASURED. 10 of 30 workflows had their independent reviewer in the SAME department as the accountable
-- owner — and in two cases the reviewer was the owner's own department head (W11 -> marketplace_director,
-- W21 -> chief_revenue_officer). W05/W06/W09/W11/W19 were all marketplace reviewing marketplace. A
-- reviewer inside the owner's own department is not a second pair of eyes. fn_kernel_reviewer_independent
-- only compared role IDENTITY, never department, so a different-role same-department reviewer passed.
--
-- THE CHANGE. Reassign the 10 same-department reviewers to independent-function roles — Assurance
-- (quality_and_release_director, cybersecurity_engineer) and Legal (compliance_and_privacy_officer,
-- general_counsel) — each in a DIFFERENT department than the owner and outside the owner's chain
-- (Assurance and Legal report to the CEO for independence). W01 keeps the FOUNDER as reviewer (the human
-- apex, above every department) and is untouched.
--
--   wf   owner department      new reviewer                     (department)
--   W02  exec                  quality_and_release_director     assurance
--   W05  marketplace           quality_and_release_director     assurance
--   W06  marketplace           quality_and_release_director     assurance
--   W08  legal                 cybersecurity_engineer           assurance
--   W09  marketplace           compliance_and_privacy_officer   legal
--   W11  marketplace           quality_and_release_director     assurance
--   W17  legal                 cybersecurity_engineer           assurance
--   W19  marketplace           compliance_and_privacy_officer   legal
--   W21  growth                general_counsel                  legal
--   W26  data_intel            quality_and_release_director     assurance
--
-- WHY A PACR AND A PBCR. Workflow ownership (including the reviewer) is frozen in BOTH baselines: the
-- Phase A registry:workflow_ownership digest over org_workflow_ownership, and the Phase B
-- structure:workflow_ownership digest over phase_b_workflow. This changes both source tables, sets both
-- change reasons, and re-records the moved 'database' digest in each, dropping and recreating the
-- append-only guard in one transaction (the pbcr_003 recipe). No count moves. Rehearsed in an aborted
-- transaction: fn_phase_a_baseline_drift()=0, fn_phase_b_baseline_drift()=0,
-- fn_phase_a_organization_violations()=0, and 0 workflows have owner and reviewer in the same department.
--
-- Change-request record: docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-004.md.
--
--   node scripts/apply_sql.mjs scripts/sql/pbcr_004_reviewers_are_independent_across_departments.sql --apply --ddl

begin;

set local app.phase_a_change_reason =
  'PACR-004: independent review made cross-department on 10 workflows (W02,W05,W06,W08,W09,W11,W17,W19,'
  'W21,W26); reviewers moved to Assurance/Legal roles outside the owner department and chain. '
  'registry:workflow_ownership re-recorded in place. See docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-004.md.';
set local app.phase_b_change_reason =
  'PBCR-004: independent_reviewer_role_id reassigned cross-department on 10 workflows. '
  'structure:workflow_ownership re-recorded in place. See docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-004.md.';

update public.org_workflow_ownership set independent_reviewer = case workflow_id
    when 'W02' then 'quality_and_release_director' when 'W05' then 'quality_and_release_director'
    when 'W06' then 'quality_and_release_director' when 'W08' then 'cybersecurity_engineer'
    when 'W09' then 'compliance_and_privacy_officer' when 'W11' then 'quality_and_release_director'
    when 'W17' then 'cybersecurity_engineer' when 'W19' then 'compliance_and_privacy_officer'
    when 'W21' then 'general_counsel' when 'W26' then 'quality_and_release_director' end
 where workflow_id in ('W02','W05','W06','W08','W09','W11','W17','W19','W21','W26');

update public.phase_b_workflow set independent_reviewer_role_id = case workflow_id
    when 'W02' then 'quality_and_release_director' when 'W05' then 'quality_and_release_director'
    when 'W06' then 'quality_and_release_director' when 'W08' then 'cybersecurity_engineer'
    when 'W09' then 'compliance_and_privacy_officer' when 'W11' then 'quality_and_release_director'
    when 'W17' then 'cybersecurity_engineer' when 'W19' then 'compliance_and_privacy_officer'
    when 'W21' then 'general_counsel' when 'W26' then 'quality_and_release_director' end
 where workflow_id in ('W02','W05','W06','W08','W09','W11','W17','W19','W21','W26');

-- Re-record both baselines in place: recompute the two moved digests exactly as the drift functions do.
drop trigger a00_org_phase_baseline_append_only on public.org_phase_baseline;

update public.org_phase_baseline b
   set registry_sha256 = jsonb_set(b.registry_sha256, '{workflow_ownership,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select o.workflow_id sortkey,
                                  o.workflow_id||'|'||o.workflow_name||'|'||o.accountable_role_id||'|'
                                  ||array_to_string(o.contributors, ';')||'|'||coalesce(o.independent_reviewer,'') x
                             from public.org_workflow_ownership o) s))),
       note = b.note || E'\n\nAMENDED under PACR-004: independent review made cross-department on 10 workflows; '
              'reviewers moved to Assurance/Legal roles outside the owner department. Counts unchanged. '
              'registry:workflow_ownership digest re-recorded from live.',
       recorded_at = now()
 where b.phase = 'A';

update public.org_phase_baseline b
   set registry_sha256 = jsonb_set(b.registry_sha256, '{structure,workflow_ownership,database}',
         to_jsonb((select sha256 from public.fn_phase_b_structure_digest() where subject = 'workflow_ownership'))),
       note = b.note || E'\n\nAMENDED under PBCR-004: independent_reviewer_role_id reassigned cross-department '
              'on 10 workflows. Counts unchanged. structure:workflow_ownership digest re-recorded from live.',
       recorded_at = now()
 where b.phase = 'B';

create trigger a00_org_phase_baseline_append_only
  before update or delete on public.org_phase_baseline
  for each row execute function public.fn_org_phase_baseline_append_only();

commit;
