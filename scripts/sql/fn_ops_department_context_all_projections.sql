-- fn_ops_department_context — the Company Operations pack's department briefing, rewritten so it
-- (a) can be reached from a LIVE department key and (b) reads every projection the pack ships.
--
-- WHY. Measured on production 2026-08-10 12:2x UTC: this function has ZERO callers, and twelve of
-- the pack's relational projections — departments, roles, sops, kpis, workflows, handoffs,
-- event_subscriptions, live_bindings, scenarios, templates (plus decision_rules and
-- exception_playbooks, which this function already read) — were read by NOTHING in production.
-- That is the same defect as the 115,148 knowledge records sitting in kb_stage while every
-- customer path read kb_chunks: complete, enabled, unread.
--
-- TWO KEYSPACES. ops_kb_stage is keyed on the pack's 24 TARGET departments
-- (rfq_intelligence, marketplace_operations, ...). The live org has 15 (procurement, sales, ...).
-- An employee arrives with a live key, so nothing keyed on target keys could ever answer them.
-- ops_kb_stage.department_crosswalk exists precisely for this and had no runtime reader either:
-- procurement -> {document_intelligence, marketplace_operations, rfq_intelligence}. Resolving
-- through the crosswalk is what the pack prescribes; MERGING the target org into org_departments
-- was tried in session 7 and reverted because it cost three Row #3 checks.
--
-- The function accepts either keyspace and resolves to the set of target departments.
create or replace function public.fn_ops_department_context(
  p_dept_key text, p_topic text default null::text, p_limit integer default 6)
