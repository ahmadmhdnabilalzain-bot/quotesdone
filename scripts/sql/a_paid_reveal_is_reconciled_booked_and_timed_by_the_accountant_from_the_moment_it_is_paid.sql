-- A PAID REVEAL IS RECONCILED, BOOKED AND TIMED BY THE ACCOUNTANT FROM THE MOMENT IT IS PAID.
--
-- Assigned: accountant (the reconcile, the books, the clock, our invoice, the notices of a sale). 13 Nov 2026,
-- founder_instruction 1685, 1687, 1688: "was the accountant aware that this is the invoice that we received? Is it kept
-- in the books properly? Is the CEO aware that we made that sales? ... the accountant will start the timer from the day
-- of payment for the refund window". Audit of 13 Nov (scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs);
-- independent review of 13 Nov (FIX, 12 items) and the coordinator's rulings R1-R6, all built here.
--
-- ══ MEASURED ON PRODUCTION, 13 Nov 2026 (read only) ═══════════════════════════════════════════════════
--   * trg_reveal_receipt files reveal.paid FROM accountant TO sales_engineer; no handoff kind is addressed TO the
--     accountant about a payment (the one accountant row on the only kept reveal, 29ac49f5, is agent_actions 100357: a
--     charge_audit finding answered "no deterministic remedy" and closed 33 days later, AED 38.77 never refunded).
--   * 0 reveal_fee journals ever. revealed_at is the INSERT time and the window counted from it. livemode is not stored:
--     "demo" was read from flags on the customer, supplier or inquiry, so a LIVE payment touching a flagged identity
--     would have been left out of the books.
--   * fn_accountant_book_stripe_fees already books Stripe's Invoicing fee (and its VAT) when Stripe bills it: no accrual.
--   * the window: fn_refund_state, fn_refund_nonresponse_eligibility (Friday and Saturday as the weekend, wrong since
--     2022), messages_api/mailbox.ts and supplier_api/actions/inbox.ts each counted it their own way, from revealed_at.
--     fn_is_working_day counts Monday to Friday and skips public.public_holidays (25 dates, to 3 Dec 2027).
--   * the same notice went out more than once per channel (29ac49f5: invoice_ready 3x, reveal_receipt 2x on WhatsApp).
--   * authority: ceo_standing_grant accountant.refund_decision max_amount_aed 0 (founder, 9 Sep 2026): every refund,
--     an overcharge included, is the CEO's. The accountant recommends; a standing grant 'overcharge_return' (a data row,
--     scripts/sql/pending note) would let it return an overcharge itself.
--
-- ══ WHAT THIS CHANGES (code or model, step by step) ═══════════════════════════════════════════════════
--   1. TEST MODE IS THE ONLY DEMO FOR MONEY (R2). transactions.livemode is Stripe's, written at the sale. A test-mode
--      payment, whoever made it (a ZZ DEMO account, or any account paying with the test key), never reaches gl_journal,
--      the invoice sequence, the brief or a total: its chain goes to public.demo_shadow_trace only. A LIVE payment is
--      always booked; if it touches a demo-flagged identity it is booked AND is a payment exception
--      ('live_payment_on_test_identity').
--   2. THE CLOCK (code). paid_at is Stripe's charge time, clamped to now; when Stripe gives none within 15 minutes the
--      insert time is used and recorded (paid_at_source). public.fn_reveal_refund_window_ends(paid_at) = 23:59:59 Asia/Dubai
--      of the 5th working day (Mon-Fri, public_holidays skipped) is the ONE end date; public.fn_reveal_window(tx) gives
--      start, chase day and end to every reader (fn_refund_state, fn_refund_nonresponse_eligibility, both portals).
--      reveal.paid (the customer's receipt) is handed over only once paid_at is known, so the date it prints never moves.
--   3. OUR INVOICE NUMBER (code): QD-INV-000001... for a live sale (unique, never reused, NOT gapless: a sequence keeps
--      what a failed transaction took); ZZ-TEST-INV-<tx> for test mode, never from the sequence.
--   4. THE ACCOUNTANT IS TOLD (code): reveal.reconcile (sales_engineer -> accountant) at the sale. The check: invoice,
--      PaymentIntent and balance transaction against 3% of quotes.price_ex_vat to the fils, AED, one payment, nothing but
--      the fee, quote_amount = price_ex_vat. A match closes the handoff, posts the journal and tells the CEO (sale.made).
--   5. ANYTHING ELSE IS JUDGED (model): accountant.payment_exception, then ceo.payment_exception. Each occurrence is
--      numbered (exception_count), so a second exception on one payment reaches everyone again. Within the hour: the
--      15-minute sweep escalates an unjudged exception to the CEO at 45 minutes and tells the founder in the same call
--      (fn_notify_founder, kind finance_alert: e-mail and WhatsApp). The CEO's 'refund_difference' requests exactly the
--      difference through fn_refund_request (the existing refund path), tells the customer once, and the check stays
--      open until Stripe's refund settles; 'investigate' has the accountant read Stripe again and come back with a final
--      two-option question; 'money_is_correct' closes it. Every CEO decision closes the reconcile handoff.
--   6. THE BOOKS (code): Dr 1050 (what Stripe settles) / Dr 6100 card fee from the balance transaction / Cr 4000 the fee
--      / Cr 2300 anything charged above it. No VAT line; no estimate: until Stripe's fee is read the sale shows as
--      "paid, awaiting Stripe's figures" (the brief counts it) and after an hour it is an exception. Refunds post the
--      amount actually refunded (2300 first, then 6900). Disputes: withdrawn Dr 6900 (Dr 1100 when the charge was already
--      refunded) / Cr 1050, Stripe's dispute fee Dr 6100 / Cr 1050, both reversed when Stripe returns them. One journal
--      per event: a unique index and an advisory lock. Revenue date = the Dubai date of paid_at.
--   7. THE CEO AND THE FOUNDER: sale.made with what was sold, fee, trade, emirate, customer type, month total; the
--      founder brief lists each live sale and each sale awaiting Stripe's figures.
--   8. PAID BUT NOT RECORDED: payment.unrecorded to the it_engineer and customer_support; the heal reported on both.
--   9. ONCE PER CHANNEL: a retry is skipped only when the other channel's copy was really sent or delivered.
--
-- NOT CHANGED: the sales engineer's reveal.paid work (fn_sales_engineer_acts_on_handoff and its sibling build: it reads
-- refund_window_sentence_en / _ar from the payload). fn_seat_handoff is its owner file's
-- (the_it_engineer_closes_every_loop_it_opens.sql). The 1150 correction is its own file.
--
-- Apply order: THIS file, then the owner file's fn_seat_handoff (it calls fn_demo_shadow_record and
-- fn_payload_names_a_live_payment defined here), then deploy the functions (reveal_sale.ts writes livemode and paid_at).
-- The whole release, step by step, with its timing, retry rule and checks: docs/runbooks/a_paid_reveal_release_13_nov_2026.md.
-- Pending: scripts/sql/pending/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.txt.
-- Probe: scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid_probe.sql.

-- ══ 0. THE APPLY MUST NOT FREEZE THE SITE (coordinator, 13 Nov 2026: rehearsals holding table locks timed out live
-- readers). Every lock this file takes is short: ADD COLUMN without a default (catalogue only, no rewrite), constraints
-- replaced in one statement (ADD CONSTRAINT ... NOT VALID followed by VALIDATE in the SAME transaction saves nothing, so
-- it is one plain ADD on refunds: 1 row in production), indexes on small tables (reveal_invoices 0 rows, gl_journal 215
-- rows on 13 Nov), triggers created in place. lock_timeout makes the apply FAIL after 1.5 seconds instead of queueing
-- behind a long query and making every live reader queue behind it; the runbook says when and how to re-run it
-- (docs/runbooks/a_paid_reveal_release_13_nov_2026.md).
set local lock_timeout = '1500ms';

-- ══ 1. COLUMNS, INDEXES, SEQUENCE ═════════════════════════════════════════════════════════════════════
alter table public.transactions add column if not exists paid_at timestamptz;
alter table public.transactions add column if not exists paid_at_source text;
alter table public.transactions add column if not exists livemode boolean;
alter table public.transactions add column if not exists stripe_amount_received_fils bigint;
alter table public.transactions add column if not exists stripe_bt_amount_fils bigint;
alter table public.transactions add column if not exists stripe_bt_currency text;
comment on column public.transactions.paid_at is
  'Stripe''s own time the charge succeeded, never later than now. The refund window counts from it (fn_reveal_refund_window_ends). paid_at_source says where it came from.';
comment on column public.transactions.livemode is
  'Stripe''s livemode for this payment. false = Stripe test mode: never booked, numbered or counted (its chain is in demo_shadow_trace). true = a real payment, always booked.';
-- THE ROWS WRITTEN BEFORE THIS FILE, FROM STRIPE'S OWN EVIDENCE (never from a flag on the customer). Stripe's hosted and
-- PDF invoice links name the mode in their path: https://invoice.stripe.com/i/acct_.../test_... for test mode, .../live_...
-- for live. Else the accountant's reconcile item for the same invoice or PaymentIntent records livemode as Stripe listed
-- it. A row neither says stays NULL = UNKNOWN: never booked, numbered or counted until the accountant's hourly reconcile
-- reads the PaymentIntent from Stripe (it tries both keys), and listed for the founder in the brief meanwhile.
-- Measured 13 Nov 2026: one paid reveal (29ac49f5), its links carry /test_ -> false.
update public.transactions t
   set livemode = case
         when coalesce(t.stripe_invoice_hosted_url, '') ~ '/test_' or coalesce(t.stripe_invoice_pdf_url, '') ~ '/test_' then false
         when coalesce(t.stripe_invoice_hosted_url, '') ~ '/live_' or coalesce(t.stripe_invoice_pdf_url, '') ~ '/live_' then true
         else (select i.livemode from public.accountant_reveal_reconcile_item i
                where (t.stripe_invoice_id is not null and i.invoice_id = t.stripe_invoice_id)
                   or (t.payment_ref is not null and i.payment_intent = t.payment_ref)
                order by i.last_seen_at desc limit 1) end
 where t.livemode is null;

alter table public.stripe_dispute add column if not exists fee_fils bigint;
alter table public.stripe_dispute add column if not exists fee_returned_fils bigint;
comment on column public.stripe_dispute.fee_fils is 'Stripe''s dispute fee, from the dispute''s balance transactions (stripe_webhook).';

create sequence if not exists public.reveal_invoice_no_seq start 1;
revoke all on sequence public.reveal_invoice_no_seq from public, anon, authenticated;
create unique index if not exists reveal_invoices_invoice_no_key on public.reveal_invoices (invoice_no) where invoice_no is not null;

-- ONE JOURNAL PER MONEY EVENT (review item 6): a webhook reconcile and the cost tick can race; the second insert fails.
create unique index if not exists gl_journal_one_entry_per_reveal_money_event on public.gl_journal (source, source_ref)
  where source = any (array['reveal_fee', 'refund_paid', 'dispute_withdrawn', 'dispute_won', 'dispute_fee', 'dispute_fee_returned'])
    and status <> 'void';

-- ══ 2. THE SHADOW OF A DEMO PAYMENT ═══════════════════════════════════════════════════════════════════
create table if not exists public.demo_shadow_trace (
  id bigint generated always as identity primary key,
  run_tag text,
  transaction_id uuid,
  quote_id uuid,
  inquiry_id uuid,
  customer_id uuid,
  step text not null check (step in ('handoff', 'reconcile', 'model_question', 'decision', 'escalation', 'journal', 'ceo_notice', 'window_clock', 'invoice_number')),
  from_seat text,
  to_seat text,
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  keep_until timestamptz not null default now() + interval '14 days',
  read_at timestamptz
);
comment on table public.demo_shadow_trace is
  'What a Stripe TEST-mode payment (or any demo work fn_seat_handoff files nothing for) would have done, step by step, kept apart from the real books and the real handoff queue. No foreign key, so a teardown leaves it; purged after keep_until by fn_accountant_payment_checks_sweep. Read by the journey proof (co_company) by transaction_id, quote_id, inquiry_id or customer_id.';
create index if not exists demo_shadow_trace_tx_idx on public.demo_shadow_trace (transaction_id) where transaction_id is not null;
create index if not exists demo_shadow_trace_quote_idx on public.demo_shadow_trace (quote_id) where quote_id is not null;
create index if not exists demo_shadow_trace_inquiry_idx on public.demo_shadow_trace (inquiry_id) where inquiry_id is not null;
create index if not exists demo_shadow_trace_keep_idx on public.demo_shadow_trace (keep_until);
alter table public.demo_shadow_trace enable row level security;
drop policy if exists demo_shadow_trace_service_role_only on public.demo_shadow_trace;
create policy demo_shadow_trace_service_role_only on public.demo_shadow_trace as permissive for all to public using (false) with check (false);
revoke all on public.demo_shadow_trace from anon, authenticated;


-- ══ 3. THE ACCOUNTANT'S CHECK OF ONE PAYMENT ══════════════════════════════════════════════════════════
create table if not exists public.accountant_reveal_payment_check (
  transaction_id uuid primary key,
  is_test_mode boolean not null default false,          -- Stripe test mode (livemode false): never booked
  on_test_identity boolean not null default false,      -- a LIVE payment touching a demo-flagged identity
  run_tag text,
  quote_id uuid,
  our_invoice_no text,
  stripe_invoice_id text,
  stripe_invoice_number text,
  payment_ref text,
  price_ex_vat numeric,
  quote_amount numeric,
  rate numeric,
  expected_fee_fils bigint,
  recorded_fee_fils bigint,
  charged_fils bigint,
  invoice_total_fils bigint,
  amount_received_fils bigint,
  bt_amount_fils bigint,
  bt_fee_fils bigint,
  currency text,
  paid_at timestamptz,
  refund_window_ends_at timestamptz,
  findings jsonb not null default '[]'::jsonb,
  -- nothing_to_book: a zero fee, or a full refund before Stripe's figures were read (review 3, item 5): resolved by code
  verdict text not null default 'waiting_for_facts' check (verdict in ('waiting_for_facts', 'matched', 'exception', 'nothing_to_book')),
  decided_by text,
  decision text,
  decision_reason text,
  held_question_id bigint,
  exception_count integer not null default 0,           -- each new exception on this payment is a new occurrence
  investigate_requested_at timestamptz,
  sale_notice_at timestamptz,                           -- sale.made reached the CEO (the sweep retries until it has)
  final_question boolean not null default false,
  stripe_snapshot jsonb,
  stripe_read_at timestamptz,
  refund_id bigint,
  refund_ceo_task_id bigint,                            -- the "Decide refund" task of the return: closed only when it is submitted
  refund_submitted_at timestamptz,                      -- the return reached Stripe (refunds.stripe_refund_id): the customer is told then
  reconcile_handoff_id bigint,
  ceo_handoff_id bigint,
  journal_id bigint,
  opened_at timestamptz not null default now(),
  checked_at timestamptz,
  escalated_at timestamptz,
  ceo_decision text,
  ceo_decided_at timestamptz,
  resolved_at timestamptz,
  resolution text
);
comment on table public.accountant_reveal_payment_check is
  'One row per paid reveal: the accountant''s reconcile of our invoice, the PaymentIntent and the balance transaction against 3% of the quotation ex-VAT. matched = code booked and reported it; exception = judged by the accountant''s model path and decided by the CEO; never resolved by a timer.';
create index if not exists accountant_reveal_payment_check_open_idx on public.accountant_reveal_payment_check (opened_at) where resolved_at is null;
alter table public.accountant_reveal_payment_check enable row level security;
drop policy if exists accountant_reveal_payment_check_service_role_only on public.accountant_reveal_payment_check;
create policy accountant_reveal_payment_check_service_role_only on public.accountant_reveal_payment_check as permissive for all to public using (false) with check (false);
revoke all on public.accountant_reveal_payment_check from anon, authenticated;


-- ══ 4. THE ONE SOURCE OF THE WINDOW ═══════════════════════════════════════════════════════════════════
-- Terms of Service v11 (src/content/legal.json, terms.en): "If the Supplier has failed to respond both to you and to
-- QuotesDone within five (5) working days of your payment ..." Counted from the PAYMENT; working days are Monday to
-- Friday (the UAE weekend is Saturday and Sunday since 2022), skipping the dates in public.public_holidays
-- (fn_is_working_day; 25 dates to 3 Dec 2027: a holiday not in that table is counted as a working day). The window ENDS
-- at 23:59:59 Asia/Dubai of the 5th working day, so the date the customer is told is true to the last minute.
create or replace function public.fn_reveal_refund_window_ends(p_paid_at timestamptz)
returns timestamptz language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select case when p_paid_at is null then null else
    ((((public.fn_add_working_days(p_paid_at,
          coalesce((select refund_window_working_days from public.pricing_config order by id limit 1), 5))
        at time zone 'Asia/Dubai')::date + 1)::timestamp - interval '1 second') at time zone 'Asia/Dubai') end
$fn$;
revoke execute on function public.fn_reveal_refund_window_ends(timestamptz) from public, anon, authenticated;
-- pure date arithmetic, read by trg_reveal_window (which runs as the writer): the reach fn_add_working_days has
grant execute on function public.fn_reveal_refund_window_ends(timestamptz) to authenticated, service_role;

-- Where the clock starts: Stripe's paid time, else (only until Stripe gives one) when our row was written; never later
-- than now.
create or replace function public.fn_reveal_clock_start(p_tx uuid)
returns timestamptz language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select least(coalesce(t.paid_at, t.revealed_at), now()) from public.transactions t where t.id = p_tx
$fn$;
revoke execute on function public.fn_reveal_clock_start(uuid) from public, anon, authenticated;

-- Every reader of the window reads this: the start, the chase day, the end, and where the start came from.
create or replace function public.fn_reveal_window(p_tx uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; v_start timestamptz; v_chase int;
begin
  select * into t from public.transactions where id = p_tx;
  if not found or t.revealed_at is null then return null; end if;
  v_start := least(coalesce(t.paid_at, t.revealed_at), now());
  select chase_after_working_days into v_chase from public.pricing_config order by id limit 1;
  return jsonb_build_object('transaction_id', p_tx, 'starts_at', v_start,
    'started_from', coalesce(t.paid_at_source, case when t.paid_at is not null then 'stripe' else 'insert_time (Stripe''s paid time not read yet)' end),
    'chase_at', public.fn_add_working_days(v_start, coalesce(v_chase, 3)),
    'ends_at', coalesce(t.refund_deadline, public.fn_reveal_refund_window_ends(v_start)));
end $fn$;
revoke execute on function public.fn_reveal_window(uuid) from public, anon, authenticated;
grant execute on function public.fn_reveal_window(uuid) to service_role;

create or replace function public.trg_reveal_window()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $function$
begin
  -- Stripe's paid time is never in the future (a clock skew or a bad payload cannot push the window out).
  if NEW.paid_at is not null and NEW.paid_at > now() then NEW.paid_at := now(); end if;
  if NEW.paid_at is not null and NEW.paid_at_source is null then NEW.paid_at_source := 'stripe'; end if;
  -- The window opens at the moment Stripe took the money (paid_at), else when our row was written; one rule,
  -- fn_reveal_refund_window_ends, for every path.
  if coalesce(NEW.paid_at, NEW.revealed_at) is not null and NEW.refund_deadline is null then
    NEW.refund_deadline := public.fn_reveal_refund_window_ends(least(coalesce(NEW.paid_at, NEW.revealed_at), now()));
    if NEW.refund_status is null then NEW.refund_status := 'window_open'; end if;
  -- Stripe's paid time arrived after the row: the deadline counts from it, while nothing has been asked of the window.
  elsif TG_OP = 'UPDATE' and NEW.paid_at is not null and OLD.paid_at is distinct from NEW.paid_at
        and coalesce(NEW.refund_status, 'window_open') = 'window_open' and NEW.refund_requested_at is null then
    NEW.refund_deadline := public.fn_reveal_refund_window_ends(NEW.paid_at);
  end if;
  return NEW;
end $function$;
revoke execute on function public.trg_reveal_window() from public, anon, authenticated;

-- ══ 5. TEST MODE, IDENTITY, RUN TAG, SHADOW, OUR INVOICE NUMBER ═══════════════════════════════════════
-- R2: for money, "demo" is Stripe TEST mode and nothing else. A row with no livemode is UNKNOWN (an old deploy wrote it,
-- or evidence was missing): it is neither booked nor shadowed as test; it waits for Stripe's answer (fn_reveal_is_live).
-- A sale whose mode is known LIVE: the only kind the books, the invoice series and the totals ever take.
create or replace function public.fn_reveal_is_live(p_tx uuid)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select t.livemode from public.transactions t where t.id = p_tx), false)
$fn$;
revoke execute on function public.fn_reveal_is_live(uuid) from public, anon, authenticated;

create or replace function public.fn_reveal_is_test_mode(p_tx uuid)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select t.livemode = false from public.transactions t where t.id = p_tx), false)
$fn$;
revoke execute on function public.fn_reveal_is_test_mode(uuid) from public, anon, authenticated;

-- A LIVE payment whose customer, supplier, quote or request carries a demo flag: booked, and an exception.
-- (A rolled-back probe proving the clean live path on a ZZ DEMO fixture sets qd.probe_files_demo_handoff.)
create or replace function public.fn_reveal_on_test_identity(p_tx uuid)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case when coalesce(current_setting('qd.probe_files_demo_handoff', true), '') = 'on' then false
              else not public.fn_reveal_is_test_mode(p_tx) and public.fn_transaction_is_demo(p_tx) end
$fn$;
revoke execute on function public.fn_reveal_on_test_identity(uuid) from public, anon, authenticated;

-- fn_seat_handoff (owner file) asks this before shadowing demo work: a handoff about a LIVE payment is always filed.
create or replace function public.fn_payload_names_a_live_payment(p_payload jsonb)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- Stripe's livemode decides, nothing else: the payload's own (a payment not recorded as a sale has no transaction yet,
  -- stripe_webhook puts the event's mode in it), else the transaction's
  select case when p_payload->>'livemode' in ('true', 'false') then (p_payload->>'livemode')::boolean
              else coalesce(p_payload->>'transaction_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                     and exists (select 1 from public.transactions t where t.id = (p_payload->>'transaction_id')::uuid and t.livemode), false) end
$fn$;
revoke execute on function public.fn_payload_names_a_live_payment(jsonb) from public, anon, authenticated;



-- The run a demo row belongs to: the request's own tag when the harness sent one, else the qd-<tag> the journey proof
-- writes into the demo customer's address. Null when neither says (the ids still find the rows).
create or replace function public.fn_demo_run_tag_of(p_customer uuid)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(public.fn_e2e_run_tag_current(),
                  (select substring(lower(c.email) from '^qd-([a-z0-9]{4,16})[-+._@]') from public.customers c where c.id = p_customer))
$fn$;
revoke execute on function public.fn_demo_run_tag_of(uuid) from public, anon, authenticated;

create or replace function public.fn_demo_shadow_record(p_step text, p_kind text, p_from text, p_to text, p_payload jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  p jsonb := coalesce(p_payload, '{}'::jsonb); v_tx uuid; v_q uuid; v_i uuid; v_c uuid; v_id bigint;
begin
  v_tx := case when p->>'transaction_id' ~ v_uuid then (p->>'transaction_id')::uuid end;
  v_q  := case when p->>'quote_id' ~ v_uuid then (p->>'quote_id')::uuid end;
  v_i  := case when p->>'inquiry_id' ~ v_uuid then (p->>'inquiry_id')::uuid end;
  v_c  := case when p->>'customer_id' ~ v_uuid then (p->>'customer_id')::uuid end;
  if v_tx is not null and (v_q is null or v_i is null or v_c is null) then
    select coalesce(v_q, t.quote_id), coalesce(v_i, t.inquiry_id), coalesce(v_c, t.customer_id) into v_q, v_i, v_c
      from public.transactions t where t.id = v_tx;
  end if;
  insert into public.demo_shadow_trace (run_tag, transaction_id, quote_id, inquiry_id, customer_id, step, from_seat, to_seat, kind, payload)
  values (coalesce(p->>'run_tag', public.fn_demo_run_tag_of(v_c)), v_tx, v_q, v_i, v_c, p_step, p_from, p_to, p_kind, p)
  returning id into v_id;
  return v_id;
exception when others then
  return null;   -- a shadow is evidence for a rehearsal; it never fails the work that produced it
end $fn$;
revoke execute on function public.fn_demo_shadow_record(text, text, text, text, jsonb) from public, anon, authenticated;


-- Our invoice number for a sale: allocated once, kept in reveal_invoices.invoice_no (unique). A test-mode sale is
-- numbered ZZ-TEST-INV-<tx> and never takes a number from the sequence. The sequence is unique and never reused, but
-- NOT gapless: Postgres keeps a number a failed transaction took. QuotesDone is not VAT-registered, so no rule needs a
-- gapless series; the books cite the number, never count on it.
create or replace function public.fn_reveal_invoice_number(p_tx uuid)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_no text;
begin
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || p_tx::text));
  select invoice_no into v_no from public.reveal_invoices where transaction_id = p_tx and invoice_no ~ '^(QD-INV-|ZZ-TEST-INV-|ZZ-PROBE-INV-)';
  if v_no is not null then return v_no; end if;
  if not exists (select 1 from public.transactions where id = p_tx) then return null; end if;
  -- a sale whose Stripe mode is not known yet takes no number: it is numbered once Stripe says (the hourly reconcile)
  if (select livemode from public.transactions where id = p_tx) is null then return null; end if;
  -- A ZERO-FEE REVEAL IS NOT INVOICED (review 4, item 6e): an invoice for AED 0 is not an invoice, so it takes no number
  -- (reveal_invoice renders no invoice for it either: reveal_fee_documents.ts invoiceIsDue)
  if (select coalesce(t.reveal_fee, 0) <= 0 and coalesce(t.total_charged, 0) <= 0 and coalesce(t.stripe_amount_received_fils, 0) <= 0
        from public.transactions t where t.id = p_tx) then return null; end if;
  -- a sequence number is never rolled back, so a rolled-back probe of a LIVE sale (it sets qd.probe_invoice_number) is
  -- numbered ZZ-PROBE-INV-<tx> and takes nothing from the company's series
  v_no := case when public.fn_reveal_is_test_mode(p_tx) then 'ZZ-TEST-INV-' || upper(left(p_tx::text, 8))
               when coalesce(current_setting('qd.probe_invoice_number', true), '') = 'probe' then 'ZZ-PROBE-INV-' || upper(left(p_tx::text, 8))
               else 'QD-INV-' || lpad(nextval('public.reveal_invoice_no_seq')::text, 6, '0') end;
  insert into public.reveal_invoices (transaction_id, invoice_no) values (p_tx, v_no)
  on conflict (transaction_id) do update set invoice_no = excluded.invoice_no
    where public.reveal_invoices.invoice_no is null or public.reveal_invoices.invoice_no !~ '^(QD-INV-|ZZ-TEST-INV-|ZZ-PROBE-INV-)';
  select invoice_no into v_no from public.reveal_invoices where transaction_id = p_tx;
  return v_no;
end $fn$;
revoke execute on function public.fn_reveal_invoice_number(uuid) from public, anon, authenticated;
grant execute on function public.fn_reveal_invoice_number(uuid) to service_role;

-- ══ 6. A TEST-MODE PAYMENT'S HANDOFFS GO TO THE SHADOW ════════════════════════════════════════════════
-- fn_seat_handoff (its owner file) shadows demo work by identity and files every handoff about a LIVE payment. A
-- test-mode payment by an account that carries no demo flag would pass its identity test, so every money conversation
-- here asks fn_reveal_is_test_mode first: test mode -> demo_shadow_trace only, never fn_seat_handoff. Nothing is
-- shadowed twice: a live payment's conversations go only through fn_seat_handoff.

-- ══ 7. THE JOURNAL OF ONE SALE (the same lines are posted for a live sale and shadowed for a test one) ═══
create or replace function public.fn_reveal_fee_journal(p_tx uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; v_inv text; v_gross bigint; v_fee bigint; v_card bigint; v_over bigint; v_net bigint; v_lines jsonb; v_memo text;
begin
  select * into t from public.transactions where id = p_tx;
  if not found then return null; end if;
  -- what the customer was charged: Stripe's own figures first, then our record
  v_gross := coalesce(t.stripe_bt_amount_fils, t.stripe_amount_received_fils, round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint);
  v_fee   := round(coalesce(t.reveal_fee, 0) * 100)::bigint;
  v_card  := t.stripe_fee_fils;
  -- NO ESTIMATE (13 Nov 2026): the card fee is only Stripe's own; until it is read the sale is "paid, awaiting Stripe's
  -- figures" (fn_founder_brief_sale_lines) and an exception to the CEO after an hour.
  if v_card is null or v_gross <= 0 or v_fee <= 0 then
    return jsonb_build_object('ready', false, 'why', case when v_card is null then 'the balance transaction (Stripe''s card fee) is not read yet' else 'no amount' end);
  end if;
  v_over := greatest(v_gross - v_fee, 0);           -- charged above the fee: owed back to the customer
  v_net  := v_gross - v_card;                        -- what Stripe settles into the clearing account
  v_inv := (select invoice_no from public.reveal_invoices where transaction_id = p_tx);
  v_memo := 'Reveal fee, our invoice ' || coalesce(v_inv, '(not numbered)')
         || coalesce(' (Stripe invoice ' || t.stripe_invoice_number || ')', '') || ', transaction ' || left(p_tx::text, 8)
         || ': 3% of the quotation ex-VAT, no VAT charged';
  -- R1: Stripe's Invoicing fee is NOT accrued here: fn_accountant_book_stripe_fees books it (with its VAT) when Stripe bills it.
  v_lines := jsonb_build_array(
    jsonb_build_object('account', '1050', 'debit', v_net / 100.0, 'memo', 'Stripe clearing: charged less Stripe''s card fee'),
    jsonb_build_object('account', '6100', 'debit', v_card / 100.0, 'memo', 'Stripe card fee from the balance transaction'),
    jsonb_build_object('account', '4000', 'credit', least(v_fee, v_gross) / 100.0, 'memo', 'Reveal fee revenue, invoice ' || coalesce(v_inv, '?')));
  if v_over > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', '2300', 'credit', v_over / 100.0,
      'memo', 'Charged above the fee: owed back to the customer'));
  end if;
  return jsonb_build_object('ready', true, 'date', (least(coalesce(t.paid_at, t.revealed_at), now()) at time zone 'Asia/Dubai')::date,
    'memo', v_memo, 'lines', v_lines, 'our_invoice_no', v_inv, 'stripe_invoice_number', t.stripe_invoice_number,
    'gross_fils', v_gross, 'fee_fils', v_fee, 'card_fee_fils', v_card, 'over_fils', v_over);
