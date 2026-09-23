-- THE CEO REVIEWS THE WEEK, WATCHES PRICING AND FORECASTS THE AED 1M TARGET — AND EACH CALL IS CHALLENGED BY ANOTHER FAMILY.
-- Seat: ceo. 23 Sep 2026, founder_instruction 898 (no new agents) and the seat-duties plan (886-898): "WEEKLY
-- MANAGEMENT REVIEW (cross-family challenge); PRICING MONITORING with evidence-based proposals to the founder;
-- FORECAST vs AED 1M by Aug 2027". Needs every_seat_duty_has_an_owner_a_clock_and_a_check.sql.
--
-- WHAT WAS MEASURED (production, 23 Sep 2026)
--   * The forecast: target_contract 21 (AED 1,000,000 of collected reveal fees) carries a driver model, and
--     fn_target_feasibility(contract, record) computes run rates, scenarios, the binding stage and a verdict into
--     target_verdict — and HAS NO CALLER. 4 verdicts exist, all written by hand on 7 Sep; all AT_RISK or CANNOT_ASSESS.
--   * The week: fn_ceo_weekly_report sends the founder figures; fn_ceo_plan_tick issues directives by binding stage.
--     Nothing REVIEWS the seats' week as a manager would — which duties failed, which findings stand open, where
--     supply is short, what is waiting in each seat's reasoning queue — and nothing challenges the CEO's own reading.
--   * Pricing: pricing_config holds the supplier fee, the caps, the promo window and the non-response charge. Nothing
--     watches whether the evidence supports them, so a proposal to the founder could only ever be a guess.
--
-- WHAT THIS ADDS — three duties (owner ceo, every 7 days), recorded in public.ceo_review (one row per kind and week):
--   ceo.target_forecast: fn_target_feasibility for every active contract that has an instrument (verdicts recorded,
--     deterministically, every week). A revenue verdict other than ON_TRACK is a judgement — hold course, change the
--     plan, or tell the founder — reasoned by the CEO (stakes high). Any call other than hold is challenged by the
--     accountant on a model of another family; "tell the founder" reaches him through customer_support.
--   ceo.management_review: the week's facts per seat, gathered deterministically; the CEO reasons the verdict
--     (on track / at risk / off track), the binding constraint and one line per seat; the accountant challenges it on
--     a model of another family (seat_deliberation). The review is the record the next week's review starts from.
--   ceo.pricing_monitor: the evidence (quoted requests, reveals, conversion, refunds, non-response, fees against quote
--     values) over 90 days. Under 20 quoted requests the evidence is too thin and that is recorded, not reasoned. With
--     enough, keep or propose a change is reasoned; a proposal goes to the founder through customer_support as an
--     evidence-based proposal, naming the accountant's challenge that runs on a model of another family. The 3 % reveal
--     fee paid by the buyer is the founder's fixed rule and is never proposed for change.
--
-- WHAT THIS DOES NOT DO: it changes no price (pricing is the founder's), issues no ceo.directive (fn_ceo_plan_tick owns
-- those, with their measures), and reads no text to decide anything — the judgements are think() decisions.

create table if not exists public.ceo_review (
  kind          text not null check (kind in ('management_review', 'pricing_monitor', 'target_forecast')),
  period        date not null,                    -- the ISO week's Monday, Dubai
  facts         jsonb not null default '{}'::jsonb,
  held_id       bigint,
  decision      text,
  fields        jsonb,
  reasoning     text,
  model         text,
  review        jsonb,                            -- the cross-family challenge (seat_deliberation) or why none
  founder_notice jsonb,
  created_at    timestamptz not null default now(),
  decided_at    timestamptz,
  primary key (kind, period)
);
alter table public.ceo_review enable row level security;
drop policy if exists ceo_review_service_role_only on public.ceo_review;
create policy ceo_review_service_role_only on public.ceo_review as permissive for all to public using (false) with check (false);
revoke all on public.ceo_review from anon, authenticated;

-- ── shared: the week, and the founder notice through customer_support ────────────────────────────────────
create or replace function public.fn_ceo_review_week()
returns date language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$ select date_trunc('week', (now() at time zone 'Asia/Dubai'))::date $fn$;
revoke execute on function public.fn_ceo_review_week() from public, anon, authenticated;
grant execute on function public.fn_ceo_review_week() to service_role;

