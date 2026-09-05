-- THE INVOKER'S CLOSE CARRIES ITS DELIVERABLE AND ITS DECIDER (5 Sep 2026).
--
-- fn_action_invoke_collect closes an org_task when the HTTP executor it queued succeeds. It wrote
-- mode, executor, http_status and a summary -- and neither result.deliverable nor decided_by. The
-- guard a10_org_task_done_needs_a_determination (org_task lane packet, 5 Sep) refuses exactly that
-- shape, and this close sits inside an exception block, so the refusal would have been swallowed and
-- the task left open for ever while the execution read 'succeeded'. The adversarial audit of PR #515
-- named it as a latent red before it fired. The executor's response body is the deliverable; the
-- invoker that ran the executor is the decider. Every other line is the live definition.
--
--   node scripts/apply_sql.mjs scripts/sql/the_invokers_close_carries_its_deliverable_and_decider.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_action_invoke_collect()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_held int := 0; v_ok int := 0; v_retry int := 0; v_dead int := 0; v_wait int := 0;
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
      if r.started_at < now() - interval '10 minutes' then
        v_status := null; v_err := 'no pg_net response after 10 minutes';
      else
        v_wait := v_wait + 1; continue;
      end if;
    end if;

    -- A 200 IS NOT ENOUGH. quote_compare returned {ok:false,'parse_failed'} at HTTP 200 for weeks.
    v_good := v_status = 200
              and coalesce(v_body,'') <> ''
              and coalesce((nullif(v_body,'')::jsonb ->> 'ok'), 'true') <> 'false';

    -- HELD IS NOT FAILED (3 Sep 2026). An executor that answers 200 {held:true} could not do the
    -- work because the paid model is held open-circuit — the founder's own hold, not a fault. Until
    -- today that answer (or a 502 analytics_llm_unavailable) was retried to max_attempts and then
    -- dead-lettered, twelve times a day, and the resilience watcher paged the founder about his own
    -- hold. The row is PARKED as status='held': no retry, no dead letter, its org_task untouched, and
    -- fn_action_release_held() re-queues every parked row the day a model answers again.
    if v_status = 200 and coalesce(v_body,'') <> '' and pg_input_is_valid(v_body, 'jsonb')
       and coalesce((v_body::jsonb ->> 'held'), 'false') = 'true' then
      update public.action_execution
         set status = 'held', finished_at = null,
             response = coalesce(response,'{}'::jsonb) - 'net_request_id' || jsonb_build_object(
               'invoker','held','at',now(),'http_status',v_status,
               'reason', coalesce(v_body::jsonb ->> 'reason', 'inference_held'))
       where id = r.id;
      v_held := v_held + 1;
      continue;
    end if;

    if v_good then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','succeeded','at',now(),'http_status',v_status,
               'body', left(coalesce(v_body,''), 4000))
       where id = r.id;
      v_ok := v_ok + 1;

      begin
        update public.org_tasks k
           set status = 'done', updated_at = now(), last_run_at = now(),
               -- 5 SEP 2026: a10_org_task_done_needs_a_determination refuses a close with no
               -- deliverable or no decided_by (the org_task lane packet closed the second closing
               -- path). This close carried a summary and no decider, so its next success would
               -- have been refused inside the exception block below and swallowed. The executor's
               -- own response IS the deliverable, and the invoker that ran it is the decider.
               decided_by = coalesce(k.decided_by, 'invoker:' || r.executor),
               result = coalesce(k.result,'{}'::jsonb) || jsonb_build_object(
                 'mode','executed_by_invoker', 'executor', r.executor,
                 'deliverable', left(coalesce(v_body, ''), 4000),
                 'http_status', v_status, 'at', now(),
                 'summary', left(coalesce(v_body,''), 500),
                 -- SIX KEYS, NOT THREE (12 Aug 2026). See the header: action_worker is the largest
                 -- producer in the estate and emits `outcome`, which none of the original three
                 -- matched, so 254 of 556 invocations in 7 days closed their task with a NULL
                 -- deliverable while carrying real work in the body. Appended, never reordered, so
                 -- anything extracting correctly today is untouched.
                 'deliverable', case
                    when pg_input_is_valid(coalesce(v_body,''), 'jsonb') then coalesce(
                      nullif(btrim(coalesce((v_body::jsonb)->>'recommendation','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'deliverable','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'note','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'outcome','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'summary','')),''),
                      nullif(btrim(coalesce((v_body::jsonb)->>'result','')),''))
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

  return jsonb_build_object('succeeded', v_ok, 'retrying', v_retry, 'dead_lettered', v_dead, 'held', v_held,
                            'still_in_flight', v_wait, 'ran_at', now());
end
$function$