end $fn$;
revoke execute on function public.fn_reveal_fee_journal(uuid) from public, anon, authenticated;

-- Posts the sale once (source reveal_fee, source_ref the transaction; the advisory lock and
-- gl_journal_one_entry_per_reveal_money_event make it once under concurrency). A test-mode sale is shadowed, never posted.
-- A LIVE sale is posted whoever it touches (R2); only an orphan (its transaction gone) is not.
create or replace function public.fn_gl_post_reveal_fee(p_tx uuid)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare j jsonb; v_jid bigint; v_why text;
begin
  -- the payment's lock first (it updates the check row below; fn_gl_sync_business calls this without it): item 6b
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || p_tx::text));
  perform pg_advisory_xact_lock(hashtext('reveal_fee:' || p_tx::text));
  select g.id into v_jid from public.gl_journal g where g.source = 'reveal_fee' and g.source_ref = p_tx::text and g.status <> 'void' order by g.id limit 1;
  if v_jid is not null then return v_jid; end if;
  -- NOTHING TO BOOK (review 4, item 3): a zero fee, or a sale refunded in full before it was booked, earns no revenue,
  -- whenever Stripe's figures arrive and whatever reopens the check later (a dispute); fn_gl_sync_business books only the
  -- card fee Stripe kept
  if public.fn_reveal_nothing_to_book(p_tx) is not null then return null; end if;
  j := public.fn_reveal_fee_journal(p_tx);
  if j is null or not coalesce((j->>'ready')::boolean, false) then return null; end if;
  if not public.fn_reveal_is_test_mode(p_tx) and not public.fn_reveal_is_live(p_tx) then return null; end if;   -- mode unknown: waits
  if public.fn_reveal_is_test_mode(p_tx) then
    if not exists (select 1 from public.demo_shadow_trace s where s.transaction_id = p_tx and s.step = 'journal') then
      perform public.fn_demo_shadow_record('journal', 'reveal_fee', 'accountant', null, j || jsonb_build_object('transaction_id', p_tx,
        'note', 'a Stripe test-mode sale: these are the lines the books would hold; nothing was posted to gl_journal'));
    end if;
    return null;
  end if;
  v_why := public.fn_gl_fixture_or_orphan(p_tx, null, null);
  if v_why like 'orphan:%' then return null; end if;
  v_jid := public.fn_gl_entry((j->>'date')::date, j->>'memo', 'reveal_fee', p_tx::text, j->'lines', 'accountant');
  update public.accountant_reveal_payment_check set journal_id = v_jid where transaction_id = p_tx;
  return v_jid;
end $fn$;
revoke execute on function public.fn_gl_post_reveal_fee(uuid) from public, anon, authenticated;


-- ══ 8. THE ACCOUNTANT'S RECONCILE OF ONE PAYMENT ══════════════════════════════════════════════════════
-- NOTHING TO BOOK (review 3, item 5; review 4, item 3): the one reason a paid sale with no reveal_fee journal may close.
-- A zero fee (nothing was charged), or the whole charge refunded before the sale was booked (no fee was earned). The
-- second is "refunded in full AND no reveal_fee journal", whether or not Stripe's figures have arrived since: before
-- review 4 it also required the card fee to be unread, so the figures arriving later, or a dispute reopening the check,
-- booked the fee as revenue on a sale fully refunded (Dr 1050 743.12 / 6100 34.48 / Cr 4000 777.60, measured locally).
-- fn_gl_post_reveal_fee posts nothing while this holds; fn_gl_sync_business books only the card fee Stripe kept.
-- Null otherwise: every other live sale without its journal stays open (trigger a10).
create or replace function public.fn_reveal_nothing_to_book(p_tx uuid)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case
    when coalesce(t.reveal_fee, 0) = 0 and coalesce(t.total_charged, 0) = 0 and coalesce(t.stripe_amount_received_fils, 0) = 0
      then 'a zero fee: nothing was charged on this reveal'
    when not exists (select 1 from public.gl_journal g where g.source = 'reveal_fee' and g.source_ref = t.id::text and g.status <> 'void')
     and coalesce(t.stripe_amount_received_fils, round(coalesce(t.total_charged, 0) * 100)::bigint) > 0
     and (select coalesce(sum(f.amount_fils), 0) from public.refunds f where f.status = 'succeeded'
           and (f.transaction_id = t.id or (f.transaction_id is null and f.stripe_payment_intent is not null and f.stripe_payment_intent = t.payment_ref)))
         >= coalesce(t.stripe_amount_received_fils, round(coalesce(t.total_charged, 0) * 100)::bigint)
      then 'refunded in full (AED ' || to_char((select sum(f.amount_fils) from public.refunds f where f.status = 'succeeded'
           and (f.transaction_id = t.id or (f.transaction_id is null and f.stripe_payment_intent is not null and f.stripe_payment_intent = t.payment_ref))) / 100.0, 'FM999,990.00')
           || ') before the sale was booked: no fee was earned'
    end
    from public.transactions t where t.id = p_tx
$fn$;
revoke execute on function public.fn_reveal_nothing_to_book(uuid) from public, anon, authenticated;

create or replace function public.fn_accountant_reconciles_reveal(p_tx uuid, p_from_handler boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; q record; c public.accountant_reveal_payment_check; v_test boolean; v_ident boolean; v_rate numeric;
  v_expected bigint; v_recorded bigint; v_charged bigint; f jsonb := '[]'::jsonb; v_waiting text; v_verdict text;
  v_inv text; v_ev jsonb; v_hid bigint; v_jid bigint; v_age interval; v_ends timestamptz; v_held bigint; v_sale jsonb;
  v_disputed boolean; v_second boolean; v_n int; v_was text; r record; v_nothing text;
begin
  -- LOCK ORDER (review 4, item 6b): one payment, one order everywhere: its advisory lock (the one fn_reveal_invoice_number
  -- takes), then its check row, then the journal's lock. Every routine that locks the check row takes this lock first.
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || p_tx::text));
  select * into t from public.transactions where id = p_tx;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no transaction ' || p_tx); end if;
  v_test := public.fn_reveal_is_test_mode(p_tx);
  v_ident := public.fn_reveal_on_test_identity(p_tx);

  -- STRIPE GAVE NO PAID TIME within 15 minutes of the sale: the clock starts at the insert, recorded as such, so the
  -- customer's receipt (reveal.paid waits for paid_at) is never held back for long.
  if t.paid_at is null and t.revealed_at is not null and t.revealed_at <= now() - interval '15 minutes' then
    update public.transactions set paid_at = least(revealed_at, now()),
           paid_at_source = 'insert_time: Stripe gave no paid time within 15 minutes'
     where id = p_tx and paid_at is null;
    select * into t from public.transactions where id = p_tx;
  end if;

  select qq.id, qq.price_ex_vat, qq.quote_amount into q from public.quotes qq where qq.id = t.quote_id;
  select standard_reveal_rate into v_rate from public.pricing_config order by id limit 1;
  v_inv := public.fn_reveal_invoice_number(p_tx);
  v_ends := public.fn_reveal_refund_window_ends(least(coalesce(t.paid_at, t.revealed_at), now()));

  insert into public.accountant_reveal_payment_check as k (transaction_id, is_test_mode, run_tag, quote_id)
  values (p_tx, v_test, case when v_test then public.fn_demo_run_tag_of(t.customer_id) end, t.quote_id)
  on conflict (transaction_id) do nothing;
  select * into c from public.accountant_reveal_payment_check where transaction_id = p_tx for update;
  v_was := c.verdict;
  -- decided already: the answer is the one recorded (idempotent for every caller)
  if c.verdict in ('matched', 'nothing_to_book') or (c.verdict = 'exception' and c.resolved_at is not null) then
    return jsonb_build_object('ok', true, 'transaction_id', p_tx, 'verdict', c.verdict, 'findings', c.findings,
      'our_invoice_no', c.our_invoice_no, 'journal_id', c.journal_id, 'decided_by', c.decided_by, 'already', true);
  end if;

  -- NOTHING TO BOOK: a terminal end state, with its reason, written to the CEO's task list as done (review 3, item 5);
  -- no longer read from Stripe every hour and no longer listed as "not yet booked"
  v_nothing := public.fn_reveal_nothing_to_book(p_tx);
  -- an open card dispute on it is still the CEO's to hear (review 4, item 3): the check goes on below as an exception,
  -- and fn_gl_post_reveal_fee books no revenue for it
  if v_nothing is not null and not exists (select 1 from public.stripe_dispute d
       where (d.transaction_id = p_tx or (t.payment_ref is not null and d.payment_intent = t.payment_ref)) and coalesce(d.status, '') not in ('won')) then
    update public.accountant_reveal_payment_check
       set verdict = 'nothing_to_book', is_test_mode = v_test, our_invoice_no = v_inv, payment_ref = t.payment_ref, paid_at = t.paid_at,
           checked_at = now(), decided_by = 'code', resolved_at = now(), resolution = 'nothing to book: ' || v_nothing
     where transaction_id = p_tx;
    if v_test then
      perform public.fn_demo_shadow_record('reconcile', 'reveal.reconcile', 'sales_engineer', 'accountant',
        jsonb_build_object('transaction_id', p_tx, 'verdict', 'nothing_to_book', 'reason', v_nothing));
    else
      insert into public.ceo_task (title, detail, state, evidence, closed_at)
      select 'Nothing to book on reveal ' || left(p_tx::text, 8),
             'The accountant closed the payment check of reveal ' || p_tx || ' with nothing to book: ' || v_nothing || '.',
             'done', 'accountant (code): ' || v_nothing || ' (accountant_reveal_payment_check ' || p_tx || ')', now()
       where not exists (select 1 from public.ceo_task k where k.title = 'Nothing to book on reveal ' || left(p_tx::text, 8));
      for r in select a.id from public.agent_actions a
                where a.kind = 'handoff' and a.detail->>'type' = 'payment.exception' and a.detail->>'transaction_id' = p_tx::text and a.status <> 'done' loop
        perform public.fn_seat_handoff_complete(r.id, jsonb_build_object('resolved_by', 'accountant (code)', 'reply', 'Nothing to book: ' || v_nothing || '.'));
      end loop;
      if not p_from_handler then
        select a.id into v_hid from public.agent_actions a
         where a.kind = 'handoff' and a.agent = 'accountant' and a.target_id = 'reveal.reconcile:' || p_tx::text and a.status <> 'done' order by a.id limit 1;
        if v_hid is not null then begin perform public.fn_seat_handoff_act(v_hid); exception when others then null; end; end if;
      end if;
    end if;
    return jsonb_build_object('ok', true, 'transaction_id', p_tx, 'verdict', 'nothing_to_book', 'reason', v_nothing, 'our_invoice_no', v_inv);
  end if;

  -- THE FEE. 3% of the quotation EXCLUDING VAT (founder 1687), to the fils, rounded half-up as public.reveal_fee does.
  v_expected := case when q.price_ex_vat is not null and v_rate is not null then round(q.price_ex_vat * v_rate * 100)::bigint end;
  v_recorded := round(coalesce(t.reveal_fee, 0) * 100)::bigint;
  v_charged  := coalesce(t.stripe_amount_received_fils, round(coalesce(t.total_charged, 0) * 100)::bigint);

  if t.stripe_fee_fils is null or t.stripe_amount_received_fils is null then
    v_waiting := 'Stripe''s charge and balance transaction are not read yet';
  elsif t.livemode is null then
    v_waiting := 'Stripe''s mode (live or test) is not known yet';
  end if;

  if q.id is null then f := f || jsonb_build_array(jsonb_build_object('code', 'no_quote', 'fact', 'the quote this payment names no longer exists'));
  else
    if q.price_ex_vat is null or q.quote_amount is distinct from q.price_ex_vat then
      f := f || jsonb_build_array(jsonb_build_object('code', 'fee_base_not_ex_vat', 'fact',
        'quotes.quote_amount ' || coalesce(q.quote_amount::text, 'null') || ' is not price_ex_vat ' || coalesce(q.price_ex_vat::text, 'null')
        || ': the fee base must be the quotation excluding VAT'));
    end if;
    if v_expected is not null and v_recorded <> v_expected then
      f := f || jsonb_build_array(jsonb_build_object('code', 'fee_not_three_percent_ex_vat', 'fact',
        'the sale recorded a fee of ' || v_recorded || ' fils; 3% of ' || q.price_ex_vat || ' ex-VAT is ' || v_expected || ' fils'));
    end if;
  end if;
  if v_ident then
    f := f || jsonb_build_array(jsonb_build_object('code', 'live_payment_on_test_identity', 'fact',
      'a LIVE Stripe payment touches a customer, supplier, quote or request flagged as demo: it is booked as a real payment, and somebody must find out who paid'));
  end if;
  if v_waiting is null then
    if v_expected is not null and v_charged > v_expected then
      f := f || jsonb_build_array(jsonb_build_object('code', 'charged_above_fee', 'fact',
        'the customer was charged ' || v_charged || ' fils, ' || (v_charged - v_expected) || ' fils above the fee of ' || v_expected, 'over_fils', v_charged - v_expected));
    elsif v_expected is not null and v_charged < v_expected then
      f := f || jsonb_build_array(jsonb_build_object('code', 'charged_below_fee', 'fact',
        'the customer was charged ' || v_charged || ' fils, below the fee of ' || v_expected));
    end if;
    if t.stripe_bt_amount_fils is not null and t.stripe_bt_amount_fils <> t.stripe_amount_received_fils then
      f := f || jsonb_build_array(jsonb_build_object('code', 'balance_transaction_differs', 'fact',
        'the balance transaction is ' || t.stripe_bt_amount_fils || ' fils, the PaymentIntent received ' || t.stripe_amount_received_fils));
    end if;
    if lower(coalesce(t.stripe_bt_currency, t.stripe_invoice_currency, 'aed')) <> 'aed' then
      f := f || jsonb_build_array(jsonb_build_object('code', 'not_aed', 'fact', 'the payment settled in ' || coalesce(t.stripe_bt_currency, t.stripe_invoice_currency)));
    end if;
  end if;
  if coalesce(t.processing_fee, 0) <> 0 then
    f := f || jsonb_build_array(jsonb_build_object('code', 'charged_more_than_the_fee', 'fact',
      'a processing fee of AED ' || t.processing_fee || ' was charged on top of the fee (Cabinet Res. 66/2023 Art. 5(3): no card surcharge)'));
  end if;
  if t.stripe_invoice_total_fils is not null and v_expected is not null and t.stripe_invoice_total_fils <> v_expected then
    f := f || jsonb_build_array(jsonb_build_object('code', 'invoice_total_differs', 'fact',
      'Stripe''s invoice total is ' || t.stripe_invoice_total_fils || ' fils, the fee is ' || v_expected));
  end if;
  v_second := exists (select 1 from public.accountant_reveal_reconcile_item i where i.quote_id = t.quote_id::text and i.outcome = 'second_payment' and i.resolved_at is null)
           or exists (select 1 from public.it_engineer_finding fi where fi.issue_key like 'reveal:second_payment:%' and fi.evidence->>'transaction_id' = p_tx::text and fi.closed_at is null);
  if v_second then f := f || jsonb_build_array(jsonb_build_object('code', 'second_payment', 'fact', 'the same quote was paid a second time; one payment is one reveal')); end if;
  v_disputed := exists (select 1 from public.stripe_dispute d where (d.transaction_id = p_tx or (t.payment_ref is not null and d.payment_intent = t.payment_ref)) and coalesce(d.status, '') not in ('won'));
  if v_disputed then f := f || jsonb_build_array(jsonb_build_object('code', 'disputed', 'fact', 'the customer''s bank opened a card dispute on this payment')); end if;
  if coalesce(t.refund_status, '') in ('refunded', 'refund_approved', 'succeeded') and c.ceo_decision is distinct from 'refund_difference' then
    f := f || jsonb_build_array(jsonb_build_object('code', 'refunded', 'fact', 'the payment was refunded (' || t.refund_status || ', AED ' || coalesce(t.refund_amount_aed::text, '?') || ')'));
  end if;

  v_age := now() - least(coalesce(t.paid_at, t.revealed_at, c.opened_at), now());
  if jsonb_array_length(f) > 0 then v_verdict := 'exception';
  elsif v_waiting is not null and v_age > interval '1 hour' then
    v_verdict := 'exception';
    f := f || jsonb_build_array(jsonb_build_object('code', 'facts_unreadable', 'fact', v_waiting || ' an hour after the payment'));
  elsif v_waiting is not null then v_verdict := 'waiting_for_facts';
  else v_verdict := 'matched';
  end if;

  -- the books hold whatever happened once Stripe's figures are in (an overcharge sits in 2300 until it is returned);
  -- posted BEFORE the check is marked, so a matched live check is never resolved without its journal
  if v_waiting is null then v_jid := public.fn_gl_post_reveal_fee(p_tx); end if;

  update public.accountant_reveal_payment_check set
    journal_id = coalesce(v_jid, journal_id), is_test_mode = v_test, on_test_identity = v_ident, our_invoice_no = v_inv, stripe_invoice_id = t.stripe_invoice_id,
    stripe_invoice_number = t.stripe_invoice_number, payment_ref = t.payment_ref, price_ex_vat = q.price_ex_vat,
    quote_amount = q.quote_amount, rate = v_rate, expected_fee_fils = v_expected, recorded_fee_fils = v_recorded,
    charged_fils = v_charged, invoice_total_fils = t.stripe_invoice_total_fils, amount_received_fils = t.stripe_amount_received_fils,
    bt_amount_fils = t.stripe_bt_amount_fils, bt_fee_fils = t.stripe_fee_fils,
    currency = lower(coalesce(t.stripe_bt_currency, t.stripe_invoice_currency, 'aed')), paid_at = t.paid_at,
    refund_window_ends_at = coalesce(t.refund_deadline, v_ends), findings = f, verdict = v_verdict, checked_at = now(),
    decided_by = case when v_verdict = 'matched' then 'code' else decided_by end,
    resolved_at = case when v_verdict = 'matched' then now() else resolved_at end,
    resolution = case when v_verdict = 'matched' and v_was = 'exception' then 'resolved by code: Stripe''s figures arrived and match'
                      when v_verdict = 'matched' then 'straight match: booked and reported by code' else resolution end
   where transaction_id = p_tx
  returning * into c;


  v_ev := jsonb_build_object('reconciled_by', 'accountant (code)', 'transaction_id', p_tx, 'verdict', v_verdict,
    'test_mode', v_test, 'our_invoice_no', v_inv, 'stripe_invoice_number', t.stripe_invoice_number, 'payment_ref', t.payment_ref,
    'expected_fee_fils', v_expected, 'charged_fils', v_charged, 'card_fee_fils', t.stripe_fee_fils,
    'price_ex_vat', round(q.price_ex_vat, 2), 'rate', v_rate::text, 'currency', c.currency, 'paid_at', t.paid_at, 'paid_at_source', t.paid_at_source,
    'refund_window_ends_at', c.refund_window_ends_at, 'findings', f, 'journal_id', v_jid);

  if v_test then
    perform public.fn_demo_shadow_record('reconcile', 'reveal.reconcile', 'sales_engineer', 'accountant', v_ev);
    if not exists (select 1 from public.demo_shadow_trace s where s.transaction_id = p_tx and s.step = 'window_clock') and t.paid_at is not null then
      perform public.fn_demo_shadow_record('window_clock', 'refund_window', 'accountant', null, jsonb_build_object('transaction_id', p_tx,
        'paid_at', t.paid_at, 'paid_at_source', t.paid_at_source, 'revealed_at', t.revealed_at, 'refund_deadline', t.refund_deadline,
        'counted_from', 'paid_at (fn_reveal_refund_window_ends: 23:59:59 Asia/Dubai of the 5th working day)', 'ends_at', v_ends));
    end if;
  end if;

  if v_verdict = 'matched' then
    -- THE BOOKS FIRST (review 2, item 1): the check and the journal are written above; a notice that fails is a finding
    -- and is retried by the sweep (sale_notice_at stays empty), never a reason to undo the books.
    begin
      v_sale := public.fn_accountant_tells_ceo_of_sale(p_tx);
      update public.accountant_reveal_payment_check set sale_notice_at = now() where transaction_id = p_tx;
    exception when others then
      v_sale := jsonb_build_object('failed', left(sqlerrm, 300));
      perform public.fn_it_engineer_finding_upsert(p_issue_key => 'reveal:sale_notice_failed:' || p_tx,
        p_title => 'The CEO could not be told of a sale (sale.made refused): ' || left(sqlerrm, 150), p_where => 'public.fn_accountant_tells_ceo_of_sale',
        p_blast => 'internal', p_affected => 1, p_evidence => jsonb_build_object('transaction_id', p_tx, 'error', left(sqlerrm, 500), 'owner_seat', 'accountant'),
        p_raised_by => 'accountant');
    end;
    v_ev := v_ev || jsonb_build_object('sale_made', v_sale);
    -- an exception Stripe's late figures answered: its open handoffs are closed with that answer
    if v_was = 'exception' and not v_test then
      for r in select a.id from public.agent_actions a
                where a.kind = 'handoff' and a.detail->>'type' = 'payment.exception' and a.detail->>'transaction_id' = p_tx::text and a.status <> 'done' loop
        perform public.fn_seat_handoff_complete(r.id, jsonb_build_object('resolved_by', 'accountant (code)',
          'reply', 'Stripe''s figures arrived and the payment reconciles: nothing is owed and nothing is left to decide.'));
      end loop;
    end if;
  elsif v_verdict = 'exception' and c.held_question_id is null and c.ceo_handoff_id is null then
    -- JUDGED, NOT CODED: the accountant's model path decides what to do about it. A NEW OCCURRENCE each time (review
    -- item 5): the dedupe keys carry the count, so a second exception on one payment is asked and handed again.
    v_n := c.exception_count + 1;
    begin
    v_held := public.fn_seat_duty_reason('accountant', 'accountant.payment_exception',
      'A reveal payment did not reconcile. Decide what the accountant does. The fee is 3% of the quotation excluding VAT, '
      || 'the customer is charged the fee and nothing else, one payment is one reveal. Every refund, an overcharge included, '
      || 'is decided by the CEO (ceo_standing_grant accountant.refund_decision: max AED 0) unless a standing grant '
      || 'overcharge_return covers it: the accountant recommends, the CEO decides.',
      ('[{"id":"recommend_refund_difference","meaning":"the customer paid money that is not the fee (above the fee, a second payment, a surcharge): recommend to the CEO that exactly the difference is returned, naming the amount"},'
      || '{"id":"escalate_to_ceo","meaning":"the facts need a decision beyond the accountant''s authority (a dispute, a refund, a missing quote, a wrong fee base, a live payment on a demo identity): hand the CEO the facts and the accountant''s view"},'
      || '{"id":"recheck_within_the_hour","meaning":"Stripe has not yet given the facts (the charge or the invoice is not final); read them again within the hour. Unresolved, it goes to the CEO anyway at 45 minutes"}]')::jsonb,
      v_ev || jsonb_build_object('occurrence', v_n), jsonb_build_object('transaction_id', p_tx, 'check', 'accountant_reveal_payment_check',
                               'occurrence', v_n, 'test_mode', v_test, 'fixture', v_test), 'payment_exception:' || p_tx || ':' || v_n);
    exception when others then v_held := null;   -- the sweep escalates an unjudged exception at 45 minutes anyway
    end;
    update public.accountant_reveal_payment_check set held_question_id = coalesce(v_held, -1), exception_count = v_n,
           opened_at = case when v_n > 1 then now() else opened_at end
     where transaction_id = p_tx;
    if v_test then perform public.fn_demo_shadow_record('model_question', 'accountant.payment_exception', 'accountant', 'accountant',
      jsonb_build_object('transaction_id', p_tx, 'held_question_id', v_held, 'occurrence', v_n, 'findings', f,
        'note', 'a test-mode payment is never sent to a paid model (fn_reason_hold files nothing for a fixture)')); end if;
    v_ev := v_ev || jsonb_build_object('held_question_id', v_held, 'occurrence', v_n, 'judged_by', 'the accountant''s model (accountant.payment_exception)');
  end if;

  -- the sales engineer's reveal.reconcile: closed with the verdict when it is final; an exception keeps it open until
  -- the CEO decides (fn_reason_apply_ceo__payment_exception closes it)
  if not p_from_handler and not v_test then
    select a.id into v_hid from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'accountant' and a.target_id = 'reveal.reconcile:' || p_tx::text and a.status <> 'done'
     order by a.id limit 1;
    if v_hid is not null then
      update public.accountant_reveal_payment_check set reconcile_handoff_id = v_hid where transaction_id = p_tx;
      if v_verdict <> 'waiting_for_facts' then begin perform public.fn_seat_handoff_act(v_hid); exception when others then null; end; end if;
    end if;
  end if;
  return jsonb_build_object('ok', true) || v_ev;
