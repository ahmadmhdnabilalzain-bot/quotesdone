-- THE CEO THINKS, PLANS AND ORDERS EVERY WEEK. Seat: ceo (agent: ceo seat builder). 15 Nov 2026.
-- Founder, ledger 1696 (15 Nov 2026): "CEO is having full authority ... He doesnt rely on me in anything."
-- Founder, ledger 1701: "I want to be profitable and that should be the main concern for the CEO ... enough registered
-- suppliers ... then a customer campaign".
-- Founder, ledger 1705/1706 (15 Nov 2026, voice): "instead of him just telling me issues, he need to find solutions ... How can I
-- get leads? ... Is it safe? If not, what's the alternative? ... KPI ... is about actually taking action ... What plan shall I
-- give for my team". The CEO brings solutions, not issues.
-- Founder, ledger 1709 (15 Nov 2026, voice): no hire. The founder personally messages and calls his own network from his own
-- number (his estimate: 20 to 100 registrations), through the tracked link
-- https://quotesdone.com/portal?join=1&utm_source=founder&utm_medium=whatsapp&utm_campaign=2026-11 (src/lib/firstTouch.ts keeps
-- the tags; supplier_api writes them to marketing_first_touch at registration). The CEO counts his people by that tag and tells
-- him daily who started, submitted and was approved, and who is stuck at which step, so he can call them.
--
-- MEASURED BEFORE THIS FILE (the CEO seat audit, SP/audit/CEO.md, SELECT 15 Nov 2026):
--   * the CEO was 40 duties of fixed SQL rules. The daily plan's model slot (app_secrets.ceo_model_slot) has been off since
--     22 Sep; all 30 plans in 30 days read decided_by plan_c_code. Of AED 228.55 of CEO model spend in 30 days, AED 3.77 went on
--     its own decisions.
--   * 2 decision asks went to the founder in 30 days ("CEO: the AED 1M revenue forecast needs your decision"), against 1696.
--   * the CEO re-issued "re-check compliance source #N" directives TO ITSELF: 72 open or escalated on 15 Nov (36 + 36,
--     source_kind register_review). Nothing in the estate updates compliance_sources.last_checked_at (READ), so no seat could
--     ever meet one of them.
--   * the knowledge-exam spend (AED 155 of the CEO's 30 days) was three paid exam sweeps run by sessions (19 Oct AED 275 for all
--     seats, 27 Oct AED 9.25, 1 Nov AED 6.62, every row tagged with an e2e run); the duty it_engineer.knowledge_exam is disabled.
--     It is not a recurring cost and this file changes nothing there.
--   * 2 approved real suppliers; 129 invited in 30 days, all Google-hosted; 5 replies, all 5 dropped by the reply path;
--     Microsoft 0/21 and Yahoo/AOL 0/17 inbox on the 10 Nov GlockApps test; invite_enabled false; 0 rows in marketing_first_touch.
-- WHAT THIS ADDS (the model proposes; CODE measures and checks, ledger 1663):
--   1. fn_ceo_planning_pack(days): ONE routine, one JSON document: the funnel by step and by channel, registrations by first-touch
--      source per day (founder / e-mail invitation / other tags / untagged), the founder's people step by step, placement by
--      provider, replies and how each was handled, coverage against the targets and the operating target, demand signals, the
--      never-invited pool by mailbox provider, spend against the company limits and the runway, each seat's board and open
--      orders, the rulings in force, the channel register with its safety verdicts and its learned priors, the capability
--      register, the last plan's predictions against what happened, and the CEO's own recent decisions. A section that cannot
--      be read says why ({"unavailable": ...}); it never fails the pack.
--   2. public.ceo_growth_channel: the safety verdict of every channel (safe / safe_if / refused, the rule it rests on, the
--      ruling numbers, and the ALTERNATIVE when refused) and its conversion prior (a Beta(alpha, beta) per channel, updated daily
--      from recorded outcomes by fn_ceo_priors_update, so next week's plan learns).
--   3. THE LOOP: fn_ceo_plan_due (the resilience_ping CEO tick, every 15 minutes): measures every open bet daily, updates the
--      priors, files the seeded first plan on its first run, and asks for a plan when one is due:
--        weekly  Monday from 07:00 Dubai: the reasoned plan, task class ceo_strategic_planning (the CEO's hard route, Opus, effort
--                high: model_policy_states_the_effort_of_every_task_class.sql), at most one revision;
--        daily   other days from 07:30 Dubai: code measures first; the model (routine_employee_reasoning, the CEO's cheap route)
--                is asked ONLY when code found an anomaly (a dropped or overdue reply, a late order, one of the founder's people
--                stuck two days, invitations bouncing over 3%), and may add at most two bets.
--      The model answers in ceo_agent (action 'plan', supabase/functions/ceo_agent/plan.ts) through makeLlmRich -> ai_gateway.
--   4. fn_ceo_plan_file: CODE checks every bet before it becomes an order (fn_ceo_plan_bet_check): the channel's verdict (a
--      refused channel is refused with its alternative), the seat (one that takes a ceo.order), a measure code can read with a
--      target and a due date inside six weeks, the message gates for every named recipient (fn_company_message_gates), the
--      inbox-placement providers of an e-mail batch, the company limits for any money (fn_company_spend_fits), a capability no
--      seat has today (only a build order may name it), switched-off invitations, an open order on the same measure, and any
--      question to the founder. A passed bet is a ceo.order hand-over with its measure, target and due date; a refused bet goes
--      back to the model ONCE with the reasons; a second refusal is recorded and the bet dropped.
--   5. THE FIRST PLAN AS DATA (week of 16 Nov 2026, the audit's plan, revised for ruling 1709): the operating target (30 verified
--      suppliers in three Dubai focus trades by 20 Dec: MEP, interior fit-out, construction materials), the narrowing of the
--      coverage targets to those trades, and the 16 Nov bets per seat. It is a ceo_plan_week row of kind 'seed'; the loop's first
--      run files it through the same checks as any model plan. Nothing here sends anything.
--   6. NO FOUNDER ASK: the forecast's third choice was "tell_founder" ("a decision only the founder holds"); it is now
--      "act_within_authority" (the CEO changes a limit, a target or the plan himself), and an answer still carrying the old
--      choice is recorded as the CEO's own decision (public.ceo_own_decision) with its reason. Nothing goes to the founder from
--      the forecast. He is told the day in the daily summary, which now also carries the week's plan and his own people.
--   7. BUSY-WORK CUT: the stale compliance sources become ONE monthly directive to the it_engineer (the seat that can build the
--      fetch), not one directive per source to the CEO; the 72 open self-addressed re-checks are closed as superseded.
-- NOT HERE (ruling 1709): no hire request. The channel register records a hired caller as refused, with the alternative.
-- FIXTURES: qd.duty_fixtures = 'on' (the estate's probe seam) makes every reading see ONLY demo rows; without it ONLY real ones.
-- prevented by: scripts/checks/the_ceo_plans_every_week_and_code_checks_every_order.test.mjs (text),
-- the_ceo_thinks_plans_and_orders_every_week_probe.sql (LOCAL, every rule executed), supabase/functions/ceo_agent/plan.test.ts
-- APPLY ORDER: after the three files of the branch ceo-the-ceo-acts-and-orders-the-seats-to-grow-supply (the limits, the pool,
-- the coverage file): it reads fn_company_message_gates, fn_company_spend_fits, ceo.order and fn_supplier_coverage.
-- LOCKS: five new tables (ACCESS EXCLUSIVE on them only, at first apply); ROW EXCLUSIVE from inserts into decision_policy and
-- seat_duty (one row each), one UPDATE of model_policy (one row) and one UPDATE of ceo_directive (the superseded self re-checks, 72 rows on 15 Nov). No busy table is
-- altered. The seed's own actions (ceo_invite_trade_priority, supplier_coverage_target) run at the loop's first run, not at apply.
set local lock_timeout = '1500ms';

-- ── 0. WHICH WORLD A READING SEES (the branch's predicate, one place) ────────────────────────────────────────────────────
create or replace function public.fn_ceo_plan_world_is_demo()
returns boolean language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'
$fn$;
revoke execute on function public.fn_ceo_plan_world_is_demo() from public, anon, authenticated;

create or replace function public.fn_ceo_plan_lead_in_world(p_is_demo boolean, p_company text, p_email text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select (coalesce(p_is_demo, false) or coalesce(p_company, '') ilike 'ZZ DEMO%' or public.fn_is_demo_email(coalesce(p_email, '')))
         = public.fn_ceo_plan_world_is_demo()
$fn$;
revoke execute on function public.fn_ceo_plan_lead_in_world(boolean, text, text) from public, anon, authenticated;

-- ── 1. TABLES ────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_growth_channel (
  channel text primary key check (channel ~ '^[a-z0-9_]{3,60}$'),
  verdict text not null check (verdict in ('safe', 'safe_if', 'refused')),
  owner_seat text not null,
  conditions text not null check (length(btrim(conditions)) >= 20),
  refused_because text,
  alternative text,
  rulings integer[] not null default '{}',
  gate_channel text check (gate_channel in ('email', 'whatsapp')),
  gate_placement boolean not null default false,
  capability text not null default 'ready',
  unit text not null,
  alpha numeric not null default 1 check (alpha > 0),
  beta numeric not null default 1 check (beta > 0),
  trials integer not null default 0,
  successes integer not null default 0,
  prior_basis text not null,
  measured_until timestamptz,
  updated_at timestamptz not null default now(),
  constraint ceo_growth_channel_refusal_says_why check (verdict <> 'refused' or (length(btrim(coalesce(refused_because, ''))) >= 20 and length(btrim(coalesce(alternative, ''))) >= 20)));
comment on table public.ceo_growth_channel is 'The CEO''s channel register (founder ledger 1705/1706: is it safe, and if not, what is the alternative): each channel''s safety verdict with its rule and rulings, the gate a named recipient must pass, whether a seat can do it today, and its conversion prior Beta(alpha, beta) learned from recorded outcomes. the_ceo_thinks_plans_and_orders_every_week.sql';

create table if not exists public.ceo_operating_target (
  id bigserial primary key,
  objective text not null check (length(btrim(objective)) >= 20),
  emirate text not null,
  due_on date not null,
  groups jsonb not null check (jsonb_typeof(groups) = 'array'),
  status text not null default 'active' check (status in ('active', 'met', 'retired')),
  source text not null check (length(btrim(source)) >= 20),
  set_at timestamptz not null default now(),
  retired_at timestamptz);
comment on table public.ceo_operating_target is 'The CEO''s operating target under the founder''s north star (ledger 1701): verified suppliers per focus trade group in one emirate by a date. groups = [{group, label, trades[], target}]. the_ceo_thinks_plans_and_orders_every_week.sql';

create table if not exists public.ceo_plan_week (
  id bigserial primary key,
  kind text not null check (kind in ('seed', 'weekly', 'daily')),
  period date not null,
  status text not null default 'asked' check (status in ('asked', 'revise', 'filed', 'held', 'measured')),
  task_class text,
  pack jsonb not null default '{}'::jsonb,
  anomalies jsonb not null default '[]'::jsonb,
  output jsonb,
  revision integer not null default 0 check (revision in (0, 1)),
  refusals jsonb not null default '[]'::jsonb,
  model text,
  error text,
  attempts integer not null default 0,
  created_at timestamptz not null default now(),
  asked_at timestamptz,
  filed_at timestamptz,
  unique (kind, period));
comment on table public.ceo_plan_week is 'One CEO plan: the seeded first plan, the weekly reasoned plan (Monday) or the daily light review. pack is what it read; output what the model (or the seed) proposed; refusals what code refused and why. the_ceo_thinks_plans_and_orders_every_week.sql';

create table if not exists public.ceo_plan_bet (
  id bigserial primary key,
  plan_id bigint not null references public.ceo_plan_week(id) on delete cascade,
  revision integer not null default 0,
  ord integer not null,
  channel text not null,
  seat text,
  what text not null,
  measure text not null,
  measure_args jsonb not null default '{}'::jsonb,
  direction text not null default 'at_least' check (direction in ('at_least', 'at_most')),
  target numeric,
  due_at timestamptz,
  expected_low numeric,
  expected_high numeric,
  cost_aed numeric not null default 0,
  legal text,
  kill_criterion text,
  status text not null check (status in ('filed', 'refused', 'met', 'missed', 'withdrawn')),
  refusal text[] not null default '{}',
  handoff_id bigint,
  actual numeric,
  met_at timestamptz,
  scored_at timestamptz,
  created_at timestamptz not null default now(),
  unique (plan_id, revision, ord));
comment on table public.ceo_plan_bet is 'Each bet of a CEO plan as code saw it: filed as a ceo.order (handoff_id) with a measure, target and due date, or refused with the reasons; scored met or missed by its measure, with the actual. the_ceo_thinks_plans_and_orders_every_week.sql';

create table if not exists public.ceo_own_decision (
  id bigserial primary key,
  source text not null,
  subject text not null,
  choice text not null,
  reason text not null,
  reading jsonb not null default '{}'::jsonb,
  dedupe_key text not null unique,
  created_at timestamptz not null default now());
comment on table public.ceo_own_decision is 'A decision the CEO takes himself where the estate used to ask the founder (ledger 1696), and his own actions from a plan (trade priorities, coverage targets), each with its reason; in the founder''s daily summary as information. the_ceo_thinks_plans_and_orders_every_week.sql';

do $guard$
declare t text;
begin
  foreach t in array array['ceo_growth_channel', 'ceo_operating_target', 'ceo_plan_week', 'ceo_plan_bet', 'ceo_own_decision'] loop
    if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
      execute format('alter table public.%I enable row level security', t);
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_service_role_only') then
      execute format('create policy %I on public.%I as permissive for all to public using (false) with check (false)', t || '_service_role_only', t);
    end if;
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
  if to_regclass('public.ceo_plan_bet_open') is null then
    create index ceo_plan_bet_open on public.ceo_plan_bet (status) where status = 'filed';
  end if;
end $guard$;
revoke all on sequence public.ceo_operating_target_id_seq, public.ceo_plan_week_id_seq, public.ceo_plan_bet_id_seq, public.ceo_own_decision_id_seq from anon, authenticated;

insert into public.decision_policy (key, value, description) values
  ('ceo_planning_loop', '{"weekly_on": true, "daily_on": true, "weekly_task_class": "ceo_strategic_planning", "daily_task_class": "routine_employee_reasoning", "week_aed_cap": 8, "weekly_local": "07:00", "daily_local": "07:30", "max_bets_weekly": 8, "max_bets_daily": 2, "max_due_days": 42}'::jsonb,
   'The CEO''s planning loop (founder ledger 1696/1701/1705): a weekly reasoned plan on the CEO''s hard route (Monday), a daily light review on the routine route only when code found an anomaly; week_aed_cap bounds the loop''s own model spend over 7 days (ai_cost_log fn ceo_agent, the two classes). the_ceo_thinks_plans_and_orders_every_week.sql')
on conflict (key) do nothing;

-- The weekly plan answers 3 to 6 options and up to 8 bets as JSON: about 3,000 to 5,000 tokens. ai_gateway takes the smaller of
-- the asked maximum and the route's; ceo_strategic_planning had 4,000 (SELECT 15 Nov) and no caller, so a full plan would be cut
-- off and held. 8,000 for this class only.
update public.model_policy set max_tokens = 8000 where task_class = 'ceo_strategic_planning' and coalesce(max_tokens, 0) < 8000;

-- ── 2. THE CHANNEL REGISTER: safety verdicts (the audit, section 6 and 8) and starting priors ─────────────────────────────
-- A prior is Beta(alpha, beta) over the channel's unit. Where nothing is measured it starts flat (1, 1) and the basis says so;
-- e-mail starts from the one measured rate (1 submitted of 115 delivered, 30 days to 15 Nov, SELECT).
insert into public.ceo_growth_channel (channel, verdict, owner_seat, conditions, refused_because, alternative, rulings, gate_channel, gate_placement, capability, unit, alpha, beta, prior_basis) values
  ('founder_network', 'safe', 'founder', 'People the founder knows, messaged and called personally from his own number with his tracked link (utm_source=founder); the CEO counts them by first touch and tells him daily who is stuck at which step.', null, null, '{1620,1709}', null, false, 'ready',
   'a registration started with utm_source founder -> submitted', 1, 1, 'nothing measured yet (0 rows in marketing_first_touch on 15 Nov); the founder estimates 20 to 100 registrations (ledger 1709)'),
  ('reply_within_1h', 'safe', 'sales_engineer', 'Answer every supplier reply within one business hour with the registration link: a reply to their own mail (ledger 1301 covers the cold invitation only); answer only what they wrote; a STOP is honoured.', null, null, '{1301,1537}', 'email', false, 'ready',
   'a supplier reply answered -> registration submitted', 1, 1, '5 replies in 30 days, all 5 dropped unanswered by the reply path (SELECT 15 Nov): no answered reply to learn from yet'),
  ('email_invitation_google', 'safe_if', 'sales_engineer', 'Cold e-mail only to Google-hosted, verified addresses, inside the 1231 schedule (up to 50 a day), bounce under 3%, checked-only, STOP line, one-click unsubscribe, no link (1301); and only while invitations are switched on.', null, null, '{1231,1301,1537}', 'email', true, 'ready',
   'an invitation delivered -> registration submitted', 1, 114, 'measured: 1 submitted of 115 delivered Google-class invitations, 30 days to 15 Nov 2026 (SELECT)'),
  ('email_followup_nudge', 'safe_if', 'sales_engineer', 'One plain-text follow-up to a non-replier after 5 working days; stops on any reply or STOP; the same gates as the invitation.', null, null, '{1231,1301}', 'email', true, 'ready',
   'a nudge delivered -> registration submitted', 1, 1, 'nothing measured: nudges were sent to too few to read'),
  ('registration_unblock', 'safe', 'sales_engineer', 'Follow up a half-finished or held registration through the supplier''s own channel: e-mail through the outbox (suppressions apply), WhatsApp only with his opt-in.', null, null, '{1341}', 'email', false, 'ready',
   'a stuck or held registration -> submitted or decided', 1, 1, '0 stuck and 0 held on 15 Nov (SELECT): nothing to learn from yet'),
  ('supplier_referral', 'safe', 'sales_engineer', 'At approval, ask the supplier who else in his trade should get requests, with his own referral link; he sends from his own channel; we never take his contact list.', null, null, '{}', null, false, 'missing: no referral link or ask at approval is built (it_engineer)',
   'an approved supplier -> a referred registration', 1, 1, 'not built; 2 approved suppliers'),
  ('whatsapp_click_to_chat', 'safe', 'customer_support', 'A wa.me link on the site, the registration page and the e-mail signature: the supplier starts the chat; replies inside the 24-hour window; templates only to opt-ins; the consent question asked (ledger 1341).', null, null, '{1341}', null, false, 'missing: no click-to-chat link on the invitation path (it_engineer)',
   'a supplier-started chat -> registration submitted', 1, 1, 'not built; 0 opt-ins on 15 Nov'),
  ('linkedin_company_page', 'safe', 'marketing', 'Organic company-page posts for the focus trades; never boosted (ledger 1456).', null, null, '{1456}', null, false, 'ready',
   'a post -> a tagged registration (utm_source linkedin)', 1, 1, '0 posts in the last 30 days'),
  ('directories_chamber', 'safe', 'marketing', 'List QuotesDone with the Dubai Chamber, DET and business-group newsletters; a short supplier call-out; no paid placement without the company limits.', null, null, '{1456}', null, false, 'ready',
   'a placement -> a tagged registration', 1, 1, 'nothing measured; Dubai Chamber membership status not checked'),
  ('google_business_profile', 'safe', 'marketing', 'QuotesDone''s own profile with its real address and category; no reviews solicited with a reward; honest copy.', null, null, '{}', null, false, 'ready',
   'trust and search, not reach', 1, 1, 'nothing measured'),
  ('deliverability_fix', 'safe', 'it_engineer', 'Raise Microsoft inbox placement to at least 80% on a GlockApps retest by honest warm-up of the one mailbox, for the mail registered suppliers must receive (invitations stay off Microsoft by ruling 1537); never lookalike domains or snowshoeing.', null, null, '{1537}', null, false, 'ready',
   'a GlockApps retest -> Microsoft inbox share', 1, 1, 'Microsoft 0/18 and 0/21 inbox since 27 Oct (SELECT)'),
  ('demand_data', 'safe', 'it_engineer', 'Search Console, site search and chat intents into demand_search, no personal data, so the focus trades are re-picked from demand.', null, null, '{}', null, false, 'ready',
   'a month of demand rows -> focus trades re-picked', 1, 1, 'demand_search and demand_forecast hold 0 rows'),
  ('linkedin_manual_personal', 'safe_if', 'founder', 'Only a person''s own manual outreach from his own account, at most 20 personalised requests a day; no seat is a person, and no hire (ledger 1709), so only the founder''s own network counts here.', null, null, '{1709}', null, false, 'missing: no person to send (ledger 1709: no hire)',
   'a personal request -> registration', 1, 1, 'nothing measured'),
  ('whatsapp_cold_scraped', 'refused', 'customer_support', 'A WhatsApp template to a number we scraped or bought.',
   'Meta Business Messaging Policy: only a person who gave the number and agreed to our messages (ledger 1184, 1341); the quality rating falls and the number is banned, taking down support and the founder''s channel.',
   'The click-to-chat link and the consent question (whatsapp_click_to_chat), supplier referral, and the founder''s own network.', '{1184,1341}', 'whatsapp', false, 'ready', 'refused', 1, 1, 'refused: never tried'),
  ('linkedin_automation', 'refused', 'marketing', 'Automating a personal LinkedIn account: bots, auto-connect, scraping, automated messages.',
   'LinkedIn User Agreement section 8.2 forbids bots and automated messaging; the account is banned.',
   'Organic company-page posts (linkedin_company_page) and a person''s own manual outreach (the founder''s network).', '{}', null, false, 'ready', 'refused', 1, 1, 'refused: never tried'),
  ('paid_ads', 'refused', 'marketing', 'Ads on any platform (LinkedIn, Google, Meta) to recruit suppliers now.',
   'Founder ledger 1456: no ads, because customers would register before there are suppliers to serve them.',
   'Organic company page, Dubai Chamber and DET listings (directories_chamber), the founder''s network.', '{1456}', null, false, 'ready', 'refused', 1, 1, 'refused by ruling'),
  ('bulk_sms', 'refused', 'customer_support', 'Bulk SMS to suppliers.',
   'Founder ledger 1185 (too expensive, not now); TDRA sender-ID and consent rules.',
   'Not needed: e-mail to the Google class, the founder''s network, click-to-chat.', '{1185}', null, false, 'ready', 'refused', 1, 1, 'refused by ruling'),
  ('email_microsoft_yahoo', 'refused', 'sales_engineer', 'Mailing Microsoft- or Yahoo/AOL-hosted (and Etisalat-hosted) addresses while they fail inbox placement.',
   'Founder instruction 1537 (3 Nov 2026): invitations never go to Yahoo/AOL or Microsoft, whatever the GlockApps verdict says; the 10 Nov test put Microsoft 0/21 and Yahoo/AOL 0/17 in spam, and mail there burns the domain''s reputation.',
   'The Google class (email_invitation_google), the founder''s own network, click-to-chat and referral; deliverability_fix still matters for the registration and approval mail the founder''s Microsoft-hosted people must receive.', '{1537}', 'email', true, 'ready', 'refused', 1, 1, 'refused by ruling 1537'),
  ('lookalike_domains', 'refused', 'it_engineer', 'Rotating lookalike sending domains or mailboxes to spread volume (snowshoeing).',
   'Google and Microsoft bulk-sender policies treat it as spam evasion; it ruins every domain it touches.',
   'Honest warm-up of the one supplier mailbox (deliverability_fix).', '{}', null, false, 'ready', 'refused', 1, 1, 'refused: never tried'),
  ('bought_or_scraped_lists', 'refused', 'sales_engineer', 'Buying a list, or scraping new contacts.',
   'UAE PDPL; the founder paused Apify until 2027; 19,939 never-invited leads already exist.',
   'Work the existing pool by mailbox provider (email_invitation_google) and the founder''s network.', '{}', null, false, 'ready', 'refused', 1, 1, 'refused: never tried'),
  ('hired_caller', 'refused', 'sales_engineer', 'Hiring a person (part-time associate or caller) to call or message suppliers.',
   'Founder ledger 1709 (15 Nov 2026): not possible by hiring someone; the founder calls and messages his own network himself.',
   'The founder''s own network (founder_network), with the CEO''s daily list of who is stuck at which step.', '{1709}', null, false, 'ready', 'refused', 1, 1, 'refused by ruling'),
  ('ai_voice_outbound', 'refused', 'customer_support', 'An automated (AI) voice calling suppliers.',
   'TDRA telemarketing rules (Cabinet Resolution 56 of 2024): the B2B scope is not confirmed from the official text, there is no company outbound number, and an automated caller must say so; none of that exists.',
   'The founder''s own calls to his network; a legal check first, then a disclosed AI voice on a company number.', '{1709}', null, false, 'ready', 'refused', 1, 1, 'refused until a legal check')
on conflict (channel) do nothing;
-- the seeded priors already hold what was measured up to apply: learning starts from here, so no window is counted twice
update public.ceo_growth_channel set measured_until = now() where measured_until is null;

-- ── 3. THE OPERATING TARGET (the audit's honest verdict: 300-400 by 31 Dec cannot be reached; 30 in three Dubai trades by 20 Dec) ─
insert into public.ceo_operating_target (objective, emirate, due_on, groups, source)
select '30 verified suppliers in three Dubai focus trades by 20 Dec 2026, so that those trades open to buyers (trade_opening_rule.open_at_suppliers = 10); the founder''s 300-400 by 31 Dec stays the north star.',
       'Dubai', date '2026-12-20',
       '[{"group":"mep","label":"MEP: HVAC, electrical, plumbing","trades":["hvac","electrical","electrical_wholesale","mep_general","plumbing"],"target":10},
         {"group":"interior_fitout","label":"Interior fit-out: fit-out, gypsum and ceilings, flooring","trades":["interior_fitout","gypsum","flooring"],"target":10},
         {"group":"construction_materials","label":"Construction materials","trades":["building_materials","masonry_blockwork","steel","steel_stock"],"target":10}]'::jsonb,
       'The CEO seat audit of 15 Nov 2026 (SP/audit/CEO.md section 8): the only recorded demand is 2 HVAC customers waiting and 1 electrical intake; fit-out has the highest fee per request and the largest reachable Dubai pool; materials suppliers quote fast from stock. Trade codes are the active taxonomy codes (SELECT 15 Nov).'
 where not exists (select 1 from public.ceo_operating_target where status = 'active');

-- Verified suppliers per focus group, by the predicate fn_supplier_coverage uses (confirmed capabilities, fn_is_matchable, stated
-- emirates hold the emirate or none stated), demo excluded; a supplier counts once per group.
create or replace function public.fn_ceo_focus_coverage()
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.ceo_operating_target; v jsonb;
begin
  select * into t from public.ceo_operating_target where status = 'active' order by id desc limit 1;
  if not found then return jsonb_build_object('active', false); end if;
  with sup as materialized (
    select sc.supplier_id, sc.trades,
           array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[]) || coalesce(l.service_emirates, '{}'::text[])) e
                  where nullif(btrim(e), '') is not null) as stated
      from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null and coalesce(l.is_demo, false) = public.fn_ceo_plan_world_is_demo()
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)),
  g as (
    select x->>'group' as grp, x->>'label' as label, (x->>'target')::int as target,
           array(select jsonb_array_elements_text(x->'trades')) as trades
      from jsonb_array_elements(t.groups) x),
  c as (
    select g.grp, g.label, g.target, g.trades,
           (select count(distinct s.supplier_id) from sup s where s.trades && g.trades
              and (cardinality(s.stated) = 0 or lower(t.emirate) = any(s.stated)))::int as verified
      from g)
  select jsonb_build_object('active', true, 'id', t.id, 'objective', t.objective, 'emirate', t.emirate, 'due_on', t.due_on,
           'days_left', t.due_on - (now() at time zone 'Asia/Dubai')::date,
           'target', (select sum(target) from c), 'verified', (select sum(least(verified, target)) from c),
           'groups', (select jsonb_agg(jsonb_build_object('group', grp, 'label', label, 'target', target, 'verified', verified, 'gap', greatest(target - verified, 0), 'trades', to_jsonb(trades))) from c))
    into v;
  return v;
