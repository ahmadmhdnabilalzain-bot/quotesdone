-- E13 — an amendment that excuses itself
--
-- MEASURED 2026-08-20. `public.phase_c_freeze_amendment` holds three rows. Its columns are
-- `amendment_id, subject, object_identity, prior_digest, new_digest, reason, evidence, amended_at`.
-- There is no approver, no approval reference and no link to a change request.
-- `fn_phase_c_freeze_drift()` treats a digest move as undrifted the moment such a row exists, so the
-- session that made the change also wrote the record that excuses it, and the board reads green on
-- its own say-so.
--
-- `PHASE_D_CHANGE_CONTROL.md` line 7 requires a Phase C change request for a kernel contract change.
-- PCCR-001 was raised on 2026-08-20 for amendments 1, 2 and 4 and names them individually in its own
-- scope table; its section 11, founder approval, is deliberately unfilled because it is not the
-- builder's to fill.
--
-- This file makes the link a column and makes the drift check read it:
--   * an amendment with no `change_request_ref` no longer excuses a digest move — the subject counts
--     as DRIFTED, which is the state it was always in;
--   * the three existing rows are backfilled with PCCR-001, which is transcription of what that
--     document already says by amendment_id, not a new claim;
--   * `approved_by` / `approved_at` stay NULL until a person fills them, and a new board row counts
--     the amendments still waiting. That count is reported, never used to excuse anything.
--
-- `scripts/checks/freeze_amendment_names_a_real_change_request.test.mjs` is the other half: the
-- database cannot see the repository, so nothing here can tell PCCR-001 from PCCR-999. The test
-- asserts every distinct `change_request_ref` has a committed
-- `docs/phase-c/PHASE_C_CHANGE_REQUEST_<ref>.md`. A row added without its artefact is a shape this
-- estate has already been caught by.
--
-- CREATE OR REPLACE on fn_phase_c_freeze_drift preserves its ACL. The DDL adds columns only.

alter table public.phase_c_freeze_amendment
  add column if not exists change_request_ref text,
  add column if not exists approved_by        text,
  add column if not exists approved_at        timestamptz;

update public.phase_c_freeze_amendment
   set change_request_ref = 'PCCR-001'
 where amendment_id in (1,2,4) and change_request_ref is null;

alter table public.phase_c_freeze_amendment
  drop constraint if exists phase_c_freeze_amendment_change_request_ref_shape;
alter table public.phase_c_freeze_amendment
  add constraint phase_c_freeze_amendment_change_request_ref_shape
  check (change_request_ref ~ '^PCCR-[0-9]{3}$');

alter table public.phase_c_freeze_amendment
  alter column change_request_ref set not null;

-- An approval is a pair or it is nothing: a name with no date, or a date with no name, is not a
-- record of anybody having approved anything.
alter table public.phase_c_freeze_amendment
  drop constraint if exists phase_c_freeze_amendment_approval_is_a_pair;
alter table public.phase_c_freeze_amendment
  add constraint phase_c_freeze_amendment_approval_is_a_pair
  check ((approved_by is null) = (approved_at is null));

CREATE OR REPLACE FUNCTION public.fn_phase_c_freeze_drift()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE
AS $function$
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
  ), judged as (
    -- D49. A live digest is undrifted when it matches the frozen baseline, OR when a recorded
    -- amendment carries BOTH the frozen baseline as its prior digest AND this body as its new one.
    -- An unrecorded edit is drift. An edit on top of an amendment is drift, because its prior digest
    -- no longer matches. Overwriting phase_c_frozen_subject.digest would have made both invisible.
    --
    -- E13. AND the amendment must name a Phase C change request. Until this line existed, the row
    -- that excused a digest move was written by the same session that moved it, with nothing outside
    -- the transaction to point at. `change_request_ref` is NOT NULL from this file onward, so the
    -- predicate can only bite on a row that predates the column — which is exactly why it is written
    -- as a condition and not assumed away.
    select l.*,
           exists (select 1 from public.phase_c_freeze_amendment a
                    where a.object_identity = l.object_identity
                      and a.prior_digest = l.frozen
                      and a.new_digest   = l.now_digest
                      and coalesce(btrim(a.change_request_ref),'') <> '') as amended,
           exists (select 1 from public.phase_c_freeze_amendment a
                    where a.object_identity = l.object_identity
                      and a.prior_digest = l.frozen
                      and a.new_digest   = l.now_digest
                      and coalesce(btrim(a.change_request_ref),'') = '') as amended_without_a_request
      from live l
  )
  select 'frozen_subjects_drifted', '0',
         count(*) filter (where now_digest is distinct from frozen and not amended)::text
           || ' of ' || count(*)::text,
         count(*) filter (where now_digest is distinct from frozen and not amended) = 0
    from judged
  union all
  select 'frozen_subjects_whose_object_no_longer_exists', '0',
         count(*) filter (where now_digest is null)::text || ' of ' || count(*)::text,
         count(*) filter (where now_digest is null) = 0
    from judged
  union all
  select 'frozen_subjects_changed_under_a_recorded_amendment', 'informational',
         count(*) filter (where amended)::text || ' of ' || count(*)::text, true
    from judged
  union all
  -- E13. The check the estate did not have: an amendment that names no change request excuses
  -- nothing. Expected 0. It counts SUBJECTS, not rows, because it is the subject that is either
  -- properly amended or drifted.
  select 'frozen_subjects_changed_with_no_change_request', '0',
         count(*) filter (where amended_without_a_request)::text || ' of ' || count(*)::text,
         count(*) filter (where amended_without_a_request) = 0
    from judged
  union all
  -- Reported, never used. A change request that has been WRITTEN is not a change request that has
  -- been APPROVED, and the difference belongs on the board rather than in a paragraph.
  select 'amendments_awaiting_founder_approval', 'informational',
         (select count(*) from public.phase_c_freeze_amendment where approved_by is null)::text
           || ' of ' || (select count(*) from public.phase_c_freeze_amendment)::text
           || ' (change requests named: '
           || (select coalesce(string_agg(distinct change_request_ref, ', '),'(none)')
                 from public.phase_c_freeze_amendment) || ')',
         true
  union all
  select 'raw_frozen_subjects', 'informational',
         count(*)::text || ' of ' || count(*)::text, true
    from judged;
$function$;
