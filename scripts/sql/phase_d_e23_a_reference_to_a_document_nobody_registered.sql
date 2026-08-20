-- E23 — a reference to a document nobody registered, and a check that could not fire
--
-- Both halves come from the R3 independent acceptance, which probed the E13 mechanism with eight
-- writes in one aborted transaction and found two things worth fixing.
--
-- ---- 1. T4: `PCCR-999` WAS ACCEPTED -----------------------------------------------------------
-- `phase_c_freeze_amendment.change_request_ref` was NOT NULL and shape-checked against
-- `^PCCR-[0-9]{3}$`, and nothing more. An amendment could therefore name a change request that has
-- never been written. The auditor's T4 inserted one and the row was accepted.
--
-- Its report adds "nothing in the database or in CI joins change_request_ref to a committed
-- document", and the CI half of that is not so —
-- `scripts/checks/freeze_amendment_names_a_real_change_request.test.mjs` asserts exactly that join,
-- and runs in the phase-d job where the credential is. But the DATABASE half is exactly right, and
-- "a later test catches it" is a weaker thing than "the write is refused". This estate has been
-- caught before by a registry row added without the artefact it points at.
--
-- So the reference becomes a FOREIGN KEY to a registry of change requests that exist:
-- `public.phase_c_change_request`, one row per PCCR, carrying the path of the document it stands
-- for. `PCCR-999` is now refused by the database at write time. The CI test still asserts the other
-- direction — that each registered path is TRACKED BY GIT and names its amendments — because
-- Postgres cannot see the repository and a row is not a document.
--
-- ---- 2. A CHECK WHOSE CONDITION CANNOT OCCUR --------------------------------------------------
-- `frozen_subjects_changed_with_no_change_request` tested `btrim(change_request_ref) = ''`. The
-- column is NOT NULL and shape-checked, so that predicate cannot be true — it would have read
-- `0 of 25` forever whatever governance did. The E13 body said as much about itself, and the
-- enforcement genuinely did move into constraints that DO bite; but a board row that cannot fire is
-- a green tick measuring nothing, and this estate treats that as a defect wherever it finds it.
--
-- It is replaced by a check of the MECHANISM rather than of the impossible outcome:
-- `change_request_reference_is_enforced` counts the three constraints that make an unregistered or
-- malformed reference impossible — the NOT NULL, the shape check and the new foreign key. Expected
-- 3 of 3. That number CAN fall: drop any one of them and the board goes red the same second, which
-- is precisely what the old row could never do.
--
-- Nothing here weakens anything. Every constraint E13 added stays; one is added; one decorative
-- board row is replaced by one that can fail.

create table if not exists public.phase_c_change_request (
  change_request_ref text primary key,
  document_path      text not null,
  subject            text not null,
  raised_at          timestamptz not null default now(),
  approved_by        text,
  approved_at        timestamptz,
  constraint phase_c_change_request_ref_shape
    check (change_request_ref ~ '^PCCR-[0-9]{3}$'),
  constraint phase_c_change_request_path_shape
    check (document_path = 'docs/phase-c/PHASE_C_CHANGE_REQUEST_' || change_request_ref || '.md'),
  constraint phase_c_change_request_approval_is_a_pair
    check ((approved_by is null) = (approved_at is null))
);

insert into public.phase_c_change_request (change_request_ref, document_path, subject)
values
  ('PCCR-001', 'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-001.md',
   'D36 wired the Phase D dispatch into fn_kernel_open_step and fn_kernel_workflow_start; E6 '
   || 'recorded on public.phase_c_component what E4''s revokes had made true. Amendments 1, 2 and 4.'),
  ('PCCR-002', 'docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-002.md',
   'E14 moved the "the run is running again" update above the fn_kernel_open_step call inside '
   || 'fn_kernel_handoff_accept, so the kernel stops refusing the work it just commissioned. '
   || 'Amendment 5.')
on conflict (change_request_ref) do update
  set document_path = excluded.document_path, subject = excluded.subject;

-- The join the database could not previously make. Any amendment naming an unregistered change
-- request is refused at write time from here on.
alter table public.phase_c_freeze_amendment
  drop constraint if exists phase_c_freeze_amendment_change_request_fk;
