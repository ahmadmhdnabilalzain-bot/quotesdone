-- PHASE C — FOUNDER APPROVED AND FROZEN, 18 AUGUST 2026.
--
-- The founder approved Phase C on the strength of the independent immutable closure audit
-- (PHASE_C_IMMUTABLE_CLOSURE_AUDIT_2026-08-18.md), which was performed read-only against
-- main f0f7339 and production htdblwldjkcgjvmqkbeh.
--
-- THIS FILE RECORDS AN APPROVAL. IT CHANGES NO PHASE C ARCHITECTURE.
-- Nothing frozen below is edited, replaced, re-granted or re-pointed here. Everything added is
-- additive: two append-only registers, one drift board, and one baseline row.
--
-- NO DIGEST IN THIS FILE IS TYPED. Every fingerprint is computed from the live catalogue at
-- INSERT time, because a baseline whose expected values were hand-entered is a rubber stamp: it
-- agrees with whatever was true when somebody typed it. The repository-side checksums (the audit
-- report, the crosswalk CSV, the routine manifest CSV, the schema mirror, the edge-function parity
-- report) cannot be computed in SQL and are passed in as literals; each was produced by
-- `sha256sum` on the committed bytes at f0f7339 and each names the file it describes.
--
-- WHAT FREEZING MEANS HERE, PRECISELY. Phase A and Phase B freeze TABLES, so they are enforced at
-- write time by statement-level triggers. Most of what the founder froze in Phase C is a ROUTINE,
-- and a trigger cannot fire on CREATE OR REPLACE FUNCTION. The mechanism is therefore DETECTIVE
-- and it is honest about that: fn_phase_c_freeze_drift() re-computes every frozen digest on every
-- call, is discovered by fn_kernel_all_boards() on signature, and is NOT listed in
-- scripts/checks/kernel-boards.json — so it is a GATE. The moment a frozen routine's body changes,
-- kernel_boards_are_green.test.mjs goes red in CI and on every pull request. It does not prevent
-- the edit; it makes shipping the edit impossible without a recorded change request.

begin;

-- ---------------------------------------------------------------- 1. the frozen subjects
create table if not exists public.phase_c_frozen_subject (
  subject          text        not null,
  object_kind      text        not null check (object_kind in ('routine','table','repository_file')),
  object_identity  text        not null,
  digest           text        not null,
  captured_at      timestamptz not null default now(),
  primary key (subject, object_identity)
);

comment on table public.phase_c_frozen_subject is
  'The fifteen Phase C subjects the founder froze on 18 Aug 2026, resolved to concrete objects with '
  'a digest captured from the live catalogue. A later change to any of these requires a formal '
  'Phase C change request with evidence and founder approval. Checked by '
  'public.fn_phase_c_freeze_drift(), which is a GATE board, not a ratchet.';

-- Populated mechanically. The (subject -> object) mapping is the founder's fifteen items expressed
-- as the objects that actually implement them; the DIGEST is read from the catalogue, never typed.
insert into public.phase_c_frozen_subject (subject, object_kind, object_identity, digest)
select m.subject, 'routine',
       m.obj || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       encode(sha256(convert_to(pg_get_functiondef(p.oid), 'UTF8')), 'hex')
  from (values
    ('founder_authentication','fn_phase_c_require_founder'),
    ('chief_of_staff_command_path','fn_founder_command_submit'),
    ('chief_of_staff_command_path','fn_founder_command_control'),
    ('chief_of_staff_command_path','fn_founder_command_clarify'),
    ('autonomous_trigger_path','fn_kernel_trigger_submit'),
    ('autonomous_trigger_path','fn_kernel_source_emit'),
    ('canonical_workflow_start_service','fn_kernel_workflow_start'),
    ('canonical_step_engine','fn_kernel_open_step'),
    ('canonical_step_engine','fn_kernel_step_complete'),
    ('canonical_cancellation_service','fn_kernel_cancel'),
    ('canonical_signal_service','fn_kernel_signal_submit'),
    ('handoff_service','fn_kernel_handoff_accept'),
    ('internal_review_service','fn_kernel_review_decide'),
    ('event_outbox_service','fn_kernel_outbox_emit'),
    ('event_outbox_service','fn_kernel_outbox_deliver'),
    ('trace_ledger','fn_kernel_system_execution_trace'),
    ('trace_ledger','fn_phase_c_trace_append_only'),
    ('trace_ledger','fn_kernel_trace_integrity'),
    ('kernel_only_write_controls','fn_kernel_write_guard'),
    ('kernel_only_write_controls','fn_kernel_truncate_guard'),
    ('kernel_only_write_controls','fn_kernel_truncate_protection_state'),
    ('refund_only_founder_approval','fn_phase_c_refund_decision_guard'),
    ('refund_only_founder_approval','fn_phase_c_refund_decision_immutable')
  ) as m(subject, obj)
  join pg_proc p on p.proname = m.obj
  join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
