-- PCCR-009 — record the frozen-subject amendment for re-enabling the dormant deterministic monitors.
--
-- Re-enabling resilience_watch (123), legal_ai (76) and employee_kpi_assign (290) as traced kernel
-- components changed public.phase_c_component (frozen subject `component_crosswalk`). This records the
-- required freeze amendment, tied to change request PCCR-009
-- (docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-009.md), with prior_digest = the frozen baseline and
-- new_digest = the live component digest (identical expression to fn_phase_c_freeze_drift).
--
-- UNAPPROVED / deployed_before_approval = true: the founder authorized the autonomy build verbally but
-- the cryptographic session approval is NOT forged here. amendments_awaiting_founder_approval discloses
-- it as 1 awaiting him (kernel-boards.json ratchet raised 0 -> 1). He ratifies PCCR-009 through a
-- Command Center session, exactly like PCCR-008.
--
--   node scripts/apply_sql.mjs scripts/sql/pccr009_component_registry_amendment.sql --apply --ddl

begin;

insert into public.phase_c_change_request
  (change_request_ref, document_path, subject, disposition)
values
  ('PCCR-009', 'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-009.md',
   'component_crosswalk — re-enable the audit-confirmed dormant deterministic monitors as traced kernel components',
   'RAISED')
on conflict (change_request_ref) do nothing;

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
  'PCCR-009. Re-enabling the audit-confirmed dormant deterministic monitors (ASSUR-01 resilience_watch, LEGAL-01 legal_ai, PO-1 employee_kpi_assign) as traced kernel components via fn_kernel_wrap_and_enable_cron flipped 2 pre-existing cron_job components active and inserted 1 new one. Each runs through fn_kernel_cron_exec, so active_state_changing_cron_components_not_wrapped stays 0. All three verified deterministic and safe by aborted-tx probe.',
  'scripts/sql/pccr009_reenable_the_audit_confirmed_deterministic_monitors.sql, applied 2 Sep 2026; verified by fn_phase_c_freeze_drift().frozen_subjects_drifted = 0 and one phase_c_system_execution trace per re-enabled cron.',
  'PCCR-009',
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
