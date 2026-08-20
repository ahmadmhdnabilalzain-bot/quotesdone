-- =================================================================================================
-- Phase D — D45. `event_self_loops = 54` is the check reporting on the wrong subject.
--
-- fn_phase_d_event_state() publishes `event_self_loops` expecting 0 and measuring 54. The
-- remediation plan's premise for it was that the reconciliation's resolution is the likelier defect,
-- "because consumer_resolves is false on 346 of 347 rows". Measured on production, that is inverted:
--
--     consumer_resolves   true on 346, false on 1  (EV-W14-S04-COMPLETED, consumer
--                                                   relevant_category_overlay, a dynamic-actor
--                                                   token, and is_self_loop = false, so not
--                                                   among the 54 at all)
--     producer_resolves   true on 286, false on 61
--
-- And the reconciliation is not wrong about the 54 either. Every figure below was read from
-- production, not inferred:
--
--     phase_d_event_reconciliation rows                                            347
--     is_self_loop                                                                  54
--     producer = primary_consumer_role_id                                           54  (the same 54)
--     producer mismatches against phase_b_event.emitted_by                           0
--     consumer mismatches against phase_b_event.primary_consumer_role_id             0
--     of the 54, producer IS the step's own accountable_role_id                      54
--     of the 54, next_step_if_pass = 'WORKFLOW_COMPLETE'                             15
--     of the 54, the successor step is accountable to the SAME role                  39
--     of the 54, the successor is accountable to a DIFFERENT role                     0
--
-- 15 + 39 = 54, with nothing left over. Every one of them is a step whose emitting role either ends
-- the workflow or hands to a successor it also owns. That is a property of the frozen Phase B
-- workflow graph, and no Phase D file should drive it to zero — doing so would mean editing frozen
-- ownership, which needs a PBCR and would be the wrong thing to ask for anyway.
--
-- SO THE DEFECT IS THE CHECK, NOT THE DATA. `event_self_loops` names a subject — "an event whose
-- producer is also its consumer" — that the frozen registry legitimately contains 54 of. A red that
-- can only be cleared by changing something nobody should change is not a finding; it is an
-- instrument pointed at the wrong thing, and it has been sitting on the board long enough to be
-- quoted in an acceptance audit as one of two red Phase D checks.
--
-- WHAT REPLACES IT, AND WHAT IS DELIBERATELY NOT DONE. Retyping the expectation from '0' to '54'
-- would be an expectation typed into the check it guards — this repository has already paid for that
-- with fifteen count literals in fn_phase_b_invariants. The expectation stays 0 and the SUBJECT is
-- narrowed to the case that would actually be a defect:
--
--     an event that self-loops, does NOT end its workflow, and whose successor step is
--     accountable to somebody else
--
-- i.e. a producer that has handed the work on and is still recorded as its own consumer. That reads
-- 0 today and it would fire on a genuine regression. The 54 stay on the board as an informational
-- row with their two components named, so nothing is hidden by the narrowing.
--
-- ONE BOUNDARY, STATED. public.phase_b_event carries ZERO non-internal triggers — no
-- z90_phase_b_freeze, not even z00_kernel_truncate_guard — while public.phase_b_workflow_step
-- carries all three. So "frozen" is enforced for the step graph these self-loops are derived from,
-- and is a convention rather than an enforcement for the event table itself. Any blocker that calls
-- the self-loops "a FROZEN Phase B property" is leaning on a freeze that is not attached to the
-- table it names. That is recorded here and is not fixed here: attaching a guard to phase_b_event is
-- a Phase B matter.
-- =================================================================================================