create or replace function public.fn_ceo_review_tells_founder(p_kind text, p_period date, p_event text, p_detail text, p_mail_kind text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint; a public.agent_actions;
begin
  -- customer_support is the one sender; the founder path honours app.qd_stub_founder_notify (a probe never reaches him).
  v_id := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_review', p_kind || ':' || p_period,
    jsonb_build_object('recipient_role', 'founder', 'event', p_event, 'detail', p_detail, 'level', 'info',
                       'kind', p_mail_kind, 'dedupe_key', 'ceo_review:' || p_kind || ':' || p_period));
  select * into a from public.agent_actions where id = v_id;
  update public.ceo_review set founder_notice = jsonb_build_object('handoff_id', v_id, 'status', a.status, 'evidence', a.evidence)
   where kind = p_kind and period = p_period;
  return jsonb_build_object('handoff_id', v_id, 'status', a.status);
end $fn$;
revoke execute on function public.fn_ceo_review_tells_founder(text, date, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_review_tells_founder(text, date, text, text, text) to service_role;

-- ── 1. the forecast against the target ───────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_target_forecast()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c record; v jsonb; v_all jsonb := '[]'::jsonb; v_rev jsonb; v_week date := public.fn_ceo_review_week(); v_held bigint;
begin
  for c in select id, contract_key from public.target_contract where status = 'active' and measure_sql is not null order by priority, id loop
    v := public.fn_target_feasibility(c.id, true);
    v_all := v_all || jsonb_build_object('contract', c.contract_key, 'verdict', v->>'verdict', 'verdict_reason', v->>'verdict_reason',
                                         'remaining', v->'remaining_outcome', 'days_remaining', v->'days_remaining',
                                         'required_run_rate_per_day', v->'required_run_rate_per_day', 'binding_stage', v->>'binding_stage',
                                         'what_must_change', v->'what_must_change');
    if c.contract_key = 'REVEAL_FEES_BASE_PATH_BY_2027_08_31' then v_rev := v; end if;   -- the target in force (the AED 1M was withdrawn, instruction 962)
  end loop;

  insert into public.ceo_review (kind, period, facts) values ('target_forecast', v_week, jsonb_build_object('verdicts', v_all))
  on conflict (kind, period) do update set facts = excluded.facts;

  if v_rev is not null and coalesce(v_rev->>'verdict', '') <> 'ON_TRACK'
     and (select held_id from public.ceo_review where kind = 'target_forecast' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.target_forecast',
      'This week''s forecast says the revenue target in force (the base-case path: AED 244,801 of collected reveal fees by 31 August 2027) is not on track. '
        || 'As the chief executive, decide the company''s response, and say what must change and who owns it.',
      ('[{"id":"hold_course","meaning":"the plan in force is right; the gap is expected at this stage and closes as it runs"},'
      || '{"id":"change_plan","meaning":"the plan must change: a different binding constraint, channel or sequence"},'
      || '{"id":"tell_founder","meaning":"the gap needs a decision only the founder holds (money, a commercial rule, his intent)"}]')::jsonb,
      jsonb_build_object('forecast', v_rev - 'chain', 'all_contracts', v_all),
      jsonb_build_object('kind', 'target_forecast', 'period', v_week), 'ceo_forecast:' || v_week);
    update public.ceo_review set held_id = v_held where kind = 'target_forecast' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'verdicts', v_all, 'reasoning_filed', v_held is not null);
end $fn$;
revoke execute on function public.fn_ceo_target_forecast() from public, anon, authenticated;
grant execute on function public.fn_ceo_target_forecast() to service_role;

