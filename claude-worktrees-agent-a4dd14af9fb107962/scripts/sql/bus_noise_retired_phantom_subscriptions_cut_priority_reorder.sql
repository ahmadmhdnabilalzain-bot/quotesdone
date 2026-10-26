-- BUS NOISE RETIRED, PHANTOM SUBSCRIPTIONS CUT, PRIORITY REORDER WIRED (4 Sep 2026, MASTER_PLAN
-- §4.4 second half, §4.6, §5.1).
--
-- Measured on production before this file:
--   review.step        567 events / 526 deliveries, 1 subscriber (knowledge_director). Emitted by
--                      trg_event_review copying a review_chain row onto the bus; the dispatcher
--                      already attaches every delivery to the subject task (8 tasks ever minted, 0
--                      open) — so the event did nothing a review_chain row did not. Pure log noise.
--   content.published  360 events / 1,003 deliveries, 2 subscribers (brief, sales_director): 163
--                      tasks minted, 87 still open. Emitted by fn_review_submit on EVERY approved
--                      review of ANY subject (org_tasks, social posts, documents), so "content" was
--                      the review chain, not content. sales_director's reason even says it wanted
--                      campaign.published. The review_chain 'published' row is the log.
--   test.failed        151 events, 2 subscribers: qa_manager (Platform, STAFF_ORG seat 42
--                      Test-triage) and ops_director (exec). Platform owns the failing suite; the
--                      exec copy minted a second task per failure under the leadership OS, which
--                      declares no such input (48 UNDECLARED INPUT assessments). The technology OS
--                      never declared test.failed as an input either (17 UNDECLARED on qa_manager's
--                      side), so the seat that owns it was assessing it as a stranger.
--   priority.updated   43 events, subscriber strategy_director; nothing re-ordered anything —
--                      fn_org_task_assign hands work out strictly by created_at, so a
--                      re-prioritisation was a task about priorities, not a change of priority.
--   regulation.changed 0 emitted, 10 subscribers. The emitters are real (fn_regulation_propagate on
--                      `regulations` via os_ops → fn_kb_gov_approve; trg_emit_regulation_changed on
--                      compliance_sources.last_changed_at via the compliance agent). But
--                      fn_regulation_propagate ALREADY flags every affected agent_knowledge row
--                      (review_due = today) — that is the knowledge invalidation. Seven
--                      per-department "owns knowledge a regulator change can invalidate"
--                      subscriptions would each mint a task duplicating that flag. Kept: the three
--                      Trust, Safety & Compliance owners (compliance_mgr — STAFF_ORG seat 37, legal,
--                      risk_governance_mgr).
--   ai.confidence_dropped  0 emitted, subscriber ai_director. Emitter fn_ai_quality_watch, cron 93
--                      INACTIVE since the stand-down, and the routine also queues an admin e-mail
--                      (detect → e-mail the founder, the anti-pattern). Not re-enabled here.
--   invoice.flagged    0 emitted, 2 subscribers (cfo, risk_governance_mgr). Emitters
--                      fn_ap_bill_dupe_guard on ap_bills (written only by fn_po_bill — no caller)
--                      and fn_dispute_open (no caller). The unconnected ERP, §5.1.
--   department.conflict 0 emitted, subscriber brief. Emitter fn_emit_department_conflict — a
--                      deterministic decision_log scan (no model, no e-mail) whose cron 280 was left
--                      inactive by the stand-down. Re-enabled through the kernel wrapper below.
--
-- Nothing is deleted: subscriptions are deactivated with the reason on the row, their components
-- recorded INACTIVE_HISTORICAL, and the two retired event types keep their history in company_event.
--
--   node scripts/apply_sql.mjs scripts/sql/bus_noise_retired_phantom_subscriptions_cut_priority_reorder.sql --apply --ddl
begin;

-- 1. review.step: the review_chain row is the log. Stop copying it onto the bus.
drop trigger if exists trg_event_review on public.review_chain;

