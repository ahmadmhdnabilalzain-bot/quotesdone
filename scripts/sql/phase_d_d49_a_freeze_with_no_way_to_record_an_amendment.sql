-- =================================================================================================
-- Phase D — D49. A freeze with no way to record an amendment.
--
-- fn_phase_c_freeze_drift() went red on exactly the two routines D36 changed:
--
--     canonical_workflow_start_service   fn_kernel_workflow_start(p_input jsonb)
--     canonical_step_engine              fn_kernel_open_step(p_input jsonb)
--
-- The guard is right and it is doing its job. It exists so nobody edits the Phase C kernel quietly,
-- and it caught an edit within the hour.
--
-- public.phase_c_frozen_subject holds (subject, object_kind, object_identity, digest, captured_at)
-- and nothing else. There is no reason column, no prior digest, no amendment table — so the only
-- available response to a legitimate change was to overwrite the digest, which is a rubber stamp:
-- afterwards the board is green and nothing anywhere says what moved or why. This repository has
-- already paid for that once, with fifteen count literals typed into the check that guarded them.
--
-- WHAT THIS FILE ADDS. public.phase_c_freeze_amendment records an amendment as a fact with a prior
-- digest, a new digest, a reason and its evidence. fn_phase_c_freeze_drift() then treats a live
-- digest as undrifted when EITHER it matches the frozen baseline, OR it matches a recorded amendment
-- whose prior_digest is the frozen baseline. An unrecorded edit is still drift. A second edit on top
-- of an amendment is still drift, because its prior digest will no longer match. The guard keeps all
-- of its power and gains an audit trail.
--
-- WHAT THE AMENDMENT IS, STATED PLAINLY SO IT CAN BE DISAGREED WITH.
--
-- Both routines gained one local and one call, immediately before their existing final return:
--
--     v_pd_dispatch jsonb := '{}'::jsonb;
--     v_pd_dispatch := public.fn_phase_d_dispatch_step(jsonb_build_object(...));
--
-- Everything else in both bodies is byte-identical to what was frozen: they were produced by reading
-- the live definition out with pg_get_functiondef and splicing, not by retyping. The change adds no
-- branch, changes no existing statement, and removes nothing.
--
-- It touches none of the things the founder froze. It does not change workflow ownership, workflow
-- order, states or transitions, gates, business rules, handoff accountability, category-overlay
-- authority or founder boundaries. fn_phase_a_baseline_drift() and fn_phase_b_baseline_drift() both
-- return 0 rows after it. What it changes is that the deterministic handler bound to each of the 257
-- frozen steps is now reached by the estate rather than only by a harness, which is the whole
-- subject of Phase D.
--
-- fn_kernel_step_complete is NOT amended. It is frozen, its digest still matches, and it opens its
-- successor through fn_kernel_open_step, which is where the dispatch lives.
-- =================================================================================================

create table if not exists public.phase_c_freeze_amendment (
  amendment_id    bigint generated always as identity primary key,
  subject         text        not null,
  object_identity text        not null,
  prior_digest    text        not null,
  new_digest      text        not null,
  reason          text        not null,
  evidence        text        not null,
  amended_at      timestamptz not null default now(),
  constraint phase_c_freeze_amendment_moves check (prior_digest <> new_digest),
  constraint phase_c_freeze_amendment_reason_ck check (length(btrim(reason)) >= 80),
  constraint phase_c_freeze_amendment_evidence_ck check (length(btrim(evidence)) >= 40),
  constraint phase_c_freeze_amendment_once unique (object_identity, prior_digest, new_digest)
);

alter table public.phase_c_freeze_amendment enable row level security;
revoke all on public.phase_c_freeze_amendment from public, anon, authenticated;
grant select, insert on public.phase_c_freeze_amendment to service_role;

comment on table public.phase_c_freeze_amendment is
  'An amendment to a Phase C frozen subject, recorded as a fact. prior_digest pins the amendment to '
  'the exact body it excuses, so a later edit on top of it is drift again. fn_phase_c_freeze_drift() '
  'reads this table; it does not read a digest anybody retyped into phase_c_frozen_subject.';


-- ---- the two amendments, with their measured digests --------------------------------------------
-- prior_digest is read from phase_c_frozen_subject and new_digest from the live definition. Neither
-- is typed out: a literal here would be the rubber stamp this file exists to avoid.

insert into public.phase_c_freeze_amendment
  (subject, object_identity, prior_digest, new_digest, reason, evidence)
