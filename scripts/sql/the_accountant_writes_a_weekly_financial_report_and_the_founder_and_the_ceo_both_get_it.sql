-- THE ACCOUNTANT WRITES A WEEKLY FINANCIAL REPORT, AND THE FOUNDER AND THE CEO BOTH GET IT.
--
-- The founder, 9 Sep 2026: the accountant agent must "create weekly report as pdf and share it with
-- me and the CEO". This is the accountant seat's ONE founder-facing subscription and it exists
-- because he asked for it by name. It is INFORMATIONAL: it opens no queue he must action, carries no
-- approval request, and is not an alert lane.
--
-- ---------------------------------------------------------------------------------------------
-- THE HARD PART IS HONESTY, NOT ARITHMETIC.
-- ---------------------------------------------------------------------------------------------
-- Every figure this report prints carries a BASIS, and there are exactly three:
--
--   'true zero' -- the source table holds no rows AT ALL, so the window count is zero over a zero
--                  denominator. Printed with the denominator, so a reader can tell an empty window
--                  from an empty table.
--   'measured'  -- the source table holds rows and the figure was computed over them.
--   'unknown'   -- no record or decision exists from which the figure could be derived. Printed as
--                  the word UNKNOWN with the reason. NEVER as 0.
--
-- That is the accountant grant's own text (ceo_standing_grant 'accountant.reporting' /
-- 'accountant.bookkeeping'): "Every figure must bind to a source row. An unmeasurable figure is
-- reported as unknown, never estimated and never defaulted to zero."
--
-- The CEO digest had to fix exactly this defect twice on 9 Sep: it printed "0 pending, 0 rejected"
-- for supplier verification when the truth was that no verification decision had ever been recorded,
-- and it printed a percentage off a zero denominator. Neither is repeated here.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT WAS MEASURED FIRST, 9 Sep 2026 on htdblwldjkcgjvmqkbeh. Every number read, none assumed.
-- ---------------------------------------------------------------------------------------------
--   transactions        0 rows   reveal fees: the revenue side has no row to sum
--   stripe_events       0 rows   AND max(last_seen_at) is null -- no Stripe event has EVER been
--                                recorded, so "0 events this week" is not evidence the webhook is
--                                live. The report says so rather than implying a quiet week.
--   expense_entries     0 rows   nothing has ever been filed to the ledger
--   inbound_messages    4 rows, ALL FOUR addressed to expenses@mail.quotesdone.com:
--                                  15 Aug  Fw: Your receipt from Resend #2675-9504
--                                  27 Aug  Fw: Payment received for Supabase Pte. Ltd. invoice
--                                  29 Aug  Fw: Your receipt from Vercel Inc. #2265-1365
--                                  03 Sep  Fw: Apify invoice #202609032256 payment successful
--                                THIS IS THE WHOLE REASON MONEY-OUT IS 'unknown' AND NOT ZERO.
--                                Four receipts arrived and none reached the ledger. A report that
--                                printed "expenses AED 0.00" would be false, and would be false in
--                                the direction that flatters the company.
--   expenses            0 rows   no recurring cost is on record either, while the inbox proves the
--                                company pays Resend, Supabase, Vercel and Apify
--   ap_bills            0 rows   refunds 0 rows   gl_journal 0   gl_journal_lines 0
--   gl_accounts        30 rows   gl_expense_map 6 -- the chart of accounts is built and unused
--   ai_cost_log        11 rows   every one model_used='none', cost_aed 0 (the paid gate denies
--                                globally). A real denominator with a real zero on it.
--   founder_mail_policy          NO kind for a financial report exists. 'cfo_report' and
--                                'period_report' are allowed_to_email but owned by cfo and
--                                chief_of_staff -- roles deleted 7 Sep. A new kind is registered
--                                below rather than borrowing a dead role's lane.
--   internal_credential          fn.resilience_ping scope = {send_outbox, alert_founder,
--                                dropbox_backup}. NOT pdf_native. Widened below, or the PDF call
--                                would have returned 403 with nothing saying why.
--   cron.job            1 row, inactive. pg_cron is dead by founder instruction; no job registered.
--
-- ---------------------------------------------------------------------------------------------
-- WHY A FINANCIAL REPORT IS EVIDENCE-CLASS, AND WHAT THAT COSTS.
-- ---------------------------------------------------------------------------------------------
-- pdf_native defaults strict_glyphs to (sign or stamp), so a report would degrade gracefully: a
-- character its fonts cannot render is dropped and the document still returns ok:true. That rule is
-- right for a customer's quotation comparison, where losing an Arabic line beats losing the report.
-- It is wrong here. This document is the founder's and the CEO's only statement of what the company
-- earned and spent; a dropped character inside a figure or a currency changes a number's meaning and
-- NOBODY re-reads it against a source. So the caller passes options.strict_glyphs = true and
-- pdf_native returns 502 rather than a PDF with a hole in a money line.
-- The cost is a failed generation, and that cost is contained: the row is retained with the reason
-- in pdf_error and the next 15-minute tick retries. A refusal delays a report; a hole falsifies one.
--
-- ---------------------------------------------------------------------------------------------
-- THE TWO RECIPIENTS, AND HOW EACH RESOLVES.
-- ---------------------------------------------------------------------------------------------
--   THE FOUNDER  app_secrets.admin_emails, first comma-separated value. That is the key the
--                notifications BEFORE INSERT gate (fn_notifications_founder_mail_policy) itself
--                matches on, so a row addressed from any other key would not be RECOGNISED as
--                founder mail by the gate meant to govern it. app_secrets.founder_email exists and
--                is read by nothing in the database; it is not read here either. The address is
--                never printed -- not in the body, not in figures, not in a return value.
--   THE CEO      public.support_ceo_report, the contract table the CEO seat already reads from its
--                direct reports (fn_support_report_to_ceo writes it; fn_ceo_accept_support_report
--                reads it). No new channel is invented. The parent is READ from
--                org_reporting_edge for 'accountant' and required to be an ACTIVE role -- if the
--                edge is gone this REFUSES rather than picking someone, exactly as
--                fn_support_report_to_ceo does. requested_outcome is honest: nothing is requested.
--
-- ---------------------------------------------------------------------------------------------
-- THE IDEMPOTENCY KEY, AND THE TRAP IT AVOIDS.
-- ---------------------------------------------------------------------------------------------
-- report_key = 'quotesdone:' || ISO year-week, e.g. 'quotesdone:2026-W36'. UNIQUE, and looked up
-- UNCONDITIONALLY -- never `and status in (...)`. fn_agent_action_work_sweep guards its unique
-- idempotency_key with `not exists (... and status in ('queued','running','succeeded'))`, so a
-- previously FAILED row occupies the key without satisfying the guard and the routine deadlocks on
-- the unique violation after two attempts; the '#2' suffix in that table is the scar. Here a row in
-- ANY state is found and returned, and a correction bumps the explicit `revision` column instead of
-- minting a second key.
--
-- ---------------------------------------------------------------------------------------------
-- DELIVERY FAILURE MUST NOT BLOCK ANYTHING.
-- ---------------------------------------------------------------------------------------------
-- Generation, PDF, founder submission and CEO submission are FOUR separate states with their own
-- timestamps. Every delivery step is inside its own exception block and none of them can raise into
-- the caller. A report with no PDF, no recipient, or a gate refusal is still GENERATED, RETAINED and
-- visible as such, delivery_attempts counts the tries, last_delivery_error carries the reason, and
-- the next tick retries. The watchdog that calls this must never go down because an email did not.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_writes_a_weekly_financial_report_and_the_founder_and_the_ceo_both_get_it.sql --apply --ddl

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE TABLE. One row per company per ISO week, forever. Shape copied from ceo_daily_digest.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.accountant_weekly_report (
  id                 bigserial primary key,
  company_key        text        not null default 'quotesdone',
  iso_year           int         not null,
  iso_week           int         not null,
  week_start         date        not null,          -- Monday, Asia/Dubai
  week_end           date        not null,          -- Sunday, Asia/Dubai
  local_timezone     text        not null default 'Asia/Dubai',
  -- company_key || ':' || IYYY-"W"IW. UNIQUE, and looked up unfiltered.
  report_key         text        not null,
  -- Corrections bump this. They never mint a second key.
  revision           int         not null default 1,
  revision_note      text,
  subject            text,
  body               text,
  -- Every line item, its value, its BASIS and the source rows it binds to.
  figures            jsonb       not null default '{}'::jsonb,
  -- The pdf_native block list, stored so a retry re-renders rather than re-measures.
  pdf_blocks         jsonb,
  pdf_bucket         text,
  pdf_path           text,
  pdf_url            text,
  pdf_bytes          int,
  pdf_generated_at   timestamptz,
  pdf_error          text,
  -- generation / pdf / founder submission / CEO submission are SEPARATE, not one status.
  status             text        not null default 'generated',
  generated_at       timestamptz not null default now(),
  founder_submitted_at timestamptz,
  ceo_submitted_at   timestamptz,
  delivered_at       timestamptz,                   -- both lanes in
  notification_id    bigint,                        -- the founder's row in notifications
  ceo_report_id      bigint,                        -- the CEO's row in support_ceo_report
  delivery_attempts  int         not null default 0,
  last_delivery_error text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint accountant_weekly_report_key_uniq unique (report_key),
  constraint accountant_weekly_report_status_ck
    check (status in ('generated','pdf_failed','partial','delivered','delivery_failed')),
  constraint accountant_weekly_report_week_ck check (week_end > week_start)
);

