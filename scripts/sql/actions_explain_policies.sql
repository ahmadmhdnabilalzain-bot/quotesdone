-- ROW #3 — every surfaced action says who, why and how confident, and none of them says under
-- which rule it was decided.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   explain-policies-applied  MISSING  0 of 34 surfaced action(s) show the policies applied:
--                                      assistant 0/8, escalations 0/8, governance 0/15, operations 0/3
-- 
-- ── WHERE THE ANSWER IS NOT ────────────────────────────────────────────────────────────────────
-- decision_trace.policy_keys is the obvious source and it is the wrong one: the table holds FOUR
-- rows in total. It cannot speak for thirty-four actions, and joining it would leave thirty of them
-- with an empty policies field — which the check correctly refuses, and which would be worse than
-- saying nothing.
-- 
-- ── WHERE IT IS ─────────────────────────────────────────────────────────────────────────────────
-- decision_policy, which is the company's own standing rule set and is what the gate consults. Two
-- of its rows speak to any action, and both are PER-ACTION rather than a constant dressed up as one:
-- 
--   action_autonomy    a map from action KIND to 'ack' or 'founder' — 25 kinds, and this is the row
--                      that decides whether the sweep may clear the action or the founder must see
--                      it. The action's own kind selects the answer.
--   confidence_min     0.6, compared against the action's OWN confidence. The rendered sentence
--                      carries the threshold, the action's value and which side of the floor it
--                      fell — so two actions of the same kind read differently.
-- 
--   founder_review_gates is added when the kind appears in it, because that is the chairman
--   doctrine list and an action inside it is not a judgement call.
-- 
-- Nothing is invented and nothing is a placeholder. An action with no recorded confidence says so
-- — "records no confidence, so the floor cannot be applied" — which is a true statement about the
-- action and, deliberately, not one of the strings the check discards as empty.
-- 
-- ── FOUR SURFACES, FOUR ROUTINES, ONE HELPER ────────────────────────────────────────────────────
-- The check reads the ACTUAL rows of four payloads, so all four have to carry it:
--   escalations  fn_os_command       -> attention
--   governance   fn_ws_governance    -> recent_escalations
--   operations   fn_ws_operations    -> approvals
--   assistant    fn_ws_ea            -> approvals_top, which fn_ea_agenda actually builds
-- 
-- A helper rather than the expression four times: one place to correct, and four one-line patches
-- instead of four transcriptions of the same logic into routines of 1.6k to 3.1k characters.
-- 
-- Two of the four components hand their payload to <ReadableObject>, so the key alone is enough
-- there. GovernanceApp already renders `rule` and `rules`. <Escalations> renders neither, so it
-- gets the render as well — a payload key that surface never draws would be exactly the
-- BUILT_BUT_UNREAD defect this row exists to measure.

