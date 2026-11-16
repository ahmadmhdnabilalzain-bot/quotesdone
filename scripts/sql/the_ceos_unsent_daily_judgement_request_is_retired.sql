-- THE CEO'S UNSENT DAILY JUDGEMENT REQUEST IS RETIRED: THE CEO REASONS ON A MODEL IN ITS WEEKLY PLAN.
--
-- Assigned: ceo. Agent: simplify_build_D, 16 Nov 2026. Founder ledgers 1714/1715 (remove what is unnecessary, with evidence).
-- Audit: scratchpad audit_simplify/STALE.md S10.
--
-- MEASURED (16 Nov 2026, SELECT on production; bodies by pg_get_functiondef):
--   * fn_ceo_plan_tick (md5 6fffe75f31a8f8aadbd22ea7666ad05e) builds fn_ceo_judgement_request(plan) every day and stores it in
--     ceo_plan.judgement; the heartbeat (resilience_ping/ticks/ceo.ts) would call ceo_agent action 'judgement' only when
--     app_secrets.ceo_model_slot = 'on'. That key does not exist: ceo_plan holds 56 rows, judgement->>'slot' = 'on' in 0. The
--     request (avg 13,818 characters over the last 14 days) was built 56 times and sent 0 times.
--   * Its contract (fn_ceo_judgement_contract, md5 7c946e6547689ee5cd42c9bd6943c857) says "a UAE construction-procurement
--     marketplace" and asks for a founder_decision, "the one decision only the founder can take".
--   * The CEO already reasons on a model elsewhere: seat duty ceo.planning_loop (hourly, "Founder ledger 1696/1701/1705/1709")
--     -> fn_ceo_plan_due -> ceo_agent action 'plan' (fn_ceo_plan_request / fn_ceo_plan_contract), filed in ceo_plan_week.
--   * References: fn_ceo_judgement_request and fn_ceo_judgement_accept read fn_ceo_judgement_contract; fn_ceo_plan_tick reads
--     fn_ceo_judgement_request; fn_ceo_judgement_counterparts is read only by ceo_agent's judgement action (removed in the same
--     commit). No view, cron job or seat_duty names any of the four. fn_ceo_judgement_room is a different routine and stays.
-- THE DECISION (rulings 1696, 1708): the CEO should reason with a model, and it does, weekly, on the newer contract (CEO
-- decides, nothing for the founder). Wiring the daily one on would cost little (about 8k tokens in and at most 4k out on
-- anthropic/claude-opus-5.5 at USD 4 / 20 per million: about USD 0.11 a day) but would add a SECOND, older contract that is
-- construction-only and asks the founder to decide, contra 1586 and 1696. So the dead request-building is removed.
-- WHAT THIS DOES: fn_ceo_plan_tick no longer builds the request nor writes ceo_plan.judgement (plan C acts exactly as before);
-- the four routines are dropped (each signature named; no overloads on production). ceo_plan.judgement keeps its history.
-- prevented by: scripts/checks/the_ceo_plans_every_day.test.mjs test E (fails if the request, its call or its action returns)
-- and the verdict row at the end of this file.
set local lock_timeout = '3s';

