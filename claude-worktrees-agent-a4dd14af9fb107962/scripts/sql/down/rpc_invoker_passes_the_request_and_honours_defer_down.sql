-- Down for rpc_invoker_passes_the_request_and_honours_defer.sql: restores fn_action_invoke_rpc as it ran on production on 4 Sep 2026.
begin;
CREATE OR REPLACE FUNCTION public.fn_action_invoke_rpc(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_ran int := 0; v_refused int := 0; v_skipped int := 0; v_failed int := 0;
        v_key text; v_res jsonb; v_missing boolean; v_required int;
begin
  for r in
    select a.id, a.action_class, a.request, a.idempotency_key, a.attempts,
           e.target, e.active, e.risk_tier, e.advisory_safe, e.reversible,
           e.required_authority, e.compensation_action_class, e.idempotency_strategy,
           e.notifies_human, e.unattended_ok
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
     where a.status = 'queued' and e.kind = 'rpc'
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
    -- function and a function needing arguments we do not have are different failures and are
    -- reported as different reasons.
    select (p.oid is null), coalesce(p.pronargs - p.pronargdefaults, -1)
      into v_missing, v_required
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

    if v_required > 0 then
      update public.action_execution
         set status = 'failed', finished_at = now(), attempts = coalesce(attempts,0) + 1,
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','failed','at',now(),'kind','rpc',
               'error', format('public.%s() requires %s argument(s) with no default, and a workflow step carries none to give it. Supply them through org_action_executor.params, or give the function defaults - do not let the invoker invent them.',
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
    -- the others in this sweep.
    begin
      execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I() t', r.target)
        into v_res;
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
                            'failed', v_failed, 'ran_at', now());
end $function$
;
commit;
