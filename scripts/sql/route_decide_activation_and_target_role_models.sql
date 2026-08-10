-- Two last unread things, and the routing decision starts honouring activation.
--
-- 1. fn_kb_route_decide must not route to a DEACTIVATED category.
--    fn_kb_route_activation_blocked decides whether a route may be used. Until today it had zero
--    callers; fn_kb_retrieve now gates on it, but fn_kb_retrieve itself is called by nothing, so
--    the gate still sat off every live path. fn_kb_route_decide is the routing brain and it runs
--    344 times an hour under kb_route_tests_hourly. A route whose regulatory review is withdrawn
--    should stop receiving customers, and this is where that becomes true.
--    Candidates are FILTERED, not merely annotated: an annotated candidate is still routed to.
--
-- 2. model_policy_by_identity scope='target_employee' — 96 rows, still unread after fn_ai_route
--    picked up the 24 current_agent rows. These are keyed on the pack's TARGET departments and
--    titles, which is the same keyspace as ops_kb_stage.roles, so the target role is where the
--    target role's model default belongs. Joined onto the roles array of
--    fn_ops_department_context, which fn_agent_context calls on every AI context build.

create or replace function public.fn_kb_route_decide(p_text text)
returns jsonb
language plpgsql
stable
as $function$
declare
  v jsonb; top numeric; second numeric; n int; v_action text; v_conf numeric; v_reason text;
  v_cat int; v_rules jsonb; v_dropped int := 0;
begin
  -- deactivated routes are removed BEFORE scoring, so a blocked route cannot win, tie, or make
  -- the decision look ambiguous
  select coalesce(jsonb_agg(to_jsonb(r) order by r.score desc), '[]'::jsonb) into v
  from (select * from public.fn_kb_route(p_text, 5)) r
  where not coalesce((public.fn_kb_route_activation_blocked(r.catalog_num)->>'blocked')::boolean, true);

  select count(*) into v_dropped
  from (select * from public.fn_kb_route(p_text, 5)) r
  where coalesce((public.fn_kb_route_activation_blocked(r.catalog_num)->>'blocked')::boolean, true);

  n := jsonb_array_length(v);
  if n = 0 then
    return jsonb_build_object(
      'action', 'ask_clarifying_question', 'confidence', 0, 'top_score', 0,
      'candidates', '[]'::jsonb, 'catalog_num', null, 'multi_category', false,
      'reason', case when v_dropped > 0
                     then format('%s matching route(s) are not activated for live use', v_dropped)
                     else 'no deterministic alias matched the customer wording' end,
      'clarification', 'Could you tell me in your own words what you need supplied or done? For example "waterproof a warehouse roof" or "supply 200 office chairs".',
      'rules', '[]'::jsonb, 'deactivated_candidates', v_dropped,
      'normalised', public.kb_norm(p_text));
  end if;

  top    := (v->0->>'score')::numeric;
  second := case when n > 1 then (v->1->>'score')::numeric else 0 end;
  v_conf := round(top / nullif(top + second, 0), 3);

  if top < 3 then
    v_action := 'ask_clarifying_question';
    v_reason := 'only a weak fragment matched; not enough to act on';
  elsif n = 1 or top >= second * 1.5 then
    v_action := 'route_or_ask_scope_details';
    v_reason := case when n = 1 then 'single deterministic alias match'
                     else 'leading route is decisively ahead of the runner-up' end;
  else
    v_action := 'ask_clarifying_question';
    v_reason := 'leading routes are too close to call';
  end if;

  v_cat := case when v_action = 'route_or_ask_scope_details' then (v->0->>'catalog_num')::int end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rule_id', d.rule_id, 'type', d.rule_type, 'priority', d.priority,
           'when', d.when_json, 'then', d.then_json,
           'requires_human_review', d.requires_human_review,
           'confidence', d.confidence) order by d.priority desc nulls last, d.rule_id), '[]'::jsonb)
    into v_rules
    from (select * from kb_stage.decision_rules dr
           where v_cat is not null
             and dr.category_slug in (select m.package_slug from public.kb_operational_route_map m
                                       where m.catalog_num = v_cat)
           order by dr.priority desc nulls last, dr.rule_id
           limit 5) d;

  return jsonb_build_object(
    'action', v_action,
    'confidence', v_conf,
    'top_score', top,
    'candidates', v,
    'catalog_num', v_cat,
    'multi_category', (n > 1 and second >= top * 0.75),
    'reason', v_reason,
    'clarification', case when v_action = 'ask_clarifying_question' then
        'Just so this reaches the right suppliers - is this closer to "' || (v->0->>'live_name') ||
        '" or "' || coalesce(v->1->>'live_name', 'something else') || '"?' end,
    'rules', coalesce(v_rules, '[]'::jsonb),
    'deactivated_candidates', v_dropped,
    'normalised', public.kb_norm(p_text));
end $function$;
