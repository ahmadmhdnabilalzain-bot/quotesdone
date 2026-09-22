-- THE CEO PLANS EVERY DAY FROM THE NUMBERS, DIRECTS THE SEATS, AND FOLLOWS UP.   seat: ceo · 22 Sep 2026
-- Founder instruction 638 (the CEO works like a real CEO, programmed properly), 641 (no Meta/social in
-- any seat now), 643 (the CEO will run on a model later: plan A/B = the model, plan C = this code).
-- The job description this programme carries out: docs/positions/ceo.md (rewritten in the same PR).
-- Apply: node scripts/apply_sql.mjs scripts/sql/the_ceo_plans_every_day_and_directs_the_seats.sql --apply --ddl
-- Pure-probe partner: the_ceo_plans_every_day_and_directs_the_seats_probe.sql
--
-- MEASURED (production, read-only, 22 Sep 2026 ~01:30 Dubai):
--   * Nothing computes the funnel against a plan. company_goals has 64 rows and no owner; target_contract
--     (21-24) holds the AED 1M / 1,000 suppliers / 1,000 customers targets with NO monthly breakdown; the
--     last feasibility run (target_verdict 38, 7 Sep) named no binding stage. fn_ceo_binding_constraint
--     reads ALL-TIME counts that include fixtures (it says "10 matchable" -- all ZZ DEMO).
--   * The real funnel today (demo excluded): 22,265 supplier leads, 19,726 never-invited and contactable,
--     171 invited ever (last 15 Aug), 0 invitation rows through the outbox ever, 1 claimed, 0 submitted,
--     0 approved; 1 customer row without a demo marker (0 substantiated); 0 inquiries; 0 reveals; AED 0.
--   * app_secrets: invite_enabled=false, supplier_outreach_golive=false, invite_daily_cap=50.
--   * The CEO gives no seat an order. agent_actions has 22 handoffs TO the ceo and none FROM the ceo
--     except refund/incident/backup remediation. seat_handoff_kind has no CEO-to-seat directive.
--   * ceo_decision_log: 2 rows (both from fn_ceo_decisions_evaluate, PR #802); 0 plans, 0 directives.
--
-- WHAT THIS CHANGES
--   * ceo_plan_month: the 12-month plan to AED 1,000,500 (Sep 2026 - Aug 2027), one row per month, per
--     stage (invites, registered, verified, inquiries, reveals, fee). docs/positions/ceo.md §9 shows the math.
--   * ceo_plan: one row per Dubai day -- the funnel measured from live rows (demo excluded), the month
--     target, the binding constraint and how long it has held, the plan C decision with its options,
--     the directives issued, the line for the founder's brief, and the model slot's request.
--   * fn_ceo_plan_measure: the ONE definition of every funnel number the CEO uses.
--   * fn_ceo_plan_decide: pure -- funnel + target + yesterday's plan -> constraint, lever, stall,
--     options, plan C's choice, the directive and the prediction.
--   * fn_ceo_plan_act / fn_ceo_plan_followup / fn_ceo_plan_review: issue directives through the EXISTING
--     handoff machinery (fn_seat_handoff, new kind ceo.directive to the four seats), re-measure and close
--     them met or missed, and review plan vs actual every Monday and every 1st of the month.
--   * fn_ceo_judgement_contract / _request / _accept: the model slot. OFF until app_secrets.ceo_model_slot
--     = 'on'. The request is built every day anyway; plan C has already acted when the model answers.
--   * fn_ceo_plan_tick on the heartbeat (resilience_step ceoPlan, hourly): the day's plan once from
--     06:00 Dubai, follow-ups on every call. fn_ceo_plan_brief_lines feeds item 7 of the founder brief.
--   * ceo_decision gains three rules (seat_directive, constraint_stalled, plan_review); the evaluator
--     in the_weekly_report_arrives_and_the_rules_decide.sql names them as decided by the plan.
--
-- WHAT THIS DOES NOT CHANGE
--   * No email, WhatsApp or alert to the founder: the plan reaches him only as lines inside the daily
--     brief (item 7) he already receives. No founder_alerts row, no fn_notify_founder call.
--   * No money moves, no supplier or customer row changes, no founder switch is touched: a directive's
--     handler only READS and replies. invite_enabled / supplier_outreach_golive / invite_daily_cap stay
--     the founder's; the CEO names them in the brief when they are the constraint.
--   * No Meta, ads or social media (instruction 641): buyer acquisition is named as the marketing seat's.
--     22 Sep 2026, later (instruction 721, the marketing seat exists): the demand stage is now OWNED by marketing,
--     the plan reads the latest marketing.report into its funnel (funnel.marketing_report), ceo.directive reaches
--     marketing like every other seat (steering, never an approval), and the founder-text rule is seat-aware: a line
--     naming a seat reaches him only while that seat is active, so the word 'marketing' is no longer forbidden.
--   * target_contract / target_verdict / fn_target_feasibility are left as they are.

-- ── 1. THE TWELVE-MONTH PLAN ──────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_plan_month (
  month      date primary key check (extract(day from month) = 1),
  invites    int not null check (invites >= 0),      -- invitations delivered by the provider in the month
  registered int not null check (registered >= 0),   -- supplier registrations submitted in the month
  verified   int not null check (verified >= 0),     -- supplier registrations approved in the month
  inquiries  int not null check (inquiries >= 0),    -- customer requests posted in the month
  reveals    int not null check (reveals >= 0),      -- reveals paid through Stripe in the month
  fee_aed    numeric(12,2) not null check (fee_aed >= 0),
  basis      text not null,
  updated_at timestamptz not null default now()
);
alter table public.ceo_plan_month enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='ceo_plan_month') then
    create policy ceo_plan_month_service_role_only on public.ceo_plan_month as permissive for all to public using (false) with check (false);
  end if;
end $$;
revoke all on public.ceo_plan_month from anon, authenticated;