comment on table public.accountant_weekly_report is
  'The accountant''s weekly financial report, requested by the founder on 9 Sep 2026: "create weekly report as pdf and share it with me and the CEO". One row per company per ISO week (report_key is UNIQUE and looked up unfiltered); corrections bump revision. generated_at / pdf_generated_at / founder_submitted_at / ceo_submitted_at keep generation, rendering and each delivery lane apart, so a report that exists but never reached a recipient is visible as exactly that. Informational: it opens no queue the founder must action.';

comment on column public.accountant_weekly_report.figures is
  'Every line item as {aed|n, basis, note, denom}. basis is one of ''true zero'' (the source table holds no rows at all), ''measured'' (computed over rows that exist) or ''unknown'' (no record exists from which the figure could be derived -- never rendered as 0).';

create index if not exists accountant_weekly_report_week_idx
  on public.accountant_weekly_report (week_start desc);
create index if not exists accountant_weekly_report_undelivered_idx
  on public.accountant_weekly_report (week_start desc) where delivered_at is null;

alter table public.accountant_weekly_report enable row level security;
-- No policy, deliberately: written by SECURITY DEFINER routines, read by the service role. RLS on
-- with zero policies denies every anon/authenticated read, which is the intent.

-- ---------------------------------------------------------------------------------------------
-- 2. THE FOUNDER-MAIL KIND. Without this row the notifications insert returns NULL and vanishes
--    with no error -- fn_notifications_founder_mail_policy's `return null` is a refusal, not a
--    failure, so nothing would ever have said the report was not sent.
--
--    A NEW kind rather than borrowing 'cfo_report' or 'period_report': both are allowed_to_email
--    but owned by cfo / chief_of_staff, roles deleted on 7 Sep 2026. Owning a lane with a dead role
--    is how the founder_brief row came to be lying about its owner.
-- ---------------------------------------------------------------------------------------------
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('accountant_weekly_report', true,
        'The founder asked for this by name on 9 Sep 2026: the accountant must "create weekly report as pdf and share it with me and the CEO". Informational only -- it carries no approval request and opens no queue he must action.',
        'accountant')
on conflict (kind) do update
  set allowed_to_email = excluded.allowed_to_email,
      reason = excluded.reason,
      owner_role = excluded.owner_role,
      updated_at = now();

-- ---------------------------------------------------------------------------------------------
-- 3. THE SCHEDULE. Monday 09:00 Asia/Dubai for the week that closed the previous Sunday.
--    A local wall clock and a local weekday, converted by Postgres against the named zone, because
--    Postgres knows what Asia/Dubai means and a cron string does not.
-- ---------------------------------------------------------------------------------------------
insert into public.app_secrets(key, value)
values ('accountant_weekly_report_local_time', '09:00')
on conflict (key) do nothing;
insert into public.app_secrets(key, value)
values ('accountant_weekly_report_local_dow', '1')   -- ISO day of week: 1 = Monday
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. THE CREDENTIAL SCOPE. resilience_ping renders the PDF, and fn.resilience_ping's scope was
--    {send_outbox, alert_founder, dropbox_backup}. pdf_native would have refused it with a bare 403
--    and the report would have been retried forever with 'store_failed' nowhere in sight. Widened
--    by ONE slug; nothing else about the credential changes.
-- ---------------------------------------------------------------------------------------------
update public.internal_credential
   set scope = scope || array['pdf_native']
 where context = 'fn.resilience_ping'
   and active
   and not ('pdf_native' = any(scope));

commit;