-- ── 2. the management review ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_management_review()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_week date := public.fn_ceo_review_week(); v_facts jsonb; v_held bigint;
begin
  if (select held_id from public.ceo_review where kind = 'management_review' and period = v_week) is not null then
    return jsonb_build_object('week', v_week, 'already_filed', true);
  end if;
  select jsonb_build_object(
    'seats', (select jsonb_object_agg(r.role_id, jsonb_build_object(
        'duties', (select coalesce(jsonb_agg(jsonb_build_object('duty', d.duty, 'last_ok_at', d.last_ok_at, 'failures', d.failures, 'last_result', d.last_result)), '[]'::jsonb)
                     from public.seat_duty d where d.owner_seat = r.role_id),
        'open_findings', (select count(*) from public.it_engineer_finding f where f.closed_at is null
                            and coalesce(f.evidence->>'owner_seat', f.raised_by) = r.role_id),
        'reasoning_waiting', (select count(*) from public.reasoning_held_question h where h.seat = r.role_id and h.status = 'held'),
        'handoffs_pending', (select count(*) from public.agent_actions a where a.agent = r.role_id and a.kind = 'handoff' and a.status = 'pending')))
      from public.org_role r where r.status = 'active'),
    'duties_unhealthy', public.fn_seat_duty_health(),
    'week_revenue_aed', (select coalesce(sum(reveal_fee), 0) from public.transactions where fee_status in ('paid', 'collected', 'succeeded') and revealed_at > now() - interval '7 days'),
    'requests_7d', (select count(*) from public.inquiries where created_at > now() - interval '7 days'),
    'customers', (select count(*) from public.customers where not coalesce(is_demo, false)),
    'suppliers_approved', (select count(*) from public.leads where approval_status = 'approved' and not coalesce(is_demo, false)),
    'forecast', (select facts from public.ceo_review where kind = 'target_forecast' and period = v_week),
    'last_review', (select jsonb_build_object('week', period, 'verdict', decision, 'fields', fields) from public.ceo_review
                     where kind = 'management_review' and period < v_week and decision is not null order by period desc limit 1))
  into v_facts;
  insert into public.ceo_review (kind, period, facts) values ('management_review', v_week, v_facts)
  on conflict (kind, period) do update set facts = excluded.facts;

  v_held := public.fn_seat_duty_reason('ceo', 'ceo.management_review',
    'The weekly management review. Read each seat''s week — its duties, failures, open findings, what waits in its '
      || 'reasoning queue — against the company''s target and last week''s review. Give the verdict, name the one '
      || 'binding constraint, and one concrete line of direction for each seat.',
    ('[{"id":"on_track","meaning":"the company is on its plan this week"},'
    || '{"id":"at_risk","meaning":"the plan holds but something material is slipping"},'
    || '{"id":"off_track","meaning":"the plan is not working and must change"}]')::jsonb,
    v_facts, jsonb_build_object('kind', 'management_review', 'period', v_week), 'ceo_mreview:' || v_week);
  -- The fields the review must fill, beside the verdict (think() fills them from its reasoning, with evidence).
  update public.reasoning_held_question
     set request = jsonb_set(request, '{decision,fields}', jsonb_build_array(
           jsonb_build_object('key', 'binding_constraint', 'question', 'the one constraint that most limits progress this week'),
           jsonb_build_object('key', 'sales_engineer', 'question', 'the sales engineer''s direction for the coming week'),
           jsonb_build_object('key', 'customer_support', 'question', 'customer support''s direction for the coming week'),
           jsonb_build_object('key', 'accountant', 'question', 'the accountant''s direction for the coming week'),
           jsonb_build_object('key', 'it_engineer', 'question', 'the IT engineer''s direction for the coming week'),
           jsonb_build_object('key', 'marketing', 'question', 'marketing''s direction for the coming week')))
   where id = v_held;
  update public.ceo_review set held_id = v_held where kind = 'management_review' and period = v_week;
  return jsonb_build_object('week', v_week, 'filed', v_held);
end $fn$;
revoke execute on function public.fn_ceo_management_review() from public, anon, authenticated;
grant execute on function public.fn_ceo_management_review() to service_role;

-- ── 3. the pricing monitor ───────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_pricing_monitor()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_week date := public.fn_ceo_review_week(); v_ev jsonb; v_quoted int; v_held bigint;
begin
  with q as (
    select i.id, (select count(*) from public.quotes x where x.inquiry_id = i.id) as quotes
      from public.inquiries i where i.created_at > now() - interval '90 days'
  )
  select jsonb_build_object(
    'pricing_config', (select to_jsonb(p) - 'id' - 'updated_at' from public.pricing_config p order by id limit 1),
    'requests_90d', (select count(*) from q),
    'quoted_requests_90d', (select count(*) from q where quotes > 0),
    'reveals_90d', (select count(*) from public.transactions where revealed_at > now() - interval '90 days'),
    'refunds_90d', (select count(*) from public.transactions where refund_requested_at > now() - interval '90 days'),
    'avg_quote_aed', (select round(avg(quote_amount), 2) from public.quotes where created_at > now() - interval '90 days' and quote_amount > 0),
    'avg_reveal_fee_aed', (select round(avg(reveal_fee), 2) from public.transactions where revealed_at > now() - interval '90 days'),
    'nonresponse_refunds', (select coalesce(sum(rv_nonresponse_refunds), 0) from public.leads),
    'supplier_fee_paying', (select count(*) from public.leads where registration_paid_at is not null),
    'competitors_on_file', (select count(*) from public.competitor))
  into v_ev;
  v_quoted := (v_ev->>'quoted_requests_90d')::int;
  insert into public.ceo_review (kind, period, facts, decision) values ('pricing_monitor', v_week, v_ev,
    case when v_quoted < 20 then 'insufficient_evidence' end)
  on conflict (kind, period) do update set facts = excluded.facts,
    decision = case when ceo_review.decided_at is null then excluded.decision else ceo_review.decision end;

  -- UNDER 20 QUOTED REQUESTS THE EVIDENCE CANNOT SUPPORT A PRICE CALL: recorded, not reasoned, not proposed.
  if v_quoted >= 20 and (select held_id from public.ceo_review where kind = 'pricing_monitor' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.pricing_monitor',
      'The weekly pricing review. From 90 days of evidence, decide whether our pricing (the supplier annual fee, the caps, '
        || 'the promotion window and the non-response charge) should stay as it is or whether an evidence-based change should '
        || 'be proposed to the founder. The 3 per cent reveal fee paid by the buyer is the founder''s fixed rule and is not in scope.',
      ('[{"id":"keep","meaning":"the evidence supports the current pricing"},'
      || '{"id":"propose_change","meaning":"the evidence supports proposing a specific change to the founder"}]')::jsonb,
      v_ev, jsonb_build_object('kind', 'pricing_monitor', 'period', v_week), 'ceo_pricing:' || v_week);
    update public.reasoning_held_question
       set request = jsonb_set(request, '{decision,fields}', jsonb_build_array(
             jsonb_build_object('key', 'proposal', 'question', 'the exact change proposed, if any, with the figure'),
             jsonb_build_object('key', 'evidence', 'question', 'the measured evidence it rests on')))
     where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'pricing_monitor' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'quoted_requests_90d', v_quoted, 'reasoning_filed', v_held is not null);