end $fn$;
revoke execute on function public.fn_accountant_reconciles_reveal(uuid, boolean) from public, anon, authenticated;
grant execute on function public.fn_accountant_reconciles_reveal(uuid, boolean) to service_role;

-- A LIVE CHECK CANNOT RESOLVE WHILE THE SALE IS NOT BOOKED (review 2, item 5; coordinator's ruling): whatever the CEO
-- answered, it stays open, is read from Stripe again every hour and is listed in the founder's brief every day as
-- "paid, not yet booked: waiting for Stripe's figures since <date>". No invented figure enters the books.
create or replace function public.trg_payment_check_stays_open_until_booked()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  -- the one way out without a journal: nothing to book (a zero fee, or refunded in full before the sale was booked),
  -- recorded as the verdict or, for a check a dispute reopened, read from the sale itself
  if NEW.resolved_at is not null and not NEW.is_test_mode and NEW.verdict is distinct from 'nothing_to_book'
     and public.fn_reveal_nothing_to_book(NEW.transaction_id) is null
     and exists (select 1 from public.transactions t where t.id = NEW.transaction_id and t.fee_status = 'paid' and coalesce(t.livemode, true))
     and not exists (select 1 from public.gl_journal g where g.source = 'reveal_fee' and g.source_ref = NEW.transaction_id::text and g.status <> 'void') then
    NEW.resolution := left(coalesce(NEW.resolution, '') || ' | stays open: the sale is not booked yet (waiting for Stripe''s figures)', 1000);
    NEW.resolved_at := null;
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_payment_check_stays_open_until_booked() from public, anon, authenticated;
create or replace trigger a10_payment_check_stays_open_until_booked before insert or update of resolved_at, verdict on public.accountant_reveal_payment_check
  for each row execute function public.trg_payment_check_stays_open_until_booked();

-- The handler of reveal.reconcile (sales_engineer -> accountant).
create or replace function public.fn_accountant_reconciles_reveal_handoff(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v jsonb; v_tx uuid;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_tx := (a.detail->>'transaction_id')::uuid;
  v := public.fn_accountant_reconciles_reveal(v_tx, true);
  update public.accountant_reveal_payment_check set reconcile_handoff_id = p_id where transaction_id = v_tx and reconcile_handoff_id is null;
  if v->>'verdict' = 'waiting_for_facts' then
    return v || jsonb_build_object('waiting', 'Stripe''s charge and balance transaction; stripe_webhook reads them and the accountant''s hourly reconcile reads them again');
  elsif v->>'verdict' = 'exception' then
    return v || jsonb_build_object('waiting', 'the accountant''s judgement and the CEO''s decision on the payment exception');
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_accountant_reconciles_reveal_handoff(bigint) from public, anon, authenticated;

-- What the accountant's runtime must read from Stripe again (review item 4): checks still waiting, unreadable, or
-- under investigation, oldest first. The runtime writes the facts and a snapshot and reconciles again.
create or replace function public.fn_accountant_payment_checks_to_read(p_limit integer default 25)
returns table(transaction_id uuid, payment_ref text, stripe_invoice_id text, livemode boolean, reason text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- livemode NULL = unknown: the runtime tries the live key, then the test key, and writes what Stripe says.
  -- A LIVE sale with no reveal_fee journal is read again every hour whatever its check says (review 2, item 5).
  -- A SALE REFUNDED IN FULL BEFORE STRIPE'S CARD FEE WAS READ (review 5, item 2) closes nothing_to_book, but the fee
  -- Stripe kept is still a cost: fn_gl_sync_business 1b books it (6100 / 1050) only from stripe_fee_fils and waits while
  -- it is unknown. Such a check was never listed again, so the fee was never read and 1050 stayed overstated by it with no
  -- finding. It is now read again while the sale is live, charged something and its fee is unknown; once the fee is
  -- written it drops off the list and the next gl sync books it once.
  select k.transaction_id, t.payment_ref, t.stripe_invoice_id, t.livemode,
         case when t.livemode is null then 'mode_unknown'
              when k.verdict = 'nothing_to_book' then 'refunded_fee_unread'
              when k.investigate_requested_at is not null and (k.stripe_read_at is null or k.stripe_read_at < k.investigate_requested_at) then 'investigate'
              when k.verdict = 'waiting_for_facts' then 'waiting'
              when t.livemode and not exists (select 1 from public.gl_journal g where g.source = 'reveal_fee' and g.source_ref = t.id::text and g.status <> 'void') then 'live_not_booked'
              else 'facts_unreadable' end
    from public.accountant_reveal_payment_check k join public.transactions t on t.id = k.transaction_id
   where (k.verdict <> 'nothing_to_book' and (t.livemode is null
      or (k.resolved_at is null
          and (k.verdict = 'waiting_for_facts'
               or k.findings @> '[{"code":"facts_unreadable"}]'::jsonb
               or (k.investigate_requested_at is not null and (k.stripe_read_at is null or k.stripe_read_at < k.investigate_requested_at))))
      or (t.livemode and t.fee_status = 'paid'
          and not exists (select 1 from public.gl_journal g where g.source = 'reveal_fee' and g.source_ref = t.id::text and g.status <> 'void'))))
      or (k.verdict = 'nothing_to_book' and t.livemode and t.stripe_fee_fils is null and coalesce(t.total_charged, 0) > 0)
   order by k.opened_at
   limit greatest(1, least(coalesce(p_limit, 25), 100))
$fn$;
revoke execute on function public.fn_accountant_payment_checks_to_read(integer) from public, anon, authenticated;
grant execute on function public.fn_accountant_payment_checks_to_read(integer) to service_role;

-- The runtime's read of Stripe for one check: the snapshot is kept as evidence, then the check runs again.
create or replace function public.fn_accountant_payment_check_snapshot(p_tx uuid, p_snapshot jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  -- LOCK ORDER (review 4, item 6b): the payment's advisory lock BEFORE its check row, as every path does (the reconcile
  -- takes it in fn_reveal_invoice_number before it locks the row; taken the other way here it deadlocked the webhook)
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || p_tx::text));
  update public.accountant_reveal_payment_check set stripe_snapshot = p_snapshot, stripe_read_at = now() where transaction_id = p_tx;
  return public.fn_accountant_reconciles_reveal(p_tx);
end $fn$;
revoke execute on function public.fn_accountant_payment_check_snapshot(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.fn_accountant_payment_check_snapshot(uuid, jsonb) to service_role;


-- ══ 9. THE CEO IS TOLD OF EACH SALE ═══════════════════════════════════════════════════════════════════
-- The month's revenue, live sales only: the fee, less what was refunded of the fee (an overcharge returned is not revenue).
create or replace function public.fn_reveal_month_revenue(p_at timestamptz default now())
returns table(revenue_aed numeric, sales integer) language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- ROUNDED TO THE FILS (review 2, item 1): fils/100.0 has scale 20, and 135.00000000000000000000 in a handoff payload was
  -- turned into "[phone]" by fn_handoff_redact's phone pattern, which broke the JSON and rolled the whole reconcile back
  select round(coalesce(sum(greatest(x.reveal_fee - greatest(coalesce(x.refunded, 0) - x.over_aed, 0), 0)), 0), 2), count(*)::int
    from (select t.reveal_fee,
                 round(greatest(coalesce(t.stripe_amount_received_fils / 100.0, t.total_charged, t.reveal_fee) - t.reveal_fee, 0), 2) as over_aed,
                 -- a partial refund is taken off too (review 5, item 1: the sale says 'partly_refunded' with the sum)
                 case when coalesce(t.refund_status, '') in ('refunded', 'succeeded', 'refund_approved') then round(coalesce(t.refund_amount_aed, t.total_charged), 2)
                      when t.refund_status = 'partly_refunded' then round(coalesce(t.refund_amount_aed, 0), 2) end as refunded
            from public.transactions t
           where t.fee_status = 'paid' and t.livemode
             and least(coalesce(t.paid_at, t.revealed_at), now()) >= (date_trunc('month', p_at at time zone 'Asia/Dubai')) at time zone 'Asia/Dubai'
             and least(coalesce(t.paid_at, t.revealed_at), now()) < ((date_trunc('month', p_at at time zone 'Asia/Dubai') + interval '1 month') at time zone 'Asia/Dubai')) x
$fn$;
revoke execute on function public.fn_reveal_month_revenue(timestamptz) from public, anon, authenticated;

create or replace function public.fn_accountant_tells_ceo_of_sale(p_tx uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; i record; cu record; v_test boolean; m record; v_p jsonb; v_hid bigint;
begin
  select * into t from public.transactions where id = p_tx;
  if not found then return null; end if;
  v_test := public.fn_reveal_is_test_mode(p_tx);
  select ii.summary_masked, ii.summary, ii.category, ii.trades, ii.emirate, ii.scope_type into i from public.inquiries ii where ii.id = t.inquiry_id;
  select cc.industry into cu from public.customers cc where cc.id = t.customer_id;
  select * into m from public.fn_reveal_month_revenue(now());
  v_p := jsonb_build_object('transaction_id', p_tx, 'quote_id', t.quote_id, 'inquiry_id', t.inquiry_id, 'customer_id', t.customer_id,
    'what_was_sold', 'the reveal of the chosen supplier''s contact for: ' || coalesce(i.summary_masked, i.summary, i.category, 'a request'),
    'fee_aed', round(t.reveal_fee, 2), 'quotation_ex_vat_aed', round(t.quote_amount, 2), 'trade', coalesce(i.category, array_to_string(i.trades, ', ')),
    'emirate', i.emirate, 'customer_type', coalesce(cu.industry, i.scope_type, 'not recorded'),
    'our_invoice_no', (select invoice_no from public.reveal_invoices where transaction_id = p_tx),
    'paid_at', t.paid_at, 'refund_window_ends_at', t.refund_deadline,
    'month_total_aed', m.revenue_aed, 'sales_this_month', m.sales, 'test_mode', v_test,
    'note', case when v_test then 'a Stripe test-mode sale: not counted in the month total' end);
  if v_test then
    if not exists (select 1 from public.demo_shadow_trace s where s.transaction_id = p_tx and s.step = 'ceo_notice') then
      perform public.fn_demo_shadow_record('ceo_notice', 'sale.made', 'accountant', 'ceo', v_p);
    end if;
    return v_p || jsonb_build_object('shadow', true);
  end if;
  v_hid := public.fn_seat_handoff('accountant', 'ceo', 'sale.made', 'transactions', p_tx::text, v_p);
  return v_p || jsonb_build_object('handoff_id', v_hid);
end $fn$;
revoke execute on function public.fn_accountant_tells_ceo_of_sale(uuid) from public, anon, authenticated;

-- The CEO's handler for sale.made: recorded and answered with what it now knows (the running month).
create or replace function public.fn_ceo_reads_sale_made(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('read_by', 'ceo', 'sale', a.detail->>'transaction_id', 'fee_aed', a.detail->'fee_aed',
    'month_total_aed', a.detail->'month_total_aed', 'sales_this_month', a.detail->'sales_this_month',
    'reply', 'ceo: sale recorded; month to date AED ' || coalesce(a.detail->>'month_total_aed', '?') || ' from '
             || coalesce(a.detail->>'sales_this_month', '?') || ' sale(s). It is in tonight''s founder brief.');
end $fn$;
revoke execute on function public.fn_ceo_reads_sale_made(bigint) from public, anon, authenticated;

-- ══ 10. THE EXCEPTION: JUDGED, DECIDED, AND TAKEN TO ITS END ═════════════════════════════════════════
-- The money owed back on a check: anything charged above the fee, else a second payment's amount.
create or replace function public.fn_payment_check_owed_back(p_tx uuid)
returns table(amount_fils bigint, payment_intent text, why text) language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with k as (select * from public.accountant_reveal_payment_check where transaction_id = p_tx),
  over as (select coalesce(sum((x->>'over_fils')::bigint), 0) as f from k, jsonb_array_elements(k.findings) x where x ? 'over_fils'),
  second as (select i.amount_fils, i.payment_intent from public.accountant_reveal_reconcile_item i, k
              where i.quote_id = k.quote_id::text and i.outcome = 'second_payment' and i.resolved_at is null order by i.first_seen_at limit 1)
  select case when (select f from over) > 0 then (select f from over) else (select amount_fils from second) end,
         case when (select f from over) > 0 then (select payment_ref from k) else (select payment_intent from second) end,
         case when (select f from over) > 0 then 'charged above the fee' when exists (select 1 from second) then 'a second payment for the same reveal' else 'nothing owed back' end
$fn$;
revoke execute on function public.fn_payment_check_owed_back(uuid) from public, anon, authenticated;

-- One occurrence of an exception reaches the CEO and the sales engineer (numbered: a later one reaches them again) and,
-- in the same call, the FOUNDER: fn_notify_founder, kind finance_alert (e-mail and WhatsApp). He is told, never asked:
-- the decision is the CEO's (founder, 8 Sep 2026). A test-mode payment's escalation goes to the shadow only.
create or replace function public.fn_accountant_escalates_payment_exception(p_tx uuid, p_by text, p_choice text, p_reason text, p_final boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.accountant_reveal_payment_check; t public.transactions; v_p jsonb; v_ceo bigint; v_se bigint; o record; v_n int; v_f jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || p_tx::text));   -- lock order: item 6b
  select * into c from public.accountant_reveal_payment_check where transaction_id = p_tx for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no check for ' || p_tx); end if;
  if c.ceo_handoff_id is not null then return jsonb_build_object('ok', true, 'already', c.ceo_handoff_id); end if;
  select * into t from public.transactions where id = p_tx;
  select * into o from public.fn_payment_check_owed_back(p_tx);
  v_n := greatest(c.exception_count, 1);
  v_p := jsonb_build_object('transaction_id', p_tx, 'quote_id', t.quote_id, 'inquiry_id', t.inquiry_id, 'customer_id', t.customer_id,
    'occurrence', v_n, 'final', p_final, 'findings', c.findings, 'accountant_choice', p_choice,
    'accountant_reason', left(coalesce(p_reason, ''), 2000), 'decided_by', p_by,
    'owed_back_fils', nullif(o.amount_fils, 0), 'owed_back_why', o.why,
    'our_invoice_no', c.our_invoice_no, 'stripe_invoice_number', c.stripe_invoice_number, 'payment_ref', c.payment_ref,
    'expected_fee_fils', c.expected_fee_fils, 'charged_fils', c.charged_fils, 'opened_at', c.opened_at,
    'stripe_snapshot', c.stripe_snapshot);
  if c.is_test_mode then
    perform public.fn_demo_shadow_record('handoff', 'payment.exception', 'accountant', 'ceo', v_p);
    perform public.fn_demo_shadow_record('handoff', 'payment.exception', 'accountant', 'sales_engineer', v_p);
    perform public.fn_demo_shadow_record('escalation', 'payment.exception', 'accountant', 'ceo', v_p);
  else
    v_ceo := public.fn_seat_handoff('accountant', 'ceo', 'payment.exception', 'transactions', p_tx::text || '#' || v_n, v_p);
    v_se  := public.fn_seat_handoff('accountant', 'sales_engineer', 'payment.exception', 'transactions', p_tx::text || '#' || v_n, v_p);
    v_f := public.fn_notify_founder(
      'Payment exception on reveal ' || left(p_tx::text, 8) || coalesce(': AED ' || to_char(nullif(o.amount_fils, 0) / 100.0, 'FM999,990.00') || ' ' || o.why, ''),
      'A reveal payment did not reconcile and is with the CEO now (' || coalesce(p_choice, '?') || ', by ' || coalesce(p_by, '?') || ').' || E'\n'
      || 'Findings: ' || coalesce((select string_agg(x->>'fact', '; ') from jsonb_array_elements(c.findings) x), 'none') || E'\n'
      || 'Invoice ' || coalesce(c.our_invoice_no, '?') || ', payment ' || coalesce(c.payment_ref, '?') || '. Nothing is refunded without the CEO''s decision.',
      'high', 'finance_alert', 'payment_exception:' || p_tx || ':' || v_n, 'accountant');
  end if;
  update public.accountant_reveal_payment_check
     set decided_by = p_by, decision = p_choice, decision_reason = left(coalesce(p_reason, ''), 2000),
         escalated_at = now(), final_question = p_final, ceo_handoff_id = coalesce(v_ceo, -1)
   where transaction_id = p_tx;
  return jsonb_build_object('ok', true, 'ceo_handoff_id', v_ceo, 'sales_engineer_handoff_id', v_se, 'founder', v_f, 'choice', p_choice, 'occurrence', v_n);
end $fn$;
revoke execute on function public.fn_accountant_escalates_payment_exception(uuid, text, text, text, boolean) from public, anon, authenticated;

-- The difference is returned through the EXISTING refund path (fn_refund_request: refunds row, the CEO's refund task,
-- the CEO's approval, fn_refund_decide, the accountant's executor, Stripe, fn_refund_settle). Review 3, item 1:
--   * the CEO's "Decide refund" task is closed, and the customer told, ONLY once the decision succeeded AND the refund is
--     actually submitted to Stripe (refunds.stripe_refund_id): trigger z59 on refunds does both, at that moment;
--   * any failure (the decision refused, or Stripe failing or cancelling it) sets that task to 'blocked' with the reason
--     and hands the check back to the CEO as a new occurrence (fn_payment_check_return_blocked).
create or replace function public.fn_payment_check_returns_difference(p_tx uuid, p_by text, p_rationale text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.accountant_reveal_payment_check; t public.transactions; o record; v_r jsonb; v_id bigint; v_dec bigint; v_fin jsonb;
        v_task bigint; v_why text;
begin
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || p_tx::text));   -- lock order: item 6b
  select * into c from public.accountant_reveal_payment_check where transaction_id = p_tx for update;
  select * into t from public.transactions where id = p_tx;
  select * into o from public.fn_payment_check_owed_back(p_tx);
  if coalesce(o.amount_fils, 0) <= 0 then return jsonb_build_object('ok', false, 'reason', 'nothing is owed back on this payment'); end if;
  if c.refund_id is not null then return jsonb_build_object('ok', true, 'already', c.refund_id); end if;
  -- ONE DECISION AT A TIME (review 4, item 6a): a new decision on this payment closes the task an earlier return left
  -- 'blocked', so the CEO has one open task per payment, the new one
  update public.ceo_task set state = 'done', closed_at = now(),
         evidence = left('Superseded: the CEO decided again on the accountant''s payment check ' || p_tx || ' (' || coalesce(p_by, '?') || ')', 1000)
   where state = 'blocked' and blocked_reason like '%payment check ' || p_tx::text || '%';
  -- ONE STEP: the request, the decision made on the check (it IS the approval of this refund, the same record
  -- fn_ceo_refund_review writes), then fn_refund_decide (no window and no second seat for an overcharge return; the CEO's
  -- approval is required). The request is inside the block (review 4, item 4): a guard that refuses it (a00, e.g. no
  -- Stripe reference) is a refusal handed back to the CEO below, never an error that loses the CEO's decision.
  begin
    v_r := public.fn_refund_request(o.amount_fils, 'overcharge_return', p_by, t.inquiry_id, t.customer_id, t.supplier_id, t.quote_id,
             o.payment_intent, null, left('Return exactly the money that is not the fee (' || o.why || '): decided by ' || p_by || '. ' || coalesce(p_rationale, ''), 1000), p_tx);
    v_id := nullif(v_r->>'refund_id', '')::bigint;
    v_task := nullif(v_r->>'ceo_task_id', '')::bigint;
    update public.accountant_reveal_payment_check set refund_id = v_id, refund_ceo_task_id = v_task, refund_submitted_at = null
     where transaction_id = p_tx;
    if v_id is null then raise exception 'the refund path made no refund: %', coalesce(v_r->>'error', v_r::text); end if;
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', v_id::text, 'approved', 'ceo', round(o.amount_fils / 100.0, 2),
            left('Overcharge return decided on the accountant''s payment check by ' || p_by || ': ' || o.why || '. ' || coalesce(p_rationale, ''), 3000))
    returning decision_id into v_dec;
    update public.refunds set refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now(),
           decision_note = 'overcharge return, decided on payment check ' || p_tx where id = v_id;
    v_fin := public.fn_refund_decide(v_id, true, 'ceo', 'overcharge return decided on payment check ' || p_tx);
    -- ceo_approval.decided_by is a CEO identity (FK ceo_identity): under the accountant's standing grant the record still
    -- names the CEO, whose grant it is; the refunds row names who acted (p_by)
    if coalesce((v_fin->>'ok')::boolean, false) and p_by <> 'ceo' then update public.refunds set decided_by = p_by where id = v_id; end if;
  exception when others then
    v_fin := jsonb_build_object('ok', false, 'error', left(sqlerrm, 300));
    -- the block rolled back whatever it wrote: a refund (and its task) it made no longer exists
    if v_id is not null and not exists (select 1 from public.refunds where id = v_id) then v_id := null; v_task := null; end if;
  end;
  if v_id is null or not coalesce((v_fin->>'ok')::boolean, false) then
    v_why := 'the decision on refund ' || coalesce(v_id::text, '?') || ' did not go through: '
             || coalesce(v_fin->>'error', v_r->>'error', 'no refund was created') || coalesce(' (' || (v_fin->'clearance'->>'state') || ')', '');
    return jsonb_build_object('ok', false, 'refund', v_r, 'decide', v_fin,
                              'blocked', public.fn_payment_check_return_blocked(p_tx, v_id, v_why));
  end if;
  update public.ceo_task set state = 'working' where task_id = v_task and state = 'open';
  update public.accountant_reveal_payment_check
     set resolution = 'return of AED ' || to_char(o.amount_fils / 100.0, 'FM999,990.00') || ' approved (refund ' || v_id
                      || '); waiting for the accountant to submit it to Stripe, then for Stripe to confirm it'
   where transaction_id = p_tx;
  return jsonb_build_object('ok', true, 'refund', v_r, 'approval', v_dec, 'decide', v_fin,
    'awaiting', 'the accountant''s executor submits it to Stripe; the CEO''s task closes and the customer is told then');
end $fn$;
revoke execute on function public.fn_payment_check_returns_difference(uuid, text, text) from public, anon, authenticated;

-- The accountant's model answered (surface accountant.payment_exception).
create or replace function public.fn_reason_apply_accountant__payment_exception(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_tx uuid; v jsonb; v_may jsonb; o record; v_ret jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  v_tx := (r.subject->>'transaction_id')::uuid;
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || v_tx::text));   -- lock order: item 6b
  if v_choice = 'recheck_within_the_hour' then
    -- read again now (and the runtime reads Stripe again); unresolved at 45 minutes it goes to the CEO anyway
    update public.accountant_reveal_payment_check set decision = v_choice, decided_by = 'accountant model: ' || coalesce(p_result->>'model', '?'),
           decision_reason = left(coalesce(p_result->>'answer', ''), 2000)
     where transaction_id = v_tx;
    v := public.fn_accountant_reconciles_reveal(v_tx);
    return jsonb_build_object('applied', true, 'choice', v_choice, 'rechecked', v->>'verdict');
  end if;
  -- A STANDING GRANT (data, never code): if the CEO grants the accountant 'overcharge_return', the accountant returns the
  -- difference itself and the CEO is told. Without it (today) the recommendation goes to the CEO.
  if v_choice = 'recommend_refund_difference' then
    select * into o from public.fn_payment_check_owed_back(v_tx);
    v_may := public.fn_agent_may_act('accountant', 'overcharge_return', o.amount_fils / 100.0);
    if coalesce((v_may->>'may_act')::boolean, false) then
      v_ret := public.fn_payment_check_returns_difference(v_tx, 'accountant (standing grant ' || coalesce(v_may->>'grant', '?') || ')', p_result->>'answer');
    end if;
  end if;
  v := public.fn_accountant_escalates_payment_exception(v_tx, 'accountant model: ' || coalesce(p_result->>'model', '?'), v_choice, p_result->>'answer');
  return jsonb_build_object('applied', true, 'choice', v_choice, 'returned_under_grant', v_ret) || v;
