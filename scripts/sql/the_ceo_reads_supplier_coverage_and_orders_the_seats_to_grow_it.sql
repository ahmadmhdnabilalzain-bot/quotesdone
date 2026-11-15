-- THE CEO READS SUPPLIER COVERAGE AND ORDERS THE SEATS TO GROW IT. Seat: ceo. 15 Nov 2026.
-- Founder, ledger 1701 (15 Nov 2026): "I want to be profitable and that should be the main concern for the CEO. So to achieve
-- that: 1 we need enough registered suppliers to be able to start a customer campaign later to fulfill their inquiries. So the
-- ceo need to find a way. And thats why i want him to be able to take actions and give tasks to the agent".
-- Founder, ledger 1696 (15 Nov 2026): "CEO is having full authority ... He doesnt rely on me in anything. He is fully
-- responsible about his decisions and their outcomes".
--
-- MEASURED ON PRODUCTION (SELECT, 15 Nov 2026):
--   * public.inquiries holds 3 requests, all from fixture customers: 0 real inquiries, so there is NO past customer demand by
--     trade or emirate to read. public.demand_forecast has 0 rows. public.customer_trade_waitlist holds 2 'waiting' rows.
--   * public.supply_gap: 144 (trade, emirate) rows in 'recruit' (decided_by 'sales_engineer:recruitment_brief'; 140 of them
--     UAE-wide), 83 'deferred' (rule:no_uninvited_leads); demand_90d sums to 0; 15 matchable suppliers over 14 rows.
--   * leads: 2 approved of 20,275 real rows. trade_opening_rule: open_at_suppliers 10, floor 5, 3 quotes at an assumed 40%
--     quote rate (ledger 1614). invite_enabled 'false', invite_daily_cap 3, ceo_growth_act_golive 'false'.
--   * The pieces exist and nobody joins them into one objective: supply_gap measures matchable suppliers per trade and area,
--     trade_customer_opening per trade, ceo_supplier_funnel_daily and fn_invite_open_funnel the invitation funnel, and
--     fn_ceo_growth_act (switch off) turns the invitation dials. No routine says "how far are we from enough suppliers to
--     fulfil customers' requests", and no seat is ordered, with a measurable outcome and a date, to close that distance.
-- WHAT THIS ADDS (the objective is DATA, read daily by code; nothing here is a sentence in a prompt):
--   1. public.supplier_coverage_target: verified, active suppliers wanted per trade per emirate ('UAE' = anywhere). Each row
--      says where its number and its demand come from (source, demand_basis). The rows written at apply are PROPOSALS
--      (status 'proposed'); the CEO confirms them on his first run (fn_ceo_grows_supply), recorded with the reason, and may
--      change a target later with a reason (fn_ceo_sets_coverage_target). Nothing is invented: the target is the company's own
--      opening level (trade_opening_rule.open_at_suppliers), and a row exists only where demand or a recruitment decision is
--      RECORDED, in this order: (a) real inquiries by trade and emirate (none on 15 Nov), (b) customers waiting for a trade
--      (customer_trade_waitlist), (c) the sales engineer's recruitment decisions (supply_gap status 'recruit'), whose demand
--      is said to be 0 where it is 0.
--   2. fn_supplier_coverage(): the ONE routine for the current numbers: per target, the real suppliers that are verified and
--      matchable for that trade in that emirate, by the predicate fn_sales_engineer_supply_gap uses (confirmed capabilities,
--      fn_is_matchable, his stated emirates or none = UAE-wide), demo excluded; covered = sum(least(verified, target)).
--   3. fn_supplier_funnel_reading(days): invited -> opened -> started sign-up -> submitted -> approved, from what is recorded
--      (notifications, email_open_event, leads), with what each stage cannot see; plus the two queues the seats can move:
--      registrations started and stopped (the definition fn_ceo_growth_reading uses) and registrations submitted and held.
--   4. fn_ceo_grows_supply(): THE CEO'S DAILY LOOP (duty ceo.supply_coverage). After 06:00 Dubai, once a day: confirm a
--      proposal on the first run; read coverage against target, the seats' board (open and late hand-overs) and the funnel;
--      decide; and ORDER seats through the pool (ceo.order hand-overs, so the order is in the seat's "Waiting on you" and
--      comes back): the seat that owns the invitation duty: the next batch in the gap trades, inside the daily cap and the
--      placement gate (only when invitations are switched on); sales_engineer: follow up the half-finished registrations
--      through allowed channels; customer_support: unblock the held registrations. Each order names the leads it is about,
--      a measured outcome and a due date; the seat's report closes it (fn_seat_reports_done); the loop measures it every day
--      and closes one whose outcome was met a day (20 hours) before the seat said so. Every decision, with its reason, is a row in
--      public.ceo_supply_decision.
--   5. fn_ceo_daily_summary_to_the_founder(): once a day, INFORMATION, NOT APPROVAL (ledger 1696): coverage against target,
--      the funnel, the CEO's decisions of the last day (IT findings, late hand-overs, seats' questions of authority, his own
--      authority, the supply orders, targets), the company limits with any waiting change and today's spend. Kind
--      ceo_daily_summary through fn_notify_founder (founder_mail_policy can silence it); nothing in it asks him anything.
-- FIXTURES: with qd.duty_fixtures = 'on' (the estate's probe seam, as fn_marketing_recruitment_funnel reads it) every reading
-- here sees ONLY demo rows, and without it ONLY real ones: a probe proves the loop on its own ZZ DEMO world, and no production
-- row decides its outcome; a live run never counts a demo supplier, request or invitation.
-- WHAT THIS DOES NOT CHANGE: fn_ceo_growth_act and its switch (it still owns the invitation dials: cap, ceiling, channels);
-- supply_gap and fn_sales_engineer_supply_gap; the senders and their gates (no order can pass a gate: an invitation order is
-- measured only by invitations the outbox sent through them, and says so). No model is called here.
-- prevented by: scripts/checks/the_ceo_acts_within_company_limits.test.mjs (text), the probe
-- the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it_probe.sql (LOCAL), supabase/functions/ceo_agent/coverage.test.ts
-- APPLY ORDER: after the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql and
-- every_seat_reads_one_pool_and_every_hand_over_comes_back.sql (ceo.order and fn_seat_reports_done are the pool's).
-- LOCKS: two new tables, routines, one seat_duty row and one founder_mail_policy row; no busy table is altered.
set local lock_timeout = '1500ms';

-- ── 1. THE TARGET: data, with where each number comes from ───────────────────────────────────────────────────────
create table if not exists public.supplier_coverage_target (
  id bigserial primary key,
  trade text not null,
  emirate text not null,
  target_suppliers integer not null check (target_suppliers > 0 and target_suppliers <= 1000),
  status text not null default 'proposed' check (status in ('proposed', 'confirmed', 'retired')),
  source text not null check (length(btrim(source)) >= 20),
  demand_basis jsonb not null default '{}'::jsonb,
  priority integer not null default 0,
  proposed_at timestamptz not null default now(),
  confirmed_at timestamptz,
  confirmed_by text,
  decision_reason text,
  retired_at timestamptz);
comment on table public.supplier_coverage_target is 'Verified, active suppliers wanted per trade per emirate (founder ledger 1701). Rows written at apply are proposals the CEO confirms on his first run; source and demand_basis say where each number comes from. the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql';
create unique index if not exists supplier_coverage_target_live on public.supplier_coverage_target (trade, emirate) where status <> 'retired';

create table if not exists public.ceo_supply_decision (
  id bigserial primary key,
  decided_on date not null,
  kind text not null check (kind in ('run', 'confirm_targets', 'set_target', 'order', 'no_order', 'order_measured', 'order_closed')),
  subject text not null,
  reason text not null,
  reading jsonb not null default '{}'::jsonb,
  handoff_id bigint,
  dedupe_key text not null unique,
  created_at timestamptz not null default now());
comment on table public.ceo_supply_decision is 'Every decision of the CEO''s supply loop, with its reason and the reading it was taken on (founder ledger 1696: recorded, and in the founder''s daily summary). the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql';

do $guard$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.supplier_coverage_target'::regclass) then
    alter table public.supplier_coverage_target enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'supplier_coverage_target' and policyname = 'supplier_coverage_target_service_role_only') then
    create policy supplier_coverage_target_service_role_only on public.supplier_coverage_target as permissive for all to public using (false) with check (false);
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.ceo_supply_decision'::regclass) then
    alter table public.ceo_supply_decision enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ceo_supply_decision' and policyname = 'ceo_supply_decision_service_role_only') then
    create policy ceo_supply_decision_service_role_only on public.ceo_supply_decision as permissive for all to public using (false) with check (false);
  end if;
end $guard$;
revoke all on public.supplier_coverage_target from anon, authenticated;
revoke all on public.ceo_supply_decision from anon, authenticated;
revoke all on sequence public.supplier_coverage_target_id_seq from anon, authenticated;
revoke all on sequence public.ceo_supply_decision_id_seq from anon, authenticated;

-- PROPOSE from what is recorded. Never overwrites a row the CEO confirmed or retired; adds only what is missing.
create or replace function public.fn_supplier_coverage_target_propose()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.trade_opening_rule; v_target int; n_inq int := 0; n_wait int := 0; n_gap int := 0;
        v_rule_src text;
begin
  select * into r from public.trade_opening_rule where id = 1;
  v_target := coalesce(r.open_at_suppliers, (select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  v_rule_src := 'target ' || v_target || ' = trade_opening_rule.open_at_suppliers, the verified suppliers at which a trade opens to customers ('
                || coalesce(r.reason, 'pricing_config.category_open_min_suppliers') || ')';
  -- (a) real inquiries, by trade and emirate (demo is never demand: the predicate fn_sales_engineer_supply_gap uses)
  with d as (
    select t as trade, coalesce(nullif(btrim(i.emirate), ''), 'UAE') as emirate, count(*) as n_all,
           count(*) filter (where i.created_at > now() - interval '90 days') as n_90d, max(i.created_at) as last_at
      from public.inquiries i left join public.customers c on c.id = i.customer_id, unnest(coalesce(i.trades, '{}'::text[])) t
     where coalesce(public.fn_seat_clock_customer_is_fixture(c), false) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
       and t in (select code from public.taxonomy_trade where active)
     group by 1, 2),
  ins as (
    insert into public.supplier_coverage_target (trade, emirate, target_suppliers, source, demand_basis, priority)
    select d.trade, d.emirate, v_target,
           'demand: ' || d.n_all || ' real inquiries in ' || d.trade || ' / ' || d.emirate || ' (public.inquiries, fixtures excluded); ' || v_rule_src,
           jsonb_build_object('source', 'inquiries', 'inquiries_all', d.n_all, 'inquiries_90d', d.n_90d, 'last_at', d.last_at), 1000 + d.n_all
      from d
     where not exists (select 1 from public.supplier_coverage_target x where x.trade = d.trade and x.emirate = d.emirate and x.status <> 'retired')
    returning 1)
  select count(*) into n_inq from ins;
  -- (b) customers waiting for a trade (no emirate is recorded on the waitlist: UAE-wide)
  with w as (
    select q.trade, count(*) as n from public.customer_trade_waitlist q
     where q.status = 'waiting' and q.trade in (select code from public.taxonomy_trade where active)
       and ((q.customer_id is not null and public.fn_customer_is_demo(q.customer_id)) or (q.phone is not null and public.fn_is_demo_phone(q.phone))) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
     group by 1),
  ins as (
    insert into public.supplier_coverage_target (trade, emirate, target_suppliers, source, demand_basis, priority)
    select w.trade, 'UAE', v_target,
           'demand: ' || w.n || ' customer(s) waiting for ' || w.trade || ' (public.customer_trade_waitlist, status waiting, fixtures excluded); ' || v_rule_src,
           jsonb_build_object('source', 'customer_trade_waitlist', 'waiting', w.n), 500 + w.n
      from w
     where not exists (select 1 from public.supplier_coverage_target x where x.trade = w.trade and x.emirate = 'UAE' and x.status <> 'retired')
    returning 1)
  select count(*) into n_wait from ins;
  -- (c) the sales engineer's recruitment decisions: no customer demand is recorded there, and the row says so
  with ins as (
    insert into public.supplier_coverage_target (trade, emirate, target_suppliers, source, demand_basis, priority)
    select g.trade, g.emirate, v_target,
           'no customer demand recorded (supply_gap.demand_90d ' || g.demand_90d || '); recruited by decision ' || coalesce(g.decided_by, '?')
             || ' (public.supply_gap status recruit, ' || g.uninvited_pool || ' uninvited leads); ' || v_rule_src,
           jsonb_build_object('source', 'supply_gap', 'demand_90d', g.demand_90d, 'short_open', g.short_open, 'decided_by', g.decided_by,
                              'uninvited_pool', g.uninvited_pool, 'matchable_then', g.matchable), least(g.uninvited_pool, 499)
      from public.supply_gap g
     where g.status = 'recruit' and g.trade in (select code from public.taxonomy_trade where active) and not (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
       and not exists (select 1 from public.supplier_coverage_target x where x.trade = g.trade and x.emirate = g.emirate and x.status <> 'retired')
    returning 1)
  select count(*) into n_gap from ins;
  return jsonb_build_object('proposed_from_inquiries', n_inq, 'proposed_from_waitlist', n_wait, 'proposed_from_recruitment_decisions', n_gap,
                            'target_each', v_target, 'proposed_total', (select count(*) from public.supplier_coverage_target where status = 'proposed'));
end $fn$;
revoke execute on function public.fn_supplier_coverage_target_propose() from public, anon, authenticated;

-- ── 2. THE ONE ROUTINE FOR THE CURRENT NUMBERS ───────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_coverage(p_limit integer default 10)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb;
begin
  with sup as materialized (   -- fn_sales_engineer_supply_gap's predicate, demo excluded
    select sc.supplier_id, sc.trades,
           array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[]) || coalesce(l.service_emirates, '{}'::text[])) e
                  where nullif(btrim(e), '') is not null) as stated
      from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null and coalesce(l.is_demo, false) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)),
  t as (
    select x.id, x.trade, x.emirate, x.target_suppliers as target, x.status, x.priority, x.demand_basis->>'source' as demand_source,
           (select count(*) from sup s where x.trade = any(s.trades)
             and (x.emirate = 'UAE' or cardinality(s.stated) = 0 or lower(x.emirate) = any(s.stated)))::int as verified
      from public.supplier_coverage_target x where x.status in ('proposed', 'confirmed'))
  select jsonb_build_object(
    'at', now(),
    'targets_confirmed', (select count(*) from t where status = 'confirmed'),
    'targets_proposed', (select count(*) from t where status = 'proposed'),
    'target_suppliers', coalesce((select sum(target) from t where status = 'confirmed'), 0),
    'covered_suppliers', coalesce((select sum(least(verified, target)) from t where status = 'confirmed'), 0),
    'coverage_pct', (select round(100.0 * sum(least(verified, target)) / nullif(sum(target), 0), 1) from t where status = 'confirmed'),
    'trades_at_target', (select count(*) from t where status = 'confirmed' and verified >= target),
    'verified_real_suppliers', (select count(*) from sup),
    'gaps', coalesce((select jsonb_agg(jsonb_build_object('trade', g.trade, 'emirate', g.emirate, 'target', g.target, 'verified', g.verified,
                                 'gap', g.target - g.verified, 'demand', g.demand_source) order by g.priority desc, g.target - g.verified desc, g.trade)
                        from (select * from t where status = 'confirmed' and verified < target order by priority desc, target - verified desc, trade
                               limit greatest(coalesce(p_limit, 10), 1)) g), '[]'::jsonb),
    'basis', 'verified = real suppliers with confirmed capabilities that fn_is_matchable passes, whose trades hold the trade and whose stated emirates hold the emirate (none stated = UAE-wide): fn_sales_engineer_supply_gap''s predicate, demo excluded. covered = sum over confirmed targets of least(verified, target).')
  into v;
  return v;
