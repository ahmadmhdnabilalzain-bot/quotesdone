-- Phase B — the freeze.
--
-- The founder approved Phase B on 15 Aug 2026 and named exactly what may not change:
-- workflow ownership, workflow order, states or transitions, gates, business rules, handoff
-- accountability, category-overlay authority, and founder boundaries. This refuses a statement
-- that changes any of them without a formal Phase B change request.
--
-- IT COMPARES A DIGEST, NOT A COUNT. Phase A's guard compares counts, so a change that swaps two
-- managers while keeping the head-count identical passes the trigger and is only caught later by
-- the separate digest check. Phase B refuses it at the moment it is written: swapping two step
-- owners changes the step_ownership digest even though the row count is untouched.
--
-- WHAT IS NOT FROZEN, and why, said plainly rather than left to be discovered:
--   * phase_b_sla_policy — the master spec §14 states SLA values may be adjusted by authorized
--     management without reopening the structural definition, provided the accountable owner is
--     unchanged and no gate is weakened. Freezing them would contradict the approved spec.
--   * phase_b_crosswalk — it is a MEASUREMENT of the current runtime, and Phase C must re-measure
--     it. Freezing a measurement would freeze the estate's own reflection.
--   * phase_b_exception, phase_b_business_object, phase_b_event — not in the founder's list. They
--     are covered by fn_phase_b_baseline_drift(), which reports a count change, but they are not
--     guarded at write time. Say so rather than implying a protection that is not there.
--
-- The escape hatch is deliberately the same shape as Phase A's, and means the same thing: a real
-- change request with evidence and founder approval, not a sentence typed to get past a guard.
--
--   set local app.phase_b_change_reason = 'PBCR-nnn: <problem, evidence, current workflow and
--     step, proposed change, affected owners, state-machine impact, gate and rule impact,
--     customer/supplier impact, privacy/legal/financial impact, backward compatibility, approver>';

set lock_timeout = '8s';
set statement_timeout = '600s';

create or replace function public.fn_phase_b_freeze_guard()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  b public.org_phase_baseline%rowtype;
  v_reason text;
  v_moved text;
  v_count bigint;
begin
  select * into b from public.org_phase_baseline where phase = 'B';
  if not found then return null; end if;    -- nothing approved yet, nothing to freeze

  -- Which of the founder's frozen subjects moved? Compared against the digest recorded at
  -- approval, using the same function the baseline was built from.
  select string_agg(d.subject || ' (' || left(d.sha256, 12) || ' != '
                    || left(coalesce(b.registry_sha256->'structure'->d.subject->>'database','NONE'), 12) || ')',
                    ', ' order by d.subject)
    into v_moved
  from public.fn_phase_b_structure_digest() d
  where d.sha256 is distinct from (b.registry_sha256->'structure'->d.subject->>'database');

  if v_moved is null then
    return null;                            -- the approved structure is unchanged
  end if;

  v_reason := nullif(btrim(current_setting('app.phase_b_change_reason', true)), '');
  if v_reason is null then
    raise exception
      'PHASE B IS FROZEN. This statement changes the approved workflow architecture: %. '
      'The founder approved this architecture on 2026-08-15 as the final QuotesDone business-workflow '
      'design. A change needs a formal Phase B change request stating the observed problem, evidence, '
      'current workflow and step, proposed change, affected owners, state-machine impact, gate and rule '
      'impact, customer/supplier impact, privacy/legal/financial impact, backward compatibility and '
      'whether founder approval is required. State it in the same transaction: '
      '  set local app.phase_b_change_reason = ''PBCR-nnn: <the above>'';',
      v_moved;
  end if;

  select count(*) into v_count from public.fn_phase_b_structure_digest() d
   where d.sha256 is distinct from (b.registry_sha256->'structure'->d.subject->>'database');
  raise notice 'PHASE B STRUCTURE CHANGED in % subject(s) [%] under change reason: %',
    v_count, v_moved, v_reason;
  return null;
end $$;

comment on function public.fn_phase_b_freeze_guard() is
  'Refuses a statement that changes the founder-approved Phase B architecture without a formal change request. Compares digests, not counts.';

-- The eight tables that carry the founder's frozen subjects. Statement-level: these tables are
-- written approximately never, so recomputing the digest per statement costs nothing that matters,
-- and a row-level trigger would recompute it once per row for no extra safety.
drop trigger if exists z90_phase_b_freeze on public.phase_b_workflow;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_workflow
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_workflow_step;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_workflow_step
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_handoff;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_handoff
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_gate;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_gate
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_business_rule;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_business_rule
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_founder_boundary;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_founder_boundary
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_dynamic_actor;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_dynamic_actor
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_workflow_state;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_workflow_state
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_workflow_transition;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_workflow_transition
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_step_state;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_step_state
  for each statement execute function public.fn_phase_b_freeze_guard();

drop trigger if exists z90_phase_b_freeze on public.phase_b_step_transition;
create trigger z90_phase_b_freeze after insert or delete or update on public.phase_b_step_transition
  for each statement execute function public.fn_phase_b_freeze_guard();

-- Verify by reading it back, and by FORCING THE GUARD TO FIRE.
-- A freeze that has never refused anything is indistinguishable from no freeze, so this does not
-- merely count triggers: it changes a step owner inside an aborted transaction and requires the
-- refusal, then proves nothing was left behind.
do $$
declare v_triggers bigint; v_fired boolean := false; v_owner text;
begin
  select count(*) into v_triggers
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and t.tgname = 'z90_phase_b_freeze' and not t.tgisinternal;
  if v_triggers <> 11 then
    raise exception 'phase_b: expected 11 freeze triggers, found %', v_triggers;
  end if;

  select accountable_role_id into v_owner from public.phase_b_workflow_step where step_id = 'W01-S01';
  begin
    update public.phase_b_workflow_step
       set accountable_role_id = 'ceo'
     where step_id = 'W01-S01' and accountable_role_id <> 'ceo';
    if not found then
      raise exception 'phase_b: the freeze probe changed no row, so it proved nothing';
    end if;
  exception when others then
    if sqlerrm like 'PHASE B IS FROZEN%' then v_fired := true; else raise; end if;
  end;
  if not v_fired then
    raise exception 'phase_b: the freeze guard did NOT refuse an owner change. It is not a freeze.';
  end if;

  if (select accountable_role_id from public.phase_b_workflow_step where step_id = 'W01-S01')
     is distinct from v_owner then
    raise exception 'phase_b: the freeze probe left the owner changed';
  end if;
  raise notice 'phase_b freeze verified: 11 triggers, guard refused an owner change, nothing left behind';
end $$;