end $fn$;
revoke execute on function public.fn_reason_apply_accountant__payment_exception(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_accountant__payment_exception(bigint, jsonb) to service_role;

-- The CEO's handler for payment.exception: the CEO decides by reasoning (ceo.payment_exception) and answers on it.
-- A FINAL question (after 'investigate' brought Stripe's objects back) has two options only.
create or replace function public.fn_ceo_takes_payment_exception(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_held bigint; v_final boolean; v_opts jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_final := coalesce((a.detail->>'final')::boolean, false);
  v_opts := ('[{"id":"refund_difference","meaning":"return to the customer exactly the money that is not the fee (owed_back_fils): it is requested through the refund path, the customer is told once, and the item stays open until Stripe confirms the refund"},'
    || '{"id":"money_is_correct","meaning":"on the facts the charge is right and nothing is owed back; the accountant records why and the item closes"}'
    || case when v_final then '' else ',{"id":"investigate","meaning":"the facts are not enough: the accountant reads the payment, the invoice and the balance transaction from Stripe again and brings back a final question with only the two options above"}' end
    || ']')::jsonb;
  v_held := public.fn_seat_duty_reason('ceo', 'ceo.payment_exception',
    'The accountant hands the CEO a reveal payment that did not reconcile, with its findings and its recommendation. '
    || 'Our rules: the customer pays 3% of the quotation excluding VAT and nothing else; one payment is one reveal; every refund '
    || 'is the CEO''s decision.' || case when v_final then ' This is the FINAL question on this payment: the Stripe objects are in stripe_snapshot.' else '' end || ' Decide.',
    v_opts, a.detail, jsonb_build_object('handoff_id', a.id, 'transaction_id', a.detail->>'transaction_id', 'occurrence', a.detail->'occurrence'),
    'payment_exception_ceo:' || a.id);
  return jsonb_build_object('accepted', true, 'held_question', v_held,
    'waiting', 'the CEO decides this by reasoning (held question ' || coalesce(v_held::text, '?') || ') and answers on this handoff');
end $fn$;
revoke execute on function public.fn_ceo_takes_payment_exception(bigint) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__payment_exception(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_hid bigint; v_tx uuid; v_ret jsonb; c public.accountant_reveal_payment_check;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  v_hid := (r.subject->>'handoff_id')::bigint;
  v_tx := (r.subject->>'transaction_id')::uuid;
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || v_tx::text));   -- lock order: item 6b
  update public.accountant_reveal_payment_check
     set ceo_decision = v_choice, ceo_decided_at = now(),
         resolved_at = case when v_choice = 'money_is_correct' then now() else resolved_at end,
         resolution = case v_choice when 'money_is_correct' then 'CEO: the charge is right, nothing owed back'
                                    when 'investigate' then 'CEO asked for Stripe''s objects; a final question follows' else resolution end,
         investigate_requested_at = case when v_choice = 'investigate' then now() else investigate_requested_at end
   where transaction_id = v_tx
  returning * into c;
  if v_choice = 'refund_difference' then
    v_ret := public.fn_payment_check_returns_difference(v_tx, 'ceo', p_result->>'answer');
  end if;
  perform set_config('qd.handoff_closer', 'ceo', true);
  perform public.fn_seat_handoff_complete(v_hid, jsonb_build_object('decided_by', 'ceo', 'choice', v_choice,
    'reasoning', left(coalesce(p_result->>'answer', ''), 3000), 'model', p_result->>'model', 'held_question', p_id, 'return', v_ret));
  -- review item 11: the sales engineer's reveal.reconcile is answered with the CEO's decision (an investigation keeps it
  -- open until the final answer)
  if v_choice <> 'investigate' and c.reconcile_handoff_id is not null and coalesce((v_ret->>'ok')::boolean, true) then
    perform public.fn_seat_handoff_complete(c.reconcile_handoff_id, jsonb_build_object('reconciled_by', 'accountant', 'verdict', 'exception',
      'findings', c.findings, 'ceo_decision', v_choice, 'resolution', coalesce(c.resolution, ''), 'return', v_ret));
  end if;
  perform set_config('qd.handoff_closer', '', true);
  return jsonb_build_object('applied', true, 'handoff_id', v_hid, 'choice', v_choice, 'return', v_ret);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__payment_exception(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__payment_exception(bigint, jsonb) to service_role;

-- The sales engineer is told; it does not contact the customer about money until the CEO decides.
create or replace function public.fn_sales_engineer_notes_payment_exception(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('noted_by', 'sales_engineer', 'transaction_id', a.detail->>'transaction_id',
    'customer_contacted', false,
    'reply', 'sales_engineer: noted the payment exception on this reveal (' || coalesce(a.detail->>'accountant_choice', '?')
             || '). The customer is not contacted about money until the CEO decides; any question from the customer is answered from this.');
end $fn$;
revoke execute on function public.fn_sales_engineer_notes_payment_exception(bigint) from public, anon, authenticated;

-- A RETURN THAT DID NOT HAPPEN goes back to the CEO (review 3, item 1). The refund's "Decide refund" task is set to
-- 'blocked' with the reason; a refund row not yet at Stripe is cancelled so a new decision can make a new one (a00
-- refuses a second live return); the check's decision is cleared and the CEO is asked again, as a new occurrence.
create or replace function public.fn_payment_check_return_blocked(p_tx uuid, p_refund_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.accountant_reveal_payment_check; v_esc jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || p_tx::text));   -- lock order: item 6b
  select * into c from public.accountant_reveal_payment_check where transaction_id = p_tx for update;
  if not found or c.resolved_at is not null then return jsonb_build_object('handed_back', false, 'reason', 'no open check'); end if;
  update public.ceo_task set state = 'blocked',
         blocked_reason = left('The overcharge return could not be made: ' || coalesce(p_reason, 'no reason given')
                               || '. Handed back to the CEO on the accountant''s payment check ' || p_tx || '.', 1000)
   where task_id = c.refund_ceo_task_id and state in ('open', 'working');
  -- a return that reached Stripe and then failed: its task is already done (a terminal state is not reopened), so the CEO
  -- gets a new task, blocked with Stripe's reason
  if not found then
    insert into public.ceo_task (title, detail, state, blocked_reason)
    values ('Overcharge return not made on reveal ' || left(p_tx::text, 8),
            'The overcharge return (refund ' || coalesce(p_refund_id::text, '?') || ') on payment check ' || p_tx || ' was not made.',
            'blocked', left('The overcharge return could not be made: ' || coalesce(p_reason, 'no reason given')
                            || '. Handed back to the CEO on the accountant''s payment check ' || p_tx || '.', 1000));
  end if;
  -- the check lets go of the refund first, so the cancellation below does not come back here through z59
  update public.accountant_reveal_payment_check
     set refund_id = null, refund_ceo_task_id = null, refund_submitted_at = null, ceo_decision = null, ceo_decided_at = null,
         ceo_handoff_id = null, held_question_id = -1, exception_count = exception_count + 1, opened_at = now(),
         findings = findings || jsonb_build_array(jsonb_build_object('code', 'return_not_made',
                      'fact', 'the return (refund ' || coalesce(p_refund_id::text, '?') || ') was not made: ' || coalesce(p_reason, '?'))),
         resolution = left('return blocked: ' || coalesce(p_reason, '?') || '; back with the CEO', 1000)
   where transaction_id = p_tx;
  update public.refunds set status = 'cancelled', decision_note = left(coalesce(decision_note, '') || ' | cancelled: ' || coalesce(p_reason, '?'), 1000)
   where id = p_refund_id and status in ('requested', 'approved') and stripe_refund_id is null;
  v_esc := public.fn_accountant_escalates_payment_exception(p_tx, 'accountant (code): the return could not be made', 'escalate_to_ceo',
             'The CEO decided to return the difference, but it was not made: ' || coalesce(p_reason, '?') || '. Decide again.');
  return jsonb_build_object('handed_back', true, 'task_blocked', c.refund_ceo_task_id, 'reason', p_reason, 'escalation', v_esc);
end $fn$;
revoke execute on function public.fn_payment_check_return_blocked(uuid, bigint, text) from public, anon, authenticated;

-- THE RETURN REACHED STRIPE: the CEO's task closes with the Stripe refund as evidence and the customer is told, once.
-- Stripe failing or cancelling it hands it back to the CEO instead. (Runs before z60, which closes the check on success.)
create or replace function public.trg_overcharge_return_submitted()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.accountant_reveal_payment_check; t public.transactions; o record; v_submitted boolean;
begin
  if NEW.reason_code is distinct from 'overcharge_return' or NEW.transaction_id is null then return NEW; end if;
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || NEW.transaction_id::text));   -- lock order: item 6b
  select * into c from public.accountant_reveal_payment_check where transaction_id = NEW.transaction_id and refund_id = NEW.id for update;
  if not found then return NEW; end if;
  v_submitted := NEW.stripe_refund_id is not null and NEW.status in ('processing', 'succeeded');
  if v_submitted and c.refund_submitted_at is null then
    update public.ceo_task set state = 'done', closed_at = now(),
           evidence = 'Overcharge return of AED ' || to_char(NEW.amount_fils / 100.0, 'FM999,990.00') || ' submitted to Stripe as '
                      || NEW.stripe_refund_id || ' (refund ' || NEW.id || ', decided on payment check ' || NEW.transaction_id
                      || ' by ' || coalesce(NEW.decided_by, '?') || ')'
     where task_id = c.refund_ceo_task_id and state in ('open', 'working', 'blocked');
    update public.accountant_reveal_payment_check
       set refund_submitted_at = now(),
           resolution = 'return of AED ' || to_char(NEW.amount_fils / 100.0, 'FM999,990.00') || ' submitted to Stripe (refund ' || NEW.id
                        || ', ' || NEW.stripe_refund_id || '); open until Stripe confirms it'
     where transaction_id = NEW.transaction_id;
    if not c.is_test_mode then
      select * into t from public.transactions where id = NEW.transaction_id;
      select * into o from public.fn_payment_check_owed_back(NEW.transaction_id);
      perform public.fn_seat_handoff('accountant', 'customer_support', 'overcharge.customer_notice', 'transactions', NEW.transaction_id::text || '#' || c.exception_count,
        jsonb_build_object('transaction_id', NEW.transaction_id, 'customer_id', t.customer_id, 'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id,
                           'amount_fils', NEW.amount_fils, 'why', o.why, 'refund_id', NEW.id, 'stripe_refund_id', NEW.stripe_refund_id));
    end if;
  elsif NEW.status in ('failed', 'cancelled', 'rejected') and OLD.status is distinct from NEW.status then
    perform public.fn_payment_check_return_blocked(NEW.transaction_id, NEW.id,
      'refund ' || NEW.id || ' is ' || NEW.status || coalesce(' at Stripe: ' || nullif(btrim(NEW.failure_reason), ''), ''));
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_overcharge_return_submitted() from public, anon, authenticated;
create or replace trigger z59_overcharge_return_submitted after update of status, stripe_refund_id on public.refunds
  for each row execute function public.trg_overcharge_return_submitted();

-- customer_support tells the customer ONCE that the difference is being returned (once the return is submitted to Stripe, never before).
create or replace function public.fn_customer_support_tells_overcharge_returned(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; c record; v_ar boolean; v_nid bigint; v_amt text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  select id, email into c from public.customers where id = (a.detail->>'customer_id')::uuid;
  if c.email is null or c.email !~ '@' then return jsonb_build_object('told', false, 'reason', 'no e-mail on file for the customer'); end if;
  v_ar := public.fn_customer_notice_locale(nullif(a.detail->>'inquiry_id', '')::uuid, c.id) = 'ar';
  v_amt := to_char((a.detail->>'amount_fils')::numeric / 100.0, 'FM999,999,990.00');
  insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, lang)
  values ('overcharge_returned', c.email, 'customer', nullif(a.detail->>'inquiry_id', '')::uuid, nullif(a.detail->>'quote_id', '')::uuid,
    case when v_ar then 'نردّ إليكم مبلغًا زائدًا' else 'We are returning money we should not have charged' end,
    case when v_ar
      then 'تقاضينا منكم ' || v_amt || ' درهم زيادةً على رسوم الكشف، ونقوم بردّه إلى بطاقتكم الآن. تُظهر البنوك المبلغ المردود عادةً خلال 7 إلى 14 يوم عمل. لا يلزمكم القيام بأي شيء.'
      else 'We charged you AED ' || v_amt || ' more than our reveal fee. It is being returned to your card now; banks usually show it within 7 to 14 working days. You do not need to do anything.'
    end, case when v_ar then 'ar' else 'en' end)
  returning id into v_nid;
  return jsonb_build_object('told', true, 'notification_id', v_nid, 'language', case when v_ar then 'ar' else 'en' end);
end $fn$;
revoke execute on function public.fn_customer_support_tells_overcharge_returned(bigint) from public, anon, authenticated;

-- The item stays open until Stripe confirms the refund: when the refund of the difference settles, the check closes.
create or replace function public.trg_payment_check_closes_when_the_return_settles()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if NEW.status = 'succeeded' and OLD.status is distinct from 'succeeded' and NEW.transaction_id is not null then
    perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || NEW.transaction_id::text));   -- lock order: item 6b
    update public.accountant_reveal_payment_check
       set resolved_at = now(),
           resolution = 'Stripe confirmed the return of AED ' || to_char(NEW.amount_fils / 100.0, 'FM999,990.00') || ' (refund ' || NEW.id || ')'
     where transaction_id = NEW.transaction_id and refund_id = NEW.id and resolved_at is null;
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_payment_check_closes_when_the_return_settles() from public, anon, authenticated;
create or replace trigger z60_payment_check_closes_when_the_return_settles after update of status on public.refunds
  for each row execute function public.trg_payment_check_closes_when_the_return_settles();


-- ══ 10b. THE REFUND PATH CARRIES AN OVERCHARGE RETURN (R4) ════════════════════════════════════════════
-- refunds.reason_code gains 'overcharge_return'. The guard a00 (fn_refund_amount_is_the_fee_paid) accepts it only for
-- exactly what fn_payment_check_owed_back names on the payment it cites, and fn_refund_decide lets it through before the
-- window (the window governs a refund of the FEE for supplier silence, not money that was never ours). Everything else
-- in both routines is the live body, unchanged (read from production 13 Nov 2026).
-- one plain ADD (review 3: NOT VALID then VALIDATE in one transaction saves nothing); refunds holds 1 row (13 Nov)
alter table public.refunds drop constraint if exists refunds_reason_code_check;
alter table public.refunds add constraint refunds_reason_code_check check (reason_code = any (array['supplier_unresponsive', 'supplier_withdrew',
  'duplicate_charge', 'customer_cancelled_in_window', 'service_not_delivered', 'fraud_or_dispute', 'goodwill', 'other', 'overcharge_return']));