-- 2. content.published: fn_review_submit no longer emits it. Full definition; only the
--    company_event insert after the 'published' stage row is removed.
CREATE OR REPLACE FUNCTION public.fn_review_submit(p_subject_type text, p_subject_id text, p_dept_key text, p_author text, p_content text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_crit        jsonb;
  v_rule        jsonb;
  v_violations  jsonb := '[]'::jsonb;
  v_unenforced  jsonb := '[]'::jsonb;
  v_critical    int := 0;
  v_major       int := 0;
  v_pick        jsonb;
  v_head        text;
  v_deleg_from  text;
  v_deleg_basis text;
  v_cos         text := 'brief';
  v_decision    text;
  v_reason      text;
  v_conf        numeric;
  v_first_rule  text;
  v_res         jsonb;
begin
  -- CANONICAL AUTHOR, OR THE LEDGER CANNOT SEE ITS OWN SELF-REVIEWS.
  -- review_chain.author_agent was written with whatever string the caller passed while
  -- reviewer_agent was always resolved. A head authoring under an alias therefore produced a row
  -- whose author and reviewer were the SAME employee under two names - and every self-review
  -- count in this system is "author_agent = reviewer_agent", which such a row passes.
  -- So the reported zero was a property of the spelling, not of the behaviour.
  p_author := coalesce(public.fn_org_agent_resolve(p_author), p_author);

  -- Who is actually able to approve for this department right now, GIVEN WHO WROTE IT.
  v_pick        := fn_pick_reviewer(p_dept_key, p_author);
  v_head        := v_pick->>'reviewer';
  v_deleg_from  := v_pick->>'delegated_from';
  v_deleg_basis := v_pick->>'basis';

  -- The Chief of Staff cannot counter-sign its own draft either: that review climbs to the CEO.
  if p_author = coalesce(public.fn_org_agent_resolve(v_cos), v_cos) then v_cos := 'ceo'; end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, stage, decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, 'drafted', null,
          'Draft submitted for department review', null);

  if v_head is null then
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                              decision, reason, confidence, delegated_from, delegation_basis)
    values (p_subject_type, p_subject_id, p_dept_key, p_author, null, 'dept_review',
            'escalate', 'No available approver in ' || p_dept_key || ': ' || coalesce(v_deleg_basis,''), 1.0,
            v_deleg_from, v_deleg_basis);
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'escalate',
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'reason', coalesce(v_deleg_basis,''));
  end if;

  select criteria into v_crit from quality_standard where work_type = p_subject_type;

  if v_crit is not null then
    for v_rule in select * from jsonb_array_elements(v_crit) loop

      if (v_rule ? 'check_fn') then
        begin
          execute format('select %I($1,$2)', v_rule->>'check_fn')
            into v_res using p_subject_id, p_content;
        exception when others then
          v_res := jsonb_build_object('passed', false, 'detail', 'check ' || (v_rule->>'check_fn') || ' errored: ' || sqlerrm);
        end;
        if not coalesce((v_res->>'passed')::boolean, false) then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity',
            'why', v_rule->>'why', 'detail', v_res->>'detail');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      elsif (v_rule ? 'pattern') and (v_rule ? 'fails_when') then
        if (v_rule->>'fails_when') = 'match' and p_content ~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        elsif (v_rule->>'fails_when') = 'no_match' and p_content !~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      else
        v_unenforced := v_unenforced || jsonb_build_object(
          'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
      end if;

    end loop;
  end if;

  if v_critical > 0 then
    v_decision := 'reject';
    v_reason   := 'Rejected by department head: ' || v_critical || ' critical rule breach(es) - ' || (v_violations::text);
    v_conf     := 1.0;
  elsif v_major > 0 then
    v_decision := 'request_revision';
    v_reason   := 'Returned for revision: ' || v_major || ' major issue(s) - ' || (v_violations::text);
    v_conf     := 0.9;
  elsif jsonb_array_length(v_unenforced) > 0
        and exists (select 1 from jsonb_array_elements(v_unenforced) u where u->>'severity' = 'critical') then
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no executable check exists for critical criteria - ' || (v_unenforced::text);
    v_conf     := 1.0;
    v_first_rule := (select u->>'rule' from jsonb_array_elements(v_unenforced) u where u->>'severity'='critical' limit 1);
  elsif v_crit is null then
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no quality standard is defined for work type "' || p_subject_type || '"';
    v_conf     := 1.0;
  else
    v_decision := 'approve';
    v_reason   := 'Meets the quality standard for ' || p_subject_type || '; every criterion was checked and passed';
    v_conf     := 0.95;
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, violated_rule, confidence, delegated_from, delegation_basis)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_head, 'dept_review',
          v_decision, v_reason, v_first_rule, v_conf, v_deleg_from,
          case when v_deleg_from is not null then v_deleg_basis else null end);

  if v_decision <> 'approve' then
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', v_decision,
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'unenforceable', v_unenforced,
                              'reviewer', v_head, 'delegated_from', v_deleg_from);
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'cos_review',
          'approve', 'Approved by Chief of Staff: brand-compliant and serves a company goal', 0.9);

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'published',
          'approve', 'Published after full approval chain', 1.0);

  -- 4 Sep 2026: the content.published emit that stood here is retired. It fired on every approved
  -- review of any subject (org_tasks, posts, documents) — 360 events, 1,003 deliveries, 163 tasks
  -- minted and 87 still open for two subscribers who wanted campaign.published. The 'published'
  -- review_chain row above is the log; the real publish path emits campaign.published from
  -- content_drafts.status = 'posted' (fn_emit_campaign_published_from_content).

  return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'published',
                            'stopped_at', 'published', 'violations', v_violations,
                            'unenforceable', v_unenforced,
                            'reviewer', v_head, 'delegated_from', v_deleg_from);
