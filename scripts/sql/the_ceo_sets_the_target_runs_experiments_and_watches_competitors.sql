-- THE CEO SETS AN EVIDENCE-BASED TARGET, RUNS EXPERIMENTS AGAINST THE PLAN'S UNKNOWNS, WATCHES THE COMPETITORS
-- AND MOVES THE COMPANY THROUGH MEASURED STAGES.
-- Seat: ceo, with marketing and sales_engineer. 23 Sep 2026. The readiness audit scored "ambition and drive" 0.5/5.
-- Needs, in this order: every_seat_duty_has_an_owner_a_clock_and_a_check.sql (#901: seat_duty, fn_seat_duty_reason,
-- fn_seat_duty_cross_review) and the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql (#906: the
-- ceo>accountant deliberation.review kind, fn_ceo_target_forecast).
--
-- WHAT WAS MEASURED (production, 23 Sep 2026 19:30 UTC)
--   * The audit's counts were wrong, and its cause was right. target_contract holds 4 rows, target_driver 11,
--     target_verdict 4 (all hand-written 7 Sep, AT_RISK / CANNOT_ASSESS) and competitor 27. What was missing: nothing
--     compares actuals with a target on a clock, nothing acts on a miss, and no experiment log exists.
--   * Contract 21 is still AED 1,000,000 by 31 Aug 2027. The founder withdrew it (founder_instruction 962: "Forget the
--     AED 1M target"). The evidence-based plan (model run 23 Sep, scratchpad plan/model.csv) puts the base case at
--     AED 244,801 of cumulative reveal fees by 31 Aug 2027. That monthly path becomes the target contract here.
--   * ceo_plan has held stage 'invitations' every day since 22 Sep. fn_ceo_plan_decide stops at the first stage
--     behind plan even when that stage is held by the founder's campaign gate (lever founder_reserved), so no
--     stage below it can ever bind. The stage column also has two meanings: the company's stage and the day's
--     binding constraint.
--   * The competitor table was last verified 27 Jul 2026 and has no ServiceMarket, Justlife, TaskRight,
--     ContractorSelect or FitOutHub. Nothing re-reads a competitor's pages.
--
-- WHAT THIS ADDS
--   1. EXPERIMENTS (ceo_experiment, ceo_experiment_verdict). A seat proposes a hypothesis with a metric, a baseline
--      and a target (fn_ceo_experiment_propose). The CEO decides approve / revise / reject by reasoning
--      (ceo.experiment_approval), and the accountant challenges the call on a model of another family. An approved
--      experiment runs with an owner seat and an end date. Every week the reading is measured deterministically and
--      the CEO reasons the verdict (ceo.experiment_verdict: kept / killed / iterated). Each verdict is written to
--      seat_case_memory, the store the learning loop recalls from. Seeded with the plan's three largest unknowns:
--      reveal conversion (customer_support), B2B accounts through consented channels (sales_engineer) and the
--      category mix (marketing).
--   2. COMPETITOR WATCH (competitor_scan). Nine competitors researched on 23 Sep 2026 from their own public pages
--      are added. A marketing duty fetches each competitor's home page and pricing page once a month through
--      pg_net. A byte-identical page is recorded as unchanged. Any other page is reasoned by marketing
--      (marketing.competitor_change) against the last reading. A change in pricing, positioning or features becomes
--      a CEO task.
--   3. THE TARGET CONTRACT AND ITS DRIVERS. Contract 21 is superseded by the base-case contract. Its causal chain goes
--      in target_driver, each stage with an owner seat. Its monthly path per seat goes in target_path, from the plan's
--      per-seat KPIs. A daily duty (ceo.target_verdict) compares actual with the path in target_daily_verdict. A miss
--      beyond tolerance opens a CEO task and hands the owning seat a root-cause question (ceo.root_cause), which the
--      seat reasons. The task closes when the measure recovers.
--   4. COMPANY STAGES (ceo_company_stage, ceo_company_stage_log). Six stages, each with a measured exit milestone,
--      advanced daily and never automatically reversed. The stage decides which funnel stages may bind: in
--      supply_seeding, demand is out of scope, so the CEO never pushes buyers onto an unready marketplace.
--      fn_ceo_plan_decide now skips a stage held by a reserved decision and binds the first seat-movable stage
--      behind plan. It falls back to the held stage only when nothing movable is behind plan. ceo_plan.company_stage
--      records the stage.
--
-- DETERMINISTIC NOW / REASONED UNDER THE HOLD: every measurement, record, task, handoff, fetch and stage advance
-- acts now. Every judgement is a think() decision (fn_seat_duty_reason, stakes high), filed and held while the model
-- hold stands. Nothing here matches words.

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0. MEASURES THE PLAN NEEDS THAT fn_ceo_plan_measure DOES NOT HAVE
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- The "real" filters are the ones fn_ceo_plan_measure uses: no demo customer, no example.invalid, no demo provenance.
create or replace function public.fn_ambition_measure(p_key text, p_from timestamptz, p_to timestamptz)
returns numeric
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v numeric; v_den numeric; v_num numeric;
  -- the four highest-fee trades in the plan (61 % of the fee from 12.6 % of requests), as category_specs keys
  c_top4 constant text[] := array['fitout', 'commercial-retail-fitout', 'kitchens', 'carpentry-joinery', 'steel', 'structural-steel-fabrication'];
begin
  case p_key
  when 'fee_aed_cumulative' then
    v := public.fn_ceo_plan_measure('fee_aed', timestamptz '2026-01-01', p_to);
  when 'reveal_conversion_pct', 'top4_category_request_share_pct' then
    with i as (
      select i.id, i.category from public.inquiries i join public.customers c on c.id = i.customer_id
       where i.parent_inquiry_id is null and i.created_at >= p_from and i.created_at < p_to
         and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
         and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%'
                  or coalesce(c.email, '') ilike '%@example.invalid' or coalesce(c.phone, '') like '+9715000000%'))
    select case when p_key = 'reveal_conversion_pct' then count(*) filter (where exists (select 1 from public.quotes q where q.inquiry_id = i.id))
                else count(*) end,
           case when p_key = 'reveal_conversion_pct'
                then count(*) filter (where exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.revealed_at is not null
                                                     and t.payment_ref ~ '^(pi|ch|py)_'))
                else count(*) filter (where i.category = any (c_top4)) end
      into v_den, v_num from i;
    -- under 20 in the denominator a percentage is noise: not measurable, never zero
    v := case when v_den >= 20 then round(100.0 * v_num / v_den, 1) end;
  when 'b2b_active_accounts' then
    -- a business buyer (customers.industry set) that posted a real request in the 30 days to p_to
    select count(distinct c.id) into v from public.customers c join public.inquiries i on i.customer_id = c.id
     where nullif(btrim(coalesce(c.industry, '')), '') is not null and i.parent_inquiry_id is null
       and i.created_at >= p_to - interval '30 days' and i.created_at < p_to
       and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
       and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%' or coalesce(c.email, '') ilike '%@example.invalid');
  when 'checkout_success_pct' then
    -- a Stripe checkout that completed, over every checkout that completed or expired
    select count(*) filter (where type = 'checkout.session.completed'),
           count(*) filter (where type in ('checkout.session.completed', 'checkout.session.expired'))
      into v_num, v_den from public.stripe_events where first_seen_at >= p_from and first_seen_at < p_to;
    v := case when v_den >= 20 then round(100.0 * v_num / v_den, 1) end;
  when 'reveals_paid_30d' then
    v := public.fn_ceo_plan_measure('reveals_paid', p_to - interval '30 days', p_to);
  when 'fee_aed_30d' then
    v := public.fn_ceo_plan_measure('fee_aed', p_to - interval '30 days', p_to);
  when 'registrations_verified_cumulative' then
    v := public.fn_ceo_plan_measure('registrations_verified', timestamptz '2026-01-01', p_to);
  when 'reveals_paid_cumulative' then
    v := public.fn_ceo_plan_measure('reveals_paid', timestamptz '2026-01-01', p_to);
  else
    v := public.fn_ceo_plan_measure(p_key, p_from, p_to);   -- raises on an unknown key
  end case;
  return v;