create or replace function public.fn_phase_d_event_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  with ev as (select count(*) n from public.phase_b_event),
       rc as (select count(*) n from public.phase_d_event_reconciliation),
       -- D45. The 54 self-loops split cleanly, and the split is what makes one half a defect and the
       -- other half the frozen graph. `sl` resolves each self-looping event to the step it belongs
       -- to and to that step's declared successor, from the frozen registry only.
       sl as (
         -- phase_d_event_reconciliation has no step_id column. The step is in the event id, and it
         -- parses for all 54 with nothing left over — measured, not assumed:
         -- no_step_parsed 0, no_step_row 0, 15 end the workflow, 39 same owner, 0 different owner.
         select r.event_id, r.producer,
                s.step_id, s.next_step_if_pass,
                (select s2.accountable_role_id from public.phase_b_workflow_step s2
                  where s2.step_id = s.next_step_if_pass) as successor_owner
           from public.phase_d_event_reconciliation r
           join public.phase_b_workflow_step s
             on s.step_id = substring(r.event_id from 'EV-(W[0-9]+-S[0-9]+)')
          where r.is_self_loop
       )
  select 'events_reconciled', (select n::text from ev), (select n::text from rc),
         (select n from rc) = (select n from ev)
  union all
  select 'reconciliations_with_no_frozen_event', '0',
         (select count(*)::text from public.phase_d_event_reconciliation r
           where not exists (select 1 from public.phase_b_event e where e.event_id = r.event_id)),
         not exists (select 1 from public.phase_d_event_reconciliation r
                      where not exists (select 1 from public.phase_b_event e
                                         where e.event_id = r.event_id))
  union all
  select 'events_with_no_factual_state_change', '0',
         (select count(*)::text from public.phase_d_event_reconciliation
           where factual_state_change = '(the frozen registry states no trigger)'),
         not exists (select 1 from public.phase_d_event_reconciliation
                      where factual_state_change = '(the frozen registry states no trigger)')
  union all
  -- D45. WAS: 'event_self_loops', expected 0, measured 54 — every one of them legitimate.
  -- The expectation is unchanged; the subject is the case that would be a defect.
  select 'self_loop_after_handing_the_work_on', '0',
         (select count(*)::text from sl
           where coalesce(next_step_if_pass,'') not in ('','WORKFLOW_COMPLETE')
             and successor_owner is not null
             and successor_owner is distinct from producer),
         not exists (select 1 from sl
                      where coalesce(next_step_if_pass,'') not in ('','WORKFLOW_COMPLETE')
                        and successor_owner is not null
                        and successor_owner is distinct from producer)
  union all
  -- and the 54 stay visible, with the two components that account for all of them, so narrowing the
  -- check above hides nothing.
  select 'event_self_loops_total', 'informational — the frozen graph, not a defect',
         (select count(*)::text from sl) || ' (' ||
         (select count(*)::text from sl where coalesce(next_step_if_pass,'') in ('','WORKFLOW_COMPLETE'))
         || ' end the workflow, ' ||
         (select count(*)::text from sl where coalesce(next_step_if_pass,'') not in ('','WORKFLOW_COMPLETE')
                                          and successor_owner is not distinct from producer)
         || ' hand to a successor the same role owns)', true
  union all
  select 'self_loops_whose_successor_step_does_not_resolve', '0',
         (select count(*)::text from sl
           where coalesce(next_step_if_pass,'') not in ('','WORKFLOW_COMPLETE')
             and successor_owner is null),
         not exists (select 1 from sl
                      where coalesce(next_step_if_pass,'') not in ('','WORKFLOW_COMPLETE')
                        and successor_owner is null)
  union all
  -- THE CHECK THIS FILE EXISTS FOR. A row may not say it was observed unless the outbox says so.
  select 'registry_only_events_reported_runtime_observed', '0',
         (select count(*)::text from public.phase_d_event_reconciliation
           where runtime_observation = 'OBSERVED_IN_OUTBOX' and emissions_observed = 0),
         not exists (select 1 from public.phase_d_event_reconciliation
                      where runtime_observation = 'OBSERVED_IN_OUTBOX' and emissions_observed = 0)
  union all
  select 'events_with_no_registered_cancellation_writer', '0',
         (select count(*)::text from public.phase_d_event_reconciliation
           where cancellation_behaviour = 'NO REGISTERED CANCELLATION WRITER'),
         not exists (select 1 from public.phase_d_event_reconciliation
                      where cancellation_behaviour = 'NO REGISTERED CANCELLATION WRITER')
  union all
  select 'events_with_no_dedupe_key', '0',
         (select count(*)::text from public.phase_d_event_reconciliation
           where coalesce(btrim(dedupe_key),'') = ''),
         not exists (select 1 from public.phase_d_event_reconciliation
                      where coalesce(btrim(dedupe_key),'') = '')
  union all
  -- DISCLOSED, AND THE WHOLE POINT. The gap between what the structure claims and what has happened
  -- is a number the founder can see rather than a word that hides it. It is NOT ratcheted to zero:
  -- closing it means running the business automation that is deliberately held.
  select 'events_structurally_connected_but_never_observed', 'informational — automation is held',
         (select count(*)::text from public.phase_d_event_reconciliation
           where structural_status = 'CONNECTED' and runtime_observation = 'NEVER_OBSERVED'), true
  union all
  select 'events_observed_at_runtime', 'informational',
         (select count(*)::text from public.phase_d_event_reconciliation
           where runtime_observation = 'OBSERVED_IN_OUTBOX'), true;