-- AN OVERCHARGE RETURN IS NOT A CUSTOMER'S REFUND REQUEST (review 4, item 1). The live z30 trigger handed every new
-- refunds row to the accountant as refund.requested; the accountant's check answered refund.request_checked and the sales
-- engineer then e-mailed the customer "we have your refund request ... you get back everything you paid" the moment the
-- CEO approved a return, before Stripe held it, and once more per retry (measured on a local copy, 13 Nov 2026). An
-- overcharge return is decided on the accountant's payment check, and the customer is told only once Stripe holds it
-- (z59 -> overcharge.customer_notice). Body otherwise the live one (payments_are_the_accountant_and_the_seats_close_every_refund_together.sql).
create or replace function public.fn_refund_request_hands_to_accountant()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if NEW.transaction_id is not null and NEW.status = 'requested'
     and NEW.reason_code is distinct from 'overcharge_return'
     and lower(coalesce(NEW.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') then
    perform public.fn_seat_handoff('sales_engineer', 'accountant', 'refund.requested', 'refunds', NEW.id::text,
      jsonb_build_object('refund_id', NEW.id, 'transaction_id', NEW.transaction_id, 'customer_id', NEW.customer_id,
                         'inquiry_id', NEW.inquiry_id, 'quote_id', NEW.quote_id));
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_refund_request_hands_to_accountant() from public, anon, authenticated;

create or replace function public.fn_refund_amount_is_the_fee_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions%rowtype;
  v_expected bigint;
  -- A refund Stripe already issued is a fact to be recorded, not a request to be approved.
  v_external constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
begin
  if lower(coalesce(NEW.requested_by,'')) = any(v_external) then
    return NEW;
  end if;

  -- AN OVERCHARGE RETURN (13 Nov 2026, accountant; coordinator ruling R4). Money charged ABOVE the fee is not a refund of
  -- the fee: it is owed back whatever the supplier does, so it waits for no window. It must cite the payment it came from
  -- and be EXACTLY what the accountant's check says is owed back, decided by the CEO (or a standing grant) on that check.
  if NEW.reason_code = 'overcharge_return' then
    select * into t from public.transactions where id = NEW.transaction_id;
    if not found then
      raise exception 'refunds: an overcharge return must name its transaction. (overcharge_return_names_no_payment)' using errcode = '23514';
    end if;
    if coalesce(btrim(NEW.stripe_payment_intent), '') = '' then
      raise exception 'refunds: an overcharge return names no Stripe payment. (overcharge_return_names_no_stripe_reference)' using errcode = '23514';
    end if;
    if exists (select 1 from public.refunds f where f.transaction_id = NEW.transaction_id and f.reason_code = 'overcharge_return'
                  and f.id is distinct from NEW.id and f.status not in ('rejected', 'failed', 'cancelled')) then
      raise exception 'refunds: payment % already has an overcharge return; a second one would return the same money twice. (overcharge_return_once)',
        NEW.stripe_payment_intent using errcode = '23514';
    end if;
    select o.amount_fils into v_expected from public.fn_payment_check_owed_back(NEW.transaction_id) o
     where o.payment_intent = btrim(NEW.stripe_payment_intent);
    if v_expected is null or NEW.amount_fils is distinct from v_expected then
      raise exception 'refunds: an overcharge return of % fils on payment % is not what the accountant''s check says is owed back (% fils). (overcharge_return_is_the_difference)',
        NEW.amount_fils, NEW.stripe_payment_intent, coalesce(v_expected::text, 'nothing') using errcode = '23514';
    end if;
    return NEW;
  end if;

  if NEW.transaction_id is null then
    raise exception 'refunds: a refund must name the transaction it reverses. transaction_id is null, so this row asserts money is owed without saying which payment it came from. (refund_names_no_payment)'
      using errcode = '23514',
            hint = 'Set transaction_id to the public.transactions row whose reveal_fee is being returned. A refund this platform did not issue is recorded through fn_refund_settle with requested_by stripe_webhook, and that path is exempt.';
  end if;

  select * into t from public.transactions where id = NEW.transaction_id;
  if not found then
    raise exception 'refunds: transaction % does not exist. (refund_transaction_absent)',
      NEW.transaction_id using errcode = '23503';
  end if;

  if coalesce(t.total_charged, t.reveal_fee) is null or coalesce(t.total_charged, t.reveal_fee) <= 0 then
    raise exception 'refunds: transaction % records no reveal fee (reveal_fee %), so there is nothing to give back. A refund of an unpaid reveal is a payment, not a refund. (refund_no_fee_was_paid)',
      NEW.transaction_id, coalesce(t.reveal_fee::text,'null') using errcode = '23514';
  end if;

  if t.refund_deadline is null then
    raise exception 'refunds: transaction % has no refund window. trg_reveal_window opens one at reveal, so a transaction without it was never revealed and no refund can be due yet. (refund_window_not_open)',
      NEW.transaction_id using errcode = '23514';
  end if;
  -- THE WINDOW GOVERNS THE DECISION, NOT THE REQUEST (14 Sep 2026). The terms let the customer
  -- complain "at any time"; what waits for the fifth working day and the CEO's final call is the
  -- approval. So a row at 'requested' is recorded whenever it arrives, and only the move to money
  -- (approved, processing, succeeded) is refused before refund_deadline.
  if NEW.status in ('approved', 'processing', 'succeeded') and now() < t.refund_deadline then
    raise exception 'refunds: transaction % may not be approved or paid before % (it is now %). The supplier has five working days from the payment and the CEO''s final call before a refund is decided; the request itself is recorded at any time. (refund_window_not_yet_open)',
      NEW.transaction_id, t.refund_deadline, now() using errcode = '23514';
  end if;

  -- ── THE STRIPE REFERENCE, ADDED 9 SEP 2026 ───────────────────────────────────────────────────
  -- The founder: "it's issued against that exact invoice reference... It has an ID." The reference
  -- Stripe gave us when the customer paid is transactions.payment_ref (stripe_webhook writes the
  -- payment_intent, falling back to the checkout session id). Until now stripe_payment_intent on a
  -- refund was a nullable text column nothing checked, so a refund could name transaction A and
  -- cite the payment of transaction B -- or name no payment at all -- and still move money.
  if coalesce(btrim(t.payment_ref), '') = '' then
    raise exception 'refunds: transaction % carries no Stripe payment reference, so there is no payment of record to reverse. (refund_payment_has_no_reference)',
      NEW.transaction_id using errcode = '23514',
            hint = 'transactions.payment_ref is written by stripe_webhook when the reveal fee settles. A transaction without one was never paid through Stripe, and money must not be returned against a payment nobody can point at.';
  end if;
  if coalesce(btrim(NEW.stripe_payment_intent), '') = '' then
    raise exception 'refunds: this refund names no Stripe payment. Transaction % was paid under reference %, and a refund is issued against that exact reference. (refund_names_no_stripe_reference)',
      NEW.transaction_id, t.payment_ref using errcode = '23514',
            hint = 'Set stripe_payment_intent to the payment_ref of the transaction being reversed. Founder ruling, 9 Sep 2026.';
  end if;
  if btrim(NEW.stripe_payment_intent) <> btrim(t.payment_ref) then
    raise exception 'refunds: this refund cites Stripe payment %, but transaction % was paid under %. A refund is issued against the exact reference of the payment it reverses, never another one. (refund_cites_the_wrong_stripe_payment)',
      NEW.stripe_payment_intent, NEW.transaction_id, t.payment_ref using errcode = '23514';
  end if;

  -- AND THE AMOUNT IS READ OFF THAT PAYMENT. Equality, not a ceiling: the reveal fee is refunded
  -- whole or not at all, so "cannot exceed what the payment took" is enforced by the stricter rule
  -- that it must EQUAL it. A platform refund with no amount is refused outright -- an unstated
  -- figure is not a smaller figure, it is an unbounded one.
  v_expected := round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint;
  -- A TOP-UP (topup_of set) completes a case on THIS payment and carries only the part still owed, so
  -- it is exempt from equality; a01 caps it, and every live refund on the payment together, at
  -- total_charged (PR #640 re-review, 14 Sep 2026).
  if NEW.topup_of is not null then
    if not exists (select 1 from public.refunds c where c.id = NEW.topup_of and c.transaction_id = NEW.transaction_id and c.topup_of is null) then
      raise exception 'refunds: a top-up must name a refund case on the same payment; % is not one for transaction %. (refund_topup_names_no_case)',
        NEW.topup_of, NEW.transaction_id using errcode = '23514';
    end if;
    if NEW.amount_fils is null or NEW.amount_fils <= 0 then
      raise exception 'refunds: a top-up must state a positive amount. (refund_states_no_amount)' using errcode = '23514';
    end if;
    return NEW;
  end if;
  if NEW.amount_fils is null then
    raise exception 'refunds: a platform refund must state its amount. Transaction % took % fils (AED %), and that is the only figure this refund may carry. (refund_states_no_amount)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2) using errcode = '23514';
  end if;
  if NEW.amount_fils <> v_expected then
    raise exception 'refunds: the amount must equal what the customer actually paid, the 3%% and the processing part together (total_charged), on transaction % — expected % fils (AED %), got % fils (AED %). A refund figure is read off the payment, never typed. (refund_amount_is_not_the_fee_paid)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2), NEW.amount_fils, round(NEW.amount_fils/100.0,2)
      using errcode = '23514';
  end if;

  return NEW;
end
$function$;
revoke execute on function public.fn_refund_amount_is_the_fee_paid() from public, anon, authenticated;

create or replace function public.fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.refunds; v_app public.ceo_approval; v_new text; v_gate jsonb;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status); end if;
  if coalesce(btrim(p_decided_by), '') = '' then return jsonb_build_object('ok', false, 'error', 'decider_required'); end if;
  if lower(btrim(p_decided_by)) like 'policy:%' then
    return jsonb_build_object('ok', false, 'error', 'automatic_decider_refused',
      'hint', 'A refund is decided by an actor, not by a rule. Approvals are the CEO''s.');
  end if;

  if p_approve then
    select * into v_app from public.ceo_approval a
     where a.subject_kind = 'refund' and a.subject_id = p_refund_id::text and a.decision = 'approved' and a.superseded_by is null
     order by a.decision_id desc limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'no_ceo_approval',
        'hint', 'A refund is approved only by a CEO approval that passed the process checklist (fn_ceo_refund_review, or ceo_agent decide). This routine records that decision; it cannot make one.');
    end if;
    -- The window: a00 refuses 'approved' before refund_deadline. Answered here instead of raised, so a CEO review
    -- run early keeps its approval; the accountant asks this routine again before it pays.
    -- 13 Nov 2026: an overcharge return (money above the fee) waits for no window (fn_refund_amount_is_the_fee_paid).
    if r.reason_code is distinct from 'overcharge_return'
       and exists (select 1 from public.transactions t where t.id = r.transaction_id and now() < t.refund_deadline) then
      return jsonb_build_object('ok', false, 'error', 'window_not_open',
        'decision_after', (select t.refund_deadline from public.transactions t where t.id = r.transaction_id));
    end if;
    -- A REFUND IS HIGH STAKES (29 Sep 2026, instruction 1009): a second seat on another family must agree first. While
    -- the model hold is on the refund proceeds and the review is owed; a later disagreement opens a finding.
    -- 13 Nov 2026 (coordinator, review 3, item 1): an OVERCHARGE RETURN skips this second seat, and only this. It is money
    -- that was never ours, its amount is fixed by the accountant's check (guard a00), and it still needs the CEO's
    -- approval above (or the CEO's standing grant 'overcharge_return'). Every other reason code goes through the gate.
    if r.reason_code = 'overcharge_return' then
      v_gate := jsonb_build_object('proceed', true, 'state', 'not_required',
        'reason', 'an overcharge return: money above the fee, exact amount fixed by the payment check; the CEO approved it');
    else
      v_gate := public.fn_high_stakes_gate('refund', 'ceo', 'refunds', p_refund_id::text,
        'Should this refund be approved as the CEO decided?',
        jsonb_build_object('refund', jsonb_build_object('amount_fils', r.amount_fils, 'currency', r.currency, 'reason_code', r.reason_code,
          'reason_note', left(r.reason_note, 1000), 'requested_by', r.requested_by, 'within_auto_window', r.within_auto_window)),
        jsonb_build_object('decision', 'approve', 'ceo_rationale', left(v_app.rationale, 3000), 'amount_aed', v_app.amount_aed));
    end if;
    if not coalesce((v_gate->>'proceed')::boolean, false) then
      return jsonb_build_object('ok', false, 'error', 'awaiting_second_seat', 'clearance', v_gate);
    end if;
    -- the mark z04 (refunds) and a00 (refund_case) read: this refund was approved here, after the second seat
    perform set_config('qd.refund_decide', p_refund_id::text, true);
    update public.refunds set status = 'approved', decided_by = v_app.decided_by, decided_at = now(),
           decision_note = coalesce(p_note, v_app.rationale), refund_decision_id = v_app.decision_id
     where id = p_refund_id;
    v_new := 'approved';
  else
    update public.refunds set status = 'rejected', decided_by = p_decided_by, decided_at = now(), decision_note = p_note where id = p_refund_id;
    v_new := 'rejected';
  end if;
  -- an overcharge return is tracked on the refunds row and the payment check, never on the sale (review 2, item 2): the
  -- fee's own non-response window and ladder keep running
  if r.transaction_id is not null and r.reason_code is distinct from 'overcharge_return' then
    update public.transactions set refund_status = v_new, refund_resolved_at = now(), refund_note = coalesce(p_note, refund_note)
     where id = r.transaction_id;
  end if;
  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'status', v_new, 'decided_by', coalesce(v_app.decided_by, p_decided_by),
                            'second_seat', v_gate);
end $function$;
revoke execute on function public.fn_refund_decide(bigint, boolean, text, text) from public, anon, authenticated;

-- fn_refund_request and fn_refund_settle: an overcharge return never writes transactions.refund_* (review 2, item 2).
-- Bodies otherwise the live ones (read from production 13 Nov 2026).
create or replace function public.fn_refund_request(p_amount_fils bigint, p_reason_code text, p_requested_by text, p_inquiry_id uuid DEFAULT NULL::uuid, p_customer_id uuid DEFAULT NULL::uuid, p_supplier_lead_id bigint DEFAULT NULL::bigint, p_quote_id uuid DEFAULT NULL::uuid, p_payment_intent text DEFAULT NULL::text, p_charge_id text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_transaction_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint; v_task bigint; v_in_window boolean := false; t public.transactions;
begin
  if p_amount_fils is null or p_amount_fils <= 0 then
    return jsonb_build_object('ok', false, 'error', 'amount_required');
  end if;

  select * into t from public.transactions
   where (p_transaction_id is not null and id = p_transaction_id)
      or (p_transaction_id is null and p_quote_id is not null and quote_id = p_quote_id)
      or (p_transaction_id is null and p_quote_id is null and p_payment_intent is not null and payment_ref = p_payment_intent)
   order by revealed_at desc nulls last limit 1;

  -- Recorded, never acted on. Whether the request arrived inside the window promised at reveal is
  -- exactly the kind of thing the decider wants in front of them, and exactly the kind of thing that
  -- must not decide for them.
  if t.id is not null and t.refund_deadline is not null and t.refund_deadline >= now() then
    v_in_window := true;
  end if;

  insert into public.refunds (transaction_id, inquiry_id, customer_id, supplier_lead_id, quote_id,
                              stripe_payment_intent, stripe_charge_id,
                              amount_fils, reason_code, reason_note, requested_by,
                              within_auto_window, status, reconciliation_note)
  values (t.id, coalesce(p_inquiry_id, t.inquiry_id), coalesce(p_customer_id, t.customer_id),
          coalesce(p_supplier_lead_id, t.supplier_id), coalesce(p_quote_id, t.quote_id),
          coalesce(p_payment_intent, t.payment_ref), p_charge_id,
          p_amount_fils, p_reason_code, p_note, p_requested_by,
          v_in_window, 'requested',
          'ROUTED TO THE CEO. Every refund waits for the CEO seat''s decision, whatever the amount '
       || 'and whether or not it is inside the promised window — founder ruling, 8 Sep 2026, '
       || 'replacing his 17 Aug rule that every refund needed him personally. This one is '
       || round(p_amount_fils / 100.0, 2) || ' AED and is '
       || case when v_in_window then 'inside' else 'outside' end || ' the window promised at reveal.')
  returning id into v_id;

  -- an overcharge return (13 Nov 2026) is tracked on this row and the payment check only: the sale keeps its own status,
  -- so the fee's non-response window and ladder keep running
  if t.id is not null and p_reason_code is distinct from 'overcharge_return' then
    update public.transactions
       set refund_status = 'requested',
           refund_reason = coalesce(refund_reason, p_reason_code),
           refund_requested_at = coalesce(refund_requested_at, now()),
           refund_note = coalesce(p_note, refund_note)
     where id = t.id;
  end if;

  -- THE ROUTE. Without this the request is recorded and nothing is asked of anyone.
  insert into public.ceo_task (title, detail)
  values (
    'Decide refund ' || v_id || ' — AED ' || round(p_amount_fils / 100.0, 2),
    'Refund ' || v_id || ' requested by ' || coalesce(nullif(btrim(p_requested_by), ''), '(unknown)')
      || ' for ' || round(p_amount_fils / 100.0, 2) || ' AED, reason ' || coalesce(p_reason_code, '(none)')
      || '. Transaction ' || coalesce(t.id::text, '(none matched)')
      || '. The request arrived ' || case when v_in_window then 'INSIDE' else 'OUTSIDE' end
      || ' the refund window promised at reveal — a fact, not a decision.'
      || coalesce(chr(10) || 'Customer note: ' || nullif(btrim(p_note), ''), '')
      || chr(10) || chr(10)
      || 'To approve: write a row in public.ceo_approval (subject_kind = ''refund'') and set '
      || 'refunds.refund_decision_id to it. The guards on public.refunds will refuse the money moving '
      || 'any other way.')
  returning task_id into v_task;

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'transaction_id', t.id,
                            'status', 'requested',
                            'within_auto_window', v_in_window,
                            'auto_approved', false,
                            'ceo_task_id', v_task,
                            'awaiting', 'ceo');
end
$function$;
revoke execute on function public.fn_refund_request(bigint, text, text, uuid, uuid, bigint, uuid, text, text, text, uuid) from public, anon, authenticated;

-- WHAT A SALE SAYS IS REFUNDED IS THE SUM OF ITS REFUNDS (review 5, item 1). fn_refund_settle wrote the settling refund's
-- own status and amount onto the sale: a AED 100 dashboard refund of a AED 1,978.80 sale set refund_status 'succeeded'
-- (fn_refund_state 'refunded', the customer's guarantee "Refund refunded", the fee ladder stopped) and a second of AED 50
-- overwrote the amount to 50 (measured locally, SP/rev5/s6c.sql). Now the sale carries what its refunds add up to:
--   * 'succeeded' (refunded in full) only when the settled refunds reach what was charged, less any overcharge returned;
--     refund_amount_aed = that sum, refund_confirmed_at = when it got there;
--   * 'processing' when what is settled plus what is in flight reaches it (a whole refund on its way, as before);
--   * 'partly_refunded' while some, not all, has gone back; refund_amount_aed = the sum (100 then 50 = 150). The ladder,
--     the CEO's reconcile and the books read the sale as still sold (the refunds rows book the money back, 1b);
--   * otherwise the sale's status is left as it was, except a whole refund that failed or was cancelled, which is written
--     as before. An amount the event did not carry counts for nothing until it is known.
-- An overcharge return (reason overcharge_return) never writes the sale (see fn_refund_request): it is not a refund of
-- the fee, so it is left out of the sum and taken off what was charged. Matched by the sale or its PaymentIntent, as
-- fn_refunds_never_return_more_than_was_paid counts them. Called with the payment already locked by the refund's trigger.
-- prevented by: scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid_probe.sql (K)
create or replace function public.fn_refund_rolls_up_to_its_sale(p_tx uuid, p_stripe_refund_id text, p_status text, p_amount_fils bigint)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; v_due bigint; v_done bigint; v_flight bigint; v_over bigint; v_new text;
begin
  select * into t from public.transactions where id = p_tx;
  if not found then return null; end if;
  select coalesce(sum(f.amount_fils) filter (where f.status = 'succeeded' and f.reason_code is distinct from 'overcharge_return'), 0),
         coalesce(sum(f.amount_fils) filter (where f.status in ('approved', 'processing') and f.reason_code is distinct from 'overcharge_return'), 0),
         coalesce(sum(f.amount_fils) filter (where f.status = 'succeeded' and f.reason_code = 'overcharge_return'), 0)
    into v_done, v_flight, v_over
    from public.refunds f
   where f.transaction_id = t.id or (f.transaction_id is null and coalesce(btrim(t.payment_ref), '') <> '' and f.stripe_payment_intent = t.payment_ref);
  v_due := round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint - v_over;
  v_new := case
    when v_due <= 0 then p_status                                           -- nothing charged on record: the old reading
    when v_done >= v_due then 'succeeded'
    when v_done + v_flight >= v_due then 'processing'
    when v_done > 0 then 'partly_refunded'
    when p_status in ('failed', 'cancelled') and coalesce(p_amount_fils, 0) >= v_due then p_status
    end;
  update public.transactions
     set refund_status = coalesce(v_new, refund_status),
         refund_stripe_id = p_stripe_refund_id,
         refund_amount_aed = case when v_done > 0 then round(v_done / 100.0, 2)
                                  when v_due <= 0 and p_amount_fils is not null then round(p_amount_fils / 100.0, 2)
                                  else refund_amount_aed end,
         refund_confirmed_at = case when v_new = 'succeeded' then coalesce(refund_confirmed_at, now()) else refund_confirmed_at end
   where id = t.id;
  return coalesce(v_new, t.refund_status);
end $fn$;
revoke execute on function public.fn_refund_rolls_up_to_its_sale(uuid, text, text, bigint) from public, anon, authenticated;

create or replace function public.fn_refund_settle(p_stripe_refund_id text, p_status text, p_amount_fils bigint DEFAULT NULL::bigint, p_payment_intent text DEFAULT NULL::text, p_charge_id text DEFAULT NULL::text, p_failure_reason text DEFAULT NULL::text, p_amount_source text DEFAULT 'webhook_event'::text, p_stripe_event_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.refunds; v_status text; v_amount bigint; v_src text; v_q bigint; v_tx public.transactions; v_matched boolean := false;
begin
  if coalesce(btrim(p_stripe_refund_id),'') = '' then
    v_q := public.fn_refund_quarantine(null, 'refund', 'event carried no refund id',
             jsonb_build_object('status', p_status, 'payment_intent', p_payment_intent), p_stripe_event_id);
    return jsonb_build_object('ok', false, 'error', 'stripe_refund_id_required', 'quarantined', v_q);
  end if;

  v_status := case lower(coalesce(p_status,''))
                when 'succeeded' then 'succeeded' when 'failed' then 'failed'
                when 'canceled' then 'cancelled'  when 'cancelled' then 'cancelled'
                else 'processing' end;
  v_amount := nullif(coalesce(p_amount_fils, 0), 0);
  v_src    := case when v_amount is null then null else coalesce(p_amount_source, 'webhook_event') end;

  select * into r from public.refunds where stripe_refund_id = p_stripe_refund_id for update;

  if not found then
    select * into r from public.refunds
     where stripe_refund_id is null and p_payment_intent is not null
       and stripe_payment_intent = p_payment_intent and status in ('approved','processing')
     order by created_at limit 1 for update;

    if found then
      update public.refunds set stripe_refund_id = p_stripe_refund_id,
             stripe_charge_id = coalesce(p_charge_id, stripe_charge_id) where id = r.id;
    else
      -- Issued outside the platform. Recorded with whatever is actually known, and NOTHING invented:
      -- if the amount is unknown it stays NULL and the row is marked unreconciled.
      -- A STRIPE-DASHBOARD REFUND IS BOOKED LIKE ANY REFUND (review 4, item 6c): the event names no transaction, so the
      -- sale is found by its PaymentIntent (transactions.payment_ref), or by the charge an earlier refund of it named,
      -- and the row carries it (fn_gl_sync_business 1b books refunds by their transaction). No match: the accountant is
      -- handed it below as an unbooked refund, never silent.
      select * into v_tx from public.transactions t
       where (p_payment_intent is not null and t.payment_ref = p_payment_intent)
          or (p_charge_id is not null and t.id = (select x.transaction_id from public.refunds x
                                                   where x.stripe_charge_id = p_charge_id and x.transaction_id is not null limit 1))
       order by (t.payment_ref is not distinct from p_payment_intent) desc, t.revealed_at desc nulls last limit 1;
      insert into public.refunds (stripe_refund_id, stripe_payment_intent, stripe_charge_id,
                                  amount_fils, amount_source, reason_code, reason_note, requested_by, status,
                                  decided_by, decided_at, decision_note, reconciliation_note,
                                  transaction_id, customer_id, inquiry_id, quote_id)
      values (p_stripe_refund_id, coalesce(p_payment_intent, v_tx.payment_ref), p_charge_id, v_amount,
              coalesce(v_src, 'unknown'), 'other',
              'Issued outside QuotesDone (Stripe dashboard or API). Recorded by the webhook.',
              'stripe_webhook', coalesce(v_status, 'processing'), 'stripe_dashboard', now(),
              'No in-platform request existed for this refund.',
              case when v_amount is null
                   then 'AMOUNT UNKNOWN - the event carried none and Stripe could not be read. Excluded from all financial totals until resolved.'
                   when v_tx.id is null
                   then 'NO SALE MATCHED - no transaction carries this PaymentIntent or charge; handed to the accountant as an unbooked refund.'
                   else null end,
              v_tx.id, v_tx.customer_id, v_tx.inquiry_id, v_tx.quote_id)
      returning * into r;

      if v_tx.id is not null then
        perform public.fn_refund_rolls_up_to_its_sale(v_tx.id, p_stripe_refund_id, v_status, v_amount);   -- review 5, item 1
      else
        perform public.fn_it_engineer_finding_upsert(p_issue_key => 'refund:unbooked:' || p_stripe_refund_id,
          p_title => 'A refund made in Stripe (dashboard or API) matches no sale we hold, so it is not booked: '
                     || coalesce('AED ' || to_char(v_amount / 100.0, 'FM999,990.00'), 'amount unknown'),
          p_where => 'public.fn_refund_settle (stripe_webhook, refund event with no in-platform request)',
          p_blast => 'internal', p_affected => 1,
          p_evidence => jsonb_build_object('refund_row', r.id, 'stripe_refund_id', p_stripe_refund_id, 'payment_intent', p_payment_intent,
                          'charge_id', p_charge_id, 'amount_fils', v_amount, 'status', v_status, 'owner_seat', 'accountant',
                          'remedy', 'find the payment in Stripe; set refunds.transaction_id to its sale and the next gl sync books it, or record why it is not ours'),
          p_raised_by => 'accountant');
      end if;

      if v_amount is null then
        perform public.fn_refund_quarantine(p_stripe_refund_id, 'refund',
          'amount unknown: absent from the event and not retrievable from Stripe',
          jsonb_build_object('status', v_status, 'payment_intent', p_payment_intent, 'refund_row', r.id),
          p_stripe_event_id);
      end if;

      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'applied', true,
                                'created', true, 'amount_known', v_amount is not null);
    end if;
  end if;

  -- a dashboard refund recorded before its sale could be matched is matched now (review 4, item 6c), by ANY later event
  -- that names its PaymentIntent, a repeat of the same status included (review 5, item 3: before, only a new status
  -- reached this block, so a settled refund re-sent with its PaymentIntent stayed unmatched)
  if r.transaction_id is null and r.reason_code is distinct from 'overcharge_return' then
    select * into v_tx from public.transactions t
     where coalesce(p_payment_intent, r.stripe_payment_intent) is not null and t.payment_ref = coalesce(p_payment_intent, r.stripe_payment_intent)
     order by t.revealed_at desc nulls last limit 1;
    if v_tx.id is not null then
      update public.refunds set transaction_id = v_tx.id, customer_id = coalesce(customer_id, v_tx.customer_id),
             stripe_payment_intent = coalesce(stripe_payment_intent, v_tx.payment_ref),
             inquiry_id = coalesce(inquiry_id, v_tx.inquiry_id), quote_id = coalesce(quote_id, v_tx.quote_id) where id = r.id;
      r.transaction_id := v_tx.id;
      v_matched := true;
      -- the accountant was handed it as unbooked when it arrived unmatched: that loop is closed here (review 5, item 3)
      perform public.fn_it_engineer_finding_close('refund:unbooked:' || p_stripe_refund_id,
        'matched to sale ' || v_tx.id || ' by a later Stripe event; booked by the next gl sync');
    end if;
  end if;

  -- Duplicate delivery: same state twice. Cheap, silent, correct - but still take the chance to fill
  -- in an amount we did not have before.
  if r.status = v_status then
    if r.amount_fils is null and v_amount is not null then
      update public.refunds
         set amount_fils = v_amount, amount_source = v_src,
             reconciliation_note = 'amount resolved from a later ' || coalesce(p_amount_source,'event'),
             updated_at = now()
       where id = r.id;
      if r.transaction_id is not null and r.reason_code is distinct from 'overcharge_return' then   -- the amount now counts (item 1)
        perform public.fn_refund_rolls_up_to_its_sale(r.transaction_id, p_stripe_refund_id, v_status, v_amount);
      end if;
      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                                'idempotent', true, 'applied', false, 'amount_resolved', true);
    end if;
    if v_matched then perform public.fn_refund_rolls_up_to_its_sale(r.transaction_id, p_stripe_refund_id, v_status, r.amount_fils); end if;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                              'idempotent', true, 'applied', false);
  end if;

  -- The matrix decides. Not a rank, not an ordering heuristic - a declared policy with a reason
  -- attached to every refusal.
  if not public.fn_refund_transition_allowed(r.status, v_status) then
    v_q := public.fn_refund_quarantine(p_stripe_refund_id, 'refund',
      'transition not permitted: ' || r.status || ' -> ' || v_status || '. '
      || coalesce((select note from public.refund_status_transition
                    where from_status = r.status and to_status = v_status), 'no rule declared for this pair'),
      jsonb_build_object('refund_row', r.id, 'from', r.status, 'to', v_status,
                         'amount_fils', p_amount_fils, 'payment_intent', p_payment_intent),
      p_stripe_event_id);
    update public.refunds
       set reconciliation_note = left(coalesce(reconciliation_note || ' | ', '')
           || 'refused ' || r.status || '->' || v_status || ' at ' || to_char(now(),'YYYY-MM-DD HH24:MI'), 500),
           updated_at = now()
     where id = r.id;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'applied', false,
                              'refused_transition', r.status || '->' || v_status, 'quarantined', v_q);
  end if;

  update public.refunds
     set status = v_status,
         amount_fils   = coalesce(v_amount, amount_fils),
         amount_source = case when v_amount is not null then v_src else amount_source end,
         stripe_charge_id = coalesce(p_charge_id, stripe_charge_id),
         stripe_payment_intent = coalesce(p_payment_intent, stripe_payment_intent),
         settled_at = case when v_status = 'succeeded' then coalesce(settled_at, now()) else settled_at end,
         failure_reason = case when v_status = 'failed' then p_failure_reason else failure_reason end,
         reconciliation_note = case
             when v_status = 'succeeded' and coalesce(v_amount, amount_fils) is null
             then 'AMOUNT UNKNOWN on a settled refund - excluded from all financial totals until resolved.'
             else reconciliation_note end,
         updated_at = now()
   where id = r.id;

  if r.transaction_id is not null and r.reason_code is distinct from 'overcharge_return' then   -- see fn_refund_request
    -- the sale carries the SUM of its refunds, not this one's (review 5, item 1)
    perform public.fn_refund_rolls_up_to_its_sale(r.transaction_id, p_stripe_refund_id, v_status, coalesce(v_amount, r.amount_fils));
  end if;

  return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', v_status, 'applied', true,
                            'amount_known', coalesce(v_amount, r.amount_fils) is not null);
end $function$;
revoke execute on function public.fn_refund_settle(text, text, bigint, text, text, text, text, text) from public, anon, authenticated;

-- The CEO approval trigger (a05 on ceo_approval, z20 on refund_case): an overcharge return is checked by its own list.
create or replace function public.fn_ceo_refund_approval_checks_the_process()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_tx uuid; v jsonb;
begin
  if TG_TABLE_NAME = 'ceo_approval' then
    if NEW.subject_kind <> 'refund' or NEW.decision <> 'approved' then return NEW; end if;
    if coalesce(NEW.subject_id, '') !~ '^[0-9]+$' then
      raise exception 'a refund approval names the refund by its id; % is not one', coalesce(NEW.subject_id, '(nothing)') using errcode = '23514';
    end if;
    select transaction_id into v_tx from public.refunds where id = NEW.subject_id::bigint;
    -- AN OVERCHARGE RETURN HAS ITS OWN CHECKLIST (13 Nov 2026, accountant, R4). It is not a refund of the fee for supplier
    -- silence, so the non-response checklist does not apply. It is approved only when: the refund cites the payment, its
    -- amount is exactly what the accountant's check says is owed back on that payment, and the check records the CEO's
    -- decision 'refund_difference' (or a standing grant overcharge_return covers it).
    if exists (select 1 from public.refunds f where f.id = NEW.subject_id::bigint and f.reason_code = 'overcharge_return') then
      if not exists (
        select 1 from public.refunds f
          join public.accountant_reveal_payment_check k on k.transaction_id = f.transaction_id
          cross join lateral public.fn_payment_check_owed_back(f.transaction_id) o
         where f.id = NEW.subject_id::bigint and o.payment_intent = f.stripe_payment_intent and o.amount_fils = f.amount_fils
           and (k.ceo_decision = 'refund_difference'
                or coalesce((public.fn_agent_may_act('accountant', 'overcharge_return', f.amount_fils / 100.0)->>'may_act')::boolean, false))) then
        raise exception 'the CEO may not approve this overcharge return: it is not exactly what the accountant''s check says is owed back, or the check records no decision to return it'
          using errcode = '23514';
      end if;
      return NEW;
    end if;
  else
    if NEW.state <> 'ceo_authorized' or (TG_OP = 'UPDATE' and OLD.state = 'ceo_authorized') then return NEW; end if;
    v_tx := NEW.transaction_id;
  end if;
  if v_tx is null then
    raise exception 'the CEO may not approve a refund that names no payment' using errcode = '23514';
  end if;
  v := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
  if not (v->>'ok')::boolean then
    raise exception 'the CEO may not approve this refund: % check(s) failed — %', jsonb_array_length(v->'failed'),
      (select string_agg((i->>'item') || ': ' || coalesce(i->>'reason', ''), ' | ') from jsonb_array_elements(v->'failed') i)
      using errcode = '23514',
            hint = 'Founder, 14 Sep 2026: the CEO''s approval exists to make sure the process was done correctly. fn_ceo_refund_review runs the checklist, records the evidence and sends each failure to the seat that owns it.';
  end if;
  return NEW;
end $function$;
revoke execute on function public.fn_ceo_refund_approval_checks_the_process() from public, anon, authenticated;

