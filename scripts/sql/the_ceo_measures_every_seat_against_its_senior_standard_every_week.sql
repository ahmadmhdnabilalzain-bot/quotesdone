-- THE CEO MEASURES EVERY SEAT AGAINST ITS SENIOR STANDARD EVERY WEEK, IN TWO STAGES, AND NEVER ON OPINION.
--
-- Assigned: ceo. 27 Oct 2026. Founder ledger 1003: "Audit every seat against a real senior human expert in two stages.
-- (1) Qualifications: ... measure our agent's actual qualifications, and state how senior it truly is. (2) Contribution:
-- if we hired that senior human at QuotesDone, what would they do to help the company grow? Compare with what our agent
-- does, and build what is missing. ... Never call a seat 'good to go' on opinion."
--
-- ══ MEASURED, 27 Oct 2026, htdblwldjkcgjvmqkbeh (read-only) ═════════════════════════════════════════════════════════
--   The senior standard exists in the repository (knowledge/standards/<seat>.json, 19 Oct) and is measured only by a
--   script a session runs by hand (scripts/eval/seat_senior_audit.mjs): nothing in production holds a two-stage verdict.
--   The quarterly ceo.seat_audit (the_ceo_audits_every_seat_each_quarter.sql) reads knowledge from seat_knowledge_exam,
--   which has 2 graded items per seat in 90 days (the model-graded exam was retired 24 Sep), so its knowledge line
--   reads "not measured" for all six seats; every seat's monthly self_review reads trend 'no_exam' with 0 items
--   (seat_exam_item is empty). Stage 1 is blind in production, and stage 2 counts duties, not contributions.
--
-- ══ WHAT THIS ADDS (code only; no model) ═══════════════════════════════════════════════════════════════════════════
--   seat_senior_contribution  each seat's senior contributions and the seat_duty keys that make each one (seeded from
--                             knowledge/standards; the block below is generated, and a check holds it equal).
--   seat_senior_exam          each seat's judged LLM-on exam: items in the bank, items passed (seeded from
--                             knowledge/exams and knowledge/exams/judged; refreshed whenever a new judged run lands).
--   seat_senior_verdict       one row per seat per Dubai week:
--     stage 1 (qualification)  the judged exam pass rate; the outcome accuracy of the seat's graded judgements (90 days);
--                              knowledge recall in English and Arabic (latest day, informational).
--     stage 2 (contribution)   contributions live (every named duty enabled and ok within twice its clock plus a day);
--                              duties on their clock; handoffs with a reply window ANSWERED inside it (detail.replied_at,
--                              else the close; 30 days); handoffs unanswered past it now; re-verifications this seat owes
--                              as an originator (informational); its own non-handoff actions and handoffs sent (30 days).
--     level   senior  only when the exam is >= 95 %, every contribution is live, 95 %+ of duties are on their clock,
--                     90 %+ of windowed handoffs were answered in time, and graded judgements (20+) are 80 %+ right;
--             mid     exam >= 80 % and 90 %+ of contributions live;
--             junior  otherwise. No measurement = not met: a seat with no judged exam cannot be mid or senior.
--     The exam and contribution thresholds are scripts/eval/seat_senior_audit.mjs's (SENIOR_BAR 0.95, mid 0.8 / 0.9);
--     the check holds them equal.
--   ceo.senior_verdict (weekly) fn_ceo_seat_senior_verdict(): writes the week's rows. A seat whose level FALLS from the
--   previous week gets one improvement from the CEO (fn_ceo_improvement_open, source 'seat_audit', ref
--   'senior:<seat>:<week>') naming each measure that fell. A level that holds opens nothing: the standing shortfalls are
--   on the row and in docs/reports/seat_audit_27_oct.md, and the missing contributions are build orders, not seat work.
--
-- WHAT IT DOES NOT DO. It does not change the quarterly audit, the exams, the duties or any seat's work. It does not
-- grade an answer: the exam is judged by a reader against answer_must (scripts/eval/seat_exam_through_think.ts).
--
-- Prevented by: scripts/checks/the_senior_verdict_is_measured_against_the_standard_in_the_repository.test.mjs
-- Pending: scripts/sql/pending/the_ceo_measures_every_seat_against_its_senior_standard_every_week.txt