-- ---------------------------------------------------------------------------------------------
-- 5. THE MEASUREMENT. Every line item for one window, with its basis.
--
--    Separated from the report body because week-over-week movement needs the SAME arithmetic run
--    over the previous week, and two copies of a money calculation is how two answers happen.
--
--    THE BASIS RULE, applied identically to every line:
--      denom = 0  -> 'true zero'  (the table holds no rows at all; say so with the denominator)
--      denom > 0  -> 'measured'
--      no derivable record at all -> 'unknown', and the value key is omitted entirely so a
--                                    caller cannot accidentally render it as 0.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_accountant_weekly_report_figures(
  p_start date,
  p_end   date
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fig$
declare
  v_tz text := 'Asia/Dubai';
  v_from timestamptz := (p_start::timestamp) at time zone v_tz;
  v_to   timestamptz := ((p_end + 1)::timestamp) at time zone v_tz;
  -- revenue
  v_txn_all int; v_txn_n int; v_rev numeric;
  v_stripe_all int; v_stripe_n int; v_stripe_last timestamptz;
  -- expenses
  v_ee_all int; v_ee_n int; v_ee_aed numeric;
  v_rcpt_all int; v_rcpt_n int;
  v_exp_all int; v_exp_active int;
  -- refunds
  v_ref_all int; v_ref_n int; v_ref_aed numeric; v_ref_settled int;
  -- payables
  v_ap_all int; v_ap_open int; v_ap_due numeric;
  -- ledger
  v_gl_all int; v_gl_lines int; v_gl_n int; v_dr numeric; v_cr numeric;
  v_cash numeric;
  -- platform cost
  v_ai_all int; v_ai_n int; v_ai_aed numeric; v_ai_models text;
  v_lines jsonb;
begin
  select count(*) into v_txn_all from transactions;
  select count(*), coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0)
    into v_txn_n, v_rev
    from transactions
   where revealed_at >= v_from and revealed_at < v_to
     and coalesce(fee_status,'') <> 'refunded' and coalesce(refund_status,'') <> 'approved';

  select count(*), max(last_seen_at) into v_stripe_all, v_stripe_last from stripe_events;
  select count(*) into v_stripe_n from stripe_events
   where first_seen_at >= v_from and first_seen_at < v_to;

  select count(*) into v_ee_all from expense_entries;
  select count(*), coalesce(sum(amount), 0) into v_ee_n, v_ee_aed
    from expense_entries where charged_on between p_start and p_end;

  -- The receipts that ARRIVED. This is the counter-evidence to a zero on the line above, and it is
  -- why money-out can be 'unknown' rather than a comfortable 0.
  select count(*) into v_rcpt_all from inbound_messages where coalesce(to_email,'') ilike '%expense%';
  select count(*) into v_rcpt_n from inbound_messages
   where coalesce(to_email,'') ilike '%expense%' and created_at >= v_from and created_at < v_to;

  select count(*), count(*) filter (where active) into v_exp_all, v_exp_active from expenses;

  select count(*) into v_ref_all from refunds;
  select count(*), coalesce(sum(amount_fils), 0) / 100.0, count(*) filter (where settled_at is not null)
    into v_ref_n, v_ref_aed, v_ref_settled
    from refunds where requested_at >= v_from and requested_at < v_to;

  select count(*) into v_ap_all from ap_bills;
  select count(*), coalesce(sum(greatest(total - coalesce(amount_paid,0), 0)), 0)
    into v_ap_open, v_ap_due
    from ap_bills where coalesce(status,'') not in ('paid','void','cancelled');

  select count(*) into v_gl_all from gl_journal;
  select count(*) into v_gl_lines from gl_journal_lines;
  select count(*) into v_gl_n from gl_journal where entry_date between p_start and p_end;
  select coalesce(sum(l.debit),0), coalesce(sum(l.credit),0) into v_dr, v_cr
    from gl_journal_lines l join gl_journal j on j.id = l.journal_id
   where j.entry_date between p_start and p_end;
  select coalesce(sum(balance),0) into v_cash from gl_account_balances where code in ('1000','1050');

  select count(*) into v_ai_all from ai_cost_log;
  select count(*), coalesce(sum(cost_aed),0), coalesce(string_agg(distinct coalesce(model_used,'?'), ', '), '')
    into v_ai_n, v_ai_aed, v_ai_models
    from ai_cost_log where occurred_at >= v_from and occurred_at < v_to;

  v_lines := jsonb_build_object(

    -- MONEY IN -------------------------------------------------------------------------------
    'reveal_fee_revenue', jsonb_build_object(
      'aed', v_rev, 'n', v_txn_n, 'denom', v_txn_all,
      'basis', case when v_txn_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_txn_all = 0
        then 'public.transactions holds 0 rows in total, so no reveal fee has been recorded for this week or any other. The denominator is zero, not the numerator only.'
        else v_txn_n||' reveal(s) settled in the window, of '||v_txn_all||' transaction row(s) on record; refunded and refund-approved rows excluded.' end),

    'stripe_settlement_events', jsonb_build_object(
      'n', v_stripe_n, 'denom', v_stripe_all,
      'basis', case when v_stripe_all = 0 then 'true zero' else 'measured' end,
      -- ZERO CANNOT TELL A DEAD FEED FROM AN IDLE ONE. Say which this is.
      'note', case when v_stripe_all = 0
        then 'public.stripe_events holds 0 rows and has never recorded one, so 0 events this week is NOT evidence that the Stripe webhook is live and the week was quiet. It is equally consistent with the feed never having delivered. Treat the revenue line above as bounded by that.'
        else v_stripe_n||' event(s) first seen in the window, of '||v_stripe_all||' ever recorded; most recent activity '||coalesce(v_stripe_last::text,'unknown')||'.' end),

    -- MONEY OUT ------------------------------------------------------------------------------
    'expenses_filed_to_ledger', jsonb_build_object(
      'aed', v_ee_aed, 'n', v_ee_n, 'denom', v_ee_all,
      'basis', case when v_ee_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ee_all = 0
        then 'public.expense_entries holds 0 rows in total. Nothing has ever been filed against the chart of accounts. This is a statement about the bookkeeping, not about the spending.'
        else v_ee_n||' receipt(s) filed with a charge date in the window, of '||v_ee_all||' entr(ies) on record.' end),

    'receipts_received_at_the_expenses_inbox', jsonb_build_object(
      'n', v_rcpt_n, 'denom', v_rcpt_all,
      'basis', case when v_rcpt_all = 0 then 'true zero' else 'measured' end,
      'note', v_rcpt_n||' message(s) reached the expenses inbox inside the window; '||v_rcpt_all||' have reached it in total. Counted from public.inbound_messages, which records arrival, not amount.'),

    -- THE HONEST ONE. If receipts arrived and none was filed, the amount spent is NOT derivable,
    -- and printing 0 would be false in the direction that flatters the company.
    'cash_out_this_week', case
      when v_rcpt_n > v_ee_n then jsonb_build_object(
        'basis', 'unknown',
        'note', v_rcpt_n||' receipt(s) arrived at the expenses inbox inside this window and '||v_ee_n||
                ' were filed to the ledger, so the amount actually spent cannot be derived from any row. '||
                'It is UNKNOWN. It is not zero, and the gap ('||(v_rcpt_n - v_ee_n)||' unfiled receipt(s)) is the reason.')
      when v_ee_all = 0 and v_rcpt_all > 0 then jsonb_build_object(
        'basis', 'unknown',
        'note', 'No receipt has ever been filed to the ledger while '||v_rcpt_all||' have arrived at the expenses inbox. '||
                'Spending for this window is UNKNOWN; a zero here would assert the company spent nothing, which the inbox contradicts.')
      when v_ee_all = 0 and v_rcpt_all = 0 then jsonb_build_object(
        'aed', 0, 'basis', 'true zero',
        'note', 'Both public.expense_entries and the expenses inbox hold 0 rows, so nothing was spent as far as any source row can say, over a denominator of zero.')
      else jsonb_build_object(
        'aed', v_ee_aed, 'n', v_ee_n, 'denom', v_ee_all, 'basis', 'measured',
        'note', 'Every receipt that arrived in the window ('||v_rcpt_n||') has a filed entry; the total is the sum of those entries.') end,

    'recurring_cost_schedule', case
      when v_exp_all = 0 and v_rcpt_all > 0 then jsonb_build_object(
        'basis', 'unknown',
        'note', 'public.expenses holds 0 rows, so no recurring cost is on record -- while the expenses inbox holds '||v_rcpt_all||
                ' vendor receipt(s), which is direct evidence that recurring costs exist. The monthly run rate is UNKNOWN, not zero.')
      when v_exp_all = 0 then jsonb_build_object(
        'n', 0, 'denom', 0, 'basis', 'true zero',
        'note', 'public.expenses holds 0 rows and no receipt has arrived to contradict that.')
      else jsonb_build_object(
        'n', v_exp_active, 'denom', v_exp_all, 'basis', 'measured',
        'note', v_exp_active||' active recurring cost(s) of '||v_exp_all||' on record.') end,

    -- REFUNDS --------------------------------------------------------------------------------
    'refunds_requested', jsonb_build_object(
      'aed', v_ref_aed, 'n', v_ref_n, 'denom', v_ref_all, 'settled', v_ref_settled,
      'basis', case when v_ref_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ref_all = 0
        then 'public.refunds holds 0 rows in total. No refund has ever been requested, so nothing was decided and nothing was declined -- this is an empty table, not a clean queue.'
        else v_ref_n||' requested in the window ('||v_ref_settled||' settled), of '||v_ref_all||' on record. Every refund decision belongs to the CEO (ceo_standing_grant accountant.refund_decision, max_amount_aed 0).' end),

    -- PAYABLES -------------------------------------------------------------------------------
    'outstanding_bills', jsonb_build_object(
      'aed', v_ap_due, 'n', v_ap_open, 'denom', v_ap_all,
      'basis', case when v_ap_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ap_all = 0
        then 'public.ap_bills holds 0 rows, so 0 outstanding means NO BILL HAS BEEN ENTERED -- it is not a statement that nothing is owed. The '||v_rcpt_all||' receipt(s) in the expenses inbox are evidence to the contrary.'
        else v_ap_open||' open bill(s) of '||v_ap_all||' on record, '||to_char(v_ap_due,'FM999,999,990.00')||' AED still due.' end),

    -- CASH -----------------------------------------------------------------------------------
    'cash_position', case
      when v_gl_lines = 0 then jsonb_build_object(
        'basis', 'unknown',
        'note', 'The general ledger holds 0 posted lines, and the database carries no bank feed or statement balance. The 1000 Cash & Bank and 1050 Stripe Clearing accounts therefore read 0.00 because NOTHING HAS BEEN POSTED, which is the absence of bookkeeping and not a bank balance. Cash position is UNKNOWN.')
      else jsonb_build_object(
        'aed', v_cash, 'denom', v_gl_lines, 'basis', 'measured',
        'note', 'Sum of the 1000 Cash & Bank and 1050 Stripe Clearing balances across '||v_gl_lines||' posted ledger line(s). It is a book balance, not a confirmed bank statement.') end,

    -- LEDGER ---------------------------------------------------------------------------------
    'journal_entries_posted', jsonb_build_object(
      'n', v_gl_n, 'denom', v_gl_all, 'debits', v_dr, 'credits', v_cr,
      'basis', case when v_gl_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_gl_all = 0
        then 'public.gl_journal holds 0 entries. Debits 0.00 equal credits 0.00, and a trial balance that balances across ZERO entries proves nothing about the books -- it proves there are none. 30 accounts and 6 expense mappings are configured and unused.'
        else v_gl_n||' entr(ies) dated inside the window, of '||v_gl_all||' on record; debits '||to_char(v_dr,'FM999,999,990.00')||' against credits '||to_char(v_cr,'FM999,999,990.00')||
             case when v_dr = v_cr then ' -- balanced.' else ' -- OUT OF BALANCE by '||to_char(abs(v_dr-v_cr),'FM999,999,990.00')||'.' end end),

    -- PLATFORM COST --------------------------------------------------------------------------
    'ai_and_model_cost', jsonb_build_object(
      'aed', v_ai_aed, 'n', v_ai_n, 'denom', v_ai_all, 'models', v_ai_models,
      'basis', case when v_ai_all = 0 then 'true zero' else 'measured' end,
      'note', case when v_ai_all = 0
        then 'public.ai_cost_log holds 0 rows.'
        else v_ai_n||' model call(s) inside the window, of '||v_ai_all||' logged in total, costing '||to_char(v_ai_aed,'FM999,999,990.00')||
             ' AED. Models used: '||coalesce(nullif(v_ai_models,''),'none in this window')||
             case when v_ai_models = 'none' then '. Every logged call resolved to model_used=''none'', so this zero is a real measured zero: the paid route was refused, not that the work was free.' else '.' end end)
  );

  return jsonb_build_object(
    'window', jsonb_build_object('start', p_start, 'end', p_end, 'timezone', v_tz,
                                 'iso', to_char(p_start,'IYYY-"W"IW')),
    'lines', v_lines,
    'measured_at', now());
