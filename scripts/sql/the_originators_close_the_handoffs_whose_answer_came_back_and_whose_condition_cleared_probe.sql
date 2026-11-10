-- PROBE (pure, no DDL, aborted transaction) for the_originators_close_the_handoffs_whose_answer_came_back_and_whose_condition_cleared.sql.
-- Seat: ceo. Run AFTER the definition (and after the_knowledge_request_duty_names_itself_when_it_closes_a_handoff.sql) in the
-- same transaction. It always ends in raise exception, so every close it makes rolls back; the counts come out in the message.
--   it_*     it.finding handoffs whose occurrence is over: before, closed by fn_it_close_cleared_handoffs, left after
--   ceo_*    the CEO's answered root-cause / review / revise / month-directive handoffs: before, closed, left
--   kr_*     knowledge.request handoffs whose gap is no longer open: before, closed by the fixed duty, left
-- PROBE OK needs: every close has its originator_close_record row and its reading; nothing closed whose predicate is false
-- (an open finding's own occurrence, a root cause whose task is open in the current month); the knowledge tick no longer raises.
do $p$
declare
  v_it_before int; v_it jsonb; v_it_after int; v_ceo_before int; v_ceo jsonb; v_ceo_after int;
  v_kr_before int; v_kr jsonb; v_kr_after int; v_bad int; v_unrecorded int; v_ok boolean; v_open bigint[];
begin
  -- the handoffs open before the sweeps: only THEIR closes are judged (an earlier file in the same transaction may close others)
  select coalesce(array_agg(a.id), '{}') into v_open from public.agent_actions a
   where a.kind = 'handoff' and a.status = 'pending'
     and a.detail->>'type' in ('it.finding', 'ceo.root_cause', 'deliberation.review', 'ceo.revise', 'ceo.month_directive');
  select count(*) into v_it_before from public.agent_actions a left join public.it_engineer_finding f on f.issue_key = a.detail->>'issue_key'
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'pending' and a.detail ? 'replied_at'
     and (f.issue_key is null or f.closed_at is not null or f.started_at > (a.detail->>'occurrence_started_at')::timestamptz);
  select count(*) into v_ceo_before from public.agent_actions a
   where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'from' = 'ceo' and a.detail ? 'replied_at'
     and a.detail->>'type' in ('ceo.root_cause', 'deliberation.review', 'ceo.revise', 'ceo.month_directive');
  select count(*) into v_kr_before from public.sales_knowledge_gap g
   where g.status <> 'open' and g.handoff_id is not null and (g.question like 'ZZ DEMO%') = false
     and exists (select 1 from public.agent_actions a where a.id = g.handoff_id and a.status not in ('done', 'failed'));

  v_it := public.fn_it_close_cleared_handoffs(500);
  v_ceo := public.fn_ceo_closes_answered_handoffs();
  v_kr := public.fn_customer_support_knowledge_request_tick();

  select count(*) into v_it_after from public.agent_actions a left join public.it_engineer_finding f on f.issue_key = a.detail->>'issue_key'
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'pending' and a.detail ? 'replied_at'
     and (f.issue_key is null or f.closed_at is not null or f.started_at > (a.detail->>'occurrence_started_at')::timestamptz);
  select count(*) into v_ceo_after from public.agent_actions a
   where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'from' = 'ceo' and a.detail ? 'replied_at'
     and a.detail->>'type' in ('ceo.root_cause', 'deliberation.review', 'ceo.revise', 'ceo.month_directive');
  select count(*) into v_kr_after from public.sales_knowledge_gap g
   where g.status <> 'open' and g.handoff_id is not null and (g.question like 'ZZ DEMO%') = false
     and exists (select 1 from public.agent_actions a where a.id = g.handoff_id and a.status not in ('done', 'failed'));

  -- a close with no record, or a record with an empty reading
  select count(*) into v_unrecorded from public.agent_actions a
   where a.id = any (v_open) and a.status = 'done'
     and not exists (select 1 from public.originator_close_record r where r.handoff_id = a.id and r.reading <> '{}'::jsonb);
  -- a close the predicate does not allow: an it.finding whose own occurrence is still open, a root cause of an open
  -- task in the current month
  select count(*) into v_bad from public.originator_close_record r join public.agent_actions a on a.id = r.handoff_id
   where r.closed_at = now() and (
         (r.handoff_type = 'it.finding' and exists (select 1 from public.it_engineer_finding f where f.issue_key = a.detail->>'issue_key'
            and f.closed_at is null and f.started_at <= (a.detail->>'occurrence_started_at')::timestamptz))
      or (r.handoff_type = 'ceo.root_cause' and exists (select 1 from public.ceo_task t
            where t.task_id = case when a.detail->>'subject_id' ~ '^[0-9]+$' then (a.detail->>'subject_id')::bigint end
              and t.state not in ('done', 'closed', 'cancelled'))
          and (case when coalesce(a.detail->>'day', '') ~ '^\d{4}-\d{2}-\d{2}$' then date_trunc('month', (a.detail->>'day')::date) end)
              = date_trunc('month', now() at time zone 'Asia/Dubai')));

  v_ok := v_unrecorded = 0 and v_bad = 0 and coalesce((v_it->>'errors')::int, 0) = 0 and coalesce((v_ceo->>'errors')::int, 0) = 0
          and v_kr_after = 0 and v_it_after <= v_it_before and v_ceo_after <= v_ceo_before;
  raise exception '% CHK<<%>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, jsonb_build_object(
    'it_before', v_it_before, 'it_closed', v_it->'closed', 'it_kept', v_it->'kept', 'it_errors', v_it->'error_detail', 'it_after', v_it_after,
    'ceo_before', v_ceo_before, 'ceo_closed', v_ceo->'closed_by_type', 'ceo_errors', v_ceo->'error_detail', 'ceo_after', v_ceo_after,
    'kr_before', v_kr_before, 'kr_closed', v_kr->'closed', 'kr_after', v_kr_after, 'unrecorded', v_unrecorded, 'bad', v_bad);
end $p$;
