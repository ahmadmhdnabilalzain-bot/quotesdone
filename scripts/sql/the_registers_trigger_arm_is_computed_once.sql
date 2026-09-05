-- THE REGISTER'S TRIGGER-CONSUMER ARM IS COMPUTED ONCE (6 Sep 2026).
--
-- On 5 Sep class C learned that a trigger on company_event is a named consumer. That first version
-- correlated a LIKE over every trigger body per company_event ROW. The register went from seconds
-- to past the cron statement_timeout, and the red-view alerter's 21:22 UTC tick -- which calls the
-- register on every sweep -- failed with "canceling statement due to statement timeout". The
-- errored-run ledger caught it. The arm is now a membership test against trigger_consumed, a CTE
-- computed once over the DISTINCT event types (a handful of trigger bodies against ~40 strings).
-- Same truth, measured in seconds again. Every other line is the live definition.
--
--   node scripts/apply_sql.mjs scripts/sql/the_registers_trigger_arm_is_computed_once.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_company_connectivity_register()
 RETURNS TABLE(gap_class text, subject text, detail text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with external_intake(event_type) as (values
       ('inquiry.created'),    -- marketplace edge (supplier_portal / customer intake)
       ('rfq.created'),        -- marketplace edge function
       ('quote.received'),     -- marketplace edge function
       ('lead.qualified'),     -- inbound sales-lead intake (no internal producer until a sales surface exists)
       ('contract.submitted'), -- third-party contract intake (arrives from counterparties)
       ('deploy.completed')    -- CI / deploy hook (scripts/deploy_functions.mjs)
  ),
  -- Event types a non-dispatcher trigger on company_event consumes: a few trigger bodies against
  -- the distinct types, not against every event row.
  trigger_consumed(event_type) as (
    select distinct et.event_type
      from (select distinct ce.event_type from public.company_event ce) et
      join (select p.prosrc from pg_trigger t
              join pg_class c on c.oid = t.tgrelid
              join pg_namespace n on n.oid = c.relnamespace
              join pg_proc p on p.oid = t.tgfoid
             where n.nspname = 'public' and c.relname = 'company_event'
               and not t.tgisinternal and t.tgenabled <> 'D'
               and p.proname <> 'trg_company_event_dispatch') tf
        on tf.prosrc like '%' || et.event_type || '%'
  ),
  -- Every event type some database code can emit: a literal in a routine body, or a literal
  -- argument on a trigger (fn_emit_event reads the type from tg_argv, so the body never names it).
  producer(event_type) as (
    select distinct e.event_type
      from (select distinct ce.event_type from public.company_event ce
            union select es.event_type from public.event_subscription es
            union select w.trigger_event from public.workflow w where w.trigger_event is not null) e
     where exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.prosrc like '%''' || e.event_type || '''%')
        or exists (select 1 from pg_trigger t
                    where not t.tgisinternal
                      and pg_get_triggerdef(t.oid) like '%''' || e.event_type || '''%')
  )
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
  -- Excluded since 4 Sep 2026: a RETIRED type — history in company_event, no producer left in the
  -- catalogue, not an external-intake type — because nothing can emit it again. Re-add an emitter
  -- and the row returns.
  select distinct 'event_emitted_no_subscriber',
         ce.event_type,
         'emitted into company_event, no active event_subscription — the dispatcher delivers it nowhere'
    from public.company_event ce
   where ce.event_type <> 'task.assigned'
     and not exists (select 1 from public.event_subscription es
                      where es.active and es.event_type = ce.event_type)
     -- 5 SEP 2026: a consumer is also a TRIGGER on company_event -- one that is not the generic
     -- dispatcher and whose function body names the event type (MASTER_PLAN 4.4 routes
     -- priority.updated to trg_priority_backlog_reorder, a named consumer with no subscription).
     -- 6 SEP 2026: computed ONCE in the trigger_consumed CTE. The first version correlated a
     -- LIKE over every trigger body per company_event row; the register went from seconds to
     -- past the cron's 120s statement_timeout and the red-view alerter's 21:22Z tick failed.
     and not exists (select 1 from trigger_consumed tc where tc.event_type = ce.event_type)
     and (exists (select 1 from producer p where p.event_type = ce.event_type)
          or exists (select 1 from external_intake x where x.event_type = ce.event_type))

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
     -- 5 SEP 2026: the invoker now supplies ONE argument -- a single jsonb parameter receives
     -- params || request || {action_execution_id} (fn_action_invoke_rpc, the change_deployment
     -- packet). A target whose only required argument is that one jsonb is callable, and three
     -- such targets (change_deploy_baseline/promote/grade -> fn_change_deployment_execute) were
     -- read as gaps by the old rule and paged the founder on 5 Sep. Any other required argument
     -- is still a gap the invoker cannot fill.
     and not ((p.pronargs - p.pronargdefaults) = 1 and p.pronargs = 1
              and p.proargtypes[0] = 'jsonb'::regtype)

  union all
  -- F · an active workflow whose trigger_event has NO producer, so it can never auto-start. The live
  -- loop starts a workflow only when a company_event.event_type equals a workflow.trigger_event (via
  -- fn_workflow_start_due), so a trigger nothing emits is a workflow that never runs. "Has a producer"
  -- = some db function body or trigger argument contains the event literal (an emitter) OR the event
  -- has already occurred in company_event. Excluded: the declared EXTERNAL-INTAKE events, which arrive
  -- from real inbound traffic (edge functions, sales/contract intake, the CI deploy hook), not an
  -- internal db producer — they are wired at the edge layer and fire when that traffic is real.
  select 'workflow_trigger_has_no_producer',
         w.workflow_key,
         'trigger_event ' || w.trigger_event || ' is emitted by no db function or trigger, has never occurred, and '
           || 'is not a declared external-intake event — the workflow can never auto-start'
    from public.workflow w
   where w.active and w.trigger_event is not null
     and not exists (select 1 from public.company_event ce where ce.event_type = w.trigger_event)
     and not exists (select 1 from producer p where p.event_type = w.trigger_event)
     and not exists (select 1 from external_intake x where x.event_type = w.trigger_event)

  union all
  -- G · an active subscription to an event type NOTHING can emit: no routine body names it, no
  -- trigger argument names it, it has never occurred, and it is not a declared external-intake event.
  -- The dispatcher would wait for it forever (MASTER_PLAN §5.1 "phantom subscriptions").
  select distinct 'subscription_without_producer',
         es.event_type || ' -> ' || es.agent_key,
         'active subscription; no db function or trigger emits this event type, it has never occurred, '
           || 'and it is not a declared external-intake event'
    from public.event_subscription es
   where es.active
     and not exists (select 1 from public.company_event ce where ce.event_type = es.event_type)
     and not exists (select 1 from producer p where p.event_type = es.event_type)
     and not exists (select 1 from external_intake x where x.event_type = es.event_type)
$function$