end $fn$;
revoke execute on function public.fn_ceo_focus_coverage() from public, anon, authenticated;

-- While an operating target is active, a supply_gap recruitment note outside its trades is not proposed again once the CEO has
-- retired it (real demand, inquiries and the waitlist, is still proposed anywhere). The rest is the coverage file's body as is.
create or replace function public.fn_supplier_coverage_target_propose()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.trade_opening_rule; v_target int; n_inq int := 0; n_wait int := 0; n_gap int := 0;
        v_rule_src text; v_focus text[];
begin
  select * into r from public.trade_opening_rule where id = 1;
  v_target := coalesce(r.open_at_suppliers, (select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  v_rule_src := 'target ' || v_target || ' = trade_opening_rule.open_at_suppliers, the verified suppliers at which a trade opens to customers ('
                || coalesce(r.reason, 'pricing_config.category_open_min_suppliers') || ')';
  v_focus := array(select jsonb_array_elements_text(x->'trades') from public.ceo_operating_target o, jsonb_array_elements(o.groups) x where o.status = 'active');
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
       -- the CEO narrowed the targets to his operating target's trades: a recruitment note he retired is not proposed again
       and not (cardinality(v_focus) > 0 and not (g.trade = any(v_focus))
                and exists (select 1 from public.supplier_coverage_target x where x.trade = g.trade and x.emirate = g.emirate and x.status = 'retired'))
    returning 1)
  select count(*) into n_gap from ins;
  return jsonb_build_object('proposed_from_inquiries', n_inq, 'proposed_from_waitlist', n_wait, 'proposed_from_recruitment_decisions', n_gap,
                            'target_each', v_target, 'proposed_total', (select count(*) from public.supplier_coverage_target where status = 'proposed'));
end $fn$;
revoke execute on function public.fn_supplier_coverage_target_propose() from public, anon, authenticated;

-- ── 4. REGISTRATIONS BY FIRST TOUCH (ruling 1709) ──────────────────────────────────────────────────────────────────────────
-- Every registration in the window by its source: 'founder' (utm_source founder), 'email_invitation' (a supplier_invite the
-- outbox sent before the registration, no tag), another tag by its own name, or 'untagged'. Started = the lead row the
-- registration created (marketing_first_touch.recorded_at, or the lead's own first visit); submitted and approved as recorded.
create or replace function public.fn_ceo_registrations_by_source(p_since timestamptz, p_until timestamptz default now())
returns table (lead_id bigint, source text, started_at timestamptz, submitted_at timestamptz, approved_at timestamptz,
               approval_status text, email_verified boolean, company text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with reg as (
    select l.id, l.company_name, l.registration_submitted_at, l.approved_at, l.approval_status,
           (coalesce(l.owner_email_verified, false) or coalesce(l.claimed, false)) as verified_owner,
           ft.utm_source,
           coalesce(ft.recorded_at, l.invite_clicked_at, l.portal_updated_at, l.registration_submitted_at) as started_at,
           exists (select 1 from public.notifications n where n.lead_id = l.id and n.type in ('supplier_invite', 'supplier_invite_wa') and n.status = 'sent') as invited
      from public.leads l left join public.marketing_first_touch ft on ft.lead_id = l.id
     where public.fn_ceo_plan_lead_in_world(l.is_demo, l.company_name, l.email)
       and (ft.lead_id is not null or coalesce(l.owner_email_verified, false) or coalesce(l.claimed, false) or l.registration_submitted_at is not null))
  select r.id, case when lower(r.utm_source) = 'founder' then 'founder'
                    when r.utm_source is not null then lower(r.utm_source)
                    when r.invited then 'email_invitation' else 'untagged' end,
         r.started_at, r.registration_submitted_at, r.approved_at, r.approval_status, r.verified_owner,
         coalesce(nullif(btrim(r.company_name), ''), 'registration #' || r.id)
    from reg r
   where r.started_at >= p_since and r.started_at < p_until
$fn$;
revoke execute on function public.fn_ceo_registrations_by_source(timestamptz, timestamptz) from public, anon, authenticated;

-- The step a registration is stuck at, in words the founder can act on (no address, no phone: only what he already knows).
create or replace function public.fn_ceo_registration_step(p_email_verified boolean, p_submitted_at timestamptz, p_approval_status text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case when p_approval_status = 'approved' then 'approved'
              when p_approval_status = 'rejected' then 'rejected: our reviewer gave the reason in the portal'
              when p_submitted_at is not null then 'submitted, waiting for our review'
              when coalesce(p_email_verified, false) then 'account made, documents not submitted'
              else 'opened the link, e-mail not confirmed' end
$fn$;
revoke execute on function public.fn_ceo_registration_step(boolean, timestamptz, text) from public, anon, authenticated;

create or replace function public.fn_ceo_founder_network_reading(p_since timestamptz default timestamptz '2026-11-01 00:00+04')
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with f as (select * from public.fn_ceo_registrations_by_source(p_since, now()) where source = 'founder')
  select jsonb_build_object(
    'since', p_since,
    'started', (select count(*) from f), 'submitted', (select count(*) from f where submitted_at is not null),
    'approved', (select count(*) from f where approval_status = 'approved'),
    'stuck', coalesce((select jsonb_agg(jsonb_build_object('company', company, 'step', public.fn_ceo_registration_step(email_verified, submitted_at, approval_status),
                                  'since', coalesce(submitted_at, started_at), 'days', round(extract(epoch from now() - coalesce(submitted_at, started_at)) / 86400.0, 1)) order by started_at)
                         from f where coalesce(approval_status, '') <> 'approved' and coalesce(submitted_at, started_at) < now() - interval '1 day'), '[]'::jsonb),
    'link', 'https://quotesdone.com/portal?join=1&utm_source=founder&utm_medium=whatsapp&utm_campaign=2026-11')
$fn$;
revoke execute on function public.fn_ceo_founder_network_reading(timestamptz) from public, anon, authenticated;

-- ── 5. THE PLANNING PACK ───────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_planning_pack(p_days integer default 7)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_days int := greatest(coalesce(p_days, 7), 1); v_from timestamptz := now() - make_interval(days => greatest(coalesce(p_days, 7), 1));
        v jsonb := jsonb_build_object('at', now(), 'days', greatest(coalesce(p_days, 7), 1), 'world', case when public.fn_ceo_plan_world_is_demo() then 'demo' else 'real' end);
        x jsonb;
begin
  -- the operating target and coverage
  begin v := v || jsonb_build_object('operating_target', public.fn_ceo_focus_coverage());
  exception when others then v := v || jsonb_build_object('operating_target', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  begin v := v || jsonb_build_object('coverage', public.fn_supplier_coverage(10) - 'basis');
  exception when others then v := v || jsonb_build_object('coverage', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- the funnel by step (30 days and the window) and by channel (ceo_supplier_funnel_daily)
  begin
    x := jsonb_build_object('window', public.fn_supplier_funnel_reading(v_days) - 'limits', 'days_30', public.fn_supplier_funnel_reading(30) - 'limits',
      'by_channel', coalesce((select jsonb_object_agg(channel, jsonb_build_object('sent', s, 'delivered', d, 'replied', r, 'started', st, 'submitted', sb, 'approved', ap))
                                from (select channel, sum(sent) s, sum(delivered) d, sum(replied) r, sum(started) st, sum(submitted) sb, sum(approved) ap
                                        from public.ceo_supplier_funnel_daily where day > current_date - 30 group by 1) c), '{}'::jsonb),
      'limits', 'opened is a floor (a tracked share only); started = owner verified or claimed; a WhatsApp reply or a call is not a stage');
    v := v || jsonb_build_object('funnel', x);
  exception when others then v := v || jsonb_build_object('funnel', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- registrations by first-touch source, per Dubai day (ruling 1709)
  begin
    x := jsonb_build_object(
      'totals', coalesce((select jsonb_object_agg(source, jsonb_build_object('started', n, 'submitted', sb, 'approved', ap))
                            from (select source, count(*) n, count(submitted_at) sb, count(*) filter (where approval_status = 'approved') ap
                                    from public.fn_ceo_registrations_by_source(now() - interval '30 days', now()) group by 1) t), '{}'::jsonb),
      'daily', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'source', source, 'started', n, 'submitted', sb) order by d, source)
                           from (select (started_at at time zone 'Asia/Dubai')::date d, source, count(*) n, count(submitted_at) sb
                                   from public.fn_ceo_registrations_by_source(v_from, now()) group by 1, 2) t), '[]'::jsonb),
      'basis', 'source = marketing_first_touch.utm_source (founder = his tracked link); email_invitation = an untagged registration the outbox had invited; untagged = neither');
    v := v || jsonb_build_object('registrations_by_source', x, 'founder_network', public.fn_ceo_founder_network_reading());
  exception when others then v := v || jsonb_build_object('registrations_by_source', jsonb_build_object('unavailable', left(sqlerrm, 200)),
                                                          'founder_network', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- placement by mailbox provider: the latest decided GlockApps test, and the providers the bar opens today
  begin
    x := (select jsonb_build_object('test_id', t.test_id, 'tested_at', t.created_at, 'verdict', t.verdict,
                   'by_class', (select jsonb_object_agg(coalesce(p.provider_class, p.provider), jsonb_build_object('seeds', p.seeds, 'inbox', p.inbox, 'tabs', p.tabs, 'spam', p.spam, 'missing', p.missing))
                                  from (select provider_class, min(provider) provider, sum(seeds) seeds, sum(inbox) inbox, sum(tabs) tabs, sum(spam) spam, sum(missing) missing
                                          from public.deliverability_test_provider where test_id = t.test_id group by provider_class) p))
            from public.deliverability_test t where t.verdict <> 'pending' order by t.created_at desc limit 1);
    v := v || jsonb_build_object('placement', coalesce(x, '{}'::jsonb) || jsonb_build_object(
      'open_providers_today', to_jsonb(coalesce(public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date), '{}'::text[]))));
  exception when others then v := v || jsonb_build_object('placement', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- supplier replies and how each was handled (no address: the lead id and the intent read)
  begin
    x := jsonb_build_object(
      'by_state', coalesce((select jsonb_object_agg(intent || ':' || state, n) from (select intent, state, count(*) n from public.supplier_reply_followup
                                                                                   where created_at >= now() - interval '30 days' group by 1, 2) s), '{}'::jsonb),
      'unanswered', coalesce((select jsonb_agg(jsonb_build_object('followup_id', f.id, 'lead_id', f.lead_id, 'intent', f.intent, 'state', f.state, 'at', f.created_at, 'outcome', left(coalesce(f.outcome, ''), 160)) order by f.id)
                                from public.supplier_reply_followup f where f.created_at >= now() - interval '30 days'
                                 and (f.state = 'dropped' or (f.state = 'due' and f.due_at < now()))), '[]'::jsonb));
    v := v || jsonb_build_object('replies', x);
  exception when others then v := v || jsonb_build_object('replies', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- demand signals
  begin
    v := v || jsonb_build_object('demand', jsonb_build_object(
      'waitlist', coalesce((select jsonb_object_agg(trade, n) from (select trade, count(*) n from public.customer_trade_waitlist where status = 'waiting' group by 1) w), '{}'::jsonb),
      'inquiries_90d', (select count(*) from public.inquiries i left join public.customers c on c.id = i.customer_id
                         where i.created_at > now() - interval '90 days' and coalesce(public.fn_seat_clock_customer_is_fixture(c), false) = public.fn_ceo_plan_world_is_demo()),
      'searches_90d', coalesce((select jsonb_object_agg(category, n) from (select category, count(*) n from public.demand_search where searched_at > now() - interval '90 days' group by 1 order by 2 desc limit 15) s), '{}'::jsonb)));
  exception when others then v := v || jsonb_build_object('demand', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- the never-invited pool by mailbox provider (Dubai and elsewhere)
  begin
    v := v || jsonb_build_object('pool', coalesce((select jsonb_object_agg(k, n) from (
        select case when coalesce(l.emirate, '') ilike 'dubai%' then 'dubai:' else 'other:' end || coalesce(public.fn_mail_provider_of_email(l.email), 'unknown') as k, count(*) n
          from public.leads l
         where public.fn_ceo_plan_lead_in_world(l.is_demo, l.company_name, l.email) and l.email is not null and l.invited_at is null
           and l.merged_into is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false) and l.approval_status is distinct from 'approved'
         group by 1) p), '{}'::jsonb));
  exception when others then v := v || jsonb_build_object('pool', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- spend: model spend by seat (30 days), the company limits, and the break-even reading (runway)
  begin
    v := v || jsonb_build_object('spend', jsonb_build_object(
      'model_aed_30d_by_seat', coalesce((select jsonb_object_agg(s, aed) from (select coalesce(seat, agent_key, '?') s, round(sum(cost_aed), 2) aed from public.ai_cost_log
                                                                              where occurred_at > now() - interval '30 days' group by 1) a), '{}'::jsonb),
      'planning_loop_aed_7d', public.fn_ceo_plan_spend_7d(),
      'limits', public.fn_company_limits(),
      'break_even', (select d.last_result from public.seat_duty d where d.duty = 'ceo.break_even')));
  exception when others then v := v || jsonb_build_object('spend', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- each seat: its board, and the CEO's open orders with their measure now
  begin
    v := v || jsonb_build_object('seats', jsonb_build_object(
      'board', public.fn_ceo_seat_board(7),
      'open_orders', coalesce((select jsonb_agg(jsonb_build_object('handoff_id', a.id, 'seat', a.agent, 'path', a.detail->>'path', 'measure', a.detail->>'measure',
                                 'target', a.detail->>'target', 'due_at', a.detail->>'due_at', 'now', a.detail->'reading_now') order by a.id)
                                 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'ceo.order' and a.status = 'pending'), '[]'::jsonb)));
  exception when others then v := v || jsonb_build_object('seats', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- the rulings in force that bear on growth (the channels' rulings and the CEO's own), and the latest open ones
  begin
    v := v || jsonb_build_object('rulings', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'status', f.status, 'said', left(f.instruction, 300)) order by f.id)
        from public.founder_instruction f
       where f.status in ('standing', 'open')
         and (f.id in (select unnest(rulings) from public.ceo_growth_channel) or f.id in (1620, 1663, 1696, 1701, 1705, 1706, 1709)
              or f.id in (select id from public.founder_instruction where status in ('standing', 'open') order by id desc limit 10))), '[]'::jsonb));
  exception when others then v := v || jsonb_build_object('rulings', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- the channel register: verdict, alternative, capability and the prior's mean with a 90% range (normal approximation)
  begin
    v := v || jsonb_build_object('channels', coalesce((select jsonb_agg(jsonb_build_object('channel', c.channel, 'verdict', c.verdict, 'seat', c.owner_seat,
        'conditions', c.conditions, 'refused_because', c.refused_because, 'alternative', c.alternative, 'rulings', to_jsonb(c.rulings), 'capability', c.capability,
        'unit', c.unit, 'prior_mean', round(c.alpha / (c.alpha + c.beta), 4),
        'prior_90', jsonb_build_array(round(greatest(0, c.alpha / (c.alpha + c.beta) - 1.645 * sqrt(c.alpha * c.beta / ((c.alpha + c.beta) ^ 2 * (c.alpha + c.beta + 1)))), 4),
                                      round(least(1, c.alpha / (c.alpha + c.beta) + 1.645 * sqrt(c.alpha * c.beta / ((c.alpha + c.beta) ^ 2 * (c.alpha + c.beta + 1)))), 4)),
        'trials', c.trials, 'successes', c.successes, 'basis', c.prior_basis) order by c.verdict desc, c.channel) from public.ceo_growth_channel c), '[]'::jsonb));
  exception when others then v := v || jsonb_build_object('channels', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- what each seat can do today: the channel state register and the switches
  begin
    v := v || jsonb_build_object('capabilities', jsonb_build_object(
      'channel_state', coalesce((select jsonb_object_agg(channel, jsonb_build_object('seat', owner_seat, 'state', state, 'switch', switch_key)) from public.ceo_supplier_channel), '{}'::jsonb),
      'switches', coalesce((select jsonb_object_agg(key, left(value, 20)) from public.app_secrets
                             where key in ('invite_enabled', 'invite_daily_cap', 'ceo_growth_act_golive', 'wa_supplier_invite_golive', 'invite_reachable_only')), '{}'::jsonb),
      'order_seats', coalesce((select jsonb_agg(distinct to_seat) from public.seat_handoff_kind where type = 'ceo.order' and from_seat = 'ceo'), '[]'::jsonb),
      'measures', public.fn_ceo_plan_measures()));
  exception when others then v := v || jsonb_build_object('capabilities', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  -- the last plan: its bets, predicted against what happened, and the calibration error
  begin
    v := v || jsonb_build_object('last_plan', coalesce((select jsonb_build_object('plan_id', p.id, 'kind', p.kind, 'period', p.period, 'status', p.status,
        'bets', (select jsonb_agg(jsonb_build_object('bet_id', b.id, 'channel', b.channel, 'seat', b.seat, 'what', left(b.what, 200), 'measure', b.measure, 'target', b.target,
                    'expected', jsonb_build_array(b.expected_low, b.expected_high), 'actual', b.actual, 'status', b.status, 'refusal', to_jsonb(b.refusal)) order by b.ord)
                   from public.ceo_plan_bet b where b.plan_id = p.id),
        'calibration', public.fn_ceo_plan_calibration(p.id))
      from public.ceo_plan_week p where p.kind in ('seed', 'weekly') and p.status in ('filed', 'measured') order by p.period desc, p.id desc limit 1), '{}'::jsonb));
  exception when others then v := v || jsonb_build_object('last_plan', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  begin
    v := v || jsonb_build_object('own_decisions', coalesce((select jsonb_agg(jsonb_build_object('source', d.source, 'subject', d.subject, 'choice', d.choice, 'reason', left(d.reason, 300), 'at', d.created_at) order by d.id desc)
        from public.ceo_own_decision d where d.created_at > now() - interval '14 days'), '[]'::jsonb));
  exception when others then v := v || jsonb_build_object('own_decisions', jsonb_build_object('unavailable', left(sqlerrm, 200))); end;
  return v;
end $fn$;

-- ── 6. MEASURES: what code can read, for every bet ───────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_plan_measures()
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select '{"registrations_by_source": "registrations started since the bet with that first-touch source (args: source)",
           "submitted_by_source": "registrations submitted since the bet with that first-touch source (args: source)",
           "replies_unanswered": "supplier replies since 1 Nov dropped or past their due time unanswered (direction at_most)",
           "invitations": "real leads of the trades the outbox invited since the bet (args: trades)",
           "held_registrations": "registrations submitted 2+ days ago and not decided (direction at_most)",
           "placement_inbox_pct": "inbox % of the provider class on the latest decided GlockApps test after the bet (args: provider_class)",
           "focus_verified": "verified suppliers in the operating target''s focus groups (fn_ceo_focus_coverage)",
           "reported": "the seat reported the order done (fn_seat_reports_done): for a build or a task code cannot count"}'::jsonb
$fn$;
revoke execute on function public.fn_ceo_plan_measures() from public, anon, authenticated;

create or replace function public.fn_ceo_plan_bet_reading(p_bet_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare b public.ceo_plan_bet; v_val numeric; v_src text; v_trades text[];
begin
  select * into b from public.ceo_plan_bet where id = p_bet_id;
  if not found then return jsonb_build_object('met', false, 'why', 'no bet ' || p_bet_id); end if;
  v_src := lower(coalesce(b.measure_args->>'source', ''));
  case b.measure
  when 'registrations_by_source' then
    select count(*) into v_val from public.fn_ceo_registrations_by_source(b.created_at, now()) where source = v_src;
  when 'submitted_by_source' then
    select count(*) into v_val from public.fn_ceo_registrations_by_source(b.created_at - interval '30 days', now()) where source = v_src and submitted_at >= b.created_at;
  when 'replies_unanswered' then
    select count(*) into v_val from public.supplier_reply_followup f join public.leads l on l.id = f.lead_id
     where f.created_at >= timestamptz '2026-11-01 00:00+04' and public.fn_ceo_plan_lead_in_world(l.is_demo, l.company_name, l.email)
       and (f.state = 'dropped' or (f.state = 'due' and f.due_at < now()));
  when 'invitations' then
    v_val := (public.fn_ceo_supply_order_reading(jsonb_build_object('measure', 'invitations', 'trades', b.measure_args->'trades', 'target', coalesce(b.target, 0)), b.created_at)->>'value')::numeric;
  when 'held_registrations' then
    select count(*) into v_val from public.fn_supplier_registrations_held(now());
  when 'placement_inbox_pct' then
    select round(100.0 * sum(p.inbox) / nullif(sum(p.seeds), 0), 1) into v_val
      from public.deliverability_test_provider p
     where p.provider_class = coalesce(b.measure_args->>'provider_class', 'microsoft')
       and p.test_id = (select t.test_id from public.deliverability_test t where t.verdict <> 'pending' and t.created_at >= b.created_at order by t.created_at desc limit 1);
  when 'focus_verified' then
    v_val := (public.fn_ceo_focus_coverage()->>'verified')::numeric;
  when 'reported' then
    select case when a.status = 'done' then 1 else 0 end into v_val from public.agent_actions a where a.id = b.handoff_id;
  else
    return jsonb_build_object('met', false, 'why', 'no such measure ' || b.measure);
  end case;
  return jsonb_build_object('measure', b.measure, 'value', v_val, 'target', b.target, 'direction', b.direction, 'at', now(),
    'met', v_val is not null and case when b.direction = 'at_most' then v_val <= b.target else v_val >= b.target end);
end $fn$;
revoke execute on function public.fn_ceo_plan_bet_reading(bigint) from public, anon, authenticated;

-- Share of a plan's scored bets whose actual fell outside the predicted range, and by how much (the ratio to the nearer edge).
create or replace function public.fn_ceo_plan_calibration(p_plan_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with s as (select b.* from public.ceo_plan_bet b where b.plan_id = p_plan_id and b.status in ('met', 'missed')
              and b.expected_low is not null and b.expected_high is not null and b.actual is not null)
  select jsonb_build_object('scored', (select count(*) from s),
    'outside_range', (select count(*) from s where actual < expected_low or actual > expected_high),
    'worst_ratio', (select max(case when actual < expected_low then expected_low / greatest(actual, 0.5)
                                    when actual > expected_high then actual / greatest(expected_high, 0.5) else 1 end) from s),
    'rule', 'a miss by more than 2x for two weekly plans running means the next plan widens its ranges')
$fn$;
revoke execute on function public.fn_ceo_plan_calibration(bigint) from public, anon, authenticated;

create or replace function public.fn_ceo_plan_spend_7d()
returns numeric language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(round(sum(cost_aed), 2), 0) from public.ai_cost_log
   where fn = 'ceo_agent' and occurred_at > now() - interval '7 days'
     and task_class in (select coalesce((select value->>'weekly_task_class' from public.decision_policy where key = 'ceo_planning_loop'), 'ceo_strategic_planning')
                        union all select coalesce((select value->>'daily_task_class' from public.decision_policy where key = 'ceo_planning_loop'), 'routine_employee_reasoning'))
$fn$;
revoke execute on function public.fn_ceo_plan_spend_7d() from public, anon, authenticated;
revoke execute on function public.fn_ceo_planning_pack(integer) from public, anon, authenticated;

-- ── 7. CODE CHECKS A BET BEFORE IT IS AN ORDER ─────────────────────────────────────────────────────────────────────────────
-- Empty array = it passes. Every reason names the rule it rests on.
create or replace function public.fn_ceo_plan_bet_check(p_bet jsonb)
returns text[] language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.ceo_growth_channel; v_out text[] := '{}'; v_seat text := nullif(btrim(coalesce(p_bet->>'seat', '')), '');
        v_measure text := p_bet->>'measure'; v_due timestamptz; v_target numeric; v_cost numeric; v_fits jsonb; v_lead bigint; v_g text[];
        v_open text[]; v_max_days int := coalesce((select (value->>'max_due_days')::int from public.decision_policy where key = 'ceo_planning_loop'), 42);
begin
  if jsonb_typeof(p_bet) <> 'object' then return array['a bet is an object']; end if;
  select * into c from public.ceo_growth_channel where channel = p_bet->>'channel';
  if not found then
    return array['no such channel in the register: ' || coalesce(p_bet->>'channel', '-') || ' (public.ceo_growth_channel names every channel the CEO may use)'];
  end if;
  if c.verdict = 'refused' then
    v_out := v_out || ('channel ' || c.channel || ' is refused: ' || c.refused_because || ' The alternative: ' || c.alternative);
  end if;
  -- the founder is told, never asked (ledger 1696); only his own network is his to work (ledger 1709)
  if coalesce((p_bet->>'asks_founder')::boolean, false) or (v_seat = 'founder' and c.channel <> 'founder_network') then
    v_out := v_out || 'the founder is not asked for anything (ledger 1696): the CEO decides; only the founder''s own network is his (ledger 1709)'::text;
  end if;
  -- the seat: one that takes a ceo.order, or nobody (the founder's network and the CEO's own measure)
  if v_seat is not null and v_seat <> 'founder'
     and not exists (select 1 from public.seat_handoff_kind k where k.type = 'ceo.order' and k.from_seat = 'ceo' and k.to_seat = v_seat) then
    v_out := v_out || ('no such seat to order: ' || v_seat || ' (seat_handoff_kind ceo.order)');
  end if;
  if v_seat is null and c.channel <> 'founder_network' then
    v_out := v_out || 'a bet names the seat that does it'::text;
  end if;
  -- a measure code can read, a target and a due date
  if v_measure is null or not (public.fn_ceo_plan_measures() ? v_measure) then
    v_out := v_out || ('no measure code can read: ' || coalesce(v_measure, '-') || ' (known: ' || array_to_string(array(select jsonb_object_keys(public.fn_ceo_plan_measures())), ', ') || ')');
  end if;
  if v_measure in ('registrations_by_source', 'submitted_by_source') and nullif(p_bet->'measure_args'->>'source', '') is null then
    v_out := v_out || 'a registration measure names its first-touch source'::text;
  end if;
  begin v_target := (p_bet->>'target')::numeric; exception when others then v_target := null; end;
  if v_target is null or v_target < 0 then v_out := v_out || 'a bet has a numeric target of 0 or more'::text; end if;
  if coalesce(p_bet->>'direction', 'at_least') not in ('at_least', 'at_most') then v_out := v_out || 'direction is at_least or at_most'::text; end if;
  begin v_due := (p_bet->>'due_at')::timestamptz; exception when others then v_due := null; end;
  if v_due is null or v_due < now() + interval '12 hours' or v_due > now() + make_interval(days => v_max_days) then
    v_out := v_out || ('a due date between 12 hours and ' || v_max_days || ' days from now')::text;
  end if;
  -- a capability no seat has today: only a build order (it_engineer, measure reported) may name it
  if c.capability <> 'ready' and not (v_seat = 'it_engineer' and v_measure = 'reported') then
    v_out := v_out || ('no seat can do ' || c.channel || ' today (' || c.capability || '): order the build from the it_engineer first')::text;
  end if;
  -- switched-off invitations: no seat can send a batch (the coverage file's rule)
  if v_measure = 'invitations' and coalesce((select value from public.app_secrets where key = 'invite_enabled'), '') <> 'true' then
    v_out := v_out || 'invitations are switched off (app_secrets.invite_enabled): no seat can send a batch, so the order could never be met'::text;
  end if;
  -- money: inside the company limits in force now
  begin v_cost := coalesce((p_bet->>'cost_aed')::numeric, 0); exception when others then v_cost := null; end;
  if v_cost is null or v_cost < 0 then v_out := v_out || 'cost_aed is a number of AED, 0 or more'::text;
  elsif v_cost > 0 then
    v_fits := public.fn_company_spend_fits(v_cost);
    if not coalesce((v_fits->>'fits')::boolean, false) then v_out := v_out || ('company limits: ' || coalesce(v_fits->>'why', 'does not fit')); end if;
  end if;
  -- every named recipient passes the existing gates for the channel (consent, suppression, opt-out, placement)
  if jsonb_typeof(p_bet->'lead_ids') = 'array' then
    if c.gate_channel is null then
      v_out := v_out || ('channel ' || c.channel || ' sends to nobody by name: a bet on it names no recipients')::text;
    else
      for v_lead in select x::bigint from jsonb_array_elements_text(p_bet->'lead_ids') x where x ~ '^\d+$' limit 200 loop
        v_g := public.fn_company_message_gates(c.gate_channel, null, v_lead);
        -- a reply to the person's own mail is not a cold invitation: the placement bar does not apply, every other gate does
        if not c.gate_placement then v_g := array(select g from unnest(v_g) g where g not like 'inbox placement:%'); end if;
        if cardinality(v_g) > 0 then v_out := v_out || ('lead ' || v_lead || ': ' || array_to_string(v_g, '; ')); end if;
      end loop;
    end if;
  end if;
  -- an e-mail batch names only providers the placement bar opens today
  if c.gate_placement and jsonb_typeof(p_bet->'providers') = 'array' then
    select array_agg(p) into v_open from jsonb_array_elements_text(p_bet->'providers') p
     where not (p = any (coalesce(public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date), '{}'::text[])));
    if cardinality(v_open) > 0 then
      v_out := v_out || ('inbox placement: ' || array_to_string(v_open, ', ') || ' not open on invite_placement_bar (founder instruction 1537)');
    end if;
  end if;
  -- one open order per seat and measure
  if v_seat is not null and v_measure is not null and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.status = 'pending'
        and a.agent = v_seat and a.detail->>'type' = 'ceo.order' and a.detail->>'measure' = v_measure and a.detail->>'path' = 'plan'
        and coalesce(a.detail->'measure_args', '{}'::jsonb) = coalesce(p_bet->'measure_args', '{}'::jsonb)) then
    v_out := v_out || ('an order to ' || v_seat || ' on ' || v_measure || ' is still open')::text;
  end if;
  return v_out;
end $fn$;
revoke execute on function public.fn_ceo_plan_bet_check(jsonb) from public, anon, authenticated;

-- ── 8. THE CEO'S OWN ACTIONS FROM A PLAN (fixed kinds, each with its reason) ─────────────────────────────────────────────
create or replace function public.fn_ceo_plan_self_action(p_plan_id bigint, p_act jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_reason text := btrim(coalesce(p_act->>'reason', '')); v_kind text := p_act->>'kind'; v_focus text[]; n_ret int := 0; n_add int := 0; n_rm int := 0;
        t text; v_key text := 'plan:' || p_plan_id || ':' || coalesce(p_act->>'kind', '-');
begin
  if length(v_reason) < 20 then return jsonb_build_object('ok', false, 'reason', 'a CEO action says why, in a sentence (20 characters or more)'); end if;
  if exists (select 1 from public.ceo_own_decision where dedupe_key = v_key) then return jsonb_build_object('ok', true, 'already', v_key); end if;
  if v_kind = 'set_trade_priority' then
    for t in select jsonb_array_elements_text(coalesce(p_act->'remove', '[]'::jsonb)) loop
      update public.ceo_invite_trade_priority set cleared_at = now(), cleared_why = 'the CEO''s plan #' || p_plan_id || ': ' || left(v_reason, 300)
       where trade = t and cleared_at is null;
      get diagnostics n_ret = row_count; n_rm := n_rm + n_ret;
    end loop;
    for t in select jsonb_array_elements_text(coalesce(p_act->'add', '[]'::jsonb)) loop
      if exists (select 1 from public.taxonomy_trade where code = t and active) and not exists (select 1 from public.ceo_invite_trade_priority where trade = t and cleared_at is null) then
        insert into public.ceo_invite_trade_priority (trade, reason) values (t, 'the CEO''s plan #' || p_plan_id || ': ' || left(v_reason, 300));
        n_add := n_add + 1;
      end if;
    end loop;
    insert into public.ceo_own_decision (source, subject, choice, reason, reading, dedupe_key)
    values ('plan', 'invitation trade priorities', 'set_trade_priority', v_reason, jsonb_build_object('added', n_add, 'removed', n_rm, 'act', p_act), v_key);
    return jsonb_build_object('ok', true, 'added', n_add, 'removed', n_rm);
  elsif v_kind = 'narrow_coverage_to_operating_target' then
    v_focus := array(select jsonb_array_elements_text(x->'trades') from public.ceo_operating_target o, jsonb_array_elements(o.groups) x where o.status = 'active');
    if cardinality(v_focus) = 0 then return jsonb_build_object('ok', false, 'reason', 'no active operating target'); end if;
    -- a recruitment note outside the focus trades is retired; real demand (inquiries, the waitlist) is kept wherever it is
    update public.supplier_coverage_target set status = 'retired', retired_at = now(),
           decision_reason = coalesce(decision_reason || ' | ', '') || 'retired by the CEO''s plan #' || p_plan_id || ': ' || left(v_reason, 300)
     where status <> 'retired' and demand_basis->>'source' = 'supply_gap' and not (trade = any(v_focus));
    get diagnostics n_ret = row_count;
    insert into public.ceo_own_decision (source, subject, choice, reason, reading, dedupe_key)
    values ('plan', 'coverage targets', 'narrow_coverage_to_operating_target', v_reason, jsonb_build_object('retired', n_ret, 'focus', to_jsonb(v_focus)), v_key);
    return jsonb_build_object('ok', true, 'retired', n_ret);
  end if;
  return jsonb_build_object('ok', false, 'reason', 'no such CEO action: ' || coalesce(v_kind, '-') || ' (set_trade_priority, narrow_coverage_to_operating_target)');
end $fn$;
revoke execute on function public.fn_ceo_plan_self_action(bigint, jsonb) from public, anon, authenticated;

-- ── 9. FILE A PLAN: every bet checked, the passed ones ordered, the refused ones back to the model once ───────────────────
create or replace function public.fn_ceo_plan_file(p_plan_id bigint, p_output jsonb, p_model text default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.ceo_plan_week; b jsonb; v_ord int := 0; v_ref text[]; v_id bigint; v_h bigint; v_seat text; v_due timestamptz;
        n_filed int := 0; n_ref int := 0; v_refusals jsonb := '[]'::jsonb; v_acts jsonb := '[]'::jsonb; a jsonb; v_bets jsonb;
        v_max int;
begin
  select * into p from public.ceo_plan_week where id = p_plan_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no plan ' || p_plan_id); end if;
  if p.status in ('filed', 'measured') then return jsonb_build_object('ok', true, 'already', p.status); end if;
  v_bets := case when jsonb_typeof(p_output->'decision'->'bets') = 'array' then p_output->'decision'->'bets'
                 when jsonb_typeof(p_output->'bets') = 'array' then p_output->'bets' end;
  if p_error is not null or jsonb_typeof(p_output) <> 'object' or v_bets is null then
    -- asked again once (fn_ceo_plan_due re-offers an 'asked' row after two hours); after the second failure it is held
    update public.ceo_plan_week set status = case when p.attempts < 2 and p.kind <> 'seed' then 'asked' else 'held' end,
           error = left(coalesce(p_error, 'the answer carries no decision.bets array'), 500),
           output = coalesce(p_output, output), model = coalesce(p_model, model) where id = p_plan_id;
    return jsonb_build_object('ok', false, 'held', true, 'reason', coalesce(p_error, 'the answer carries no decision.bets array'));
  end if;
  v_max := coalesce((select (value->>(case when p.kind = 'daily' then 'max_bets_daily' else 'max_bets_weekly' end))::int from public.decision_policy where key = 'ceo_planning_loop'), 8);
  for b in select * from jsonb_array_elements(v_bets) loop
    v_ord := v_ord + 1;
    v_ref := case when v_ord > v_max then array['more bets than a ' || p.kind || ' plan may carry (' || v_max || ')'] else public.fn_ceo_plan_bet_check(b) end;
    v_seat := nullif(btrim(coalesce(b->>'seat', '')), '');
    begin v_due := (b->>'due_at')::timestamptz; exception when others then v_due := null; end;
    insert into public.ceo_plan_bet (plan_id, revision, ord, channel, seat, what, measure, measure_args, direction, target, due_at, expected_low, expected_high,
                                     cost_aed, legal, kill_criterion, status, refusal)
    values (p_plan_id, p.revision, v_ord, coalesce(b->>'channel', '-'), v_seat, left(coalesce(b->>'what', '-'), 1000), coalesce(b->>'measure', '-'),
            case when jsonb_typeof(b->'measure_args') = 'object' then b->'measure_args' else '{}'::jsonb end,
            case when b->>'direction' = 'at_most' then 'at_most' else 'at_least' end,
            case when b->>'target' ~ '^-?\d+(\.\d+)?$' then (b->>'target')::numeric end, v_due,
            case when b->>'expected_low' ~ '^\d+(\.\d+)?$' then (b->>'expected_low')::numeric end,
            case when b->>'expected_high' ~ '^\d+(\.\d+)?$' then (b->>'expected_high')::numeric end,
            case when b->>'cost_aed' ~ '^\d+(\.\d+)?$' then (b->>'cost_aed')::numeric else 0 end,
            left(b->>'legal', 1000), left(b->>'kill_criterion', 500),
            case when cardinality(v_ref) = 0 then 'filed' else 'refused' end, v_ref)
    on conflict (plan_id, revision, ord) do nothing
    returning id into v_id;
    if v_id is null then continue; end if;
    if cardinality(v_ref) > 0 then
      n_ref := n_ref + 1;
      v_refusals := v_refusals || jsonb_build_object('ord', v_ord, 'channel', b->>'channel', 'seat', v_seat, 'what', left(coalesce(b->>'what', ''), 200), 'refused_because', to_jsonb(v_ref));
      continue;
    end if;
    n_filed := n_filed + 1;
    if v_seat is not null and v_seat <> 'founder' then
      v_h := public.fn_seat_handoff('ceo', v_seat, 'ceo.order', 'ceo_plan_bet', 'plan_bet:' || v_id,
        jsonb_build_object('path', 'plan', 'plan_id', p_plan_id, 'bet_id', v_id, 'channel', b->>'channel', 'measure', b->>'measure',
          'measure_args', coalesce(b->'measure_args', '{}'::jsonb), 'direction', coalesce(b->>'direction', 'at_least'), 'target', b->'target', 'due_at', v_due,
          'decision', 'the CEO''s ' || p.kind || ' plan of ' || to_char(p.period, 'DD Mon'),
          'what', left(coalesce(b->>'what', ''), 600), 'how', left(coalesce(b->>'how', b->>'legal', ''), 600),
          'reasons', left(coalesce(b->>'why', ''), 600), 'kill_criterion', left(coalesce(b->>'kill_criterion', ''), 300),
          'lead_ids', coalesce(b->'lead_ids', '[]'::jsonb)));
      update public.ceo_plan_bet set handoff_id = v_h where id = v_id;
    end if;
  end loop;
  -- the CEO's own actions (fixed kinds)
  for a in select * from jsonb_array_elements(case when jsonb_typeof(p_output->'decision'->'ceo_actions') = 'array' then p_output->'decision'->'ceo_actions'
                                                   when jsonb_typeof(p_output->'ceo_actions') = 'array' then p_output->'ceo_actions' else '[]'::jsonb end) loop
    v_acts := v_acts || public.fn_ceo_plan_self_action(p_plan_id, a);
  end loop;
  -- one revision: refused bets go back to the model once with the reasons; the second time they are dropped and recorded
  if n_ref > 0 and p.revision = 0 and p.kind <> 'seed' then
    update public.ceo_plan_week set status = 'revise', revision = 1, refusals = v_refusals, output = p_output, model = coalesce(p_model, model) where id = p_plan_id;
    return jsonb_build_object('ok', true, 'revise', true, 'filed', n_filed, 'refused', n_ref, 'refusals', v_refusals, 'ceo_actions', v_acts);
  end if;
  update public.ceo_plan_week set status = 'filed', filed_at = now(), refusals = refusals || v_refusals,
         output = case when p.revision = 1 then coalesce(output, '{}'::jsonb) || jsonb_build_object('revision', p_output) else p_output end,
         model = coalesce(p_model, model) where id = p_plan_id;
  return jsonb_build_object('ok', true, 'revise', false, 'filed', n_filed, 'refused', n_ref, 'refusals', v_refusals, 'ceo_actions', v_acts);
end $fn$;
revoke execute on function public.fn_ceo_plan_file(bigint, jsonb, text, text) from public, anon, authenticated;

-- ── 10. MEASURE THE BETS AND LEARN ─────────────────────────────────────────────────────────────────────────────────────────
-- Daily: each filed bet is read; met -> met (its order closed by measure after 20 hours unreported, as the coverage file does);
-- past due and not met -> missed. The actual is kept for the calibration.
create or replace function public.fn_ceo_plan_measure(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare b public.ceo_plan_bet; v_r jsonb; n_met int := 0; n_missed int := 0; n_closed int := 0; v_met boolean;
begin
  for b in select * from public.ceo_plan_bet where status = 'filed' order by id loop
    v_r := public.fn_ceo_plan_bet_reading(b.id);
    v_met := coalesce((v_r->>'met')::boolean, false);
    if b.handoff_id is not null then
      update public.agent_actions set detail = detail || jsonb_build_object('reading_now', v_r) where id = b.handoff_id and status = 'pending';
    end if;
    if v_met then
      update public.ceo_plan_bet set status = 'met', actual = (v_r->>'value')::numeric, met_at = coalesce(met_at, p_at), scored_at = p_at where id = b.id;
      n_met := n_met + 1;
    elsif b.due_at is not null and b.due_at < p_at then
      update public.ceo_plan_bet set status = 'missed', actual = (v_r->>'value')::numeric, scored_at = p_at where id = b.id;
      n_missed := n_missed + 1;
    end if;
  end loop;
  -- a met bet whose order the seat has not reported for 20 hours is closed by its measure
  for b in select x.* from public.ceo_plan_bet x join public.agent_actions a on a.id = x.handoff_id
            where x.status = 'met' and a.status = 'pending' and x.met_at < p_at - interval '20 hours' loop
    perform public.fn_seat_handoff_complete(b.handoff_id, jsonb_build_object('outcome', 'met', 'reply',
      'Met, measured by the CEO: ' || coalesce(b.actual::text, '?') || ' against ' || coalesce(b.target::text, '?') || ' (' || b.measure || '); the seat did not report it',
      'not_cited', jsonb_build_object('reason', 'closed by its measure', 'by', 'ceo')));
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('met', n_met, 'missed', n_missed, 'closed_by_measure', n_closed);
end $fn$;
revoke execute on function public.fn_ceo_plan_measure(timestamptz) from public, anon, authenticated;

-- Per channel, what the record shows in a window: trials of the channel's unit and successes. A window is read once (the
-- watermark measured_until), so a day is never counted twice.
create or replace function public.fn_ceo_channel_outcomes(p_since timestamptz, p_until timestamptz)
returns table (channel text, trials integer, successes integer)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- Each unit is read with a LAG, so a trial has had time to succeed before it is counted: a registration started 7 days
  -- before the window, an invitation or an answered reply 14 days before; success = submitted by the window's end.
  with r as (select * from public.fn_ceo_registrations_by_source(p_since - interval '7 days', p_until - interval '7 days'))
  -- founder_network: a registration started with his tag -> submitted
  select 'founder_network'::text, (select count(*) from r where source = 'founder')::int,
         (select count(*) from r where source = 'founder' and submitted_at is not null and submitted_at < p_until)::int
  union all
  -- email_invitation_google: an invitation the outbox delivered -> that lead submitted afterwards
  select 'email_invitation_google', count(distinct n.lead_id)::int,
         count(distinct n.lead_id) filter (where l.registration_submitted_at is not null and l.registration_submitted_at >= n.sent_at and l.registration_submitted_at < p_until)::int
    from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.status = 'sent' and n.sent_at >= p_since - interval '14 days' and n.sent_at < p_until - interval '14 days'
     and coalesce(n.provider_status, '') <> 'undelivered' and public.fn_ceo_plan_lead_in_world(l.is_demo, l.company_name, l.email)
  union all
  -- reply_within_1h: a supplier reply answered (state sent) -> that lead submitted afterwards
  select 'reply_within_1h', count(*) filter (where f.state = 'sent')::int,
         count(*) filter (where f.state = 'sent' and l.registration_submitted_at is not null and l.registration_submitted_at >= f.created_at and l.registration_submitted_at < p_until)::int
    from public.supplier_reply_followup f join public.leads l on l.id = f.lead_id
   where f.created_at >= p_since - interval '14 days' and f.created_at < p_until - interval '14 days' and public.fn_ceo_plan_lead_in_world(l.is_demo, l.company_name, l.email)
$fn$;
revoke execute on function public.fn_ceo_channel_outcomes(timestamptz, timestamptz) from public, anon, authenticated;

create or replace function public.fn_ceo_priors_update(p_until timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare o record; v_since timestamptz; v jsonb := '{}'::jsonb;
begin
  for o in select c.channel, coalesce(c.measured_until, now() - interval '30 days') as since from public.ceo_growth_channel c
            where c.verdict <> 'refused' and coalesce(c.measured_until, '-infinity') < p_until - interval '1 hour' loop
    v_since := o.since;
    update public.ceo_growth_channel c set
           alpha = c.alpha + x.successes, beta = c.beta + greatest(x.trials - x.successes, 0),
           trials = c.trials + x.trials, successes = c.successes + x.successes,
           prior_basis = case when x.trials > 0 then left(c.prior_basis || ' | +' || x.successes || '/' || x.trials || ' to ' || to_char(p_until at time zone 'Asia/Dubai', 'DD Mon'), 900) else c.prior_basis end,
           measured_until = p_until, updated_at = now()
      from public.fn_ceo_channel_outcomes(v_since, p_until) x
     where x.channel = c.channel and c.channel = o.channel;
    if not found then update public.ceo_growth_channel set measured_until = p_until where channel = o.channel; end if;
    v := v || jsonb_build_object(o.channel, (select jsonb_build_object('alpha', alpha, 'beta', beta) from public.ceo_growth_channel where channel = o.channel));
  end loop;
  return v;
end $fn$;
revoke execute on function public.fn_ceo_priors_update(timestamptz) from public, anon, authenticated;

-- ── 11. THE CONTRACT THE MODEL ANSWERS ─────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_plan_contract(p_kind text)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'system', 'You are the chief executive of QuotesDone, a UAE B2B procurement marketplace before launch. The founder gave you full authority '
      || '(ledger 1696) and you do not rely on him; profitability is your main concern: first enough verified suppliers, then a customer '
      || 'campaign (1701). Bring solutions, not issues (1705/1706): for every obstacle say what you will do, whether it is safe, and if not, '
      || 'the alternative. No hire (1709): the founder personally messages and calls his own network with his tracked link, and you track them. '
      || case when p_kind = 'daily' then 'This is the DAILY light review: code found the anomalies listed; propose at most two bets that fix them, or none. '
              else 'This is the WEEKLY plan: first score last week''s bets against what happened (last_plan, calibration), then decide this week. ' end
      || 'Read the pack: the funnel, registrations by first-touch source, placement by provider, replies, coverage and the operating target, '
      || 'demand, the pool, spend against the company limits and runway, each seat''s board and open orders, the rulings, the channel register '
      || '(verdicts, alternatives, capabilities, priors) and the measures code can read. Use only channels in the register; a refused channel will be '
      || 'refused by code with its alternative. Every bet names its seat (one of capabilities.order_seats; seat "founder" only for founder_network), '
      || 'a measure from capabilities.measures with measure_args, a numeric target, direction, a due_at (ISO, 12 hours to 6 weeks ahead), the '
      || 'expected range from the priors (say the assumption), the cost in AED (0 if none), the legal and platform analysis naming the rule (PDPL, TDRA, '
      || 'Meta, LinkedIn, Google or Microsoft sender rules, a founder ruling), and a kill criterion. Never ask the founder anything. A capability no '
      || 'seat has becomes a build order to it_engineer with measure "reported". Code checks every bet against the message gates, the company limits, '
      || 'the rulings and the register; a refused bet comes back to you once with the reasons. If last week''s predictions missed by more than 2x, widen '
      || 'your ranges. Answer ONLY the JSON object of output_schema.',
    'output_schema', jsonb_build_object(
      'situation', 'three lines',
      'binding_constraint', jsonb_build_object('stage', 'the funnel stage that binds', 'evidence', 'numbers from the pack'),
      'last_week', '[{bet_id, actual, verdict keep|scale|kill, lesson}]',
      'options', '[{channel, message, expected_per_week [low, high], assumptions, cost_aed, legal, brand_risk, reversible, seat, seat_can_do_it_today}] 3 to 6',
      'decision', jsonb_build_object(
        'bets', '[{channel, seat, what, how, why, measure, measure_args, target, direction, due_at, expected_low, expected_high, cost_aed, legal, kill_criterion, lead_ids?, providers?}]',
        'ceo_actions', '[{kind: set_trade_priority {add[], remove[]} | narrow_coverage_to_operating_target, reason}]',
        'dropped', '[{option, why}]')),
    'task_class', case when p_kind = 'daily' then coalesce((select value->>'daily_task_class' from public.decision_policy where key = 'ceo_planning_loop'), 'routine_employee_reasoning')
                       else coalesce((select value->>'weekly_task_class' from public.decision_policy where key = 'ceo_planning_loop'), 'ceo_strategic_planning') end)
$fn$;
revoke execute on function public.fn_ceo_plan_contract(text) from public, anon, authenticated;

-- What ceo_agent sends the model for a plan (and, on a revision, the refusals to answer).
create or replace function public.fn_ceo_plan_request(p_plan_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.ceo_plan_week; c jsonb;
begin
  select * into p from public.ceo_plan_week where id = p_plan_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no plan ' || p_plan_id); end if;
  if p.status not in ('asked', 'revise') then return jsonb_build_object('ok', false, 'reason', 'plan ' || p_plan_id || ' is ' || p.status); end if;
  c := public.fn_ceo_plan_contract(p.kind);
  update public.ceo_plan_week set asked_at = now(), attempts = attempts + case when p.status = 'asked' then 1 else 0 end where id = p_plan_id;
  return jsonb_build_object('ok', true, 'plan_id', p.id, 'kind', p.kind, 'revision', p.revision, 'task_class', c->>'task_class',
    'system', c->>'system', 'output_schema', c->'output_schema',
    'input', jsonb_build_object('pack', p.pack, 'anomalies', p.anomalies) || case when p.status = 'revise'
      then jsonb_build_object('your_previous_answer', p.output, 'refused_by_code', p.refusals,
             'instruction', 'Code refused these bets for the reasons given. Answer again with replacement bets for them only (the passed ones are already ordered), or drop them in decision.dropped.')
      else '{}'::jsonb end);
end $fn$;
revoke execute on function public.fn_ceo_plan_request(bigint) from public, anon, authenticated;

-- ── 12. THE LOOP'S CLOCK (resilience_ping's CEO tick, every 15 minutes) ─────────────────────────────────────────────────────
create or replace function public.fn_ceo_plan_anomalies(p_at timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := '[]'::jsonb; n int; s int;
begin
  select count(*) into n from public.supplier_reply_followup f join public.leads l on l.id = f.lead_id
   where f.created_at > p_at - interval '48 hours' and public.fn_ceo_plan_lead_in_world(l.is_demo, l.company_name, l.email)
     and (f.state = 'dropped' or (f.state = 'due' and f.due_at < p_at));
  if n > 0 then v := v || jsonb_build_object('kind', 'reply_unanswered', 'count', n, 'why', n || ' supplier replies of the last 48 hours dropped or overdue'); end if;
  select count(*) into n from public.ceo_plan_bet b join public.agent_actions a on a.id = b.handoff_id
   where b.status = 'missed' and b.scored_at > p_at - interval '24 hours';
  if n > 0 then v := v || jsonb_build_object('kind', 'order_missed', 'count', n, 'why', n || ' plan orders missed their due date in the last day'); end if;
  select count(*) into n from jsonb_array_elements(coalesce(public.fn_ceo_founder_network_reading()->'stuck', '[]'::jsonb)) x where (x->>'days')::numeric >= 2;
  if n > 0 then v := v || jsonb_build_object('kind', 'founder_people_stuck', 'count', n, 'why', n || ' of the founder''s people stuck two days or more'); end if;
  select count(*), count(*) filter (where n2.provider_status = 'undelivered') into n, s from public.notifications n2
   where n2.type = 'supplier_invite' and n2.status = 'sent' and n2.sent_at > p_at - interval '7 days';
  if n >= 20 and s * 100.0 / n > 3 then v := v || jsonb_build_object('kind', 'bounce', 'count', s, 'why', s || ' of ' || n || ' invitations undelivered in 7 days (over 3%)'); end if;
  return v;
end $fn$;
revoke execute on function public.fn_ceo_plan_anomalies(timestamptz) from public, anon, authenticated;

-- p_open_model false (the hourly duty): measure, learn and file the seed only; opening a model plan is the heartbeat's, which
-- calls ceo_agent at once, so a plan is never opened by a caller that cannot answer it.
create or replace function public.fn_ceo_plan_due(p_at timestamptz default now(), p_open_model boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local timestamp := p_at at time zone 'Asia/Dubai'; v_today date := (p_at at time zone 'Asia/Dubai')::date;
        v_monday date := date_trunc('week', (p_at at time zone 'Asia/Dubai'))::date; pol jsonb := coalesce((select value from public.decision_policy where key = 'ceo_planning_loop'), '{}'::jsonb);
        v_measure jsonb; v_priors jsonb; s public.ceo_plan_week; v_id bigint; v_anom jsonb; v_spent numeric; v_cap numeric := coalesce((pol->>'week_aed_cap')::numeric, 8);
        v_filed jsonb;
begin
  -- 1. once a Dubai day: measure the open bets and learn the priors (the daily row's existence is the guard)
  if not exists (select 1 from public.ceo_plan_week where kind = 'daily' and period = v_today) and v_local::time >= time '06:00' then
    v_measure := public.fn_ceo_plan_measure(p_at);
    v_priors := public.fn_ceo_priors_update(p_at);
  end if;
  -- 2. the seeded first plan is filed by the first run, through the same checks as any plan
  select * into s from public.ceo_plan_week where kind = 'seed' and status = 'asked' order by id limit 1;
  if found then
    v_filed := public.fn_ceo_plan_file(s.id, s.output, 'seed: the CEO seat audit of 15 Nov 2026, revised for ruling 1709', null);
    return jsonb_build_object('call_model', false, 'seed_filed', v_filed, 'measured', v_measure, 'priors', v_priors);
  end if;
  if not coalesce(p_open_model, true) then return jsonb_build_object('call_model', false, 'measured', v_measure, 'priors', v_priors); end if;
  -- 3. a plan the model has not answered for two hours is offered again (twice at most), a revision at once
  select * into s from public.ceo_plan_week where status = 'revise' or (status = 'asked' and kind <> 'seed' and attempts < 2 and coalesce(asked_at, created_at) < p_at - interval '2 hours')
   order by id desc limit 1;
  if found then return jsonb_build_object('call_model', true, 'plan_id', s.id, 'kind', s.kind, 'retry', true); end if;
  v_spent := public.fn_ceo_plan_spend_7d();
  -- 4. the weekly plan: Monday from 07:00 Dubai
  if extract(isodow from v_local) = 1 and v_local::time >= coalesce((pol->>'weekly_local')::time, time '07:00') and coalesce((pol->>'weekly_on')::boolean, true)
     and not exists (select 1 from public.ceo_plan_week where kind = 'weekly' and period = v_monday) then
    if v_spent >= v_cap then
      insert into public.ceo_plan_week (kind, period, status, task_class, error) values ('weekly', v_monday, 'held', (public.fn_ceo_plan_contract('weekly'))->>'task_class',
        format('the loop''s model spend in 7 days (AED %s) reached its cap (AED %s, decision_policy ceo_planning_loop)', v_spent, v_cap)) on conflict (kind, period) do nothing;
      return jsonb_build_object('call_model', false, 'held', 'week_aed_cap', 'measured', v_measure);
    end if;
    insert into public.ceo_plan_week (kind, period, status, task_class, pack, asked_at)
    values ('weekly', v_monday, 'asked', (public.fn_ceo_plan_contract('weekly'))->>'task_class', public.fn_ceo_planning_pack(7), p_at)
    on conflict (kind, period) do nothing returning id into v_id;
    return jsonb_build_object('call_model', v_id is not null, 'plan_id', v_id, 'kind', 'weekly', 'measured', v_measure, 'priors', v_priors);
  end if;
  -- 5. the daily light review: code measures; the model only on an anomaly
  if v_local::time >= coalesce((pol->>'daily_local')::time, time '07:30') and not exists (select 1 from public.ceo_plan_week where kind = 'daily' and period = v_today) then
    v_anom := public.fn_ceo_plan_anomalies(p_at);
    if jsonb_array_length(v_anom) = 0 or extract(isodow from v_local) = 1 or not coalesce((pol->>'daily_on')::boolean, true) or v_spent >= v_cap then
      insert into public.ceo_plan_week (kind, period, status, anomalies, pack, error)
      values ('daily', v_today, 'measured', v_anom, jsonb_build_object('measured', v_measure, 'priors', v_priors),
              case when jsonb_array_length(v_anom) = 0 then null when extract(isodow from v_local) = 1 then 'Monday: the weekly plan reads them'
                   when v_spent >= v_cap then 'week_aed_cap reached' else 'daily_on is off' end)
      on conflict (kind, period) do nothing;
      return jsonb_build_object('call_model', false, 'daily', 'measured', 'anomalies', v_anom, 'measured', v_measure);
    end if;
    insert into public.ceo_plan_week (kind, period, status, task_class, anomalies, pack, asked_at)
    values ('daily', v_today, 'asked', (public.fn_ceo_plan_contract('daily'))->>'task_class', v_anom, public.fn_ceo_planning_pack(1), p_at)
    on conflict (kind, period) do nothing returning id into v_id;
    return jsonb_build_object('call_model', v_id is not null, 'plan_id', v_id, 'kind', 'daily', 'anomalies', v_anom, 'measured', v_measure);
  end if;
  return jsonb_build_object('call_model', false, 'measured', v_measure, 'priors', v_priors);
end $fn$;
revoke execute on function public.fn_ceo_plan_due(timestamptz, boolean) from public, anon, authenticated;

-- ── 13. THE FOUNDER'S DAILY SUMMARY: the week's plan and his own people (information, ledger 1696 and 1709) ────────────────
create or replace function public.fn_ceo_plan_summary_text(p_since timestamptz default now() - interval '24 hours')
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare f jsonb := public.fn_ceo_founder_network_reading(); o jsonb := public.fn_ceo_focus_coverage(); v text := '';
begin
  v := E'\nYOUR PEOPLE (your link, utm_source founder): ' || coalesce(f->>'started', '0') || ' started, ' || coalesce(f->>'submitted', '0') || ' submitted, '
       || coalesce(f->>'approved', '0') || ' approved since ' || to_char((f->>'since')::timestamptz at time zone 'Asia/Dubai', 'DD Mon') || '.'
       || coalesce((select E'\nStuck, so you can call them: ' || string_agg((x->>'company') || ' - ' || (x->>'step') || ' (' || (x->>'days') || ' days)', '; ')
                      from jsonb_array_elements(f->'stuck') x), '');
  if coalesce((o->>'active')::boolean, false) then
    v := v || E'\nOPERATING TARGET: ' || coalesce(o->>'verified', '0') || ' of ' || coalesce(o->>'target', '?') || ' verified in Dubai focus trades, '
         || coalesce(o->>'days_left', '?') || ' days to ' || to_char((o->>'due_on')::date, 'DD Mon') || ' ('
         || (select string_agg((g->>'label') || ' ' || (g->>'verified') || '/' || (g->>'target'), '; ') from jsonb_array_elements(o->'groups') g) || ').';
  end if;
  v := v || coalesce((select E'\nTHE CEO''S PLAN (' || p.kind || ', ' || to_char(p.period, 'DD Mon') || ', ' || p.status || '): '
                      || (select string_agg(coalesce(b.seat, 'founder') || ' ' || b.channel || ' ' || b.measure || ' ' || coalesce(b.target::text, '?')
                                            || ' by ' || coalesce(to_char(b.due_at at time zone 'Asia/Dubai', 'DD Mon'), '?') || ' [' || b.status
                                            || coalesce(', now ' || b.actual, '') || case when b.status = 'refused' then ': ' || left(array_to_string(b.refusal, '; '), 200) else '' end || ']', '; ' order by b.revision, b.ord)
                            from public.ceo_plan_bet b where b.plan_id = p.id)
                     from public.ceo_plan_week p where p.kind in ('seed', 'weekly') and p.status in ('filed', 'measured', 'revise', 'held') order by p.period desc, p.id desc limit 1), '')
       || coalesce((select E'\nTODAY''S REVIEW: ' || string_agg(x->>'why', '; ') from public.ceo_plan_week p, jsonb_array_elements(p.anomalies) x
                     where p.kind = 'daily' and p.period = (now() at time zone 'Asia/Dubai')::date), '')
       || coalesce((select E'\nTHE CEO DECIDED HIMSELF: ' || string_agg(d.subject || ' - ' || d.choice || ': ' || left(d.reason, 200), '; ' order by d.id)
                     from public.ceo_own_decision d where d.created_at >= p_since), '');
  return v;
end $fn$;
revoke execute on function public.fn_ceo_plan_summary_text(timestamptz) from public, anon, authenticated;

-- The coverage file's sender, with the plan and his people appended. Same key, kind and once-a-day rule.
create or replace function public.fn_ceo_daily_summary_to_the_founder(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_key text := 'ceo_daily_summary:' || to_char(p_at at time zone 'Asia/Dubai', 'YYYY-MM-DD'); v_r jsonb;
begin
  if (p_at at time zone 'Asia/Dubai')::time < time '07:00' then return jsonb_build_object('told', false, 'reason', 'before 07:00 Dubai'); end if;
  if exists (select 1 from public.founder_alerts f where f.dedupe_key = v_key) then return jsonb_build_object('told', false, 'reason', 'already told today'); end if;
  v_r := public.fn_notify_founder('The CEO''s day: supplier coverage and decisions',
                                  public.fn_ceo_daily_summary_text(p_at - interval '24 hours') || public.fn_ceo_plan_summary_text(p_at - interval '24 hours'),
                                  'info', 'ceo_daily_summary', v_key, 'ceo');
  return jsonb_build_object('told', true, 'result', v_r);
end $fn$;
revoke execute on function public.fn_ceo_daily_summary_to_the_founder(timestamptz) from public, anon, authenticated;

-- ── 14. NO FOUNDER ASK FROM THE FORECAST (ledger 1696) ─────────────────────────────────────────────────────────────────────
-- The forecast's body as in the_ceo_target_verdict_and_forecast_read_the_year_plan.sql; only the third option changes.
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
        || 'customers from January 2027) is not on track. As the chief executive with full authority (founder ledger 1696), decide the company''s '
        || 'response yourself, and say what must change and who owns it. Nothing goes to the founder: he reads your decision in the daily summary.',
      ('[{"id":"hold_course","meaning":"the plan in force is right; the gap is expected at this stage and closes as it runs"},'
      || '{"id":"change_plan","meaning":"the plan must change: a different binding constraint, channel or sequence (the weekly plan takes it)"},'
      || '{"id":"act_within_authority","meaning":"the gap needs money, a limit, a target or a rule changed: the CEO changes it himself within the company limits and says so"}]')::jsonb,
      jsonb_build_object('forecast', v - 'chain', 'milestones', v_ms, 'year_plan', public.fn_ceo_year_plan_status(now())),
      jsonb_build_object('kind', 'target_forecast', 'period', v_week), 'ceo_forecast:' || v_week);
    update public.reasoning_held_question set request = request || '{"stakes":"normal"}'::jsonb where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'target_forecast' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'verdicts', v_all, 'milestones', v_ms, 'reasoning_filed', v_held is not null);
end $fn$;
revoke execute on function public.fn_ceo_target_forecast() from public, anon, authenticated;

-- The review's apply, as in the_ceo_review_proves_its_author_on_the_class_think_bills.sql, except: a forecast decision is the
-- CEO's own (public.ceo_own_decision, with its reason), never a notice to the founder; an old held row still carrying
-- tell_founder is recorded the same way. The pricing proposal path is unchanged (its accountant challenge and its notice).
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
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  select * into rv from public.ceo_review where kind = v_kind and period = v_period for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'no review row'); end if;
  if rv.decided_at is not null then return jsonb_build_object('applied', true, 'already', v_kind || ' ' || v_period); end if;
  select coalesce(jsonb_object_agg(k, v->>'value'), '{}'::jsonb) into v_fields from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) f(k, v);

  if v_kind = 'pricing_monitor' and v_choice = 'propose_change' then
    v_gate := public.fn_high_stakes_gate('pricing_change', 'ceo', 'ceo_review', v_kind || ':' || v_period,
      'Challenge the chief executive''s pricing call before it reaches the founder.',
      case when length(rv.facts::text) <= 50000 then jsonb_build_object('facts', rv.facts)
           else jsonb_build_object('facts_cut_at_50000_chars', left(rv.facts::text, 50000)) end,
      jsonb_build_object('call', v_choice, 'fields', v_fields, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000),
                         'founder_detail', left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)),
      nullif(p_result->>'model', ''), 'internal_judgement');
    v_review := v_gate;
  elsif v_choice = 'propose_change' then
    v_review := public.fn_seat_duty_cross_review('ceo.' || v_kind, 'ceo', 'accountant',
      case v_kind when 'management_review' then 'Challenge the chief executive''s reading of the company''s week.'
                  else 'Challenge the chief executive''s pricing call before it reaches the founder.' end,
      case when length(rv.facts::text) <= 50000 then jsonb_build_object('facts', rv.facts)
           else jsonb_build_object('facts_cut_at_50000_chars', left(rv.facts::text, 50000)) end,
      jsonb_build_object('call', v_choice, 'fields', v_fields, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000)),
      p_result, 'ceo_review', v_kind || ':' || v_period);
  end if;
  update public.ceo_review set decision = v_choice, fields = v_fields, reasoning = left(coalesce(p_result->>'answer', ''), 6000),
         model = p_result->>'model', review = v_review, decided_at = now()
   where kind = v_kind and period = v_period;

  if v_kind = 'target_forecast' then
    -- the CEO's own decision, with its reason (ledger 1696); the old "tell_founder" answer is his decision to act within authority
    insert into public.ceo_own_decision (source, subject, choice, reason, reading, dedupe_key)
    values ('target_forecast', 'the year-one forecast, week of ' || v_period,
            case when v_choice = 'tell_founder' then 'act_within_authority' else v_choice end,
            left(coalesce(nullif(btrim(coalesce(v_fields->>'proposal', '') || ' ' || coalesce(v_fields->>'evidence', '')), ''), p_result->>'answer', 'no reason given'), 2000),
            jsonb_build_object('held_id', p_id, 'model', p_result->>'model', 'fields', v_fields, 'answered', v_choice), 'target_forecast:' || v_period)
    on conflict (dedupe_key) do nothing;
  elsif v_kind = 'pricing_monitor' and v_choice = 'propose_change' and coalesce((v_gate->>'proceed')::boolean, false) then
    v_notice := public.fn_ceo_review_tells_founder(v_kind, v_period, 'CEO pricing proposal (evidence-based) for the week of ' || v_period,
      left(coalesce(v_fields->>'proposal', '') || E'\n\n' || coalesce(v_fields->>'evidence', '') || E'\n\n' || coalesce(p_result->>'answer', ''), 4000)
        || E'\n\nThe accountant is challenging this on a model of another family (seat_deliberation '
        || coalesce(v_review->>'deliberation_id', 'not opened: ' || coalesce(v_review->>'error', v_review->>'reason', '?')) || ').',
      'founder_brief');
  end if;
  return jsonb_build_object('applied', true, 'kind', v_kind, 'period', v_period, 'choice', v_choice, 'review', v_review, 'founder', v_notice);
end $fn$;
revoke execute on function public.fn_ceo_review_applies(bigint, jsonb) from public, anon, authenticated;

-- ── 15. BUSY-WORK CUT: one monthly compliance batch to the it_engineer, not a directive per source to the CEO ─────────────
-- fn_ceo_register_review as in the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql, except the compliance loop.
create or replace function public.fn_ceo_register_review()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM'); r record; v_seat text; v_id bigint;
  n_risk int := 0; n_comp int := 0; n_vendor int := 0; n_cal int := 0; v_stale int; v_list text;
begin
  for r in select id, risk, owner_agent, review_due from public.risk_register
            where status = 'open' and coalesce(review_due, current_date - 1) < current_date loop
    v_seat := case when exists (select 1 from public.org_role where role_id = r.owner_agent and status = 'active') then r.owner_agent else 'ceo' end;
    v_id := public.fn_ceo_directive_issue(v_seat, 'register_review', 'risk_register:' || r.id || ':' || v_m,
      format('Review risk #%s (%s): it was due for review on %s. Re-score it, update the mitigation and set the next review date, or close it.',
             r.id, left(r.risk, 200), coalesce(r.review_due::text, 'no date')),
      format('risk #%s is closed or its review_due is today or later.', r.id),
      format($q$exists (select 1 from public.risk_register where id = %s and (status <> 'open' or review_due >= current_date))$q$, r.id),
      now() + interval '14 days', jsonb_build_object('register', 'risk_register', 'id', r.id));
    n_risk := n_risk + (v_id is not null)::int;
  end loop;

  -- compliance (15 Nov 2026, the CEO seat audit): nothing in the estate updates compliance_sources.last_checked_at, so a re-check
  -- directive per source to the CEO could never be met (72 open or escalated on 15 Nov). ONE monthly batch goes to the
  -- it_engineer, the seat that can build and run the fetch; it is met when no active source is older than 35 days.
  select count(*), string_agg('#' || id || ' ' || authority, ', ' order by id) into v_stale, v_list
    from (select id, authority from public.compliance_sources where active and coalesce(last_checked_at, 'epoch') < now() - interval '35 days' order by id limit 40) s;
  if v_stale > 0 then
    v_id := public.fn_ceo_directive_issue('it_engineer', 'register_review', 'compliance_sources:batch:' || v_m,
      format('Re-check the %s compliance sources not checked in 35 days (%s): fetch each, record last_checked_at and what changed, and route any change to the seat it affects. If no fetch exists yet, build it.', v_stale, left(v_list, 600)),
      'no active compliance source is older than 35 days.',
      $q$not exists (select 1 from public.compliance_sources where active and coalesce(last_checked_at, 'epoch') < now() - interval '35 days')$q$,
      now() + interval '21 days', jsonb_build_object('register', 'compliance_sources', 'stale', v_stale));
    n_comp := n_comp + (v_id is not null)::int;
  end if;

  for r in select kind, item, renews_on, coalesce(owner_seat, 'accountant') seat from public.v_company_subscriptions
            where renews_on is not null and renews_on < current_date + 14 loop
    v_id := public.fn_ceo_directive_issue(r.seat, 'register_review', 'vendor:' || r.kind || ':' || r.item || ':' || v_m,
      format('Vendor register: %s %s renews on %s. Confirm the renewal was charged and recorded (or that it was cancelled) so the register shows the next date.',
             r.kind, r.item, to_char(r.renews_on, 'DD Mon YYYY')),
      format('%s %s shows a renewal date at least 14 days ahead, or is no longer on the register.', r.kind, r.item),
      format($q$not exists (select 1 from public.v_company_subscriptions where kind = %L and item = %L and renews_on < current_date + 14)$q$, r.kind, r.item),
      now() + interval '7 days', jsonb_build_object('register', 'v_company_subscriptions', 'kind', r.kind, 'item', r.item, 'renews_on', r.renews_on));
    n_vendor := n_vendor + (v_id is not null)::int;
  end loop;

  for r in select id, event_name, verified_at from public.company_calendar
            where kind = 'compliance' and coalesce(verified_at, '1970-01-01') < current_date - 365 loop
    v_id := public.fn_ceo_directive_issue('ceo', 'register_review', 'company_calendar:' || r.id || ':' || v_m,
      format('Re-verify compliance calendar entry #%s (%s) against its source; last verified %s.', r.id, r.event_name, coalesce(r.verified_at::text, 'never')),
      format('calendar entry #%s was verified in the last year.', r.id),
      format($q$exists (select 1 from public.company_calendar where id = %s and verified_at >= current_date - 365)$q$, r.id),
      now() + interval '14 days', jsonb_build_object('register', 'company_calendar', 'id', r.id));
    n_cal := n_cal + (v_id is not null)::int;
  end loop;
  return jsonb_build_object('month', v_m, 'risks', n_risk, 'compliance_sources', n_comp, 'vendors', n_vendor, 'calendar', n_cal,
    'open', (select count(*) from public.ceo_directive where source_kind = 'register_review' and status = 'open'));
end $fn$;
revoke execute on function public.fn_ceo_register_review() from public, anon, authenticated;
grant execute on function public.fn_ceo_register_review() to service_role;

-- The open per-source re-checks the CEO addressed to himself are closed as superseded by the batch (status 'missed' is the only
-- closed state the table allows that is not a claim of success; the evidence says why). Idempotent: a second run finds none.
update public.ceo_directive
   set status = 'missed', evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('superseded', 'one monthly compliance batch to the it_engineer (the_ceo_thinks_plans_and_orders_every_week.sql): no seat updates compliance_sources.last_checked_at, so a per-source re-check to the CEO could never be met', 'superseded_at', now())
 where seat = 'ceo' and source_kind = 'register_review' and source_ref like 'compliance_sources:%' and status in ('open', 'escalated');

-- ── 16. THE FIRST PLAN AS DATA (week of 16 Nov 2026): filed by the loop's first run through fn_ceo_plan_file ───────────────
-- The audit's 16 Nov orders (SP/audit/CEO.md section 8), revised for ruling 1709: the founder's own network is bet 1 and no hire.
-- Due dates are absolute; the checks run when it is filed, so a bet whose date has passed by then is refused with the reason.
insert into public.ceo_plan_week (kind, period, status, task_class, output, pack)
select 'seed', date '2026-11-16', 'asked', 'seed',
'{"situation": "2 verified suppliers and 0 real inquiries; e-mail reaches only Google-hosted inboxes (Microsoft 0/21, Yahoo/AOL 0/17 on 10 Nov); 129 invited in 30 days, 1 approved; 5 supplier replies, all 5 dropped unanswered; invitations switched off; runway 7.46 months.",
  "binding_constraint": {"stage": "registrations", "evidence": "1 submitted of 115 delivered invitations; every reply lost; the only open mailbox class is Google (2,730 never-invited)"},
  "decision": {
   "bets": [
    {"channel": "founder_network", "seat": "founder", "what": "The founder messages and calls his own network from his own number with his tracked link; the CEO tells him every morning who started, submitted and was approved, and who is stuck at which step.", "how": "https://quotesdone.com/portal?join=1&utm_source=founder&utm_medium=whatsapp&utm_campaign=2026-11", "why": "Ledger 1709: his estimate is 20 to 100 registrations; people he knows convert far above cold mail.", "measure": "registrations_by_source", "measure_args": {"source": "founder"}, "target": 20, "direction": "at_least", "due_at": "2026-12-06T18:00:00+04:00", "expected_low": 20, "expected_high": 100, "cost_aed": 0, "legal": "Safe: people he knows, personal messages from his own number (PDPL: business contacts he holds; no list is taken).", "kill_criterion": "none: it is his network; the CEO reports the numbers"},
    {"channel": "reply_within_1h", "seat": "sales_engineer", "what": "Answer every supplier reply since 1 Nov with the registration link (5 replies dropped), and every new reply within one business hour.", "how": "Through the supplier mailbox reply path; answer only what they wrote; a STOP is honoured.", "why": "5 of 5 replies were dropped by the reply path; each answered reply is the warmest lead we have.", "measure": "replies_unanswered", "measure_args": {}, "target": 0, "direction": "at_most", "due_at": "2026-11-17T18:00:00+04:00", "expected_low": 1, "expected_high": 2, "cost_aed": 0, "legal": "Safe: a reply to their own mail; ledger 1301 covers the cold invitation only.", "kill_criterion": "never: the 1-hour answer is permanent"},
    {"channel": "email_invitation_google", "seat": "sales_engineer", "what": "Invitation batches in the three focus trades, Dubai, Google-hosted and verified addresses only, up to the 1231 schedule.", "how": "The existing invitation duty and the outbox: fn_email_sendable, suppressions, the placement bar.", "why": "The only open mailbox class; 1,248 never-invited Dubai Google addresses.", "measure": "invitations", "measure_args": {"trades": ["hvac", "electrical", "mep_general", "interior_fitout", "gypsum", "flooring", "building_materials"]}, "target": 100, "direction": "at_least", "due_at": "2026-11-23T18:00:00+04:00", "expected_low": 1, "expected_high": 3, "cost_aed": 0, "legal": "Safe at: 1231 schedule, bounce under 3%, checked-only, STOP line, one-click unsubscribe, no link (1301); Google class only (1537).", "kill_criterion": "bounce over 3% in 7 days, or 0 registrations from 250 delivered", "providers": ["google"]},
    {"channel": "registration_unblock", "seat": "sales_engineer", "what": "Every submitted registration decided within two days, so none of the founder''s people waits on us.", "how": "The registration review the sales engineer already owns; ask the supplier for what is missing through his own channel.", "why": "The founder''s people will arrive in a burst; a held registration is the next leak.", "measure": "held_registrations", "measure_args": {}, "target": 0, "direction": "at_most", "due_at": "2026-11-20T18:00:00+04:00", "expected_low": 0, "expected_high": 0, "cost_aed": 0, "legal": "Safe: e-mail through the outbox; WhatsApp only with his opt-in (1341).", "kill_criterion": "never"},
    {"channel": "deliverability_fix", "seat": "it_engineer", "what": "Microsoft inbox placement at least 80% on a GlockApps retest.", "how": "Honest warm-up of supplier@quotesdone.com; one GlockApps credit when ready; never lookalike domains.", "why": "The founder''s people on Microsoft-hosted company mail must receive our sign-up, approval and request mail; invitations stay off Microsoft by ruling 1537.", "measure": "placement_inbox_pct", "measure_args": {"provider_class": "microsoft"}, "target": 80, "direction": "at_least", "due_at": "2026-12-08T18:00:00+04:00", "expected_low": 0, "expected_high": 0, "cost_aed": 0, "legal": "Safe if honest warm-up (Microsoft and Google sender policies).", "kill_criterion": "two retests under 50%: stop and keep the Google class only"},
    {"channel": "supplier_referral", "seat": "it_engineer", "what": "Build the referral link asked at approval and the WhatsApp click-to-chat link on the site, the registration page and the e-mail signature.", "how": "A per-supplier referral link with utm_source referral; a wa.me link with the consent question.", "why": "Both channels are safe and cost nothing, and no seat can run them today.", "measure": "reported", "measure_args": {}, "target": 1, "direction": "at_least", "due_at": "2026-11-22T18:00:00+04:00", "expected_low": 0, "expected_high": 0, "cost_aed": 0, "legal": "Safe: the supplier sends from his own channel; the chat is started by the supplier (Meta policy, 1341).", "kill_criterion": "none: a build"},
    {"channel": "reply_within_1h", "seat": "customer_support", "what": "Every supplier conversation on WhatsApp and the website answered within one hour, with the consent question asked.", "how": "The support reply path; templates only after an opt-in.", "why": "The founder''s people and every click-to-chat will reach support first.", "measure": "replies_unanswered", "measure_args": {}, "target": 0, "direction": "at_most", "due_at": "2026-11-18T18:00:00+04:00", "expected_low": 0, "expected_high": 1, "cost_aed": 0, "legal": "Safe: the person wrote first; replies inside the 24-hour window (Meta).", "kill_criterion": "never"},
    {"channel": "linkedin_company_page", "seat": "marketing", "what": "Three company-page posts a week for the focus trades; Google Business Profile verified; Dubai Chamber listing applied for.", "how": "The monthly calendar; never boosted (1456); honest copy: before buyers start sending requests.", "why": "Trust for the founder''s people who look us up, at no cost.", "measure": "reported", "measure_args": {}, "target": 1, "direction": "at_least", "due_at": "2026-11-30T18:00:00+04:00", "expected_low": 0, "expected_high": 1, "cost_aed": 0, "legal": "Safe: organic posts; no paid placement (1456); no incentivised reviews (Google policy).", "kill_criterion": "0 tagged registrations from 12 posts"}
   ],
   "ceo_actions": [
    {"kind": "set_trade_priority", "add": ["hvac", "electrical", "mep_general", "gypsum", "building_materials"], "remove": ["painting", "signage", "upholstery"], "reason": "The operating target names three Dubai focus trades from the only recorded demand (2 HVAC customers waiting, 1 electrical intake) and fee size; painting, signage and upholstery were chosen on pool size alone."},
    {"kind": "narrow_coverage_to_operating_target", "reason": "143 of the 144 coverage targets came from recruitment notes with no recorded demand; the CEO holds only his three focus trades (and real demand wherever it is) until they open."}
   ],
   "dropped": [
    {"option": "hire a part-time caller", "why": "ruling 1709: no hire; the founder calls his own network"},
    {"option": "WhatsApp templates to scraped mobiles", "why": "refused: Meta policy (1341); click-to-chat instead"},
    {"option": "LinkedIn or other ads", "why": "refused: ledger 1456"},
    {"option": "bulk SMS", "why": "refused: ledger 1185"},
    {"option": "mail Microsoft or Yahoo hosts now", "why": "refused while they fail placement; fix Microsoft first"}
   ]}}'::jsonb,
  jsonb_build_object('source', 'the CEO seat audit of 15 Nov 2026 (SP/audit/CEO.md sections 7 and 8), revised for founder ledger 1709')
 where not exists (select 1 from public.ceo_plan_week where kind = 'seed');

-- ── 17. ONE DUTY (measure and learn even when the heartbeat's model call does not run) ─────────────────────────────────────
-- The tick itself is called by resilience_ping's CEO plan step, which also calls ceo_agent action 'plan' when it says call_model.
-- The duty keeps the measurement alive on its own: fn_ceo_plan_due is idempotent by day and by plan.
create or replace function public.fn_ceo_planning_loop_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb;
begin
  begin v := public.fn_ceo_plan_due(now(), false);
  exception when others then v := jsonb_build_object('error', left(sqlerrm, 300)); end;
  return v;
end $fn$;
revoke execute on function public.fn_ceo_planning_loop_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.planning_loop', 'ceo', interval '1 hour', 'fn_ceo_planning_loop_tick',
   'Founder ledger 1696/1701/1705/1709: the CEO measures every bet of his plan daily and learns the channel priors; files the seeded first plan; asks for the weekly reasoned plan on Monday and a daily review only on an anomaly (ceo_agent action plan answers it); code checks every order before it is filed.',
   'scripts/sql/the_ceo_thinks_plans_and_orders_every_week.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