create or replace function public.fn_ceo_plan_tick(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  v_local timestamp := p_at at time zone 'Asia/Dubai';
  v_fu jsonb; v_funnel jsonb; v_target jsonb; v_prev jsonb; v_dec jsonb; v_act jsonb; v_rev int;
  p public.ceo_plan;
begin
  v_fu := public.fn_ceo_plan_followup(p_at);

  select * into p from public.ceo_plan where plan_date = v_local::date;
  if found then
    return jsonb_build_object('ok', coalesce((v_fu->>'ok')::boolean, false), 'planned', false, 'reason', 'today''s plan exists',
                              'plan_id', p.id, 'stage', p.stage, 'followup', v_fu)
        || case when v_fu ? 'error' then jsonb_build_object('error', v_fu->>'error') else '{}'::jsonb end;
  end if;
  if v_local::time < time '06:00' then
    return jsonb_build_object('ok', coalesce((v_fu->>'ok')::boolean, false), 'planned', false, 'reason', 'before 06:00 Dubai', 'followup', v_fu)
        || case when v_fu ? 'error' then jsonb_build_object('error', v_fu->>'error') else '{}'::jsonb end;
  end if;

  v_funnel := public.fn_ceo_plan_funnel(p_at);
  -- THE CEO READS THE MARKETING PICTURE INTO THE PLAN (instruction 721): the latest marketing.report is kept on the
  -- day's plan row, read by the judgement request as input.marketing. Informational: it changes no lever.
  v_funnel := v_funnel || jsonb_build_object('marketing_report',
    (select jsonb_build_object('report_date', m.report_date, 'no_data_yet', m.no_data_yet, 'headline', m.figures->>'headline',
                               'measured', m.figures->'measured', 'not_measured', m.figures->'not_measured')
       from public.marketing_report m where m.report_date <= v_local::date order by m.report_date desc limit 1));
  select to_jsonb(m) into v_target from public.ceo_plan_month m where m.month = date_trunc('month', v_local)::date;
  select to_jsonb(x) into v_prev from public.ceo_plan x where x.plan_date < v_local::date order by x.plan_date desc limit 1;
  v_dec := public.fn_ceo_plan_decide(v_funnel, coalesce(v_target, '{}'::jsonb), v_prev);

  insert into public.ceo_plan (plan_date, funnel, month_target, stage, constraint_since, decision, founder_line)
  values (v_local::date, v_funnel, v_target, v_dec->>'stage', (v_dec->>'constraint_since')::date, v_dec, v_dec->>'founder_line')
  returning * into p;

  v_act := public.fn_ceo_plan_act(p.id);
  v_rev := public.fn_ceo_plan_review(p_at);

  -- 16 NOV 2026 (ceo, wave D): the model request built here every day was never sent (app_secrets.ceo_model_slot never
  -- existed; 0 of 56 plans answered) and is retired with its routines. The CEO reasons on a model in its weekly plan
  -- (fn_ceo_plan_due -> ceo_agent action 'plan'). ceo_plan.judgement is no longer written.

  return jsonb_build_object('ok', coalesce((v_act->>'ok')::boolean, false) and coalesce((v_fu->>'ok')::boolean, false),
    'planned', true, 'plan_id', p.id, 'stage', p.stage, 'lever', v_dec->>'lever', 'stalled', v_dec->'stalled',
    'directives', v_act->'directives', 'decisions_written', v_act->'decisions_written', 'reviews_written', v_rev, 'followup', v_fu
    )
    || case when coalesce((v_act->>'ok')::boolean, false) then '{}'::jsonb else jsonb_build_object('error', v_act->>'error') end
    || case when v_fu ? 'error' then jsonb_build_object('error', v_fu->>'error') else '{}'::jsonb end;
end $fn$;

drop function if exists public.fn_ceo_judgement_accept(bigint, jsonb, text);
drop function if exists public.fn_ceo_judgement_request(bigint);
drop function if exists public.fn_ceo_judgement_counterparts(bigint);
drop function if exists public.fn_ceo_judgement_contract();

select case
  when exists (select 1 from pg_proc where proname in ('fn_ceo_judgement_request', 'fn_ceo_judgement_accept', 'fn_ceo_judgement_contract', 'fn_ceo_judgement_counterparts'))
    then 'PROBE FAILED: a retired judgement routine is still there'
  when exists (select 1 from pg_proc where proname = 'fn_ceo_plan_tick' and prosrc ~ 'fn_ceo_judgement_')
    then 'PROBE FAILED: the daily plan still builds the judgement request'
  when exists (select 1 from pg_proc where prosrc ~ 'fn_ceo_judgement_(request|accept|contract|counterparts)\(')
    then 'PROBE FAILED: a routine still calls a retired judgement routine'
  else 'PROBE OK: the daily plan builds no model request; the four judgement routines are gone' end as verdict;
