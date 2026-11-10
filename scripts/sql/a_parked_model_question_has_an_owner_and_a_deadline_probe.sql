-- PROBE (pure, no DDL, aborted transaction) for a_parked_model_question_has_an_owner_and_a_deadline.sql. Seat: it_engineer.
-- Run AFTER the definition in the same transaction; it ends in raise exception, so nothing survives.
-- It settles today's pending held questions and reports what closed and what stays; PROBE OK needs: every pending row
-- has an owner and a deadline, no person-facing question was dismissed, nothing closed whose question is still live
-- inside its deadline, and a row filed after the first settle gets its owner and deadline on the next.
do $p$
declare v_before int; v jsonb; v_after int; v_person_dismissed int; v_live_closed int; v_new jsonb; v_ok boolean; v_surfaces jsonb;
begin
  select count(*) into v_before from public.agent_actions where kind = 'held_question' and status = 'pending';
  v := public.fn_held_questions_settle(5000);
  select count(*) into v_after from public.agent_actions where kind = 'held_question' and status = 'pending';
  select count(*) into v_person_dismissed from public.agent_actions a join public.reasoning_held_question r on r.id = (a.detail->>'held_id')::bigint
   where a.kind = 'held_question' and a.decided_by = 'it_engineer:fn_held_questions_settle' and a.status = 'dismissed'
     and public.fn_held_question_is_person_facing(r.surface);
  select count(*) into v_live_closed from public.agent_actions a join public.reasoning_held_question r on r.id = (a.detail->>'held_id')::bigint
   where a.kind = 'held_question' and a.decided_by = 'it_engineer:fn_held_questions_settle' and r.status in ('held', 'reasoning')
     and not exists (select 1 from public.reasoning_held_question r2 where r2.seat = r.seat and r2.surface = r.surface
                      and r2.subject is not distinct from r.subject and r2.created_at > r.created_at);
  select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) into v_surfaces from (
    select r.surface s, count(*) n from public.agent_actions a join public.reasoning_held_question r on r.id = (a.detail->>'held_id')::bigint
     where a.kind = 'held_question' and a.status = 'pending' and a.detail ? 'overdue_at' group by 1 order by 2 desc limit 12) z;
  insert into public.agent_actions (agent, kind, status, title, detail)
  values ('it_engineer', 'held_question', 'pending', 'probe held question', jsonb_build_object('held_id', 0, 'surface', 'probe'));
  perform public.fn_held_questions_settle(5000);
  select detail into v_new from public.agent_actions where kind = 'held_question' and title = 'probe held question' order by id desc limit 1;
  v_ok := v_person_dismissed = 0 and v_live_closed = 0 and v_new ? 'owner_seat' and v_new ? 'due_at'
          and not exists (select 1 from public.agent_actions where kind = 'held_question' and status = 'pending' and not (detail ? 'due_at'));
  raise exception '% CHK<<%>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, jsonb_build_object(
    'pending_before', v_before, 'settle', v, 'pending_after', v_after, 'person_facing_dismissed', v_person_dismissed,
    'live_closed', v_live_closed, 'overdue_by_surface', v_surfaces, 'new_row_detail', v_new);
end $p$;
