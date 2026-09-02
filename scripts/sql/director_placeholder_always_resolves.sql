-- Make the employee_task 'Director' (department-head) placeholder always resolve. fn_workflow_start
-- binds 'owner' -> the task's assignee and 'Director' -> the owner's active manager before queuing
-- each step; trg_step_run_actor_is_a_real_employee refuses an unresolved placeholder. The owner's
-- manager was null for exactly one active agent -- the ceo, the top of the org -- so any task owned by
-- (or resolving to) the ceo raised "actor \"Director\" resolves to no employee" and stalled the whole
-- employee_task run. Root fix: the top of the org is its own department head (coalesce to the owner).
-- Surfaced by re-enabling the company-loop start cron and probing fn_workflow_start_due.
--
--   node scripts/apply_sql.mjs scripts/sql/director_placeholder_always_resolves.sql --apply --ddl

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
  -- The owner's active manager is the department head. If the owner has no active manager (only the
  -- ceo, the top of the org), the owner is its own department head, so 'Director' never resolves to
  -- no employee and never stalls a run at step 10.
  return coalesce(
    (select m.agent_key
       from public.org_agents o
       join public.org_agents m on m.agent_key = o.manager_key and m.active
      where o.agent_key = v_live),
    v_live);
end
$function$
;
