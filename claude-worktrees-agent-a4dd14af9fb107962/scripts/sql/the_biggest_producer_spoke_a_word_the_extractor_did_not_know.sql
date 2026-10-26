-- The biggest producer spoke a word the extractor did not know
-- ===========================================================
--
-- Yesterday's fix to fn_action_invoke_collect was right about the defect and wrong about the
-- vocabulary. Its own comment is worth re-reading: "TEN routines read result.deliverable -
-- fn_task_lesson, fn_learning_loop_sweep, fn_task_review and fn_ws_company_os among them - so a
-- task closed by this path produced real work that never entered the learning loop." It then
-- extracted the deliverable from three key names:
--
--     recommendation -> deliverable -> note
--
-- ACTION_WORKER EMITS NONE OF THEM. It emits `outcome`, and it is the single largest producer in
-- the estate. Measured over 7 days on production, succeeded invocations:
--
--     action_worker        254   1 carry rec/deliverable/note   254 carry outcome
--     analytics_recommend  203   203                            203
--     kb_deepen             70   0                              0
--     exec_agents           15   0                              0
--     ai_health / cost_snapshot / compliance_archive  13   0     0
--
-- So 204 of 556 invocations were extractable and 254 more were sitting one key name away. The body
-- is real work, not a status line - a representative action_worker response reads
-- {"ok":true,"worked":1,"action_id":2831,"agent":"bd","kind":"handoff","chars":5901,
--  "outcome":"Outreach drafts and lead-qualification criteria for hospitality-supplies-companies
--  and gym-and-sports-equipment-suppliers are complete..."}
-- and every one of those 254 tasks closed with deliverable NULL, invisible to all ten readers.
--
-- The brief called this "most executors emit nothing to extract". For action_worker that is not
-- true: it emitted 254 outcomes into a reader that was listening for a different word. This is the
-- same two-vocabularies defect as leads.invite_trades against taxonomy_trade, one layer along.
--
-- `outcome`, `summary` and `result` are APPENDED to the coalesce chain, never inserted ahead of it,
-- so nothing that extracts correctly today changes by a single byte. The only rows affected are
-- the ones that resolve to NULL now.
--
-- The backfill recovers what was already produced. It reads the body this function itself stored on
-- action_execution.response and pulls the same keys out of it - extraction of work that exists, not
-- invention of work that does not. Tasks whose stored body carries none of the six keys stay NULL,
-- which is the honest answer for kb_deepen and exec_agents: they genuinely return nothing to
-- extract, and that is a separate fix in their own response bodies.

create or replace function public.fn_action_invoke_collect()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
               result = coalesce(k.result,'{}'::jsonb) || jsonb_build_object(
                 'mode','executed_by_invoker', 'executor', r.executor,
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

  return jsonb_build_object('succeeded', v_ok, 'retrying', v_retry, 'dead_lettered', v_dead,
                            'still_in_flight', v_wait, 'ran_at', now());
end
$function$;

-- Recover what was already produced, from the body this function stored at the time.
update public.org_tasks k
   set result = k.result || jsonb_build_object('deliverable', x.found,
                  'deliverable_recovered_at', now())
  from (
    select a.id,
           (a.request->>'org_task_id')::bigint as task_id,
           coalesce(
             nullif(btrim(coalesce(((a.response->>'body')::jsonb)->>'recommendation','')),''),
             nullif(btrim(coalesce(((a.response->>'body')::jsonb)->>'deliverable','')),''),
             nullif(btrim(coalesce(((a.response->>'body')::jsonb)->>'note','')),''),
             nullif(btrim(coalesce(((a.response->>'body')::jsonb)->>'outcome','')),''),
             nullif(btrim(coalesce(((a.response->>'body')::jsonb)->>'summary','')),''),
             nullif(btrim(coalesce(((a.response->>'body')::jsonb)->>'result','')),'')) as found
      from public.action_execution a
     where a.status = 'succeeded'
       and (a.request->>'org_task_id') is not null
       and jsonb_typeof(a.response->'body') = 'string'
       and pg_input_is_valid(coalesce(a.response->>'body',''), 'jsonb')
  ) x
 where k.id = x.task_id
   and x.found is not null
   and coalesce(btrim(k.result->>'deliverable'), '') = '';
