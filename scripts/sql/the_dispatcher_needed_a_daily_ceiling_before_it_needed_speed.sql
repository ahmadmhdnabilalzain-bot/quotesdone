-- THE DISPATCHER NEEDED A DAILY CEILING BEFORE IT NEEDED SPEED.
--
-- Routing workflow_dispatch to agent_reasoning fixed the truncation and cost exactly what it should:
-- measured on production 2026-08-11, the same step went from 900 output tokens on haiku at
-- 0.0221 AED to 5,437 on sonnet-5 at 0.2170 AED. Ten times the price for a deliverable that is not
-- cut off mid-sentence, which is the right trade.
--
-- It is the wrong trade UNBOUNDED. At two steps per ten-minute cron that is 288 steps a day, about
-- 62 AED — against a MEASURED whole-company spend of 143.75 AED over the last THIRTY days
-- (fn_cost_per_os(30)). The dispatcher alone would be thirteen times the company's current daily
-- model bill, and fn_spend_concentration_check already filed org_tasks 1309 because 85.4% of that
-- spend goes to the OS that reasons about the company and 0.04% to the one meant to earn the
-- AED 1,000,000. Adding an uncapped internal-reasoning drain points straight the wrong way.
--
-- So the claim carries its own daily ceiling. 24 steps per UTC day is about 5 AED/day: it doubles
-- the company's model spend rather than multiplying it, drains the 71 ready steps in three days,
-- and is a real operating tempo for 19 processes in a company with no customers yet. The number
-- lives here rather than in the edge function on purpose — raising it when demand arrives is one
-- CREATE OR REPLACE, not a deploy, and the reason is next to the number.
--
-- IT COUNTS DELIVERED STEPS, NOT INVOCATIONS. A claim that produced no deliverable was released
-- back to 'ready' and did not spend the day's budget on anything the company kept.

CREATE OR REPLACE FUNCTION public.fn_workflow_step_claim(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_out jsonb; v_today int; v_cap constant int := 24;
begin
  update public.workflow_step_run sr
     set status = 'ready'
   where sr.status = 'running'
     and sr.finished_at is null
     and sr.started_at < now() - interval '15 minutes'
     and not exists (select 1 from public.action_execution x
                      where x.workflow_step_run_id = sr.id
                        and x.status in ('queued','running','succeeded'));

  select count(*) into v_today
    from public.workflow_step_run sr
   where sr.output->>'worked_by' = 'workflow_dispatch'
     and sr.finished_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc';

  if v_today >= v_cap then
    return jsonb_build_object('capped', true, 'worked_today', v_today, 'cap', v_cap,
             'note', 'the daily ceiling is spent; see '
                     || 'scripts/sql/the_dispatcher_needed_a_daily_ceiling_before_it_needed_speed.sql');
  end if;

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
     limit greatest(least(coalesce(p_limit, 5), v_cap - v_today), 1)
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
