-- Three pack artefacts that had NO runtime reader at all. Measured 2026-08-10 12:5x UTC by
-- searching every function body in public for the table name:
--
--   kb_stage.decision_rules   16,254 rows   readers: none
--                             (fn_ops_department_context matched only as a substring of
--                              ops_kb_stage.decision_rules — a false positive worth naming,
--                              because it is how an unread table looks read.)
--   model_catalog                 14 rows   readers: none
--   model_policy_by_identity     120 rows   readers: none
--   ai_tool_matrix                22 rows   readers: none  (handled in fn_ops_dashboard)
--
-- Each gets the consumer the pack's own text implies, not a call added to make a label flip.

-- ── 1. kb_stage.decision_rules → the routing decision that should already carry them ───────────
-- fn_kb_route_decide picks the operational category from the customer's wording. The category's
-- deterministic rules are what to DO once it is picked, and they were sitting one join away.
-- Additive: the 344 route tests assert on `action`, which is unchanged, and the hourly
-- kb_route_tests_hourly cron now exercises this read 344 times an hour.
create or replace function public.fn_kb_route_decide(p_text text)
returns jsonb
language plpgsql
stable
as $function$
declare
  v jsonb; top numeric; second numeric; n int; v_action text; v_conf numeric; v_reason text;
  v_cat int; v_rules jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(r) order by r.score desc), '[]'::jsonb) into v
  from (select * from public.fn_kb_route(p_text, 5)) r;

  n := jsonb_array_length(v);
  if n = 0 then
    return jsonb_build_object(
      'action', 'ask_clarifying_question', 'confidence', 0, 'top_score', 0,
      'candidates', '[]'::jsonb, 'catalog_num', null, 'multi_category', false,
      'reason', 'no deterministic alias matched the customer wording',
      'clarification', 'Could you tell me in your own words what you need supplied or done? For example "waterproof a warehouse roof" or "supply 200 office chairs".',
      'rules', '[]'::jsonb,
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

  -- The corpus's own deterministic rules for the category that was chosen. Highest priority
  -- first, five at most: this is a routing reply, not the rulebook.
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
    'normalised', public.kb_norm(p_text));
end $function$;

-- ── 2. model_catalog → a drift monitor, because drift is live TODAY ────────────────────────────
-- 22 of the 61 model policies were activated in session 7 naming models from the pack's
-- catalogue, and several of those models — deepseek/deepseek-v4-flash, qwen/qwen3.7-plus,
-- google/gemini-3.6-flash, anthropic/claude-opus-5 — are not in production's model_registry.
-- fn_ai_route silently substitutes and writes a WARNING into `why` that nothing reads. This makes
-- the divergence a measured, dated number instead of a string in a return value.
-- ROUTINE REMOVED 7 September 2026. public.fn_model_catalog_drift was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke execute on function public.fn_model_catalog_drift() from public;
revoke execute on function public.fn_model_catalog_drift() from anon;
revoke execute on function public.fn_model_catalog_drift() from authenticated;

-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