end;
$function$;

-- 3. Subscriptions retired, reason on the row.
update public.event_subscription s
   set active = false,
       reason = coalesce(s.reason, '') || ' [retired 4 Sep 2026: ' || x.why || ']'
  from (values
    ('knowledge_director',      'review.step',           'event retired — trg_event_review dropped; review_chain is the log and the dispatcher only ever attached these deliveries to the subject task'),
    ('brief',                   'content.published',     'event retired — fn_review_submit no longer emits it; it fired on every approved review of any subject (163 tasks, 87 open); review_chain stage=published is the log'),
    ('sales_director',          'content.published',     'event retired — the reason on this row asked for campaign.published, which marketing_analyst consumes from the real posting path (content_drafts.status=posted)'),
    ('ops_director',            'test.failed',           'Platform owns test triage (STAFF_ORG seat 42 = qa_manager, still subscribed); the exec copy minted a second task per failure under an OS that declares no such input'),
    ('ai_director',             'ai.confidence_dropped', 'no live producer — fn_ai_quality_watch runs from cron 93, inactive since the stand-down, and pages the admin mailbox when it fires'),
    ('cfo',                     'invoice.flagged',       'no live producer — fn_ap_bill_dupe_guard sits on ap_bills (only writer fn_po_bill has no caller) and fn_dispute_open has no caller; reactivate with the ERP (MASTER_PLAN §5.1)'),
    ('risk_governance_mgr',     'invoice.flagged',       'no live producer — fn_ap_bill_dupe_guard sits on ap_bills (only writer fn_po_bill has no caller) and fn_dispute_open has no caller; reactivate with the ERP (MASTER_PLAN §5.1)'),
    ('brief',                   'regulation.changed',    'fan-out collapsed — fn_regulation_propagate already flags the affected agent_knowledge rows; compliance_mgr/legal/risk_governance_mgr own the change'),
    ('onboarding',              'regulation.changed',    'fan-out collapsed — fn_regulation_propagate already flags the affected agent_knowledge rows; compliance_mgr/legal/risk_governance_mgr own the change'),
    ('ops_director',            'regulation.changed',    'fan-out collapsed — fn_regulation_propagate already flags the affected agent_knowledge rows; compliance_mgr/legal/risk_governance_mgr own the change'),
    ('process_improvement_mgr', 'regulation.changed',    'fan-out collapsed — fn_regulation_propagate already flags the affected agent_knowledge rows; compliance_mgr/legal/risk_governance_mgr own the change'),
    ('procurement',             'regulation.changed',    'fan-out collapsed — fn_regulation_propagate already flags the affected agent_knowledge rows; compliance_mgr/legal/risk_governance_mgr own the change'),
    ('qa_manager',              'regulation.changed',    'fan-out collapsed — fn_regulation_propagate already flags the affected agent_knowledge rows; compliance_mgr/legal/risk_governance_mgr own the change'),
    ('rfq_qualification_mgr',   'regulation.changed',    'fan-out collapsed — fn_regulation_propagate already flags the affected agent_knowledge rows; compliance_mgr/legal/risk_governance_mgr own the change')
  ) as x(agent_key, event_type, why)
 where s.agent_key = x.agent_key and s.event_type = x.event_type and s.active;