end;$fig$;

revoke execute on function public.fn_accountant_weekly_report_figures(date, date) from public;

comment on function public.fn_accountant_weekly_report_figures(date, date) is
  'Measures every line item of the weekly financial report for one Asia/Dubai window and labels each with its basis: ''true zero'' (source table holds no rows at all, denominator stated), ''measured'' (computed over rows that exist) or ''unknown'' (no record exists from which it could be derived -- the value key is omitted so it cannot be rendered as 0). Called twice per report: once for the week and once for the week before it.';

-- ---------------------------------------------------------------------------------------------
-- 6. THE REPORT. Generate once per ISO week, or bump a revision in place.
--
--    It does NOT deliver. The founder asked for the report AS A PDF, so a submission before the PDF
--    exists would mail him a report with nothing attached and mark the week done. Generation ends
--    with the blocks pdf_native needs; the caller renders, calls attach_pdf, and delivery follows
--    from there.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_accountant_weekly_report(
  p_week_start    date default null,
  p_revise        boolean default false,
  p_revision_note text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $awr$
declare
  v_tz      text := 'Asia/Dubai';
  v_company text := 'quotesdone';
  v_start   date;
  v_end     date;
  v_key     text;
  v_row     public.accountant_weekly_report%rowtype;
  v_now     jsonb;
  v_prev    jsonb;
  v_subject text;
  v_body    text;
  v_blocks  jsonb;
  v_rows    jsonb := '[]'::jsonb;
  v_k       text;
  v_ln      jsonb;
  v_pn      jsonb;
  v_val     text;
  v_mov     text;
  v_unknown int := 0;
  v_truezero int := 0;
  v_measured int := 0;
  -- The line order the report prints in. Insertion order of a jsonb object is not preserved, so it
  -- is stated here rather than discovered.
  v_order text[] := array[
    'reveal_fee_revenue','stripe_settlement_events',
    'expenses_filed_to_ledger','receipts_received_at_the_expenses_inbox','cash_out_this_week',
    'recurring_cost_schedule','refunds_requested','outstanding_bills','cash_position',
    'journal_entries_posted','ai_and_model_cost'];
  v_label jsonb := jsonb_build_object(
    'reveal_fee_revenue','Revenue - reveal fees (Stripe in)',
    'stripe_settlement_events','Stripe settlement events seen',
    'expenses_filed_to_ledger','Expenses filed to the ledger',
    'receipts_received_at_the_expenses_inbox','Receipts received at the expenses inbox',
    'cash_out_this_week','Cash out this week',
    'recurring_cost_schedule','Recurring cost schedule',
    'refunds_requested','Refunds requested',
    'outstanding_bills','Outstanding bills (accounts payable)',
    'cash_position','Cash position',
    'journal_entries_posted','Journal entries posted',
    'ai_and_model_cost','AI and model cost');
begin
  -- Default: the week that CLOSED. Never the week in progress -- a partial week reported as a week
  -- is a figure that will be wrong by Sunday and nobody will go back and correct it.
  v_start := coalesce(p_week_start,
                      (date_trunc('week', (now() at time zone v_tz)::date) - interval '7 days')::date);
  v_start := date_trunc('week', v_start::timestamp)::date;   -- normalise to the Monday
  v_end   := v_start + 6;
  v_key   := v_company||':'||to_char(v_start,'IYYY-"W"IW');

  -- UNFILTERED. Never `and status in (...)`.
  select * into v_row from public.accountant_weekly_report where report_key = v_key;

  if found and not p_revise then
    return jsonb_build_object(
      'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
      'status', v_row.status, 'generated', false, 'reason', 'already generated for this ISO week',
      'week_start', v_row.week_start, 'week_end', v_row.week_end,
      'pdf_pending', v_row.pdf_path is null,
      'pdf_blocks', case when v_row.pdf_path is null then v_row.pdf_blocks else null end,
      'subject', v_row.subject,
      'delivered', v_row.delivered_at is not null,
      'delivery_attempts', v_row.delivery_attempts);
  end if;

  v_now  := public.fn_accountant_weekly_report_figures(v_start, v_end);
  v_prev := public.fn_accountant_weekly_report_figures(v_start - 7, v_end - 7);

  -- BUILD THE TABLE. One row per line item: what it is, what it says, on what basis, and how it
  -- moved. A line whose basis is 'unknown' prints the word and never a number.
  foreach v_k in array v_order loop
    v_ln := v_now->'lines'->v_k;
    v_pn := v_prev->'lines'->v_k;
    if v_ln is null then continue; end if;

    if (v_ln->>'basis') = 'unknown' then
      v_val := 'UNKNOWN';
      v_unknown := v_unknown + 1;
    elsif v_ln ? 'aed' then
      v_val := 'AED '||to_char((v_ln->>'aed')::numeric, 'FM999,999,990.00')
               || case when v_ln ? 'n' then ' ('||(v_ln->>'n')||')' else '' end;
    else
      v_val := coalesce(v_ln->>'n', '-');
    end if;
    if (v_ln->>'basis') = 'true zero' then v_truezero := v_truezero + 1;
    elsif (v_ln->>'basis') = 'measured' then v_measured := v_measured + 1; end if;

    -- WEEK-OVER-WEEK. A movement is only stated when BOTH weeks carry a comparable number.
    if v_pn is null or (v_pn->>'basis') = 'unknown' or (v_ln->>'basis') = 'unknown' then
      v_mov := 'not comparable';
    elsif v_ln ? 'aed' and v_pn ? 'aed' then
      v_mov := case when (v_ln->>'aed')::numeric - (v_pn->>'aed')::numeric >= 0 then '+' else '' end
               || to_char((v_ln->>'aed')::numeric - (v_pn->>'aed')::numeric, 'FM999,999,990.00');
    elsif v_ln ? 'n' and v_pn ? 'n' then
      v_mov := case when (v_ln->>'n')::int - (v_pn->>'n')::int >= 0 then '+' else '' end
               || ((v_ln->>'n')::int - (v_pn->>'n')::int)::text;
    else
      v_mov := 'not comparable';
    end if;

    v_rows := v_rows || jsonb_build_array(jsonb_build_array(
      coalesce(v_label->>v_k, v_k), v_val, upper(coalesce(v_ln->>'basis','?')), v_mov));
  end loop;

  v_subject := 'QuotesDone weekly financial report - '||to_char(v_start,'IYYY-"W"IW')
               ||' ('||to_char(v_start,'DD Mon')||' to '||to_char(v_end,'DD Mon YYYY')||')';

  v_body :=
    'WEEKLY FINANCIAL REPORT'||E'\n'||
    to_char(v_start,'Dy DD Mon YYYY')||' to '||to_char(v_end,'Dy DD Mon YYYY')||' (Asia/Dubai) - ISO '||to_char(v_start,'IYYY-"W"IW')||E'\n'||
    'Prepared by the accountant seat. Informational: nothing here asks you for a decision.'||E'\n\n'||
    'HOW TO READ THE BASIS COLUMN'||E'\n'||
    '- MEASURED   the figure was computed over source rows that exist.'||E'\n'||
    '- TRUE ZERO  the source table holds no rows at all, so the figure is zero over a zero denominator.'||E'\n'||
    '- UNKNOWN    no record exists from which the figure could be derived. It is NOT zero.'||E'\n\n';

  foreach v_k in array v_order loop
    v_ln := v_now->'lines'->v_k;
    if v_ln is null then continue; end if;
    v_body := v_body || upper(coalesce(v_label->>v_k, v_k))||E'\n'||
      '  '||case when (v_ln->>'basis') = 'unknown' then 'UNKNOWN'
                 when v_ln ? 'aed' then 'AED '||to_char((v_ln->>'aed')::numeric,'FM999,999,990.00')
                 else coalesce(v_ln->>'n','-') end||
      '   ['||upper(v_ln->>'basis')||']'||E'\n'||
      '  '||coalesce(v_ln->>'note','')||E'\n\n';
  end loop;

  v_body := v_body ||
    'RECONCILIATION OF THE TWO CASHFLOW SOURCES'||E'\n'||
    'The founder named two, and only two: Stripe in, the expenses mailbox out. Against the ledger:'||E'\n'||
    '- Stripe in:  '||coalesce(v_now->'lines'->'stripe_settlement_events'->>'note','')||E'\n'||
    '- Mailbox out: '||coalesce(v_now->'lines'->'cash_out_this_week'->>'note','')||E'\n'||
    '- Ledger:     '||coalesce(v_now->'lines'->'journal_entries_posted'->>'note','')||E'\n\n'||
    'BASIS SUMMARY: '||v_measured||' measured, '||v_truezero||' true zero, '||v_unknown||' unknown, of '||
      (v_measured + v_truezero + v_unknown)||' line item(s).'||E'\n'||
    case when v_unknown > 0
      then 'An unknown is not a gap in this report. It is the report refusing to publish a number it cannot bind to a source row.'
      else 'Every line item on this report binds to a source row.' end;

  -- THE PDF BLOCKS. pdf_native's own block vocabulary; letterhead on, strict glyphs on.
  v_blocks := jsonb_build_array(
    jsonb_build_object('t','h2','text','Weekly financial report'),
    jsonb_build_object('t','p','text', to_char(v_start,'Dy DD Mon YYYY')||' to '||to_char(v_end,'Dy DD Mon YYYY')||
                                       '  (Asia/Dubai)   ISO '||to_char(v_start,'IYYY-"W"IW')||'   Revision '||
                                       coalesce(v_row.revision + 1, 1)::text),
    jsonb_build_object('t','note','text','Prepared by the accountant seat and reported to the CEO. Informational: nothing in this document asks for a decision or an approval.'),
    jsonb_build_object('t','space','h',6),
    jsonb_build_object('t','h3','text','Position'),
    jsonb_build_object('t','table',
      'head', jsonb_build_array('Line item','This week','Basis','vs prior week'),
      'rows', v_rows,
      'widths', jsonb_build_array(0.42, 0.24, 0.16, 0.18)),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','What the basis column means'),
    jsonb_build_object('t','li','text','MEASURED - computed over source rows that exist.'),
    jsonb_build_object('t','li','text','TRUE ZERO - the source table holds no rows at all; the figure is zero over a zero denominator.'),
    jsonb_build_object('t','li','text','UNKNOWN - no record exists from which the figure could be derived. It is not zero, and it is not an omission.'),
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','Every figure, and the rows it binds to'));

  foreach v_k in array v_order loop
    v_ln := v_now->'lines'->v_k;
    if v_ln is null then continue; end if;
    v_blocks := v_blocks || jsonb_build_array(
      jsonb_build_object('t','p','bold',true,'text', coalesce(v_label->>v_k, v_k)||
        ' - '||case when (v_ln->>'basis') = 'unknown' then 'UNKNOWN'
                    when v_ln ? 'aed' then 'AED '||to_char((v_ln->>'aed')::numeric,'FM999,999,990.00')
                    else coalesce(v_ln->>'n','-') end||'  ['||upper(v_ln->>'basis')||']'),
      jsonb_build_object('t','note','text', coalesce(v_ln->>'note','')));
  end loop;

  v_blocks := v_blocks || jsonb_build_array(
    jsonb_build_object('t','space','h',8),
    jsonb_build_object('t','h3','text','Reconciliation of the two cashflow sources'),
    jsonb_build_object('t','p','text','The founder named two, and only two: Stripe in, the expenses mailbox out. Reconciled against the general ledger, this week reads as follows.'),
    jsonb_build_object('t','li','text','Stripe in - '||coalesce(v_now->'lines'->'stripe_settlement_events'->>'note','')),
    jsonb_build_object('t','li','text','Mailbox out - '||coalesce(v_now->'lines'->'cash_out_this_week'->>'note','')),
    jsonb_build_object('t','li','text','Ledger - '||coalesce(v_now->'lines'->'journal_entries_posted'->>'note','')),
    jsonb_build_object('t','space','h',6),
    jsonb_build_object('t','p','bold',true,'text','Basis summary: '||v_measured||' measured, '||v_truezero||
      ' true zero, '||v_unknown||' unknown, of '||(v_measured+v_truezero+v_unknown)||' line items.'),
    jsonb_build_object('t','note','text', case when v_unknown > 0
      then 'An unknown is not a gap in this report. It is the report refusing to publish a number it cannot bind to a source row.'
      else 'Every line item on this report binds to a source row.' end));

  if p_revise and v_row.id is not null then
    update public.accountant_weekly_report
       set revision = revision + 1, revision_note = p_revision_note,
           subject = v_subject, body = v_body,
           figures = jsonb_build_object('this_week', v_now, 'prior_week', v_prev,
                                        'basis_counts', jsonb_build_object('measured', v_measured,
                                          'true_zero', v_truezero, 'unknown', v_unknown)),
           pdf_blocks = v_blocks,
           -- A correction regenerates the document. The old PDF is not the new report.
           pdf_path = null, pdf_url = null, pdf_bytes = null, pdf_generated_at = null, pdf_error = null,
           status = 'generated', generated_at = now(), updated_at = now()
     where id = v_row.id
    returning * into v_row;
  else
    insert into public.accountant_weekly_report(
      company_key, iso_year, iso_week, week_start, week_end, local_timezone, report_key,
      revision, revision_note, subject, body, figures, pdf_blocks, status)
    values (
      v_company, extract(isoyear from v_start)::int, extract(week from v_start)::int,
      v_start, v_end, v_tz, v_key, 1, p_revision_note, v_subject, v_body,
      jsonb_build_object('this_week', v_now, 'prior_week', v_prev,
                         'basis_counts', jsonb_build_object('measured', v_measured,
                           'true_zero', v_truezero, 'unknown', v_unknown)),
      v_blocks, 'generated')
    returning * into v_row;
  end if;

  return jsonb_build_object(
    'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
    'status', v_row.status, 'generated', true,
    'week_start', v_row.week_start, 'week_end', v_row.week_end,
    'subject', v_row.subject,
    'basis', jsonb_build_object('measured', v_measured, 'true_zero', v_truezero, 'unknown', v_unknown),
    'pdf_pending', true, 'pdf_blocks', v_blocks);
end;$awr$;

revoke execute on function public.fn_accountant_weekly_report(date, boolean, text) from public;

comment on function public.fn_accountant_weekly_report(date, boolean, text) is
  'Generates the accountant''s weekly financial report for one ISO week, once. Idempotent: the lookup on the unique report_key is UNFILTERED, so a second call returns the existing row in whatever state it is in rather than colliding on the key. p_revise bumps revision in place and discards the stale PDF. It does not deliver -- the founder asked for a PDF, so delivery waits for fn_accountant_weekly_report_attach_pdf.';

-- ---------------------------------------------------------------------------------------------
-- 7. THE PDF COMES BACK. Postgres cannot render one, so the caller (resilience_ping) posts the
--    stored blocks to pdf_native and hands the result back here. Success attaches and delivers;
--    failure is RECORDED and the report is retained for the next tick. Nothing raises.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_accountant_weekly_report_attach_pdf(
  p_id     bigint,
  p_bucket text default null,
  p_path   text default null,
  p_url    text default null,
  p_bytes  int  default null,
  p_error  text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $att$
declare v_row public.accountant_weekly_report%rowtype;
begin
  select * into v_row from public.accountant_weekly_report where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such report'); end if;

  if p_path is null or coalesce(p_error,'') <> '' then
    update public.accountant_weekly_report
       set pdf_error = coalesce(nullif(p_error,''), 'pdf_native returned no path'),
           status = case when delivered_at is null then 'pdf_failed' else status end,
           delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'the PDF could not be rendered: '||coalesce(nullif(p_error,''),'no path returned'),
           updated_at = now()
     where id = p_id returning * into v_row;
    -- RETAINED, NOT LOST. The next tick re-renders from the stored blocks.
    return jsonb_build_object('ok', false, 'report_key', v_row.report_key, 'retained', true,
      'reason', v_row.pdf_error, 'delivery_attempts', v_row.delivery_attempts);
  end if;

  update public.accountant_weekly_report
     set pdf_bucket = p_bucket, pdf_path = p_path, pdf_url = p_url, pdf_bytes = p_bytes,
         pdf_generated_at = now(), pdf_error = null,
         status = case when status = 'pdf_failed' then 'generated' else status end,
         updated_at = now()
   where id = p_id returning * into v_row;

  return public.fn_accountant_weekly_report_deliver(p_id);
end;$att$;

revoke execute on function public.fn_accountant_weekly_report_attach_pdf(bigint, text, text, text, int, text) from public;

-- ---------------------------------------------------------------------------------------------
-- 8. DELIVERY. Two recipients, two independent lanes, neither able to stop the other or the caller.
--
--    THE FOUNDER  a notifications row of kind 'accountant_weekly_report', addressed to
--                 app_secrets.admin_emails -- the key the gate matches on. The address is read into
--                 a local and never returned, logged or embedded in the body.
--    THE CEO      a support_ceo_report row with source_agent 'accountant'. The parent is READ from
--                 org_reporting_edge and required to be active; with no edge this refuses rather
--                 than choosing a recipient, because inventing one is how work goes to nobody.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_accountant_weekly_report_deliver(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $del$
declare
  v_row     public.accountant_weekly_report%rowtype;
  v_owner   text;
  v_parent  text;
  v_notif   bigint;
  v_ceo_id  bigint;
  v_errs    text[] := '{}';
  v_link    text;
  v_body    text;
begin
  select * into v_row from public.accountant_weekly_report where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such report'); end if;

  -- THE PDF IS THE DELIVERABLE. He asked for the report AS a PDF; mailing the text alone and
  -- marking the week delivered would close the key on something he did not ask for.
  if v_row.pdf_path is null then
    update public.accountant_weekly_report
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'not delivered: the PDF has not been rendered yet. The report is retained and the next tick retries.',
           updated_at = now()
     where id = p_id returning * into v_row;
    return jsonb_build_object('ok', false, 'report_key', v_row.report_key, 'retained', true,
      'reason', 'pdf not yet rendered', 'delivery_attempts', v_row.delivery_attempts);
  end if;

  v_link := case when v_row.pdf_url is not null
    then E'\n\n'||'The PDF: '||v_row.pdf_url||E'\n'||'(That link is signed and expires seven days from generation; the document itself is retained at '||coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path||'.)'
    else E'\n\n'||'The PDF is stored at '||coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path||'.' end;
  v_body := coalesce(v_row.body,'') || v_link;

  -- ---- LANE 1: THE FOUNDER -------------------------------------------------------------------
  if v_row.founder_submitted_at is null then
    select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
      from public.app_secrets where key = 'admin_emails';
    if v_owner is null then
      v_errs := v_errs || 'no recipient configured in app_secrets.admin_emails';
    else
      begin
        insert into public.notifications(type, kind, to_email, to_role, channel, subject, body)
        values ('accountant_weekly_report', 'accountant_weekly_report', v_owner, 'admin', 'email',
                v_row.subject, v_body)
        returning id into v_notif;
        if v_notif is null then
          -- The gate returned NULL: a refusal, not an error. Name it, do not swallow it.
          v_errs := v_errs || 'the founder-mail gate did not accept the row (kind accountant_weekly_report)';
        end if;
      exception when others then
        v_errs := v_errs || ('founder submission raised: '||sqlerrm);
      end;
    end if;
  end if;

  -- ---- LANE 2: THE CEO -----------------------------------------------------------------------
  if v_row.ceo_submitted_at is null then
    select e.parent_role_id into v_parent
      from public.org_reporting_edge e
      join public.org_role r on r.role_id = e.parent_role_id and r.status = 'active'
     where e.child_role_id = 'accountant';
    if v_parent is null then
      v_errs := v_errs || 'no active reporting parent for accountant; the CEO copy is NOT redirected to anyone else';
    else
      begin
        insert into public.support_ceo_report
          (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions,
           requested_outcome, owner_role_id, next_review_at)
        values
          ('accountant_weekly_report:'||v_row.report_key||':r'||v_row.revision,
           'accountant', 'routine', v_row.subject,
           jsonb_build_object(
             'report_key', v_row.report_key, 'revision', v_row.revision,
             'week_start', v_row.week_start, 'week_end', v_row.week_end,
             'pdf', coalesce(v_row.pdf_bucket,'agent-docs')||'/'||v_row.pdf_path,
             'pdf_bytes', v_row.pdf_bytes,
             'basis_counts', v_row.figures->'basis_counts',
             'figures', v_row.figures->'this_week'->'lines'),
           '[]'::jsonb,
           'Note the week''s financial position. NOTHING IS REQUESTED: this is the informational weekly report the founder asked for on 9 Sep 2026, delivered to the CEO because the accountant reports to the CEO. It carries no decision, no approval and no deadline. Refund and Meta-ads approvals reach the CEO through their own lanes, never through this one.',
           'accountant',
           now() + interval '7 days')
        returning id into v_ceo_id;
      exception
        when unique_violation then
          -- This revision was already reported. The original IS the delivery.
          select id into v_ceo_id from public.support_ceo_report
           where idempotency_key = 'accountant_weekly_report:'||v_row.report_key||':r'||v_row.revision;
        when others then
          v_errs := v_errs || ('CEO submission raised: '||sqlerrm);
      end;
    end if;
  end if;

  update public.accountant_weekly_report
     set notification_id      = coalesce(v_notif, notification_id),
         founder_submitted_at = case when v_notif is not null then now() else founder_submitted_at end,
         ceo_report_id        = coalesce(v_ceo_id, ceo_report_id),
         ceo_submitted_at     = case when v_ceo_id is not null then now() else ceo_submitted_at end,
         delivery_attempts    = delivery_attempts + 1,
         last_delivery_error  = nullif(array_to_string(v_errs, ' | '), ''),
         updated_at           = now()
   where id = p_id returning * into v_row;

  update public.accountant_weekly_report
     set status = case
           when v_row.founder_submitted_at is not null and v_row.ceo_submitted_at is not null then 'delivered'
           when v_row.founder_submitted_at is not null or  v_row.ceo_submitted_at is not null then 'partial'
           else 'delivery_failed' end,
         delivered_at = case
           when v_row.founder_submitted_at is not null and v_row.ceo_submitted_at is not null
           then coalesce(delivered_at, now()) else delivered_at end
   where id = p_id returning * into v_row;

  return jsonb_build_object(
    'ok', v_row.status in ('delivered','partial'),
    'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
    'status', v_row.status,
    'founder_submitted', v_row.founder_submitted_at is not null,
    'ceo_submitted', v_row.ceo_submitted_at is not null,
    'ceo_report_id', v_row.ceo_report_id,
    'delivery_attempts', v_row.delivery_attempts,
    'error', v_row.last_delivery_error);
end;$del$;

revoke execute on function public.fn_accountant_weekly_report_deliver(bigint) from public;

comment on function public.fn_accountant_weekly_report_deliver(bigint) is
  'Delivers one weekly financial report to BOTH recipients: the founder through a notifications row of the registered kind addressed from app_secrets.admin_emails (the key the founder-mail gate itself matches; the address is never returned or logged), and the CEO through public.support_ceo_report, the channel the CEO seat already reads, with the parent read live from org_reporting_edge and required to be active. The two lanes are independent, each already-delivered lane is skipped on a retry, and neither can raise into the caller: a failure is recorded in last_delivery_error and retried on the next tick.';

-- ---------------------------------------------------------------------------------------------
-- 9. THE TICK. What the LIVE scheduler calls every 15 minutes.
--
--    NOT pg_cron. cron.job holds one inactive row; 234 jobs were deleted on the founder's 7 Sep
--    instruction. The live path is Vercel cron -> /api/resilience-ping -> resilience_ping, which
--    already carries the CEO digest, the rating ask and the Dropbox backup. This is the fourth tick
--    on that path and it behaves like the other three: idempotent, and swallowed by its caller.
--
--    Returns pdf_pending + pdf_blocks when a PDF still needs rendering; the caller renders and
--    calls fn_accountant_weekly_report_attach_pdf. A report whose PDF failed, or whose delivery
--    failed, is picked up again here on the very next tick.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_accountant_weekly_report_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $tick$
declare
  v_tz    text := 'Asia/Dubai';
  v_local timestamp;
  v_at    time;
  v_dow   int;
  v_start date;
  v_key   text;
  v_row   public.accountant_weekly_report%rowtype;
begin
  v_local := now() at time zone v_tz;
  v_start := (date_trunc('week', v_local::date) - interval '7 days')::date;   -- the week that closed
  v_key   := 'quotesdone:'||to_char(v_start,'IYYY-"W"IW');

  begin
    select coalesce(nullif(btrim(value),''),'09:00')::time into v_at
      from public.app_secrets where key = 'accountant_weekly_report_local_time';
  exception when others then v_at := time '09:00'; end;
  v_at := coalesce(v_at, time '09:00');

  begin
    select coalesce(nullif(btrim(value),''),'1')::int into v_dow
      from public.app_secrets where key = 'accountant_weekly_report_local_dow';
  exception when others then v_dow := 1; end;
  v_dow := coalesce(v_dow, 1);

  select * into v_row from public.accountant_weekly_report where report_key = v_key;

  -- A REPORT ALREADY IN FLIGHT IS FINISHED WHATEVER DAY IT IS. The schedule decides when a week's
  -- report STARTS, not when a half-delivered one may be retried -- otherwise a Monday failure would
  -- wait a week, which is precisely the "retained but never retried" state this shape exists to
  -- prevent.
  if found then
    if v_row.pdf_path is null then
      return jsonb_build_object('fired', true, 'reason', 'the PDF for this week is still outstanding',
        'report_key', v_key, 'id', v_row.id, 'revision', v_row.revision, 'status', v_row.status,
        'pdf_pending', true, 'pdf_blocks', v_row.pdf_blocks, 'subject', v_row.subject);
    end if;
    if v_row.delivered_at is null then
      return public.fn_accountant_weekly_report_deliver(v_row.id)
             || jsonb_build_object('fired', true, 'reason', 'retrying an undelivered lane');
    end if;
    return jsonb_build_object('fired', false, 'reason', 'already generated and delivered for this ISO week',
      'report_key', v_key, 'id', v_row.id, 'revision', v_row.revision, 'status', v_row.status);
  end if;

  if extract(isodow from v_local)::int < v_dow or (extract(isodow from v_local)::int = v_dow and v_local::time < v_at) then
    return jsonb_build_object('fired', false, 'reason', 'before the configured local day/time',
      'local_now', to_char(v_local,'Dy YYYY-MM-DD HH24:MI'), 'configured_dow', v_dow,
      'configured_at', v_at::text, 'report_key', v_key);
  end if;

  return public.fn_accountant_weekly_report(v_start)
         || jsonb_build_object('fired', true, 'configured_at', v_at::text, 'configured_dow', v_dow);
end;$tick$;

revoke execute on function public.fn_accountant_weekly_report_tick() from public;

comment on function public.fn_accountant_weekly_report_tick() is
  'The once-per-ISO-week trigger for the accountant''s weekly financial report, called by resilience_ping on the LIVE (Vercel cron) scheduler every 15 minutes. Fires at or after app_secrets.accountant_weekly_report_local_dow / _local_time in Asia/Dubai and is idempotent within the week. An outstanding PDF or an undelivered lane is picked up on ANY tick, not only the scheduled one, so a Monday failure is retried in fifteen minutes rather than in a week. Not a pg_cron job: cron.job was emptied on the founder''s 7 Sep 2026 instruction and would not fire.';

-- ---------------------------------------------------------------------------------------------
-- 10. THE CLOSING ASSERTION. Every claim this file makes, checked against the database it made it in.
-- ---------------------------------------------------------------------------------------------
do $check$
declare
  v_kind int; v_scope int; v_fns int; v_pub int; v_edge int;
begin
  select count(*) into v_kind from public.founder_mail_policy
   where kind = 'accountant_weekly_report' and allowed_to_email and owner_role = 'accountant';
  if v_kind <> 1 then
    raise exception 'THE MAIL KIND IS NOT REGISTERED: the notifications insert would return NULL and vanish silently';
  end if;

  select count(*) into v_scope from public.internal_credential
   where context = 'fn.resilience_ping' and active and 'pdf_native' = any(scope);
  if v_scope <> 1 then
    raise exception 'resilience_ping CANNOT CALL pdf_native: the PDF would 403 forever';
  end if;

  select count(*) into v_edge from public.org_reporting_edge e
    join public.org_role r on r.role_id = e.parent_role_id and r.status = 'active'
   where e.child_role_id = 'accountant';
  if v_edge <> 1 then
    raise exception 'THE CEO COPY HAS NOWHERE TO GO: no active reporting parent for accountant';
  end if;

  select count(*) into v_fns from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (
     'fn_accountant_weekly_report_figures','fn_accountant_weekly_report',
     'fn_accountant_weekly_report_attach_pdf','fn_accountant_weekly_report_deliver',
     'fn_accountant_weekly_report_tick');
  if v_fns <> 5 then raise exception 'EXPECTED 5 ROUTINES, FOUND %', v_fns; end if;

  -- A new SECURITY DEFINER routine that PUBLIC can execute is a privilege escalation, not a report.
  select count(*) into v_pub from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'fn_accountant_weekly_report%'
     and has_function_privilege('public', p.oid, 'execute');
  if v_pub <> 0 then raise exception '% ROUTINE(S) ARE STILL EXECUTABLE BY PUBLIC', v_pub; end if;

  raise notice 'accountant weekly report installed: 1 table, 5 routines (0 public-executable), mail kind registered to owner accountant, pdf_native in resilience_ping scope, CEO copy routed by org_reporting_edge';
end
$check$;
