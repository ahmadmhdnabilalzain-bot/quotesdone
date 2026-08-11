-- THE PROCESS DID NOT ACCUMULATE: STEP THREE NEVER SAW WHAT STEP TWO CONCLUDED.
--
-- The employee-side dispatcher shipped earlier tonight works. It also had a defect I put in it, and
-- it is this codebase's recurring root cause wearing a new hat: something complete and correct is
-- produced and addressed to nobody.
--
-- MEASURED 2026-08-11, on the sixteen steps the dispatcher had delivered:
--
--   Each step's deliverable is 3,700-4,700 characters of real analysis by a named employee, stored
--   in workflow_step_run.output. Routines that READ that column: fn_workflow_step_claim (writes it),
--   fn_workflow_step_done (writes it), fn_agent_context (reads input->>'step' only, never output).
--   fn_ws_company_os COUNTS rows per day. So nothing anywhere reads a deliverable.
--
-- The visibility half of that is bad. The other half is worse and is a CORRECTNESS defect: the
-- dispatcher passed each employee the run's trigger context and nothing else, so on
-- metric_lifecycle run 1, forecast_analyst answered step 3 - "Measure on cadence and record the
-- actual" - without being shown what intel_director had just concluded in step 2, "Instrument it
-- with a measure that runs". Six independent essays about the same metric is not a process. A
-- process accumulates.
--
-- The fix is at the claim, so it applies to every caller of the queue rather than to the one edge
-- function I happen to have written. The three most recent finished steps of the same run travel
-- with the claim, newest last, each carrying who did it, what the step was, and the OUTCOME line
-- they closed on - not the full 4,000-character body, because the next employee needs the
-- conclusion, not the essay, and the prompt has a budget.
--
-- Steps that were SKIPPED are excluded. An employee_task run's skipped steps carry
-- "never separately observed" as their note, and feeding that to the next employee as if it were a
-- finding would be handing it a fabrication in its own context window.

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
           'context',      r.context,
           -- WHAT THIS RUN HAS ALREADY CONCLUDED. See the header: without this the process does not
           -- accumulate. Skipped steps are excluded on purpose - their note says the work was never
           -- separately observed, and passing that on as a finding would be a fabrication.
           'prior_steps', (select coalesce(jsonb_agg(jsonb_build_object(
                                    'step_no', p.step_no,
                                    'step',    p.input->>'step',
                                    'by',      coalesce(p.output->>'employee', p.actor),
                                    'outcome', left(coalesce(p.output->>'outcome',
                                                             p.output->>'note', ''), 600))
                                  order by p.step_no), '[]'::jsonb)
                             from (select p2.* from public.workflow_step_run p2
                                    where p2.workflow_run_id = c.workflow_run_id
                                      and p2.step_no < c.step_no
                                      and p2.status = 'done'
                                      and coalesce(p2.output->>'outcome', p2.output->>'note','') <> ''
                                    order by p2.step_no desc
                                    limit 3) p)
         ) order by c.id), '[]'::jsonb)
    into v_out
    from claimed c
    join public.workflow_run r on r.id = c.workflow_run_id
    left join public.workflow w on w.workflow_key = r.workflow_key;

  return v_out;
end
$function$;
REVOKE ALL ON FUNCTION public.fn_workflow_step_claim(integer) FROM PUBLIC;