-- 4. test.failed is a declared input of the technology OS (the seat that triages it).
insert into public.os_interface (os_key, direction, kind, description, event_type, active, planned, severity)
select 'technology', 'input', 'test.failed',
       'A scheduled suite or executor run failed. Technology (Test-triage, STAFF_ORG seat 42) diagnoses, quarantines flaky tests and routes real breaks.',
       'test.failed', true, false, 'high'
 where not exists (select 1 from public.os_interface where os_key = 'technology' and direction = 'input' and kind = 'test.failed');

-- 5. department.conflict gets its scheduler back, as a traced kernel component owned by the
--    Chief of Staff (the subscriber's own role), in the Office of the CEO.
do $$
declare v jsonb;
begin
  v := public.fn_kernel_wrap_and_enable_cron(280, 'chief_of_staff', 'exec');
  if not coalesce((v->>'ok')::boolean, false) then
    raise exception 'cron 280 (department_conflict_scan_weekly) could not be wrapped and enabled: %', v;
  end if;
end $$;

-- 6. priority.updated → the planner's backlog is actually re-ordered. A cross-OS episode that
--    concluded (fn_event_consolidate LINK 9) carries its assessed max_severity; the open tasks
--    attached to that episode move ahead of the created_at queue, and fn_org_task_assign hands
--    them out first. The subscription (strategy_director) keeps the human-readable re-read.
alter table public.org_tasks add column if not exists priority smallint not null default 0;

create or replace function public.fn_priority_backlog_reorder()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare v_rank smallint; v_n int;
begin
  v_rank := case new.payload->>'max_severity' when 'high' then 2 when 'medium' then 1 else 0 end;
  if v_rank = 0 or new.correlation_id is null then return new; end if;
  update public.org_tasks t
     set priority = greatest(t.priority, v_rank), updated_at = now()
   where t.status not in ('done','closed','cancelled')
     and t.priority < v_rank
     and t.id in (select d.task_id from public.event_delivery d
                    join public.company_event e on e.id = d.event_id
                   where e.correlation_id = new.correlation_id and d.task_id is not null);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('priority_backlog_reorder', now(), now(), 'ok',
            jsonb_build_object('event_id', new.id, 'correlation_id', new.correlation_id, 'rank', v_rank, 'tasks_moved', v_n),
            'priority.updated (' || coalesce(new.payload->>'max_severity','?') || ') moved ' || v_n
            || ' open task(s) of the episode ahead of the created_at queue.');
  end if;
  return new;
end $function$;

drop trigger if exists trg_priority_backlog_reorder on public.company_event;
create trigger trg_priority_backlog_reorder
  after insert on public.company_event
  for each row
  when (new.event_type = 'priority.updated')
  execute function public.fn_priority_backlog_reorder();

CREATE OR REPLACE FUNCTION public.fn_org_task_assign(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record; v_pick text;
  v_assigned int := 0; v_no_capacity int := 0; v_considered int := 0; v_saturated text;
  REVIEW_CLASSES constant text[] := array['review','audit','verify','qa_gate','security_review',
                                          'compliance_check','legal_review','supplier_verify',
                                          'capability_review','self_review'];
begin
  -- ONE TASK AT A TIME, TO THE CURRENTLY-LEAST-LOADED ELIGIBLE COLLEAGUE. Assigning inside the
  -- transaction makes each pick see the assignments already made in this sweep, so the load spreads
  -- breadth-first across the department and a single sweep fills it.
  --
  -- 4 Sep 2026: priority first. fn_priority_backlog_reorder raises it on the open tasks of a
  -- cross-OS episode that concluded with a high/medium assessed severity (priority.updated), so a
  -- re-prioritisation changes who gets served next instead of only minting a task about it.
  for r in
    select t.id, t.dept_key, t.action_class
      from public.org_tasks t
     where t.assigned_agent is null
       and t.status in ('assigned','in_progress')
     order by t.priority desc, t.created_at, t.id
     limit greatest(coalesce(p_limit, 200), 1)
  loop
    v_considered := v_considered + 1;
    select a.agent_key into v_pick
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role rr on rr.runtime_agent_key = a.agent_key and rr.status = 'active'
     where a.active
       and coalesce(a.available, true)
       and (a.unavailable_until is null or a.unavailable_until < now())
       and a.department = r.dept_key
       -- AN INDEPENDENT REVIEWER CARRYING THE DEPARTMENT'S ROUTINE QUEUE IS NOT INDEPENDENT OF IT.
       -- Review work still reaches them: the review action classes are the exception, and
       -- fn_pick_reviewer routes review directly rather than through this queue.
       and (coalesce(rr.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer'
            or coalesce(r.action_class, '') = any (REVIEW_CLASSES))
       -- REMAINING CAPACITY, RECOMPUTED EACH PICK so it counts what this sweep already assigned.
       and (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key
               and o.status in ('assigned','in_progress')) < coalesce(a.max_open_tasks, 6)
     order by case when p.tier = 'probation' then 1 else 0 end,
              (select count(*) from public.org_tasks o
                where o.assigned_agent = a.agent_key
                  and o.status in ('assigned','in_progress')),
              a.agent_key
     limit 1;

    if v_pick is not null then
      update public.org_tasks set assigned_agent = v_pick, updated_at = now() where id = r.id;
      v_assigned := v_assigned + 1;
    else
      v_no_capacity := v_no_capacity + 1;
    end if;
  end loop;

  -- Departments that genuinely could not take all their open work: every eligible colleague was at
  -- max_open_tasks. Now that a sweep fills a department, this is a TRUE saturation signal.
  select string_agg(x.dept_key||' '||x.unowned||'/'||x.capacity, ', ' order by x.unowned desc)
    into v_saturated
    from (select t.dept_key, count(*) as unowned,
                 (select coalesce(sum(coalesce(a.max_open_tasks,6)),0) from public.org_agents a
                   where a.active and coalesce(a.available,true) and a.department = t.dept_key) as capacity
            from public.org_tasks t
           where t.assigned_agent is null and t.status in ('assigned','in_progress')
           group by t.dept_key
          having count(*) > 0
           order by count(*) desc
           limit 6) x;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('org_task_assign', now(), now(), 'ok',
          jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                             'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none')),
          'Assigned '||v_assigned||' of '||v_considered||' unowned open task(s) to the currently '
          ||'least-loaded named colleague in the owning department, spreading within the department '
          ||'and skipping independent reviewers for non-review work. '||v_no_capacity||' left unowned '
          ||'only where every eligible colleague was already at max_open_tasks - deliberate: an '
          ||'unowned task is visible, an overloaded one is not. Departments still carrying more open '
          ||'work than they staff (unowned/capacity): '||coalesce(v_saturated,'none')||'.');

  return jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                            'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'));