alter table public.phase_c_freeze_amendment
  add constraint phase_c_freeze_amendment_change_request_fk
  foreign key (change_request_ref) references public.phase_c_change_request(change_request_ref);

revoke all on public.phase_c_change_request from public;
revoke all on public.phase_c_change_request from anon;
revoke all on public.phase_c_change_request from authenticated;
alter table public.phase_c_change_request enable row level security;

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
    -- E13 required the amendment to name a Phase C change request. E23 makes that reference a
    -- foreign key to public.phase_c_change_request, so an amendment can no longer point at a
    -- document nobody wrote.
    select l.*,
           exists (select 1 from public.phase_c_freeze_amendment a
                    where a.object_identity = l.object_identity
                      and a.prior_digest = l.frozen
                      and a.new_digest   = l.now_digest
                      and coalesce(btrim(a.change_request_ref),'') <> '') as amended
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
  -- E23 REPLACES frozen_subjects_changed_with_no_change_request, WHICH COULD NOT FIRE.
  -- That row tested btrim(change_request_ref) = '' on a column that is NOT NULL and shape-checked,
  -- so it read 0 of 25 whatever anyone did. The R3 acceptance named it, correctly, as a green tick
  -- measuring nothing. What is checkable is whether the MECHANISM is still in place, and this row
  -- goes red the moment any of the three constraints is dropped.
  select 'change_request_reference_is_enforced', '3',
         -- The three are counted into ONE number. An earlier draft printed the two constraints as
         -- "2 of 3" and reported the NOT NULL separately, which read as a failing check sitting
         -- next to a green tick — the precise confusion this row exists to end.
         ((select count(*) from pg_constraint
            where conrelid = 'public.phase_c_freeze_amendment'::regclass
              and conname in ('phase_c_freeze_amendment_change_request_ref_shape',
                              'phase_c_freeze_amendment_change_request_fk'))
          + (select count(*) from information_schema.columns
              where table_schema='public' and table_name='phase_c_freeze_amendment'
                and column_name='change_request_ref' and is_nullable='NO'))::text
         || ' of 3 (shape check, foreign key to phase_c_change_request, NOT NULL)',
         (select count(*) from pg_constraint
           where conrelid = 'public.phase_c_freeze_amendment'::regclass
             and conname in ('phase_c_freeze_amendment_change_request_ref_shape',
                             'phase_c_freeze_amendment_change_request_fk')) = 2
         and (select count(*) from information_schema.columns
               where table_schema='public' and table_name='phase_c_freeze_amendment'
                 and column_name='change_request_ref' and is_nullable='NO') = 1
  union all
  select 'amendments_whose_change_request_is_unregistered', '0',
         (select count(*)::text from public.phase_c_freeze_amendment a
           where not exists (select 1 from public.phase_c_change_request cr
                              where cr.change_request_ref = a.change_request_ref))
         || ' of ' || (select count(*)::text from public.phase_c_freeze_amendment),
         not exists (select 1 from public.phase_c_freeze_amendment a
                      where not exists (select 1 from public.phase_c_change_request cr
                                         where cr.change_request_ref = a.change_request_ref))
  union all
  -- Reported, never used. A change request that has been WRITTEN is not one that has been APPROVED.
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

do $$
declare v_reg int; v_orphan int; v_fk int;
begin
  select count(*) into v_reg from public.phase_c_change_request;
  select count(*) into v_orphan from public.phase_c_freeze_amendment a
   where not exists (select 1 from public.phase_c_change_request cr
                      where cr.change_request_ref = a.change_request_ref);
  select count(*) into v_fk from pg_constraint
   where conrelid = 'public.phase_c_freeze_amendment'::regclass
     and conname = 'phase_c_freeze_amendment_change_request_fk';
  if v_reg < 2 then raise exception 'E23: only % change request(s) registered', v_reg; end if;
  if v_orphan > 0 then raise exception 'E23: % amendment(s) name an unregistered change request', v_orphan; end if;
  if v_fk <> 1 then raise exception 'E23: the foreign key did not land'; end if;
end $$;
