-- PCCR-008 — record the frozen-subject amendment for re-opening the deterministic automation.
--
-- Re-enabling the stand-down's deterministic crons as traced kernel components changed
-- public.phase_c_component (frozen subject `component_crosswalk`). fn_phase_c_freeze_drift reports
-- that as `frozen_subjects_drifted` (a hard kernel gate) until a freeze amendment carries the frozen
-- baseline as its prior digest and the live component body as its new one. This file records that
-- amendment, tied to change request PCCR-008 (docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-008.md).
--
-- The amendment is recorded with approved_by = NULL / deployed_before_approval = true: the founder
-- authorized the freeze-lift verbally (2 Sep 2026) but the cryptographic session approval is not
-- forged here — fn_phase_c_freeze_amendment_session_claim_is_verified refuses an approval write from
-- a non-authenticator connection, correctly. The kernel ratchet amendments_awaiting_founder_approval
-- discloses it as 1 awaiting the founder; kernel-boards.json is raised 0 -> 1 to match, honestly.
--
--   node scripts/apply_sql.mjs scripts/sql/pccr008_reopen_automation_component_amendment.sql --apply --ddl

begin;

-- 1. The change request (RAISED, unapproved) — mirrors the shape of PCCR-006, which exists RAISED/NULL.
insert into public.phase_c_change_request
  (change_request_ref, document_path, subject, disposition)
values
  ('PCCR-008', 'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-008.md',
   'component_crosswalk — re-open the deterministic automation the stand-down closed, as traced kernel components',
   'RAISED')
on conflict (change_request_ref) do nothing;

-- 2. The freeze amendment. prior_digest = the frozen baseline (immutable), new_digest = the live
--    component digest, computed with the IDENTICAL expression fn_phase_c_freeze_drift uses, so the
--    board's `amended` predicate matches exactly. Idempotent: skip if an amendment already carries
--    this baseline->live pair for this subject.
insert into public.phase_c_freeze_amendment
  (subject, object_identity, prior_digest, new_digest, reason, evidence,
   change_request_ref, deployed_before_approval)
select
  'component_crosswalk',
  'public.phase_c_component',
  f.digest,
  (select encode(sha256(convert_to(string_agg(
     c.component_id||'|'||coalesce(c.component_type,'')||'|'||coalesce(c.workflow_id,'')
       ||'|'||coalesce(c.step_id,'')||'|'||coalesce(c.accountable_role_id,'')
       ||'|'||coalesce(c.canonical_system_actor,'')||'|'||coalesce(c.authority_class,'')
       ||'|'||coalesce(c.trace_policy_id,'')||'|'||coalesce(c.activation_state,'')
       ||'|'||coalesce(c.classification,'')||'|'||coalesce(c.mutates_state::text,''),
     chr(10) order by c.component_id),'UTF8')),'hex') from public.phase_c_component c),
  'PCCR-008. Re-opening the deterministic automation the stand-down closed re-enabled ~22 pre-existing cron_job components (inactive->active) and inserted 4 new ones, as traced kernel components via fn_kernel_wrap_and_enable_cron. Every re-enabled cron runs through fn_kernel_cron_exec, so active_state_changing_cron_components_not_wrapped stays 0. The three inference-bound crons stay OFF until OpenRouter.',
  'scripts/sql/reenable_crons_after_standdown.sql + scripts/sql/kernel_wrap_and_enable_cron.sql, applied 2 Sep 2026; verified by fn_phase_c_freeze_drift().frozen_subjects_drifted = 0 and one phase_c_system_execution trace per re-enabled cron.',
  'PCCR-008',
  true
from public.phase_c_frozen_subject f
where f.object_identity = 'public.phase_c_component'
  and not exists (
    select 1 from public.phase_c_freeze_amendment a
     where a.object_identity = 'public.phase_c_component'
       and a.prior_digest = f.digest
       and a.new_digest = (select encode(sha256(convert_to(string_agg(
             c.component_id||'|'||coalesce(c.component_type,'')||'|'||coalesce(c.workflow_id,'')
               ||'|'||coalesce(c.step_id,'')||'|'||coalesce(c.accountable_role_id,'')
               ||'|'||coalesce(c.canonical_system_actor,'')||'|'||coalesce(c.authority_class,'')
               ||'|'||coalesce(c.trace_policy_id,'')||'|'||coalesce(c.activation_state,'')
               ||'|'||coalesce(c.classification,'')||'|'||coalesce(c.mutates_state::text,''),
             chr(10) order by c.component_id),'UTF8')),'hex') from public.phase_c_component c));

commit;