-- ══ 11. PAID BUT NOT RECORDED ═════════════════════════════════════════════════════════════════════════
create or replace function public.fn_accountant_payment_unrecorded(p_payment_ref text, p_quote_id text, p_amount_fils bigint, p_customer_id text, p_reason text, p_demo boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_p jsonb; v_it bigint; v_cs bigint; v_cust uuid; v_inq uuid;
begin
  if coalesce(btrim(p_payment_ref), '') = '' then return jsonb_build_object('ok', false, 'reason', 'a payment reference is required'); end if;
  if p_quote_id ~ v_uuid then select q.inquiry_id into v_inq from public.quotes q where q.id = p_quote_id::uuid; end if;
  v_cust := case when p_customer_id ~ v_uuid then p_customer_id::uuid
                 else (select i.customer_id from public.inquiries i where i.id = v_inq) end;
  v_p := jsonb_build_object('payment_ref', p_payment_ref, 'quote_id', case when p_quote_id ~ v_uuid then p_quote_id end,
    'inquiry_id', v_inq, 'customer_id', v_cust, 'amount_fils', p_amount_fils, 'reason', left(coalesce(p_reason, ''), 500),
    'seen_at', now())
    || case when p_demo then jsonb_build_object('rehearsal', 'Stripe test-mode payment') else '{}'::jsonb end
    -- Stripe's own mode of the event (review 2, item 6): a live payment's handoff is filed whoever it names
    || jsonb_build_object('livemode', not p_demo);
  -- p_demo = the payment arrived in Stripe TEST mode (stripe_webhook's sigMode): the shadow only, whoever paid (R2)
  if p_demo then
    perform public.fn_demo_shadow_record('handoff', 'payment.unrecorded', 'accountant', 'it_engineer', v_p);
    perform public.fn_demo_shadow_record('handoff', 'payment.unrecorded', 'accountant', 'customer_support', v_p);
    return jsonb_build_object('ok', true, 'shadow', true);
  end if;
  v_it := public.fn_seat_handoff('accountant', 'it_engineer', 'payment.unrecorded', 'payments', p_payment_ref, v_p);
  v_cs := public.fn_seat_handoff('accountant', 'customer_support', 'payment.unrecorded', 'payments', p_payment_ref, v_p);
  return jsonb_build_object('ok', true, 'it_engineer_handoff', v_it, 'customer_support_handoff', v_cs);
end $fn$;
revoke execute on function public.fn_accountant_payment_unrecorded(text, text, bigint, text, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_accountant_payment_unrecorded(text, text, bigint, text, text, boolean) to service_role;

create or replace function public.fn_it_engineer_takes_unrecorded_payment(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  perform public.fn_it_engineer_finding_upsert(
    p_issue_key => 'reveal:paid_not_recorded:' || (a.detail->>'payment_ref'),
    p_title => 'A customer paid a reveal and no sale was recorded: ' || left(coalesce(a.detail->>'reason', ''), 120),
    p_where => 'stripe_webhook (recordRevealSale) -> accountant.reveal_reconcile heals within the hour',
    p_blast => 'customer_facing', p_affected => 1,
    p_evidence => a.detail || jsonb_build_object('owner_seat', 'it_engineer', 'handoff_id', a.id),
    p_raised_by => 'accountant');
  return jsonb_build_object('finding', 'reveal:paid_not_recorded:' || (a.detail->>'payment_ref'),
    'waiting', 'the sale to be recorded (the webhook retry or the accountant''s hourly reconcile); the heal is reported on this handoff');
end $fn$;
revoke execute on function public.fn_it_engineer_takes_unrecorded_payment(bigint) from public, anon, authenticated;

-- customer_support tells the customer ONCE, in the request's language, that the payment arrived.
create or replace function public.fn_customer_support_tells_payment_received(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; c record; v_ar boolean; v_nid bigint; v_amt text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  select id, email into c from public.customers where id = (a.detail->>'customer_id')::uuid;
  if c.email is null or c.email !~ '@' then
    return jsonb_build_object('told', false, 'reason', 'no customer or no e-mail on the payment',
      'waiting', 'the sale to be recorded; the heal is reported on this handoff');
  end if;
  if exists (select 1 from public.notifications n where n.type = 'payment_received_reveal_pending' and n.to_email = c.email
                and n.subject is not null and n.body like '%' || left(a.detail->>'payment_ref', 40) || '%') then
    return jsonb_build_object('told', true, 'already', true, 'waiting', 'the sale to be recorded; the heal is reported on this handoff');
  end if;
  v_ar := public.fn_customer_notice_locale(nullif(a.detail->>'inquiry_id', '')::uuid, c.id) = 'ar';
  v_amt := coalesce(to_char((a.detail->>'amount_fils')::numeric / 100.0, 'FM999,999,990.00'), '');
  insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, lang)
  values ('payment_received_reveal_pending', c.email, 'customer', nullif(a.detail->>'inquiry_id', '')::uuid, nullif(a.detail->>'quote_id', '')::uuid,
    case when v_ar then 'استلمنا دفعتكم' else 'We have received your payment' end,
    case when v_ar
      then 'استلمنا دفعتكم البالغة ' || v_amt || ' درهم لرسوم الكشف، ونعمل على إتمام الكشف عن بيانات المورّد. ستصلكم رسالة التأكيد والفاتورة قريبًا، ولا حاجة إلى الدفع مرة أخرى. مرجع الدفع: ' || (a.detail->>'payment_ref')
      else 'We have received your payment of AED ' || v_amt || ' for the reveal fee, and we are completing your reveal of the supplier''s contact details. You will receive the confirmation and your invoice shortly; there is no need to pay again. Payment reference: ' || (a.detail->>'payment_ref')
    end,
    case when v_ar then 'ar' else 'en' end)
  returning id into v_nid;
  return jsonb_build_object('told', true, 'notification_id', v_nid, 'language', case when v_ar then 'ar' else 'en' end,
    'waiting', 'the sale to be recorded; the heal is reported on this handoff');
end $fn$;
revoke execute on function public.fn_customer_support_tells_payment_received(bigint) from public, anon, authenticated;


-- ══ 12. AT THE SALE: OUR INVOICE NUMBER, reveal.reconcile, a heal reported back; reveal.paid ONCE paid_at IS KNOWN ══
-- reveal.paid (the customer's receipt and the chosen supplier's notice, composed by the sales engineer) waits for
-- Stripe's paid time, so the window date it prints (refund_window_sentence_en / _ar) never moves afterwards. In the
-- checkout flow stripe_webhook writes paid_at seconds after the insert; if Stripe gives none, the accountant's reconcile
-- uses the insert time after 15 minutes (paid_at_source says so) and reveal.paid goes then.
create or replace function public.trg_reveal_receipt()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare v_test boolean; v_inv text; v_ends timestamptz; v_h record; v_paid jsonb; v_sale boolean; v_told boolean;
begin
  if NEW.revealed_at is null then return NEW; end if;
  v_sale := TG_OP = 'INSERT' or OLD.revealed_at is null;                                   -- the sale was just written
  v_told := NEW.paid_at is not null and (TG_OP = 'INSERT' or OLD.paid_at is null or OLD.revealed_at is null);  -- its clock is now known
  if not v_sale and not v_told then return NEW; end if;
  v_test := coalesce(NEW.livemode = false, false);
  -- nothing added here may fail the sale: a number that cannot be allocated now is allocated by the reconcile
  begin v_inv := public.fn_reveal_invoice_number(NEW.id); exception when others then v_inv := null; end;

  if v_sale then
    if v_test then
      perform public.fn_demo_shadow_record('invoice_number', 'our_invoice_no', 'accountant', null, jsonb_build_object('transaction_id', NEW.id, 'our_invoice_no', v_inv));
      perform public.fn_demo_shadow_record('handoff', 'reveal.reconcile', 'sales_engineer', 'accountant',
        jsonb_build_object('transaction_id', NEW.id, 'quote_id', NEW.quote_id, 'our_invoice_no', v_inv));
    else
      -- the accountant is TOLD: the sale was made in the sales engineer's portal; the accountant reconciles and books it
      perform public.fn_seat_handoff('sales_engineer', 'accountant', 'reveal.reconcile', 'transactions', NEW.id::text,
        jsonb_build_object('transaction_id', NEW.id, 'quote_id', NEW.quote_id, 'inquiry_id', NEW.inquiry_id,
                           'customer_id', NEW.customer_id, 'payment_ref', NEW.payment_ref, 'stripe_invoice_id', NEW.stripe_invoice_id,
                           'our_invoice_no', v_inv, 'question', 'Reconcile this payment against our invoice and book it.'));
    end if;
    -- the check runs whatever the handoff did (a test-mode sale files none; the handler already ran it for a live one)
    if not exists (select 1 from public.accountant_reveal_payment_check k where k.transaction_id = NEW.id) then
      begin perform public.fn_accountant_reconciles_reveal(NEW.id, true); exception when others then null; end;
    end if;
    -- A PAYMENT THAT WAS NOT RECORDED IS NOW: the heal is reported to the it_engineer and to customer_support.
    begin
    for v_h in select a.id from public.agent_actions a
                where a.kind = 'handoff' and a.detail->>'type' = 'payment.unrecorded' and a.status <> 'done'
                  and (a.detail->>'quote_id' = NEW.quote_id::text or a.detail->>'payment_ref' = NEW.payment_ref) loop
      perform public.fn_seat_handoff_complete(v_h.id, jsonb_build_object('healed', true, 'transaction_id', NEW.id,
        'recorded_at', now(), 'reply', 'the sale is recorded (transaction ' || left(NEW.id::text, 8) || '); the customer receives the reveal confirmation and invoice through reveal.paid'));
    end loop;
    exception when others then null;   -- the heal report never fails the sale; the handoffs stay open and visible
    end;
  end if;

  if v_told then
    v_ends := coalesce(NEW.refund_deadline, public.fn_reveal_refund_window_ends(least(NEW.paid_at, now())));
    -- the sales engineer's reveal.paid: the same payload as before, plus fields (none removed)
    v_paid := jsonb_build_object('transaction_id', NEW.id, 'customer_id', NEW.customer_id, 'supplier_id', NEW.supplier_id,
                         'inquiry_id', NEW.inquiry_id, 'quote_id', NEW.quote_id, 'revealed_at', NEW.revealed_at,
                         'paid_at', NEW.paid_at, 'paid_at_source', NEW.paid_at_source, 'refund_window_ends_at', v_ends, 'our_invoice_no', v_inv,
                         'refund_window_sentence_en', 'The supplier must respond within the refund window, which ends on '
                            || to_char(v_ends at time zone 'Asia/Dubai', 'FMDD Mon YYYY') || ' at 23:59 UAE time (five working days from your payment).',
                         'refund_window_sentence_ar', 'يجب أن يردّ المورّد خلال مهلة الاسترداد التي تنتهي في ' || to_char(v_ends at time zone 'Asia/Dubai', 'DD/MM/YYYY')
                            || ' الساعة 23:59 بتوقيت الإمارات (خمسة أيام عمل من تاريخ الدفع).');
    if v_test then perform public.fn_demo_shadow_record('handoff', 'reveal.paid', 'accountant', 'sales_engineer', v_paid);
    else perform public.fn_seat_handoff('accountant', 'sales_engineer', 'reveal.paid', 'transactions', NEW.id::text, v_paid);
    end if;
  end if;
  return NEW;
end $function$;
revoke execute on function public.trg_reveal_receipt() from public, anon, authenticated;
create or replace trigger z20_reveal_receipt after insert or update of revealed_at, paid_at on public.transactions
  for each row execute function public.trg_reveal_receipt();

-- ══ 13. THE SWEEP, EVERY 15 MINUTES: re-read, escalate within the hour, never close, purge test-mode shadows ═══
-- Each row in its own block: one bad row raises an it_engineer finding and the sweep goes on (review item 8).
create or replace function public.fn_accountant_payment_checks_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; n_reread int := 0; n_escalated int := 0; n_final int := 0; n_purged int := 0; n_failed int := 0;
begin
  -- facts still missing, or a sale with no check at all: read again (stripe_webhook or the accountant runtime may have
  -- filled them; the runtime's hourly reconcile reads Stripe itself for these)
  for r in select k.transaction_id as id from public.accountant_reveal_payment_check k where k.verdict = 'waiting_for_facts' and k.resolved_at is null
           union
           select t.id from public.transactions t
            where t.fee_status = 'paid' and t.revealed_at is not null and least(coalesce(t.paid_at, t.revealed_at), now()) >= now() - interval '30 days'
              and not exists (select 1 from public.accountant_reveal_payment_check k where k.transaction_id = t.id)
  loop
    begin perform public.fn_accountant_reconciles_reveal(r.id); n_reread := n_reread + 1;
    exception when others then n_failed := n_failed + 1;
      perform public.fn_it_engineer_finding_upsert(p_issue_key => 'reveal:payment_check_failed:' || r.id,
        p_title => 'The accountant''s check of a paid reveal raised: ' || left(sqlerrm, 150), p_where => 'public.fn_accountant_payment_checks_sweep',
        p_blast => 'internal', p_affected => 1, p_evidence => jsonb_build_object('transaction_id', r.id, 'error', left(sqlerrm, 500), 'owner_seat', 'accountant'),
        p_raised_by => 'accountant');
    end;
  end loop;
  -- WITHIN THE HOUR: an exception the model has not decided goes to the CEO (and the founder is told) at 45 minutes.
  for r in select transaction_id from public.accountant_reveal_payment_check
            where verdict = 'exception' and resolved_at is null and ceo_handoff_id is null and investigate_requested_at is null
              and opened_at <= now() - interval '45 minutes' loop
    begin
      perform public.fn_accountant_escalates_payment_exception(r.transaction_id, 'code: not judged within 45 minutes', 'escalate_to_ceo',
        'The accountant''s judgement did not arrive in time (the model was held or slow), so the facts go to the CEO as they stand.');
      n_escalated := n_escalated + 1;
    exception when others then n_failed := n_failed + 1;
      perform public.fn_it_engineer_finding_upsert(p_issue_key => 'reveal:payment_escalation_failed:' || r.transaction_id,
        p_title => 'A payment exception could not be escalated to the CEO: ' || left(sqlerrm, 150), p_where => 'public.fn_accountant_payment_checks_sweep',
        p_blast => 'internal', p_affected => 1, p_evidence => jsonb_build_object('transaction_id', r.transaction_id, 'error', left(sqlerrm, 500), 'owner_seat', 'accountant'),
        p_raised_by => 'accountant');
    end;
  end loop;
  -- 'investigate': the accountant read Stripe again (stripe_read_at after the request) or an hour passed without it:
  -- the CEO gets the FINAL question, a new occurrence, with whatever Stripe gave
  for r in select transaction_id from public.accountant_reveal_payment_check
            where resolved_at is null and investigate_requested_at is not null
              and (stripe_read_at > investigate_requested_at or investigate_requested_at <= now() - interval '1 hour') loop
    begin
      perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || r.transaction_id::text));   -- lock order: item 6b
      update public.accountant_reveal_payment_check
         set exception_count = exception_count + 1, ceo_handoff_id = null, held_question_id = -1, investigate_requested_at = null, opened_at = now()
       where transaction_id = r.transaction_id;
      perform public.fn_accountant_escalates_payment_exception(r.transaction_id, 'accountant (code): Stripe''s objects gathered for the CEO', 'escalate_to_ceo',
        'The CEO asked for more facts; the accountant read the payment, the invoice and the balance transaction from Stripe again (stripe_snapshot).', true);
      n_final := n_final + 1;
    exception when others then n_failed := n_failed + 1;
    end;
  end loop;
  -- A LIVE CHECK WHOSE SALE IS MATCHED BUT WHOSE CEO NOTICE FAILED: tell the CEO again (the books are already written)
  for r in select k.transaction_id from public.accountant_reveal_payment_check k
            where k.verdict = 'matched' and not k.is_test_mode and k.sale_notice_at is null and k.checked_at <= now() - interval '10 minutes' loop
    begin
      perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || r.transaction_id::text));   -- lock order: item 6b
      perform public.fn_accountant_tells_ceo_of_sale(r.transaction_id);
      update public.accountant_reveal_payment_check set sale_notice_at = now() where transaction_id = r.transaction_id;
    exception when others then n_failed := n_failed + 1;
    end;
  end loop;
  -- THE CALENDAR THE WINDOW COUNTS ON (review 2): public_holidays must reach a year ahead, or a holiday after its last
  -- date counts as a working day and every window ends a day early.
  begin
    if coalesce((select max(holiday_date) from public.public_holidays), current_date) < current_date + 365 then
      perform public.fn_it_engineer_finding_upsert(p_issue_key => 'calendar:public_holidays_running_out',
        p_title => 'public_holidays lists UAE holidays only to ' || coalesce((select max(holiday_date) from public.public_holidays)::text, 'nothing')
                   || ': add the next year''s, or refund windows will count a holiday as a working day',
        p_where => 'public.public_holidays (read by fn_is_working_day)', p_blast => 'customer_facing', p_affected => 0,
        p_evidence => jsonb_build_object('last_listed', (select max(holiday_date) from public.public_holidays), 'owner_seat', 'accountant'),
        p_raised_by => 'accountant');
    end if;
  exception when others then n_failed := n_failed + 1;
  end;
  -- test-mode evidence only: a live payment's check is never purged
  delete from public.demo_shadow_trace where keep_until < now();
  get diagnostics n_purged = row_count;
  delete from public.accountant_reveal_payment_check where is_test_mode and opened_at < now() - interval '14 days';
  return jsonb_build_object('reread', n_reread, 'escalated_to_ceo', n_escalated, 'final_questions', n_final, 'failed_rows', n_failed,
    'shadow_purged', n_purged,
    'open_exceptions', (select count(*) from public.accountant_reveal_payment_check where verdict = 'exception' and resolved_at is null and not is_test_mode));
end $fn$;
revoke execute on function public.fn_accountant_payment_checks_sweep() from public, anon, authenticated;

do $cron$ begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('accountant_payment_checks_hourly', 'accountant_payment_checks');
  perform cron.schedule('accountant_payment_checks', '8,23,38,53 * * * *', $job$select public.fn_accountant_payment_checks_sweep();$job$);
end $cron$;

-- A dispute opened or moved on a payment re-runs the accountant's check: a NEW occurrence (exception 'disputed').
create or replace function public.trg_dispute_reopens_the_payment_check()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_tx uuid;
begin
  v_tx := coalesce(NEW.transaction_id, (select t.id from public.transactions t where t.payment_ref = NEW.payment_intent limit 1));
  if v_tx is null then return NEW; end if;
  perform pg_advisory_xact_lock(hashtext('reveal_invoice_no:' || v_tx::text));   -- lock order: item 6b
  if NEW.status not in ('won') then
    update public.accountant_reveal_payment_check set resolved_at = null, verdict = 'exception',
           resolution = 'reopened: a card dispute ' || NEW.status, ceo_handoff_id = null, held_question_id = null
     where transaction_id = v_tx and not (findings @> '[{"code":"disputed"}]'::jsonb and resolved_at is null);
  end if;
  perform public.fn_accountant_reconciles_reveal(v_tx);
  return NEW;
exception when others then
  return NEW;   -- recording the dispute never fails on the check; the sweep re-reads it
end $fn$;
revoke execute on function public.trg_dispute_reopens_the_payment_check() from public, anon, authenticated;
create or replace trigger z60_dispute_reopens_the_payment_check after insert or update of status on public.stripe_dispute
  for each row execute function public.trg_dispute_reopens_the_payment_check();


-- ══ 14. THE BOOKS: the sale, refunds at the amount refunded, disputes and their fee ═══════════════════
create or replace function public.fn_gl_sync_business()
returns integer language plpgsql set search_path to 'public', 'pg_temp' as $function$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2); extra numeric(18,2); lines jsonb; v_orphans jsonb;
        v_jid bigint; v_over numeric(18,2); v_from_over numeric(18,2);
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  select num_value into fx        from public.gl_settings where key='usd_to_aed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);
  fx        := coalesce(fx, 3.6725);

  -- TEST MONEY NEVER REACHES THE BOOKS (15 Sep 2026; 13 Nov 2026, R2). A reveal payment is test money exactly when Stripe
  -- says so (transactions.livemode = false): its lines go to public.demo_shadow_trace (fn_gl_post_reveal_fee). A LIVE
  -- payment is booked whoever it touches; only an orphan (its transaction gone) is not. The other branches keep
  -- fn_gl_fixture_or_orphan. Journal #690 was an E2E fixture due whose supplier and transaction the teardown had deleted.

  -- 1) Reveal-fee revenue with Stripe fee split (refunded transactions excluded)
  --    13 Nov 2026 (accountant): posted by fn_gl_post_reveal_fee once Stripe's own card fee is in (stripe_fee_fils from
  --    the balance transaction): Dr 1050 net / Dr 6100 card fee / Cr 4000 the fee / Cr 2300 anything charged above it.
  --    The memo names our invoice (reveal_invoices.invoice_no) and Stripe's (transactions.stripe_invoice_number). No VAT
  --    line, no estimated card fee (until it is read the sale is "paid, awaiting Stripe's figures" in the founder brief and
  --    an exception to the CEO after an hour), no Invoicing-fee accrual (fn_accountant_book_stripe_fees books it when
  --    Stripe bills it, R1). The advisory lock in fn_gl_post_reveal_fee and gl_journal_one_entry_per_reveal_money_event
  --    make it one journal under concurrency.
  for r in
    select t.id, t.stripe_invoice_number
    from public.transactions t
    where t.fee_status='paid' and coalesce(t.reveal_fee,0) > 0 and t.stripe_fee_fils is not null and t.livemode
      and coalesce(t.refund_status,'') not in ('refunded','refund_approved','succeeded')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=t.id::text and g.status <> 'void')
      and coalesce(public.fn_gl_fixture_or_orphan(t.id, null, null), '') not like 'orphan:%'
  loop
    v_jid := public.fn_gl_post_reveal_fee(r.id);
    if v_jid is not null then n := n + 1; end if;
  end loop;

  -- 1b) A REFUND PAID OUT, AT THE AMOUNT ACTUALLY REFUNDED (13 Nov 2026, R3). Each settled refund (public.refunds,
  --     status succeeded) is its own journal (source_ref 'refund:<id>'): what was charged above the fee comes back out of
  --     2300 first, then the fee through 6900 (the refunds expense the supplier's non-response clawback credits back);
  --     the Stripe fee booked at sale stays in 6100, absorbed. A refund recorded only on the transaction (no refunds row,
  --     before 13 Nov) keeps the old reading: the whole charge, source_ref the transaction. If the sale was never booked,
  --     the only real movement is the fee Stripe kept: 6100 / 1050, at STRIPE'S OWN figure (stripe_fee_fils) and only once
  --     Stripe has reported it; until then the refund waits (review 4, item 3: it was estimated from gl_settings, 23.55
  --     where Stripe kept 34.48). A refund made in the Stripe dashboard carries no transaction_id: it is matched to the sale
  --     by its PaymentIntent (review 4, item 6c; fn_refund_settle also writes the match). A test-mode refund is never booked.
  for r in
    select 'refund:' || f.id as ref, f.id as refund_id, t.id as tx, round(f.amount_fils / 100.0, 2) as amt,
           coalesce(f.settled_at, f.updated_at, now())::date as d,
           exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=t.id::text and g.status <> 'void') as sale_booked,
           coalesce((select ri.invoice_no from public.reveal_invoices ri where ri.transaction_id = t.id), t.stripe_invoice_number, left(t.id::text, 8)) as inv,
           greatest(coalesce(t.stripe_amount_received_fils / 100.0, t.total_charged, t.reveal_fee) - t.reveal_fee, 0) as over_aed,
           round(t.stripe_fee_fils / 100.0, 2) as fee_absorbed
      from public.refunds f join public.transactions t
        on t.id = f.transaction_id or (f.transaction_id is null and f.stripe_payment_intent is not null and f.stripe_payment_intent = t.payment_ref)
     where f.status = 'succeeded' and coalesce(f.amount_fils, 0) > 0 and t.livemode
       and not exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref in ('refund:' || f.id, t.id::text) and g.status <> 'void')
       and coalesce(public.fn_gl_fixture_or_orphan(t.id, null, null), '') not like 'orphan:%'
    union all
    select t.id::text, null, t.id, round(coalesce(t.refund_amount_aed, t.total_charged, t.reveal_fee, t.app_fee, 0), 2),
           coalesce(t.refund_resolved_at::date, t.revealed_at::date, current_date),
           exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=t.id::text and g.status <> 'void'),
           coalesce((select ri.invoice_no from public.reveal_invoices ri where ri.transaction_id = t.id), t.stripe_invoice_number, left(t.id::text, 8)),
           greatest(coalesce(t.stripe_amount_received_fils / 100.0, t.total_charged, t.reveal_fee) - t.reveal_fee, 0),
           round(t.stripe_fee_fils / 100.0, 2)
      from public.transactions t
     where coalesce(t.refund_status,'') in ('refunded','refund_approved','succeeded') and t.livemode
       and coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) > 0
       and not exists (select 1 from public.refunds f where f.status = 'succeeded'
                        and (f.transaction_id = t.id or (f.transaction_id is null and f.stripe_payment_intent is not null and f.stripe_payment_intent = t.payment_ref)))
       and not exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref=t.id::text and g.status <> 'void')
       and coalesce(public.fn_gl_fixture_or_orphan(t.id, null, null), '') not like 'orphan:%'
  loop
    perform pg_advisory_xact_lock(hashtext('refund_paid:' || r.ref));
    if exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref=r.ref and g.status <> 'void') then continue; end if;
    gross := r.amt;
    if r.sale_booked then
      -- what is left of the overcharge in 2300 (earlier returns already took theirs)
      v_over := greatest(r.over_aed - coalesce((select sum(l.debit) from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
                  where g.source = 'refund_paid' and g.status <> 'void' and l.account_code = '2300'
                    and (g.source_ref = r.tx::text or g.source_ref in (select 'refund:' || x.id from public.refunds x where x.transaction_id = r.tx))), 0), 0);
      v_from_over := least(gross, v_over);
      lines := '[]'::jsonb;
      if v_from_over > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','2300','debit',v_from_over,'memo','charged above the fee, returned')); end if;
      if gross - v_from_over > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6900','debit',gross - v_from_over)); end if;
      lines := lines || jsonb_build_array(jsonb_build_object('account','1050','credit',gross));
      perform public.fn_gl_entry(r.d, 'Reveal payment refunded to the customer: AED ' || gross || ', invoice ' || r.inv
        || case when v_from_over > 0 then ' (AED ' || v_from_over || ' of it charged above the fee)' else '' end
        || '; the Stripe fee booked at sale stays in 6100, absorbed', 'refund_paid', r.ref, lines, 'gl_sync');
      n := n + 1;
    else
      if r.fee_absorbed is null then continue; end if;   -- Stripe has not reported its fee yet: no estimate, the next run books it
      fee := least(round(r.fee_absorbed, 2), gross);
      if fee > 0 then
        perform public.fn_gl_entry(r.d, 'Stripe processing fee absorbed on a reveal refunded before its sale was booked, invoice ' || r.inv,
          'refund_paid', r.ref,
          jsonb_build_array(jsonb_build_object('account','6100','debit',fee),
                            jsonb_build_object('account','1050','credit',fee)), 'gl_sync');
        n := n + 1;
      end if;
    end if;
  end loop;

  -- 1c) A CARD DISPUTE (13 Nov 2026, R3). Stripe withdraws the disputed amount when the dispute opens: Dr 6900 / Cr 1050,
  --     or Dr 1100 (a claim to recover) when the charge was already refunded, so the same money is never expensed twice.
  --     Stripe's dispute fee (stripe_dispute.fee_fils, from the dispute's balance transactions): Dr 6100 / Cr 1050, and
  --     reversed when Stripe returns it (fee_returned_fils). A dispute won returns the amount: Dr 1050 / Cr the account it
  --     was booked to. Only a LIVE dispute is booked.
  for r in
    select d.id, d.amount_fils, d.status, d.transaction_id, coalesce(d.fee_fils, 0) as fee_fils, coalesce(d.fee_returned_fils, 0) as fee_back,
           coalesce(d.first_seen_at::date, current_date) as d1, coalesce(d.closed_at::date, current_date) as d2,
           exists (select 1 from public.gl_journal g where g.source = 'refund_paid' and g.status <> 'void'
                    and (g.source_ref = d.transaction_id::text or g.source_ref in (select 'refund:' || x.id from public.refunds x where x.transaction_id = d.transaction_id))) as refunded
    from public.stripe_dispute d
    where d.livemode and coalesce(d.amount_fils, 0) > 0 and lower(coalesce(d.currency, 'aed')) = 'aed'
      and (d.transaction_id is null or coalesce(public.fn_gl_fixture_or_orphan(d.transaction_id, null, null), '') not like 'orphan:%')
  loop
    perform pg_advisory_xact_lock(hashtext('dispute:' || r.id));
    acct := coalesce((select l.account_code from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
                       where g.source = 'dispute_withdrawn' and g.source_ref = r.id and g.status <> 'void' and l.debit > 0 limit 1),
                     case when r.refunded then '1100' else '6900' end);
    if not exists (select 1 from public.gl_journal g where g.source='dispute_withdrawn' and g.source_ref=r.id and g.status <> 'void') then
      perform public.fn_gl_entry(r.d1, 'Card dispute ' || r.id || ': Stripe withdrew the disputed amount'
        || case when acct = '1100' then ' from a charge already refunded (to recover)' else '' end, 'dispute_withdrawn', r.id,
        jsonb_build_array(jsonb_build_object('account', acct, 'debit', r.amount_fils / 100.0),
                          jsonb_build_object('account','1050','credit', r.amount_fils / 100.0)), 'gl_sync');
      n := n + 1;
    end if;
    if r.fee_fils > 0 and not exists (select 1 from public.gl_journal g where g.source='dispute_fee' and g.source_ref=r.id and g.status <> 'void') then
      perform public.fn_gl_entry(r.d1, 'Card dispute ' || r.id || ': Stripe''s dispute fee', 'dispute_fee', r.id,
        jsonb_build_array(jsonb_build_object('account','6100','debit', r.fee_fils / 100.0),
                          jsonb_build_object('account','1050','credit', r.fee_fils / 100.0)), 'gl_sync');
      n := n + 1;
    end if;
    if r.fee_back > 0 and not exists (select 1 from public.gl_journal g where g.source='dispute_fee_returned' and g.source_ref=r.id and g.status <> 'void') then
      perform public.fn_gl_entry(r.d2, 'Card dispute ' || r.id || ': Stripe returned its dispute fee', 'dispute_fee_returned', r.id,
        jsonb_build_array(jsonb_build_object('account','1050','debit', r.fee_back / 100.0),
                          jsonb_build_object('account','6100','credit', r.fee_back / 100.0)), 'gl_sync');
      n := n + 1;
    end if;
    if r.status = 'won' and not exists (select 1 from public.gl_journal g where g.source='dispute_won' and g.source_ref=r.id and g.status <> 'void') then
      perform public.fn_gl_entry(r.d2, 'Card dispute ' || r.id || ' won: Stripe returned the disputed amount', 'dispute_won', r.id,
        jsonb_build_array(jsonb_build_object('account','1050','debit', r.amount_fils / 100.0),
                          jsonb_build_object('account', acct, 'credit', r.amount_fils / 100.0)), 'gl_sync');
      n := n + 1;
    end if;
  end loop;


  -- 2) Clawback RAISED on the supplier. Credits 6900 (recovering the refund), NOT 4100.
  --    Any admin fee / interest assessed at the same time is genuine income -> 4400.
  --    A due with no supplier is judged as one whose supplier is gone (-1 is never a lead id).
  for r in
    select id, amount_due,
           coalesce(admin_fee,0) + coalesce(interest_amount,0) as extra_owed,
           coalesce(reveal_date, created_at::date, current_date) as d
    from public.supplier_dues
    where coalesce(amount_due,0) > 0
      and coalesce(status,'') not in ('waived','cancelled','reversed','void')
      and not exists (select 1 from public.gl_journal g where g.source='commission_accrue' and g.source_ref=supplier_dues.id::text)
      and public.fn_gl_fixture_or_orphan(supplier_dues.transaction_id, coalesce(supplier_dues.supplier_id, -1), null) is null
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    lines := jsonb_build_array(
      jsonb_build_object('account','1110','debit', round(r.amount_due,2) + extra),
      jsonb_build_object('account','6900','credit', round(r.amount_due,2)));
    if extra > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','4400','credit', extra)); end if;
    perform public.fn_gl_entry(r.d,
      'Refund clawback raised on supplier' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_accrue', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2b) Supplier SETTLES via Stripe.
  for r in
    select id, amount_due,
           coalesce(fine_amount,0) + coalesce(interest_amount,0) + coalesce(admin_fee,0) as extra_owed,
           paid_at::date as d
    from public.supplier_dues
    where status in ('paid','settled') and paid_at is not null and coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_collect' and g.source_ref=supplier_dues.id::text)
      and public.fn_gl_fixture_or_orphan(supplier_dues.transaction_id, coalesce(supplier_dues.supplier_id, -1), null) is null
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    gross := round(r.amount_due,2) + extra;
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;

    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','1110','credit', gross));

    perform public.fn_gl_entry(r.d,
      'Refund clawback settled by supplier via Stripe' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_collect', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2c) SUBSCRIPTION revenue (RULE 1). Previously never posted - 4200 sat unused.
  for r in
    select l.id, l.registration_fee_due, l.registration_paid_at::date as d
    from public.leads l
    where l.registration_status = 'paid'
      and l.registration_paid_at is not null
      and coalesce(l.registration_fee_due,0) >= 0
      and coalesce(l.subscription_exempt,false) = false
      and not exists (select 1 from public.gl_journal g
                      where g.source='subscription' and g.source_ref = l.id::text || ':' || l.registration_paid_at::date)
      and public.fn_gl_fixture_or_orphan(null, l.id, null) is null
  loop
    gross := round(coalesce(r.registration_fee_due,0),2);
    if gross <= 0 then continue; end if;
    fee := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net := gross - fee;
    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','4200','credit',gross));
    perform public.fn_gl_entry(r.d, 'Annual supplier subscription', 'subscription',
      r.id::text || ':' || r.d::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 3) Expense charges, converted to AED (the ledger currency). A ZZ DEMO expense is a rehearsal's, never
  --    the company's (the same marker the receipt duty uses).
  for r in
    select e.id, e.amount, upper(coalesce(e.currency,'AED')) as cur, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not ((coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo')
  loop
    if r.cur not in ('AED','USD') then
      begin
        insert into public.founder_alerts(level, event, detail, channel)
        values ('warn', 'gl_unconvertible_currency',
                'Expense #'||r.id||' from '||coalesce(r.vendor,'?')||' is in '||r.cur||
                ', which has no rate in gl_settings, so it was NOT posted. Expenses are understated by '||
                r.amount||' '||r.cur||' until a rate is added. Skipped rather than booked at 1:1.', 'system');
      exception when others then null; end;
      continue;
    end if;
    amt_aed := round(r.amount * case when r.cur='USD' then fx else 1 end, 2);
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'Expense: '||coalesce(r.category,'G&A')||case when r.cur='USD' then ' ('||r.amount||' USD @ '||fx||')' else '' end,
      'expense', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',amt_aed),
                        jsonb_build_object('account','1000','credit',amt_aed)), 'gl_sync');
    n := n + 1;
  end loop;

  -- 3b) One-off FX correction for USD expenses posted at 1:1 before the 19 Jul 2026 fix.
  for r in
    select e.id, e.amount, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d,
           (select sum(jl.debit) from public.gl_journal g
              join public.gl_journal_lines jl on jl.journal_id = g.id
             where g.source='expense' and g.source_ref = e.id::text and jl.debit > 0) as posted_aed
    from public.expense_entries e
    where upper(coalesce(e.currency,'AED')) = 'USD'
      and coalesce(e.amount,0) > 0
      and exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not exists (select 1 from public.gl_journal g where g.source='expense_fx_adj' and g.source_ref=e.id::text)
      and not ((coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo')
  loop
    diff := round(r.amount * fx, 2) - coalesce(r.posted_aed, 0);
    if diff is null or diff = 0 then continue; end if;
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'FX correction: expense #'||r.id||' ('||coalesce(r.vendor,'?')||') was booked at 1:1; restated at USD/AED '||fx,
      'expense_fx_adj', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',diff),
                        jsonb_build_object('account','1000','credit',diff)), 'gl_fx_fix');
    n := n + 1;
  end loop;

  -- 4) AN ORPHAN IS NEVER BOOKED SILENTLY. Every open money row whose transaction, supplier or customer is
  --    gone is an accountant finding; the same call closes it once the row is reversed, cancelled or
  --    waived. Fixtures are expected and raise nothing.
  select coalesce(jsonb_agg(jsonb_build_object('item', x.item, 'owner_seat', 'accountant', 'subject', x.subject,
           'title', x.subject || ' #' || x.id || ' (' || x.amount || ' AED) was not booked: ' || x.why,
           'blast', 'internal', 'affected', 0, 'demo', false,
           'evidence', jsonb_build_object('row', x.id, 'amount_aed', x.amount, 'why', x.why, 'no_founder_email', true,
             'remedy', 'find what created it; reverse any journal already posted from it (fn_gl_reverse), then set the row reversed or cancelled with status_reason'))
           order by x.item), '[]'::jsonb)
    into v_orphans
    from (select 'supplier_dues:' || d.id as item, 'supplier_dues' as subject, d.id::text as id,
                 round(coalesce(d.total_claim, d.amount_due), 2) as amount,
                 public.fn_gl_fixture_or_orphan(d.transaction_id, coalesce(d.supplier_id, -1), null) as why
            from public.supplier_dues d
           where coalesce(d.amount_due, 0) > 0 and coalesce(d.status, '') not in ('waived', 'cancelled', 'reversed', 'void')
          union all
          select 'transactions:' || t.id, 'transactions', t.id::text,
                 round(coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0), 2),
                 public.fn_gl_fixture_or_orphan(t.id, null, null)
            from public.transactions t
           where t.fee_status = 'paid' or coalesce(t.refund_status, '') in ('refunded', 'refund_approved', 'succeeded')) x
   where x.why like 'orphan:%';
  perform public.fn_it_duty_settle('ledger_orphan', v_orphans);

  return n;
