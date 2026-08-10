-- THE HTTP INVOKER — the missing piece that makes 39 registered executors able to execute.
--
-- WHAT WAS MEASURED FIRST. org_action_executor holds 55 rows: 16 kind='rpc' (a database routine
-- fn_execution_run can PERFORM) and 39 kind='edge', whose target is an edge function —
-- quote_compare, ai_health, match, knowledge_exam, send_outbox. fn_execution_run invokes nothing
-- for those: it writes an agent_actions row telling a person. The table was designed for an
-- invoker — idempotency_strategy, timeout_seconds, max_attempts, backoff, required_authority and
-- compensation_action_class are all columns on it — and not one was implemented.
--
-- AND A SECOND MEASUREMENT THAT CHANGES THE PLAN. action_execution holds 4 rows in total and
-- ZERO queued, and none of the 199 pending agent_actions has a matching executor at all —
-- agent_actions.kind is a different vocabulary (handoff, improvement_question, knowledge_task)
-- from org_action_executor.action_class. So this invoker does not drain the 199; nothing about
-- it could. It makes the executor path real for the work that arrives through fn_decide.
--
-- RISK ORDER, ENFORCED BY PREDICATE RATHER THAN BY INTENTION. Only
-- risk_tier='low' AND advisory_safe AND reversible is dispatched — the 27. Everything else is
-- left queued with a recorded reason, so widening later is one predicate and a decision, not a
-- rewrite. Three refusals are absolute and separate from the risk tier:
--   * required_authority = 'founder'  (refund_within_window) is never auto-invoked;
--   * an action that is NOT reversible and declares NO compensation_action_class is refused —
--     this is OS_PORTALS gate 19 ("destructive actions have rollback/undo where technically
--     possible") turned from a claim into an enforcement. Seven executors are in that state today
--     (collections_chase, escalate_founder, invite, nudge, outreach_send, pdpl_action,
--     refund_within_window) and every one of them stays refused until someone declares one;
--   * an inactive executor row.
--
-- TWO PHASES, BECAUSE pg_net IS ASYNCHRONOUS. net.http_post returns a request id and the response
-- lands later in net._http_response. Dispatch marks the row running and records the request id;
-- collect asserts on it. A single-phase invoker that returned "sent" would be asserting on a
-- function call, not on a 200.

-- The project ref, seeded per project by scripts' apply step. Staging has no cron job that
-- names a functions/v1 URL, so scanning cron.job works on production and returns null there.
insert into app_secrets(key, value) values ('project_ref', '__PROJECT_REF__')
  on conflict (key) do update set value = excluded.value;

-- ── the credential: least privilege, scoped to exactly the targets that may be invoked ─────────
do $$
declare v_secret text; v_scope text[]; v_issued jsonb;
begin
  if exists (select 1 from app_secrets where key = 'cred_action_invoker') then
    return;   -- already issued; rotate with fn_internal_credential_rotate('action.invoker', ...)
  end if;
  select array_agg(distinct target order by target) into v_scope
    from org_action_executor
   where kind = 'edge' and active and risk_tier = 'low' and advisory_safe and reversible;
  v_issued := public.fn_internal_credential_issue('action.invoker', v_scope,
                'HTTP invoker for low-risk advisory-safe reversible edge executors', null);
  v_secret := coalesce(v_issued->>'secret', v_issued->>'value', v_issued->>'token');
  if v_secret is null then raise exception 'credential issue returned no secret: %', v_issued::text; end if;
  insert into app_secrets(key, value) values ('cred_action_invoker', v_secret)
    on conflict (key) do update set value = excluded.value;
end $$;

-- ── phase 1: dispatch ──────────────────────────────────────────────────────────────────────────
create or replace function public.fn_action_invoke_dispatch(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_req bigint; v_sent int := 0; v_refused int := 0; v_skipped int := 0;
        v_url text; v_secret text; v_ref text; v_key text;
begin
  select value into v_secret from app_secrets where key = 'cred_action_invoker';
  if v_secret is null then
    return jsonb_build_object('error', 'no cred_action_invoker credential', 'ran_at', now());
  end if;
  -- The project ref is read off an existing cron command rather than hard-coded, so the same
  -- migration file is correct on production and on staging.
  select value into v_ref from app_secrets where key = 'project_ref';
  if v_ref is null then
    select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
      from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
  end if;
  if v_ref is null then return jsonb_build_object('error','cannot determine project ref','ran_at',now()); end if;

  for r in
    select a.id, a.action_class, a.request, a.idempotency_key, a.attempts,
           e.target, e.kind, e.active, e.risk_tier, e.advisory_safe, e.reversible,
           e.required_authority, e.compensation_action_class, e.idempotency_strategy, e.params,
           coalesce(e.timeout_seconds, 60) timeout_seconds, coalesce(e.max_attempts, 1) max_attempts
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
     where a.status = 'queued' and e.kind = 'edge'
     order by a.created_at
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    -- ---- the three absolute refusals, then the risk tier -------------------------------------
    if not r.active
       or coalesce(r.required_authority,'') = 'founder'
       or (not r.reversible and r.compensation_action_class is null)
       or not (r.risk_tier = 'low' and r.advisory_safe and r.reversible) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker', 'refused', 'at', now(),
               'reason', case
                 when not r.active then 'executor row is inactive'
                 when coalesce(r.required_authority,'') = 'founder' then 'reserved to the founder'
                 when (not r.reversible and r.compensation_action_class is null)
                   then 'not reversible and declares no compensation_action_class'
                 else format('risk gate: tier=%s advisory_safe=%s reversible=%s — the invoker dispatches low/advisory_safe/reversible only',
                             r.risk_tier, r.advisory_safe, r.reversible) end)
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- ---- idempotency: the column exists on both tables and was never consulted ---------------
    v_key := coalesce(nullif(btrim(r.idempotency_key),''),
                      r.action_class || ':' || md5(coalesce(r.request::text,'')));
    if r.idempotency_strategy is distinct from 'none_read_only'
       and exists (select 1 from public.action_execution x
                    where x.id <> r.id and x.status = 'succeeded'
                      and x.idempotency_key = v_key
                      and x.finished_at > now() - interval '24 hours') then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','deduplicated','at',now(),'idempotency_key',v_key,
               'strategy', r.idempotency_strategy)
       where id = r.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_url := 'https://' || v_ref || '.supabase.co/functions/v1/' || r.target;
    select net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             -- org_action_executor.params is the per-executor payload TEMPLATE and it existed,
             -- empty, on all 55 rows. Without it the invoker sent {org_task_id, dept_key, title}
             -- to every target and compliance_archive answered 400 unknown_action — found by
             -- execution on the first real sweep, not by reading. params is the base of the body
             -- so a target's contract is declared as data, not coded into the invoker.
             body := coalesce(r.params, '{}'::jsonb) || coalesce(r.request, '{}'::jsonb)
                     || jsonb_build_object('__secret', v_secret),
             timeout_milliseconds := r.timeout_seconds * 1000)
      into v_req;

    update public.action_execution
       set status = 'running', attempts = coalesce(attempts,0) + 1,
           executor = r.target, idempotency_key = v_key,
           started_at = coalesce(started_at, now()),
           response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
             'invoker','dispatched','at',now(),'net_request_id',v_req,'url',v_url,
             'timeout_seconds', r.timeout_seconds, 'attempt', coalesce(r.attempts,0)+1,
             'max_attempts', r.max_attempts)
     where id = r.id;
    v_sent := v_sent + 1;
  end loop;

  return jsonb_build_object('dispatched', v_sent, 'refused', v_refused,
                            'deduplicated', v_skipped, 'ran_at', now());
end $function$;

-- ── phase 2: collect, and assert on a 200 AND on the body ──────────────────────────────────────
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
                 'summary', left(coalesce(v_body,''), 500))
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

revoke execute on function public.fn_action_invoke_dispatch(integer) from public;
revoke execute on function public.fn_action_invoke_dispatch(integer) from anon;
revoke execute on function public.fn_action_invoke_dispatch(integer) from authenticated;
revoke execute on function public.fn_action_invoke_collect() from public;
revoke execute on function public.fn_action_invoke_collect() from anon;
revoke execute on function public.fn_action_invoke_collect() from authenticated;

select cron.schedule('action_invoke_dispatch_5min', '2,7,12,17,22,27,32,37,42,47,52,57 * * * *',
                     $$select public.fn_action_invoke_dispatch(5);$$);
select cron.schedule('action_invoke_collect_5min',  '4,9,14,19,24,29,34,39,44,49,54,59 * * * *',
                     $$select public.fn_action_invoke_collect();$$);