-- ASSUMED RATES, each replaced by a measured one once 20 real events exist (docs/positions/ceo.md §9):
-- invitation -> registration 4%; registration -> approval 70%; request -> 3+ quotes 70%;
-- quoted request -> reveal 25%; average selected quotation AED 50,000, so AED 1,500 fee per reveal.
-- Invitations: 50 a day (today's cap) in Oct, 100 a day from Nov -- the founder's number to set.
insert into public.ceo_plan_month (month, invites, registered, verified, inquiries, reveals, fee_aed, basis) values
  ('2026-09-01',  300,  5,  0,   0,   0,      0, 'launch week: 50/day from 23 Sep'),
  ('2026-10-01', 1100, 45, 30,  10,   1,   1500, '50/day x 22 working days'),
  ('2026-11-01', 2200, 90, 65,  40,   5,   7500, '100/day x 22 working days (the sales engineer''s invitation ramp)'),
  ('2026-12-01', 2200, 90, 65,  70,  10,  15000, '100/day'),
  ('2027-01-01', 2200, 90, 65, 115,  20,  30000, '100/day'),
  ('2027-02-01', 2200, 90, 65, 190,  33,  49500, '100/day'),
  ('2027-03-01', 2200, 90, 60, 285,  50,  75000, '100/day'),
  ('2027-04-01', 2200, 90, 65, 400,  70, 105000, '100/day'),
  ('2027-05-01', 2200, 90, 60, 515,  90, 135000, '100/day; the lead list needs ~3,700 new contacts before June'),
  ('2027-06-01', 2200, 90, 65, 630, 110, 165000, '100/day'),
  ('2027-07-01', 2200, 90, 60, 745, 130, 195000, '100/day'),
  ('2027-08-01', 2200, 90, 65, 850, 148, 222000, '100/day; cumulative fee AED 1,000,500')
on conflict (month) do nothing;

-- ── 2. THE DAY'S PLAN ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_plan (
  id               bigserial primary key,
  plan_date        date not null unique,
  created_at       timestamptz not null default now(),
  funnel           jsonb not null,
  month_target     jsonb,
  stage            text not null,
  constraint_since date not null,
  decision         jsonb not null,           -- fn_ceo_plan_decide's answer (plan C)
  directives       jsonb not null default '[]'::jsonb,
  founder_line     text,
  judgement        jsonb not null default '{}'::jsonb,
  decided_by       text not null default 'plan_c_code' check (decided_by in ('plan_c_code','model'))
);
alter table public.ceo_plan enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='ceo_plan') then
    create policy ceo_plan_service_role_only on public.ceo_plan as permissive for all to public using (false) with check (false);
  end if;
end $$;
revoke all on public.ceo_plan from anon, authenticated;

