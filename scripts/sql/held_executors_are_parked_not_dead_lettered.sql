-- HELD EXECUTORS ARE PARKED, NOT DEAD-LETTERED; REHEARSALS DECLARE THEIR WINDOW; A DEDUPE KEY IS
-- STORED (3 Sep 2026).
--
-- Three defects, one theme: instruments paging the founder about things that are not failures.
--
-- 1. fn_action_invoke_collect. analytics_recommend answered 502 analytics_llm_unavailable because the
--    paid model is held (the founder's own hold, open-circuit on 8 of 8 routes). The collector retried
--    it to max_attempts and dead-lettered it — 12 open dead letters in one night — and the resilience
--    watcher then paged the founder about the dead-letter queue. Executors now answer 200 {held:true}
--    when the gate is closed, and the collector PARKS that row as status='held': no retry, no dead
--    letter, the org_task untouched. fn_action_release_held() re-queues parked rows when a model
--    answers again. The definition below is the live routine with that one branch added; the two
--    earlier files that define it stay in the manifest above this one and this one is canonical.
--
-- 2. rehearsal_window. demo_factory.withRun stands up ZZ DEMO fixtures on the production database
--    and tears them down; the functions it exercises log their run rows into agent_runs like any
--    other call, and fn_watch_failed_runs cannot tell an operator's rehearsal from a customer's
--    failure. It paged the founder twice this morning about this session's own probes. A rehearsal
--    now declares its window (withRun opens and closes it), and the watcher counts rows inside a
--    declared window separately instead of paging. Rows outside any window are judged exactly as
--    before — a real failure during a rehearsal that ALSO fails outside it is still paged.
--
-- 3. founder_alerts.dedupe_key. alert_founder accepted a dedupe_key and matched it against the SUBJECT
--    of sent notifications, where 'failed_runs:2026-09-03' never appears — so passing a key silently
--    disabled deduplication. The key is now stored on the alert row and matched there.

alter table public.founder_alerts add column if not exists dedupe_key text;
create index if not exists founder_alerts_dedupe_idx on public.founder_alerts (dedupe_key, created_at desc) where dedupe_key is not null;

create table if not exists public.rehearsal_window (
  id         bigint generated always as identity primary key,
  run_tag    text not null,
  opened_by  text not null default 'demo_factory.withRun',
  started_at timestamptz not null default now(),
  ended_at   timestamptz,
  note       text
);
alter table public.rehearsal_window enable row level security;
create index if not exists rehearsal_window_open_idx on public.rehearsal_window (started_at, ended_at);

-- A row inside a declared window is not a page. Windows are never deleted; a window left open (a
-- crashed rehearsal) is closed by the next tick after 6 hours so it cannot hide anything for long.
create or replace function public.fn_rehearsal_window_covers(p_at timestamptz)
returns boolean
language sql
stable
set search_path to 'public'
as $$
  select exists (
    select 1 from public.rehearsal_window w
    where p_at >= w.started_at
      and p_at <= coalesce(w.ended_at, w.started_at + interval '6 hours')
  );
$$;

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

  return jsonb_build_object('succeeded', v_ok, 'retrying', v_retry, 'dead_lettered', v_dead, 'held', v_held,
                            'still_in_flight', v_wait, 'ran_at', now());
end
$function$
;

create or replace function public.fn_action_release_held()
returns jsonb
language plpgsql
set search_path to 'public'
as $$
declare v_n int;
begin
  update public.action_execution
     set status = 'queued',
         response = coalesce(response,'{}'::jsonb) || jsonb_build_object('invoker','released_from_held','at',now())
   where status = 'held';
  get diagnostics v_n = row_count;
  return jsonb_build_object('released', v_n, 'at', now());
end;
$$;
