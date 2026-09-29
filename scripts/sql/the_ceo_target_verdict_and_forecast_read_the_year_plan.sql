-- THE CEO'S DAILY TARGET VERDICT AND WEEKLY FORECAST READ THE FOUNDER'S YEAR PLAN, AND NOTHING WITHDRAWN.
-- Seat: ceo. 28 Sep 2026. Needs: the_ceo_runs_the_company_on_the_founders_year_one_targets.sql (#915, applied) and
-- routine_work_is_code_and_the_model_answers_only_real_judgement.sql (applied; it holds the forecast this replaces).
--
-- THE FOUNDER'S RULING (24 Sep 2026): targets only. 50 verified suppliers within two weeks (by 12 Oct 2026), 200 by
-- 30 Nov 2026, 300 by 31 Dec 2026; customers from January 2027; the AED 1M revenue target and "1,000 suppliers /
-- 1,000 customers" are WITHDRAWN and are never graded again.
--
-- WHAT WAS MEASURED (production, 28 Sep 2026)
--   * seat_duty ceo.target_verdict last_result: {"metrics": [], "misses": 0, "contract_id": 57}. The routine reads
--     target_path for the current month only, and contract 57's path starts in October 2026, so every September day
--     returned an empty list and "0 misses" was vacuous. Nothing guarded against an empty list.
--   * seat_duty ceo.target_forecast last_result (24 Sep): graded REVENUE_AED_1M_BY_2027_10_01 (2,688.17 AED a day),
--     SUPPLIERS_1000_BY_2027_10_01 and CUSTOMERS_1000_BY_2027_10_01. Contracts 21 and 22 have since been marked
--     superseded, but CUSTOMERS_1000 (23) is still 'active' with a measure, so the next run grades it again: the
--     forecast loops over every active contract instead of the plan.
--   * ceo_year_plan holds Oct 2026 - Sep 2027 (verified 125 / 200 / 300 ..., requests, reveals, fees from Jan 2027,
--     cost ceiling); target_path (contract 57) carries it per metric and seat. The 50-by-12-Oct milestone is held
--     nowhere as a number.
--
-- WHAT CHANGES
--   1. ceo_year_plan_milestone: the founder's dated supplier milestones (start 28 Sep = 0, 50 by 12 Oct, 200 by
--      30 Nov, 300 by 31 Dec 2026). The month-end path stays in ceo_year_plan; this holds only his dated words.
--   2. fn_ceo_target_daily_verdict: always grades verified suppliers against the milestone line (linear between the
--      previous and the next milestone). Before the path starts (September) it reads the first plan month and marks
--      those metrics 'not_yet_due'; customer-side metrics before the launch month (the first ceo_year_plan month with
--      requests > 0, January 2027) are 'not_yet_due', never a miss. It raises if the metric list would be empty.
--   3. fn_ceo_target_forecast: grades ONLY the plan contract (FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30) and adds each
--      supplier milestone's gap and the verified suppliers a day it needs.
--   4. CUSTOMERS_1000_BY_2027_10_01 is closed as 'abandoned' (withdrawn) with the founder's ruling as the reason,
--      superseded by the plan contract. Contracts 21 and 22 already carry their reasons. No row is deleted.
--
-- WHAT THIS DOES NOT CHANGE: the path numbers, the task / root-cause / handoff behaviour on a miss, fn_ambition_measure
-- (demo suppliers stay excluded), fn_ceo_year_plan_status, the duty clock, SOCIAL_2000 (marketing's), and there is no
-- per-trade tracker (ceo/supplier-target-tracker owns that). A new file, not an edit of the owners: those files are
-- 1,100+ lines each, and replaying one would resurrect superseded routines.
-- Prevented by: scripts/checks/the_ceo_target_routines_read_the_year_plan.test.mjs

-- ── 1. the founder's dated milestones ─────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_year_plan_milestone (
  due       date primary key,
  verified  integer not null check (verified >= 0),
  basis     text not null
);
alter table public.ceo_year_plan_milestone enable row level security;
drop policy if exists ceo_year_plan_milestone_service on public.ceo_year_plan_milestone;
create policy ceo_year_plan_milestone_service on public.ceo_year_plan_milestone for all to service_role using (true) with check (true);
revoke all on public.ceo_year_plan_milestone from anon, authenticated;

