-- THE RPC INVOKER NOW HANDS THE EXECUTOR ITS REQUEST, AND LETS IT DEFER (MASTER_PLAN A1 / §4.2), 5 Sep 2026.
--
-- MEASURED before this file: fn_action_invoke_rpc called every rpc target as public.<target>() with NO
-- arguments, and its own error text told the operator to "supply them through org_action_executor.params"
-- — which it never read either. The edge invoker posts params || request to the function; the rpc invoker
-- gave a SQL executor nothing, so an rpc executor could not know which workflow step it was serving, and
-- every one of the 19 rpc-executed workflow steps runs a routine that ignores its step (fn_emit_metric_alerts,
-- fn_self_review, fn_org_exec_knowledge_fill ...). A change_deployment executor that must read THIS run's
-- deploy.completed payload cannot be built on that contract.
--
-- TWO ADDITIONS, nothing removed:
--   1. A target whose signature is exactly one jsonb parameter receives params || request ||
--      {action_execution_id}. Zero-argument targets are called exactly as before.
--   2. A target may DEFER by returning a row carrying `defer_until` (timestamptz) and `reason`. The row is
--      left 'queued' with request.not_before set and response.invoker='deferred'; the invoker skips it until
--      not_before has passed. Nothing else in the kernel changes: the step stays 'running' with a queued
--      execution, so fn_workflow_step_claim's 15-minute reset does not fire and the dispatcher cannot take
--      it. A monitor step ("grade the outcome against the baseline") needs a window to elapse after the
--      deploy; before this the invoker marked every call 'succeeded' unconditionally, so the only options
--      were a fake close over a 4-minute window or a raise that failed the whole run.
--
-- Down: scripts/sql/down/rpc_invoker_passes_the_request_and_honours_defer_down.sql (restores the 4 Sep body).
--
--   node scripts/apply_sql.mjs scripts/sql/rpc_invoker_passes_the_request_and_honours_defer.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_action_invoke_rpc(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_ran int := 0; v_refused int := 0; v_skipped int := 0; v_failed int := 0; v_deferred int := 0;
        v_key text; v_res jsonb; v_missing boolean; v_required int; v_takes_jsonb boolean; v_arg jsonb;
begin
  for r in
    select a.id, a.action_class, a.request, a.idempotency_key, a.attempts,
           e.target, e.active, e.risk_tier, e.advisory_safe, e.reversible,
           e.required_authority, e.compensation_action_class, e.idempotency_strategy,
           e.notifies_human, e.unattended_ok, e.params
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
     where a.status = 'queued' and e.kind = 'rpc'
       -- a deferred execution is not due yet; see (2) in the header
       and coalesce(nullif(a.request->>'not_before','')::timestamptz, now()) <= now()
     order by a.created_at
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    -- THE SAME REFUSALS AS THE EDGE PATH, in the same order and for the same reasons. A SQL
    -- function is not safer than an HTTP call because it is closer to the data; if anything it is
    -- nearer the money. notifies_human is still checked before the risk tier: a message that
    -- should not have been sent cannot be un-sent by a low risk score.
    if not r.active
       or coalesce(r.required_authority,'') = 'founder'
       or (not r.reversible and r.compensation_action_class is null)
       or (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))
       or not (r.risk_tier = 'low' and r.advisory_safe and r.reversible) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','refused','at',now(),'kind','rpc',
               'reason', case
                 when not r.active then 'executor row is inactive'
                 when coalesce(r.required_authority,'') = 'founder' then 'reserved to the founder'
                 when (not r.reversible and r.compensation_action_class is null)
                   then 'not reversible and declares no compensation_action_class'
                 when (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))
                   then 'notifies_human is true and unattended_ok has not been set for this class'
                 else format('risk gate: tier=%s advisory_safe=%s reversible=%s - the invoker runs low/advisory_safe/reversible only',
                             r.risk_tier, r.advisory_safe, r.reversible) end)
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- CAN THIS TARGET ACTUALLY BE CALLED? Asked of pg_proc, not assumed from the table. A missing
    -- function, a function that takes the request as one jsonb, and a function needing arguments we
    -- do not have are three different cases and are reported as three different things.
    select (p.oid is null),
           coalesce(p.pronargs - p.pronargdefaults, -1),
           coalesce(p.pronargs = 1 and p.proargtypes[0] = 'jsonb'::regtype::oid, false)
      into v_missing, v_required, v_takes_jsonb
      from (select 1) _
      left join pg_proc p on p.proname = r.target and p.pronamespace = 'public'::regnamespace;

    if v_missing then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', format('executor target public.%s() does not exist', r.target))
       where id = r.id;
      v_failed := v_failed + 1;
      continue;
    end if;

    if v_required > 0 and not v_takes_jsonb then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', format('public.%s() requires %s argument(s) with no default, and a workflow step carries none to give it. Take the request as ONE jsonb parameter (the invoker passes params || request || {action_execution_id}), or give the function defaults - do not let the invoker invent them.',
                               r.target, v_required))
       where id = r.id;
      v_failed := v_failed + 1;
      continue;
    end if;

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
               'invoker','deduplicated','at',now(),'kind','rpc','idempotency_key',v_key)
       where id = r.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    -- One form for every return shape. A set-returning function yields its rows; a scalar
    -- function in FROM yields exactly one. Wrapped per row so one failing target cannot roll back
    -- the others in this sweep. A jsonb-taking target gets the same body the edge invoker posts.
    begin
      if v_takes_jsonb then
        v_arg := coalesce(r.params, '{}'::jsonb) || coalesce(r.request, '{}'::jsonb)
                 || jsonb_build_object('action_execution_id', r.id);
        execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I($1) t', r.target)
          into v_res using v_arg;
      else
        execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I() t', r.target)
          into v_res;
      end if;

      -- (2) THE TARGET ASKED TO BE CALLED BACK LATER. Left queued and dated; not an attempt.
      if jsonb_typeof(v_res->0) = 'object' and (v_res->0) ? 'defer_until'
         and nullif(v_res->0->>'defer_until','') is not null then
        update public.action_execution
           set executor = r.target, idempotency_key = v_key,
               request = coalesce(request,'{}'::jsonb)
                         || jsonb_build_object('not_before', (v_res->0->>'defer_until')::timestamptz),
               response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','deferred','at',now(),'kind','rpc',
                 'not_before', (v_res->0->>'defer_until')::timestamptz,
                 'defer_reason', left(coalesce(v_res->0->>'reason',''), 500),
                 'deferrals', coalesce((response->>'deferrals')::int, 0) + 1)
         where id = r.id;
        v_deferred := v_deferred + 1;
        continue;
      end if;

      update public.action_execution
         set status = 'succeeded', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             executor = r.target, idempotency_key = v_key,
             started_at = coalesce(started_at, now()),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','succeeded','at',now(),'kind','rpc','result', v_res)
       where id = r.id;
      v_ran := v_ran + 1;
    exception when others then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             executor = r.target,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', replace(coalesce(sqlerrm,'unknown'), '''', ''))
       where id = r.id;
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object('ran', v_ran, 'refused', v_refused, 'deduplicated', v_skipped,
                            'failed', v_failed, 'deferred', v_deferred, 'ran_at', now());
end $function$;

commit;