end $fn$;
revoke execute on function public.fn_supplier_coverage(integer) from public, anon, authenticated;

-- ── 3. THE FUNNEL, FROM WHAT IS RECORDED ─────────────────────────────────────────────────────────────────────────
-- Registrations started and stopped: fn_ceo_growth_reading's started_stuck, as ids. Held: submitted, not decided, 2+ days.
create or replace function public.fn_supplier_registrations_stuck(p_at timestamptz default now())
returns setof bigint language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select l.id from public.leads l
   where (l.owner_email_verified or coalesce(l.claimed, false)) and l.registration_submitted_at is null
     and coalesce(l.portal_updated_at, l.invite_clicked_at) < p_at - interval '3 days'
     and (coalesce(l.is_demo, false) or coalesce(l.company_name, '') ilike 'ZZ DEMO%' or public.fn_is_demo_email(coalesce(l.email, ''))) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
     and not coalesce(l.banned, false)
   order by coalesce(l.portal_updated_at, l.invite_clicked_at)
$fn$;
revoke execute on function public.fn_supplier_registrations_stuck(timestamptz) from public, anon, authenticated;

create or replace function public.fn_supplier_registrations_held(p_at timestamptz default now())
returns setof bigint language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select l.id from public.leads l
   where l.registration_submitted_at is not null and l.registration_submitted_at < p_at - interval '2 days'
     and coalesce(l.approval_status, '') not in ('approved', 'rejected')
     and (coalesce(l.is_demo, false) or coalesce(l.company_name, '') ilike 'ZZ DEMO%' or public.fn_is_demo_email(coalesce(l.email, ''))) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
     and not coalesce(l.banned, false)
   order by l.registration_submitted_at