insert into public.ceo_year_plan_milestone (due, verified, basis) values
  ('2026-09-28', 0,   'the two weeks start (founder, 24 Sep 2026: 50 within two weeks)'),
  ('2026-10-12', 50,  'founder, 24 Sep 2026: 50 verified suppliers within two weeks'),
  ('2026-11-30', 200, 'founder, 24 Sep 2026: 200 by 30 Nov 2026'),
  ('2026-12-31', 300, 'founder, 24 Sep 2026: 300 by 31 Dec 2026')
on conflict (due) do update set verified = excluded.verified, basis = excluded.basis;

-- 'not_yet_due': a metric the plan defines but whose stage has not started (pre-launch, or before the path begins)
alter table public.target_daily_verdict drop constraint if exists target_daily_verdict_status_check;
alter table public.target_daily_verdict add constraint target_daily_verdict_status_check
  check (status = any (array['on_track', 'within_tolerance', 'miss', 'not_measurable', 'no_target', 'too_early', 'not_yet_due']));

-- ── 2. the daily verdict ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_target_daily_verdict(p_at timestamptz default now())
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_local timestamp := p_at at time zone 'Asia/Dubai'; v_day date := v_local::date;
  v_m0 date := date_trunc('month', v_local)::date; v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_frac numeric := extract(day from v_local) / extract(day from (date_trunc('month', v_local) + interval '1 month - 1 day'));
  p record; v_exp numeric; v_act numeric; v_gap numeric; v_status text; v_task bigint; v_hid bigint; v_prev_cum numeric;
  n_miss int := 0; n_new int := 0; n_closed int := 0; v_out jsonb := '[]'::jsonb; c_id bigint;
  v_pm date; v_launch date; m_next record; m_prev record;
  -- the customer side of the plan: zero until customers launch (founder, 24 Sep 2026: customers from January 2027)
  c_customer constant text[] := array['inquiries_posted', 'quotes_received', 'quote_coverage_pct', 'reveals_paid',
    'b2b_active_accounts', 'fee_aed', 'fee_aed_cumulative', 'checkout_success_pct', 'reveal_conversion_pct'];
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null then raise exception 'ceo.target_verdict: the year-one plan contract is not active'; end if;

  -- the plan month graded: this month, or before the path starts, its first month (graded 'not_yet_due')
  v_pm := coalesce((select max(month) from public.target_path where contract_id = c_id and month = v_m0),
                   (select min(month) from public.target_path where contract_id = c_id and month > v_m0));
  v_launch := (select min(month) from public.ceo_year_plan where requests > 0);
  select * into m_next from public.ceo_year_plan_milestone where due > v_day order by due limit 1;
  if m_next is null then select * into m_next from public.ceo_year_plan_milestone order by due desc limit 1; end if;
  select * into m_prev from public.ceo_year_plan_milestone where due < m_next.due order by due desc limit 1;

  for p in
    select t.metric_key, t.owner_seat, t.kind, t.direction, t.value, t.tolerance_pct from public.target_path t
     where t.contract_id = c_id and t.month = v_pm
    union all
    select 'verified_suppliers_milestone', 'sales_engineer', 'milestone', 'min', m_next.verified, 20 where m_next.due is not null
    order by 1
  loop
    if p.kind = 'milestone' then
      v_act := public.fn_ambition_measure('registrations_verified_cumulative', v_from, p_at);
      v_exp := case when m_prev.due is null or v_day >= m_next.due then m_next.verified
                    else round(m_prev.verified + (m_next.verified - m_prev.verified)
                               * (v_day - m_prev.due)::numeric / (m_next.due - m_prev.due), 1) end;
    else
      v_act := public.fn_ambition_measure(p.metric_key, v_from, p_at);
      if p.kind = 'cumulative' then
        -- the day's line starts from last month's TARGET; a real shortfall is carried by the month directive (still_needed)
        select coalesce(max(value), 0) into v_prev_cum from public.target_path where contract_id = c_id and metric_key = p.metric_key and month < v_pm;
        v_exp := round(v_prev_cum + (p.value - v_prev_cum) * v_frac, 1);
      elsif p.kind = 'month' and p.direction = 'min' then v_exp := round(p.value * v_frac, 1);
      else v_exp := p.value; end if;   -- a ceiling (direction max) is the whole month's: costs are lumpy, never pro-rated
    end if;

    v_gap := case when v_exp > 0 and v_act is not null then round(100.0 * (v_act - v_exp) / v_exp, 1) end;
    v_status := case when p.kind <> 'milestone' and v_pm <> v_m0 then 'not_yet_due'
                     when p.metric_key = any (c_customer) and (v_launch is null or v_m0 < v_launch) then 'not_yet_due'
                     when p.direction = 'max' then
                       case when v_act is null then 'not_measurable'
                            when v_act <= v_exp then 'on_track'
                            when v_gap <= p.tolerance_pct then 'within_tolerance'
                            else 'miss' end
                     when p.kind in ('month', 'cumulative') and extract(day from v_local) < 7 then 'too_early'
                     when v_exp is null or v_exp <= 0 then 'no_target'
                     when v_act is null then 'not_measurable'
                     when v_act >= v_exp then 'on_track'
                     when -v_gap <= p.tolerance_pct then 'within_tolerance'
                     else 'miss' end;

    -- the month's open task for this metric, if any
    select t.task_id into v_task from public.target_daily_verdict d join public.ceo_task t on t.task_id = d.task_id
     where d.contract_id = c_id and d.metric_key = p.metric_key and d.day >= v_m0 and d.day <= v_day
       and t.state in ('open', 'working', 'blocked') order by d.day desc limit 1;
    v_hid := null;
    if v_status = 'miss' then
      n_miss := n_miss + 1;
      if v_task is null then
        v_task := public.fn_ceo_task_open(format('Target miss: %s (%s) %s', p.metric_key, p.owner_seat, to_char(v_m0, 'Mon YYYY')),
          format(E'On %s %s read %s against %s (%s) on the founder''s year-one path (%s%% gap, tolerance %s%%).\nOwner: %s. The root-cause question went to the owner; this task closes when the measure is back within tolerance.',
                 v_day, p.metric_key, v_act, v_exp, case when p.direction = 'max' then 'the month''s ceiling' else 'expected by today' end,
                 v_gap, p.tolerance_pct, p.owner_seat));
        n_new := n_new + 1;
        if p.owner_seat = 'ceo' then
          perform public.fn_ceo_root_cause_ask('ceo', v_task, jsonb_build_object('metric', p.metric_key, 'day', v_day, 'expected', v_exp,
                                               'actual', v_act, 'gap_pct', v_gap, 'tolerance_pct', p.tolerance_pct, 'month_target', p.value));
        else
          v_hid := public.fn_seat_handoff('ceo', p.owner_seat, 'ceo.root_cause', 'ceo_task', v_task::text,
            jsonb_build_object('task_id', v_task, 'metric', p.metric_key, 'day', v_day, 'expected', v_exp, 'actual', v_act,
                               'gap_pct', v_gap, 'tolerance_pct', p.tolerance_pct, 'month_target', p.value));
        end if;
      end if;
    elsif v_task is not null and v_status in ('on_track', 'within_tolerance') then
      update public.ceo_task set state = 'done', closed_at = now(),
             evidence = format('Recovered on %s: %s read %s against %s expected (%s).', v_day, p.metric_key, v_act, v_exp, v_status)
       where task_id = v_task;
      n_closed := n_closed + 1; v_task := null;
    elsif v_task is not null and v_status = 'not_measurable' then
      update public.ceo_task set state = 'blocked',
             blocked_reason = format('On %s %s became not measurable (under 20 in its denominator); the miss is neither confirmed nor cleared.', v_day, p.metric_key)
       where task_id = v_task and state <> 'blocked';
    end if;

    insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status, task_id, handoff_id)
    values (v_day, c_id, p.metric_key, p.owner_seat, v_exp, v_act, v_gap, v_status, case when v_status = 'miss' then v_task end, v_hid)
    on conflict (day, contract_id, metric_key) do update set expected = excluded.expected, actual = excluded.actual, gap_pct = excluded.gap_pct,
      status = excluded.status, task_id = coalesce(target_daily_verdict.task_id, excluded.task_id),
      handoff_id = coalesce(target_daily_verdict.handoff_id, excluded.handoff_id);
    v_out := v_out || jsonb_build_object('metric', p.metric_key, 'status', v_status, 'expected', v_exp, 'actual', v_act);
  end loop;

  -- an empty verdict reads as "0 misses"; it must fail loudly instead
  if jsonb_array_length(v_out) = 0 then raise exception 'ceo.target_verdict: no plan metric graded on %', v_day; end if;
  return jsonb_build_object('day', v_day, 'contract_id', c_id, 'plan_month', v_pm, 'customers_launch', v_launch,
                            'milestone', jsonb_build_object('due', m_next.due, 'verified', m_next.verified),
                            'metrics', v_out, 'misses', n_miss, 'tasks_opened', n_new, 'tasks_closed', n_closed);