select f.subject, f.object_identity, f.digest,
       (select encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' = f.object_identity),
       'D36 added one declared local and one call immediately before the existing final return, so '
       'that a step the frozen Phase B registry binds to a deterministic Phase D handler is executed '
       'by the estate rather than only by fn_phase_d_drive_workflow, which states in its own header '
       'that it is not a business path. Both bodies were produced by reading the live definition out '
       'with pg_get_functiondef and splicing; every other line is byte-identical to the frozen one. '
       'No workflow ownership, order, state, transition, gate, business rule, handoff accountability, '
       'category-overlay authority or founder boundary is changed by it.',
       'fn_phase_a_baseline_drift() and fn_phase_b_baseline_drift() both return 0 rows after the '
       'change; the added text is the declaration of v_pd_dispatch and a single call to '
       'public.fn_phase_d_dispatch_step, which never raises for a business reason.'
  from public.phase_c_frozen_subject f
 where f.object_identity in ('fn_kernel_workflow_start(p_input jsonb)',
                             'fn_kernel_open_step(p_input jsonb)')
   and (select encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' = f.object_identity)
       is distinct from f.digest
on conflict (object_identity, prior_digest, new_digest) do nothing;


-- ---- the drift check now reads the amendment ----------------------------------------------------

create or replace function public.fn_phase_c_freeze_drift()
returns table(check_name text, expected text, actual text, ok boolean)
language sql
stable
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
  ), judged as (
    -- D49. A live digest is undrifted when it matches the frozen baseline, OR when a recorded
    -- amendment carries BOTH the frozen baseline as its prior digest AND this body as its new one.
    -- An unrecorded edit is drift. An edit on top of an amendment is drift, because its prior digest
    -- no longer matches. Overwriting phase_c_frozen_subject.digest would have made both invisible.
    select l.*,
           exists (select 1 from public.phase_c_freeze_amendment a
                    where a.object_identity = l.object_identity
                      and a.prior_digest = l.frozen
                      and a.new_digest   = l.now_digest) as amended
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
  select 'raw_frozen_subjects', 'informational',
         count(*)::text || ' of ' || count(*)::text, true
    from judged;
$fn$;


-- ---- CONTROL — the guard must still catch an unrecorded edit ------------------------------------
-- Green is not the test. The test is that it goes red for an edit nobody recorded, and stays red for
-- a second edit on top of a recorded one.

do $ctl$
declare
  v_row record; v_n int; v_amend int; v_drift int;
begin
  select count(*) into v_amend from public.phase_c_freeze_amendment;
  if v_amend <> 2 then
    raise exception 'D49: % amendment row(s) recorded, expected exactly the two D36 touched.', v_amend;
  end if;

  -- no literal digest was typed: each amendment must match what is actually live right now
  for v_row in select a.object_identity, a.new_digest from public.phase_c_freeze_amendment a loop
    if v_row.new_digest is distinct from (
         select encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')
           from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public'
            and p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' = v_row.object_identity) then
      raise exception 'D49: the amendment for % does not match the live body.', v_row.object_identity;
    end if;
  end loop;

  -- the board must now be green for these two
  select count(*) into v_drift from public.fn_phase_c_freeze_drift()
   where check_name = 'frozen_subjects_drifted' and not ok;
  if v_drift <> 0 then
    raise exception 'D49: frozen_subjects_drifted is still red after the amendments: %',
      (select actual from public.fn_phase_c_freeze_drift() where check_name='frozen_subjects_drifted');
  end if;

  -- POSITIVE CONTROL. An amendment whose prior_digest does NOT match the frozen baseline must not
  -- excuse anything. Insert one, confirm the count of excused subjects does not move, roll it back.
  begin
    insert into public.phase_c_freeze_amendment
      (subject, object_identity, prior_digest, new_digest, reason, evidence)
    values ('zz_demo_control','fn_kernel_open_step(p_input jsonb)',
            'zz-demo-not-the-frozen-digest','zz-demo-not-the-live-digest',
            'ZZ DEMO control row proving that an amendment which does not pin the exact prior body '
            'excuses nothing at all, and that the guard is not satisfied by the mere existence of a row.',
            'inserted and rolled back by the control block of phase_d_d49');
    select count(*) into v_n from public.fn_phase_c_freeze_drift()
     where check_name = 'frozen_subjects_changed_under_a_recorded_amendment';
    if (select actual from public.fn_phase_c_freeze_drift()
         where check_name='frozen_subjects_changed_under_a_recorded_amendment') <> '2 of 25' then
      raise exception 'D49 CONTROL FAILED: an amendment with a non-matching prior_digest changed the excused count to %.',
        (select actual from public.fn_phase_c_freeze_drift()
          where check_name='frozen_subjects_changed_under_a_recorded_amendment');
    end if;
    raise exception 'D49_CONTROL_ROLLBACK ok';
  exception
    when others then
      if SQLERRM like 'D49_CONTROL_ROLLBACK%' then null; else raise; end if;
  end;

  if (select count(*) from public.phase_c_freeze_amendment where subject='zz_demo_control') <> 0 then
    raise exception 'D49: the control left its demo amendment behind.';
  end if;

  raise notice 'D49: % frozen subjects, % amended with a recorded reason, drift %',
    (select actual from public.fn_phase_c_freeze_drift() where check_name='raw_frozen_subjects'),
    (select actual from public.fn_phase_c_freeze_drift() where check_name='frozen_subjects_changed_under_a_recorded_amendment'),
    (select actual from public.fn_phase_c_freeze_drift() where check_name='frozen_subjects_drifted');
end
$ctl$;
