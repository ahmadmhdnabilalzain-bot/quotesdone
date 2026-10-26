-- THE CONNECTIVITY REGISTER LEARNS THE OTHER DIRECTION (4 Sep 2026, MASTER_PLAN §4.6 / §5.1).
--
-- Class C asked "is every EMITTED event consumed?"; nothing asked "is every SUBSCRIPTION to an
-- event anything can emit?". Measured on production 4 Sep: 38 subscribed types, and the phantom
-- half of that question — regulation.changed ×10, ai.confidence_dropped, invoice.flagged ×2 — was
-- invisible to the register. Class G closes it: an active subscription whose event type has no
-- producer in this database (no routine body naming it, no trigger argument naming it — see
-- an-event-type-passed-as-a-trigger-argument) and that has never occurred, and is not one of the
-- declared external-intake events, is a subscription to nothing.
--
-- Class C also stops reporting the two RETIRED types (review.step, content.published): their
-- history stays in company_event, but an event type that no routine and no trigger can emit any
-- more is not a live gap — and the exclusion is computed from the catalogue, not typed, so the
-- moment anyone re-adds an emitter for a retired type the class C row comes straight back. The
-- external-intake list is shared with class F so an edge-emitted type can never hide under it.
--
--   node scripts/apply_sql.mjs scripts/sql/connectivity_register_subscription_without_producer.sql --apply --ddl
begin;

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
$function$;

-- PROOF: the register still returns 0 rows, and class G is decidable (it names a gap when an
-- unproducible subscription is inserted, inside a subtransaction that is rolled back).
do $proof$
declare v_gaps int; v_g int;
begin
  select count(*) into v_gaps from public.fn_company_connectivity_register();
  if v_gaps <> 0 then
    raise exception 'register is not clean: % gap(s): %', v_gaps,
      (select string_agg(gap_class || ' ' || subject, '; ') from public.fn_company_connectivity_register());
  end if;
  begin
    insert into public.event_subscription (agent_key, event_type, reason, active)
    values ('ceo', 'zz.probe.nothing_emits_this', 'register proof', true);
    select count(*) into v_g from public.fn_company_connectivity_register()
     where gap_class = 'subscription_without_producer' and subject = 'zz.probe.nothing_emits_this -> ceo';
    raise exception 'PROBE_ROLLBACK %', v_g;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK %' then raise; end if;
    if sqlerrm <> 'PROBE_ROLLBACK 1' then raise exception 'class G did not fire on an unproducible subscription (%)', sqlerrm; end if;
  end;
  raise notice 'proof: register 0 gaps; class G fires on an unproducible subscription and rolled back';
end $proof$;
commit;
