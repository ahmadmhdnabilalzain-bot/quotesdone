-- The deterministic company-connectivity register.
--
-- WHY THIS EXISTS. The "audit" of the autonomous company was being run by fleets of LLM agents, and
-- LLM agents explore differently every run, so the finding set ROTATED — 114 one pass, 8 the next,
-- never converging. This function replaces that with ONE reproducible instrument: it enumerates every
-- true structural connectivity gap from the estate's own tables, returns the SAME set every run, and
-- so can be driven to zero and then held at zero by CI. A "directionless connection" is now a row
-- this function returns, nothing vaguer.
--
-- Each class is SQL-decidable (the SQL layer cannot see edge-function emitters, so classes that would
-- need that are deliberately out of scope and noted). By-design exceptions are excluded IN the query
-- with a comment naming why, never silently.
--
--   select * from public.fn_company_connectivity_register();      -- 0 rows == fully wired
--
--   node scripts/apply_sql.mjs scripts/sql/company_connectivity_register.sql --apply --ddl

create or replace function public.fn_company_connectivity_register()
returns table (gap_class text, subject text, detail text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  -- A · a live workflow step with a side-effect action_class and no active executor. Nothing can
  -- perform the step; the workflow stalls at it. (Mirror of v_workflow_side_effects_without_executor.)
  select 'step_without_executor',
         w.workflow_key || ' step ' || s.step_no,
         'action_class ' || s.action_class || ' has no active org_action_executor'
    from public.workflow w
    join public.workflow_step s on s.workflow_key = w.workflow_key
    left join public.org_action_executor e on e.action_class = s.action_class and e.active
   where w.active and s.action_class is not null and e.action_class is null

  union all
  -- B · a live workflow step whose actor_role the RUNTIME resolver (fn_org_agent_resolve, the same
  -- function the dispatcher and handoff paths use) cannot resolve to any agent. Excluded: 'owner' and
  -- 'Director' in the generic employee_task workflow — those are CONTEXTUAL roles resolved per task
  -- from the task's own assigned_agent / manager, never global agents, so a null here is correct.
  select distinct 'actor_role_unresolved',
         s.actor_role,
         'used in active workflow steps; fn_org_agent_resolve() returns null'
    from public.workflow_step s
    join public.workflow w on w.workflow_key = s.workflow_key and w.active
   where s.actor_role is not null
     and s.actor_role not in ('owner', 'Director')                       -- contextual (employee_task)
     and public.fn_org_agent_resolve(s.actor_role) is null

  union all
  -- C · an event_type that has ACTUALLY been emitted into company_event but has no active subscriber.
  -- The dispatcher (fn_event_dispatch) delivers only through event_subscription, so such an event
  -- reaches no one. Excluded: 'task.assigned' — task assignment is delivered by the direct
  -- fn_org_task_assign path (the org_task row IS the delivery); a bus subscriber would double-create.
  select distinct 'event_emitted_no_subscriber',
         ce.event_type,
         'emitted into company_event, no active event_subscription — the dispatcher delivers it nowhere'
    from public.company_event ce
   where ce.event_type <> 'task.assigned'
     and not exists (select 1 from public.event_subscription es
                      where es.active and es.event_type = ce.event_type)

  union all
  -- D · an active subscription pointing at an agent that is missing or inactive. The dispatcher joins
  -- company_event -> event_subscription -> org_agents on agent_key (it does NOT run the resolver), so
  -- the event is delivered to a dormant agent and dies there. Repoint to the active successor.
  select 'dead_subscription',
         es.event_type || ' -> ' || es.agent_key,
         case when a.agent_key is null then 'subscriber agent does not exist'
              else 'subscriber agent is inactive' end
    from public.event_subscription es
    left join public.org_agents a on a.agent_key = es.agent_key
   where es.active and (a.agent_key is null or not a.active)

  union all
  -- E · an active rpc executor whose target needs arguments the queue invoker cannot supply AND whose
  -- action_class is actually reachable from a live workflow step. fn_action_invoke_rpc fails any
  -- args>0 target, so a reachable one is a guaranteed runtime failure. (Registry rows for functions
  -- called only directly, never queued from a step, are not gaps and are excluded by the step join.)
  select distinct 'executor_target_needs_args',
         e.action_class || ' -> ' || e.target,
         'rpc target requires ' || (p.pronargs - p.pronargdefaults)::text
           || ' arg(s) with no default; reachable from a live workflow step; the queue invoker cannot call it'
    from public.org_action_executor e
    join pg_proc p on p.proname = e.target and p.pronamespace = 'public'::regnamespace
    join public.workflow_step s on s.action_class = e.action_class
    join public.workflow w on w.workflow_key = s.workflow_key and w.active
   where e.active and e.kind = 'rpc' and (p.pronargs - p.pronargdefaults) > 0

  union all
  -- F · an active workflow whose trigger_event has NO producer, so it can never auto-start. The live
  -- loop starts a workflow only when a company_event.event_type equals a workflow.trigger_event (via
  -- fn_workflow_start_due), so a trigger nothing emits is a workflow that never runs. "Has a producer"
  -- = some db function body contains the event literal (an emitter) OR the event has already occurred
  -- in company_event. Excluded: the declared EXTERNAL-INTAKE events, which arrive from real inbound
  -- traffic (edge functions, sales/contract intake, the CI deploy hook), not an internal db producer —
  -- they are wired at the edge layer and fire when that traffic is real, not a structural gap.
  select 'workflow_trigger_has_no_producer',
         w.workflow_key,
         'trigger_event ' || w.trigger_event || ' is emitted by no db function, has never occurred, and '
           || 'is not a declared external-intake event — the workflow can never auto-start'
    from public.workflow w
   where w.active and w.trigger_event is not null
     and not exists (select 1 from public.company_event ce where ce.event_type = w.trigger_event)
     and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.prosrc like '%''' || w.trigger_event || '''%')
     and w.trigger_event not in (
       'inquiry.created',    -- marketplace edge (supplier_portal / customer intake)
       'rfq.created',        -- marketplace edge function
       'quote.received',     -- marketplace edge function
       'lead.qualified',     -- inbound sales-lead intake (no internal producer until a sales surface exists)
       'contract.submitted', -- third-party contract intake (arrives from counterparties)
       'deploy.completed'    -- CI / deploy hook
     )
$function$;

revoke execute on function public.fn_company_connectivity_register() from public;