end $fn$;
revoke execute on function public.fn_ambition_measure(text, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ambition_measure(text, timestamptz, timestamptz) to service_role;

-- A CEO task the seat opens itself (no founder command behind it: command_id stays null).
create or replace function public.fn_ceo_task_open(p_title text, p_detail text)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  insert into public.ceo_task (title, detail, state) values (left(p_title, 300), left(p_detail, 8000), 'open') returning task_id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_ceo_task_open(text, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_task_open(text, text) to service_role;

-- The choice think() returned, checked against the question's own options. A non-answer RAISES, so
-- fn_reason_held_resolve leaves the question to be reasoned again rather than marking it applied.
create or replace function public.fn_ambition_choice(p_id bigint, p_result jsonb)
returns text
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v text := p_result->'decision'->>'choice';
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v) then
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v, 'no choice'), r.surface, p_id;
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_ambition_choice(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_ambition_fields(p_result jsonb)
returns jsonb language sql immutable security definer set search_path to 'public', 'pg_temp'
as $fn$ select coalesce((select jsonb_object_agg(k, coalesce(v->>'value', v #>> '{}')) from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) f(k, v)), '{}'::jsonb) $fn$;
revoke execute on function public.fn_ambition_fields(jsonb) from public, anon, authenticated;

-- Fields a held question must fill beside its choice.
create or replace function public.fn_ambition_ask_fields(p_held bigint, p_fields jsonb)
returns void language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ update public.reasoning_held_question set request = jsonb_set(request, '{decision,fields}', p_fields) where id = p_held $fn$;
revoke execute on function public.fn_ambition_ask_fields(bigint, jsonb) from public, anon, authenticated;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 1. THE HYPOTHESIS AND EXPERIMENT LOG
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.ceo_experiment (
  id                bigserial primary key,
  key               text not null unique check (key ~ '^[a-z0-9_]+$'),
  proposed_by       text not null references public.org_role (role_id),
  owner_seat        text references public.org_role (role_id),
  hypothesis        text not null check (btrim(hypothesis) <> ''),
  metric_key        text not null,
  metric_definition text not null,
  baseline          numeric,                       -- null = not measured yet (said in baseline_note)
  baseline_note     text not null,
  target            numeric not null,
  direction         text not null default 'min' check (direction in ('min', 'max')),
  approach          text not null,
  starts_on         date not null,
  days              integer not null check (days between 7 and 365),
  ends_on           date,
  status            text not null default 'proposed' check (status in ('proposed', 'approved', 'running', 'rejected', 'kept', 'killed')),
  iteration         integer not null default 1,
  approval_held_id  bigint,
  approval          jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  closed_at         timestamptz
);
alter table public.ceo_experiment enable row level security;
drop policy if exists ceo_experiment_service_role_only on public.ceo_experiment;
create policy ceo_experiment_service_role_only on public.ceo_experiment as permissive for all to public using (false) with check (false);
revoke all on public.ceo_experiment from anon, authenticated;
revoke all on sequence public.ceo_experiment_id_seq from anon, authenticated;

create table if not exists public.ceo_experiment_verdict (
  experiment_id bigint not null references public.ceo_experiment (id) on delete cascade,
  week          date not null,
  iteration     integer not null,
  reading       numeric,
  reading_from  timestamptz not null,
  reading_to    timestamptz not null,
  held_id       bigint,
  decision      text check (decision in ('kept', 'killed', 'iterated')),
  fields        jsonb,
  reasoning     text,
  model         text,
  decided_at    timestamptz,
  created_at    timestamptz not null default now(),
  primary key (experiment_id, week)
);
alter table public.ceo_experiment_verdict enable row level security;
drop policy if exists ceo_experiment_verdict_service_role_only on public.ceo_experiment_verdict;
create policy ceo_experiment_verdict_service_role_only on public.ceo_experiment_verdict as permissive for all to public using (false) with check (false);
revoke all on public.ceo_experiment_verdict from anon, authenticated;

-- A seat proposes (or, after "revise", re-proposes) a hypothesis. The metric must be one the estate can measure.
create or replace function public.fn_ceo_experiment_propose(p_seat text, p_key text, p_hypothesis text, p_metric_key text,
  p_metric_definition text, p_baseline numeric, p_baseline_note text, p_target numeric, p_direction text, p_approach text,
  p_starts_on date, p_days integer)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare e public.ceo_experiment; v_held bigint;
begin
  if not exists (select 1 from public.org_role where role_id = p_seat and status = 'active') then
    raise exception 'a hypothesis is proposed by an active seat, not %', p_seat;
  end if;
  perform public.fn_ambition_measure(p_metric_key, now() - interval '1 day', now());   -- raises on a metric nobody can measure
  select * into e from public.ceo_experiment where key = p_key for update;
  if found and e.status <> 'proposed' then
    return e.id;                                   -- decided already: a new hypothesis takes a new key
  end if;
  insert into public.ceo_experiment (key, proposed_by, hypothesis, metric_key, metric_definition, baseline, baseline_note,
                                     target, direction, approach, starts_on, days)
  values (p_key, p_seat, p_hypothesis, p_metric_key, p_metric_definition, p_baseline, p_baseline_note,
          p_target, coalesce(p_direction, 'min'), p_approach, p_starts_on, p_days)
  on conflict (key) do update set hypothesis = excluded.hypothesis, metric_key = excluded.metric_key,
       metric_definition = excluded.metric_definition, baseline = excluded.baseline, baseline_note = excluded.baseline_note,
       target = excluded.target, direction = excluded.direction, approach = excluded.approach, starts_on = excluded.starts_on,
       days = excluded.days, iteration = ceo_experiment.iteration + 1, approval_held_id = null, updated_at = now()
  returning * into e;

  v_held := public.fn_seat_duty_reason('ceo', 'ceo.experiment_approval',
    'A seat proposes an experiment against one of the plan''s unknowns. As the chief executive, judge the approach: '
      || 'is the hypothesis falsifiable, is the metric the right one and honestly measurable, are the baseline and '
      || 'target realistic against the plan, and is it safe for customers, suppliers and the founder''s rules? '
      || 'Approve it, send it back for revision, or reject it.',
    ('[{"id":"approve","meaning":"the approach is sound; run it with an owner and an end date"},'
    || '{"id":"revise","meaning":"worth testing, but the metric, target, duration or approach must change first"},'
    || '{"id":"reject","meaning":"not worth the company''s effort or not safe to run"}]')::jsonb,
    jsonb_build_object('experiment', to_jsonb(e) - 'approval', 'reading_now', public.fn_ambition_measure(e.metric_key, now() - interval '30 days', now()),
                       'company_stage', (select stage from public.ceo_company_stage_log where left_at is null order by id desc limit 1)),
    jsonb_build_object('experiment_id', e.id, 'iteration', e.iteration), 'ceo_exp_approve:' || e.id || ':' || e.iteration);
  perform public.fn_ambition_ask_fields(v_held, jsonb_build_array(
    jsonb_build_object('key', 'owner_seat', 'question', 'the seat that runs it (sales_engineer, customer_support, accountant, it_engineer or marketing)'),
    jsonb_build_object('key', 'days', 'question', 'how many days it runs before a final verdict (7 to 365)'),
    jsonb_build_object('key', 'conditions', 'question', 'the conditions, or for revise the change required')));
  update public.ceo_experiment set approval_held_id = v_held where id = e.id;
  return e.id;
end $fn$;
revoke execute on function public.fn_ceo_experiment_propose(text, text, text, text, text, numeric, text, numeric, text, text, date, integer) from public, anon, authenticated;
grant execute on function public.fn_ceo_experiment_propose(text, text, text, text, text, numeric, text, numeric, text, text, date, integer) to service_role;

create or replace function public.fn_reason_apply_ceo__experiment_approval(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; e public.ceo_experiment; v_choice text; v_f jsonb; v_review jsonb; v_owner text; v_days int;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  select * into e from public.ceo_experiment where id = (r.subject->>'experiment_id')::bigint for update;
  if not found or e.status <> 'proposed' or e.iteration <> (r.subject->>'iteration')::int then
    return jsonb_build_object('applied', true, 'already', 'the experiment moved on');
  end if;
  v_f := public.fn_ambition_fields(p_result);
  v_owner := case when exists (select 1 from public.org_role where role_id = v_f->>'owner_seat' and status = 'active' and role_id <> 'ceo')
                  then v_f->>'owner_seat' else e.proposed_by end;
  v_days := case when coalesce(v_f->>'days', '') ~ '^\d{1,3}$' and (v_f->>'days')::int between 7 and 365 then (v_f->>'days')::int else e.days end;

  -- THE CHALLENGE: the accountant reviews every approval call on a model of another family.
  v_review := public.fn_seat_duty_cross_review('ceo.experiment_approval', 'ceo', 'accountant',
    'Challenge the chief executive''s call on this experiment before it runs.',
    jsonb_build_object('experiment', to_jsonb(e) - 'approval'),
    jsonb_build_object('call', v_choice, 'fields', v_f, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000)),
    p_result, 'ceo_experiment', e.id::text || ':' || e.iteration);

  update public.ceo_experiment
     set approval = jsonb_build_object('decision', v_choice, 'fields', v_f, 'reasoning', left(coalesce(p_result->>'answer', ''), 6000),
                                       'model', p_result->>'model', 'review', v_review, 'decided_at', now()),
         status = case v_choice when 'approve' then case when e.starts_on <= v_today then 'running' else 'approved' end
                                when 'reject' then 'rejected' else 'proposed' end,
         owner_seat = case when v_choice = 'approve' then v_owner else owner_seat end,
         days = v_days,
         starts_on = case when v_choice = 'approve' then greatest(e.starts_on, v_today) else starts_on end,
         ends_on = case when v_choice = 'approve' then greatest(e.starts_on, v_today) + v_days end,
         closed_at = case when v_choice = 'reject' then now() end,
         updated_at = now()
   where id = e.id;
  return jsonb_build_object('applied', true, 'experiment', e.key, 'choice', v_choice, 'owner', v_owner, 'review', v_review);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__experiment_approval(bigint, jsonb) from public, anon, authenticated;

-- THE WEEKLY REVIEW: measure every live experiment now; the verdict is reasoned.
create or replace function public.fn_ceo_experiment_review()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare e public.ceo_experiment; v_week date := date_trunc('week', (now() at time zone 'Asia/Dubai'))::date;
  v_today date := (now() at time zone 'Asia/Dubai')::date; v_from timestamptz; v_reading numeric; v_held bigint;
  n_started int := 0; n_measured int := 0; n_filed int := 0;
begin
  -- an approved experiment starts on its day
  update public.ceo_experiment set status = 'running', updated_at = now() where status = 'approved' and starts_on <= v_today;
  get diagnostics n_started = row_count;

  for e in select * from public.ceo_experiment where status = 'running' order by id loop
    v_from := (e.starts_on::timestamp at time zone 'Asia/Dubai');
    v_reading := public.fn_ambition_measure(e.metric_key, v_from, now());
    insert into public.ceo_experiment_verdict (experiment_id, week, iteration, reading, reading_from, reading_to)
    values (e.id, v_week, e.iteration, v_reading, v_from, now())
    on conflict (experiment_id, week) do update set reading = excluded.reading, reading_to = excluded.reading_to
      where ceo_experiment_verdict.decided_at is null;
    n_measured := n_measured + 1;
    if (select held_id from public.ceo_experiment_verdict where experiment_id = e.id and week = v_week) is null then
      v_held := public.fn_seat_duty_reason('ceo', 'ceo.experiment_verdict',
        'The weekly verdict on a running experiment. Read the hypothesis, its baseline and target, this week''s measured '
          || 'reading and the earlier verdicts. Keep it (it is working, or too early to judge and still sound), kill it '
          || '(the evidence refutes it or it costs more than it can return), or iterate it (change the approach and run '
          || 'again). A reading of null means the metric is not measurable yet: say whether that is expected.',
        ('[{"id":"kept","meaning":"keep running it as it is (after its end date: the hypothesis held and the change stays)"},'
        || '{"id":"killed","meaning":"stop it: the evidence refutes it or it is not worth continuing"},'
        || '{"id":"iterated","meaning":"change the approach and run the next iteration"}]')::jsonb,
        jsonb_build_object('experiment', to_jsonb(e) - 'approval', 'reading', v_reading, 'week', v_week,
                           'days_left', e.ends_on - v_today, 'past_end_date', v_today >= e.ends_on,
                           'earlier', (select coalesce(jsonb_agg(jsonb_build_object('week', week, 'reading', reading, 'decision', decision, 'fields', fields) order by week), '[]'::jsonb)
                                         from public.ceo_experiment_verdict where experiment_id = e.id and week < v_week)),
        jsonb_build_object('experiment_id', e.id, 'week', v_week), 'ceo_exp_verdict:' || e.id || ':' || v_week);
      perform public.fn_ambition_ask_fields(v_held, jsonb_build_array(
        jsonb_build_object('key', 'lesson', 'question', 'what this week teaches, in one sentence a future decision can reuse'),
        jsonb_build_object('key', 'next_step', 'question', 'for iterated: the changed approach; otherwise the next action')));
      update public.ceo_experiment_verdict set held_id = v_held where experiment_id = e.id and week = v_week;
      n_filed := n_filed + 1;
    end if;
  end loop;
  return jsonb_build_object('week', v_week, 'started', n_started, 'measured', n_measured, 'verdicts_filed', n_filed);
end $fn$;
revoke execute on function public.fn_ceo_experiment_review() from public, anon, authenticated;
grant execute on function public.fn_ceo_experiment_review() to service_role;

create or replace function public.fn_reason_apply_ceo__experiment_verdict(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; e public.ceo_experiment; v public.ceo_experiment_verdict; v_choice text; v_f jsonb;
  v_final boolean; v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  select * into e from public.ceo_experiment where id = (r.subject->>'experiment_id')::bigint for update;
  select * into v from public.ceo_experiment_verdict where experiment_id = e.id and week = (r.subject->>'week')::date for update;
  if v.decided_at is not null or e.status <> 'running' then return jsonb_build_object('applied', true, 'already', 'decided'); end if;
  v_f := public.fn_ambition_fields(p_result);
  v_final := v_choice = 'killed' or (v_choice = 'kept' and v_today >= e.ends_on);

  update public.ceo_experiment_verdict set decision = v_choice, fields = v_f, reasoning = left(coalesce(p_result->>'answer', ''), 6000),
         model = p_result->>'model', decided_at = now()
   where experiment_id = e.id and week = v.week;
  update public.ceo_experiment
     set status = case when v_choice = 'killed' then 'killed' when v_final then 'kept' else 'running' end,
         iteration = iteration + case when v_choice = 'iterated' then 1 else 0 end,
         approach = case when v_choice = 'iterated' and coalesce(v_f->>'next_step', '') <> '' then v_f->>'next_step' else approach end,
         closed_at = case when v_final then now() end, updated_at = now()
   where id = e.id;

  -- THE CASE MEMORY: every verdict is a case the owner seat (and the CEO) recall next time; final ones carry the outcome.
  insert into public.seat_case_memory (seat, case_kind, source_table, source_id, trade, situation, decision, reasoning, outcome,
                                       finalised, finalised_at, lessons, opened_at)
  values (coalesce(e.owner_seat, e.proposed_by), 'experiment', 'ceo_experiment_verdict', e.id || ':' || v.week,
          null,
          left(format('Experiment %s (iteration %s): %s Metric %s, baseline %s, target %s (%s). Reading %s over %s to %s.',
                      e.key, e.iteration, e.hypothesis, e.metric_key, coalesce(e.baseline::text, 'not measured'), e.target, e.direction,
                      coalesce(v.reading::text, 'not measurable'), v.reading_from::date, v.reading_to::date), 4000),
          v_choice, left(coalesce(p_result->>'answer', ''), 4000),
          case when v_final then format('%s: the hypothesis %s at a reading of %s against a target of %s.', v_choice,
                                        case when v_choice = 'kept' then 'held' else 'failed' end, coalesce(v.reading::text, 'unmeasured'), e.target) end,
          v_final, case when v_final then now() end,
          case when coalesce(v_f->>'lesson', '') <> '' then array[v_f->>'lesson'] else '{}'::text[] end, v.created_at)
  on conflict (source_table, source_id) do update set decision = excluded.decision, reasoning = excluded.reasoning,
    outcome = excluded.outcome, finalised = excluded.finalised, finalised_at = excluded.finalised_at, lessons = excluded.lessons,
    updated_at = now();
  return jsonb_build_object('applied', true, 'experiment', e.key, 'choice', v_choice, 'final', v_final);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__experiment_verdict(bigint, jsonb) from public, anon, authenticated;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 2. THE COMPETITOR WATCH
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
alter table public.competitor add column if not exists pricing_url text;
alter table public.competitor add column if not exists watch jsonb;             -- the latest reasoned reading
alter table public.competitor add column if not exists watched boolean not null default true;

create table if not exists public.competitor_scan (
  id            bigserial primary key,
  competitor_id bigint not null references public.competitor (id) on delete cascade,
  page_kind     text not null check (page_kind in ('home', 'pricing')),
  url           text not null,
  requested_at  timestamptz not null default now(),
  request_id    bigint,
  status        text not null default 'fetching' check (status in ('fetching', 'failed', 'unchanged', 'fetched', 'reasoned')),
  http_status   integer,
  content_hash  text,
  page_text     text,
  error         text,
  held_id       bigint,
  decision      text,
  fields        jsonb,
  reasoning     text,
  model         text,
  task_id       bigint,
  decided_at    timestamptz
);
create index if not exists competitor_scan_latest on public.competitor_scan (competitor_id, page_kind, requested_at desc);
alter table public.competitor_scan enable row level security;
drop policy if exists competitor_scan_service_role_only on public.competitor_scan;
create policy competitor_scan_service_role_only on public.competitor_scan as permissive for all to public using (false) with check (false);
revoke all on public.competitor_scan from anon, authenticated;
revoke all on sequence public.competitor_scan_id_seq from anon, authenticated;

-- A fetched page: identical bytes are recorded as unchanged (identity, not judgement); anything else is reasoned.
create or replace function public.fn_competitor_scan_ingest(p_scan_id bigint, p_status integer, p_content text, p_error text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare s public.competitor_scan; c public.competitor; v_text text; v_hash text; prev public.competitor_scan; v_held bigint; v_first boolean;
begin
  select * into s from public.competitor_scan where id = p_scan_id for update;
  if not found or s.status <> 'fetching' then return jsonb_build_object('scan', p_scan_id, 'skipped', true); end if;
  select * into c from public.competitor where id = s.competitor_id;
  if p_status is null or p_status not between 200 and 399 or coalesce(btrim(p_content), '') = '' then
    update public.competitor_scan set status = 'failed', http_status = p_status, error = left(coalesce(p_error, 'empty page'), 500) where id = s.id;
    return jsonb_build_object('scan', s.id, 'status', 'failed');
  end if;
  v_text := regexp_replace(p_content, '<script[^>]*>.*?</script>', ' ', 'gi');
  v_text := regexp_replace(v_text, '<style[^>]*>.*?</style>', ' ', 'gi');
  v_text := regexp_replace(v_text, '<[^>]+>', ' ', 'g');
  v_text := replace(replace(replace(replace(v_text, '&nbsp;', ' '), '&amp;', '&'), '&#39;', ''''), '&quot;', '"');
  v_text := left(btrim(regexp_replace(v_text, '\s+', ' ', 'g')), 20000);
  v_hash := md5(v_text);

  select * into prev from public.competitor_scan
   where competitor_id = s.competitor_id and page_kind = s.page_kind and id <> s.id and status in ('unchanged', 'fetched', 'reasoned')
   order by requested_at desc limit 1;
  v_first := prev.id is null;
  if not v_first and prev.content_hash = v_hash then
    update public.competitor_scan set status = 'unchanged', http_status = p_status, content_hash = v_hash where id = s.id;
    update public.competitor set verified_at = (now() at time zone 'Asia/Dubai')::date where id = c.id;
    return jsonb_build_object('scan', s.id, 'status', 'unchanged');
  end if;

  update public.competitor_scan set status = 'fetched', http_status = p_status, content_hash = v_hash, page_text = v_text where id = s.id;
  v_held := public.fn_seat_duty_reason('marketing', 'marketing.competitor_change',
    case when v_first then
      'Read this competitor''s public ' || s.page_kind || ' page for the first time and record its pricing, positioning and features '
        || 'as they stand, so later readings can be compared with it. Say unreadable if the page carries no usable content.'
    else
      'Compare this competitor''s public ' || s.page_kind || ' page with the last reading. Decide whether its pricing, positioning '
        || 'or features changed in a way that matters to QuotesDone (a construction and home-services quotation marketplace in the UAE: '
        || 'best-3 comparison, 3 per cent reveal fee paid by the buyer, no supplier commission). Cosmetic or rotating content is not a change.'
    end,
    case when v_first then
      '[{"id":"profiled","meaning":"the page was read and its pricing, positioning and features are recorded"},{"id":"unreadable","meaning":"the page has no usable content (blocked, empty or only a script shell)"}]'::jsonb
    else
      '[{"id":"no_material_change","meaning":"nothing that matters to us changed"},{"id":"changed","meaning":"pricing, positioning or features changed in a way the CEO should act on"},{"id":"unreadable","meaning":"the page has no usable content (blocked, empty or only a script shell)"}]'::jsonb
    end,
    jsonb_build_object('competitor', to_jsonb(c) - 'watch', 'page_kind', s.page_kind, 'url', s.url, 'page_text', left(v_text, 12000),
                       'last_reading', case when v_first then null else jsonb_build_object('fetched', prev.requested_at, 'fields', prev.fields,
                                                                                          'page_text', left(prev.page_text, 6000)) end),
    jsonb_build_object('scan_id', s.id), 'mkt_competitor:' || s.id);
  perform public.fn_ambition_ask_fields(v_held, jsonb_build_array(
    jsonb_build_object('key', 'pricing', 'question', 'who pays what, as the page states it (or "not published")'),
    jsonb_build_object('key', 'positioning', 'question', 'who it is for and what it claims, in one sentence'),
    jsonb_build_object('key', 'features', 'question', 'the features that compete with QuotesDone'),
    jsonb_build_object('key', 'what_changed', 'question', 'for changed: exactly what changed and why it matters to us')));
  update public.competitor_scan set held_id = v_held where id = s.id;
  return jsonb_build_object('scan', s.id, 'status', 'fetched', 'held', v_held, 'first', v_first);
end $fn$;
revoke execute on function public.fn_competitor_scan_ingest(bigint, integer, text, text) from public, anon, authenticated;
grant execute on function public.fn_competitor_scan_ingest(bigint, integer, text, text) to service_role;

-- The duty: collect what pg_net fetched, then start the month's fetches (10 pages a run, each page every 30 days).
-- pg_net sends a request when the calling transaction commits; its response is kept about six hours, so an
-- hourly duty always collects it, and one not collected in six hours is recorded as failed.
create or replace function public.fn_marketing_competitor_scan()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare s record; r record; c record; n_in int := 0; n_out int := 0; v_req bigint;
begin
  for s in select * from public.competitor_scan where status = 'fetching' and request_id is not null order by id loop
    select status_code, content, error_msg, timed_out into r from net._http_response where id = s.request_id;
    if found then
      perform public.fn_competitor_scan_ingest(s.id, case when coalesce(r.timed_out, false) then null else r.status_code end, r.content,
                                               coalesce(r.error_msg, case when r.timed_out then 'timed out' end));
      n_in := n_in + 1;
    elsif s.requested_at < now() - interval '6 hours' then
      perform public.fn_competitor_scan_ingest(s.id, null, null, 'no response within six hours');
      n_in := n_in + 1;
    end if;
  end loop;

  for c in
    select x.id, x.kind, p.page_kind, p.url
      from public.competitor x
      cross join lateral (values ('home', x.url), ('pricing', x.pricing_url)) p(page_kind, url)
     where x.watched and x.kind <> 'incumbent_behaviour' and p.url ~ '^https://'
       and not exists (select 1 from public.competitor_scan z where z.competitor_id = x.id and z.page_kind = p.page_kind
                         and (z.status = 'fetching' or z.requested_at > now() - interval '30 days'))
     order by x.id, p.page_kind limit 10
  loop
    v_req := net.http_get(c.url, '{}'::jsonb,
               jsonb_build_object('User-Agent', 'QuotesDone market watch (+https://www.quotesdone.ae)', 'Accept', 'text/html'), 20000);
    insert into public.competitor_scan (competitor_id, page_kind, url, request_id) values (c.id, c.page_kind, c.url, v_req);
    n_out := n_out + 1;
  end loop;
  return jsonb_build_object('collected', n_in, 'requested', n_out);
end $fn$;
revoke execute on function public.fn_marketing_competitor_scan() from public, anon, authenticated;
grant execute on function public.fn_marketing_competitor_scan() to service_role;

create or replace function public.fn_reason_apply_marketing__competitor_change(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; s public.competitor_scan; c public.competitor; v_choice text; v_f jsonb; v_task bigint;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  select * into s from public.competitor_scan where id = (r.subject->>'scan_id')::bigint for update;
  if s.decided_at is not null then return jsonb_build_object('applied', true, 'already', s.decision); end if;
  select * into c from public.competitor where id = s.competitor_id;
  v_f := public.fn_ambition_fields(p_result);
  if v_choice = 'changed' then
    v_task := public.fn_ceo_task_open('Competitor change: ' || c.name || ' (' || s.page_kind || ' page)',
      format(E'Marketing read %s on %s and judged that it changed in a way that matters to us.\n\nWhat changed: %s\nPricing: %s\nPositioning: %s\nFeatures: %s\n\nMarketing''s reasoning: %s\n\nDecide the company''s response: pricing is proposed to the founder only through the weekly pricing monitor.',
             s.url, s.requested_at::date, coalesce(v_f->>'what_changed', '?'), coalesce(v_f->>'pricing', '?'), coalesce(v_f->>'positioning', '?'),
             coalesce(v_f->>'features', '?'), left(coalesce(p_result->>'answer', ''), 2000)));
  end if;
  update public.competitor_scan set status = 'reasoned', decision = v_choice, fields = v_f, reasoning = left(coalesce(p_result->>'answer', ''), 6000),
         model = p_result->>'model', task_id = v_task, decided_at = now()
   where id = s.id;
  if v_choice in ('profiled', 'changed', 'no_material_change') then
    update public.competitor set verified_at = (now() at time zone 'Asia/Dubai')::date,
           watch = coalesce(watch, '{}'::jsonb) || jsonb_build_object(s.page_kind, jsonb_build_object('read_at', now(), 'decision', v_choice) || v_f)
     where id = c.id;
  end if;
  return jsonb_build_object('applied', true, 'competitor', c.name, 'choice', v_choice, 'ceo_task', v_task);
end $fn$;
revoke execute on function public.fn_reason_apply_marketing__competitor_change(bigint, jsonb) from public, anon, authenticated;

-- The competitors researched on 23 Sep 2026 from their own pages. What a page did not say is written as not published.
insert into public.competitor (name, url, kind, what_they_do, business_model, overlap, strength, weakness, offers_anonymity,
                               threat_level, verified_at, source_url, pricing_url) values
  ('ServiceMarket', 'https://servicemarket.com', 'marketplace',
   'Home-services marketplace for the Middle East: more than 25 services in Dubai (cleaning, moving, maintenance, pest control); customers get quotes from selected companies or book directly.',
   'Free for customers, who pay the provider directly after the work. The partner fee is not published.',
   'Very high: its FAQ promises at least three quotes from selected companies within 24 hours, the same multi-quote comparison we offer for home services.',
   'Established brand, many categories, an app, first-booking discounts, 3+ quotes in 24 hours.',
   'Consumer home services rather than construction and procurement; no buyer anonymity or structured best-3 comparison shown; supplier model not public.',
   false, 'high', date '2026-09-23', 'https://servicemarket.com/en/faqs', null),
  ('Bark', 'https://www.bark.com', 'global_platform',
   'Global lead marketplace: a customer posts a request and professionals buy credits to contact the customers they choose.',
   'Professionals buy credit packs and spend credits per lead; the pricing page says no commission. The price varies by service, job value and local demand.',
   'The same post-a-request pattern, but the UAE is not in its pricing page''s country list and /en/ae/ returned 404 on 23 Sep 2026.',
   'Global scale and a proven pay-per-lead model.',
   'Not operating in the UAE as read; suppliers pay whether or not they win; the customer''s details reach every paying professional.',
   false, 'low', date '2026-09-23', 'https://www.bark.com/en/us/sellers/pricing/', 'https://www.bark.com/en/us/sellers/pricing/'),
  ('Justlife', 'https://www.justlife.com', 'marketplace',
   'Home-services app (cleaning, salon, healthcare, home repair, pest control) in Dubai, Abu Dhabi, Sharjah, Ajman, Jeddah and Riyadh.',
   'Not published.',
   'Partial: the same home-repair and maintenance categories, but instant booking rather than quote comparison.',
   'Same-day booking in under a minute, a wide catalogue, UAE and KSA presence.',
   'No quote comparison, no construction or procurement scope, no choice of supplier by price.',
   null, 'medium', date '2026-09-23', 'https://www.justlife.com/', null),
  ('Procure Axis', 'https://www.procureaxis.com', 'adjacent',
   'A buying office in China (Xiamen ISEUP Procurement Management) sourcing from Chinese manufacturing hubs for importers, wholesalers and e-commerce sellers.',
   'Not published.',
   'Low: import sourcing from China, not a UAE local-supplier quotation marketplace.',
   'Sourcing teams in China and South and Southeast Asia.',
   'No UAE supplier network, no home or construction services, not a two-sided quotation marketplace.',
   null, 'low', date '2026-09-23', 'https://www.procureaxis.com/aboutus.html', null),
  ('FitOutHub', 'https://fitout-hub.com', 'marketplace',
   'Calls itself the UAE''s first AI-powered fit-out marketplace: owners post projects and contractors bid blind, with escrow and milestone release.',
   'Not published (escrow is mentioned, no fee).',
   'The closest model found: buyers see prices and portfolios, not identities, and the contractor is revealed only after the client picks a bid.',
   'Blind bidding, escrow and milestone payments, an AI positioning.',
   'Fit-out only as read; no public pricing; the contractor is hidden from the buyer rather than the buyer from suppliers.',
   false, 'high', date '2026-09-23', 'https://fitout-hub.com/', null),
  ('TaskRight', 'https://taskright.ae', 'marketplace',
   'UAE marketplace matching homeowners with verified providers for AC, plumbing, cleaning, electrical and renovation; quotes are compared over WhatsApp.',
   'Free for customers; providers pay no commission and a flat subscription once they get leads (amount not published).',
   'High: the same UAE home and renovation categories, a no-commission pitch to suppliers, multi-quote comparison.',
   'Zero-commission message, fast response, WhatsApp-native.',
   'Subscription price not public; no structured comparison or anonymity shown; quotes handled in chats.',
   false, 'high', date '2026-09-23', 'https://taskright.ae/', null),
  ('ContractorSelect.me', 'https://www.contractorselect.me', 'marketplace',
   'UAE marketplace where clients post residential, commercial, retail and exhibition projects and receive proposals from vetted contractors.',
   'Free for clients with no success fee; contractors pay only when they win, at a rate that falls as they grow (rate not published).',
   'High: construction and fit-out quotations in the UAE, contact details shown only to contractors the client approves.',
   'Pay-on-win for contractors; the client controls who sees their details.',
   'No public rate card; privacy covers contact details, not full buyer anonymity.',
   false, 'high', date '2026-09-23', 'https://www.contractorselect.me/', null),
  ('Renov.at', 'https://renov.at', 'marketplace',
   'UAE renovation marketplace: homeowners post kitchen, bathroom, flooring or full-apartment projects and compare proposals from licensed contractors; has a cost calculator.',
   'Not published; posting is free for homeowners.',
   'High for residential renovation quote comparison.',
   'Renovation focus, a cost calculator, project showcases.',
   'No published model; homeowners vet contractors themselves; no anonymity shown.',
   null, 'medium', date '2026-09-23', 'https://renov.at/', null),
  ('Urban Company', 'https://www.urbancompany.com/dubai', 'marketplace',
   'Books cleaning, maids, beauty, repairs, AC, painting and moving in Dubai at fixed listed prices.',
   'Customers pay fixed listed prices; the provider-side model is not published.',
   'Partial: home repair and improvement in Dubai, but fixed-price booking rather than quotes.',
   'Strong brand and trust signals, fixed prices, a large catalogue.',
   'No quote comparison, no construction or procurement scope, no supplier choice.',
   null, 'medium', date '2026-09-23', 'https://www.urbancompany.com/dubai', null)
on conflict (name) do update set url = excluded.url, kind = excluded.kind, what_they_do = excluded.what_they_do,
  business_model = excluded.business_model, overlap = excluded.overlap, strength = excluded.strength, weakness = excluded.weakness,
  offers_anonymity = excluded.offers_anonymity, threat_level = excluded.threat_level, verified_at = excluded.verified_at,
  source_url = excluded.source_url, pricing_url = excluded.pricing_url;
update public.competitor
   set pricing_url = 'https://www.rfqsnow.com/pricing',
       business_model = 'Buyers free. Suppliers pay AED 1,200 a month for priority access (2 RFQs), or unlock one RFQ for AED 800 (under AED 500k), AED 2,500 (AED 500k-5M) or AED 6,000-8,000 (over AED 5M); verification AED 1,500 once (pricing page, 23 Sep 2026).',
       verified_at = date '2026-09-23'
 where name = 'RFQsNow';

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 3. THE TARGET CONTRACT, ITS DRIVERS PER SEAT, AND THE DAILY VERDICT
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
alter table public.target_driver add column if not exists owner_seat text references public.org_role (role_id);

insert into public.target_contract (contract_key, version, status, objective, business_reason, priority, accountable_owner,
  metric_definition, metric_unit, metric_population, authoritative_source, measure_sql, baseline_value, baseline_state, baseline_at,
  baseline_note, desired_value, desired_basis, deadline, timezone, measurement_cadence, guardrails, assumptions, confidence_note,
  escalation_threshold, success_definition, evidence_required, created_by, activated_at)
select 'REVEAL_FEES_BASE_PATH_BY_2027_08_31', 1, 'active',
  'Reach AED 244,801 of cumulative reveal fees by 31 August 2027 along the base-case monthly path: AED 5,297 in November 2026, rising to AED 42,931 in August 2027.',
  'The founder withdrew the AED 1M target (founder_instruction 962). The evidence-based plan of 23 Sep 2026 puts the base case at AED 244,801; the company is held to that path month by month, and beats it where it can.',
  1, 'ceo',
  'Cumulative reveal fees collected through Stripe (payment_ref pi_/ch_/py_) from real customers, in AED: fn_ambition_measure(''fee_aed_cumulative'').',
  'AED', 'Every real reveal transaction since 1 Jan 2026 (demo customers and example.invalid addresses excluded).',
  'public.transactions, through fn_ceo_plan_measure(''fee_aed'').',
  'select public.fn_ambition_measure(''fee_aed_cumulative'', timestamptz ''2026-01-01'', now())',
  public.fn_ambition_measure('fee_aed_cumulative', timestamptz '2026-01-01', now()), 'measured', now(),
  'Measured live from the contract''s own measure_sql on the day it was written.',
  244801, 'cumulative', date '2027-08-31', 'Asia/Dubai', 'daily',
  (select guardrails from public.target_contract where id = 21),
  jsonb_build_array('Monthly path = the base scenario of the plan model (model.csv, 23 Sep 2026): organic demand, AED 200k of paid media over ten months, 25 new B2B accounts a month from November.',
                    'Reveal conversion 15 % of quoted requests (A22, unmeasured), average revealed quote about AED 13,000 at a 3 % fee.',
                    'Suppliers #1-1,000 pay nothing; non-response recovery and subscriptions are excluded.'),
  'Every rate is assumed until the platform carries real transactions; the three largest unknowns run as experiments (ceo_experiment).',
  'Any day on which a seat''s path metric is behind its tolerance (target_path.tolerance_pct): a CEO task and a root-cause question to that seat.',
  'Cumulative collected reveal fees reach AED 244,801 on or before 31 August 2027, read from public.transactions and reconciled against Stripe.',
  'The measure_sql result, the Stripe payout reconciliation for the same period, and the reveal-invoice count.', 'ceo', now()
where not exists (select 1 from public.target_contract where contract_key = 'REVEAL_FEES_BASE_PATH_BY_2027_08_31');

update public.target_contract
   set status = 'superseded', closed_at = now(),
       superseded_by = (select id from public.target_contract where contract_key = 'REVEAL_FEES_BASE_PATH_BY_2027_08_31'),
       close_reason = 'The founder withdrew the AED 1M target (founder_instruction 962, 23 Sep 2026). Replaced by the evidence-based base-case path.'
 where contract_key = 'REVENUE_AED_1M_BY_2027_10_01' and status = 'active';

-- the causal chain, each stage owned: value quoted -> value revealed -> fee (3 %). Rates are the plan's, assumed.
insert into public.target_driver (contract_id, stage_order, stage_key, stage_label, from_stage_key, rate, rate_source, rate_evidence, lag_days, owner_seat, note)
select c.id, x.o, x.k, x.l, x.f, x.r, 'assumed', x.e, x.lag, x.s, 'Plan model 23 Sep 2026, base scenario.'
  from public.target_contract c
  cross join (values
    (1, 'quoted_value_aed', 'AED value of the quotes on quoted requests', null, 1.0, 'The top of the chain: every quoted request''s value.', 0, 'sales_engineer'),
    (2, 'revealed_value_aed', 'AED value the buyer reveals', 'quoted_value_aed', 0.143, 'model.csv base: 77 reveals of 538 quoted requests (Aug 2027); A22, unmeasured.', 5, 'customer_support'),
    (3, 'fee_aed', 'Reveal fee collected (3 %)', 'revealed_value_aed', 0.03, 'The 3 % reveal fee, the founder''s fixed rule.', 0, 'accountant')) x(o, k, l, f, r, e, lag, s)
 where c.contract_key = 'REVEAL_FEES_BASE_PATH_BY_2027_08_31'
   and not exists (select 1 from public.target_driver d where d.contract_id = c.id);

create table if not exists public.target_path (
  contract_id   bigint not null references public.target_contract (id) on delete cascade,
  month         date not null check (extract(day from month) = 1),
  metric_key    text not null,
  owner_seat    text not null references public.org_role (role_id),
  kind          text not null check (kind in ('month', 'cumulative', 'level', 'rate')),
  value         numeric not null check (value >= 0),
  tolerance_pct numeric not null check (tolerance_pct > 0 and tolerance_pct < 100),
  source        text not null,
  primary key (contract_id, month, metric_key)
);
alter table public.target_path enable row level security;
drop policy if exists target_path_service_role_only on public.target_path;
create policy target_path_service_role_only on public.target_path as permissive for all to public using (false) with check (false);
revoke all on public.target_path from anon, authenticated;

-- One row a seat metric a month, from model.csv (base) and the plan's section 10 KPIs.
--   ceo              fee_aed_cumulative     cumulative path                         30 %
--   accountant       fee_aed                the month's fee, pro-rated              30 %
--   marketing        inquiries_posted       posted requests, pro-rated              30 %
--   sales_engineer   b2b_active_accounts    B2B accounts active in the last 30 days 30 %
--   sales_engineer   quote_coverage_pct     requests with 3+ quotes, >= 60 %        20 %
--   customer_support reveal_conversion_pct  reveals / quoted requests               20 %
--   it_engineer      checkout_success_pct   checkouts completed, >= 98 %             2 %
insert into public.target_path (contract_id, month, metric_key, owner_seat, kind, value, tolerance_pct, source)
select c.id, m.month::date, x.metric, x.seat, x.kind,
       case x.metric when 'fee_aed_cumulative' then m.cum when 'fee_aed' then m.fee when 'inquiries_posted' then m.posted
                     when 'b2b_active_accounts' then m.b2b when 'quote_coverage_pct' then 60
                     when 'reveal_conversion_pct' then round(100.0 * m.reveals / m.quoted, 1) when 'checkout_success_pct' then 98 end,
       x.tol, 'plan model 23 Sep 2026 (model.csv base; plan.md section 10)'
  from public.target_contract c
  cross join (values
    ('2026-11-01', 138, 25, 62, 9, 5297, 5297), ('2026-12-01', 209, 46, 110, 15, 10008, 15305),
    ('2027-01-01', 281, 64, 158, 22, 14613, 29918), ('2027-02-01', 355, 80, 213, 30, 19544, 49462),
    ('2027-03-01', 434, 93, 260, 37, 23474, 72936), ('2027-04-01', 500, 104, 300, 42, 26776, 99712),
    ('2027-05-01', 575, 113, 345, 49, 30184, 129896), ('2027-06-01', 663, 121, 398, 57, 33896, 163791),
    ('2027-07-01', 769, 128, 461, 66, 38079, 201870), ('2027-08-01', 897, 134, 538, 77, 42931, 244801)) m(month, posted, b2b, quoted, reveals, fee, cum)
  cross join (values
    ('fee_aed_cumulative', 'ceo', 'cumulative', 30), ('fee_aed', 'accountant', 'month', 30),
    ('inquiries_posted', 'marketing', 'month', 30), ('b2b_active_accounts', 'sales_engineer', 'level', 30),
    ('quote_coverage_pct', 'sales_engineer', 'rate', 20), ('reveal_conversion_pct', 'customer_support', 'rate', 20),
    ('checkout_success_pct', 'it_engineer', 'rate', 2)) x(metric, seat, kind, tol)
 where c.contract_key = 'REVEAL_FEES_BASE_PATH_BY_2027_08_31'
on conflict (contract_id, month, metric_key) do update set owner_seat = excluded.owner_seat, kind = excluded.kind,
  value = excluded.value, tolerance_pct = excluded.tolerance_pct, source = excluded.source;

-- The CEO's month plan follows the same path for demand, reveals and fee (supply rows stay the sales engineer's ramp).
update public.ceo_plan_month m
   set inquiries = p.posted, reveals = p.reveals, fee_aed = p.fee,
       basis = regexp_replace(coalesce(m.basis, ''), '; demand, reveals and fee: .*$', '') || '; demand, reveals and fee: base-case path (plan model 23 Sep 2026)',
       updated_at = now()
  from (values ('2026-10-01'::date, 0, 0, 0), ('2026-11-01', 138, 9, 5297), ('2026-12-01', 209, 15, 10008),
               ('2027-01-01', 281, 22, 14613), ('2027-02-01', 355, 30, 19544), ('2027-03-01', 434, 37, 23474),
               ('2027-04-01', 500, 42, 26776), ('2027-05-01', 575, 49, 30184), ('2027-06-01', 663, 57, 33896),
               ('2027-07-01', 769, 66, 38079), ('2027-08-01', 897, 77, 42931)) p(month, posted, reveals, fee)
 where m.month = p.month;

create table if not exists public.target_daily_verdict (
  day          date not null,
  contract_id  bigint not null references public.target_contract (id) on delete cascade,
  metric_key   text not null,
  owner_seat   text not null,
  expected     numeric,
  actual       numeric,
  gap_pct      numeric,
  status       text not null check (status in ('on_track', 'within_tolerance', 'miss', 'not_measurable', 'no_target', 'too_early')),
  task_id      bigint,
  handoff_id   bigint,
  created_at   timestamptz not null default now(),
  primary key (day, contract_id, metric_key)
);
alter table public.target_daily_verdict enable row level security;
drop policy if exists target_daily_verdict_service_role_only on public.target_daily_verdict;
create policy target_daily_verdict_service_role_only on public.target_daily_verdict as permissive for all to public using (false) with check (false);
revoke all on public.target_daily_verdict from anon, authenticated;

-- THE DAILY VERDICT. Pro-rated metrics are judged from day 7 of the month (a week of evidence); rates only when
-- the measure has 20+ in its denominator (fn_ambition_measure returns null below that).
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
begin
  select id into c_id from public.target_contract where contract_key = 'REVEAL_FEES_BASE_PATH_BY_2027_08_31' and status = 'active';
  if c_id is null then return jsonb_build_object('day', v_day, 'contract', null); end if;

  for p in select * from public.target_path where contract_id = c_id and month = v_m0 order by metric_key loop
    v_act := public.fn_ambition_measure(p.metric_key, v_from, p_at);
    if p.kind = 'cumulative' then
      select coalesce(max(value), 0) into v_prev_cum from public.target_path where contract_id = c_id and metric_key = p.metric_key and month < v_m0;
      v_exp := round(v_prev_cum + (p.value - v_prev_cum) * v_frac, 1);
    elsif p.kind = 'month' then v_exp := round(p.value * v_frac, 1);
    else v_exp := p.value; end if;

    v_gap := case when v_exp > 0 and v_act is not null then round(100.0 * (v_act - v_exp) / v_exp, 1) end;
    v_status := case when p.kind in ('month', 'cumulative') and extract(day from v_local) < 7 then 'too_early'
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
          format(E'On %s %s read %s against %s expected by today on the base-case path (%s%% gap, tolerance %s%%).\nOwner: %s. The root-cause question went to the owner; this task closes when the measure is back within tolerance.',
                 v_day, p.metric_key, v_act, v_exp, v_gap, p.tolerance_pct, p.owner_seat));
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
    end if;

    insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status, task_id, handoff_id)
    values (v_day, c_id, p.metric_key, p.owner_seat, v_exp, v_act, v_gap, v_status, case when v_status = 'miss' then v_task end, v_hid)
    on conflict (day, contract_id, metric_key) do update set expected = excluded.expected, actual = excluded.actual, gap_pct = excluded.gap_pct,
      status = excluded.status, task_id = coalesce(target_daily_verdict.task_id, excluded.task_id),
      handoff_id = coalesce(target_daily_verdict.handoff_id, excluded.handoff_id);
    v_out := v_out || jsonb_build_object('metric', p.metric_key, 'status', v_status, 'expected', v_exp, 'actual', v_act);
  end loop;
  return jsonb_build_object('day', v_day, 'contract_id', c_id, 'metrics', v_out, 'misses', n_miss, 'tasks_opened', n_new, 'tasks_closed', n_closed);
end $fn$;
revoke execute on function public.fn_ceo_target_daily_verdict(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_target_daily_verdict(timestamptz) to service_role;

-- The owning seat reasons the root cause (its own reasoning queue).
create or replace function public.fn_ceo_root_cause_ask(p_seat text, p_task bigint, p_miss jsonb, p_handoff bigint default null)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_held bigint;
begin
  v_held := public.fn_seat_duty_reason(p_seat, p_seat || '.root_cause',
    'A metric you own is behind the company''s target path beyond its tolerance. As the owner, find the root cause from '
      || 'the evidence, not the symptom, and say what you will change and by when the measure recovers.',
    ('[{"id":"demand_short","meaning":"not enough requests or buyers are reaching the platform"},'
    || '{"id":"supply_short","meaning":"not enough verified, responsive suppliers in the trades that are asked for"},'
    || '{"id":"conversion","meaning":"requests, quotes or comparisons are not converting at the planned rate"},'
    || '{"id":"execution","meaning":"one of our own duties failed, slipped or was not done"},'
    || '{"id":"instrumentation","meaning":"the measure is wrong or does not capture what happened"},'
    || '{"id":"plan_assumption","meaning":"the plan''s assumption for this metric is wrong and the path should be revised"}]')::jsonb,
    p_miss || jsonb_build_object('task_id', p_task, 'last_14_days', (select coalesce(jsonb_agg(jsonb_build_object('day', day, 'expected', expected, 'actual', actual, 'status', status) order by day), '[]'::jsonb)
                                                                    from public.target_daily_verdict where metric_key = p_miss->>'metric' and day > current_date - 14)),
    jsonb_build_object('task_id', p_task, 'handoff_id', p_handoff, 'metric', p_miss->>'metric'), 'root_cause:' || p_seat || ':' || p_task);
  perform public.fn_ambition_ask_fields(v_held, jsonb_build_array(
    jsonb_build_object('key', 'root_cause', 'question', 'the root cause, with the evidence it rests on'),
    jsonb_build_object('key', 'corrective_action', 'question', 'what you will change'),
    jsonb_build_object('key', 'recovery_by', 'question', 'the date the measure is back within tolerance (YYYY-MM-DD)')));
  return v_held;
end $fn$;
revoke execute on function public.fn_ceo_root_cause_ask(text, bigint, jsonb, bigint) from public, anon, authenticated;

-- The handoff handler: the receiving seat files the question in its own queue and replies with the held id.
create or replace function public.fn_seat_answers_ceo_root_cause(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; v_held bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_held := public.fn_ceo_root_cause_ask(a.agent, (a.detail->>'task_id')::bigint, a.detail - 'type' - 'from' - 'from_name' - 'to', a.id);
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'reasoning_held_id', v_held,
                            'waiting', 'the seat reasons the root cause; the CEO closes this when the answer is applied');
end $fn$;
revoke execute on function public.fn_seat_answers_ceo_root_cause(bigint) from public, anon, authenticated;

-- The answer: written onto the CEO task, the handoff closed by the CEO, challenged across families, kept as a case.
create or replace function public.fn_ceo_root_cause_applies(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text; v_f jsonb; v_task bigint; v_hid bigint; v_review jsonb;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_task := (r.subject->>'task_id')::bigint; v_hid := nullif(r.subject->>'handoff_id', '')::bigint;
  v_f := public.fn_ambition_fields(p_result);
  update public.ceo_task
     set state = case when state = 'open' then 'working' else state end,
         evidence = left(coalesce(evidence || E'\n\n', '') || format(E'Root cause from %s (%s): %s\nCorrective action: %s\nRecovery by: %s',
                           r.seat, v_choice, coalesce(v_f->>'root_cause', '?'), coalesce(v_f->>'corrective_action', '?'), coalesce(v_f->>'recovery_by', '?')), 8000)
   where task_id = v_task;
  if v_hid is not null and exists (select 1 from public.agent_actions where id = v_hid and status = 'pending') then
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(v_hid, jsonb_build_object('verified_by', 'ceo', 'root_cause', v_choice, 'fields', v_f, 'held_id', p_id));
    perform set_config('qd.handoff_closer', '', true);
  end if;
  -- the other side reads it on a model of another family: the CEO for a seat's answer, the accountant for the CEO's own
  v_review := public.fn_seat_duty_cross_review(r.seat || '.root_cause', r.seat, case when r.seat = 'ceo' then 'accountant' else 'ceo' end,
    'Challenge this root cause and corrective action for a metric behind the company''s target path.',
    jsonb_build_object('miss', r.request->'context'->'case'), jsonb_build_object('call', v_choice, 'fields', v_f,
    'reasoning', left(coalesce(p_result->>'answer', ''), 3000)), p_result, 'ceo_task', v_task::text);
  insert into public.seat_case_memory (seat, case_kind, source_table, source_id, situation, decision, reasoning, outcome, finalised, lessons, opened_at)
  values (r.seat, 'target_miss', 'ceo_task', v_task::text,
          left(format('%s behind the base-case path: %s', r.subject->>'metric', r.request->'context'->'case'), 4000),
          v_choice, left(coalesce(p_result->>'answer', ''), 4000), null, false,
          case when coalesce(v_f->>'corrective_action', '') <> '' then array[v_f->>'corrective_action'] else '{}'::text[] end, r.created_at)
  on conflict (source_table, source_id) do update set decision = excluded.decision, reasoning = excluded.reasoning, lessons = excluded.lessons, updated_at = now();
  return jsonb_build_object('applied', true, 'task', v_task, 'root_cause', v_choice, 'review', v_review);
end $fn$;
revoke execute on function public.fn_ceo_root_cause_applies(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__root_cause(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_root_cause_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_ceo__root_cause(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_sales_engineer__root_cause(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_root_cause_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__root_cause(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_customer_support__root_cause(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_root_cause_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_customer_support__root_cause(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_accountant__root_cause(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_root_cause_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_accountant__root_cause(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_it_engineer__root_cause(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_root_cause_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_it_engineer__root_cause(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_marketing__root_cause(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_root_cause_applies(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_marketing__root_cause(bigint, jsonb) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select 'ceo.root_cause', 'ceo', s,
       'A metric this seat owns is behind the base-case target path beyond tolerance: the seat reasons the root cause and the corrective action; the CEO closes it when the answer is applied.',
       'fn_seat_answers_ceo_root_cause', interval '2 days', true,
       'scripts/sql/the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql'
  from unnest(array['sales_engineer', 'customer_support', 'accountant', 'it_engineer', 'marketing']) s
on conflict (type, from_seat, to_seat) do nothing;
-- the CEO challenges a seat's root cause on a model of another family (marketing>ceo is registered already)
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, owner_file)
select 'deliberation.review', s, 'ceo',
       'The CEO challenges, on a model of another family, the root cause this seat gave for a metric behind the target path.',
       'fn_seat_deliberation_acts_on_handoff', interval '2 days',
       'scripts/sql/the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql'
  from unnest(array['sales_engineer', 'customer_support', 'accountant', 'it_engineer']) s
on conflict (type, from_seat, to_seat) do nothing;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 4. COMPANY STAGES WITH MEASURED MILESTONES, AND A PLAN THAT IS NOT PINNED TO A HELD STAGE
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.ceo_company_stage (
  stage            text primary key,
  stage_order      integer not null unique,
  meaning          text not null,
  exit_measure     text,                        -- fn_ambition_measure key; null = the last stage
  exit_threshold   numeric,
  exit_meaning     text,
  constraint_scope text[] not null              -- the funnel stages that may bind the CEO's daily plan
);
alter table public.ceo_company_stage enable row level security;
drop policy if exists ceo_company_stage_service_role_only on public.ceo_company_stage;
create policy ceo_company_stage_service_role_only on public.ceo_company_stage as permissive for all to public using (false) with check (false);
revoke all on public.ceo_company_stage from anon, authenticated;

create table if not exists public.ceo_company_stage_log (
  id          bigserial primary key,
  stage       text not null references public.ceo_company_stage (stage),
  entered_at  timestamptz not null default now(),
  left_at     timestamptz,
  exit_reading jsonb
);
create unique index if not exists ceo_company_stage_log_one_current on public.ceo_company_stage_log ((true)) where left_at is null;
alter table public.ceo_company_stage_log enable row level security;
drop policy if exists ceo_company_stage_log_service_role_only on public.ceo_company_stage_log;
create policy ceo_company_stage_log_service_role_only on public.ceo_company_stage_log as permissive for all to public using (false) with check (false);
revoke all on public.ceo_company_stage_log from anon, authenticated;
revoke all on sequence public.ceo_company_stage_log_id_seq from anon, authenticated;

insert into public.ceo_company_stage (stage, stage_order, meaning, exit_measure, exit_threshold, exit_meaning, constraint_scope) values
  ('supply_seeding', 1, 'Build verified supply before any buyer is invited: the marketplace is not opened to demand on an empty shelf.',
   'registrations_verified_cumulative', 80, '80 verified real suppliers (the plan''s 10 in each of the top 8 fee trades, counted in total)',
   array['deliverability', 'invitations', 'registrations', 'verification']),
  ('demand_opening', 2, 'Open demand to the verified supply and prove requests get three quotes.',
   'reveals_paid_cumulative', 1, 'the first real paid reveal',
   array['deliverability', 'invitations', 'registrations', 'verification', 'demand', 'quotes']),
  ('first_revenue', 3, 'Turn quoted requests into paid reveals repeatedly.',
   'reveals_paid_30d', 9, '9 paid reveals in 30 days (the base path''s November)',
   array['deliverability', 'invitations', 'registrations', 'verification', 'demand', 'quotes', 'reveals']),
  ('repeatable', 4, 'Revenue repeats month on month; B2B accounts carry the volume.',
   'fee_aed_30d', 19544, 'AED 19,544 of fees in 30 days (the base path''s February)',
   array['deliverability', 'invitations', 'registrations', 'verification', 'demand', 'quotes', 'reveals']),
  ('scaling', 5, 'Scale the channels that the experiments proved.',
   'fee_aed_30d', 42931, 'AED 42,931 of fees in 30 days (the base path''s August)',
   array['deliverability', 'invitations', 'registrations', 'verification', 'demand', 'quotes', 'reveals']),
  ('market_leadership', 6, 'Beyond the base path: take share from every competitor on the watch list.',
   null, null, null,
   array['deliverability', 'invitations', 'registrations', 'verification', 'demand', 'quotes', 'reveals'])
on conflict (stage) do update set stage_order = excluded.stage_order, meaning = excluded.meaning, exit_measure = excluded.exit_measure,
  exit_threshold = excluded.exit_threshold, exit_meaning = excluded.exit_meaning, constraint_scope = excluded.constraint_scope;

insert into public.ceo_company_stage_log (stage) select 'supply_seeding'
 where not exists (select 1 from public.ceo_company_stage_log);

-- PURE: the stage the measurements reach from the current one (walks forward over every milestone already met).
create or replace function public.fn_ceo_company_stage_next(p_current text, p_readings jsonb)
returns text
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v text := p_current; s record;
begin
  loop
    select * into s from public.ceo_company_stage where stage = v;
    exit when s.exit_measure is null or (p_readings->>s.exit_measure) is null
           or (p_readings->>s.exit_measure)::numeric < s.exit_threshold;
    select stage into v from public.ceo_company_stage where stage_order = s.stage_order + 1;
    exit when v is null;
  end loop;
  return coalesce(v, p_current);
end $fn$;
revoke execute on function public.fn_ceo_company_stage_next(text, jsonb) from public, anon, authenticated;

create or replace function public.fn_ceo_company_stage_advance()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare cur public.ceo_company_stage_log; v_read jsonb := '{}'::jsonb; k text; v_next text;
begin
  select * into cur from public.ceo_company_stage_log where left_at is null for update;
  for k in select distinct exit_measure from public.ceo_company_stage where exit_measure is not null loop
    v_read := v_read || jsonb_build_object(k, public.fn_ambition_measure(k, timestamptz '2026-01-01', now()));
  end loop;
  v_next := public.fn_ceo_company_stage_next(cur.stage, v_read);
  if v_next <> cur.stage then
    update public.ceo_company_stage_log set left_at = now(), exit_reading = v_read where id = cur.id;
    insert into public.ceo_company_stage_log (stage) values (v_next);
    perform public.fn_ceo_plan_log('company_stage', 'company_stage:' || v_next,
      format('The company moved from %s to %s on measured milestones.', cur.stage, v_next), jsonb_build_object('readings', v_read));
  end if;
  return jsonb_build_object('stage', v_next, 'from', cur.stage, 'moved', v_next <> cur.stage, 'readings', v_read);
end $fn$;
revoke execute on function public.fn_ceo_company_stage_advance() from public, anon, authenticated;
grant execute on function public.fn_ceo_company_stage_advance() to service_role;

-- The funnel now carries the company stage and its scope (the rest is the_ceo_plans_every_day_and_directs_the_seats.sql).
create or replace function public.fn_ceo_plan_funnel(p_at timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local timestamp := p_at at time zone 'Asia/Dubai';
  v_m0 timestamptz := date_trunc('month', v_local) at time zone 'Asia/Dubai';
  v_w0 timestamptz := p_at - interval '7 days';
  k text; v_mtd jsonb := '{}'; v_l7 jsonb := '{}';
begin
  foreach k in array array['invitations_delivered','registrations_submitted','registrations_verified',
                           'inquiries_posted','quote_coverage_pct','reveals_paid','fee_aed'] loop
    v_mtd := v_mtd || jsonb_build_object(k, public.fn_ceo_plan_measure(k, v_m0, p_at));
    v_l7  := v_l7  || jsonb_build_object(k, public.fn_ceo_plan_measure(k, v_w0, p_at));
  end loop;
  return jsonb_build_object(
    'at', p_at, 'local_date', v_local::date,
    'day_of_month', extract(day from v_local)::int,
    'days_in_month', extract(day from (date_trunc('month', v_local) + interval '1 month - 1 day'))::int,
    'month_to_date', v_mtd, 'last_7_days', v_l7,
    'company_stage', (select jsonb_build_object('stage', s.stage, 'since', l.entered_at, 'scope', to_jsonb(s.constraint_scope),
                                                'exit', s.exit_meaning, 'exit_measure', s.exit_measure, 'exit_threshold', s.exit_threshold,
                                                'exit_reading', case when s.exit_measure is not null then public.fn_ambition_measure(s.exit_measure, timestamptz '2026-01-01', p_at) end)
                        from public.ceo_company_stage_log l join public.ceo_company_stage s on s.stage = l.stage where l.left_at is null),
    'state', jsonb_build_object(
      'bounce_pct_7d', public.fn_ceo_plan_measure('bounce_pct_7d', p_at, p_at),
      'stranded_submissions', public.fn_ceo_plan_measure('stranded_submissions', p_at, p_at),
      'contactable_leads', public.fn_ceo_plan_measure('contactable_leads', p_at, p_at),
      'fee_aed_cumulative', public.fn_ceo_plan_measure('fee_aed', timestamptz '2026-01-01', p_at)),
    'gates', (select jsonb_build_object(
        'invite_enabled', coalesce(max(value) filter (where key='invite_enabled'),'') = 'true',
        'supplier_outreach_golive', coalesce(max(value) filter (where key='supplier_outreach_golive'),'') = 'true',
        'invite_daily_cap', coalesce(nullif(max(value) filter (where key='invite_daily_cap'),'')::int, 0),
        'ceo_model_slot', coalesce(nullif(max(value) filter (where key='ceo_model_slot'),''), 'off'))
      from public.app_secrets where key in ('invite_enabled','supplier_outreach_golive','invite_daily_cap','ceo_model_slot')));
end $fn$;
revoke execute on function public.fn_ceo_plan_funnel(timestamptz) from public, anon, authenticated;

-- THE DECISION, now aware of the company stage. Changed from the_ceo_plans_every_day_and_directs_the_seats.sql:
--   (a) only the funnel stages in the company stage's scope may bind (no scope in the funnel = every stage);
--   (b) a stage HELD by a reserved decision (the founder's campaign gate) no longer ends the walk: it is recorded in
--       held_upstream and the walk continues to the first seat-movable stage behind plan. Only when no movable stage
--       in scope is behind plan does the held stage bind (hold_reserved, recorded silently as before).
-- Everything else (stall, level, founder line, targets, options) is unchanged.
create or replace function public.fn_ceo_plan_decide(p_funnel jsonb, p_target jsonb, p_prev jsonb)
returns jsonb language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare
  v_pro numeric := (p_funnel->>'day_of_month')::numeric / (p_funnel->>'days_in_month')::numeric;
  v_dim numeric := (p_funnel->>'days_in_month')::numeric;
  m jsonb := p_funnel->'month_to_date'; w jsonb := p_funnel->'last_7_days'; s jsonb := p_funnel->'state';
  g jsonb := p_funnel->'gates';
  v_today date := (p_funnel->>'local_date')::date;
  v_att jsonb := '{}'; v_stage text; v_label text; v_owner text; v_lever text := 'seat';
  v_key text; v_dir text := 'min'; v_month_qty numeric; v_since date; v_days int; v_week_actual numeric;
  v_stalled boolean := false; v_level int; v_target numeric; v_due int; v_founder text; v_cap int; v_hold text;
  v_choice text; v_options jsonb; v_stage_order text[] := array['deliverability','invitations','registrations',
    'verification','demand','quotes','reveals'];
  st text; v_plan numeric; v_act numeric; v_a numeric;
  v_gate_open boolean := coalesce((g->>'invite_enabled')::boolean,false) and coalesce((g->>'supplier_outreach_golive')::boolean,false);
  v_scope text[] := case when jsonb_typeof(p_funnel->'company_stage'->'scope') = 'array'
                         then array(select jsonb_array_elements_text(p_funnel->'company_stage'->'scope')) else v_stage_order end;
  v_held_upstream text[] := '{}'; v_first_held text;
begin
  -- attainment per stage: actual month-to-date over the pro-rated month plan (null when the plan is < 1)
  foreach st in array v_stage_order loop
    v_plan := null; v_act := null; v_a := null;
    case st
      when 'invitations'   then v_plan := (p_target->>'invites')::numeric * v_pro;    v_act := (m->>'invitations_delivered')::numeric;
      when 'registrations' then v_plan := (p_target->>'registered')::numeric * v_pro; v_act := (m->>'registrations_submitted')::numeric;
      when 'verification'  then v_plan := (p_target->>'verified')::numeric * v_pro;   v_act := (m->>'registrations_verified')::numeric;
      when 'demand'        then v_plan := (p_target->>'inquiries')::numeric * v_pro;  v_act := (m->>'inquiries_posted')::numeric;
      when 'reveals'       then v_plan := (p_target->>'reveals')::numeric * v_pro;    v_act := (m->>'reveals_paid')::numeric;
      when 'quotes'        then v_plan := case when m->>'quote_coverage_pct' is not null then 70 end; v_act := (m->>'quote_coverage_pct')::numeric;
      else null;
    end case;
    if v_plan is not null and v_plan >= 1 then v_a := round(coalesce(v_act,0) / v_plan, 3); end if;
    v_att := v_att || jsonb_build_object(st, jsonb_build_object('actual', v_act, 'planned_to_date', round(v_plan), 'attainment', v_a));
  end loop;

  -- the binding stage
  if (s->>'bounce_pct_7d')::numeric > 5 then
    v_stage := 'deliverability';
  elsif (s->>'stranded_submissions')::numeric > 0 then
    v_stage := 'verification';
  else
    foreach st in array v_stage_order loop
      continue when st = 'deliverability' or not (st = any (v_scope));
      if (v_att->st->>'attainment') is not null and (v_att->st->>'attainment')::numeric < 0.8 then
        if st in ('invitations','registrations') and not v_gate_open then
          v_held_upstream := v_held_upstream || st;          -- held by the founder's gate: record it and keep walking
          v_first_held := coalesce(v_first_held, st);
          continue;
        end if;
        v_stage := st; exit;
      end if;
    end loop;
    v_stage := coalesce(v_stage, v_first_held);
  end if;
  v_stage := coalesce(v_stage, 'on_plan');

  v_label := case v_stage
    when 'deliverability' then 'email deliverability (bounces above 5%)'
    when 'invitations'    then 'supplier invitations delivered'
    when 'registrations'  then 'supplier registrations submitted'
    when 'verification'   then 'supplier registrations verified'
    when 'demand'         then 'customer requests posted'
    when 'quotes'         then 'requests reaching 3 quotes'
    when 'reveals'        then 'reveal fees paid'
    else 'every stage on plan' end;
  -- demand (customer requests posted) is buyer acquisition: the marketing seat's since 22 Sep 2026 (instruction 721).
  v_owner := case v_stage when 'deliverability' then 'customer_support' when 'demand' then 'marketing'
                          when 'on_plan' then null else 'sales_engineer' end;
  v_key := case v_stage
    when 'deliverability' then 'bounce_pct_7d' when 'invitations' then 'invitations_delivered'
    when 'registrations' then 'registrations_submitted'
    when 'verification' then case when (s->>'stranded_submissions')::numeric > 0 then 'stranded_submissions' else 'registrations_verified' end
    when 'demand' then 'inquiries_posted' when 'quotes' then 'quote_coverage_pct' when 'reveals' then 'reveals_paid' end;
  if v_key in ('bounce_pct_7d','stranded_submissions') then v_dir := 'max'; end if;

  -- who can move it. A HELD stage is recorded here and in ceo_decision_log, and NOWHERE the founder reads
  -- (instructions 636 and 639, 22 Sep 2026): the campaign gate and the daily cap are never raised with him.
  v_cap := coalesce((g->>'invite_daily_cap')::int, 0);
  if v_stage in ('invitations','registrations') and not v_gate_open then
    v_lever := 'founder_reserved';
    v_hold := 'the campaign gate is closed: the founder''s reserved decision, held silently';
  elsif v_stage = 'invitations' and ceil((p_target->>'invites')::numeric / 22) > v_cap then
    v_hold := format('the daily cap of %s is below the %s a day this month''s plan needs; the directive is bounded by the cap',
                     v_cap, ceil((p_target->>'invites')::numeric / 22));
  end if;

  -- how long it has held, and whether it is moving
  if p_prev is not null and p_prev->>'stage' = v_stage then v_since := (p_prev->>'constraint_since')::date;
  else v_since := v_today; end if;
  v_days := v_today - v_since;
  v_month_qty := case v_stage when 'invitations' then (p_target->>'invites')::numeric when 'registrations' then (p_target->>'registered')::numeric
                   when 'verification' then (p_target->>'verified')::numeric when 'demand' then (p_target->>'inquiries')::numeric
                   when 'reveals' then (p_target->>'reveals')::numeric end;
  v_week_actual := (w->>v_key)::numeric;
  if v_stage <> 'on_plan' and v_days >= 7 then
    v_stalled := case when v_dir = 'max' then true
                      when v_key = 'quote_coverage_pct' then coalesce(v_week_actual, 0) < 35
                      else coalesce(v_week_actual, 0) < 0.5 * ceil(coalesce(v_month_qty,0) * 7 / v_dim) end;
  end if;
  v_level := case when v_stalled and v_days >= 14 then 3 when v_stalled then 2 else 1 end;
  if v_level = 3 and v_lever = 'seat' and v_stage <> 'invitations' then
    v_founder := format('The %s constraint has not moved in %s days although %s was directed; it now needs your view.', v_label, v_days, v_owner);
  end if;

  v_due := case v_level when 1 then 7 else 3 end;
  v_target := case
    when v_dir = 'max' and v_key = 'bounce_pct_7d' then 5
    when v_dir = 'max' then 0
    when v_key = 'quote_coverage_pct' then 70
    when v_key = 'invitations_delivered' then least(ceil(v_month_qty * v_due / v_dim), v_cap * v_due)
    else greatest(1, ceil(coalesce(v_month_qty,0) * v_due / v_dim)) end;

  v_options := jsonb_build_array(
    jsonb_build_object('id','hold','effect','no directive; the seats run their standing duties'),
    jsonb_build_object('id','direct_owner','effect',format('direct %s: %s %s %s within %s days', v_owner, v_key, case v_dir when 'min' then '>=' else '<=' end, v_target, v_due)),
    jsonb_build_object('id','escalate','effect','record the stall, tighten the deadline to 3 days, and put the constraint in the founder brief at 14 days'),
    jsonb_build_object('id','hold_reserved','effect','the stage is held by a reserved decision or has no owning seat: record it internally, give no seat an order it cannot carry out, say nothing to the founder'),
    jsonb_build_object('id','revise_target','effect','propose a new month target with the evidence; the table changes only by a recorded CEO decision'));
  v_choice := case when v_stage = 'on_plan' then 'hold' when v_lever <> 'seat' then 'hold_reserved'
                   when v_stalled then 'escalate' else 'direct_owner' end;

  return jsonb_build_object(
    'stage', v_stage, 'label', v_label, 'owner_seat', v_owner, 'lever', v_lever,
    'company_stage', p_funnel->'company_stage'->>'stage', 'scope', to_jsonb(v_scope), 'held_upstream', to_jsonb(v_held_upstream),
    'constraint_since', v_since, 'days_on_constraint', v_days, 'stalled', v_stalled, 'level', v_level,
    'attainment', v_att, 'founder_line', v_founder, 'held_because', v_hold, 'options', v_options, 'plan_c_choice', v_choice,
    'directive', case when v_lever = 'seat' and v_stage <> 'on_plan' then jsonb_build_object(
        'seat', v_owner, 'stage', v_stage, 'measure_key', v_key, 'direction', v_dir, 'target', v_target,
        'due_days', v_due, 'level', v_level) end,
    'prediction', case when v_lever = 'seat' and v_stage <> 'on_plan' then jsonb_build_object(
        'measure_key', v_key, 'direction', v_dir, 'value', v_target, 'by_date', v_today + v_due) end);
end $fn$;
revoke execute on function public.fn_ceo_plan_decide(jsonb, jsonb, jsonb) from public, anon, authenticated;

insert into public.ceo_decision (decision_key, domain, decision, trigger_condition, measure, measure_sql, authority, evidence_required, cadence, active) values
  ('company_stage', 'strategy', 'Move the company to its next stage when the stage''s exit milestone is measured, never back.',
   'The current stage''s exit measure (ceo_company_stage.exit_measure) reaches its threshold.',
   'The stage reached and the day it was reached.', null, 'ceo_alone',
   'The exit readings at the moment of the move (ceo_company_stage_log.exit_reading).', 'daily', true)
on conflict (decision_key) do nothing;

alter table public.ceo_plan add column if not exists company_stage text generated always as (funnel->'company_stage'->>'stage') stored;

-- The CEO seat's own record names the target in force, not the withdrawn one.
update public.org_agents
   set role = 'Chief Executive: owns the evidence-based target path (AED 244,801 of reveal fees by 31 Aug 2027, base case) and beats it where it can',
       improvement_plan = 'Measured daily against public.target_path (target_daily_verdict), weekly against its experiments (ceo_experiment_verdict), and by the company stage reached (ceo_company_stage_log).'
 where agent_key = 'ceo';

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 5. THE DUTIES
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.target_verdict', 'ceo', interval '1 day', 'fn_ceo_target_daily_verdict',
   'Actual against the base-case path per seat metric; a miss beyond tolerance opens a CEO task and a root-cause question to the owning seat.',
   'scripts/sql/the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql'),
  ('ceo.experiment_review', 'ceo', interval '7 days', 'fn_ceo_experiment_review',
   'Every running experiment measured weekly; the verdict (kept, killed, iterated) is reasoned and kept as a case.',
   'scripts/sql/the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql'),
  ('ceo.company_stage', 'ceo', interval '1 day', 'fn_ceo_company_stage_advance',
   'The company stage advances on its measured exit milestone and sets which funnel stages may bind the daily plan.',
   'scripts/sql/the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql'),
  ('marketing.competitor_scan', 'marketing', interval '1 hour', 'fn_marketing_competitor_scan',
   'Each competitor''s home and pricing page fetched monthly; a changed page is reasoned and a material change becomes a CEO task.',
   'scripts/sql/the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 6. THE SEEDED HYPOTHESES: THE PLAN'S THREE LARGEST UNKNOWNS (plan.md section 11)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
select public.fn_ceo_experiment_propose('customer_support', 'reveal_conversion',
  'Buyers who receive the best-3 comparison with each supplier''s verified credentials, and a follow-up from support within 24 hours of the third quote, reveal a supplier on at least 15 % of quoted requests.',
  'reveal_conversion_pct', 'Paid reveals over real requests with at least one quote, created since the start date; not measurable under 20 quoted requests.',
  null, 'Not measured: the platform has carried no real reveal. The plan assumes 10-25 % (A22) and uses 15 % in the base case; it moves the outcome by about 30 % either way.',
  15, 'min', 'Customer support follows up every quoted request within 24 hours of the third quote, answers the comparison questions, and records why a buyer did not reveal.',
  date '2026-11-01', 90);
select public.fn_ceo_experiment_propose('sales_engineer', 'b2b_accounts_consented',
  'Business buyers (contractors, fit-out firms, FM companies, property managers) reached only through consented channels (inbound enquiries, opted-in WhatsApp, events and referrals) open at least 25 active accounts a month from November.',
  'b2b_active_accounts', 'Distinct real business customers (industry recorded) that posted a request in the last 30 days.',
  0, 'Measured zero: no business buyer has posted a real request yet.',
  25, 'min', 'The sales engineer works only consented contacts: every account comes from an inbound form, an opted-in WhatsApp conversation, an event or a referral, with its consent recorded; nobody is contacted cold.',
  date '2026-11-01', 120);
select public.fn_ceo_experiment_propose('marketing', 'category_mix_top4',
  'Concentrating SEO pages and paid reach on the four highest-fee trades (fit-out, villa renovation, kitchens and joinery, steel and building materials) lifts their share of posted requests from about 12.6 % to at least 20 %.',
  'top4_category_request_share_pct', 'Share of real posted requests whose category is one of the top-4 fee trades (fitout, commercial-retail-fitout, kitchens, carpentry-joinery, steel, structural-steel-fabrication); not measurable under 20 requests.',
  12.6, 'From the plan model, not measured: the top four trades carry 61 % of the modelled fee on 12.6 % of requests (A21).',
  20, 'min', 'Marketing publishes SEO pages for the top-4 trades first and weights paid reach toward them, within the approved monthly budget.',
  date '2026-11-01', 90);