end
$function$;
revoke execute on function public.fn_gl_sync_business() from public, anon, authenticated;


-- ══ 15. OUR INVOICE IS THE DOCUMENT; STRIPE'S IS THE BACK-OFFICE RECORD ═══════════════════════════════
create or replace function public.fn_accountant_files_reveal_invoice()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare
  v_doc bigint;
  v_h   bigint;
  v_inv text;
begin
  if new.doc_path is null or new.doc_path !~ '^invoices/' then return new; end if;
  if tg_op = 'UPDATE' and old.doc_path is not distinct from new.doc_path then return new; end if;

  -- STRIPE'S PDF IS THE ACCOUNTANT'S SOURCE RECORD, NOT THE CUSTOMER'S DOCUMENT (ruling 1671, 13 Nov 2026). It is filed
  -- against the transaction (not the inquiry), so fn_customer_document_refs never shows it; the Dropbox mirror keeps it
  -- under Finance. The customer's Documents get OUR invoice, filed by fn_accountant_files_our_reveal_invoice when
  -- reveal_invoice renders it. (bucket, path) is UNIQUE, so a replayed attach files nothing twice and hands off nothing twice.
  insert into public.documents (bucket, path, file_name, kind, ref_table, ref_id, mime, status)
  values ('finance-docs', new.doc_path,
          coalesce(nullif(new.doc_name, ''), 'Stripe invoice ' || coalesce(new.stripe_invoice_number, '') || '.pdf'),
          'stripe_invoice_record', 'transactions', new.id::text, 'application/pdf', 'done')
  on conflict (bucket, path) do nothing
  returning id into v_doc;
  if v_doc is null then return new; end if;
  begin v_inv := public.fn_reveal_invoice_number(new.id); exception when others then v_inv := null; end;

  perform public.fn_emit('invoice.issued', 'transaction', new.id::text, 'accountant',
    jsonb_build_object('document_id', v_doc, 'quote_id', new.quote_id, 'inquiry_id', new.inquiry_id,
                       'customer_id', new.customer_id, 'invoice_id', new.stripe_invoice_id,
                       'invoice_number', new.stripe_invoice_number, 'our_invoice_no', v_inv, 'total_charged', new.total_charged));

  -- The handoff names its conversation, its case, its decision and its ask, so its note can be stated.
  -- If it still cannot be filed, the invoice stays filed and the IT engineer is told which case lost it.
  begin
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'handoff', 'pending', 'low',
            'Reveal invoice ready - tell the customer',
            'Our invoice ' || coalesce(v_inv, '') || ' is rendered by reveal_invoice when the notice is queued (z30_invoice_ready_asks_for_its_invoice): attached to the e-mail if the render succeeds within the notice''s 10-minute hold, and filed in the customer''s Documents. If it fails the notice goes without it and says where to open the invoice.',
            jsonb_build_object('type', 'invoice.issued', 'from', 'accountant', 'from_name', 'Accountant', 'to', 'sales_engineer',
                               'subject', 'reveal_invoice', 'subject_table', 'transactions', 'subject_id', new.id::text,
                               'decision', 'accountant filed Stripe''s invoice as the back-office record (document ' || v_doc
                                           || ') and issues our invoice ' || coalesce(v_inv, '') || '; hands the notice to the sales engineer',
                               'question', 'Tell the customer their reveal invoice is ready, in the inquiry''s language.',
                               'transaction_id', new.id, 'quote_id', new.quote_id, 'inquiry_id', new.inquiry_id,
                               'customer_id', new.customer_id, 'document_id', v_doc,
                               'invoice_number', new.stripe_invoice_number, 'our_invoice_no', v_inv,
                               'refund_window_ends_at', new.refund_deadline),
            'transactions', new.id::text)
    returning id into v_h;
    perform public.fn_seat_handoff_event(v_h, 'sent');
  exception when others then
    perform public.fn_it_engineer_finding_upsert(
      'monitor:reveal_invoice_handoff_not_filed:' || new.id,
      'Reveal invoice filed but its handoff to the sales engineer was refused: ' || left(sqlerrm, 200),
      'public.fn_accountant_files_reveal_invoice (caller: accountant)', 'customer_facing', 1,
      jsonb_build_object('transaction_id', new.id, 'document_id', v_doc, 'error', left(sqlerrm, 500), 'owner_seat', 'accountant'),
      '{}'::text[], array['why the reveal_invoice handoff could not be filed for this transaction'], 'fn_accountant_files_reveal_invoice');
  end;
  return new;
end
$function$;
revoke execute on function public.fn_accountant_files_reveal_invoice() from public, anon, authenticated;