$fn$;


-- ---- CONTROL — the narrowed predicate must be SEEN to fire -------------------------------------
-- A zero that has never been seen to move is worth less than the red it replaced. The obvious
-- control would point a self-looping step at a successor owned by somebody else and watch the check
-- go red — but public.phase_b_workflow_step carries z90_phase_b_freeze, and writing to it to prove a
-- Phase D check works would be working around a guard that is correct. So the predicate itself is
-- evaluated over a constructed row set containing one row of the defective shape, and must count it.

do $ctl$
declare v_fires int; v_clean int; v_total text; v_red int;
begin
  -- the live board must be green on the narrowed check, and must still publish the 54
  select count(*) into v_red from public.fn_phase_d_event_state()
   where check_name = 'self_loop_after_handing_the_work_on' and not ok;
  if v_red <> 0 then
    raise exception 'D45: the narrowed check is red on live data: %',
      (select actual from public.fn_phase_d_event_state()
        where check_name = 'self_loop_after_handing_the_work_on');
  end if;

  select actual into v_total from public.fn_phase_d_event_state()
   where check_name = 'event_self_loops_total';
  if v_total not like '54 (%' then
    raise exception 'D45: the informational row reads %, not the measured 54.', v_total;
  end if;
  if v_total not like '%15 end the workflow%' or v_total not like '%39 hand to a successor%' then
    raise exception 'D45: the two components do not account for the 54: %', v_total;
  end if;

  -- POSITIVE: the same predicate, over three rows — one that ends the workflow, one handed to the
  -- same owner, and one handed to a DIFFERENT owner. It must count exactly the third.
  select count(*) into v_fires from (
    values ('EV-ZZ-DEMO-1', 'role_a', 'WORKFLOW_COMPLETE', null::text),
           ('EV-ZZ-DEMO-2', 'role_a', 'W99-S02',          'role_a'),
           ('EV-ZZ-DEMO-3', 'role_a', 'W99-S03',          'role_b')
  ) as t(event_id, producer, next_step_if_pass, successor_owner)
   where coalesce(next_step_if_pass,'') not in ('','WORKFLOW_COMPLETE')
     and successor_owner is not null
     and successor_owner is distinct from producer;
  if v_fires <> 1 then
    raise exception 'D45 CONTROL FAILED: the predicate counted % of a constructed set holding exactly one defective row.', v_fires;
  end if;

  -- NEGATIVE: with the defective row removed it must count nothing, so the 1 above is the row and
  -- not the predicate matching everything.
  select count(*) into v_clean from (
    values ('EV-ZZ-DEMO-1', 'role_a', 'WORKFLOW_COMPLETE', null::text),
           ('EV-ZZ-DEMO-2', 'role_a', 'W99-S02',          'role_a')
  ) as t(event_id, producer, next_step_if_pass, successor_owner)
   where coalesce(next_step_if_pass,'') not in ('','WORKFLOW_COMPLETE')
     and successor_owner is not null
     and successor_owner is distinct from producer;
  if v_clean <> 0 then
    raise exception 'D45 CONTROL FAILED: the predicate counted % rows of a set with no defective row.', v_clean;
  end if;

  -- and the step parse the check depends on must cover every one of the 54, or the narrowing has
  -- quietly dropped rows rather than classified them.
  if (select count(*) from public.phase_d_event_reconciliation r
       where r.is_self_loop
         and not exists (select 1 from public.phase_b_workflow_step s
                          where s.step_id = substring(r.event_id from 'EV-(W[0-9]+-S[0-9]+)'))) <> 0 then
    raise exception 'D45: % self-looping events do not resolve to a step, so the narrowed check does not see them.',
      (select count(*) from public.phase_d_event_reconciliation r
        where r.is_self_loop
          and not exists (select 1 from public.phase_b_workflow_step s
                           where s.step_id = substring(r.event_id from 'EV-(W[0-9]+-S[0-9]+)')));
  end if;

  raise notice 'D45: self_loop_after_handing_the_work_on is 0, the predicate counts exactly the defective shape and nothing else, and the 54 are published as %', v_total;
end
$ctl$;
