-- Put the pack's decision rules, SOPs and exception playbooks in front of the employee who is
-- actually deciding. fn_ops_department_context is what an employee reads; it returned company
-- core, department knowledge, live data, sources, hard gates and memory, while the 240 decision
-- rules, 236 SOPs and 240 exception playbooks sat one table away and were never read by anything.
--
-- Their conditions and actions are natural language, so enforcement is not a predicate evaluator:
-- it is the rule reaching the decider, in priority order, with its authority tier attached. Only
-- enabled rows appear, and the scenarios (282, all RUNNABLE) had to pass before they were enabled.
create or replace function public.fn_ops_department_context(p_dept_key text, p_topic text default null::text, p_limit integer default 6)
 returns jsonb
 language sql
 stable
as $function$
with q as (
  select to_tsquery('simple', nullif(array_to_string(
      array(select w || ':*' from unnest(regexp_split_to_array(lower(coalesce(p_topic,'')), '[^a-z0-9]+')) w
            where length(w) >= 3), ' | '), '')) tsq
)
select jsonb_build_object(
  'department', p_dept_key,
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
      from ops_kb_stage.records r, q
      where r.scope_type = 'department' and r.scope_key = p_dept_key
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
    from ops_kb_stage.decision_rules d
    where d.department_key = p_dept_key and d.enabled),
  'sops', (
    select coalesce(jsonb_agg(jsonb_build_object('title', r.title, 'content', left(r.content, 1200),
                                                 'authority_tier', r.authority_tier) order by r.record_id), '[]'::jsonb)
    from ops_kb_stage.records r
    where r.scope_type = 'department' and r.scope_key = p_dept_key
      and r.record_type = 'standard_operating_procedure'),
  'exception_playbooks', (
    select coalesce(jsonb_agg(jsonb_build_object('exception', p.exception_key, 'trigger', p.trigger,
                                                 'immediate_actions', p.immediate_actions,
                                                 'recovery', p.recovery) order by p.exception_key), '[]'::jsonb)
    from ops_kb_stage.exception_playbooks p
    where p.department_key = p_dept_key and p.enabled),
  'live_data', (
    select coalesce(jsonb_agg(jsonb_build_object('object', b.object_name, 'kind', b.db_object_kind,
                                                 'purpose', b.read_purpose, 'write_policy', b.write_policy)), '[]'::jsonb)
    from ops_kb_stage.live_bindings b
    where b.department_key = p_dept_key and b.mapping_status = 'mapped'),
  'authoritative_sources', (
    select coalesce(jsonb_agg(jsonb_build_object('source_id', s2.source_id, 'title', s2.title,
                                                 'publisher', s2.publisher, 'url', s2.url_or_path)), '[]'::jsonb)
    from ops_kb_stage.sources s2
    where exists (select 1 from ops_kb_stage.records r
                  where r.scope_key = p_dept_key and s2.source_id = any(r.source_ids))),
  'hard_gates', (
    select coalesce(jsonb_agg(jsonb_build_object('action_class', g.raw->>'action_class',
                                                 'approval_role', g.raw->>'approval_role')), '[]'::jsonb)
    from ops_kb_stage.hard_gates g),
  'institutional_memory', (
    select coalesce(jsonb_agg(jsonb_build_object('headline', m.headline, 'outcome', m.outcome)), '[]'::jsonb)
    from (select headline, outcome from public.institutional_memory order by created_at desc limit 3) m),
  'note', 'Decision rules, SOPs and exception playbooks are ENABLED as of 2026-08-10, after all 282 pack scenarios returned RUNNABLE. Hard gates still bind, and money still routes to the founder.'
);
$function$;
