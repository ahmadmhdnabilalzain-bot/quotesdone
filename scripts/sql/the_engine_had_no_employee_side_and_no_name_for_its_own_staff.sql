-- THE WORKFLOW ENGINE HAD NO EMPLOYEE SIDE, AND NO NAME FOR ITS OWN STAFF.
--
-- fn_workflow_step_sweep (#218) queues a ready step only for a registered low-risk reversible EDGE
-- executor that does not notify a human. Everything else parks forever. Measured on production
-- 2026-08-11 21:30 UTC: 195 workflow_run rows running, 5 done, 7 failed; 195 ready steps and ZERO
-- executable. This file builds the other half - the side that routes a step to the EMPLOYEE who
-- owns it - and fixes the identity vocabulary that made "the employee who owns it" unanswerable.
--
--
-- 1. THE FIFTH VOCABULARY, IN FULL
--
-- workflow_step.actor_role holds 66 distinct values and they are not one namespace. They are
-- agent_keys (intel_director, cpo, brief), job TITLES (Compliance Manager, Fraud & Risk Analyst,
-- Chief of Staff), and run-relative POSITIONS (owner, Director). The same employee appears twice
-- under two spellings - compliance_mgr AND Compliance Manager, brand_mgr AND Brand Manager,
-- qa_manager AND Quality Assurance Manager, financial_analyst AND Financial Analyst,
-- risk_governance_mgr AND Risk & Governance Manager. fn_org_agent_resolve knew the first spelling
-- of each pair and none of the second, so half the org chart was unaddressable from a workflow.
--
-- Fixed where the memory says to fix it: at the resolver and at the WRITE boundary, never by
-- widening a reader's join. fn_workflow_start now resolves actor_role as it plans the run and keeps
-- the raw string in input.addressed_as, so nothing is silently reassigned and the original wording
-- survives for audit. An actor that still does not resolve is left RAW and the dispatcher reports
-- it rather than guessing.
--
--
-- 2. WHAT THE MEASUREMENT CHANGED ABOUT THE PLAN
--
-- The session brief proposed landing dispatched steps in org_tasks. Two measurements say no.
--
--   (a) 124 of the 195 ready steps are workflow_key='employee_task', actor 'owner'. Their runs are
--       started BY org_tasks: workflow.trigger_event for employee_task is 'task.assigned', live.
--       An org_tasks row created per step would emit the event that starts another 17-step run.
--       124 runs x 17 steps = 2,108 tasks on the first pass. That is a fork bomb, not a dispatcher.
--
--   (b) Of those 124 runs, 96 own an org_task that is ALREADY 'done' and 28 one 'in_progress'.
--       Zero are orphaned. The work was performed - by cos_execute, through fn_task_review's
--       department-head + Chief-of-Staff + cross-department chain - and the workflow_run recording
--       it was never told. Dispatching them would commission work the company has already finished.
--
-- So employee_task is not dispatched. It FOLLOWS ITS OWN TASK, below. The remaining 71 steps are
-- dispatched to their employee, and 71 is exactly the count the brief predicted.
--
--
-- 3. WHY THE OTHER 71 ARE PARKED, WHICH IS TWO DIFFERENT REASONS
--
--   44  intel_director / health_report   - executor ai_health has notifies_human = true, so the
--                                          sweep is RIGHT to refuse it. The step is "Instrument it
--                                          with a measure that runs" / "Evidence: KPI scoreboard":
--                                          employee work, not a cron that emails the founder.
--   19  kb_engineer, knowledge_director / knowledge_fill - executor is kind='rpc'; the sweep takes
--                                          kind='edge' only.
--    8  Customer Support Specialist       - a TITLE, and no action_class at all.
--
-- None of these is an executor defect. They are steps that belong to a person.

-- ---------------------------------------------------------------------------------------------
-- A. THE RESOLVER LEARNS JOB TITLES.
-- Order is most-specific-first: exact active key, curated alias, exact job title, department head.
-- CREATE OR REPLACE preserves the existing ACL, so this one is deliberately NOT revoked again.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_org_agent_resolve(p_addressee text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select o.agent_key from public.org_agents o
      where o.agent_key = p_addressee and o.active),
    (select a.agent_key from public.org_agent_alias a
       join public.org_agents o on o.agent_key = a.agent_key and o.active
      where a.alias = p_addressee),
    -- THE TITLE ARM (11 Aug 2026). 30 of the 66 workflow actor_role values are job titles, and
    -- five of them are a second spelling of an employee the alias table already knew by key.
    -- Ordered so a title held by more than one employee resolves to the senior holder rather than
    -- to whichever row the planner returned first.
    (select o.agent_key from public.org_agents o
      where lower(btrim(o.title)) = lower(btrim(p_addressee)) and o.active
      order by case o.seniority
                 when 'executive' then 0 when 'chief' then 1 when 'director' then 2
                 when 'lead'      then 3 when 'manager' then 4 when 'senior' then 5 else 6 end,
               o.agent_key
      limit 1),
    (select o.agent_key from public.org_agents o
      where o.department = p_addressee and o.active
      order by case o.seniority
                 when 'executive' then 0 when 'chief' then 1 when 'director' then 2
                 when 'lead'      then 3 when 'manager' then 4 when 'senior' then 5 else 6 end,
               o.agent_key
      limit 1)
  );