create or replace function public.fn_action_policies(p_kind text, p_confidence numeric)
returns text[]
language sql
stable security definer
set search_path to 'public', 'pg_catalog'
as $function$
  select array_remove(array[
    -- action_autonomy: the standing per-kind rule that decides whether the sweep may clear this
    -- action or the founder must see it. The action's own kind selects the answer.
    (select 'action_autonomy: '||coalesce(p_kind,'(no kind)')||' → '||(d.value->>p_kind)
       from public.decision_policy d
      where d.key = 'action_autonomy' and p_kind is not null and d.value ? p_kind),
    -- confidence_min, against this action's own confidence, so two actions of the same kind read
    -- differently. An action with no confidence says that rather than being left blank.
    (select case when p_confidence is null
              then 'confidence_min '||(d.value#>>'{}')||' — this action records no confidence, so the floor cannot be applied'
              else 'confidence_min '||(d.value#>>'{}')||' — this action '||round(p_confidence, 2)::text
                   ||case when p_confidence < (d.value#>>'{}')::numeric then ', below the floor' else ', at or above the floor' end end
       from public.decision_policy d where d.key = 'confidence_min'),
    -- the chairman doctrine list: an action inside it is not a judgement call.
    (select 'founder_review_gates: '||p_kind||' is on the founder-review list'
       from public.decision_policy d
      where d.key = 'founder_review_gates' and p_kind is not null and d.value ? p_kind)
  ], null);
$function$;

CREATE OR REPLACE FUNCTION public.fn_os_command()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_health jsonb; v_ops jsonb; v_counts jsonb; v_attention jsonb; v_pipeline jsonb;
begin
  v_health := to_jsonb(fn_health_index());
  v_ops    := to_jsonb(fn_ops_dashboard());

  select jsonb_build_object(
    'suppliers_total', (select count(*) from leads),
    'rfqs_total',      (select count(*) from inquiries),
    'rfqs_active',     (select count(*) from inquiries where status = 'quoted'),
    'rfqs_revealed',   (select count(*) from inquiries where status = 'revealed'),
    'rfqs_cancelled',  (select count(*) from inquiries where status = 'cancelled'),
    'quotes_total',    (select count(*) from quotes),
    'decisions_7d',    (select count(*) from decision_log where created_at > now() - interval '7 days'),
    'decisions_24h',   (select count(*) from decision_log where created_at > now() - interval '24 hours')
  ) into v_counts;

  select jsonb_build_object(
    'sent',      (select count(*) from inquiries where status = 'sent' and parent_inquiry_id is null),
    'matched',   (select count(distinct im.inquiry_id) from inquiry_matches im join inquiries i on i.id = im.inquiry_id where i.status = 'sent'),
    'quoted',    (select count(*) from inquiries where status = 'quoted'),
    'revealed',  (select count(*) from inquiries where status = 'revealed'),
    'completed', (select count(*) from inquiries where status in ('completed','won'))
  ) into v_pipeline;

  select coalesce(jsonb_agg(x order by created_at desc), '[]'::jsonb) into v_attention
  from (
    select id, actor, kind, decision, confidence, route_to, created_at,
           jsonb_build_object('id', id, 'actor', actor, 'kind', kind, 'decision', decision,
             'policies', public.fn_action_policies(kind, confidence),
             'confidence', confidence, 'route_to', route_to, 'created_at', created_at,
             'os', public.fn_owning_os(actor),
             'reasons', reasons,
             'outcome', case when exists (select 1 from public.agent_actions a where a.decision_log_id = decision_log.id)
                  then (select coalesce(a.status,'recorded') || ' — ' || coalesce(a.title,'action taken')
                          from public.agent_actions a where a.decision_log_id = decision_log.id
                         order by a.created_at desc limit 1)
                  else 'held for ' || coalesce(route_to,'review') || ', no follow-up action recorded since ' || created_at::date end
           ) as x
    from decision_log where route_to is not null and route_to <> 'auto'
    order by created_at desc limit 8
  ) t;

  return jsonb_build_object(
    'ok', true, 'generated_at', now(),
    'health', v_health, 'ops', v_ops, 'counts', v_counts,
    'pipeline', v_pipeline, 'attention', v_attention
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_ws_governance()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.governance_kpis k),
    'universal_rules', (select universal_rules from public.agent_governance where active order by version desc limit 1),
    'response_structure', (select response_structure from public.agent_governance where active order by version desc limit 1),
    'recent_escalations', (select coalesce(jsonb_agg(e),'[]'::jsonb) from (
        select agent, title, coalesce(escalation_reason,'—') as reason, confidence,
               public.fn_action_policies(kind, confidence) as policies,
               public.fn_owning_os(agent) as os,
               case when decided_at is not null
        then coalesce(status,'decided') || ' by ' || coalesce(decided_by,'the system') || ' on ' || decided_at::date
        else 'still open, no decision recorded since ' || created_at::date end as outcome,
               to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions where escalated order by created_at desc limit 15) e),
    'agent_coverage', (select coalesce(jsonb_agg(c),'[]'::jsonb) from (
        select ca.name as agent, (ca.persona is not null) as has_persona,
               exists(select 1 from public.agent_knowledge k where k.agent_key='cat:'||ca.slug or k.agent_key=ca.slug) as has_knowledge,
               (select count(*) from public.agent_actions a where a.agent=ca.slug) as audit_items
        from public.category_agents ca where ca.active order by ca.name limit 60) c)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.fn_ws_operations()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'ops', jsonb_build_object(
      'health', (select (kpis->>'ops_health')::numeric from ops_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from ops_kpis k),
      'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='operations_ai' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'security', jsonb_build_object(
      'score', (select (kpis->>'security_score')::numeric from security_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from security_kpis k),
      'incidents', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk)) from agent_actions where agent='security_ai' and status in ('pending','needs_review')),'[]'::jsonb),
      'events', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'severity',severity,'source',source,'at',created_at) order by created_at desc) from (select * from security_events order by created_at desc limit 10) e),'[]'::jsonb)
    ),
    'kpis', jsonb_build_object(
      'approvals_pending',(select count(*) from agent_actions where status='pending'),
      'high_risk',(select count(*) from agent_actions where status='pending' and coalesce(risk,'') in ('high','critical')),
      'tasks_open',(select count(*) from crm_tasks where coalesce(status,'')<>'done'),
      'decisions_24h',(select count(*) from decision_log where created_at > now()-interval '24 hours'),
      'disputes',(select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending'))
    ),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'kind',kind,'risk',risk,'title',title,
        'policies', public.fn_action_policies(kind, confidence),
        'recommendation',recommendation,'status',status,'target_table',target_table,'created_at',created_at,
        'os', public.fn_owning_os(agent), 'confidence', confidence,
        'outcome', case when decided_at is not null
        then coalesce(status,'decided') || ' by ' || coalesce(decided_by,'the system') || ' on ' || decided_at::date
        else 'still open, no decision recorded since ' || created_at::date end)) from (
        select * from agent_actions where status='pending' order by (coalesce(risk,'')='critical') desc, created_at desc limit 30) a),'[]'::jsonb),
    'decisions', coalesce((select jsonb_agg(jsonb_build_object('id',id,'actor',actor,'kind',kind,'decision',decision,
        'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log order by created_at desc limit 20) d),'[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'source',source,'entity',entity)) from (select * from crm_tasks order by (coalesce(status,'')='done'), created_at desc limit 20) t),'[]'::jsonb)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.fn_ea_agenda(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'as_of', now(),
    'today', jsonb_build_object(
      'events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location,'attendees',attendees) order by starts_at)
          from ea_events where status='scheduled' and coalesce(starts_at, now())::date = current_date),'[]'::jsonb),
      'reminders_due', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'remind_at',remind_at) order by remind_at)
          from ea_reminders where not done and remind_at <= now()+interval '1 day'),'[]'::jsonb)
    ),
    'upcoming_events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location) order by starts_at)
        from ea_events where status='scheduled' and starts_at > current_date and starts_at <= (current_date + (p_days||' days')::interval)),'[]'::jsonb),
    'open_tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'priority',priority,'due',due_date,'source',source) order by (due_date is null), due_date)
        from (select * from crm_tasks where coalesce(status,'')<>'done' order by (due_date is null), due_date limit 15) t),'[]'::jsonb),
    'overdue_tasks', (select count(*) from crm_tasks where coalesce(status,'')<>'done' and due_date < now()),
    'approvals_to_clear', jsonb_build_object(
      'total',(select count(*) from agent_actions where status in ('pending','needs_review')),
      'high_risk',(select count(*) from agent_actions where status in ('pending','needs_review') and coalesce(risk,'') in ('high','critical')),
      'top', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'title',title,'risk',risk,
            'reason', coalesce(nullif(btrim(recommendation),''), nullif(btrim(escalation_reason),''), 'queued for founder review: ' || coalesce(kind,'action')),
            'policies', public.fn_action_policies(kind, confidence),
            'confidence', confidence,
            'os', public.fn_owning_os(agent),
            'outcome', case when decided_at is not null
                 then coalesce(status,'decided') || ' by ' || coalesce(decided_by,'the system') || ' on ' || decided_at::date
                 else 'still open, no decision recorded since ' || created_at::date end)
          order by (coalesce(risk,'')='high') desc, created_at desc)
          from (select * from agent_actions where status in ('pending','needs_review') order by (coalesce(risk,'')='high') desc, created_at desc limit 8) a),'[]'::jsonb)
    ),
    'recent_meetings', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'meeting_at',meeting_at,'summary',left(summary,240)) order by meeting_at desc)
        from (select * from ea_meetings order by meeting_at desc limit 5) m),'[]'::jsonb)
  );
$function$
;