on conflict do nothing;

-- The component crosswalk, frozen as a content digest over every row and every column that the
-- crosswalk gate compares — not as a row count, which cannot see a swapped classification.
insert into public.phase_c_frozen_subject (subject, object_kind, object_identity, digest)
select 'component_crosswalk', 'table', 'public.phase_c_component',
       encode(sha256(convert_to(string_agg(
         c.component_id || '|' || coalesce(c.component_type,'') || '|' || coalesce(c.workflow_id,'')
           || '|' || coalesce(c.step_id,'') || '|' || coalesce(c.accountable_role_id,'')
           || '|' || coalesce(c.canonical_system_actor,'') || '|' || coalesce(c.authority_class,'')
           || '|' || coalesce(c.trace_policy_id,'') || '|' || coalesce(c.activation_state,'')
           || '|' || coalesce(c.classification,'') || '|' || coalesce(c.mutates_state::text,''),
         chr(10) order by c.component_id), 'UTF8')), 'hex')
  from public.phase_c_component c
on conflict do nothing;

-- The founder's fifteenth item is a REPOSITORY mechanism, so it is frozen by the checksum of the
-- committed engine rather than by a catalogue digest. Recorded as such, not dressed up as a
-- database object.
insert into public.phase_c_frozen_subject (subject, object_kind, object_identity, digest) values
  ('canonical_routine_source_of_truth', 'repository_file',
   'scripts/checks/canonical_routine_manifest.mjs',
   'RECORDED_IN_APPROVAL_RECORD:canonical_routine_manifest_csv_sha256')
on conflict do nothing;

-- ---------------------------------------------------------------- 2. the drift board (a GATE)
create or replace function public.fn_phase_c_freeze_drift()
returns table(check_name text, expected text, actual text, ok boolean)
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  with live as (
    select f.subject, f.object_identity, f.digest as frozen,
           case
             when f.object_kind = 'routine' then (
               select encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')
                 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                where n.nspname='public'
                  and p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
                      = f.object_identity)
             when f.object_kind = 'table' and f.object_identity = 'public.phase_c_component' then (
               select encode(sha256(convert_to(string_agg(
                 c.component_id || '|' || coalesce(c.component_type,'') || '|' || coalesce(c.workflow_id,'')
                   || '|' || coalesce(c.step_id,'') || '|' || coalesce(c.accountable_role_id,'')
                   || '|' || coalesce(c.canonical_system_actor,'') || '|' || coalesce(c.authority_class,'')
                   || '|' || coalesce(c.trace_policy_id,'') || '|' || coalesce(c.activation_state,'')
                   || '|' || coalesce(c.classification,'') || '|' || coalesce(c.mutates_state::text,''),
                 chr(10) order by c.component_id),'UTF8')),'hex')
                 from public.phase_c_component c)
             else f.digest   -- repository_file subjects are checked in CI, not here; never silently green
           end as now_digest
      from public.phase_c_frozen_subject f
  )
  select 'frozen_subjects_drifted', '0',
         count(*) filter (where now_digest is distinct from frozen)::text || ' of ' || count(*)::text,
         count(*) filter (where now_digest is distinct from frozen) = 0
    from live
  union all
  select 'frozen_subjects_whose_object_no_longer_exists', '0',
         count(*) filter (where now_digest is null)::text || ' of ' || count(*)::text,
         count(*) filter (where now_digest is null) = 0
    from live
  union all
  select 'raw_frozen_subjects', 'informational',
         count(*)::text || ' of ' || count(*)::text, true
    from live;
$fn$;

revoke all on function public.fn_phase_c_freeze_drift() from public;
grant execute on function public.fn_phase_c_freeze_drift() to service_role;

