-- THE CEO REVIEW PROVES ITS AUTHOR ON THE CLASS think() BILLS (5 Oct 2026, ceo seat).
--
-- Found by the release operator's end sweep: ceo_reviews_pricing_and_forecast_act failed on production with the
-- forecast's tell_founder decision recorded challenged:false. Measured cause: since founder_instruction 1056 think()
-- bills a seat's own decision to task_class internal_judgement, and fn_seat_duty_cross_review / fn_high_stakes_gate
-- prove the author model on that class. The check's fixture still seeded the CEO's proving call as agent_reasoning, so
-- the cross review answered AUTHOR_MODEL_UNPROVEN and no deliberation opened (the check is fixed in the same commit).
-- The same stale class lived in THIS routine: the pricing gate was handed p_author_task_class 'agent_reasoning', so a
-- real pricing proposal would carry a class think() never bills. This redefinition changes only that argument.
-- Not changed: the founder is notified, never asked (8 Sep, 1058/1059) - the accountant's challenge is the second seat,
-- not an approval by him.
--
-- prevented by: scripts/checks/ceo_reviews_pricing_and_forecast_act.test.mjs (aborted production probe, now seeded
-- on internal_judgement, asserts the challenge opens) and the probe at the end of this file.

create or replace function public.fn_ceo_review_applies(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_kind text; v_period date;
  rv public.ceo_review; v_review jsonb; v_notice jsonb; v_fields jsonb; v_gate jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_kind := r.subject->>'kind'; v_period := (r.subject->>'period')::date;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  select * into rv from public.ceo_review where kind = v_kind and period = v_period for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'no review row'); end if;
  if rv.decided_at is not null then return jsonb_build_object('applied', true, 'already', v_kind || ' ' || v_period); end if;
  select coalesce(jsonb_object_agg(k, v->>'value'), '{}'::jsonb) into v_fields from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) f(k, v);

  -- THE CHALLENGE (narrowed 24 Sep 2026, it_engineer): only a call that goes to the founder - a pricing proposal or
  -- "tell the founder" - is challenged by the accountant on a model of another family. An internal verdict is one call.
  -- A PRICING CHANGE IS HIGH STAKES (29 Sep 2026, instruction 1009): it goes to the founder only once the accountant agreed on
  -- another family, or, while the model hold is on, at once with the review owed.
  if v_kind = 'pricing_monitor' and v_choice = 'propose_change' then
    v_gate := public.fn_high_stakes_gate('pricing_change', 'ceo', 'ceo_review', v_kind || ':' || v_period,
      'Challenge the chief executive''s pricing call before it reaches the founder.',
      case when length(rv.facts::text) <= 50000 then jsonb_build_object('facts', rv.facts)
           else jsonb_build_object('facts_cut_at_50000_chars', left(rv.facts::text, 50000)) end,
      jsonb_build_object('call', v_choice, 'fields', v_fields, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000),
                         'founder_detail', left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)),
      nullif(p_result->>'model', ''), 'internal_judgement');
    v_review := v_gate;
  elsif v_choice in ('propose_change', 'tell_founder') then
    v_review := public.fn_seat_duty_cross_review('ceo.' || v_kind, 'ceo', 'accountant',
      case v_kind when 'management_review' then 'Challenge the chief executive''s reading of the company''s week.'
                  when 'pricing_monitor' then 'Challenge the chief executive''s pricing call before it reaches the founder.'
                  else 'Challenge the chief executive''s response to the revenue forecast.' end,
      -- seat_deliberation.evidence is capped at 60,000 characters; a week that outgrows it is passed as text, cut.
      case when length(rv.facts::text) <= 50000 then jsonb_build_object('facts', rv.facts)
           else jsonb_build_object('facts_cut_at_50000_chars', left(rv.facts::text, 50000)) end,
      jsonb_build_object('call', v_choice, 'fields', v_fields, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000)),
      p_result, 'ceo_review', v_kind || ':' || v_period);
  end if;
  update public.ceo_review set decision = v_choice, fields = v_fields, reasoning = left(coalesce(p_result->>'answer', ''), 6000),
         model = p_result->>'model', review = v_review, decided_at = now()
   where kind = v_kind and period = v_period;

  -- A pricing proposal still waiting for the accountant reaches the founder when the accountant agrees (trg_high_stakes_review).
  if (v_kind = 'pricing_monitor' and v_choice = 'propose_change' and coalesce((v_gate->>'proceed')::boolean, false))
     or (v_kind = 'target_forecast' and v_choice = 'tell_founder') then
    v_notice := public.fn_ceo_review_tells_founder(v_kind, v_period,
      case when v_kind = 'pricing_monitor' then 'CEO pricing proposal (evidence-based) for the week of ' || v_period
           else 'CEO: the AED 1M revenue forecast needs your decision (week of ' || v_period || ')' end,
      left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)
        || E'\n\nThe accountant is challenging this on a model of another family (seat_deliberation '
        || coalesce(v_review->>'deliberation_id', 'not opened: ' || coalesce(v_review->>'error', v_review->>'reason', '?')) || ').',
      case when v_kind = 'pricing_monitor' then 'founder_brief' else 'business_health_at_risk' end);
  end if;
  return jsonb_build_object('applied', true, 'kind', v_kind, 'period', v_period, 'choice', v_choice, 'review', v_review, 'founder', v_notice);
end $fn$;

-- probe (no DDL rolled back: a verdict row)
select case when position('''agent_reasoning''' in pg_get_functiondef('public.fn_ceo_review_applies(bigint,jsonb)'::regprocedure)) = 0
             and position('''internal_judgement''' in pg_get_functiondef('public.fn_ceo_review_applies(bigint,jsonb)'::regprocedure)) > 0
            then 'PROBE OK' else 'PROBE FAILED: fn_ceo_review_applies still names agent_reasoning' end as verdict;