end $fn$;
revoke execute on function public.fn_ceo_pricing_monitor() from public, anon, authenticated;
grant execute on function public.fn_ceo_pricing_monitor() to service_role;

-- ── the reasoned calls, each challenged by the accountant on another family ──────────────────────────────
create or replace function public.fn_ceo_review_applies(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_kind text; v_period date;
  rv public.ceo_review; v_review jsonb; v_notice jsonb; v_fields jsonb;
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

  -- THE CHALLENGE: every call except "hold course" / "keep" is reviewed by the accountant on a model of another family.
  if v_choice not in ('hold_course', 'keep') then
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

  if (v_kind = 'pricing_monitor' and v_choice = 'propose_change') or (v_kind = 'target_forecast' and v_choice = 'tell_founder') then
    v_notice := public.fn_ceo_review_tells_founder(v_kind, v_period,
      case when v_kind = 'pricing_monitor' then 'CEO pricing proposal (evidence-based) for the week of ' || v_period
           else 'CEO: the revenue forecast needs your decision (week of ' || v_period || ')' end,
      left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)
        || E'\n\nThe accountant is challenging this on a model of another family (seat_deliberation '
        || coalesce(v_review->>'deliberation_id', 'not opened: ' || coalesce(v_review->>'error', '?')) || ').',
      case when v_kind = 'pricing_monitor' then 'founder_brief' else 'business_health_at_risk' end);
  end if;
  return jsonb_build_object('applied', true, 'kind', v_kind, 'period', v_period, 'choice', v_choice, 'review', v_review, 'founder', v_notice);
end $fn$;
revoke execute on function public.fn_ceo_review_applies(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_ceo_review_applies(bigint, jsonb) to service_role;

create or replace function public.fn_reason_apply_ceo__management_review(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_review_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_ceo__management_review(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_ceo__pricing_monitor(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_review_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_ceo__pricing_monitor(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_ceo__target_forecast(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_review_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_ceo__target_forecast(bigint, jsonb) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, owner_file)
values ('deliberation.review', 'ceo', 'accountant',
        'The accountant challenges, on a model of another family, the CEO''s weekly review, pricing call or forecast response.',
        'fn_seat_deliberation_acts_on_handoff', interval '2 days',
        'scripts/sql/the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql')
on conflict (type, from_seat, to_seat) do nothing;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.target_forecast', 'ceo', interval '7 days', 'fn_ceo_target_forecast',
   'Weekly feasibility verdicts for every instrumented target; a revenue verdict off track is a reasoned CEO response, challenged across families.',
   'scripts/sql/the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql'),
  ('ceo.management_review', 'ceo', interval '7 days', 'fn_ceo_management_review',
   'The week per seat, reasoned into a verdict, the binding constraint and a line per seat; challenged by the accountant on another family.',
   'scripts/sql/the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql'),
  ('ceo.pricing_monitor', 'ceo', interval '7 days', 'fn_ceo_pricing_monitor',
   '90 days of pricing evidence; with 20+ quoted requests keep-or-propose is reasoned, challenged, and a proposal goes to the founder.',
   'scripts/sql/the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