-- ── 3. EVERY NUMBER THE CEO USES, DEFINED ONCE ───────────────────────────────────────────────────
-- Each reads an event or delivery record (a timestamp written when it happened, a provider id), never
-- a status column, and excludes fixtures with the founder brief's own predicates. Flow keys count
-- inside [p_from, p_to); state keys (bounce_pct_7d, stranded_submissions) read the state at p_to.
create or replace function public.fn_ceo_plan_measure(p_key text, p_from timestamptz, p_to timestamptz)
returns numeric language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v numeric; v_sent numeric; v_bounced numeric;
begin
  case p_key
  when 'invitations_delivered' then
    select count(*) into v from public.notifications n left join public.leads l on l.id = n.lead_id
     where n.type = 'supplier_invite' and n.provider_message_id is not null
       and n.sent_at >= p_from and n.sent_at < p_to
       and coalesce(n.to_email,'') not ilike '%@example.invalid'
       and not (coalesce(l.is_demo,false) or coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid');
  when 'registrations_submitted', 'registrations_verified' then
    select count(*) into v from public.leads l
     where case when p_key = 'registrations_submitted' then l.registration_submitted_at else l.approved_at end >= p_from
       and case when p_key = 'registrations_submitted' then l.registration_submitted_at else l.approved_at end <  p_to
       and not (coalesce(l.is_demo,false) or coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid');
  when 'stranded_submissions' then
    select count(*) into v from public.leads l
     where l.registration_submitted_at < p_to - interval '24 hours' and l.approved_at is null and l.rejection_reason is null
       and not (coalesce(l.is_demo,false) or coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid');
  when 'inquiries_posted', 'quote_coverage_pct' then
    with i as (
      select i.id from public.inquiries i join public.customers c on c.id = i.customer_id
       where i.parent_inquiry_id is null and i.created_at >= p_from
         and i.created_at < case when p_key = 'quote_coverage_pct' then p_to - interval '3 days' else p_to end
         and coalesce(i.provenance->>'source','') not in ('demo_factory','e2e')
         and not (coalesce(c.is_demo,false) or coalesce(c.full_name,'') ilike 'ZZ DEMO%'
                  or coalesce(c.email,'') ilike '%@example.invalid' or coalesce(c.phone,'') like '+9715000000%'))
    select case when p_key = 'inquiries_posted' then count(*)
                when count(*) = 0 then null     -- no request old enough to judge: not measurable, not zero
                else round(100.0 * count(*) filter (where (select count(*) from public.quotes q where q.inquiry_id = i.id) >= 3) / count(*), 1) end
      into v from i;
  when 'reveals_paid', 'fee_aed' then
    select case when p_key = 'reveals_paid' then count(*) else coalesce(sum(coalesce(t.reveal_fee, t.app_fee, 0)), 0) end into v
      from public.transactions t join public.customers c on c.id = t.customer_id
     where t.payment_ref ~ '^(pi|ch|py)_' and t.revealed_at >= p_from and t.revealed_at < p_to
       and not (coalesce(c.is_demo,false) or coalesce(c.full_name,'') ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid');
  when 'bounce_pct_7d' then
    -- the same reading as the channel_volume rule in fn_ceo_decisions_evaluate
    select count(*) into v_sent from public.notifications
     where channel = 'email' and status = 'sent' and sent_at > p_to - interval '7 days' and sent_at <= p_to;
    select count(*) into v_bounced from public.email_suppressions
     where reason ilike '%bounce%' and created_at > p_to - interval '7 days' and created_at <= p_to;
    v := case when v_sent >= 20 then round(100.0 * v_bounced / v_sent, 2) end;   -- under 20 sends is not a rate
  when 'contactable_leads' then
    select count(*) into v from public.leads l
     where l.email is not null and l.invited_at is null and coalesce(l.invite_status,'') <> 'bounced'
       and not (coalesce(l.is_demo,false) or coalesce(l.company_name,'') ilike 'ZZ DEMO%' or coalesce(l.email,'') ilike '%@example.invalid');
  else
    raise exception 'fn_ceo_plan_measure: unknown measure %', p_key;
  end case;
  return v;
end $fn$;
revoke execute on function public.fn_ceo_plan_measure(text, timestamptz, timestamptz) from public, anon, authenticated;

-- The funnel for one moment: month to date, the last 7 days, and the founder's switches.
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

-- ── 4. THE DECISION (plan C). PURE: the same inputs always give the same answer ─────────────────────
-- Theory of constraints, walked in the funnel's own order: the FIRST stage behind 80% of its pro-rated
-- plan binds, because nothing downstream of it can move until it does.
--   lever 'seat'             -- a seat can move it; the CEO directs that seat with a target and a deadline.
--   lever 'founder_reserved' -- the campaign gate is closed. HELD SILENTLY: recorded in the plan and the
--                               decision log, never in the brief, the weekly report or founder_line
--                               (instruction 636: he is never asked or reminded about the campaign go).
--   lever 'unowned'          -- no existing seat owns the stage (buyer acquisition today). Recorded internally.
-- Stall: the same stage for 7+ days with the last 7 days under half its weekly plan. Level 2 at 7 days
-- (tighter deadline, stall recorded), level 3 at 14 (a seat-movable stage other than invitations reaches
-- the founder brief). No email. The daily cap is never raised with the founder (instruction 639).
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
      continue when st = 'deliverability';
      if (v_att->st->>'attainment') is not null and (v_att->st->>'attainment')::numeric < 0.8 then v_stage := st; exit; end if;
    end loop;
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
  -- (instructions 636 and 639, 22 Sep 2026): the campaign gate and the daily cap are never raised with him,
  -- and a seat that does not exist yet is never named to him. The CEO directs no seat on a held stage.
  v_cap := coalesce((g->>'invite_daily_cap')::int, 0);
  if v_stage in ('invitations','registrations') and not (coalesce((g->>'invite_enabled')::boolean,false) and coalesce((g->>'supplier_outreach_golive')::boolean,false)) then
    v_lever := 'founder_reserved';
    v_hold := 'the campaign gate is closed: the founder''s reserved decision, held silently';
  elsif v_stage = 'invitations' and ceil((p_target->>'invites')::numeric / 22) > v_cap then
    -- the ramp is the sales engineer's and customer support's (warm-up config), so the seat is directed
    -- and the shortfall is recorded -- the founder is not asked about the cap
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
  -- the only founder line: a seat-movable stage that did not move in 14 days despite directives. Never the
  -- invitation stage -- its volume is the campaign and its ramp, neither of which is raised with him.
  if v_level = 3 and v_lever = 'seat' and v_stage <> 'invitations' then
    v_founder := format('The %s constraint has not moved in %s days although %s was directed; it now needs your view.', v_label, v_days, v_owner);
  end if;

  -- the directive plan C gives (only on a seat lever)
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
    'constraint_since', v_since, 'days_on_constraint', v_days, 'stalled', v_stalled, 'level', v_level,
    'attainment', v_att, 'founder_line', v_founder, 'held_because', v_hold, 'options', v_options, 'plan_c_choice', v_choice,
    'directive', case when v_lever = 'seat' and v_stage <> 'on_plan' then jsonb_build_object(
        'seat', v_owner, 'stage', v_stage, 'measure_key', v_key, 'direction', v_dir, 'target', v_target,
        'due_days', v_due, 'level', v_level) end,
    'prediction', case when v_lever = 'seat' and v_stage <> 'on_plan' then jsonb_build_object(
        'measure_key', v_key, 'direction', v_dir, 'value', v_target, 'by_date', v_today + v_due) end);
end $fn$;
revoke execute on function public.fn_ceo_plan_decide(jsonb, jsonb, jsonb) from public, anon, authenticated;

-- ── 5. ONE DECISION ROW, WITH ITS EVIDENCE, ONCE ────────────────────────────────────────────────────
create or replace function public.fn_ceo_plan_log(p_key text, p_dedupe text, p_decision text, p_evidence jsonb, p_outcome text default 'decided')
returns int language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  with ins as (
    insert into public.ceo_decision_log (decision_key, the_decision, evidence, escalated_to_founder, outcome, dedupe_key)
    values (p_key, p_decision, p_evidence, false, p_outcome, p_dedupe)
    on conflict (dedupe_key) where dedupe_key is not null do nothing returning 1)
  select count(*)::int from ins
$fn$;
revoke execute on function public.fn_ceo_plan_log(text, text, text, jsonb, text) from public, anon, authenticated;

insert into public.ceo_decision (decision_key, domain, decision, trigger_condition, measure, measure_sql, authority, evidence_required, cadence, active) values
  ('seat_directive', 'operations', 'Give a seat a target on the binding constraint, with a deadline, and close it met or missed on the re-measurement.',
   'The day''s plan names a binding stage a seat can move and no directive for it is open; or an open directive is met or past its deadline.',
   'Share of directives met by their deadline.', null, 'ceo_alone',
   'The plan row, the measure key, the target, the deadline and the re-measured value.', 'daily', true),
  ('constraint_stalled', 'strategy', 'Escalate a binding constraint that has not moved: tighten the deadline at 7 days, tell the founder in the brief at 14.',
   'The same stage binds for 7+ days and the last 7 days are under half of its weekly plan.',
   'Days the binding stage has held.', null, 'ceo_alone',
   'The stage, the days on it, the last-7-day reading against the weekly plan.', 'daily', true),
  ('plan_review', 'strategy', 'Compare plan and actual per stage every week and every month, and state whether AED 1,000,000 is still reachable.',
   'Every Monday (week) and every 1st (month), Asia/Dubai.',
   'Cumulative fee against the cumulative plan.', null, 'ceo_alone',
   'Per-stage actual and plan for the period, the directives met and missed, the cumulative fee.', 'weekly', true)
on conflict (decision_key) do nothing;

-- ── 6. THE DIRECTIVE REACHES THE SEAT THROUGH THE EXISTING HANDOFF MACHINERY ──────────────────────
-- The receiving seat's handler READS and replies: which of its duties carries the target, what the
-- measure reads now, and what blocks it. It writes nothing else. The CEO closes (originator_closes).
create or replace function public.fn_seat_takes_ceo_directive(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; d jsonb; v_gates jsonb; v_duty text; v_block text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  d := a.detail;
  select jsonb_build_object('on', coalesce(max(value) filter (where key='invite_enabled'),'') = 'true'
                                 and coalesce(max(value) filter (where key='supplier_outreach_golive'),'') = 'true',
                            'cap', max(value) filter (where key='invite_daily_cap'))
    into v_gates from public.app_secrets where key in ('invite_enabled','supplier_outreach_golive','invite_daily_cap');
  case d->>'stage'
    when 'invitations', 'registrations' then
      v_duty := 'fn_sales_engineer_supplier_outreach_tick: the daily invitation batch (cap '||coalesce(v_gates->>'cap','?')||') and the day-2/day-6 registration reminders';
      if not (v_gates->>'on')::boolean then v_block := 'held: the founder''s invitation switches are off'; end if;
    when 'verification' then
      v_duty := 'fn_sales_engineer_supplier_outreach_tick: the 24-hour clock on a submitted registration, and the mandatory-six check';
    when 'deliverability' then
      v_duty := 'fn_delivery_feedback_canary_tick and the outbox bounce brake: suppress the bouncing addresses, prove bounce reports arrive';
    when 'quotes' then
      v_duty := 'the RFQ dispatch and the spec-offer duty: widen the match inside the exact trade and chase the suppliers who have not quoted';
    when 'reveals' then
      v_duty := 'the comparison follow-up with the customer; the payment path is the accountant''s nightly test';
    when 'demand' then
      v_duty := 'the marketing seat''s duties (supabase/functions/marketing/duties.ts): approved posts, the social inbox and paid reach that bring buyers to post requests; its daily report (marketing.report) says what moved';
    else
      v_duty := 'no standing duty carries this stage'; v_block := 'no owner duty exists';
  end case;
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'stage', d->>'stage', 'duty', v_duty, 'blocker', v_block,
    'measure_key', d->>'measure_key', 'target', d->'target', 'due_at', d->>'due_at',
    'reading_now', public.fn_ceo_plan_measure(d->>'measure_key', a.created_at, now()),
    'waiting', 'the CEO re-measures '||(d->>'measure_key')||' by '||(d->>'due_at'));
end $fn$;
revoke execute on function public.fn_seat_takes_ceo_directive(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select 'ceo.directive', 'ceo', s, 'The CEO''s daily plan names the binding constraint this seat can move: reach the target by the deadline. The CEO re-measures and closes it, met or missed.',
       'fn_seat_takes_ceo_directive', interval '1 hour', true, 'scripts/sql/the_ceo_plans_every_day_and_directs_the_seats.sql'
  from unnest(array['sales_engineer','customer_support','accountant','it_engineer','marketing']) s
on conflict do nothing;

-- ── 7. ACT ON THE DAY'S PLAN ──────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_plan_act(p_plan_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.ceo_plan; d jsonb; dr jsonb; v_open bigint; v_hid bigint; v_logged int := 0; v_issued jsonb := '[]';
begin
  select * into p from public.ceo_plan where id = p_plan_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no ceo_plan '||p_plan_id); end if;
  d := p.decision;

  -- the constraint, once per run of the same stage
  v_logged := v_logged + public.fn_ceo_plan_log('binding_constraint', 'binding_constraint:plan:'||p.stage||':'||p.constraint_since,
    format('The binding constraint is %s (since %s). %s', d->>'label', p.constraint_since,
           case when d->>'lever' <> 'seat' and p.stage <> 'on_plan' then 'Held, no directive: '||coalesce(d->>'held_because','')
                            when d->>'lever' = 'seat' and p.stage <> 'on_plan' then (d->>'owner_seat')||' is directed to move it.' else 'Every stage is on plan.' end),
    jsonb_build_object('plan_id', p.id, 'plan_stage', p.stage, 'lever', d->>'lever', 'held_because', d->>'held_because', 'attainment', d->'attainment',
                       'funnel_month_to_date', p.funnel->'month_to_date', 'month_target', p.month_target));

  if (d->>'stalled')::boolean then
    v_logged := v_logged + public.fn_ceo_plan_log('constraint_stalled', 'constraint_stalled:'||p.stage||':'||p.constraint_since||':L'||(d->>'level'),
      format('The %s constraint has held %s days and the last 7 days read %s against a weekly plan it must reach. Level %s: %s.',
             d->>'label', d->>'days_on_constraint', coalesce(p.funnel->'last_7_days'->>(d->'directive'->>'measure_key'), p.funnel->'state'->>(d->'directive'->>'measure_key'), 'n/a'),
             d->>'level', case d->>'level' when '3' then 'the founder is told in the brief' else 'deadline tightened to 3 days' end),
      jsonb_build_object('plan_id', p.id, 'stage', p.stage, 'days', d->'days_on_constraint', 'level', d->'level', 'last_7_days', p.funnel->'last_7_days'));
  end if;

  -- jsonb_build_object stores a SQL NULL as JSON null, which IS NOT NULL: unwrap it before testing.
  dr := nullif(d->'directive', 'null'::jsonb);
  if dr is not null then
    select a.id into v_open from public.agent_actions a
     where a.kind = 'handoff' and a.detail->>'type' = 'ceo.directive' and a.detail->>'from' = 'ceo'
       and a.detail->>'stage' = p.stage and a.status = 'pending' limit 1;
    if v_open is null then
      v_hid := public.fn_seat_handoff('ceo', dr->>'seat', 'ceo.directive', 'ceo_plan', p.plan_date::text||':'||p.stage,
        dr || jsonb_build_object('plan_id', p.id, 'due_at', now() + make_interval(days => (dr->>'due_days')::int),
                                 'prediction', d->'prediction', 'decided_by', p.decided_by));
      v_issued := v_issued || jsonb_build_object('handoff_id', v_hid) || dr;
      v_logged := v_logged + public.fn_ceo_plan_log('seat_directive', 'seat_directive:issued:'||v_hid,
        format('%s must bring %s %s %s within %s days (level %s).', dr->>'seat', dr->>'measure_key',
               case dr->>'direction' when 'min' then 'to at least' else 'down to' end, dr->>'target', dr->>'due_days', dr->>'level'),
        jsonb_build_object('plan_id', p.id, 'handoff_id', v_hid, 'directive', dr, 'prediction', d->'prediction'));
    else
      v_issued := v_issued || jsonb_build_object('handoff_id', v_open, 'already_open', true);
    end if;
  end if;

  update public.ceo_plan set directives = v_issued where id = p.id;
  return jsonb_build_object('ok', true, 'plan_id', p.id, 'stage', p.stage, 'directives', v_issued, 'decisions_written', v_logged);
end $fn$;
revoke execute on function public.fn_ceo_plan_act(bigint) from public, anon, authenticated;

-- ── 8. FOLLOW UP: RE-MEASURE EVERY OPEN DIRECTIVE, CLOSE IT MET OR MISSED ────────────────────────
create or replace function public.fn_ceo_plan_followup(p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a record; v numeric; v_met boolean; n_met int := 0; n_missed int := 0; n_open int := 0; v_err jsonb := '[]';
begin
  for a in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'ceo.directive' and detail->>'from' = 'ceo' and status = 'pending'
            order by id loop
    begin
      v := public.fn_ceo_plan_measure(a.detail->>'measure_key',
             case when a.detail->>'measure_key' in ('bounce_pct_7d','stranded_submissions') then p_now else a.created_at end, p_now);
      v_met := case when v is null then false
                    when a.detail->>'direction' = 'max' then v <= (a.detail->>'target')::numeric
                    else v >= (a.detail->>'target')::numeric end;
      if v_met or p_now > (a.detail->>'due_at')::timestamptz then
        perform set_config('qd.handoff_closer', 'ceo', true);
        perform public.fn_seat_handoff_complete(a.id, coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object(
          'verified_by', 'ceo', 'verified_at', p_now, 'reading', v, 'target', a.detail->'target', 'met', v_met));
        perform set_config('qd.handoff_closer', '', true);
        perform public.fn_ceo_plan_log('seat_directive', 'seat_directive:'||case when v_met then 'met' else 'missed' end||':'||a.id,
          format('%s %s the directive: %s read %s against %s by %s.', a.agent, case when v_met then 'met' else 'missed' end,
                 a.detail->>'measure_key', coalesce(v::text,'n/a'), a.detail->>'target', a.detail->>'due_at'),
          jsonb_build_object('handoff_id', a.id, 'reading', v, 'target', a.detail->'target', 'met', v_met,
                             'prediction', a.detail->'prediction', 'prediction_held', v_met));
        if v_met then n_met := n_met + 1; else n_missed := n_missed + 1; end if;
      else
        n_open := n_open + 1;
      end if;
    exception when others then
      perform set_config('qd.handoff_closer', '', true);
      v_err := v_err || jsonb_build_object('handoff', a.id, 'error', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'met', n_met, 'missed', n_missed, 'open', n_open)
      || case when jsonb_array_length(v_err) = 0 then '{}'::jsonb else jsonb_build_object('error', v_err::text) end;
end $fn$;
revoke execute on function public.fn_ceo_plan_followup(timestamptz) from public, anon, authenticated;

-- ── 9. WEEK AND MONTH: PLAN AGAINST ACTUAL ────────────────────────────────────────────────────────
create or replace function public.fn_ceo_plan_review(p_at timestamptz default now())
returns int language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local date := (p_at at time zone 'Asia/Dubai')::date; v_n int := 0; t public.ceo_plan_month;
  v_from timestamptz; v_to timestamptz; v_fee_cum numeric; v_plan_cum numeric; v_left numeric; v_months int; ev jsonb;
begin
  if extract(isodow from v_local) = 1 then
    v_to := v_local::timestamp at time zone 'Asia/Dubai'; v_from := v_to - interval '7 days';
    select * into t from public.ceo_plan_month where month = date_trunc('month', v_from at time zone 'Asia/Dubai')::date;
    ev := jsonb_build_object('week_from', v_from, 'week_to', v_to,
      'invitations', jsonb_build_array(public.fn_ceo_plan_measure('invitations_delivered', v_from, v_to), round(coalesce(t.invites,0)*7/30.0)),
      'registrations', jsonb_build_array(public.fn_ceo_plan_measure('registrations_submitted', v_from, v_to), round(coalesce(t.registered,0)*7/30.0)),
      'verified', jsonb_build_array(public.fn_ceo_plan_measure('registrations_verified', v_from, v_to), round(coalesce(t.verified,0)*7/30.0)),
      'inquiries', jsonb_build_array(public.fn_ceo_plan_measure('inquiries_posted', v_from, v_to), round(coalesce(t.inquiries,0)*7/30.0)),
      'reveals', jsonb_build_array(public.fn_ceo_plan_measure('reveals_paid', v_from, v_to), round(coalesce(t.reveals,0)*7/30.0)),
      'fee_aed', jsonb_build_array(public.fn_ceo_plan_measure('fee_aed', v_from, v_to), round(coalesce(t.fee_aed,0)*7/30.0)),
      'directives', (select jsonb_build_object('met', count(*) filter (where (evidence->>'met')::boolean), 'missed', count(*) filter (where not (evidence->>'met')::boolean))
                       from public.agent_actions where kind='handoff' and detail->>'type'='ceo.directive' and status='done' and decided_at >= v_from and decided_at < v_to),
      'shape', '[actual, plan]');
    v_n := v_n + public.fn_ceo_plan_log('plan_review', 'plan_review:week:'||to_char(v_from at time zone 'Asia/Dubai','IYYY-"W"IW'),
      format('Week review: invitations %s/%s, registrations %s/%s, requests %s/%s, reveals %s/%s, fee AED %s/%s (actual/plan).',
             ev->'invitations'->>0, ev->'invitations'->>1, ev->'registrations'->>0, ev->'registrations'->>1,
             ev->'inquiries'->>0, ev->'inquiries'->>1, ev->'reveals'->>0, ev->'reveals'->>1, ev->'fee_aed'->>0, ev->'fee_aed'->>1), ev);
  end if;

  if extract(day from v_local) = 1 then
    v_fee_cum := public.fn_ceo_plan_measure('fee_aed', timestamptz '2026-01-01', v_local::timestamp at time zone 'Asia/Dubai');
    select coalesce(sum(fee_aed),0) into v_plan_cum from public.ceo_plan_month where month < v_local;
    select count(*) into v_months from public.ceo_plan_month where month >= v_local;
    v_left := 1000000 - v_fee_cum;
    ev := jsonb_build_object('fee_cumulative', v_fee_cum, 'plan_cumulative', v_plan_cum, 'remaining', v_left, 'months_left', v_months,
      'required_per_month', case when v_months > 0 then round(v_left / v_months) end,
      'highest_month_ever', (select max(public.fn_ceo_plan_measure('fee_aed', m.month::timestamp at time zone 'Asia/Dubai', (m.month + interval '1 month')::timestamp at time zone 'Asia/Dubai'))
                               from public.ceo_plan_month m where m.month < v_local));
    v_n := v_n + public.fn_ceo_plan_log('plan_review', 'plan_review:month:'||to_char(v_local - 1, 'YYYY-MM'),
      format('Month review: cumulative fee AED %s against a plan of AED %s. AED %s remains over %s months: AED %s a month is now required.',
             v_fee_cum, v_plan_cum, v_left, v_months, coalesce(ev->>'required_per_month','n/a')), ev);
  end if;
  return v_n;
end $fn$;
revoke execute on function public.fn_ceo_plan_review(timestamptz) from public, anon, authenticated;

-- ── 10. THE MODEL SLOT: PLAN A/B. OFF UNTIL app_secrets.ceo_model_slot = 'on' ─────────────────────
-- The contract is data, versioned. The model chooses among options the CODE computed, from numbers the
-- CODE measured, and every field it returns is validated here before anything happens. It cannot move
-- money, change a supplier or customer record, message anyone, or touch a founder switch: its only
-- effect is a decision row and ceo.directive handoffs, whose handler only reads.
-- What the founder is never told by the CEO (instructions 636, 639; 22 Sep 2026): the campaign gate and
-- its switches, the invitation volume, cap and warm-up, and subscriptions. One pattern, read by
-- fn_ceo_judgement_accept, fn_ceo_plan_brief_lines and the recurrence test.
-- "A seat that does not exist" was enforced here by the word 'marketing' until 22 Sep 2026; the seat exists now
-- (instruction 721), so that rule is SEAT-AWARE instead: a directive, and so a brief line, may name only a seat
-- that is active in org_role (fn_ceo_judgement_accept and fn_ceo_plan_brief_lines read org_role).
create or replace function public.fn_ceo_founder_text_forbidden()
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select '(switched off|switch them|campaign|\mgate\M|go[- ]?live|invite_enabled|\mcaps?\M|ceiling|warm[- ]?up|subscription)'::text
$fn$;
revoke execute on function public.fn_ceo_founder_text_forbidden() from public, anon, authenticated;

create or replace function public.fn_ceo_judgement_contract()
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'version', 'ceo-judgement-v1',
    'system', 'You are the chief executive of QuotesDone, a UAE construction-procurement marketplace. Customers post requests; verified suppliers quote; the customer sees a free comparison of the best three technical quotes plus every other quote, and pays a 3% reveal fee (plus card processing) to reveal the supplier they choose. Suppliers pay no commission. The company goal is AED 1,000,000 of reveal-fee revenue by 31 August 2027. You direct five seats: sales_engineer, customer_support, accountant, it_engineer, marketing (marketing owns the demand stage: buyers posting requests). input.marketing is the marketing seat''s latest daily report: read it as the picture of that stage. Decide ONLY from the numbers in the input; never invent one. You may not move money, change a supplier or customer record, message a customer, a supplier or the founder, or touch any founder switch. The supplier invitation campaign (its go, its switches, its daily volume and ramp), subscriptions and seats that do not exist yet are not yours to propose or mention: when a stage is held by them, choose hold_reserved and leave founder_decision null. founder_decision is only for a stage a seat can move that has not moved in 14 days despite directives. Choose exactly one option id from input.options. Give your reasoning in at most eight sentences, citing the input numbers you relied on. Make one measurable prediction. Reply with a single JSON object matching output_schema and nothing else.',
    'input_fields', jsonb_build_array('date','goal','month_target','funnel','attainment','constraint','open_directives','options','plan_c_choice','marketing'),
    'output_schema', jsonb_build_object(
      'option_id', 'one of input.options[].id',
      'reasoning', 'string, 40-2000 characters, cites input numbers',
      'prediction', jsonb_build_object('measure_key','one of the measure keys in input.funnel','direction','min|max','value','number >= 0','by_date','YYYY-MM-DD, 1-30 days after input.date'),
      'directives', 'array of at most 3: {seat: sales_engineer|customer_support|accountant|it_engineer|marketing, stage, measure_key, direction, target >= 0, due_days 1-14, instruction <= 400 characters}',
      'founder_decision', 'null, or <= 300 characters naming the one decision only the founder can take'),
    'plan_c', 'If the slot is off, the call fails, or the answer fails validation, the coded decision already taken stands and the rejection is recorded on the plan.')
$fn$;
revoke execute on function public.fn_ceo_judgement_contract() from public, anon, authenticated;

create or replace function public.fn_ceo_judgement_request(p_plan_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.ceo_plan; c jsonb := public.fn_ceo_judgement_contract();
begin
  select * into p from public.ceo_plan where id = p_plan_id;
  if not found then return null; end if;
  return jsonb_build_object('contract', c->>'version', 'system', c->>'system', 'output_schema', c->'output_schema',
    'input', jsonb_build_object(
      'date', p.plan_date, 'goal', 'AED 1,000,000 cumulative reveal fees by 2027-08-31',
      'month_target', p.month_target, 'funnel', p.funnel - 'gates' || jsonb_build_object('founder_switches', p.funnel->'gates'),
      'attainment', p.decision->'attainment',
      'constraint', jsonb_build_object('stage', p.stage, 'label', p.decision->>'label', 'lever', p.decision->>'lever',
                                       'since', p.constraint_since, 'days', p.decision->'days_on_constraint', 'stalled', p.decision->'stalled'),
      'open_directives', (select coalesce(jsonb_agg(jsonb_build_object('seat', a.agent, 'stage', a.detail->>'stage', 'measure_key', a.detail->>'measure_key',
                                   'target', a.detail->'target', 'due_at', a.detail->>'due_at', 'reply', a.evidence)), '[]'::jsonb)
                            from public.agent_actions a where a.kind='handoff' and a.detail->>'type'='ceo.directive' and a.status='pending'),
      'options', p.decision->'options', 'plan_c_choice', p.decision->>'plan_c_choice',
      -- the marketing report the plan read when it was made (fn_ceo_plan_tick), 22 Sep 2026 (instruction 721)
      'marketing', p.funnel->'marketing_report'));
end $fn$;
revoke execute on function public.fn_ceo_judgement_request(bigint) from public, anon, authenticated;

create or replace function public.fn_ceo_judgement_accept(p_plan_id bigint, p_output jsonb, p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  p public.ceo_plan; v_why text; x jsonb; v_keys text[] := array['invitations_delivered','registrations_submitted','registrations_verified',
    'stranded_submissions','inquiries_posted','quote_coverage_pct','reveals_paid','fee_aed','bounce_pct_7d'];
  v_hid bigint; v_ids jsonb := '[]';
begin
  select * into p from public.ceo_plan where id = p_plan_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no ceo_plan '||p_plan_id); end if;

  v_why := case
    when p_error is not null then 'the call failed: '||left(p_error, 300)
    when p_output is null or jsonb_typeof(p_output) <> 'object' then 'no JSON object came back'
    when not exists (select 1 from jsonb_array_elements(p.decision->'options') o where o->>'id' = p_output->>'option_id') then 'option_id is not one of the options'
    when length(coalesce(p_output->>'reasoning','')) not between 40 and 2000 then 'reasoning missing or out of bounds'
    -- every test is coalesced: a missing field compares NULL, and a NULL WHEN is a pass
    when not coalesce(p_output->'prediction'->>'measure_key' = any (v_keys), false) then 'prediction.measure_key is not a funnel measure'
    when coalesce(p_output->'prediction'->>'direction','') not in ('min','max') then 'prediction.direction is not min or max'
    when coalesce(p_output->'prediction'->>'value','') !~ '^[0-9]+(\.[0-9]+)?$' then 'prediction.value is not a number >= 0'
    -- A cast is only reached once its format is proven: OR gives no evaluation-order guarantee, CASE does.
    when coalesce(p_output->'prediction'->>'by_date','') !~ '^\d{4}-\d{2}-\d{2}$' then 'prediction.by_date is not a date'
    when (p_output->'prediction'->>'by_date')::date not between p.plan_date + 1 and p.plan_date + 30 then 'prediction.by_date is not 1-30 days ahead'
    when jsonb_typeof(coalesce(p_output->'directives','[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_output->'directives','[]'::jsonb)) > 3 then 'directives is not an array of at most 3'
    when exists (select 1 from jsonb_array_elements(coalesce(p_output->'directives','[]'::jsonb)) dd
                  where jsonb_typeof(dd) <> 'object'
                     or not coalesce(dd->>'seat' = any (array['sales_engineer','customer_support','accountant','it_engineer','marketing']), false)
                     or not exists (select 1 from public.org_role r where r.role_id = dd->>'seat' and r.status = 'active')
                     or not coalesce(dd->>'measure_key' = any (v_keys), false) or coalesce(dd->>'direction','') not in ('min','max')
                     or coalesce(dd->>'target','') !~ '^[0-9]+(\.[0-9]+)?$'
                     or case when coalesce(dd->>'due_days','') ~ '^[0-9]{1,3}$' then (dd->>'due_days')::int not between 1 and 14 else true end
                     or length(coalesce(dd->>'instruction','')) > 400) then 'a directive is outside the contract'
    when length(coalesce(p_output->>'founder_decision','')) > 300 then 'founder_decision is longer than 300 characters'
    -- instructions 636/639: the campaign gate, its volume and subscriptions never reach the founder, and a
    -- seat that is not in org_agents is never named to him
    when coalesce(p_output->>'founder_decision','') ~* public.fn_ceo_founder_text_forbidden() then 'founder_decision raises a subject reserved from the founder (campaign, invitations, caps, subscriptions, a seat that does not exist)'
  end;

  if v_why is not null then
    update public.ceo_plan set judgement = judgement || jsonb_build_object('answered_at', now(), 'accepted', false, 'rejected_because', v_why, 'output', p_output)
     where id = p.id;
    return jsonb_build_object('ok', false, 'plan_id', p.id, 'plan_c_stands', true, 'error', 'model answer rejected: '||v_why);
  end if;

  for x in select * from jsonb_array_elements(coalesce(p_output->'directives','[]'::jsonb)) loop
    v_hid := public.fn_seat_handoff('ceo', x->>'seat', 'ceo.directive', 'ceo_plan',
      p.plan_date::text||':model:'||(x->>'seat')||':'||(x->>'measure_key'),
      jsonb_build_object('stage', coalesce(x->>'stage', p.stage), 'measure_key', x->>'measure_key', 'direction', x->>'direction',
                         'target', (x->>'target')::numeric, 'due_days', (x->>'due_days')::int, 'instruction', x->>'instruction',
                         'due_at', now() + make_interval(days => (x->>'due_days')::int), 'plan_id', p.id,
                         'prediction', p_output->'prediction', 'decided_by', 'model', 'level', p.decision->'level'));
    v_ids := v_ids || to_jsonb(v_hid);
  end loop;

  perform public.fn_ceo_plan_log('binding_constraint', 'judgement:plan:'||p.id,
    format('Model judgement on %s: %s. %s', p.stage, p_output->>'option_id', left(p_output->>'reasoning', 1500)),
    jsonb_build_object('plan_id', p.id, 'contract', (public.fn_ceo_judgement_contract())->>'version', 'output', p_output,
                       'plan_c_choice', p.decision->>'plan_c_choice', 'directive_handoffs', v_ids));
  update public.ceo_plan
     set decided_by = 'model',
         founder_line = coalesce(founder_line, nullif(p_output->>'founder_decision','')),
         judgement = judgement || jsonb_build_object('answered_at', now(), 'accepted', true, 'output', p_output, 'directive_handoffs', v_ids)
   where id = p.id;
  return jsonb_build_object('ok', true, 'plan_id', p.id, 'option_id', p_output->>'option_id', 'directive_handoffs', v_ids);
end $fn$;
revoke execute on function public.fn_ceo_judgement_accept(bigint, jsonb, text) from public, anon, authenticated;

-- ── 11. THE TICK ──────────────────────────────────────────────────────────────────────────────────
-- p_at is now() on the heartbeat; the probe passes today 07:00 Dubai so it proves the planning path at
-- any hour of the day rather than only after six.
create or replace function public.fn_ceo_plan_tick(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local timestamp := p_at at time zone 'Asia/Dubai';
  v_fu jsonb; v_funnel jsonb; v_target jsonb; v_prev jsonb; v_dec jsonb; v_act jsonb; v_rev int; v_req jsonb;
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

  v_req := public.fn_ceo_judgement_request(p.id);
  update public.ceo_plan set judgement = jsonb_build_object('slot', v_funnel->'gates'->>'ceo_model_slot', 'request', v_req,
           'plan_c_acted', true) where id = p.id;

  return jsonb_build_object('ok', coalesce((v_act->>'ok')::boolean, false) and coalesce((v_fu->>'ok')::boolean, false),
    'planned', true, 'plan_id', p.id, 'stage', p.stage, 'lever', v_dec->>'lever', 'stalled', v_dec->'stalled',
    'directives', v_act->'directives', 'decisions_written', v_act->'decisions_written', 'reviews_written', v_rev, 'followup', v_fu,
    'judgement', jsonb_build_object('slot', v_funnel->'gates'->>'ceo_model_slot',
                                    'call_model', v_funnel->'gates'->>'ceo_model_slot' = 'on'))
    || case when coalesce((v_act->>'ok')::boolean, false) then '{}'::jsonb else jsonb_build_object('error', v_act->>'error') end
    || case when v_fu ? 'error' then jsonb_build_object('error', v_fu->>'error') else '{}'::jsonb end;
end $fn$;
revoke execute on function public.fn_ceo_plan_tick(timestamptz) from public, anon, authenticated;

comment on function public.fn_ceo_plan_tick(timestamptz) is
  'The CEO''s daily plan (once per Dubai day from 06:00) and the follow-up of every open ceo.directive (every call). Called by resilience_ping step ceoPlan. Writes ceo_plan, ceo_decision_log and ceo.directive handoffs; emails nobody. 22 Sep 2026, ceo.';

-- ── 12. WHAT THE FOUNDER READS: LINES FOR ITEM 7 OF THE DAILY BRIEF ─────────────────────────────────
create or replace function public.fn_ceo_plan_brief_lines()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- A HELD stage (lever founder_reserved / unowned) contributes no line at all: the founder is not told
  -- the CEO is waiting on the campaign, nor about a seat that does not exist. Every line is then passed
  -- through fn_ceo_founder_text_forbidden, so a line that would raise a reserved subject is dropped.
  select coalesce((select jsonb_agg(x) from jsonb_array_elements_text((
    select case when p.decision->>'lever' = 'seat' or p.stage = 'on_plan' then
             jsonb_build_array('The CEO''s focus: '||(p.decision->>'label')
             || case when p.stage = 'on_plan' then '.'
                     else ' ('||coalesce(p.decision->'attainment'->p.stage->>'actual','0')||' of '
                          ||coalesce(p.decision->'attainment'->p.stage->>'planned_to_date','0')||' planned so far this month; day '
                          ||(p.decision->>'days_on_constraint')||' on this constraint).' end)
           else '[]'::jsonb end
        || coalesce((select jsonb_agg(initcap(replace(a.agent,'_',' '))||' is directed to bring '||replace(a.detail->>'measure_key','_',' ')
                                      ||case a.detail->>'direction' when 'max' then ' down to ' else ' to ' end||(a.detail->>'target')
                                      ||' by '||to_char((a.detail->>'due_at')::timestamptz at time zone 'Asia/Dubai','DD Mon')||'.')
                       from public.agent_actions a
                      where a.kind='handoff' and a.detail->>'type'='ceo.directive' and a.status='pending'
                        and exists (select 1 from public.org_role r where r.role_id = a.agent and r.status = 'active')), '[]'::jsonb)
        || case when p.founder_line is not null then jsonb_build_array('Waiting on you: '||p.founder_line) else '[]'::jsonb end
      from public.ceo_plan p order by p.plan_date desc limit 1)) x
   where x !~* public.fn_ceo_founder_text_forbidden()), '[]'::jsonb)
$fn$;
revoke execute on function public.fn_ceo_plan_brief_lines() from public, anon, authenticated;

-- ── 13. THE SEAT'S OWN RECORD SAYS WHAT THE JOB IS ────────────────────────────────────────────────
-- Measured 22 Sep: org_agents still described the department-era CEO ("quarterly priorities and OKRs ...
-- reviews department performance") and carried an improvement_plan about "331 deliverables returned by
-- review" in departments that were deleted on 7 Sep. The job description is docs/positions/ceo.md.
update public.org_agents
   set role = 'Chief Executive: owns the path to AED 1,000,000 of reveal fees by 31 Aug 2027',
       responsibilities = 'Every day: measure the funnel from live rows, name the binding constraint, direct the seat that can move it (ceo.directive: owner, target, deadline, measure), re-measure and close every directive met or missed, escalate a constraint that has not moved (7 days: tighter deadline; 14 days: the founder brief). Every week and month: plan against actual. Decides every approval including refunds, inside the founder''s hard rules. Never moves money outside the guarded refund path, never writes a supplier or customer record, never touches a founder switch, never emails the founder beyond the daily brief and the weekly report. Job description: docs/positions/ceo.md; programme: scripts/sql/the_ceo_plans_every_day_and_directs_the_seats.sql.',
       improvement_plan = 'Measured against public.ceo_plan_month: directives met by their deadline, and days the binding constraint has held (ceo_decision_log keys seat_directive, constraint_stalled, plan_review).'
 where agent_key = 'ceo';

-- ── 14. THE CEO'S OWN FUNCTION MAY PRESENT ITS CREDENTIAL TO ai_gateway ───────────────────────────
-- Plan A/B runs in ceo_agent (action 'judgement'), never in the 15-minute heartbeat, so resilience_ping does
-- not import _shared/llm.ts. ceo_agent now does; llm.ts presents cred_fn_ceo_agent, whose scope (measured
-- 22 Sep: ['ceo_agent']) gains ai_gateway -- widened, not a second credential, exactly as
-- _audit_95_llm_path_scoped_credentials.sql does for every other llm.ts importer (it now names ceo_agent).
update public.internal_credential
   set scope = array(select distinct x from unnest(scope || array['ai_gateway']) x order by x)
 where context = 'fn.ceo_agent' and active and not (scope @> array['ai_gateway']);

-- ── 15. ON THE HEARTBEAT ──────────────────────────────────────────────────────────────────────────
insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('ceoPlan', interval '1 hour', 3000, 'plan', 0,
   'fn_ceo_plan_tick: the CEO''s daily plan from the live funnel (once per Dubai day from 06:00), directives to the seats, and the follow-up of every open directive')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
                                rank = excluded.rank, note = excluded.note;
