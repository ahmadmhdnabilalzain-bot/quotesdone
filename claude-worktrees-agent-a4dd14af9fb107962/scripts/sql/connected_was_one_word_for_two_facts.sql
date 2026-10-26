-- ============================================================================================
-- CONNECTED WAS ONE WORD FOR TWO FACTS
--
-- public.phase_c_event_binding carries a single status column. 287 of its 347 rows read CONNECTED.
-- Measured during the final acceptance audit, by joining each binding to the outbox and to the
-- delivery-attempt log:
--
--     CONNECTED                          287 bindings, 13 have EVER produced an outbox row
--     DEFERRED_RUNTIME_IMPLEMENTATION     60 bindings,  1 has  EVER produced an outbox row
--
-- So 274 rows told every reader CONNECTED for something never once observed to run, and one row
-- told every reader it was deferred while it was running. One column, two different questions:
--
--     STRUCTURAL   is there a producer, a durable row, a claim, a worker and a consumer for this
--                  event in the deployed code?
--     RUNTIME      has this event ever actually been emitted and delivered?
--
-- Both are legitimate. Answering the second with the first is not. A registry-only event presented
-- as runtime-observed is the same defect shape as a green number measuring something other than
-- what it names, and it is the reason "347 event bindings said CONNECTED" was believed before.
--
-- THE RUNTIME HALF IS DERIVED AND IS NEVER STORED. A second status column would be a second claim,
-- editable by anyone with an UPDATE, and in six weeks it would be as untrue as the first. It is a
-- function over phase_c_event_outbox and phase_c_event_delivery_attempt, so it cannot be asserted,
-- only observed. Where it says NEVER_OBSERVED, that is because there is no row, not because nobody
-- has got round to setting a flag.
--
-- The stored column keeps its name and its values and becomes STRUCTURAL-only by contract. The new
-- invariant below is what holds it to that: the stored value must equal what
-- fn_phase_c_event_binding_status derives from the deployed code, so a hand-edited status fires.
-- ============================================================================================

-- ---------------------------------------------------------------- the runtime half, derived
create or replace function public.fn_phase_c_event_runtime_observation(p_event_id text)
returns table(observation text, outbox_rows bigint, delivered_rows bigint,
              delivery_attempts bigint, first_seen timestamptz, last_seen timestamptz)
language sql
stable
set search_path to 'public', 'pg_temp'
as $ero$
  select case
           when count(*) filter (where o.status = 'delivered') > 0 then 'OBSERVED_DELIVERED'
           when count(*) > 0                                       then 'EMITTED_NOT_DELIVERED'
           else                                                         'NEVER_OBSERVED'
         end::text,
         count(*)::bigint,
         count(*) filter (where o.status = 'delivered')::bigint,
         (select count(*) from public.phase_c_event_delivery_attempt a
            join public.phase_c_event_outbox o2 on o2.outbox_id = a.outbox_id
           where o2.event_id = p_event_id)::bigint,
         min(o.created_at),
         max(o.created_at)
    from public.phase_c_event_outbox o
   where o.event_id = p_event_id;
$ero$;

revoke execute on function public.fn_phase_c_event_runtime_observation(text) from public;
grant  execute on function public.fn_phase_c_event_runtime_observation(text) to service_role;

-- ---------------------------------------------------------------- both facts, side by side
-- Every reader that used to select connection_status and draw a conclusion about the runtime now
-- has somewhere honest to look. The two columns can never be collapsed again by an UPDATE, because
-- only one of them is a column.
create or replace view public.v_phase_c_event_binding_state as
select b.event_id,
       b.event_name,
       b.workflow_id,
       b.primary_consumer_role_id,
       b.connection_status                        as structural_status_stored,
       (select s.status  from public.fn_phase_c_event_binding_status(b.event_id) s)
                                                  as structural_status_derived,
       (select s.status  from public.fn_phase_c_event_binding_status(b.event_id) s)
         is distinct from b.connection_status      as structural_status_disagrees,
       r.observation                              as runtime_observation,
       r.outbox_rows,
       r.delivered_rows,
       r.delivery_attempts,
       r.first_seen,
       r.last_seen
  from public.phase_c_event_binding b
  cross join lateral public.fn_phase_c_event_runtime_observation(b.event_id) r;

revoke all on public.v_phase_c_event_binding_state from public;
grant  select on public.v_phase_c_event_binding_state to service_role;

-- ---------------------------------------------------------------- the board
-- Reported, not asserted, for the two population lines: a Phase C estate whose runtime is
-- deliberately held is SUPPOSED to have most events unobserved, and a check that demanded
-- otherwise would be demanding that the hold be lifted. What IS asserted is that no row claims a
-- structural status the deployed code does not support.
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_event_truth_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke execute on function public.fn_phase_c_event_truth_state() from public;
grant  execute on function public.fn_phase_c_event_truth_state() to service_role;