-- Our invoice PDF, rendered by reveal_invoice, filed into the customer's Documents (the vault reads documents under the
-- inquiry). Idempotent on (bucket, path); reveal_invoices keeps the number and the last file rendered.
create or replace function public.fn_accountant_files_our_reveal_invoice(p_tx uuid, p_bucket text, p_path text, p_file_name text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; v_doc bigint; v_inv text;
begin
  select * into t from public.transactions where id = p_tx;
  if not found or coalesce(btrim(p_path), '') = '' or p_path !~ '^reveal_invoice/' then return null; end if;
  v_inv := public.fn_reveal_invoice_number(p_tx);
  update public.reveal_invoices set bucket = coalesce(p_bucket, 'agent-docs'), path = p_path where transaction_id = p_tx;
  insert into public.documents (bucket, path, file_name, kind, ref_table, ref_id, mime, status)
  values (coalesce(p_bucket, 'agent-docs'), p_path, coalesce(nullif(p_file_name, ''), 'Invoice ' || coalesce(v_inv, '') || '.pdf'),
          'invoice', 'inquiries', t.inquiry_id::text, 'application/pdf', 'done')
  on conflict (bucket, path) do nothing
  returning id into v_doc;
  return v_doc;
end $fn$;
revoke execute on function public.fn_accountant_files_our_reveal_invoice(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_accountant_files_our_reveal_invoice(uuid, text, text, text) to service_role;

-- "Your invoice is ready" names OUR invoice and the date the refund window ends, in English or Arabic. The subject is
-- the WhatsApp template's only variable (send_whatsapp templates.ts, customer_reveal_invoice {{1}}, 90 characters), so
-- the end date is in the subject too.
create or replace function public.fn_sales_engineer_answers_reveal_invoice(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare
  a public.agent_actions;
  c record;
  v_ar boolean;
  v_nid bigint;
  v_inv text;
  v_ends timestamptz;
  v_en text; v_ardate text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'invoice.issued' then
    raise exception 'fn_sales_engineer_answers_reveal_invoice: % is not an invoice.issued handoff', p_id;
  end if;
  select id, email into c from public.customers where id = (a.detail->>'customer_id')::uuid;
  if c.email is null or c.email !~ '@' then
    return jsonb_build_object('told', false, 'reason', 'no email address on file for the customer');
  end if;
  v_inv := coalesce(a.detail->>'our_invoice_no', public.fn_reveal_invoice_number((a.detail->>'transaction_id')::uuid));
  select coalesce(t.refund_deadline, public.fn_reveal_refund_window_ends(coalesce(t.paid_at, t.revealed_at))) into v_ends
    from public.transactions t where t.id = (a.detail->>'transaction_id')::uuid;
  v_en := to_char(v_ends at time zone 'Asia/Dubai', 'DD Mon YYYY');
  v_ardate := to_char(v_ends at time zone 'Asia/Dubai', 'DD/MM/YYYY');
  v_ar := public.fn_customer_notice_locale((a.detail->>'inquiry_id')::uuid, c.id) = 'ar';
  insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, lang)
  values ('invoice_ready', c.email, 'customer',
          (a.detail->>'inquiry_id')::uuid, (a.detail->>'quote_id')::uuid,
          case when v_ar then 'فاتورتكم ' || coalesce(v_inv, '') || ' جاهزة · تنتهي مهلة الاسترداد ' || coalesce(v_ardate, '')
               else 'Invoice ' || coalesce(v_inv, '') || ' ready · refund window ends ' || coalesce(v_en, '') end,
          case when v_ar
            then 'أصبحت فاتورة رسوم الكشف رقم ' || coalesce(v_inv, '') || ' التي سددتموها متاحة في حسابكم على QuotesDone، ويمكنكم فتحها في أي وقت من زر «الفاتورة» على العرض الذي كشفتموه، أو من «المستندات» ضمن «الفواتير». '
                 || 'تنتهي مهلة الاسترداد لهذا الكشف في ' || coalesce(v_ardate, '') || '، أي بعد خمسة أيام عمل من تاريخ الدفع.'
            else 'The invoice for the reveal fee you paid, invoice ' || coalesce(v_inv, '') || ', is now in your QuotesDone account. Open it any time from the "Invoice (PDF)" button on the quote you revealed, or under Invoices in Documents. '
                 || 'The refund window for this reveal ends on ' || coalesce(v_en, '') || ', five working days from your payment.'
          end,
          case when v_ar then 'ar' else 'en' end)
  returning id into v_nid;
  return jsonb_build_object('told', true, 'notification_id', v_nid, 'language', case when v_ar then 'ar' else 'en' end,
    'our_invoice_no', v_inv, 'refund_window_ends_at', v_ends);
end
$function$;
revoke execute on function public.fn_sales_engineer_answers_reveal_invoice(bigint) from public, anon, authenticated;

-- ══ 16. THE FOUNDER'S BRIEF LISTS EACH SALE OF THE DAY ════════════════════════════════════════════════
create or replace function public.fn_founder_brief_sale_lines(p_from timestamptz, p_to timestamptz)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v text := ''; i int := 0; v_open int; v_wait int; v_unbooked text; v_unknown int; v_nothing text;
begin
  for r in
    select t.reveal_fee, t.quote_amount, coalesce(t.paid_at, t.revealed_at) as at, ii.category, ii.emirate,
           coalesce(ri.invoice_no, t.stripe_invoice_number) as inv, k.verdict
      from public.transactions t
      left join public.inquiries ii on ii.id = t.inquiry_id
      left join public.reveal_invoices ri on ri.transaction_id = t.id
      left join public.accountant_reveal_payment_check k on k.transaction_id = t.id
     where t.fee_status = 'paid' and coalesce(t.paid_at, t.revealed_at) >= p_from and coalesce(t.paid_at, t.revealed_at) < p_to
       and t.livemode          -- R2: only a payment Stripe says is live reaches the brief's sales (unknown ones are listed below)
     order by coalesce(t.paid_at, t.revealed_at)
  loop
    i := i + 1;
    v := v || E'\n   ' || i || ') AED ' || to_char(r.reveal_fee, 'FM999,999,990.00') || ' reveal fee on a quotation of AED '
         || to_char(r.quote_amount, 'FM999,999,990.00') || ' ex-VAT, ' || coalesce(r.category, 'trade not recorded')
         || coalesce(', ' || r.emirate, '') || ', invoice ' || coalesce(r.inv, '(not numbered)')
         || case coalesce(r.verdict, 'waiting_for_facts') when 'matched' then ', reconciled and booked' when 'exception' then ', NOT reconciled: with the CEO' when 'nothing_to_book' then ', nothing to book (see below)' else ', paid, awaiting Stripe''s figures (not booked yet)' end;
  end loop;
  select count(*) into v_open from public.accountant_reveal_payment_check where verdict = 'exception' and resolved_at is null and not is_test_mode;
  -- every LIVE paid sale with no journal, every day, whatever its check says; and every sale whose mode is unknown
  select count(*), coalesce(string_agg('since ' || to_char(least(coalesce(t.paid_at, t.revealed_at), now()) at time zone 'Asia/Dubai', 'DD Mon') || ' (' || left(t.id::text, 8) || ')', ', '), '')
    into v_wait, v_unbooked
    from public.transactions t
   where t.fee_status = 'paid' and t.livemode
     and not exists (select 1 from public.gl_journal g where g.source = 'reveal_fee' and g.source_ref = t.id::text and g.status <> 'void')
     and not exists (select 1 from public.accountant_reveal_payment_check k where k.transaction_id = t.id and k.verdict = 'nothing_to_book');
  select string_agg(left(k.transaction_id::text, 8) || ': ' || replace(k.resolution, 'nothing to book: ', ''), '; ' order by k.resolved_at) into v_nothing
    from public.accountant_reveal_payment_check k
   where k.verdict = 'nothing_to_book' and not k.is_test_mode and k.resolved_at >= p_from and k.resolved_at < p_to;
  select count(*) into v_unknown from public.transactions t where t.fee_status = 'paid' and t.livemode is null;
  return case when i = 0 then E'\n\nSales today: none.' else E'\n\nSales today (' || i || '):' || v end
      || case when v_wait > 0 then E'\nPaid, not yet booked: waiting for Stripe''s figures (' || v_wait || '): ' || v_unbooked || '.' else '' end
      || case when v_unknown > 0 then E'\nPaid, Stripe mode not known yet, not booked or counted: ' || v_unknown || '.' else '' end
      || case when v_nothing is not null then E'\nClosed with nothing to book: ' || v_nothing || '.' else '' end
      || case when v_open > 0 then E'\nPayment exceptions open with the CEO: ' || v_open || '.' else '' end;
end $fn$;
revoke execute on function public.fn_founder_brief_sale_lines(timestamptz, timestamptz) from public, anon, authenticated;

create or replace function public.fn_founder_brief(p_local_date date default null::date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare
  v_tz text := 'Asia/Dubai';
  v_day date := coalesce(p_local_date, (now() at time zone 'Asia/Dubai')::date);
  v_midnight timestamptz := (v_day::timestamp) at time zone 'Asia/Dubai';
  v_from timestamptz; v_to timestamptz; v_prev timestamptz;
  v_fig jsonb; v_body text; v_subj text; v_run bigint; v_alert uuid;
begin
  insert into public.agent_runs(agent, started_at) values ('brief', now()) returning id into v_run;

  -- The window starts where the previous brief ended, so 20:00-24:00 is never lost between days.
  select (figures->>'window_to')::timestamptz into v_prev
    from public.ceo_daily_digest
   where local_date < v_day and figures ? 'window_to'
   order by local_date desc limit 1;
  v_from := case when v_prev is null or v_prev < v_midnight - interval '1 day' then v_midnight else v_prev end;
  v_to   := least(now(), v_midnight + interval '1 day');

  v_fig  := public.fn_founder_brief_figures(v_from, v_to);
  v_body := public.fn_founder_brief_text(v_fig);
  -- 13 Nov 2026 (ledger 1685): each sale of the day, not only a count (fn_founder_brief_sale_lines)
  v_body := v_body || public.fn_founder_brief_sale_lines(v_from, v_to);
  -- ledger 1616: what the CEO decided in the window, told here and nowhere else (fn_founder_brief_ceo_lines)
  v_body := v_body || public.fn_founder_brief_ceo_lines(v_from, v_to);
  v_subj := 'QuotesDone daily brief - '||to_char(v_day,'Dy DD Mon');

  -- The Command Center row is written whether or not a recipient exists.
  insert into public.founder_alerts(level, event, detail, channel)
    values ('info', 'CEO end-of-day company digest', v_body, 'os') returning id into v_alert;

  -- Unchanged from the previous brief: fold the week's 'digest' notifications.
  update public.notifications set status = 'digested'
   where status = 'digest' and created_at >= now() - interval '7 days' and created_at <= now();

  update public.agent_runs set finished_at = now(), status = 'ok',
         counts = jsonb_build_object(
           'invitations', v_fig->'invitations'->'count', 'suppliers_registered', v_fig->'suppliers_registered'->'count',
           'inquiries', v_fig->'inquiries'->'count', 'customers', v_fig->'customers'->'count',
           'comparisons', v_fig->'comparisons'->'count', 'reveal_fees', v_fig->'reveal_fees'->'count')
   where id = v_run;

  return jsonb_build_object('subject', v_subj, 'body', v_body, 'figures', v_fig, 'command_center_id', v_alert);
end;
$function$;

-- ══ 17. ONCE PER CHANNEL: a retry never goes to a channel that already carries the notice ══════════════
create or replace function public.fn_originator_checks_delivery(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare
  a public.agent_actions; req public.agent_actions; n public.notifications; v_seat text; v_result text; v_seen jsonb;
  v_verdict text; v_phone text; v_email text; v_channel text; v_retry bigint; v_rep jsonb; v_origin bigint;
  v_carried public.notifications;
begin
  select * into a from public.agent_actions where id = p_id;
  v_seat := a.agent; v_result := a.detail->>'result';
  select * into req from public.agent_actions where id = (a.detail->>'request_id')::bigint;
  if req.id is null then return jsonb_build_object('closed', false, 'reason', 'the request this result answers is gone'); end if;

  select * into n from public.notifications
   where id = coalesce((req.detail->>'retry_notification_id')::bigint, (req.evidence->>'notification_id')::bigint);
  v_seen := jsonb_build_object('notification_id', n.id, 'status', n.status, 'channel', n.channel,
                               'provider_message_id', n.provider_message_id, 'sent_at', n.sent_at, 'checked_at', now(),
                               'provider_status', n.provider_status, 'provider_error_code', n.provider_error_code);

  if v_result in ('proof_of_response', 'no_response_confirmation') then
    v_verdict := 'handled_by_the_ladder';
  -- 22 Sep 2026: for WhatsApp and SMS the seat's own re-check also reads Twilio's delivery report; a SID
  -- alone is only Twilio's acceptance (every_whatsapp_says_whether_it_arrived.sql).
  elsif v_result = 'delivered' and n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> ''
        and (coalesce(n.channel, 'email') not in ('whatsapp', 'sms') or n.provider_status in ('delivered', 'read')) then
    v_verdict := 'confirmed';
  -- 'held' and 'record_removed' close here (22 Sep 2026, UNSOLVED-06): a message the founder's own switch
  -- holds, and a queued row that was deleted afterwards, are both recorded rather than retried on the other
  -- channel and escalated to the CEO. Neither is a delivery the seat can correct.
  elsif v_result in ('routed', 'stubbed', 'digested', 'cancelled', 'held', 'record_removed') then
    v_verdict := v_result;
  end if;

  if v_verdict is null and v_result not in ('not_queued', 'sent_unconfirmed') and req.detail->'retry_of' is null
     and coalesce(req.detail->>'recipient_role', n.to_role) in ('customer', 'supplier') then
    -- THE OTHER CHANNEL, ONCE. Email that did not arrive goes to the number on file; WhatsApp that did
    -- not arrive goes to the address. A refused request (not_queued) is a defect, not a channel
    -- problem, and a send that may have left (sent_unconfirmed) is never sent twice: both escalate.
    v_email := coalesce(n.to_email, req.detail->>'to_email');
    if coalesce(n.channel, req.detail->'prepared'->>'channel', 'email') = 'whatsapp' then
      if coalesce(v_email, '') ~ '@' then v_channel := 'email'; end if;
    else
      -- 14 Sep 2026 (#322): the CONFIRMED WhatsApp number, else SMS on the verified mobile. This used to
      -- take leads.whatsapp (a scraped listing number) or any phone on file.
      v_phone := public.fn_whatsapp_destination(coalesce(req.detail->>'recipient_role', n.to_role), null,
                   coalesce((req.detail->>'supplier_id')::bigint, n.lead_id), v_email);
      if v_phone is not null then v_channel := 'whatsapp';
      else
        v_phone := public.fn_verified_mobile(coalesce(req.detail->>'recipient_role', n.to_role), null,
                     coalesce((req.detail->>'supplier_id')::bigint, n.lead_id), v_email);
        if v_phone is not null then v_channel := 'sms'; end if;
      end if;
    end if;
    -- ONCE PER CHANNEL (13 Nov 2026, measured on 29ac49f5: invoice_ready 3x and reveal_receipt 2x on WhatsApp). The
    -- other channel may already carry this very notice: trg_wa_fanout twins an e-mail onto WhatsApp, and the twin has its
    -- own request. A retry there sends it a second time, and a retry onto e-mail is twinned onto WhatsApp again. So the
    -- retry is skipped when that channel already holds the same notice for the same person and request, and what that
    -- copy did is recorded instead; a copy that did not go out is escalated below, never sent a third time.
    if v_channel is not null and n.id is not null then
      select * into v_carried from public.notifications m
       where m.id <> n.id and m.type = n.type and coalesce(m.to_role, '') = coalesce(n.to_role, '')
         and m.quote_id is not distinct from n.quote_id and m.inquiry_id is not distinct from n.inquiry_id
         and coalesce(m.channel, 'email') = v_channel
         and (lower(coalesce(m.to_email, '')) = lower(coalesce(n.to_email, v_email, '')) or m.lead_id is not distinct from n.lead_id)
         and m.created_at >= n.created_at - interval '1 day'
       order by m.id limit 1;
      if v_carried.id is not null then
        v_seen := v_seen || jsonb_build_object('already_on_' || v_channel, jsonb_build_object('notification_id', v_carried.id, 'status', v_carried.status));
        -- only a copy that really went out counts (review item 12): sent, or delivered/read by the provider. A twin that is
        -- queued, suppressed, held or skipped has not reached the person: the retry is not sent there a second time, and
        -- the notice is escalated below instead of being closed as carried.
        if v_carried.status = 'sent' or coalesce(v_carried.provider_status, '') in ('delivered', 'read') then v_verdict := 'already_on_' || v_channel; end if;
        v_channel := null;
      end if;
    end if;
    if v_channel is not null and n.id is not null then
      v_retry := public.fn_seat_handoff(v_seat, 'customer_support', 'delivery.request', 'notifications', 'retry:' || req.id,
        jsonb_build_object('retry_of', req.id, 'msg_type', n.type, 'recipient_role', coalesce(n.to_role, req.detail->>'recipient_role'),
                           'to_email', v_email, 'supplier_id', coalesce(req.detail->'supplier_id', to_jsonb(n.lead_id)),
                           'inquiry_id', n.inquiry_id, 'quote_id', n.quote_id,
                           'prepared', jsonb_build_object('type', n.type, 'kind', n.kind, 'to_role', n.to_role, 'lead_id', n.lead_id,
                                                          'inquiry_id', n.inquiry_id, 'quote_id', n.quote_id, 'subject', n.subject,
                                                          'body', n.body, 'lang', n.lang, 'channel', v_channel,
                                                          'to_email', case when v_channel = 'email' then v_email else n.to_email end,
                                                          'to_phone', case when v_channel in ('whatsapp', 'sms') then v_phone end)));
      v_verdict := 'retried_on_' || v_channel;
    end if;
  end if;

  if v_verdict is null then
    v_rep := public.fn_support_report_to_ceo(
      'delivery_undelivered:' || req.id, 'elevated',
      'A ' || coalesce(req.detail->>'msg_type', 'notice') || ' for the ' || coalesce(req.detail->>'recipient_role', n.to_role, 'recipient')
        || ' did not arrive (' || v_result || ')',
      jsonb_build_object('request_id', req.id, 'result', v_result, 'support_evidence', a.detail->'evidence', 'rechecked', v_seen,
                         'retry_of', req.detail->'retry_of'),
      jsonb_build_array(v_seat || ' asked customer_support to send it',
                        case when req.detail->'retry_of' is not null then 'it was already a retry on the other channel'
                             else 'no other channel was on file' end),
      'Decide how this reaches them: correct the address or number, reach them another way, or record that it need not go.',
      'agent_actions#' || req.id, p_source_agent => v_seat);
    v_verdict := case when coalesce((v_rep->>'ok')::boolean, false) then 'escalated' else 'escalation_refused' end;
  end if;

  update public.agent_actions
     set detail = detail || jsonb_build_object('loop', v_verdict, 'closed_by', v_seat, 'closed_at', now(), 'close_check', v_seen,
                                               'retry_request_id', v_retry, 'escalation', v_rep)
   where id = req.id;
  -- A retry's outcome is the original's outcome too: whoever reads the first request sees how it ended.
  v_origin := (req.detail->>'retry_of')::bigint;
  if v_origin is not null then
    update public.agent_actions set detail = detail || jsonb_build_object('loop', 'retry_' || v_verdict) where id = v_origin;
  end if;
  return jsonb_build_object('checked_by', v_seat, 'result', v_result, 'verdict', v_verdict, 'rechecked', v_seen,
                            'retry_request_id', v_retry, 'escalation', v_rep);
end $function$;
revoke execute on function public.fn_originator_checks_delivery(bigint) from public, anon, authenticated;

-- ══ 18. A TORN-DOWN REHEARSAL PAYMENT IS LABELLED AS ONE AND RESOLVED ═════════════════════════════════
-- 13 Nov 2026: 57 test-mode reconcile items were open as 'test_mode_not_demo', 148 attempts each, though every one is a
-- demo payment (Stripe's customer e-mail is a demo address) whose quote the e2e teardown deleted. They are rehearsal
-- payments, not findings: outcome 'rehearsal_torn_down', resolved. A live payment is never labelled so.
alter table public.accountant_reveal_reconcile_item drop constraint if exists accountant_reveal_reconcile_item_outcome_check;
alter table public.accountant_reveal_reconcile_item add constraint accountant_reveal_reconcile_item_outcome_check
  check (outcome = any (array['recovered', 'second_payment', 'refunded', 'refunded_unrecorded', 'failed', 'deferred',
                              'recorded_elsewhere', 'test_mode_not_demo', 'rehearsal_torn_down']));   -- one plain ADD: 60 rows (13 Nov)

create or replace function public.fn_accountant_reveal_reconcile_record(p_run_id bigint, p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare v_run bigint; x jsonb; n_kept int := 0; n_refused int := 0; n_resolved int := 0; v_demo boolean; v_qid uuid; v_outcome text;
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if jsonb_typeof(p_r) is distinct from 'object' or jsonb_typeof(coalesce(p_r->'outcomes', '[]'::jsonb)) is distinct from 'array' then
    raise exception 'fn_accountant_reveal_reconcile_record(run, readings): readings must be an object with an outcomes array';
  end if;
  select id into v_run from public.accountant_reveal_reconcile_run where id = p_run_id;
  if v_run is null then   -- a call the duty did not dispatch (the founder, by hand): it is a run of its own
    insert into public.accountant_reveal_reconcile_run (window_days)
    values (greatest(1, least(90, coalesce(nullif(p_r->>'days', '')::int, 30)))) returning id into v_run;
  end if;
  update public.accountant_reveal_reconcile_run
     set reported_at = now(),
         result = (p_r - 'outcomes') || jsonb_build_object('reported', jsonb_array_length(coalesce(p_r->'outcomes', '[]'::jsonb)))
   where id = v_run;

  for x in select e from jsonb_array_elements(coalesce(p_r->'outcomes', '[]'::jsonb)) e loop
    if coalesce(x->>'key', '') !~ '^(in|pi)_[A-Za-z0-9_]+$' or coalesce(btrim(x->>'quote_id'), '') = ''
       or coalesce(x->>'outcome', '') not in ('recovered', 'second_payment', 'refunded', 'refunded_unrecorded', 'failed', 'deferred', 'test_mode_not_demo', 'rehearsal_torn_down')
       or coalesce(x->>'source', '') not in ('invoice', 'payment_intent') then
      n_refused := n_refused + 1;   -- 'recorded' (a plain match) never needs a row; anything malformed is refused, not guessed
      continue;
    end if;
    v_qid := case when x->>'quote_id' ~ c_uuid then (x->>'quote_id')::uuid end;
    -- DEMO: a test-mode payment, an email the one demo rule names, or a customer the database marks is_demo.
    -- 'test_mode_not_demo': a test payment whose quote is not provably a demo account's. It reaches the findings,
    -- unless Stripe's own customer e-mail is a demo address (fn_is_demo_email, the identity that picks the Stripe test
    -- key, #1835): the e2e teardown deletes a demo quote while its paid test invoice stays in the window, and that is
    -- demo, not a finding.
    v_demo := case when x->>'outcome' in ('test_mode_not_demo', 'rehearsal_torn_down') then public.fn_is_demo_email(x->>'customer_email')
      else (not coalesce((x->>'livemode')::boolean, false)
           or public.fn_is_demo_email(x->>'customer_email')
           or exists (select 1 from public.customers c where c.is_demo and c.id::text = x->>'customer_id')
           or exists (select 1 from public.quotes q join public.inquiries iq on iq.id = q.inquiry_id
                        join public.customers c on c.id = iq.customer_id where q.id = v_qid and c.is_demo)) end;
    -- 13 Nov 2026: a TEST-mode payment by a demo address whose quote no longer exists is a torn-down rehearsal: labelled
    -- so and resolved, never a finding. A live payment, or a test payment by anyone else, keeps its outcome.
    v_outcome := case when x->>'outcome' in ('test_mode_not_demo', 'rehearsal_torn_down') and not coalesce((x->>'livemode')::boolean, false)
                        and v_demo and (v_qid is null or not exists (select 1 from public.quotes q where q.id = v_qid))
                      then 'rehearsal_torn_down'
                      when x->>'outcome' = 'rehearsal_torn_down' then 'test_mode_not_demo'
                      else x->>'outcome' end;
    insert into public.accountant_reveal_reconcile_item as it (key, livemode, source, quote_id, invoice_id, payment_intent,
        customer_id, customer_email, amount_fils, currency, paid_at, demo, outcome, transaction_id, error, last_run_id, resolved_at)
    values (x->>'key', coalesce((x->>'livemode')::boolean, false), x->>'source', x->>'quote_id', nullif(x->>'invoice_id', ''),
        nullif(x->>'payment_intent', ''), nullif(x->>'customer_id', ''), lower(nullif(x->>'customer_email', '')),
        nullif(x->>'amount_fils', '')::bigint, nullif(x->>'currency', ''),
        case when x->>'paid_at' ~ '^[0-9]+$' then to_timestamp((x->>'paid_at')::bigint) end,
        v_demo, v_outcome, case when x->>'transaction_id' ~ c_uuid then (x->>'transaction_id')::uuid end,
        left(nullif(x->>'error', ''), 1000), v_run,
        case when v_outcome in ('recovered', 'refunded', 'rehearsal_torn_down') then now() end)
    -- 'deferred' says only "not looked at this run": it never overwrites what an earlier run found (failed, second payment).
    on conflict (key) do update set
        outcome = case when excluded.outcome = 'deferred' and it.resolved_at is null then it.outcome else excluded.outcome end,
        error = case when excluded.outcome = 'deferred' and it.resolved_at is null then it.error else excluded.error end,
        demo = excluded.demo,
        payment_intent = coalesce(excluded.payment_intent, it.payment_intent),
        customer_email = coalesce(excluded.customer_email, it.customer_email),
        transaction_id = coalesce(excluded.transaction_id, it.transaction_id),
        attempts = it.attempts + 1, last_seen_at = now(), last_run_id = excluded.last_run_id,
        resolved_at = case when excluded.outcome in ('recovered', 'refunded', 'rehearsal_torn_down') then coalesce(it.resolved_at, now())
                           when excluded.outcome = 'deferred' then null
                           -- Founder ruling 1558 (10 Nov 2026): a TEST-mode payment the accountant resolved stays resolved.
                           -- Test mode moves no money, and the sweep reads the same payment every hour for 30 days.
                           when excluded.outcome = 'test_mode_not_demo' and not excluded.livemode then it.resolved_at end
    -- 10 Nov 2026: after 10 attempts (ten hourly sweeps) an item still open as failed / test_mode_not_demo /
    -- refunded_unrecorded is not rewritten again. Its finding stays open, built from the unresolved item. A result
    -- that resolves it or changes what it is (recovered, refunded, second_payment, rehearsal_torn_down) is still written.
    -- (Carried from the_it_engineers_detectors_stop_counting_finished_work_as_problems.sql.)
    where not (it.resolved_at is null and it.attempts >= 10
               and it.outcome in ('failed', 'test_mode_not_demo', 'refunded_unrecorded')
               and excluded.outcome in ('failed', 'test_mode_not_demo', 'refunded_unrecorded', 'deferred'));
    n_kept := n_kept + 1;
  end loop;

  -- A payment the books now hold by another path (the webhook, a by-hand recording) is resolved, whatever this run saw.
  update public.accountant_reveal_reconcile_item i
     set outcome = 'recorded_elsewhere', resolved_at = now(), transaction_id = t.id
    from public.transactions t
   where i.resolved_at is null and i.outcome in ('failed', 'refunded_unrecorded', 'deferred')
     and ((i.invoice_id is not null and t.stripe_invoice_id = i.invoice_id) or (i.payment_intent is not null and t.payment_ref = i.payment_intent));
  get diagnostics n_resolved = row_count;

  return jsonb_build_object('run', v_run, 'kept', n_kept, 'refused', n_refused, 'resolved_elsewhere', n_resolved,
    'findings', public.fn_accountant_reveal_reconcile_findings());
end $function$;
revoke execute on function public.fn_accountant_reveal_reconcile_record(bigint, jsonb) from public, anon, authenticated;

-- The ones already open: measured 13 Nov 2026, 57 open items, every one test mode, demo = true, its quote gone. Labelled
-- and resolved here; a live item, or one whose quote still exists, is not touched.
update public.accountant_reveal_reconcile_item i
   set outcome = 'rehearsal_torn_down', resolved_at = now(),
       error = left(coalesce(i.error || ' | ', '') || 'a ZZ DEMO rehearsal payment in Stripe test mode whose quote the e2e teardown deleted: not a finding (13 Nov 2026)', 1000)
 where i.resolved_at is null and not i.livemode and i.demo and i.outcome = 'test_mode_not_demo'
   and not exists (select 1 from public.quotes q where q.id::text = i.quote_id);

-- ══ 19. THE CONVERSATIONS (each with its handler; payment_handoffs.ts lists the same) ══════════════════
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('reveal.reconcile', 'sales_engineer', 'accountant',
   'The customer paid the reveal fee in the sales engineer''s portal: the accountant reconciles our invoice, the PaymentIntent and the balance transaction against 3% of the quotation ex-VAT, books it and answers with the verdict.',
   'fn_accountant_reconciles_reveal_handoff', interval '1 hour', false,
   'scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql'),
  ('sale.made', 'accountant', 'ceo',
   'A reveal was paid and reconciled: what was sold, the fee, the trade, the emirate, the customer type and the running month total.',
   'fn_ceo_reads_sale_made', interval '1 day', false,
   'scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql'),
  ('payment.exception', 'accountant', 'ceo',
   'A reveal payment did not reconcile (an amount above the fee, a second payment, a refund, a dispute, facts unreadable): the accountant''s findings and recommendation, for the CEO to decide by reasoning.',
   'fn_ceo_takes_payment_exception', interval '1 day', false,
   'scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql'),
  ('payment.exception', 'accountant', 'sales_engineer',
   'The sales engineer is told a reveal payment is with the CEO, so it answers the customer from the facts and does not discuss money until the CEO decides.',
   'fn_sales_engineer_notes_payment_exception', interval '1 day', false,
   'scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql'),
  ('payment.unrecorded', 'accountant', 'it_engineer',
   'A customer paid a reveal and no sale could be recorded: the it_engineer holds the finding until the sale is recorded (the webhook retry or the hourly reconcile), reported on this handoff.',
   'fn_it_engineer_takes_unrecorded_payment', interval '1 hour', false,
   'scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql'),
  ('overcharge.customer_notice', 'accountant', 'customer_support',
   'Money charged above the reveal fee is being returned (decided by the CEO, or under a standing grant): customer_support tells the customer once, plainly, with the amount.',
   'fn_customer_support_tells_overcharge_returned', interval '1 day', false,
   'scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql'),
  ('payment.unrecorded', 'accountant', 'customer_support',
   'A customer paid a reveal and no sale could be recorded yet: customer_support tells the customer once that the payment arrived and the reveal is being completed; the heal is reported on this handoff.',
   'fn_customer_support_tells_payment_received', interval '1 hour', false,
   'scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql')
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- ══ 20. EVERY READER OF THE WINDOW READS THE ONE SOURCE (R6) ═════════════════════════════════════════
-- fn_refund_state (the chase and the notice) and fn_refund_nonresponse_eligibility now count from the payment and end at
-- fn_reveal_window's end; messages_api/mailbox.ts and supplier_api/actions/inbox.ts read fn_reveal_window (edge code).
-- The sales engineer's sibling build hard-codes 5 in fn_sales_engineer_closes_on_reveal: its author reads fn_reveal_window.
-- Bodies otherwise unchanged from production (13 Nov 2026), except fn_refund_state's partly_refunded / refunded_aed (review 5).
create or replace function public.fn_refund_state(p_transaction uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; v_window int; v_chase int; v_notify_days int; v_min int; v_max int;
        v_responded boolean; v_chase_at timestamptz; v_final_at timestamptz; v_notify_at timestamptz;
        v_chased_at timestamptz; v_final_sent_at timestamptz; v_state text; v_start timestamptz;
begin
  select * into t from transactions where id = p_transaction;
  if not found then return jsonb_build_object('error','transaction_not_found'); end if;

  -- THE LADDER (founder, 6 Sep 2026): the clock starts when the customer PAYS (revealed_at), never at
  -- a nudge or a notice. Day 3 without a supplier response: the owning employee chases. Day 5: the
  -- founder is notified for the final call and the refund becomes approvable. All from pricing_config.
  select refund_window_working_days, chase_after_working_days,
         bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  v_notify_days := coalesce((select value::text::int from decision_policy where key='refund_notify_after_working_days'),1);

  v_responded := t.supplier_ack_at is not null
    or exists (select 1 from messages m
               where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id
                 and m.sender = 'supplier' and coalesce(m.blocked,false) = false
                 and m.created_at > t.revealed_at);

  -- 13 Nov 2026 (accountant, R6): the clock starts at the PAYMENT (fn_reveal_clock_start: Stripe's paid time, else the
  -- insert until Stripe gives one); the end is fn_reveal_window's, the one source every reader shares.
  v_start := public.fn_reveal_clock_start(t.id);
  v_chase_at  := case when t.revealed_at is null then null else public.fn_add_working_days(v_start, v_chase) end;
  v_final_at  := case when t.revealed_at is null then null else (public.fn_reveal_window(t.id)->>'ends_at')::timestamptz end;
  v_notify_at := case when t.revealed_at is null then null else public.fn_add_working_days(v_start, v_notify_days) end;

  select min(n.created_at) into v_chased_at from notifications n
   where n.type = 'supplier_no_response_chase' and n.channel = 'email'
     and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
     and t.revealed_at is not null and n.created_at > t.revealed_at;
  -- The day-5 final call is the sales engineer's notice delivered by support (type refund_final_notice).
  -- The founder_alerts marker the ladder wrote before 14 Sep is still honoured for cases already on it.
  select least((select min(n.created_at) from notifications n
                 where n.type = 'refund_final_notice' and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
                   and t.revealed_at is not null and n.created_at > t.revealed_at),
               (select min(f.created_at) from founder_alerts f where f.dedupe_key = 'refund_final_call:' || t.id::text))
    into v_final_sent_at;

  v_state := case
    when t.revealed_at is null                                                          then 'not_revealed'
    when v_responded                                                                    then 'supplier_responded'
    when coalesce(t.refund_status,'') in ('approved','refunded','processing','succeeded') then 'refunded'
    when coalesce(t.refund_status,'') = 'rejected'                                      then 'refund_rejected'
    when now() < v_chase_at                                                             then 'waiting'
    when now() < v_final_at then case when v_chased_at is null then 'chase_due' else 'chased' end
    else case when v_final_sent_at is null then 'final_call_due' else 'final_call_sent' end end;

  return jsonb_build_object(
    'transaction_id', t.id,
    'state', v_state,
    'revealed_at', t.revealed_at,
    'supplier_responded', v_responded,
    'refund_window_working_days', v_window,
    'chase_after_working_days', v_chase,
    'chase_due_at', v_chase_at,
    'chased_at', v_chased_at,
    'founder_call_due_at', v_final_at,
    'final_call_sent_at', v_final_sent_at,
    'refund_deadline', t.refund_deadline,
    'notify_available_at', v_notify_at,
    'can_notify', (t.revealed_at is not null and not v_responded and t.customer_notified_at is null
                   and now() >= v_notify_at and v_state not in ('refunded','refund_rejected')),
    'notified_at', t.customer_notified_at,
    'auto_nudged_at', t.nudged_24_at,
    'refund_approvable', v_state in ('final_call_due','final_call_sent'),
    'refund_status', t.refund_status,
    -- review 5, item 1: some, not all, of the payment has gone back (fn_refund_rolls_up_to_its_sale). The ladder goes on:
    -- the state above is the supplier's, and the rest of the fee is still the CEO's to decide.
    'partly_refunded', coalesce(t.refund_status, '') = 'partly_refunded',
    'refunded_aed', t.refund_amount_aed,
    'working_days_since_reveal', case when t.revealed_at is null then 0
                                      else public.fn_working_days_between(v_start, now()) end,
    'clock_starts_at', v_start,
    'working_days_since_notice', case when t.customer_notified_at is null then 0
                                      else public.fn_working_days_between(t.customer_notified_at, now()) end,
    'bank_settlement_working_days', coalesce(v_min,7)::text || '-' || coalesce(v_max,14)::text
  );
end $function$;
-- fn_refund_state keeps its live grants (CREATE OR REPLACE preserves them). The window routines it reads are the SERVICE
-- ROLE's only (review 3, item 5): their callers are refund_flow (fn_refund_state), messages_api and supplier_api, all
-- through the service role; nothing signed in reads a sale's window directly (read 13 Nov 2026).
revoke execute on function public.fn_reveal_clock_start(uuid) from public, anon, authenticated;
revoke execute on function public.fn_reveal_window(uuid) from public, anon, authenticated;
grant execute on function public.fn_reveal_clock_start(uuid) to service_role;
grant execute on function public.fn_reveal_window(uuid) to service_role;

create or replace function public.fn_refund_nonresponse_eligibility(p_transaction_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  w public.supplier_response_watch; c public.pricing_config;
  v_wd int; v_att int; v_ch int; v_reasons text[] := '{}'; v_ends timestamptz;
begin
  select * into w from public.supplier_response_watch where transaction_id = p_transaction_id;
  select * into c from public.pricing_config limit 1;

  if w.id is null then
    return jsonb_build_object('eligible', false, 'basis', 'no_watch',
      'detail', 'Support has not recorded contacting this supplier at all, so there is no evidence of silence to decide on.');
  end if;

  -- WORKING days since the PAYMENT (13 Nov 2026, R6): Monday to Friday, skipping public.public_holidays
  -- (fn_is_working_day). This counted Friday and Saturday as the weekend, wrong since the UAE moved to Saturday and
  -- Sunday in 2022, and counted from the watch, not the payment. The window's end is fn_reveal_window's.
  select count(*) into v_wd
    from generate_series((public.fn_reveal_clock_start(p_transaction_id) at time zone 'Asia/Dubai')::date,
                         (now() at time zone 'Asia/Dubai')::date, interval '1 day') d
   where public.fn_is_working_day(d::date);
  v_wd := greatest(v_wd - 1, 0);   -- the day of the payment itself is not an elapsed day
  v_ends := (public.fn_reveal_window(p_transaction_id)->>'ends_at')::timestamptz;

  select count(*), count(distinct a->>'channel')
    into v_att, v_ch
    from jsonb_array_elements(w.attempts) a;

  if w.first_response_at is not null then
    v_reasons := v_reasons || ('the supplier replied on ' || w.first_response_at::text || ' via ' || coalesce(w.response_channel,'?'));
  end if;
  if v_ends is null or now() <= v_ends then
    v_reasons := v_reasons || (v_wd || ' working day(s) have passed of the ' || c.refund_window_working_days || ' the terms allow; the window ends '
                               || coalesce(to_char(v_ends at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI'), 'when the payment is recorded') || ' UAE time');
  end if;
  if v_att < c.supplier_nonresponse_min_attempts then
    v_reasons := v_reasons || ('support made ' || v_att || ' attempt(s), fewer than the ' || c.supplier_nonresponse_min_attempts || ' required');
  end if;
  if v_ch < c.supplier_nonresponse_min_channels then
    v_reasons := v_reasons || ('support used ' || v_ch || ' channel(s), fewer than the ' || c.supplier_nonresponse_min_channels || ' required');
  end if;

  return jsonb_build_object(
    'eligible', array_length(v_reasons,1) is null,
    'basis', 'measured',
    'transaction_id', p_transaction_id,
    'working_days_elapsed', v_wd,
    'working_days_required', c.refund_window_working_days,
    'window_ends_at', v_ends,
    'attempts', v_att, 'attempts_required', c.supplier_nonresponse_min_attempts,
    'channels', v_ch, 'channels_required', c.supplier_nonresponse_min_channels,
    'supplier_replied', w.first_response_at is not null,
    'first_response_at', w.first_response_at,
    'blocking_reasons', coalesce(to_jsonb(v_reasons), '[]'::jsonb),
    'evidence', w.attempts);
end $function$;
revoke execute on function public.fn_refund_nonresponse_eligibility(uuid) from public, anon, authenticated;