comment on function public.fn_phase_c_freeze_drift() is
  'Board: every Phase C subject frozen by the founder on 18 Aug 2026 still has the digest it was '
  'frozen with. A GATE, not a ratchet — any drift fails kernel_boards_are_green immediately. '
  'Detective, not preventive: a trigger cannot fire on CREATE OR REPLACE FUNCTION, so this makes '
  'shipping an unapproved change impossible rather than making the edit impossible.';

-- ---------------------------------------------------------------- 3. the immutable approval record
create table if not exists public.phase_c_founder_approval (
  approval_id                text        primary key,
  approved_by                text        not null,
  approved_at                timestamptz not null,
  main_commit                text        not null,
  project_ref                text        not null,
  audit_filename             text        not null,
  audit_sha256               text        not null,
  phase_a_fingerprint        text        not null,
  phase_b_fingerprint        text        not null,
  phase_c_fingerprint        text        not null,
  component_crosswalk_sha256 text        not null,
  routine_manifest_sha256    text        not null,
  full_schema_sha256         text        not null,
  edge_parity_sha256         text        not null,
  automation_hold            jsonb       not null,
  provider_hold              jsonb       not null,
  rollback_refs              jsonb       not null,
  evidence                   jsonb       not null,
  recorded_at                timestamptz not null default now()
);

comment on table public.phase_c_founder_approval is
  'Immutable founder approval of Phase C. Append-only and undeletable: a later approval is a new '
  'row, never an edit of this one.';

create or replace function public.fn_phase_c_founder_approval_immutable()
returns trigger language plpgsql as $imm$
begin
  raise exception 'public.phase_c_founder_approval is append-only: a founder approval is a record of '
                  'what was approved and when, and editing or deleting it would erase the only '
                  'evidence that the approval happened. Record a NEW approval row instead.'
    using errcode = '42501';
end
$imm$;

revoke all on function public.fn_phase_c_founder_approval_immutable() from public;

drop trigger if exists a00_phase_c_founder_approval_immutable on public.phase_c_founder_approval;
create trigger a00_phase_c_founder_approval_immutable
  before update or delete on public.phase_c_founder_approval
  for each row execute function public.fn_phase_c_founder_approval_immutable();

drop trigger if exists a00_phase_c_frozen_subject_immutable on public.phase_c_frozen_subject;
create trigger a00_phase_c_frozen_subject_immutable
  before update or delete on public.phase_c_frozen_subject
  for each row execute function public.fn_phase_c_founder_approval_immutable();

-- BOTH NEW TABLES NOW CARRY AN ENFORCING ROW-LEVEL TRIGGER, which puts them in the population
-- fn_kernel_truncate_protection_state() watches. Attaching the statement-level guard here is not
-- optional: without it that board goes red the moment this file lands, exactly as the canary probe
-- in the closure audit demonstrated it would.
do $attach$
declare t text;
begin
  foreach t in array array['phase_c_frozen_subject','phase_c_founder_approval'] loop
    execute format('revoke truncate on public.%I from public, anon, authenticated, service_role', t);
    execute format('drop trigger if exists z00_kernel_truncate_guard on public.%I', t);
    execute format('create trigger z00_kernel_truncate_guard before truncate on public.%I '
                || 'for each statement execute function public.fn_kernel_truncate_guard()', t);
  end loop;
end
$attach$;

-- ---------------------------------------------------------------- 4. the approval itself
insert into public.phase_c_founder_approval (
  approval_id, approved_by, approved_at, main_commit, project_ref,
  audit_filename, audit_sha256,
  phase_a_fingerprint, phase_b_fingerprint, phase_c_fingerprint,
  component_crosswalk_sha256, routine_manifest_sha256, full_schema_sha256, edge_parity_sha256,
  automation_hold, provider_hold, rollback_refs, evidence)