end
$function$;

-- 7. Component mirror (the same two statements as every_live_entry_point_is_a_component.sql): a
--    subscription that went inactive is history; any live subscription without a component gets one.
update public.phase_c_component c
   set activation_state = 'inactive', classification = 'INACTIVE_HISTORICAL',
       repair_or_keep_action = 'recorded inactive 4 Sep 2026: the subscription this component described was retired (reason on the event_subscription row)',
       evidence = coalesce(c.evidence, '') || ' | 4 Sep 2026: no active event_subscription row matches this id'
 where c.component_id like 'evsub:%' and c.activation_state = 'active'
   and not exists (select 1 from public.event_subscription s where s.active
                    and 'evsub:' || s.agent_key || '@' || s.event_type = c.component_id);

insert into public.phase_c_component
  (component_id, component_type, source_path_or_db_object, entry_method, current_callers,
   external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor,
   accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id,
   idempotency_strategy, retry_policy, activation_state, classification, gap,
   repair_or_keep_action, evidence)
select 'evsub:' || s.agent_key || '@' || s.event_type, 'event_subscription', 'public.event_subscription',
       t.entry_method, t.current_callers, 'no', s.event_type, true, 'agent ' || s.agent_key, t.canonical_system_actor,
       r.role_id, r.primary_department_id, 'SYSTEM_SCOPE', '', t.authority_class, t.trace_policy_id,
       t.idempotency_strategy, t.retry_policy, 'active', 'WIRE_TO_CANONICAL', '',
       t.repair_or_keep_action,
       'event_subscription: agent_key=' || s.agent_key || ' event_type=' || s.event_type || ' active=true; reason="' || left(coalesce(s.reason, ''), 80) || '" (declared 4 Sep 2026)'
  from public.event_subscription s
  join public.org_agents a on a.agent_key = s.agent_key and a.active
  join public.org_role r on r.runtime_agent_key = s.agent_key and r.status = 'active' and r.runtime_mode <> 'knowledge_overlay'
  cross join (select * from public.phase_c_component where component_id = 'evsub:strategy_director@kpi.missed') t
 where s.active
   and not exists (select 1 from public.phase_c_component c where c.component_id = 'evsub:' || s.agent_key || '@' || s.event_type);