$function$;

-- ---------------------------------------------------------------------------------------------
-- B. 'owner' AND 'Director' ARE POSITIONS IN A RUN, NOT IDENTITIES.
-- No global table can answer them: the owner of run X is whoever run X's work belongs to. This is
-- the per-run arm, and it delegates everything else to the global resolver above.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_workflow_actor_resolve(p_run uuid, p_actor text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ctx jsonb; v_owner text; v_live text; v_tid bigint;
begin
  if p_actor is null or btrim(p_actor) = '' then return null; end if;

  if lower(btrim(p_actor)) not in ('owner', 'director', 'dept_head', 'department head') then
    return public.fn_org_agent_resolve(p_actor);
  end if;

  select r.context into v_ctx from public.workflow_run r where r.id = p_run;
  if v_ctx is null then return null; end if;

  -- The owner is the assignee of the task this run was raised for. employee_task runs carry
  -- context.task_id; the guard on the cast is there because context is free-form jsonb and a
  -- non-numeric task_id would abort the whole planning statement rather than skip one step.
  if coalesce(v_ctx->>'task_id','') ~ '^[0-9]+$' then
    v_tid := (v_ctx->>'task_id')::bigint;
    select t.assigned_agent into v_owner from public.org_tasks t where t.id = v_tid;
  end if;
  if v_owner is null then v_owner := nullif(v_ctx->>'agent',''); end if;
  if v_owner is null then v_owner := public.fn_org_agent_resolve(nullif(v_ctx->>'dept_key','')); end if;

  select o.agent_key into v_live from public.org_agents o where o.agent_key = v_owner and o.active;
  if v_live is null then return null; end if;

  if lower(btrim(p_actor)) = 'owner' then return v_live; end if;

  -- 'Director' on employee_task step 10 is "department head review" - the owner's own manager,
  -- which org_agents.manager_key already models for 93 of 94 employees, acyclically.
  return (select m.agent_key
            from public.org_agents o
            join public.org_agents m on m.agent_key = o.manager_key and m.active
           where o.agent_key = v_live);
end
$function$;
REVOKE ALL ON FUNCTION public.fn_workflow_actor_resolve(uuid, text) FROM PUBLIC;

-- ---------------------------------------------------------------------------------------------
-- C. RESOLVE AT THE WRITE BOUNDARY, NOT IN THE READER.
-- Only the planning INSERT changes. The raw actor_role is preserved in input.addressed_as whenever
-- resolution moved it, and an unresolvable actor is written through untouched.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_workflow_start(p_workflow_key text, p_trigger_event_id bigint DEFAULT NULL::bigint, p_entity_type text DEFAULT NULL::text, p_entity_id text DEFAULT NULL::text, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run uuid; v_key text; v_corr uuid; v_first int;
begin
  if not exists (select 1 from workflow w where w.workflow_key = p_workflow_key and coalesce(w.active,true))
    then return null; end if;

  -- One run per (workflow, triggering event). Without the event there is nothing to be idempotent
  -- against, so a manual start gets its own key rather than silently colliding with the last one.
  v_key := p_workflow_key || ':' || coalesce(p_trigger_event_id::text, gen_random_uuid()::text);

  select e.correlation_id into v_corr from company_event e where e.id = p_trigger_event_id;

  insert into workflow_run (workflow_key, trigger_event_id, correlation_id, entity_type, entity_id,
                            idempotency_key, status, current_step, context, started_at)
  values (p_workflow_key, p_trigger_event_id, v_corr, p_entity_type, p_entity_id,
          v_key, 'running', 0, coalesce(p_context,'{}'::jsonb), now())
  on conflict (idempotency_key) do nothing
  returning id into v_run;

  if v_run is null then
    select id into v_run from workflow_run where idempotency_key = v_key;
    return v_run;                      -- already started; nothing to re-plan
  end if;

  -- Plan every step of the workflow up front. A run whose steps are only materialised as they are
  -- reached cannot be read as "where is this piece of work", which is the entire value of the table.
  --
  -- THE ACTOR IS RESOLVED HERE (11 Aug 2026). It used to copy workflow_step.actor_role verbatim,
  -- and actor_role is not one namespace - see the header. Resolving in the dispatcher instead
  -- would leave the stored row still addressed to nobody, which is the defect this codebase keeps
  -- reproducing. addressed_as keeps the original wording so no reassignment is silent.
  insert into workflow_step_run (workflow_run_id, step_no, actor, action_class, status,
                                 input, idempotency_key)
  select v_run, s.step_no, coalesce(x.resolved, s.actor_role), s.action_class, 'queued',
         jsonb_build_object('step', s.step, 'gate', s.gate)
           || case when x.resolved is not null and x.resolved is distinct from s.actor_role
                   then jsonb_build_object('addressed_as', s.actor_role)
                   else '{}'::jsonb end,
         v_key || '#' || s.step_no
    from workflow_step s
    cross join lateral (select public.fn_workflow_actor_resolve(v_run, s.actor_role) as resolved) x
   where s.workflow_key = p_workflow_key
   order by s.step_no
  on conflict (idempotency_key) do nothing;

  select min(step_no) into v_first from workflow_step_run where workflow_run_id = v_run;
  if v_first is null then
    -- A workflow with no steps cannot be in flight. Closing it here stops it sitting in the
    -- in-flight list forever pretending to be work.
    update workflow_run set status = 'done', finished_at = now(), updated_at = now()
     where id = v_run;
    return v_run;
  end if;

  update workflow_step_run set status = 'ready', started_at = now()
   where workflow_run_id = v_run and step_no = v_first;
  update workflow_run set current_step = v_first, updated_at = now() where id = v_run;
  return v_run;
end $function$;

-- ---------------------------------------------------------------------------------------------
-- D. AN employee_task RUN FOLLOWS THE TASK IT WAS RAISED FOR.
--
-- This is the honest close, and it is deliberately NOT "mark 17 steps done". The company performs
-- the employee task loop as ONE act inside cos_execute/agent_brain and reviews it once through
-- fn_task_review. It does not observe 17 separate steps, so it may not claim 17. Unfinished steps
-- are closed 'skipped' carrying the org_task id and status that closed them; the RUN takes the
-- task's own outcome, because that outcome is a reviewed fact and not an inference.
--
-- A trigger, not a patch to a writer: fourteen routines write org_tasks and the fifteenth would
-- otherwise be free to close a task without telling the workflow again.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_workflow_run_follow_task()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run uuid;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status not in ('done','failed','escalated') then return new; end if;

  for v_run in
    select r.id from public.workflow_run r
     where r.workflow_key = 'employee_task'
       and r.status = 'running'
       and (r.context->>'task_id') = new.id::text
  loop
    update public.workflow_step_run
       set status = 'skipped', finished_at = now(),
           output = coalesce(output, '{}'::jsonb) || jsonb_build_object(
             'closed_by', 'owning_org_task', 'org_task_id', new.id,
             'org_task_status', new.status,
             'note', 'the owning task was performed and reviewed as one act; this step was never '
                     || 'separately observed, so it is skipped rather than claimed as done')
     where workflow_run_id = v_run and finished_at is null;

    update public.workflow_run
       set status      = case when new.status = 'done' then 'done' else 'failed' end,
           finished_at = now(),
           updated_at  = now(),
           context     = coalesce(context,'{}'::jsonb)
                         || jsonb_build_object('closed_by','owning_org_task',
                                               'org_task_status', new.status),
           error       = case when new.status = 'done' then null
                              else jsonb_build_object('owning_org_task', new.id,
                                                      'org_task_status', new.status) end
     where id = v_run;
  end loop;
  return new;
end
$function$;
REVOKE ALL ON FUNCTION public.fn_workflow_run_follow_task() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_workflow_run_follow_task ON public.org_tasks;
CREATE TRIGGER trg_workflow_run_follow_task
  AFTER UPDATE OF status ON public.org_tasks
  FOR EACH ROW EXECUTE FUNCTION public.fn_workflow_run_follow_task();

-- ---------------------------------------------------------------------------------------------
-- E. THE EMPLOYEE-SIDE CLAIM.
--
-- The executor-side sweep's opposite number. It hands the dispatcher a bounded batch of ready
-- steps that resolve to a live employee, marking them 'running' in the same statement so two
-- concurrent invocations cannot both work the same step.
--
-- WHAT IT REFUSES, AND WHY EACH ONE:
--   employee_task    - follows its own org_task (D). Dispatching it would commission finished work
--                      and, via trigger_event 'task.assigned', start another run per step.
--   gate = 'founder' - the four absolute gates: Stripe refund, invoice payment, campaign publish,
--                      complaint remedy. No agent may pass these and nothing here tries.
--   a step a real executor can run - left to fn_workflow_step_sweep. The two halves must not race
--                      for the same row, and a genuine side effect beats an advisory note.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_workflow_step_claim(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_out jsonb;
begin
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
       set status = 'running', started_at = coalesce(sr.started_at, now())
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

-- ---------------------------------------------------------------------------------------------
-- F. WHAT IS STILL ADDRESSED TO NOBODY, SAID OUT LOUD.
-- An actor that resolves to no live employee is the defect this file exists to remove, so it gets
-- a reader rather than being left for the next session to rediscover by grep.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_workflow_actor_coverage()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'catalogue_actor_roles',  (select count(distinct actor_role) from public.workflow_step),
    'catalogue_unresolved',   (select count(*) from (
                                 select distinct actor_role a from public.workflow_step) t
                                where t.a is not null
                                  and public.fn_org_agent_resolve(t.a) is null
                                  and lower(btrim(t.a)) not in ('owner','director','dept_head')),
    'catalogue_unresolved_names', (select coalesce(jsonb_agg(t.a order by t.a),'[]'::jsonb) from (
                                 select distinct actor_role a from public.workflow_step) t
                                where t.a is not null
                                  and public.fn_org_agent_resolve(t.a) is null
                                  and lower(btrim(t.a)) not in ('owner','director','dept_head')),
    'live_steps_unresolved',  (select count(*) from public.workflow_step_run sr
                                where sr.finished_at is null
                                  and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is null),
    'ready_dispatchable',     (select count(*) from public.workflow_step_run sr
                                join public.workflow_run r on r.id = sr.workflow_run_id
                               where sr.status='ready' and sr.finished_at is null and r.status='running'
                                 and r.workflow_key <> 'employee_task'
                                 and coalesce(sr.input->>'gate','') <> 'founder'
                                 and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null),
    'measured_at', now());
$function$;
REVOKE ALL ON FUNCTION public.fn_workflow_actor_coverage() FROM PUBLIC;

-- ---------------------------------------------------------------------------------------------
-- G. BACKFILL — the rows written before the resolver knew any of this.
-- Unfinished steps only: a finished step is a historical record and is not re-addressed.
-- ---------------------------------------------------------------------------------------------
UPDATE public.workflow_step_run sr
   SET actor = x.resolved,
       input = coalesce(sr.input,'{}'::jsonb) || jsonb_build_object('addressed_as', sr.actor)
  FROM (select sr2.id, public.fn_workflow_actor_resolve(sr2.workflow_run_id, sr2.actor) as resolved
          from public.workflow_step_run sr2
         where sr2.finished_at is null) x
 WHERE sr.id = x.id
   AND x.resolved is not null
   AND x.resolved is distinct from sr.actor
   AND NOT (coalesce(sr.input,'{}'::jsonb) ? 'addressed_as');

-- The 124 employee_task runs whose task closed while nothing was listening. Same shape as the
-- trigger in D, applied once to the rows that predate it.
WITH shut AS (
  SELECT r.id AS run_id, t.id AS task_id, t.status AS task_status
    FROM public.workflow_run r
    JOIN public.org_tasks t ON t.id = nullif(r.context->>'task_id','')::bigint
   WHERE r.workflow_key = 'employee_task'
     AND r.status = 'running'
     AND t.status IN ('done','failed','escalated')
), steps AS (
  -- A data-modifying CTE runs to completion whether or not the outer query reads it, so this
  -- closes every unfinished step of every run in `shut` without being referenced below.
  UPDATE public.workflow_step_run sr
     SET status = 'skipped', finished_at = now(),
         output = coalesce(sr.output,'{}'::jsonb) || jsonb_build_object(
           'closed_by','owning_org_task','org_task_id', shut.task_id,
           'org_task_status', shut.task_status,
           'note','the owning task was performed and reviewed as one act; this step was never '
                  || 'separately observed, so it is skipped rather than claimed as done')
    FROM shut
   WHERE sr.workflow_run_id = shut.run_id AND sr.finished_at is null
  RETURNING sr.id
)
UPDATE public.workflow_run r
   SET status      = case when shut.task_status = 'done' then 'done' else 'failed' end,
       finished_at = now(), updated_at = now(),
       context     = coalesce(r.context,'{}'::jsonb)
                     || jsonb_build_object('closed_by','owning_org_task',
                                           'org_task_status', shut.task_status),
       error       = case when shut.task_status = 'done' then null
                          else jsonb_build_object('owning_org_task', shut.task_id,
                                                  'org_task_status', shut.task_status) end
  FROM shut
 WHERE r.id = shut.run_id;