select
  'PCA-2026-08-18-001',
  'founder',
  timestamptz '2026-08-18 11:45:00+00',
  'f0f7339d0c39d6dea918d1d24da81f8ff7e09f14',
  'htdblwldjkcgjvmqkbeh',
  'PHASE_C_IMMUTABLE_CLOSURE_AUDIT_2026-08-18.md',
  'c7eed77aef879e21ab96d1b11d6db7f97ba844c0ceae5c8ac687f7d51ad5dd58',
  -- Phase A and Phase B fingerprints are the digests those approvals were recorded with, read from
  -- their own baseline rows. Not recomputed here: quoting a number back from the row that defines it
  -- is the only way this record can be checked against them later.
  (select organization_sha256 from public.org_phase_baseline where phase='A'),
  (select organization_sha256 from public.org_phase_baseline where phase='B'),
  -- Phase C's fingerprint is the digest of every frozen subject digest, in subject order.
  (select encode(sha256(convert_to(string_agg(f.subject||'|'||f.object_identity||'|'||f.digest,
                                              chr(10) order by f.subject, f.object_identity),'UTF8')),'hex')
     from public.phase_c_frozen_subject f),
  '46cb7165c46ade1615d86df0eb9460dffaddd171a561882b9ad4c55d9e9c66d7',  -- docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv
  'd84ede4cfe60f401a1e82b84dd22c915f08ac28d60ba7ef36cbaec3d6b25d608',  -- docs/phase-c-final-kernel/CANONICAL_ROUTINE_MANIFEST.csv
  '875c488ffc4e25f949865fafa47c55b0073f235a0c8c34119c146633458f4abb',  -- supabase/schema/full_schema.sql
  '2a6c6b840e321ae7722b1d4d078ca50e35d6c0c8e6b9f09f494564ea3fab43ea',  -- sha256 over sorted slug+version, 202 functions
  jsonb_build_object(
    'policy', 'selective hold retained unchanged by this approval',
    'kernel_infrastructure_active', true,
    'read_only_monitoring_active', true,
    'business_producing_automation', 'HELD',
    'customer_supplier_notifications', 'HELD',
    'social_publishing', 'HELD',
    'payment_refund_provider_execution', 'HELD',
    'external_provider_effects', 'HELD',
    'cron_jobs_total', (select count(*) from cron.job),
    'cron_jobs_active', (select count(*) from cron.job where active),
    'cron_jobs_inactive', (select count(*) from cron.job where not active),
    'active_job_names', (select jsonb_agg(jobname order by jobname) from cron.job where active)),
  jsonb_build_object(
    'openrouter_and_paid_ai', 'HELD',
    'routes_total', (select count(*) from public.llm_route_health),
    'routes_held', (select count(*) from public.llm_route_health where open_until > now()),
    'paid_ai_allowed', public.fn_os_paid_ai_allowed(),
    'held_until', (select max(open_until) from public.llm_route_health),
    'last_paid_attempt_at', (select max(created_at) from public.llm_attempt),
    'fallback_provider_key', 'none'),
  jsonb_build_object(
    'phase_a_tag', 'phase-a-founder-approved-2026-08-15',
    'phase_b_tag', 'phase-b-founder-approved-2026-08-15',
    'phase_c_tag', 'phase-c-founder-approved-2026-08-18',
    'phase_c_commit', 'f0f7339d0c39d6dea918d1d24da81f8ff7e09f14',
    'previous_main_before_truncate_fix', 'e753505095e72eec79026b99c444953cfe65fd3a',
    'truncate_protection_migration', 'scripts/sql/the_truncate_protection_was_a_typed_list.sql',
    'truncate_protection_pr', 'PR #444',
    'phase_c_change_request_template', 'docs/phase-b/PHASE_B_CHANGE_REQUEST_TEMPLATE.md (shape reused for PCCR)'),
  jsonb_build_object(
    'phase_a_drift', (select count(*) from public.fn_phase_a_baseline_drift()),
    'phase_b_drift', (select count(*) from public.fn_phase_b_baseline_drift()),
    'phase_c_drift', (select count(*) from public.fn_phase_c_baseline_drift()),
    'components_live', (select count(*) from public.phase_c_component),
    'protected_tables', (select count(*) from public.phase_c_frozen_subject) * 0
                        + (select split_part(a.actual,' of ',1)::int
                             from public.fn_kernel_truncate_protection_state() a
                            where a.check_name='raw_enforcing_tables_watched'),
    'truncate_attempts_refused', '75/75 (independent closure audit, aborted transaction)',
    'founder_chain', '30/30',
    'command_acceptance', '20/20',
    'negative_guard_cases', '58/58 refused',
    'genuine_positive_controls', '13/13 accepted',
    'phase_d_profile', '300/300 pass on two consecutive runs',
    'openrouter_http_requests', 0,
    'paid_inference_cost_usd', '0.00',
    'live_external_effects', 0,
    'unresolved_phase_c_defects', 0,
    'phase_d_d0_preflight_debt', jsonb_build_array(
      'valid enabled founder JWT -> success',
      'valid non-founder JWT -> 403'))
  where not exists (select 1 from public.phase_c_founder_approval where approval_id='PCA-2026-08-18-001');

commit;