-- PROOF.
do $proof$
declare v_sub_missing int; v_sub_orphan int; v_retired int; v_cron_active boolean; v_trg int;
begin
  select count(*) into v_retired from public.event_subscription where not active and reason like '%retired 4 Sep 2026%';
  if v_retired <> 14 then raise exception 'expected 14 retired subscriptions, found %', v_retired; end if;
  select count(*) into v_sub_missing from public.event_subscription s where s.active and not exists (select 1 from public.phase_c_component c where c.component_id = 'evsub:' || s.agent_key || '@' || s.event_type);
  select count(*) into v_sub_orphan from public.phase_c_component c where c.component_id like 'evsub:%' and c.activation_state = 'active' and not exists (select 1 from public.event_subscription s where s.active and 'evsub:' || s.agent_key || '@' || s.event_type = c.component_id);
  if v_sub_missing + v_sub_orphan > 0 then raise exception 'component mirror off: missing % orphan %', v_sub_missing, v_sub_orphan; end if;
  select active into v_cron_active from cron.job where jobid = 280;
  if not coalesce(v_cron_active, false) then raise exception 'cron 280 is not active'; end if;
  select count(*) into v_trg from pg_trigger where tgname = 'trg_event_review';
  if v_trg <> 0 then raise exception 'trg_event_review still attached'; end if;
  if exists (select 1 from pg_proc where proname = 'fn_review_submit' and prosrc like '%''content.published''%') then
    raise exception 'fn_review_submit still emits content.published';
  end if;
  if not exists (select 1 from public.os_interface where os_key = 'technology' and direction = 'input' and kind = 'test.failed' and active) then
    raise exception 'technology:test.failed input not declared';
  end if;
  raise notice 'proof: 14 subscriptions retired with reasons, components mirrored (0 missing, 0 orphan), cron 280 active, review.step/content.published no longer emitted, technology declares test.failed';
end $proof$;
commit;
