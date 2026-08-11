-- Wiring for workflow_dispatch: its two credentials, the release path, the stale reclaim, and cron.
-- Companion to the_engine_had_no_employee_side_and_no_name_for_its_own_staff.sql.

-- 1. OUTBOUND. workflow_dispatch calls a model through _shared/llm.ts, which looks up
--    app_secrets.cred_fn_<fn> and falls back to the shared inbound_secret while logging it.
--    Issuing the scoped credential is what keeps it off that path — same shape as fn.action_worker.
do $$
declare v_issued jsonb; v_secret text;
begin
  if not exists (select 1 from app_secrets where key = 'cred_fn_workflow_dispatch') then
    v_issued := public.fn_internal_credential_issue('fn.workflow_dispatch',
                  array['ai_gateway','workflow_dispatch'],
                  'Outbound credential for workflow_dispatch: it calls ai_gateway and nothing else', null);
    v_secret := coalesce(v_issued->>'secret', v_issued->>'value', v_issued->>'token');
    if v_secret is null then raise exception 'credential issue returned no secret: %', v_issued::text; end if;
    insert into app_secrets(key, value) values ('cred_fn_workflow_dispatch', v_secret)
      on conflict (key) do update set value = excluded.value;
  end if;
end $$;

-- 2. INBOUND. cron presents cred_cron_agents; requireInternal checks that credential's scope
--    against this function's own slug, so the slug has to be in it or the call is refused.
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['workflow_dispatch']) s)
 where context = 'cron.agents' and active and not (scope @> array['workflow_dispatch']);

-- 3. THE RELEASE PATH. fn_workflow_step_claim marks a step 'running' as it hands it over. If the
--    employee produces no usable deliverable the step must go BACK to 'ready', not sit 'running'
--    forever — that is the same invisible parking this whole build exists to end, only harder to
--    see because 'running' reads as progress.
CREATE OR REPLACE FUNCTION public.fn_workflow_step_release(p_step_run_id bigint, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.workflow_step_run
     set status   = 'ready',
         attempts = coalesce(attempts,0) + 1,
         error    = jsonb_build_object('released_at', now(), 'reason', left(coalesce(p_reason,''), 500),
                                       'released_by', 'workflow_dispatch')
   where id = p_step_run_id and status = 'running' and finished_at is null;
  if not found then return 'not held'; end if;
  return 'released';
end
$function$;
REVOKE ALL ON FUNCTION public.fn_workflow_step_release(bigint, text) FROM PUBLIC;

-- 4. THE CLAIM, WITH A RECLAIM IN FRONT OF IT.
--    A step held 'running' for over 15 minutes by a killed invocation is indistinguishable from one
--    being worked, and nothing would ever pick it up again. Same STALE_MIN discipline cos_execute
--    already applies to in_progress org_tasks. The executor side's holds are excluded by name: the
--    sweep also sets 'running' when it queues an action_execution, and that row IS the work in
--    flight.
CREATE OR REPLACE FUNCTION public.fn_workflow_step_claim(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_out jsonb;
begin
  update public.workflow_step_run sr
     set status = 'ready'
   where sr.status = 'running'
     and sr.finished_at is null
     and sr.started_at < now() - interval '15 minutes'
     and not exists (select 1 from public.action_execution x
                      where x.workflow_step_run_id = sr.id
                        and x.status in ('queued','running','succeeded'));

  with pick as (
    select sr.id
      from public.workflow_step_run sr
      join public.workflow_run r on r.id = sr.workflow_run_id
     where sr.status = 'ready'
       and sr.finished_at is null
       and r.status = 'running'
       and r.workflow_key <> 'employee_task'
       and coalesce(sr.input->>'gate','') <> 'founder'
       and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
       and not exists (
             select 1 from public.org_action_executor e
              where e.action_class = sr.action_class and e.active and e.kind = 'edge'
                and e.risk_tier = 'low' and e.advisory_safe and e.reversible
                and not e.notifies_human
                and coalesce(e.required_authority,'') <> 'founder')
     order by sr.id
     limit greatest(coalesce(p_limit, 5), 1)
     for update of sr skip locked
  ), claimed as (
    update public.workflow_step_run sr
       set status = 'running', started_at = now()
      from pick
     where sr.id = pick.id
    returning sr.id, sr.workflow_run_id, sr.step_no, sr.actor, sr.action_class, sr.input
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'step_run_id',  c.id,
           'run_id',       c.workflow_run_id,
           'step_no',      c.step_no,
           'employee',     public.fn_workflow_actor_resolve(c.workflow_run_id, c.actor),
           'addressed_as', coalesce(c.input->>'addressed_as', c.actor),
           'action_class', c.action_class,
           'step',         c.input->>'step',
           'gate',         c.input->>'gate',
           'workflow_key', r.workflow_key,
           'workflow',     w.name,
           'context',      r.context) order by c.id), '[]'::jsonb)
    into v_out
    from claimed c
    join public.workflow_run r on r.id = c.workflow_run_id
    left join public.workflow w on w.workflow_key = r.workflow_key;

  return v_out;
end
$function$;
REVOKE ALL ON FUNCTION public.fn_workflow_step_claim(integer) FROM PUBLIC;

-- 5. CRON. Ten-minutely, offset from workflow_step_sweep_10min (which runs at :06 and every ten
--    after) so the executor half and the employee half do not contend for the same rows.
--
--    THE URL IS BUILT FROM app_secrets.project_ref AT RUN TIME, NOT HARDCODED. This same file is
--    applied byte-identically to both projects; a literal production ref would give staging a cron
--    job that POSTs to production every ten minutes. Four active staging jobs already do exactly
--    that and this one is not going to be the fifth.
select cron.unschedule('workflow_dispatch_10min')
 where exists (select 1 from cron.job where jobname = 'workflow_dispatch_10min');

select cron.schedule('workflow_dispatch_10min', '1,11,21,31,41,51 * * * *', $cron$
  select net.http_post(
    url := 'https://' || (select value from app_secrets where key = 'project_ref')
                      || '.supabase.co/functions/v1/workflow_dispatch',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_agents'),
                               'limit', 2),
    timeout_milliseconds := 150000);
$cron$);