create table if not exists public.seat_senior_contribution (
  seat            text not null references public.org_role (role_id),
  contribution_id text not null,
  what            text not null,
  duties          text[] not null default '{}',
  primary key (seat, contribution_id)
);
comment on table public.seat_senior_contribution is
  'ceo: what a senior hire in each seat would contribute (knowledge/standards/<seat>.json, ledger 1003 stage 2) and the seat_duty keys that make it. Seeded by the_ceo_measures_every_seat_against_its_senior_standard_every_week.sql.';
alter table public.seat_senior_contribution enable row level security;
drop policy if exists seat_senior_contribution_service_role_only on public.seat_senior_contribution;
create policy seat_senior_contribution_service_role_only on public.seat_senior_contribution
  as permissive for all to public using (false) with check (false);
revoke all on public.seat_senior_contribution from anon, authenticated;

create table if not exists public.seat_senior_exam (
  seat      text not null references public.org_role (role_id),
  judged_on date not null,
  items     int not null check (items > 0),
  passed    int not null check (passed between 0 and items),
  source    text not null,
  primary key (seat, judged_on)
);
comment on table public.seat_senior_exam is
  'ceo: each seat''s judged LLM-on exam (ledger 1003 stage 1): the reworded questions asked of the seat''s real models, each answer read against answer_must. Items = the whole bank, so an unasked item counts as not passed.';
alter table public.seat_senior_exam enable row level security;
drop policy if exists seat_senior_exam_service_role_only on public.seat_senior_exam;
create policy seat_senior_exam_service_role_only on public.seat_senior_exam
  as permissive for all to public using (false) with check (false);
revoke all on public.seat_senior_exam from anon, authenticated;

create table if not exists public.seat_senior_verdict (
  week        date not null,
  seat        text not null references public.org_role (role_id),
  stage1      jsonb not null,
  stage2      jsonb not null,
  level       text not null check (level in ('junior', 'mid', 'senior')),
  shortfalls  text[] not null default '{}',
  improvement_id bigint,
  measured_at timestamptz not null default now(),
  primary key (week, seat)
);
comment on table public.seat_senior_verdict is
  'ceo.senior_verdict: each seat''s weekly two-stage verdict against a senior human (ledger 1003): stage 1 qualification, stage 2 contribution, the level and every shortfall with its number.';
alter table public.seat_senior_verdict enable row level security;
drop policy if exists seat_senior_verdict_service_role_only on public.seat_senior_verdict;
create policy seat_senior_verdict_service_role_only on public.seat_senior_verdict
  as permissive for all to public using (false) with check (false);
revoke all on public.seat_senior_verdict from anon, authenticated;

