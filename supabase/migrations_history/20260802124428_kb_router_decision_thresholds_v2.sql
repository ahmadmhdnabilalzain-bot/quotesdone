-- ROUTER DECISION RULE, second pass.
-- The first thresholds (absolute floor of 6, confidence >= 0.62) failed 11 of the 258 supplied route
-- tests, and every failure was the same shape: a customer writing ONE unambiguous word - "hvac",
-- "catering", "law", "pharmaceutical" - matched exactly one route, at full confidence, and was asked
-- a clarifying question anyway. That is the worst possible behaviour: the buyer said the category
-- name and we pretended not to understand.
-- The floor was measuring the wrong thing. Score is a proxy for SPECIFICITY (weight x word count),
-- not for certainty; a single high-weight word is a perfect signal with a low score. Certainty is
-- the MARGIN over the runner-up, so that is what the decision uses now:
--   * nothing matched              -> ask. (All 86 supplied "ambiguous" tests land here on their own
--                                     merits - they contain no category vocabulary at all - so this
--                                     rule is doing the work, not a tuned threshold.)
--   * exactly one route matched    -> route. There is nothing to be ambiguous between.
--   * two or more matched          -> route only if the leader is at least 1.5x the runner-up,
--                                     otherwise ask ONE question naming the two real candidates.
-- The residual floor of 3 exists only to stop a single low-weight fragment from deciding anything.
create or replace function public.fn_kb_route_decide(p_text text)
returns jsonb language plpgsql stable as $$
declare
  v jsonb; top numeric; second numeric; n int; v_action text; v_conf numeric; v_reason text;
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

  return jsonb_build_object(
    'action', v_action,
    'confidence', v_conf,
    'top_score', top,
    'candidates', v,
    'catalog_num', case when v_action = 'route_or_ask_scope_details' then (v->0->>'catalog_num')::int else null end,
    -- A genuinely multi-trade request (a fit-out that is also flooring and also joinery) is NOT an
    -- error to be collapsed to one route. Flagged so the intake can open several RFQs rather than
    -- forcing the buyer to pick one.
    'multi_category', (n > 1 and second >= top * 0.75),
    'reason', v_reason,
    'clarification', case when v_action = 'ask_clarifying_question' then
        'Just so this reaches the right suppliers - is this closer to "' || (v->0->>'live_name') ||
        '" or "' || coalesce(v->1->>'live_name', 'something else') || '"?' end,
    'normalised', public.kb_norm(p_text));
end $$;