end $fn$;
revoke execute on function public.fn_ceo_target_daily_verdict(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_target_daily_verdict(timestamptz) to service_role;

-- ── 3. the weekly forecast: the plan contract only, plus the dated milestones ─────────────────────────────
create or replace function public.fn_ceo_target_forecast()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb; v_all jsonb := '[]'::jsonb; v_ms jsonb; v_week date := public.fn_ceo_review_week(); v_held bigint; c_id bigint;
  v_today date := (now() at time zone 'Asia/Dubai')::date; v_now numeric;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null then raise exception 'ceo.target_forecast: the year-one plan contract is not active'; end if;
  v := public.fn_target_feasibility(c_id, true);
  v_all := jsonb_build_array(jsonb_build_object('contract', 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30', 'verdict', v->>'verdict',
             'verdict_reason', v->>'verdict_reason', 'remaining', v->'remaining_outcome', 'days_remaining', v->'days_remaining',
             'required_run_rate_per_day', v->'required_run_rate_per_day', 'binding_stage', v->>'binding_stage',
             'what_must_change', v->'what_must_change'));

  v_now := public.fn_ambition_measure('registrations_verified_cumulative', now(), now());
  select coalesce(jsonb_agg(jsonb_build_object('due', m.due, 'verified_target', m.verified, 'verified_now', v_now,
           'gap', greatest(m.verified - v_now, 0),
           'needed_per_day', case when m.due > v_today then round(greatest(m.verified - v_now, 0) / (m.due - v_today), 2) end)
           order by m.due), '[]'::jsonb)
    into v_ms from public.ceo_year_plan_milestone m where m.due >= v_today and m.verified > 0;

  insert into public.ceo_review (kind, period, facts) values ('target_forecast', v_week, jsonb_build_object('verdicts', v_all, 'milestones', v_ms))
  on conflict (kind, period) do update set facts = excluded.facts;

  if coalesce(v->>'verdict', '') <> 'ON_TRACK'
     and (select held_id from public.ceo_review where kind = 'target_forecast' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.target_forecast',
      'This week''s forecast says the founder''s year-one plan (50 verified suppliers by 12 Oct, 200 by 30 Nov, 300 by 31 Dec 2026, '
        || 'customers from January 2027) is not on track. As the chief executive, decide the company''s response, and say what must change and who owns it.',
      ('[{"id":"hold_course","meaning":"the plan in force is right; the gap is expected at this stage and closes as it runs"},'
      || '{"id":"change_plan","meaning":"the plan must change: a different binding constraint, channel or sequence"},'
      || '{"id":"tell_founder","meaning":"the gap needs a decision only the founder holds (money, a commercial rule, his intent)"}]')::jsonb,
      jsonb_build_object('forecast', v - 'chain', 'milestones', v_ms, 'year_plan', public.fn_ceo_year_plan_status(now())),
      jsonb_build_object('kind', 'target_forecast', 'period', v_week), 'ceo_forecast:' || v_week);
    -- ONE CALL PER REPORT (24 Sep 2026, it_engineer): normal stakes, so think() runs no second-family verify on it.
    update public.reasoning_held_question set request = request || '{"stakes":"normal"}'::jsonb where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'target_forecast' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'verdicts', v_all, 'milestones', v_ms, 'reasoning_filed', v_held is not null);
end $fn$;
revoke execute on function public.fn_ceo_target_forecast() from public, anon, authenticated;
grant execute on function public.fn_ceo_target_forecast() to service_role;

-- ── 4. the withdrawn customer contract is closed, never deleted ───────────────────────────────────────────
update public.target_contract
   set status = 'abandoned', closed_at = coalesce(closed_at, now()),
       superseded_by = (select id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30'),
       close_reason = 'Withdrawn by the founder (24 Sep 2026): "1,000 suppliers / 1,000 customers" is no longer a target; '
                      || 'customers launch in January 2027 on the year-one plan (FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30).'
 where contract_key = 'CUSTOMERS_1000_BY_2027_10_01' and status = 'active';