$fn$;
revoke execute on function public.fn_supplier_registrations_held(timestamptz) from public, anon, authenticated;

create or replace function public.fn_supplier_funnel_reading(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_from timestamptz := now() - make_interval(days => greatest(coalesce(p_days, 30), 1)); v jsonb;
begin
  with real_lead as (
    select l.* from public.leads l
     where (coalesce(l.is_demo, false) or coalesce(l.company_name, '') ilike 'ZZ DEMO%' or public.fn_is_demo_email(coalesce(l.email, ''))) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'))
  select jsonb_build_object(
    'days', p_days, 'from', v_from,
    'invited', (select count(distinct n.lead_id) from public.notifications n join real_lead l on l.id = n.lead_id
                 where n.type in ('supplier_invite', 'supplier_invite_wa') and n.status = 'sent' and n.sent_at >= v_from),
    'opened', (select count(distinct n.lead_id) from public.email_open_event e join public.notifications n on n.id = e.notification_id
                 join real_lead l on l.id = n.lead_id
                where n.type = 'supplier_invite' and e.classification = 'likely_human' and e.opened_at >= v_from),
    'started', (select count(*) from real_lead l where (l.owner_email_verified or coalesce(l.claimed, false))
                 and coalesce(l.invite_clicked_at, l.portal_updated_at) >= v_from),
    'submitted', (select count(*) from real_lead l where l.registration_submitted_at >= v_from),
    'approved', (select count(*) from real_lead l where l.approval_status = 'approved' and l.approved_at >= v_from),
    'approved_all_time', (select count(*) from real_lead l where l.approval_status = 'approved'),
    'started_and_stopped', (select count(*) from public.fn_supplier_registrations_stuck(now())),
    'submitted_and_held', (select count(*) from public.fn_supplier_registrations_held(now())),
    'limits', 'invited = leads with a sent supplier_invite or supplier_invite_wa in the window (the outbox, not leads.invite_status); opened = a likely_human load of the tracked share''s image (app_secrets.invite_open_tracking): a floor, never a read receipt, and 0 for the untracked arm by construction; started = the owner verified his e-mail or claimed the listing, dated by his click or portal visit; submitted = registration_submitted_at; approved = approval_status approved, dated approved_at. A WhatsApp reply or a call is not a stage here.')
  into v;
  return v;
end $fn$;
revoke execute on function public.fn_supplier_funnel_reading(integer) from public, anon, authenticated;

-- ── 4. THE ORDERS' MEASURE ────────────────────────────────────────────────────────────────────────────────────────
-- What an order's outcome reads now. invitations: real leads of the order's trades the outbox invited since the order;
-- stuck_followed_up: the order's leads that have since submitted; held_unblocked: the order's leads still held.
create or replace function public.fn_ceo_supply_order_reading(p_detail jsonb, p_since timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ids bigint[] := array(select x::bigint from jsonb_array_elements_text(coalesce(p_detail->'lead_ids', '[]'::jsonb)) x where x ~ '^\d+$');
        v_trades text[] := array(select x from jsonb_array_elements_text(coalesce(p_detail->'trades', '[]'::jsonb)) x);
        v_target int := coalesce((p_detail->>'target')::int, 0); v_value int; v_met boolean;
begin
  case p_detail->>'measure'
  when 'invitations' then
    select count(distinct n.lead_id) into v_value from public.notifications n join public.leads l on l.id = n.lead_id
     where n.type in ('supplier_invite', 'supplier_invite_wa') and n.status = 'sent' and n.sent_at >= p_since
       and coalesce(l.is_demo, false) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on') and coalesce(l.invite_trades, '{}'::text[]) && v_trades;
    v_met := v_value >= v_target;
  when 'stuck_followed_up' then
    select count(*) into v_value from public.leads l where l.id = any(v_ids) and l.registration_submitted_at is not null;
    v_met := v_value >= v_target;
  when 'held_unblocked' then
    select count(*) into v_value from public.leads l where l.id = any(v_ids)
       and coalesce(l.approval_status, '') not in ('approved', 'rejected') and not coalesce(l.banned, false);
    v_met := v_value <= v_target;
  else
    return jsonb_build_object('measure', p_detail->>'measure', 'met', false, 'why', 'no such measure');
  end case;
  return jsonb_build_object('measure', p_detail->>'measure', 'value', v_value, 'target', v_target, 'met', v_met, 'at', now());
end $fn$;
revoke execute on function public.fn_ceo_supply_order_reading(jsonb, timestamptz) from public, anon, authenticated;

-- ── 5. THE CEO CHANGES A TARGET, with a reason ────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_sets_coverage_target(p_trade text, p_emirate text, p_target integer, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_old public.supplier_coverage_target; v_id bigint; v_em text := coalesce(nullif(btrim(p_emirate), ''), 'UAE');
begin
  if length(btrim(coalesce(p_reason, ''))) < 20 then return jsonb_build_object('ok', false, 'reason', 'say why, in a sentence (20 characters or more)'); end if;
  if not exists (select 1 from public.taxonomy_trade where code = p_trade and active) then return jsonb_build_object('ok', false, 'reason', 'no active trade ' || coalesce(p_trade, '-')); end if;
  if p_target is not null and (p_target < 1 or p_target > 1000) then return jsonb_build_object('ok', false, 'reason', 'a target is 1 to 1000 suppliers, or null to retire it'); end if;
  select * into v_old from public.supplier_coverage_target where trade = p_trade and emirate = v_em and status <> 'retired' for update;
  if found then
    update public.supplier_coverage_target set status = 'retired', retired_at = now(), decision_reason = coalesce(decision_reason || ' | ', '') || 'retired by the CEO: ' || left(btrim(p_reason), 300)
     where id = v_old.id;
  end if;
  if p_target is not null then
    insert into public.supplier_coverage_target (trade, emirate, target_suppliers, status, source, demand_basis, priority, confirmed_at, confirmed_by, decision_reason)
    values (p_trade, v_em, p_target, 'confirmed', 'set by the CEO: ' || left(btrim(p_reason), 400), coalesce(v_old.demand_basis, '{}'::jsonb) || jsonb_build_object('set_by', 'ceo'),
            coalesce(v_old.priority, 0), now(), 'ceo', left(btrim(p_reason), 600)) returning id into v_id;
  end if;
  insert into public.ceo_supply_decision (decided_on, kind, subject, reason, reading, dedupe_key)
  values ((now() at time zone 'Asia/Dubai')::date, 'set_target', p_trade || ' / ' || v_em, left(btrim(p_reason), 600),
          jsonb_build_object('before', v_old.target_suppliers, 'after', p_target), 'set_target:' || p_trade || ':' || v_em || ':' || clock_timestamp());
  return jsonb_build_object('ok', true, 'trade', p_trade, 'emirate', v_em, 'before', v_old.target_suppliers, 'after', p_target, 'id', v_id);
end $fn$;
revoke execute on function public.fn_ceo_sets_coverage_target(text, text, integer, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_sets_coverage_target(text, text, integer, text) to service_role;

-- ── 6. THE CEO'S DAILY LOOP ───────────────────────────────────────────────────────────────────────────────────────
-- The seat that owns the duty that sends invitations (seat_duty, read now, never assumed): on 15 Nov 2026 the routine
-- fn_sales_engineer_supplier_outreach_tick is the duty sales_engineer.supplier_outreach (SELECT); marketing when none is found.
create or replace function public.fn_ceo_invitation_seat()
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select d.owner_seat from public.seat_duty d where d.routine = 'fn_sales_engineer_supplier_outreach_tick' and d.enabled limit 1), 'marketing')
$fn$;
revoke execute on function public.fn_ceo_invitation_seat() from public, anon, authenticated;

create or replace function public.fn_ceo_grows_supply(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local timestamp := p_at at time zone 'Asia/Dubai'; v_today date := (p_at at time zone 'Asia/Dubai')::date;
        v_cov jsonb; v_fun jsonb; v_board jsonb; v_conf int := 0; o record; v_read jsonb; v_h bigint; v_ids bigint[]; v_trades text[];
        v_n int; v_target int; v_cap int; v_seat text; v_on boolean; n_orders int := 0; n_closed int := 0; v_due timestamptz;
        v_gap int; v_reason text;
begin
  if v_local::time < time '06:00' then return jsonb_build_object('ran', false, 'reason', 'before 06:00 Dubai'); end if;
  if exists (select 1 from public.ceo_supply_decision where dedupe_key = 'run:' || v_today) then
    return jsonb_build_object('ran', false, 'reason', 'today''s run exists');
  end if;

  -- 1. THE TARGETS: what is newly recorded is proposed, and the CEO confirms it (ledger 1701: the objective is his to hold).
  -- The first run confirms the proposal written at apply; a later run confirms what new demand added. Each with its reason.
  perform public.fn_supplier_coverage_target_propose();
  update public.supplier_coverage_target set status = 'confirmed', confirmed_at = now(), confirmed_by = 'ceo',
         decision_reason = 'Confirmed by the CEO''s daily run: ' || source
   where status = 'proposed';
  get diagnostics v_conf = row_count;
  if v_conf > 0 then
    insert into public.ceo_supply_decision (decided_on, kind, subject, reason, reading, dedupe_key)
    values (v_today, 'confirm_targets', v_conf || ' coverage targets',
            'Each target is the company''s own opening level, on a trade and emirate where demand or a recruitment decision is recorded (inquiries, the waitlist, supply_gap recruit); no other source exists, so the CEO holds them as the objective and changes one with a reason when demand shows itself.',
            jsonb_build_object('by_source', (select jsonb_object_agg(src, n) from (select demand_basis->>'source' src, count(*) n from public.supplier_coverage_target
                                                                                    where status = 'confirmed' and confirmed_at = now() group by 1) x)),
            'confirm_targets:' || v_today) on conflict (dedupe_key) do nothing;
  end if;

  -- 2. READ: coverage against target, the funnel, the seats' board
  v_cov := public.fn_supplier_coverage(5);
  v_fun := public.fn_supplier_funnel_reading(30);
  select jsonb_object_agg(agent, jsonb_build_object('open', n_open, 'late', n_late)) into v_board from (
    select a.agent, count(*) n_open,
           count(*) filter (where coalesce(case when a.detail->>'due_at' ~ '^\d{4}' then (a.detail->>'due_at')::timestamptz end, a.created_at)
                                  + coalesce(k.reply_within, interval '1 day') < now()) n_late
      from public.agent_actions a
      left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.status = 'pending' and a.created_at > now() - interval '60 days'
     group by a.agent) b;

  -- 3. THE OPEN ORDERS: measured every day; a met outcome the seat has not reported for a day is closed as measured
  for o in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'type' = 'ceo.order' and a.detail->>'path' = 'coverage' and a.status = 'pending' loop
    v_read := public.fn_ceo_supply_order_reading(o.detail, o.created_at);
    update public.agent_actions set detail = detail || jsonb_build_object('reading_now', v_read)
             || case when (v_read->>'met')::boolean and not (detail ? 'met_at') then jsonb_build_object('met_at', now()) else '{}'::jsonb end
     where id = o.id;
    -- 20 hours, not 24: the daily run's own minute drifts, and a day's grace must not become two
    if (v_read->>'met')::boolean and o.detail ? 'met_at' and (o.detail->>'met_at')::timestamptz < now() - interval '20 hours' then
      perform public.fn_seat_handoff_complete(o.id, jsonb_build_object('outcome', 'met', 'reply',
        'Met, measured by the CEO: ' || (v_read->>'value') || ' against ' || (v_read->>'target') || ' (' || (o.detail->>'measure') || '); ' || o.agent || ' did not report it',
        'reading', v_read, 'not_cited', jsonb_build_object('reason', 'closed by its measure', 'by', 'ceo')));
      insert into public.ceo_supply_decision (decided_on, kind, subject, reason, reading, handoff_id, dedupe_key)
      values (v_today, 'order_closed', o.agent || ': ' || (o.detail->>'measure'), 'met by measure a day before the seat reported it', v_read, o.id, 'order_closed:' || o.id)
      on conflict (dedupe_key) do nothing;
      n_closed := n_closed + 1;
    end if;
  end loop;
  -- orders the seat reported done: the measure at the report is written beside the report
  for o in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'type' = 'ceo.order' and a.detail->>'path' = 'coverage' and a.status = 'done'
              and not (a.detail ? 'outcome_measured') and a.decided_at > now() - interval '30 days' loop
    v_read := public.fn_ceo_supply_order_reading(o.detail, o.created_at);
    update public.agent_actions set detail = detail || jsonb_build_object('outcome_measured', v_read) where id = o.id;
    insert into public.ceo_supply_decision (decided_on, kind, subject, reason, reading, handoff_id, dedupe_key)
    values (v_today, 'order_measured', o.agent || ': ' || (o.detail->>'measure'),
            case when (v_read->>'met')::boolean then 'reported done and met' else 'reported done; the measure is not met: ' || (v_read->>'value') || ' against ' || (v_read->>'target') end,
            v_read, o.id, 'order_measured:' || o.id) on conflict (dedupe_key) do nothing;
  end loop;

  -- 4. DECIDE AND ORDER (a seat with an open order on a measure gets no second one)
  v_gap := coalesce((v_cov->>'target_suppliers')::int, 0) - coalesce((v_cov->>'covered_suppliers')::int, 0);
  -- 4a. the next invitation batch, in the gap trades, inside the cap and the placement gate
  v_seat := public.fn_ceo_invitation_seat();
  v_on := coalesce((select value from public.app_secrets where key = 'invite_enabled'), '') = 'true';
  v_cap := coalesce(nullif((select value from public.app_secrets where key = 'invite_daily_cap'), '')::int, 0);
  v_trades := array(select g->>'trade' from jsonb_array_elements(coalesce(v_cov->'gaps', '[]'::jsonb)) g);
  if v_gap <= 0 then
    v_reason := 'coverage is at target: no invitation order';
  elsif not v_on then
    v_reason := 'invitations are switched off (app_secrets.invite_enabled): no seat can send a batch; reopening them is fn_ceo_growth_act''s power, under its own switch';
  elsif v_cap <= 0 or cardinality(v_trades) = 0 then
    v_reason := 'no daily invitation cap or no gap trade to invite in';
  elsif exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.order'
                 and a.detail->>'path' = 'coverage' and a.detail->>'measure' = 'invitations') then
    v_reason := 'the last invitation order is still open';
  else
    v_reason := null;
    v_target := least(v_gap, v_cap * 3);
    v_due := p_at + interval '3 days';
    v_h := public.fn_seat_handoff('ceo', v_seat, 'ceo.order', 'supplier_coverage', 'invitations:' || v_today,
      jsonb_build_object('path', 'coverage', 'measure', 'invitations', 'trades', to_jsonb(v_trades), 'target', v_target, 'due_at', v_due,
        'decision', 'grow supply: invite', 'reasons', format('coverage %s of %s target suppliers; the widest gaps are %s', v_cov->>'covered_suppliers', v_cov->>'target_suppliers', array_to_string(v_trades, ', ')),
        'what', format('send the next invitation batch to %s real suppliers in %s by %s, inside invite_daily_cap (%s a day) and the inbox-placement bar', v_target, array_to_string(v_trades, ', '),
                       to_char(v_due at time zone 'Asia/Dubai', 'DD Mon'), v_cap),
        'how', 'only through the existing invitation duty and the outbox: every address passes fn_email_sendable, the suppressions and the placement bar; WhatsApp only to an opt-in. The outcome counts only invitations the outbox sent.'));
    if v_h is not null then
      n_orders := n_orders + 1;
      insert into public.ceo_supply_decision (decided_on, kind, subject, reason, reading, handoff_id, dedupe_key)
      values (v_today, 'order', v_seat || ': invitations', format('invite %s in the gap trades %s by %s', v_target, array_to_string(v_trades, ', '), to_char(v_due at time zone 'Asia/Dubai', 'DD Mon')),
              jsonb_build_object('coverage', v_cov - 'basis', 'cap', v_cap), v_h, 'order:invitations:' || v_today) on conflict (dedupe_key) do nothing;
    end if;
  end if;
  if v_reason is not null then
    insert into public.ceo_supply_decision (decided_on, kind, subject, reason, reading, dedupe_key)
    values (v_today, 'no_order', v_seat || ': invitations', v_reason, jsonb_build_object('gap', v_gap, 'invite_enabled', v_on, 'cap', v_cap), 'no_order:invitations:' || v_today)
    on conflict (dedupe_key) do nothing;
  end if;
  -- 4b. the half-finished registrations: the sales engineer follows each up, through the channels the gates allow
  v_ids := array(select x from public.fn_supplier_registrations_stuck(p_at) x limit 50);
  if cardinality(v_ids) > 0 and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
                                              and a.detail->>'type' = 'ceo.order' and a.detail->>'measure' = 'stuck_followed_up') then
    v_target := greatest(1, ceil(cardinality(v_ids) / 2.0)::int); v_due := p_at + interval '3 days';
    v_h := public.fn_seat_handoff('ceo', 'sales_engineer', 'ceo.order', 'supplier_coverage', 'stuck_followed_up:' || v_today,
      jsonb_build_object('path', 'coverage', 'measure', 'stuck_followed_up', 'lead_ids', to_jsonb(v_ids), 'target', v_target, 'due_at', v_due,
        'decision', 'grow supply: finish registrations', 'reasons', cardinality(v_ids) || ' suppliers started registering and stopped more than 3 days ago',
        'what', format('follow up the %s half-finished registrations so that %s of them submit by %s', cardinality(v_ids), v_target, to_char(v_due at time zone 'Asia/Dubai', 'DD Mon')),
        'how', 'e-mail through the outbox (suppressions and opt-outs apply); WhatsApp only where the supplier opted in (ledger 1341); never a number that did not.'));
    if v_h is not null then
      n_orders := n_orders + 1;
      insert into public.ceo_supply_decision (decided_on, kind, subject, reason, reading, handoff_id, dedupe_key)
      values (v_today, 'order', 'sales_engineer: stuck_followed_up', format('%s of %s half-finished registrations submitted by %s', v_target, cardinality(v_ids), to_char(v_due at time zone 'Asia/Dubai', 'DD Mon')),
              jsonb_build_object('funnel', v_fun - 'limits'), v_h, 'order:stuck_followed_up:' || v_today) on conflict (dedupe_key) do nothing;
    end if;
  end if;
  -- 4c. the held registrations: customer support asks each supplier for what blocks the decision
  v_ids := array(select x from public.fn_supplier_registrations_held(p_at) x limit 50);
  if cardinality(v_ids) > 0 and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
                                              and a.detail->>'type' = 'ceo.order' and a.detail->>'measure' = 'held_unblocked') then
    v_due := p_at + interval '3 days';
    v_h := public.fn_seat_handoff('ceo', 'customer_support', 'ceo.order', 'supplier_coverage', 'held_unblocked:' || v_today,
      jsonb_build_object('path', 'coverage', 'measure', 'held_unblocked', 'lead_ids', to_jsonb(v_ids), 'target', 0, 'due_at', v_due,
        'decision', 'grow supply: unblock registrations', 'reasons', cardinality(v_ids) || ' registrations submitted more than 2 days ago are neither approved nor rejected',
        'what', format('unblock the %s held registrations by %s: ask each supplier for what blocks the decision and hand what arrives to the sales engineer, so none is still held', cardinality(v_ids), to_char(v_due at time zone 'Asia/Dubai', 'DD Mon')),
        'how', 'through the supplier''s own channel: e-mail through the outbox, WhatsApp only with his opt-in.'));
    if v_h is not null then
      n_orders := n_orders + 1;
      insert into public.ceo_supply_decision (decided_on, kind, subject, reason, reading, handoff_id, dedupe_key)
      values (v_today, 'order', 'customer_support: held_unblocked', format('%s held registrations to 0 by %s', cardinality(v_ids), to_char(v_due at time zone 'Asia/Dubai', 'DD Mon')),
              jsonb_build_object('funnel', v_fun - 'limits'), v_h, 'order:held_unblocked:' || v_today) on conflict (dedupe_key) do nothing;
    end if;
  end if;

  -- 5. THE RUN IS A ROW, so a day with nothing to order still proves the CEO looked
  insert into public.ceo_supply_decision (decided_on, kind, subject, reason, reading, dedupe_key)
  values (v_today, 'run', 'daily', format('coverage %s of %s (%s%%), %s orders filed, %s closed by measure', v_cov->>'covered_suppliers', v_cov->>'target_suppliers',
            coalesce(v_cov->>'coverage_pct', '-'), n_orders, n_closed),
          jsonb_build_object('coverage', v_cov - 'basis', 'funnel', v_fun - 'limits', 'board', coalesce(v_board, '{}'::jsonb)), 'run:' || v_today);
  return jsonb_build_object('ran', true, 'confirmed', v_conf, 'orders', n_orders, 'closed_by_measure', n_closed, 'coverage', v_cov - 'basis' - 'gaps', 'funnel', v_fun - 'limits');
end $fn$;
revoke execute on function public.fn_ceo_grows_supply(timestamptz) from public, anon, authenticated;

-- ── 7. THE FOUNDER'S DAILY SUMMARY: information, never a question ─────────────────────────────────────────────────
create or replace function public.fn_ceo_daily_summary_text(p_since timestamptz default now() - interval '24 hours')
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_cov jsonb := public.fn_supplier_coverage(5); v_fun jsonb := public.fn_supplier_funnel_reading(30); v_lim jsonb := public.fn_company_limits();
        v_out text;
begin
  v_out := 'SUPPLIER COVERAGE (founder ledger 1701): ' || coalesce(v_cov->>'covered_suppliers', '0') || ' of ' || coalesce(v_cov->>'target_suppliers', '0')
    || ' target suppliers (' || coalesce(v_cov->>'coverage_pct', '-') || '%) across ' || coalesce(v_cov->>'targets_confirmed', '0') || ' trade-areas; '
    || coalesce(v_cov->>'trades_at_target', '0') || ' at target; ' || coalesce(v_cov->>'verified_real_suppliers', '0') || ' verified real suppliers in all.'
    || coalesce(E'\nWidest gaps: ' || (select string_agg(g->>'trade' || ' / ' || (g->>'emirate') || ' ' || (g->>'verified') || ' of ' || (g->>'target'), '; ')
                                         from jsonb_array_elements(v_cov->'gaps') g), '')
    || E'\nFUNNEL, 30 days: invited ' || (v_fun->>'invited') || ', opened (a floor) ' || (v_fun->>'opened') || ', started ' || (v_fun->>'started')
    || ', submitted ' || (v_fun->>'submitted') || ', approved ' || (v_fun->>'approved') || '; started and stopped ' || (v_fun->>'started_and_stopped')
    || ', submitted and held ' || (v_fun->>'submitted_and_held') || '.'
    || E'\nCOMPANY LIMITS: AED ' || coalesce(v_lim->>'spent_today_aed', '0') || ' committed today of AED ' || coalesce(v_lim->>'daily_spend_aed', '?')
    || '; per action AED ' || coalesce(v_lim->>'per_action_aed', '?') || '.'
    || coalesce((select E'\nLIMIT CHANGES: ' || string_agg(c.limit_key || ' to AED ' || c.value_aed || ' from ' || to_char(c.effective_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
                         || ' (' || c.reason || ')', '; ' order by c.id)
                   from public.company_limit_change c where c.set_by = 'ceo' and (c.set_at >= p_since or c.effective_at > now())), '')
    || coalesce((select E'\nTHE CEO DECIDED (' || count(*) || '):' || string_agg(E'\n- ' || line, '' order by at) from (
          select (a.evidence->'ceo_decision'->>'decided_at')::timestamptz as at,
                 case a.detail->>'type'
                   when 'it.finding' then 'IT finding #' || a.id || ' (' || left(coalesce(a.detail->>'title', a.detail->>'issue_key', ''), 80) || '): '
                   when 'ceo.authority' then (a.detail->>'from') || ' asked ' || left(coalesce(a.detail->>'what', ''), 80) || ': '
                   else coalesce(a.detail->>'type', 'hand-over') || ' #' || a.id || ': ' end
                 || (a.evidence->'ceo_decision'->>'choice') || ' - ' || left(coalesce(a.evidence->'ceo_decision'->>'reason', ''), 160) as line
            from public.agent_actions a
           where a.kind = 'handoff' and a.evidence ? 'ceo_decision' and a.evidence->'ceo_decision'->>'decided_at' ~ '^\d{4}'
             and (a.evidence->'ceo_decision'->>'decided_at')::timestamptz >= p_since
          union all
          select (a.detail->'silence'->'ceo_decision'->>'decided_at')::timestamptz,
                 'late ' || coalesce(a.detail->>'type', '?') || ' #' || a.id || ' (' || coalesce(a.detail->'silence'->>'silent_seat', '?') || '): '
                 || (a.detail->'silence'->'ceo_decision'->>'choice') || ' - ' || left(coalesce(a.detail->'silence'->'ceo_decision'->>'reason', ''), 160)
            from public.agent_actions a
           where a.kind = 'handoff' and a.detail->'silence'->'ceo_decision'->>'decided_at' ~ '^\d{4}'
             and (a.detail->'silence'->'ceo_decision'->>'decided_at')::timestamptz >= p_since
          union all
          select g.granted_at, 'on his own authority: ' || g.action_class || ' on ' || g.subject || coalesce(' AED ' || g.amount_aed, '') || ' - ' || left(g.reason, 160)
            from public.ceo_grant_once g where g.seat = 'ceo' and g.granted_at >= p_since
          union all
          select d.created_at, 'supply ' || d.kind || ' ' || d.subject || ': ' || left(d.reason, 200)
            from public.ceo_supply_decision d where d.created_at >= p_since and d.kind <> 'run') x), '')
    || coalesce((select E'\nORDERS OPEN: ' || string_agg(a.agent || ' ' || coalesce(a.detail->>'measure', a.detail->>'path', 'order') || ' due '
                         || coalesce(to_char((a.detail->>'due_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon'), '?')
                         || coalesce(' (now ' || (a.detail->'reading_now'->>'value') || ' of ' || (a.detail->'reading_now'->>'target') || ')', ''), '; ' order by a.id)
                   from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'ceo.order' and a.status = 'pending'), '')
    || E'\nThis is information: the CEO decides (founder ledger 1696). Nothing here waits on you.';
  return v_out;
end $fn$;
revoke execute on function public.fn_ceo_daily_summary_text(timestamptz) from public, anon, authenticated;

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  ('ceo_daily_summary', true, 'Once a day, information only (founder ledger 1696: the CEO decides, the founder is told): supplier coverage against target, the funnel, the CEO''s decisions with their reasons, the company limits and any waiting change. It never asks him anything.', 'ceo')
on conflict (kind) do nothing;

create or replace function public.fn_ceo_daily_summary_to_the_founder(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_key text := 'ceo_daily_summary:' || to_char(p_at at time zone 'Asia/Dubai', 'YYYY-MM-DD'); v_r jsonb;
begin
  if (p_at at time zone 'Asia/Dubai')::time < time '07:00' then return jsonb_build_object('told', false, 'reason', 'before 07:00 Dubai'); end if;
  if exists (select 1 from public.founder_alerts f where f.dedupe_key = v_key) then return jsonb_build_object('told', false, 'reason', 'already told today'); end if;
  v_r := public.fn_notify_founder('The CEO''s day: supplier coverage and decisions', public.fn_ceo_daily_summary_text(p_at - interval '24 hours'),
                                  'info', 'ceo_daily_summary', v_key, 'ceo');
  return jsonb_build_object('told', true, 'result', v_r);
end $fn$;
revoke execute on function public.fn_ceo_daily_summary_to_the_founder(timestamptz) from public, anon, authenticated;

-- ── 8. ONE DUTY ───────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_supply_coverage_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := '{}'::jsonb;
begin
  begin v := v || jsonb_build_object('supply', public.fn_ceo_grows_supply(now()));
  exception when others then v := v || jsonb_build_object('supply_error', left(sqlerrm, 300)); end;
  begin v := v || jsonb_build_object('founder', public.fn_ceo_daily_summary_to_the_founder(now()));
  exception when others then v := v || jsonb_build_object('founder_error', left(sqlerrm, 300)); end;
  return v;
end $fn$;
revoke execute on function public.fn_ceo_supply_coverage_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.supply_coverage', 'ceo', interval '1 hour', 'fn_ceo_supply_coverage_tick',
   'Founder ledger 1701: once a day after 06:00 Dubai, read supplier coverage against target, the funnel and the seats'' board, confirm the targets on the first run, order the seats (invitations, half-finished and held registrations) with a measured outcome and a date, measure and close the orders; then tell the founder the day (information, ledger 1696).',
   'scripts/sql/the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── 9. THE PROPOSAL, written at apply (the CEO confirms it on his first run) ──────────────────────────────────────
select public.fn_supplier_coverage_target_propose();
