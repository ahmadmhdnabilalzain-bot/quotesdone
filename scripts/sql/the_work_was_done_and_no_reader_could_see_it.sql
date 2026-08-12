-- THE WORK WAS DONE AND NO READER COULD SEE IT.
--
-- fn_action_invoke_collect closes a task by writing the executor's HTTP response as a
-- 500-character 'summary' blob and never setting 'deliverable'. TEN routines read
-- result.deliverable - fn_task_lesson, fn_learning_loop_sweep, fn_task_review and
-- fn_ws_company_os among them - so every task closed by this path produced real work that
-- never entered the learning loop, was never reviewed, and never reached the founder's screen.
--
-- MEASURED: of 482 done tasks carrying a result, 373 closed 'delivered' and ALL 373 carry a
-- deliverable. 86 closed 'executed_by_invoker' and 81 do not; 12 closed 'executed' and none do.
--
-- org_tasks 1309 is the example that matters: the AI-spend escalation the founder named as
-- his own decision input. It closed with a real, specific recommendation - "Redirect AI spend
-- from internal automation and quote optimization to diagnosing why the 20,470-supplier
-- directory generates zero RFQs and why supplier approval is stuck at 0/6 - these are the
-- revenue gates, not AI quality" - buried in a stringified body where none of the ten readers
-- would ever find it. I first read that task as a false success BECAUSE of this, and it was not.
--
-- FIXED FORWARD ONLY. The 93 historical rows stored just the first 500 characters, and
-- reconstructing a 'deliverable' from a truncated blob would hand partial text to fn_task_review
-- and the learning loop as if it were the finished work product. They keep their summary.
--
-- Transformed from the LIVE production definition, not retyped: one changed jsonb key.
CREATE OR REPLACE FUNCTION public.fn_action_invoke_collect()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_ok int := 0; v_retry int := 0; v_dead int := 0; v_wait int := 0;
        v_status int; v_body text; v_err text; v_good boolean;
begin
  for r in
    select a.id, a.action_class, a.attempts, a.executor,
           (a.response->>'net_request_id')::bigint req,
           coalesce((a.response->>'max_attempts')::int, 1) max_attempts,
           a.started_at
      from public.action_execution a
     where a.status = 'running' and (a.response->>'net_request_id') is not null
  loop
    select status_code, content, error_msg into v_status, v_body, v_err
      from net._http_response where id = r.req;

    if not found then
      -- pg_net has not resolved it yet. Only a request older than its own timeout is a failure.
      if r.started_at < now() - interval '10 minutes' then
        v_status := null; v_err := 'no pg_net response after 10 minutes';
      else
        v_wait := v_wait + 1; continue;
      end if;
    end if;

    -- A 200 IS NOT ENOUGH. quote_compare returned {ok:false,'parse_failed'} at HTTP 200 for
    -- weeks. The body has to not say it failed.
    v_good := v_status = 200
              and coalesce(v_body,'') <> ''
              and coalesce((nullif(v_body,'')::jsonb ->> 'ok'), 'true') <> 'false';

    if v_good then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','succeeded','at',now(),'http_status',v_status,
               'body', left(coalesce(v_body,''), 4000))
       where id = r.id;
      v_ok := v_ok + 1;

      -- Close the org_task this invocation was carrying out. The task is the unit of work the
      -- company tracks; leaving it 'in_progress' after its executor returned 200 would keep it in
      -- the 439-row backlog for ever.
      --
      -- IN ITS OWN SUB-BLOCK, and that is not defensive padding. The very first scheduled run of
      -- this function died on org_tasks #189: fn_org_task_root_cause_guard refuses to close a
      -- KPI-miss task that records no root_cause, and one refusing task aborted the entire collect
      -- pass, leaving every other invocation stuck in 'running'. The guard is right — a missed KPI
      -- must say why — so the invocation is still recorded as succeeded and the TASK stays open
      -- with the reason attached, which is the true state: the executor ran, the task cannot close.
      begin
        update public.org_tasks k
           set status = 'done', updated_at = now(), last_run_at = now(),
               result = coalesce(k.result,'{}'::jsonb) || jsonb_build_object(
                 'mode','executed_by_invoker', 'executor', r.executor,
                 'http_status', v_status, 'at', now(),
                 'summary', left(coalesce(v_body,''), 500),
                 -- THE WORK WAS DONE AND NO READER COULD SEE IT (12 Aug 2026). This wrote the
                 -- executor response only as a 500-character 'summary' blob and never set
                 -- 'deliverable'. TEN routines read result.deliverable - fn_task_lesson,
                 -- fn_learning_loop_sweep, fn_task_review and fn_ws_company_os among them - so a
                 -- task closed by this path produced real work that never entered the learning
                 -- loop, was never reviewed, and never reached the founder's screen. Measured:
                 -- 373 tasks closed 'delivered' all carry a deliverable; 86 closed
                 -- 'executed_by_invoker' and 12 'executed' mostly do not.
                 --
                 -- org_tasks 1309 - the AI-spend escalation the founder asked for a decision on -
                 -- is the example. It closed with a real, specific recommendation ("Redirect AI
                 -- spend ... to diagnosing why the 20,470-supplier directory generates zero RFQs")
                 -- buried inside a stringified body, invisible to every one of those ten readers.
                 --
                 -- pg_input_is_valid, not a bare cast: this block closes the task, and the header
                 -- above records an incident where one raising statement aborted the entire
                 -- collect pass. A malformed body must not be able to throw here.
                 'deliverable', case
                    when pg_input_is_valid(coalesce(v_body,''), 'jsonb') then coalesce(
                      nullif(btrim(coalesce((v_body::jsonb)->>'recommendation','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'deliverable','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'note','')),''))
                    else nullif(btrim(coalesce(v_body,'')),'') end)
         where k.id = (select (a.request->>'org_task_id')::bigint from public.action_execution a where a.id = r.id)
           and k.status in ('assigned','in_progress');
      exception when others then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'org_task_close', 'refused', 'reason', left(SQLERRM, 400))
         where id = r.id;
      end;
    elsif coalesce(r.attempts,1) < r.max_attempts then
      update public.action_execution
         set status = 'queued',
             response = coalesce(response,'{}'::jsonb) - 'net_request_id' || jsonb_build_object(
               'invoker','retrying','at',now(),'http_status',v_status,
               'error', left(coalesce(v_err, v_body, 'unknown'), 500))
       where id = r.id;
      v_retry := v_retry + 1;
    else
      update public.action_execution
         set status = 'failed', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'http_status',v_status,
               'error', left(coalesce(v_err, v_body, 'unknown'), 500))
       where id = r.id;
      insert into public.dead_letter(source, source_id, kind, reason, payload, first_failed_at, attempts)
      values ('fn_action_invoke_collect', r.id::text, r.action_class,
              left(coalesce(v_err, v_body, 'http ' || coalesce(v_status::text,'?')), 500),
              jsonb_build_object('executor', r.executor, 'http_status', v_status,
                                 'body', left(coalesce(v_body,''), 2000)),
              now(), coalesce(r.attempts,1));
      v_dead := v_dead + 1;
    end if;
  end loop;

  return jsonb_build_object('succeeded', v_ok, 'retrying', v_retry, 'dead_lettered', v_dead,
                            'still_in_flight', v_wait, 'ran_at', now());
end $function$;