returns jsonb
language sql
stable
as $function$
with tk as (
  -- a target key given directly, plus every target this production key maps onto
  select array(
    select distinct k from (
      select d.department_key k from ops_kb_stage.departments d where d.department_key = p_dept_key
      union
      select c.target_department_key from ops_kb_stage.department_crosswalk c
       where c.production_dept_key = p_dept_key and c.target_exists
    ) z where k is not null) targets
),
q as (
  select to_tsquery('simple', nullif(array_to_string(
      array(select w || ':*' from unnest(regexp_split_to_array(lower(coalesce(p_topic,'')), '[^a-z0-9]+')) w
            where length(w) >= 3), ' | '), '')) tsq
)
select jsonb_build_object(
  'department', p_dept_key,
  'target_departments', (select to_jsonb(targets) from tk),
  'charter', (
    select coalesce(jsonb_agg(jsonb_build_object('department', d.department_key, 'name', d.name,
             'charter', left(d.charter,400), 'north_star', left(d.north_star,240),
             'implementation_status', d.implementation_status) order by d.department_key), '[]'::jsonb)
    from ops_kb_stage.departments d, tk where d.department_key = any(tk.targets)),
  -- Each target role carries the routing pack's model default for that role. The 96
  -- scope='target_employee' rows in model_policy_by_identity are keyed on the same target
  -- department and title as ops_kb_stage.roles and had no reader anywhere; fn_ai_route picked up
  -- only the 24 current_agent rows. deterministic_first is the operative field: the pack says
  -- most of these roles should reach for a rule before a model.
  'roles', (
    select coalesce(jsonb_agg(jsonb_build_object('title', r.title, 'agent_key', r.agent_key,
             'authority_tier', r.authority_tier, 'max_authority', r.max_authority,
             'responsibilities', left(r.responsibilities,300),
             'model_default', case when i.identity_key is null then null else jsonb_build_object(
                 'primary', i.primary_model, 'fallback', i.fallback_model,
                 'deterministic_first', i.deterministic_first,
                 'max_output_tokens', i.max_output_tokens) end) order by r.record_id), '[]'::jsonb)
    from ops_kb_stage.roles r
    cross join tk
    -- identity_key IS the role's agent_key: 96 of 96 join exactly. Matching on department+title
    -- reached only 44 and was my invention, not the data's.
    left join public.model_policy_by_identity i
           on i.scope = 'target_employee' and i.identity_key = r.agent_key
    where r.department_key = any(tk.targets)),
  'company_core', (
    select coalesce(jsonb_agg(jsonb_build_object('title', c.title, 'content', c.body)), '[]'::jsonb)
    from (select r.title, left(r.content,1200) body from ops_kb_stage.records r
          where r.scope_type = 'company' and r.module in ('identity','principles','governance','privacy','language')
            and r.validation_status in ('reviewed','source_verified','approved')
          order by r.record_type limit 8) c),
  'department_knowledge', (
    select coalesce(jsonb_agg(s.x), '[]'::jsonb) from (
      select jsonb_build_object('record_id', r.record_id, 'title', r.title,
                                'content', left(r.content, 1500), 'module', r.module,
                                'implementation_status', r.implementation_status,
                                'authority_tier', r.authority_tier, 'risk_level', r.risk_level,
                                'source_ids', r.source_ids) x
      from ops_kb_stage.records r, q, tk
      where r.scope_type = 'department' and r.scope_key = any(tk.targets)
        and r.validation_status in ('reviewed','source_verified','approved')
        and (q.tsq is null or to_tsvector('simple', r.title || ' ' || left(r.content,4000)) @@ q.tsq)
      order by ts_rank(to_tsvector('simple', r.title || ' ' || left(r.content,4000)), q.tsq) desc,
               r.implementation_status, r.record_id
      limit greatest(p_limit,1)) s),
  'decision_rules', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'rule_id', d.rule_id, 'priority', d.priority,
             'when', coalesce(d.condition->>'text', d.condition::text),
             'then', coalesce(d.action->>'text', d.action::text),
             'authority_tier', d.authority_tier,
             'requires_human_review', d.requires_human_review) order by d.priority desc nulls last), '[]'::jsonb)
    from ops_kb_stage.decision_rules d, tk
    where d.department_key = any(tk.targets) and d.enabled),
  -- SOPs come from the pack's own sops projection (steps, definition of done, rollback, SLA),
  -- not from records filtered by record_type: the projection is the structured shape and the
  -- structure is the part an employee needs to actually follow the procedure.
  'sops', (
    select coalesce(jsonb_agg(jsonb_build_object('workflow', s.workflow_key, 'trigger', s.trigger,
             'steps', s.steps, 'definition_of_done', s.definition_of_done,
             'service_level', s.service_level, 'rollback', left(s.rollback,240),
             'authority_tier', s.authority_tier) order by s.record_id), '[]'::jsonb)
    from ops_kb_stage.sops s, tk where s.department_key = any(tk.targets)),
  'exception_playbooks', (
    select coalesce(jsonb_agg(jsonb_build_object('exception', p.exception_key, 'trigger', p.trigger,
                                                 'immediate_actions', p.immediate_actions,
                                                 'recovery', p.recovery) order by p.exception_key), '[]'::jsonb)
    from ops_kb_stage.exception_playbooks p, tk
    where p.department_key = any(tk.targets) and p.enabled),
  'kpis', (
    select coalesce(jsonb_agg(jsonb_build_object('metric', k.metric_name, 'formula', left(k.formula_description,240),
             'direction', k.direction, 'owner', k.owner) order by k.record_id), '[]'::jsonb)
    from ops_kb_stage.kpis k, tk where k.department_key = any(tk.targets) and coalesce(k.enabled,true)),
  'workflows', (
    select coalesce(jsonb_agg(jsonb_build_object('workflow', w.workflow_key, 'name', w.name,
             'trigger', left(w.trigger,200), 'departments', to_jsonb(w.departments),
             'hard_gates', to_jsonb(w.hard_gates), 'implementation_status', w.implementation_status)
             order by w.workflow_key), '[]'::jsonb)
    from ops_kb_stage.workflows w, tk where w.departments && tk.targets and coalesce(w.enabled,true)),
  'handoffs', (
    select coalesce(jsonb_agg(jsonb_build_object('workflow', h.workflow_key,
             'direction', case when h.from_department = any(tk.targets) then 'you send' else 'you receive' end,
             'from', h.from_department, 'to', h.to_department,
             'you_must', case when h.from_department = any(tk.targets) then left(h.sender_action,200)
                              else left(h.receiver_action,200) end,
             'acceptance', left(h.acceptance,160), 'rejection', left(h.rejection,160)) order by h.record_id), '[]'::jsonb)
    from ops_kb_stage.handoffs h, tk
    where (h.from_department = any(tk.targets) or h.to_department = any(tk.targets)) and coalesce(h.enabled,true)),
  -- All 100 pack subscriptions carry active=false: the pack ships them staged and step 18 of
  -- 03_IMPORT_ORDER says stop before activation. Filtering on active would return [] for every
  -- department and the projection would still be unread. They are emitted WITH the flag, because
  -- "your department is supposed to receive this event and does not yet" is the fact the target
  -- operating model is asserting. Setting active=true here would change nothing on the live bus
  -- (public.event_subscription is a different table) and would only dress the flag up as delivery.
  'event_subscriptions', (
    select coalesce(jsonb_agg(jsonb_build_object('event', e.event_type, 'reason', left(e.reason,200),
             'activated', coalesce(e.active,false)) order by e.event_type), '[]'::jsonb)
    from ops_kb_stage.event_subscriptions e, tk
    where e.department_key = any(tk.targets) or e.department_key = 'all'),
  'scenarios', (
    select coalesce(jsonb_agg(jsonb_build_object('scenario', s.scenario_key, 'kind', s.kind,
             'situation', left(s.situation,240), 'expected', left(s.expected_behaviour,240),
             'last_result', s.last_result, 'last_run', s.last_run) order by s.scenario_key), '[]'::jsonb)
    from ops_kb_stage.scenarios s, tk where s.scope_key = any(tk.targets)),
  'templates', (
    select coalesce(jsonb_agg(jsonb_build_object('template', t.template_key, 'purpose', left(t.purpose,200))
             order by t.template_key), '[]'::jsonb)
    from ops_kb_stage.templates t, tk where t.department_key = any(tk.targets)),
  'live_data', (
    select coalesce(jsonb_agg(jsonb_build_object('object', b.object_name, 'kind', b.db_object_kind,
                                                 'purpose', b.read_purpose, 'write_policy', b.write_policy)), '[]'::jsonb)
    from ops_kb_stage.live_bindings b, tk
    where b.department_key = any(tk.targets) and b.mapping_status = 'mapped'),
  'authoritative_sources', (
    select coalesce(jsonb_agg(jsonb_build_object('source_id', s2.source_id, 'title', s2.title,
                                                 'publisher', s2.publisher, 'url', s2.url_or_path)), '[]'::jsonb)
    from ops_kb_stage.sources s2
    where exists (select 1 from ops_kb_stage.records r, tk
                  where r.scope_key = any(tk.targets) and s2.source_id = any(r.source_ids))),
  'hard_gates', (
    select coalesce(jsonb_agg(jsonb_build_object('action_class', g.raw->>'action_class',
                                                 'approval_role', g.raw->>'approval_role')), '[]'::jsonb)
    from ops_kb_stage.hard_gates g),
  'institutional_memory', (
    select coalesce(jsonb_agg(jsonb_build_object('headline', m.headline, 'outcome', m.outcome)), '[]'::jsonb)
    from (select headline, outcome from public.institutional_memory order by created_at desc limit 3) m),
  'note', 'Decision rules, SOPs and exception playbooks are ENABLED as of 2026-08-10, after all 282 pack scenarios returned RUNNABLE. Hard gates still bind, and money still routes to the founder. Records marked target_state describe a capability that is NOT built yet.'
);
$function$;

-- Not SECURITY DEFINER (unchanged): it is called from fn_agent_context, which is, and from
-- fn_ops_dashboard. Nothing new is granted, so nothing new needs revoking.
