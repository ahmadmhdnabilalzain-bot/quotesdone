-- AN EVENTLESS WORKFLOW START HAD NO CORRELATION, AND THE COLUMN FORBIDS IT (4 Sep 2026).
--
-- fn_workflow_start reads correlation_id from the triggering company_event. Called with no event --
-- which is how MASTER_PLAN 4.3's promoter lifts a backlog org_task onto the spine -- the read found
-- nothing, v_corr stayed null, and the insert raised 23502 against workflow_run.correlation_id every
-- single time. The statement immediately above it already handles the eventless case by minting a
-- fresh idempotency key, so this was one missing coalesce, not a missing intention.
--
-- Two swallowed errors hid it: fn_org_task_promote catches every promotion failure with
-- `exception when others then null`, and its own callers catch its 42703. The lane reported itself
-- healthy while its promotion leg had never inserted a row. Measured before the fix: 0 of 301
-- employee_task runs carry context->>'promoted_by' = 'fn_org_task_promote'; the promoter returned
-- {"promoted": 0, "room": 3, "backlog_without_a_run": 654}.
--
-- Every other line is the live definition, unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/an_eventless_start_begins_its_own_correlation.sql --apply --ddl
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
  -- 4 SEP 2026: a run started WITHOUT a triggering event begins its own correlation.
  -- The line above finds nothing when p_trigger_event_id is null, workflow_run.correlation_id is
  -- NOT NULL, and the insert below therefore raised 23502 on every eventless start. The line before
  -- it already anticipates exactly this case -- it mints a fresh idempotency key rather than
  -- colliding -- so the omission was in the next statement, not in the design.
  --
  -- It is the reason MASTER_PLAN 4.3's one-spine design never ran: fn_org_task_promote is the leg
  -- that lifts an org_task onto the workflow spine, it calls this with a null event because a
  -- backlog task has no event, every call raised, and the promoter's own
  -- `exception when others then null` swallowed it. Measured: 0 of 301 employee_task runs ever
  -- created carry promoted_by = fn_org_task_promote, and the raise reproduces on any backlog task.
  -- Correlation ties together work that shares a cause; a promoted task IS its own cause.
  v_corr := coalesce(v_corr, gen_random_uuid());

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
end $function$