-- The daily export: the standard and the judged exam are copies of the repository (its source), the verdict is the CEO's
-- record and is kept, as ceo_seat_audit is.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('seat_senior_contribution', false, 'cache', 'A copy of knowledge/standards/<seat>.json contributions, re-seeded by the_ceo_measures_every_seat_against_its_senior_standard_every_week.sql (ledger 1003).', 'ceo'),
  ('seat_senior_exam', false, 'cache', 'A copy of knowledge/exams/judged/<seat>.json pass counts, re-seeded from the repository (ledger 1003).', 'ceo'),
  ('seat_senior_verdict', true, 'decision', 'The CEO''s weekly two-stage senior verdict per seat (ledger 1003).', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- BEGIN STANDARD SEED (generated by scripts/eval/seat_senior_standard_seed.mjs; do not edit by hand)
delete from public.seat_senior_contribution where seat = any (array['accountant', 'ceo', 'customer_support', 'it_engineer', 'marketing', 'sales_engineer']::text[]);
insert into public.seat_senior_contribution (seat, contribution_id, what, duties) values
  ('accountant', 'ACC-C01', 'Confirms every paid reveal in Stripe, files the invoice in the portal and Dropbox', array['accountant.reveal_invoice_filing']::text[]),
  ('accountant', 'ACC-C02', 'Matches every Stripe payout to the bank daily', array['accountant.stripe_reconcile']::text[]),
  ('accountant', 'ACC-C03', 'Closes and locks the month by day 5 and sends the founder close pack', array['accountant.close_by_day_five', 'accountant.founder_close_pack']::text[]),
  ('accountant', 'ACC-C04', 'Keeps one cash truth and reports cash, reserve and runway against budget', array['accountant.cash_truth', 'accountant.runway_report']::text[]),
  ('accountant', 'ACC-C05', 'Proves every refund was the amount paid, CEO-approved and on the same charge', array['accountant.refund_correctness']::text[]),
  ('accountant', 'ACC-C06', 'Watches for duplicate accounts, fee circumvention and risky parties before money moves', array['accountant.fraud_watch', 'accountant.risk_screen']::text[]),
  ('accountant', 'ACC-C07', 'Re-screens suppliers and their beneficial owners against sanctions lists', array['accountant.sanctions_rescreen', 'accountant.ubo_rescreen', 'accountant.ubo_watch']::text[]),
  ('accountant', 'ACC-C08', 'Reconciles ad spend reported by marketing against booked invoices, including zero months', array['accountant.ad_spend_reconcile']::text[]),
  ('accountant', 'ACC-C09', 'Keeps Stripe customer emails off so only QuotesDone receipts reach customers', array['accountant.stripe_email_setting']::text[]),
  ('accountant', 'ACC-C10', 'Re-sits its qualification exam monthly and opens work on what it failed', array['accountant.self_review']::text[]),
  ('accountant', 'ACC-C11', 'Books every receipt arriving in the expenses mailbox and holds what it cannot read', array['accountant.receipt_intake']::text[]),
  ('accountant', 'ACC-C12', 'Tracks every supplier non-response charge to payment or court on the UAE clock', array['accountant.charge_recovery']::text[]),
  ('accountant', 'ACC-C13', 'Maintains the 13-week cash forecast and the monthly budget variance review', array['accountant.runway_report']::text[]),
  ('accountant', 'ACC-C14', 'Watches revenue against the VAT thresholds (AED 187,500 voluntary, AED 375,000 mandatory) and tells the CEO in time to register within 30 days', array['accountant.vat_threshold']::text[]),
  ('accountant', 'ACC-C15', 'Sends the CEO a weekly finance report: cash, collections, exceptions and decisions needed', array['accountant.finance_week']::text[]),
  ('accountant', 'ACC-C16', 'Builds the year-end pack and audit-readiness file and raises auditor appointment before the first year-end', array['accountant.year_end']::text[]),
  ('ceo', 'CEO-C01', 'Reads the business every morning against the year-one path and sets each seat''s priorities', array['ceo.daily_run', 'ceo.target_verdict']::text[]),
  ('ceo', 'CEO-C02', 'Runs the weekly management review per seat with a verdict and the binding constraint, challenged by another model family', array['ceo.management_review']::text[]),
  ('ceo', 'CEO-C03', 'Issues directives with a done-condition to every seat and closes them when met', array['ceo.directive']::text[]),
  ('ceo', 'CEO-C04', 'Closes last month per seat, sends the founder the monthly review/board pack and issues each seat''s month directive', array['ceo.month_plan', 'ceo.strategy_memo']::text[]),
  ('ceo', 'CEO-C05', 'Forecasts which scenario the company is tracking and answers an off-track verdict with a counter-action', array['ceo.target_forecast']::text[]),
  ('ceo', 'CEO-C06', 'Turns the binding constraint and recurring misses into improvements and closes them', array['ceo.constraint_lever', 'ceo.improvement', 'ceo.improvement_review']::text[]),
  ('ceo', 'CEO-C07', 'Drives supply to the 50 / 200 / 300 verified milestones and the launch go/no-go before customers open', array['ceo.supplier_target', 'ceo.launch_readiness', 'ceo.company_stage']::text[]),
  ('ceo', 'CEO-C08', 'Monitors pricing evidence and brings evidence-based proposals to the founder', array['ceo.pricing_monitor']::text[]),
  ('ceo', 'CEO-C09', 'Runs one growth experiment a month to a recorded verdict', array['ceo.experiment_review']::text[]),
  ('ceo', 'CEO-C10', 'Audits every seat quarterly and re-sits its own qualification exam monthly', array['ceo.seat_audit', 'ceo.self_review']::text[]),
  ('ceo', 'CEO-C11', 'Answers every report the hour it arrives and keeps the CEO queue clean', array['ceo.report_answer', 'ceo.queue_work']::text[]),
  ('ceo', 'CEO-C12', 'Reviews next month''s marketing plan and chases it when late', array['ceo.marketing_plan']::text[]),
  ('ceo', 'CEO-C13', 'Rules on refunds and disputes as the approving seat', array['ceo.report_answer']::text[]),
  ('ceo', 'CEO-C14', 'Keeps the risk register, compliance calendar and vendor register reviewed every month', array['ceo.register_review']::text[]),
  ('customer_support', 'CS-C01', 'Answer every chat, WhatsApp and email question in the same reply, grounded, in the person''s language', array[]::text[]),
  ('customer_support', 'CS-C02', 'Weekly case review: first-reply time, resolution, repeat contacts, complaints, unanswered questions filed as knowledge requests', array['customer_support.case_review']::text[]),
  ('customer_support', 'CS-C03', 'Turn every unanswered question into a knowledge request and close it with an entry', array['customer_support.case_review']::text[]),
  ('customer_support', 'CS-C04', 'Weekly root-cause loop: group cases, fix support''s own causes, hand the rest to the owning seat', array['customer_support.root_cause_loop']::text[]),
  ('customer_support', 'CS-C05', 'Close answered cases the customer left idle and ask for the CSAT rating', array['customer_support.case_idle_close']::text[]),
  ('customer_support', 'CS-C06', 'Monthly tone and readability review of every reply by channel and language', array['customer_support.monthly_self_review']::text[]),
  ('customer_support', 'CS-C07', 'Re-sit the qualification exam and senior checklist monthly and open the seat''s own gaps', array['customer_support.self_review']::text[]),
  ('customer_support', 'CS-C08', 'Deliver every other seat''s messages and return a verified delivery outcome', array[]::text[]),
  ('customer_support', 'CS-C09', 'Watch delivery health daily: bounces, suppressions, WhatsApp failures, template approval, unsubscribe endpoint', array[]::text[]),
  ('customer_support', 'CS-C10', 'Run complaints to the published service levels (acknowledge, update, final response) with a reference number', array['customer_support.case_review']::text[]),
  ('customer_support', 'CS-C11', 'Handle PDPL data subject requests (access, correction, erasure, objection) with identity check and a tracked clock', array[]::text[]),
  ('customer_support', 'CS-C12', 'Tell customers proactively during a platform incident, in English and Arabic, coordinated with the IT engineer', array[]::text[]),
  ('customer_support', 'CS-C13', 'Monitor public reviews and social complaints and answer them within the service levels', array[]::text[]),
  ('customer_support', 'CS-C14', 'Report voice-of-the-customer findings (CSAT, top contact reasons, effort) to the CEO monthly with actions', array['customer_support.case_review']::text[]),
  ('it_engineer', 'IT-C01', 'Measures 30-day uptime of every public URL from external 15-minute probes against 99.9% and raises a finding below target', array['it_engineer.uptime_slo']::text[]),
  ('it_engineer', 'IT-C02', 'Holds the 2.5 s p95 budget for every portal data function and the home page, handing breaches to the owning seat', array['it_engineer.latency_slo']::text[]),
  ('it_engineer', 'IT-C03', 'Keeps backups in Supabase and Dropbox, measures achieved RPO/RTO daily and restores a table weekly and a sample monthly', array['it_engineer.backup_objectives']::text[]),
  ('it_engineer', 'IT-C04', 'Rehearses a full-database restore into scratch each quarter and reviews DR', array['it_engineer.dr_review']::text[]),
  ('it_engineer', 'IT-C05', 'Rotates every internal credential on schedule and proves each rotation', array['it_engineer.credential_rotation_age']::text[]),
  ('it_engineer', 'IT-C06', 'Watches provider cost weekly and model spend hourly (unlisted consumers, loops, repeated paid prompts, class over budget)', array['it_engineer.cost_watch', 'it_engineer.model_spend']::text[]),
  ('it_engineer', 'IT-C07', 'Writes an incident record with root cause and a regression check for every closed critical/high fault', array['it_engineer.postmortem']::text[]),
  ('it_engineer', 'IT-C08', 'Chases every non-demo finding older than 24 hours back to its owning seat once a day', array['it_engineer.finding_chase']::text[]),
  ('it_engineer', 'IT-C09', 'Runs a monthly game day injecting five faults on fixture traffic and timing detection and recovery', array['it_engineer.game_day']::text[]),
  ('it_engineer', 'IT-C10', 'Reviews capacity against disk/storage limits and code health (definer search_path, RLS without policy, failing duties) monthly', array['it_engineer.capacity_review', 'it_engineer.code_health']::text[]),
  ('it_engineer', 'IT-C11', 'Detects data-quality faults daily: demo rows crossing into real parties, orphans, transaction-quote mismatches', array['it_engineer.data_quality']::text[]),
  ('it_engineer', 'IT-C12', 'Keeps all seats'' knowledge measured: recall every 30 min, pass-rate trend daily, quarterly refresh, monthly self-review', array['it_engineer.knowledge_recall', 'it_engineer.knowledge_pass_rate', 'it_engineer.knowledge_refresh', 'it_engineer.self_review']::text[]),
  ('it_engineer', 'IT-C13', 'Guards the perimeter hourly/daily: OTP pumping, provider usage caps, provider status, sender health, Postmaster, DB health, monthly access review', array['it_engineer.perimeter_freshness']::text[]),
  ('it_engineer', 'IT-C14', 'Turns failure clusters in agent_runs (over 50% non-ok, more than 5 runs in 7 days) into owned findings, and flags run labels with no owner', array['it_engineer.run_clusters']::text[]),
  ('it_engineer', 'IT-C15', 'Triages dependency and platform advisories (deployed? CVSS v4, EPSS) and audits GitHub workflows for unpinned actions and excess token permissions', array['it_engineer.advisory_triage']::text[]),
  ('it_engineer', 'IT-C16', 'Load-tests the inquiry, quote and reveal journeys to the breakpoint before customers arrive in January 2027 and records the ceiling', array['it_engineer.load_test']::text[]),
  ('it_engineer', 'IT-C17', 'Removes suppliers with an expired trade licence from matching automatically', array[]::text[]),
  ('marketing', 'MKT-C01', 'Monthly marketing plan drafted, reviewed by the CEO seat and sent to the founder for one-shot approval on the 1st', array['marketing.month_plan']::text[]),
  ('marketing', 'MKT-C02', 'One SEO/GEO article a week, released only on the founder''s approval on a UAE working day', array['marketing.article_release']::text[]),
  ('marketing', 'MKT-C03', 'Monthly answer-engine (GEO) prompt panel: are we cited, by which engine, and what to fix', array['marketing.geo_check']::text[]),
  ('marketing', 'MKT-C04', 'Supplier recruitment plan per thin trade: ranked by gap and demand, where its suppliers gather, an English invitation variant', array['marketing.gap_recruitment_plans']::text[]),
  ('marketing', 'MKT-C05', 'Supplier acquisition funnel analytics per recruit gap (invited, registered, verified, quoting) with diagnosis', array['marketing.recruitment_funnel']::text[]),
  ('marketing', 'MKT-C06', 'Competitor watch: home and pricing pages, social posts, material changes raised to the CEO, weekly brief', array['marketing.competitor_scan', 'marketing.competitor_refresh']::text[]),
  ('marketing', 'MKT-C07', 'Reputation: ask every revealed customer for a public review 3 weeks after reveal, daily review snapshot, reply to reviews', array['marketing.reputation']::text[]),
  ('marketing', 'MKT-C08', 'January 2027 launch plan redrawn from category readiness, organic only until every category is open, sent for approval from 1 December', array['marketing.launch_plan']::text[]),
  ('marketing', 'MKT-C09', 'Monthly self-review against the qualification exam and senior checklist, opening the seat''s own improvements', array['marketing.self_review']::text[]),
  ('marketing', 'MKT-C10', 'Publish the approved social calendar natively per platform (LinkedIn, Instagram/Facebook, TikTok, YouTube, X) on working days, with UTM links', array[]::text[]),
  ('marketing', 'MKT-C11', 'Community management: classify and answer comments and DMs within 1-2 working hours, route leads and complaints', array[]::text[]),
  ('marketing', 'MKT-C12', 'Weekly trend scan (TikTok Creative Center, Google Trends UAE, regulatory news) with a 48-hour accept/reject decision', array[]::text[]),
  ('marketing', 'MKT-C13', 'Monthly marketing scorecard: suppliers registered per campaign, cost per registered supplier, GEO citations, share of voice, post performance by pillar', array[]::text[]),
  ('marketing', 'MKT-C14', 'Fact register kept in sync: a changed fee or policy updates every page, schema, llms.txt and profile the same day', array[]::text[]),
  ('marketing', 'MKT-C15', 'Ad-spend reporting to the accountant and paid campaigns once a budget is approved (creative tests, pacing, kill line)', array['marketing.launch_plan']::text[]),
  ('sales_engineer', 'SE-C01', 'Matches every qualified inquiry to exact-trade suppliers and rescues any request with no quote 48 h after matching', array['sales_engineer.stalled_inquiry_rescue', 'sales_engineer.supplier_availability']::text[]),
  ('sales_engineer', 'SE-C02', 'Holds a flagged quote and sends the supplier exact fixes so the customer only sees clean, comparable quotes', array['sales_engineer.quote_quality_hold']::text[]),
  ('sales_engineer', 'SE-C03', 'Delivers the comparison report and measures time to comparison and share with 3+ complete quotes', array['sales_engineer.comparison_kpi']::text[]),
  ('sales_engineer', 'SE-C04', 'Moves every invited supplier to first quote, stage by stage', array['sales_engineer.supplier_onboarding']::text[]),
  ('sales_engineer', 'SE-C05', 'Scores every supplier and feeds the score to matching; sends a monthly scorecard', array['sales_engineer.supplier_performance', 'sales_engineer.supplier_scorecard']::text[]),
  ('sales_engineer', 'SE-C06', 'Keeps no expired-licence supplier matchable', array['sales_engineer.licence_expiry_watch']::text[]),
  ('sales_engineer', 'SE-C07', 'Finds supply gaps per trade and emirate and gets them recruited', array['sales_engineer.supply_gap']::text[]),
  ('sales_engineer', 'SE-C08', 'Converts new customers to a first request and a first quote (concierge and activation)', array['sales_engineer.concierge', 'sales_engineer.activation']::text[]),
  ('sales_engineer', 'SE-C09', 'Learns the outcome of every reveal and wins back dormant customers', array['sales_engineer.followup', 'sales_engineer.winback']::text[]),
  ('sales_engineer', 'SE-C10', 'Reasons post-reveal dispute findings for the CEO', array['sales_engineer.disputes']::text[]),
  ('sales_engineer', 'SE-C11', 'Reviews quality weekly and learns from every hold and correction', array['sales_engineer.weekly_quality_review', 'sales_engineer.knowledge_gap_sweep', 'sales_engineer.self_review']::text[]),
  ('sales_engineer', 'SE-C12', 'Negotiates for the customer once quotes are levelled (clarify, then levers, then price)', array['sales_engineer.negotiation_round']::text[]),
  ('sales_engineer', 'SE-C13', 'Runs a win/loss review on chosen, declined and no-decision outcomes and reduces leakage', array['sales_engineer.win_loss_review']::text[]),
  ('sales_engineer', 'SE-C14', 'Proposes framework/rate agreements to repeat customers', array['sales_engineer.framework_proposal']::text[]);
insert into public.seat_senior_exam (seat, judged_on, items, passed, source) values
  ('accountant', date '2026-10-19', 109, 53, 'knowledge/exams/judged/accountant.json'),
  ('ceo', date '2026-10-19', 122, 63, 'knowledge/exams/judged/ceo.json'),
  ('customer_support', date '2026-10-19', 96, 35, 'knowledge/exams/judged/customer_support.json'),
  ('it_engineer', date '2026-10-19', 109, 42, 'knowledge/exams/judged/it_engineer.json'),
  ('marketing', date '2026-10-19', 78, 38, 'knowledge/exams/judged/marketing.json'),
  ('sales_engineer', date '2026-10-19', 122, 50, 'knowledge/exams/judged/sales_engineer.json')
on conflict (seat, judged_on) do update set items = excluded.items, passed = excluded.passed, source = excluded.source;
-- END STANDARD SEED

create or replace function public.fn_ceo_seat_senior_verdict(p_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c_senior_exam  constant numeric := 0.95;   -- SENIOR_BAR in scripts/eval/seat_senior_audit.mjs
  c_mid_exam     constant numeric := 0.80;   -- mid-level exam bar in seat_senior_audit.mjs
  c_mid_contrib  constant numeric := 0.90;   -- mid-level contribution bar
  c_on_clock     constant numeric := 0.95;
  c_on_time      constant numeric := 0.90;
  c_judged_min   constant int     := 20;
  c_judged_bar   constant numeric := 0.80;
  v_week date := date_trunc('week', p_at at time zone 'Asia/Dubai')::date;
  s record; v_s1 jsonb; v_s2 jsonb; v_short text[]; v_level text; v_prev text; v_id bigint;
  v_exam numeric; v_items int; v_passed int; v_judged_n int; v_judged_ok numeric;
  v_contrib int; v_live int; v_not_live jsonb; v_duties int; v_on_clock int;
  v_win int; v_in_time int; v_late_open int; v_own int; v_sent int; v_owed int;
  n_seats int := 0; n_fell int := 0; v_levels jsonb := '{}'::jsonb;
begin
  for s in select role_id from public.org_role where status = 'active' order by role_id loop
    n_seats := n_seats + 1;

    -- STAGE 1: qualification
    select e.items, e.passed into v_items, v_passed from public.seat_senior_exam e
     where e.seat = s.role_id order by e.judged_on desc limit 1;
    v_exam := case when v_items > 0 then round(v_passed::numeric / v_items, 3) end;
    select count(*), round(avg(j.outcome_correct::int), 3) into v_judged_n, v_judged_ok
      from public.seat_judgement j
     where j.seat = s.role_id and j.outcome_correct is not null and j.made_at > p_at - interval '90 days';
    v_s1 := jsonb_build_object(
      'exam_items', v_items, 'exam_passed', v_passed, 'exam_rate', v_exam,
      'judged_outcomes_90d', v_judged_n, 'judged_correct_rate', v_judged_ok,
      'recall', (select jsonb_build_object('day', r.day, 'questions', r.questions, 'en', r.recall_en, 'ar', r.recall_ar)
                   from public.seat_knowledge_recall r where r.seat = s.role_id order by r.day desc limit 1));

    -- STAGE 2: contribution
    with c as (
      select sc.contribution_id, sc.what, sc.duties,
             cardinality(sc.duties) > 0 and not exists (
               select 1 from unnest(sc.duties) k
                where not exists (select 1 from public.seat_duty d
                                   where d.duty = k and d.enabled and d.last_ok_at is not null
                                     and d.last_ok_at >= p_at - (d.every * 2 + interval '1 day'))) as live
        from public.seat_senior_contribution sc where sc.seat = s.role_id)
    select count(*), count(*) filter (where live),
           coalesce(jsonb_agg(contribution_id || ' ' || left(what, 120) order by contribution_id) filter (where not live), '[]'::jsonb)
      into v_contrib, v_live, v_not_live from c;
    select count(*), count(*) filter (where d.last_ok_at >= p_at - (d.every * 2 + interval '1 day'))
      into v_duties, v_on_clock from public.seat_duty d where d.owner_seat = s.role_id and d.enabled;
    -- THE RECEIVER'S ANSWER, not the close. Measured 27 Oct 2026: on a kind the originator closes, decided_at is the
    -- originator's re-verification and detail.replied_at is the receiver's reply; sales_engineer's it.finding handoffs
    -- (4-hour window) were replied in time 414 of 414 and closed in time 21 of 414. A handoff already answered and
    -- waiting for its originator is not late on the receiver.
    select count(*) filter (where a.status = 'done' or a.detail ? 'replied_at'),
           count(*) filter (where (a.status = 'done' or a.detail ? 'replied_at')
                              and coalesce((a.detail->>'replied_at')::timestamptz, a.decided_at) <= a.created_at + k.reply_within),
           count(*) filter (where a.status = 'pending' and not a.detail ? 'replied_at' and a.created_at < p_at - k.reply_within)
      into v_win, v_in_time, v_late_open
      from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.agent = s.role_id and k.reply_within is not null
       and a.created_at > p_at - interval '30 days' and coalesce(a.title, '') not like '%ZZ DEMO%';
    -- The other half of a loop (nothing is one-way): handoffs THIS seat sent, answered, and still waiting for this seat to
    -- re-verify and close, past one more reply window. Informational: an it.finding legitimately waits on its fix.
    select count(*) into v_owed
      from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'from' = s.role_id and k.originator_closes
       and k.reply_within is not null and a.detail ? 'replied_at'
       and (a.detail->>'replied_at')::timestamptz < p_at - k.reply_within and coalesce(a.title, '') not like '%ZZ DEMO%';
    select count(*) filter (where a.agent = s.role_id and a.kind <> 'handoff'),
           count(*) filter (where a.kind = 'handoff' and a.detail->>'from' = s.role_id and a.agent <> s.role_id)
      into v_own, v_sent
      from public.agent_actions a where a.created_at > p_at - interval '30 days';
    v_s2 := jsonb_build_object(
      'contributions', v_contrib, 'contributions_live', v_live,
      'contributions_live_rate', case when v_contrib > 0 then round(v_live::numeric / v_contrib, 3) end,
      'contributions_not_live', v_not_live,
      'duties', v_duties, 'duties_on_clock', v_on_clock,
      'duties_on_clock_rate', case when v_duties > 0 then round(v_on_clock::numeric / v_duties, 3) end,
      'windowed_handoffs_answered_30d', v_win, 'answered_in_window_30d', v_in_time,
      'answered_in_window_rate', case when v_win > 0 then round(v_in_time::numeric / v_win, 3) end,
      'handoffs_unanswered_past_window_now', v_late_open, 'closes_owed_past_window_now', v_owed,
      'own_actions_30d', v_own, 'handoffs_sent_30d', v_sent);

    -- THE LEVEL, and every shortfall with its number. No measurement is never a pass.
    v_short := '{}';
    if v_exam is null then v_short := v_short || 'stage 1: no judged exam'::text;
    elsif v_exam < c_senior_exam then
      v_short := v_short || format('stage 1: exam %s%% (%s of %s) below the senior 95%%', round(v_exam * 100, 1), v_passed, v_items);
    end if;
    if v_judged_n >= c_judged_min and v_judged_ok < c_judged_bar then
      v_short := v_short || format('stage 1: %s%% of %s graded judgements right (bar 80%%)', round(v_judged_ok * 100), v_judged_n);
    end if;
    if v_contrib = 0 then v_short := v_short || 'stage 2: no senior contributions defined'::text;
    elsif v_live < v_contrib then
      v_short := v_short || format('stage 2: %s of %s senior contributions live', v_live, v_contrib);
    end if;
    if v_duties = 0 or v_on_clock::numeric / v_duties < c_on_clock then
      v_short := v_short || format('stage 2: %s of %s duties on their clock', v_on_clock, v_duties);
    end if;
    if v_win > 0 and v_in_time::numeric / v_win < c_on_time then
      v_short := v_short || format('stage 2: %s of %s windowed handoffs answered within their window in 30 days', v_in_time, v_win);
    end if;
    if v_late_open > 0 then v_short := v_short || format('stage 2: %s handoffs unanswered past their window now', v_late_open); end if;

    v_level := case
      when cardinality(v_short) = 0 then 'senior'
      when v_exam >= c_mid_exam and v_contrib > 0 and v_live::numeric / v_contrib >= c_mid_contrib then 'mid'
      else 'junior' end;

    -- a level that FELL since the last verdict is the CEO's to act on, once
    select v.level into v_prev from public.seat_senior_verdict v where v.seat = s.role_id and v.week < v_week order by v.week desc limit 1;
    v_id := null;
    if v_prev is not null and array_position(array['junior', 'mid', 'senior'], v_level) < array_position(array['junior', 'mid', 'senior'], v_prev) then
      v_id := public.fn_ceo_improvement_open('seat_audit', 'senior:' || s.role_id || ':' || v_week, s.role_id,
        format('Senior verdict for %s fell from %s to %s in the week of %s. ', s.role_id, v_prev, v_level, to_char(v_week, 'DD Mon YYYY'))
          || array_to_string(v_short, '; ') || '. Restore each measure that fell before the next weekly verdict.',
        jsonb_build_object('week', v_week, 'stage1', v_s1, 'stage2', v_s2, 'from', v_prev, 'to', v_level));
      n_fell := n_fell + 1;
    end if;

    insert into public.seat_senior_verdict (week, seat, stage1, stage2, level, shortfalls, improvement_id, measured_at)
    values (v_week, s.role_id, v_s1, v_s2, v_level, v_short, v_id, now())
    on conflict (week, seat) do update set stage1 = excluded.stage1, stage2 = excluded.stage2, level = excluded.level,
      shortfalls = excluded.shortfalls, improvement_id = coalesce(public.seat_senior_verdict.improvement_id, excluded.improvement_id),
      measured_at = excluded.measured_at;
    v_levels := v_levels || jsonb_build_object(s.role_id, v_level);
  end loop;
  return jsonb_build_object('week', v_week, 'seats', n_seats, 'levels', v_levels, 'fell', n_fell);
end $fn$;

revoke execute on function public.fn_ceo_seat_senior_verdict(timestamptz) from public, anon, authenticated;

create or replace function public.fn_ceo_seat_senior_verdict_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_seat_senior_verdict(now()) $fn$;

revoke execute on function public.fn_ceo_seat_senior_verdict_now() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.senior_verdict', 'ceo', interval '7 days', 'fn_ceo_seat_senior_verdict_now',
   'Ledger 1003: every seat measured weekly against its senior standard in two stages (the judged exam and graded judgements; contributions live, duties on clock, handoffs in time); the level is junior, mid or senior only on that evidence, and a level that falls gets one CEO improvement.',
   'scripts/sql/the_ceo_measures_every_seat_against_its_senior_standard_every_week.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
