-- A PAID REVEAL IS RECONCILED, BOOKED AND TIMED BY THE ACCOUNTANT FROM THE MOMENT IT IS PAID.
--
-- Assigned: accountant (the reconcile, the books, the clock, our invoice, the notices of a sale). 13 Nov 2026,
-- founder_instruction 1685, 1687, 1688: "was the accountant aware that this is the invoice that we received? Is it kept
-- in the books properly? Is the CEO aware that we made that sales? ... the accountant will start the timer from the day
-- of payment for the refund window". Audit of 13 Nov (scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs).
--
-- ══ MEASURED ON PRODUCTION, 13 Nov 2026 (read only) ═══════════════════════════════════════════════════
--   * trg_reveal_receipt files reveal.paid FROM accountant TO sales_engineer; no handoff kind is addressed TO the
--     accountant about a payment, so 0 rows ever reached it (the one accountant row on the only kept reveal, 29ac49f5,
--     is agent_actions 100357: a charge_audit finding answered "no deterministic remedy" and closed 33 days later).
--   * 0 reveal_fee journals ever: fn_gl_fixture_or_orphan excludes demos and no real reveal has been paid. The memo
--     names no invoice; the Stripe Invoicing fee (billed separately, outside the balance transaction) is never booked.
--   * revealed_at is the INSERT time (reveal_sale.ts) and trg_reveal_window counts the 5 working days from it, so a late
--     webhook starts the customer's window late. No column holds Stripe's paid time.
--   * fn_seat_handoff returns NULL for any demo payload (ruling 1199), so no rehearsal leaves a trace of the chain.
--   * the CEO hears of a sale only as a count (report.five_numbers, the founder brief line "Customers who paid a reveal
--     fee").
--   * the Stripe PDF is what the customer's Documents vault shows (fn_accountant_files_reveal_invoice files it under the
--     inquiry); our invoice prints Stripe's number; reveal_invoices has 0 rows.
--   * the same notice went out more than once per channel (29ac49f5: invoice_ready 3x and reveal_receipt 2x on
--     WhatsApp): fn_originator_checks_delivery retried a 'suppressed' e-mail ON WHATSAPP although trg_wa_fanout had
--     already twinned it there, and retried the WhatsApp twin ON E-MAIL, whose own fan-out twinned it again.
--   * authority: ceo_standing_grant accountant.refund_decision has max_amount_aed 0, "RESERVED BY THE FOUNDER 9 Sep
--     2026": every refund, an overcharge included, is the CEO's. So the accountant RECOMMENDS a refund; it never makes one.
--
-- ══ WHAT THIS CHANGES (each step says whether code or the model decides) ══════════════════════════════
--   1. THE CLOCK (code). transactions.paid_at holds Stripe's own paid time (written by stripe_webhook / the reconcile
--      sweep from the charge). public.fn_reveal_refund_window_ends(paid_at) is the ONE source of the window's end:
--      fn_add_working_days(paid_at, pricing_config.refund_window_working_days). trg_reveal_window uses it, from paid_at
--      when known (else revealed_at), and moves the deadline when paid_at arrives later, while nothing has been asked.
--   2. OUR INVOICE NUMBER (code). public.reveal_invoice_no_seq numbers every real sale QD-INV-000001...; a demo sale is
--      numbered ZZ-DEMO-INV-<tx> and never takes a number from the real sequence. Allocated at the sale, kept in
--      reveal_invoices.invoice_no, printed on our invoice and named in the journal. Stripe's PDF is filed as a
--      back-office record (documents kind stripe_invoice_record, ref transactions: not in the customer's vault); our
--      PDF, rendered by reveal_invoice, is filed into the customer's Documents by fn_accountant_files_our_reveal_invoice.
--   3. THE ACCOUNTANT IS TOLD (code). At the sale the sales engineer hands the accountant reveal.reconcile. The handler
--      fn_accountant_reconciles_reveal_handoff runs fn_accountant_reconciles_reveal: invoice, PaymentIntent and balance
--      transaction against 3% of quotes.price_ex_vat to the fils, AED, one payment for one reveal, nothing charged but
--      the fee, and quotes.quote_amount = price_ex_vat (the VAT assertion: a wrong base is caught on the first payment).
--      Facts not in yet -> it waits (stripe_webhook calls it again when the charge is read). A straight match closes
--      the handoff with the evidence, posts the journal and tells the CEO (sale.made).
--   4. ANYTHING ELSE IS JUDGED (model). A mismatch, an amount above the fee, a second payment, a refund, a dispute, or
--      facts still unreadable after an hour is an exception: the accountant's model path (fn_seat_duty_reason,
--      surface accountant.payment_exception) chooses recommend_refund_difference | escalate_to_ceo | recheck_within_the_hour;
--      fn_reason_apply_accountant__payment_exception writes the choice on the check and hands it to the CEO
--      (payment.exception, judged by the CEO's model: ceo.payment_exception) and to the sales engineer (acknowledged,
--      the customer is not contacted until the CEO decides).
--   5. NEVER CLOSES ITSELF (code). fn_accountant_payment_checks_sweep runs hourly: an exception with no CEO handoff one
--      hour after it opened is escalated to the CEO by code (the model was held or slow); an exception is resolved only
--      by the CEO's decision. Facts still missing are re-read. Nothing closes on a timer.
--   6. THE BOOKS (code). fn_gl_post_reveal_fee: Dr 1050 Stripe clearing (what Stripe settles) / Dr 6100 the card fee
--      from the balance transaction / Cr 4000 the fee (3% ex-VAT) / Cr 2300 anything charged above the fee (owed back
--      until the CEO decides) / Dr 6110 Stripe Invoicing fee, accrued / Cr 2200. The memo names OUR invoice and Stripe's.
--      No VAT line. Revenue is RECOGNISED ON PAYMENT, not deferred to 2400 (the hand-back says why, for the founder).
--      A refund reverses through 6900 and 2300; a dispute's withdrawn funds are booked Dr 6900 / Cr 1050 and reversed
--      when it is won. Every posting is immutable: corrections are reversal entries.
--   7. THE CEO AND THE FOUNDER (code). sale.made accountant -> ceo carries what was sold, the fee, the trade, the
--      emirate, the customer's industry and the running month total; fn_founder_brief lists each sale of the day.
--   8. PAID BUT NOT RECORDED (code). fn_accountant_payment_unrecorded hands payment.unrecorded to the it_engineer (a
--      finding, waits for the heal) and to customer_support (the customer is told ONCE that the payment is received and
--      the reveal is being completed). When the sale is recorded (webhook retry or the hourly reconcile), the heal is
--      reported back to both on those handoffs.
--   9. DEMO PAYMENTS LEAVE THE SAME CHAIN IN A SHADOW (code). public.demo_shadow_trace keeps, tagged by run, every
--      money handoff a demo sale would have filed (fn_seat_handoff files nothing for demo work, ruling 1199), the
--      accountant's reconcile, the journal lines that would have posted, the CEO notice and the window clock. Never in
--      agent_actions, gl_journal or any total. No foreign key, so teardown leaves it; kept 14 days, then purged by the
--      hourly sweep. The journey-proof harness reads it by transaction_id / quote_id / inquiry_id / customer_id.
--  10. ONCE PER CHANNEL (code). fn_originator_checks_delivery never retries a notice on a channel that already carries
--      it; it records what that channel did instead.
--
-- NOT CHANGED: what the sales engineer does on reveal.paid (fn_sales_engineer_acts_on_handoff; it still receives
-- reveal.paid with the same payload plus paid_at, refund_window_ends_at, our invoice number and the window sentence in
-- English and Arabic, for its receipt), the request's status, follow-up rows, the quote hold. The execution at Stripe of
-- a CEO-approved PART refund of an overcharge (the CEO's decision is recorded on the check; the refunds ladder executes
-- full refunds only). The 1150 correction is its own file: the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.sql.
--
-- Pending: scripts/sql/pending/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.txt.
-- Probe: scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid_probe.sql.

-- ══ 1. COLUMNS, ACCOUNTS, SETTINGS, SEQUENCE ══════════════════════════════════════════════════════════
alter table public.transactions add column if not exists paid_at timestamptz;
alter table public.transactions add column if not exists stripe_amount_received_fils bigint;
alter table public.transactions add column if not exists stripe_bt_amount_fils bigint;
alter table public.transactions add column if not exists stripe_bt_currency text;
comment on column public.transactions.paid_at is
  'Stripe''s own time the charge succeeded (latest_charge.created / invoice status_transitions.paid_at). The refund window counts from it (fn_reveal_refund_window_ends). revealed_at is when our row was written.';
comment on column public.transactions.stripe_amount_received_fils is 'PaymentIntent.amount_received, in fils: what the customer was charged.';
comment on column public.transactions.stripe_bt_amount_fils is 'The balance transaction''s gross amount, in fils (before Stripe''s fee).';

insert into public.gl_accounts (code, name, type, subtype, normal_balance, parent_code, is_active, description)
values ('6110', 'Stripe Invoicing Fees', 'expense', 'payment_processing', 'D', '6100', true,
        'Stripe''s Invoicing fee on each paid reveal invoice (published Invoicing Plus 0.5% + 5% VAT on Stripe''s fees). Billed by Stripe separately from the card fee, so it is accrued at the sale (Cr 2200) and trued up against Stripe''s monthly fee charge.')
on conflict (code) do nothing;
insert into public.gl_settings (key, num_value, txt_value) values
  ('stripe_invoicing_fee_pct', 0.5, 'percent of each paid invoice: Stripe Invoicing Plus (stripe.com/ae/invoicing/pricing); Starter is 0.4. The plan could not be read, so the higher rate.'),
  ('stripe_fee_vat_pct', 5, 'percent: UAE VAT Stripe charges on its own fees (stripe.com/ae/pricing)')
on conflict (key) do nothing;

create sequence if not exists public.reveal_invoice_no_seq start 1;
revoke all on sequence public.reveal_invoice_no_seq from public, anon, authenticated;

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
  'What a ZZ DEMO payment would have done, step by step, kept apart from the real books and the real handoff queue. No foreign key, so a teardown leaves it; purged after keep_until by fn_accountant_payment_checks_sweep. Read by the journey proof (co_company) by transaction_id, quote_id, inquiry_id or customer_id.';
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
  is_demo boolean not null default false,
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
  verdict text not null default 'waiting_for_facts' check (verdict in ('waiting_for_facts', 'matched', 'exception')),
  decided_by text,
  decision text,
  decision_reason text,
  held_question_id bigint,
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

-- ══ 4. THE ONE SOURCE OF THE WINDOW'S END ═════════════════════════════════════════════════════════════
-- Terms of Service v11 (src/content/legal.json, terms.en): "If the Supplier has failed to respond both to you and to
-- QuotesDone within five (5) working days of your payment ..." The window is counted from the PAYMENT.
create or replace function public.fn_reveal_refund_window_ends(p_paid_at timestamptz)
returns timestamptz language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select public.fn_add_working_days(p_paid_at,
    coalesce((select refund_window_working_days from public.pricing_config order by id limit 1), 5))
$fn$;
revoke execute on function public.fn_reveal_refund_window_ends(timestamptz) from public, anon, authenticated;
-- pure date arithmetic, read by trg_reveal_window (which runs as the writer): the same reach fn_add_working_days has for a signed-in writer
grant execute on function public.fn_reveal_refund_window_ends(timestamptz) to authenticated, service_role;

create or replace function public.trg_reveal_window()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $function$
declare v_from timestamptz := coalesce(NEW.paid_at, NEW.revealed_at);
begin
  -- The window opens at the moment Stripe took the money (paid_at), else when our row was written; one rule,
  -- fn_reveal_refund_window_ends, for every path.
  if v_from is not null and NEW.refund_deadline is null then
    NEW.refund_deadline := public.fn_reveal_refund_window_ends(v_from);
    if NEW.refund_status is null then NEW.refund_status := 'window_open'; end if;
  -- Stripe's paid time arrived after the row (the charge is read after the insert): the deadline moves to count from
  -- it, while nothing has yet been asked of the window.
  elsif TG_OP = 'UPDATE' and NEW.paid_at is not null and OLD.paid_at is distinct from NEW.paid_at
        and coalesce(NEW.refund_status, 'window_open') = 'window_open' and NEW.refund_requested_at is null then
    NEW.refund_deadline := public.fn_reveal_refund_window_ends(NEW.paid_at);
  end if;
  return NEW;
end $function$;
revoke execute on function public.trg_reveal_window() from public, anon, authenticated;

-- ══ 5. DEMO, RUN TAG, SHADOW, OUR INVOICE NUMBER ══════════════════════════════════════════════════════
create or replace function public.fn_reveal_is_demo(p_tx uuid)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- a rolled-back probe proving the real path on ZZ DEMO fixtures sets qd.probe_files_demo_handoff (never outside one)
  select case when coalesce(current_setting('qd.probe_files_demo_handoff', true), '') = 'on' then false
              else public.fn_transaction_is_demo(p_tx) end
$fn$;
revoke execute on function public.fn_reveal_is_demo(uuid) from public, anon, authenticated;

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

-- Our invoice number for a sale: allocated once, kept in reveal_invoices.invoice_no. A demo sale never takes a number
-- from the real sequence, so the company's numbers have no gap a rehearsal made.
create or replace function public.fn_reveal_invoice_number(p_tx uuid)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_no text;
begin
  select invoice_no into v_no from public.reveal_invoices where transaction_id = p_tx and invoice_no ~ '^(QD-INV-|ZZ-DEMO-INV-)';
  if v_no is not null then return v_no; end if;
  if not exists (select 1 from public.transactions where id = p_tx) then return null; end if;
  v_no := case when public.fn_reveal_is_demo(p_tx) then 'ZZ-DEMO-INV-' || upper(left(p_tx::text, 8))
               else 'QD-INV-' || lpad(nextval('public.reveal_invoice_no_seq')::text, 6, '0') end;
  insert into public.reveal_invoices (transaction_id, invoice_no) values (p_tx, v_no)
  on conflict (transaction_id) do update set invoice_no = excluded.invoice_no
    where public.reveal_invoices.invoice_no is null or public.reveal_invoices.invoice_no !~ '^(QD-INV-|ZZ-DEMO-INV-)';
  select invoice_no into v_no from public.reveal_invoices where transaction_id = p_tx;
  return v_no;
end $fn$;
revoke execute on function public.fn_reveal_invoice_number(uuid) from public, anon, authenticated;
grant execute on function public.fn_reveal_invoice_number(uuid) to service_role;


-- ══ 6. A DEMO PAYLOAD'S HANDOFFS GO TO THE SHADOW ═════════════════════════════════════════════════════
-- fn_seat_handoff (owned by scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql; handoff_kinds_are_data.test.mjs
-- forbids a second owner) files nothing for a demo payload (ruling 1199). Every money conversation this file starts
-- therefore asks first: a demo sale's conversation is written to demo_shadow_trace here, a real one goes through
-- fn_seat_handoff. (The it_engineer's file can make fn_seat_handoff itself call fn_demo_shadow_record for every seat.)

-- ══ 7. THE JOURNAL OF ONE SALE (pure: the same lines are posted for a real sale and shadowed for a demo) ═══
create or replace function public.fn_reveal_fee_journal(p_tx uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; v_inv text; v_gross bigint; v_fee bigint; v_card bigint; v_over bigint; v_net bigint;
  v_invpct numeric; v_vatpct numeric; v_invoicing bigint; v_lines jsonb; v_memo text;
begin
  select * into t from public.transactions where id = p_tx;
  if not found then return null; end if;
  -- what the customer was charged: Stripe's own figures first, then our record
  v_gross := coalesce(t.stripe_bt_amount_fils, t.stripe_amount_received_fils, round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint);
  v_fee   := round(coalesce(t.reveal_fee, 0) * 100)::bigint;
  v_card  := t.stripe_fee_fils;
  if v_card is null or v_gross <= 0 or v_fee <= 0 then
    return jsonb_build_object('ready', false, 'why', case when v_card is null then 'the balance transaction (Stripe''s card fee) is not read yet' else 'no amount' end);
  end if;
  v_over := greatest(v_gross - v_fee, 0);           -- charged above the fee: owed back until the CEO decides
  v_net  := v_gross - v_card;                        -- what Stripe settles into the clearing account
  select num_value into v_invpct from public.gl_settings where key = 'stripe_invoicing_fee_pct';
  select num_value into v_vatpct from public.gl_settings where key = 'stripe_fee_vat_pct';
  v_invoicing := ceil(v_gross * coalesce(v_invpct, 0.5) / 100.0 * (1 + coalesce(v_vatpct, 5) / 100.0) - 1e-9)::bigint;
  v_inv := (select invoice_no from public.reveal_invoices where transaction_id = p_tx);
  v_memo := 'Reveal fee, our invoice ' || coalesce(v_inv, '(not numbered)')
         || coalesce(' (Stripe invoice ' || t.stripe_invoice_number || ')', '') || ', transaction ' || left(p_tx::text, 8)
         || ': 3% of the quotation ex-VAT, no VAT charged';
  v_lines := jsonb_build_array(
    jsonb_build_object('account', '1050', 'debit', v_net / 100.0, 'memo', 'Stripe clearing: charged less Stripe''s card fee'),
    jsonb_build_object('account', '6100', 'debit', v_card / 100.0, 'memo', 'Stripe card fee from the balance transaction'),
    jsonb_build_object('account', '4000', 'credit', least(v_fee, v_gross) / 100.0, 'memo', 'Reveal fee revenue, invoice ' || coalesce(v_inv, '?')));
  if v_over > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', '2300', 'credit', v_over / 100.0,
      'memo', 'Charged above the fee: owed back to the customer until the CEO decides'));
  end if;
  if v_invoicing > 0 then
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object('account', '6110', 'debit', v_invoicing / 100.0, 'memo', 'Stripe Invoicing fee on invoice ' || coalesce(t.stripe_invoice_number, v_inv, '?') || ', accrued at the published rate'),
      jsonb_build_object('account', '2200', 'credit', v_invoicing / 100.0, 'memo', 'Accrued: Stripe bills its Invoicing fee separately'));
  end if;
  return jsonb_build_object('ready', true, 'date', (coalesce(t.paid_at, t.revealed_at, now()) at time zone 'Asia/Dubai')::date,
    'memo', v_memo, 'lines', v_lines, 'our_invoice_no', v_inv, 'stripe_invoice_number', t.stripe_invoice_number,
    'gross_fils', v_gross, 'fee_fils', v_fee, 'card_fee_fils', v_card, 'over_fils', v_over, 'invoicing_fee_fils', v_invoicing);
end $fn$;
revoke execute on function public.fn_reveal_fee_journal(uuid) from public, anon, authenticated;

-- Posts the sale once (source reveal_fee, source_ref the transaction). A demo sale is shadowed, never posted.
create or replace function public.fn_gl_post_reveal_fee(p_tx uuid)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare j jsonb; v_jid bigint; v_why text;
begin
  select g.id into v_jid from public.gl_journal g where g.source = 'reveal_fee' and g.source_ref = p_tx::text order by g.id limit 1;
  if v_jid is not null then return v_jid; end if;
  j := public.fn_reveal_fee_journal(p_tx);
  if j is null or not coalesce((j->>'ready')::boolean, false) then return null; end if;
  if public.fn_reveal_is_demo(p_tx) then
    if not exists (select 1 from public.demo_shadow_trace s where s.transaction_id = p_tx and s.step = 'journal') then
      perform public.fn_demo_shadow_record('journal', 'reveal_fee', 'accountant', null, j || jsonb_build_object('transaction_id', p_tx,
        'note', 'a demo sale: these are the lines the books would hold; nothing was posted to gl_journal'));
    end if;
    return null;
  end if;
  -- (a rolled-back probe proving the real path on the ZZ DEMO fixture is the one caller allowed past the fixture rule)
  v_why := case when coalesce(current_setting('qd.probe_files_demo_handoff', true), '') = 'on'
                then null else public.fn_gl_fixture_or_orphan(p_tx, null, null) end;
  if v_why is not null then return null; end if;
  v_jid := public.fn_gl_entry((j->>'date')::date, j->>'memo', 'reveal_fee', p_tx::text, j->'lines', 'accountant');
  update public.accountant_reveal_payment_check set journal_id = v_jid where transaction_id = p_tx;
  return v_jid;
end $fn$;
revoke execute on function public.fn_gl_post_reveal_fee(uuid) from public, anon, authenticated;

-- ══ 8. THE ACCOUNTANT'S RECONCILE OF ONE PAYMENT ══════════════════════════════════════════════════════
create or replace function public.fn_accountant_reconciles_reveal(p_tx uuid, p_from_handler boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; q record; c public.accountant_reveal_payment_check; v_demo boolean; v_rate numeric;
  v_expected bigint; v_recorded bigint; v_charged bigint; f jsonb := '[]'::jsonb; v_waiting text; v_verdict text;
  v_inv text; v_ev jsonb; v_hid bigint; v_jid bigint; v_age interval; v_ends timestamptz; v_held bigint; v_sale jsonb;
  v_disputed boolean; v_second boolean;
begin
  select * into t from public.transactions where id = p_tx;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no transaction ' || p_tx); end if;
  v_demo := public.fn_reveal_is_demo(p_tx);
  select qq.id, qq.price_ex_vat, qq.quote_amount into q from public.quotes qq where qq.id = t.quote_id;
  select standard_reveal_rate into v_rate from public.pricing_config order by id limit 1;
  v_inv := public.fn_reveal_invoice_number(p_tx);
  v_ends := public.fn_reveal_refund_window_ends(coalesce(t.paid_at, t.revealed_at));

  insert into public.accountant_reveal_payment_check as k (transaction_id, is_demo, run_tag, quote_id)
  values (p_tx, v_demo, case when v_demo then public.fn_demo_run_tag_of(t.customer_id) end, t.quote_id)
  on conflict (transaction_id) do nothing;
  select * into c from public.accountant_reveal_payment_check where transaction_id = p_tx for update;
  -- decided already: the answer is the one recorded (idempotent for every caller)
  if c.verdict = 'matched' or (c.verdict = 'exception' and c.decided_by is not null and c.resolved_at is not null) then
    return jsonb_build_object('ok', true, 'transaction_id', p_tx, 'verdict', c.verdict, 'findings', c.findings,
      'our_invoice_no', c.our_invoice_no, 'journal_id', c.journal_id, 'decided_by', c.decided_by, 'already', true);
  end if;

  -- THE FEE. 3% of the quotation EXCLUDING VAT (founder 1687), to the fils, rounded half-up as public.reveal_fee does.
  v_expected := case when q.price_ex_vat is not null and v_rate is not null then round(q.price_ex_vat * v_rate * 100)::bigint end;
  v_recorded := round(coalesce(t.reveal_fee, 0) * 100)::bigint;
  v_charged  := coalesce(t.stripe_amount_received_fils, round(coalesce(t.total_charged, 0) * 100)::bigint);

  -- facts not in yet: the charge (amount received, card fee) is read by stripe_webhook after the insert
  if t.stripe_fee_fils is null or t.stripe_amount_received_fils is null then
    v_waiting := 'Stripe''s charge and balance transaction are not read yet';
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
  if coalesce(t.refund_status, '') in ('refunded', 'refund_approved', 'succeeded') then
    f := f || jsonb_build_array(jsonb_build_object('code', 'refunded', 'fact', 'the payment was refunded (' || t.refund_status || ', AED ' || coalesce(t.refund_amount_aed::text, '?') || ')'));
  end if;

  v_age := now() - coalesce(t.paid_at, t.revealed_at, c.opened_at);
  if jsonb_array_length(f) > 0 then v_verdict := 'exception';
  elsif v_waiting is not null and v_age > interval '1 hour' then
    v_verdict := 'exception';
    f := f || jsonb_build_array(jsonb_build_object('code', 'facts_unreadable', 'fact', v_waiting || ' an hour after the payment'));
  elsif v_waiting is not null then v_verdict := 'waiting_for_facts';
  else v_verdict := 'matched';
  end if;

  update public.accountant_reveal_payment_check set
    is_demo = v_demo, our_invoice_no = v_inv, stripe_invoice_id = t.stripe_invoice_id, stripe_invoice_number = t.stripe_invoice_number,
    payment_ref = t.payment_ref, price_ex_vat = q.price_ex_vat, quote_amount = q.quote_amount, rate = v_rate,
    expected_fee_fils = v_expected, recorded_fee_fils = v_recorded, charged_fils = v_charged,
    invoice_total_fils = t.stripe_invoice_total_fils, amount_received_fils = t.stripe_amount_received_fils,
    bt_amount_fils = t.stripe_bt_amount_fils, bt_fee_fils = t.stripe_fee_fils,
    currency = lower(coalesce(t.stripe_bt_currency, t.stripe_invoice_currency, 'aed')), paid_at = t.paid_at,
    refund_window_ends_at = coalesce(t.refund_deadline, v_ends), findings = f, verdict = v_verdict, checked_at = now(),
    decided_by = case when v_verdict = 'matched' then 'code' else decided_by end,
    resolved_at = case when v_verdict = 'matched' then now() else resolved_at end,
    resolution = case when v_verdict = 'matched' then 'straight match: booked and reported by code' else resolution end
   where transaction_id = p_tx
  returning * into c;

  -- the books hold whatever happened once Stripe's figures are in (an overcharge sits in 2300 until the CEO decides)
  if v_waiting is null then v_jid := public.fn_gl_post_reveal_fee(p_tx); end if;

  v_ev := jsonb_build_object('reconciled_by', 'accountant (code)', 'transaction_id', p_tx, 'verdict', v_verdict,
    'our_invoice_no', v_inv, 'stripe_invoice_number', t.stripe_invoice_number, 'payment_ref', t.payment_ref,
    'expected_fee_fils', v_expected, 'charged_fils', v_charged, 'card_fee_fils', t.stripe_fee_fils,
    'price_ex_vat', q.price_ex_vat, 'rate', v_rate, 'currency', c.currency, 'paid_at', t.paid_at,
    'refund_window_ends_at', c.refund_window_ends_at, 'findings', f, 'journal_id', v_jid);

  if v_demo then
    perform public.fn_demo_shadow_record('reconcile', 'reveal.reconcile', 'sales_engineer', 'accountant', v_ev);
    if not exists (select 1 from public.demo_shadow_trace s where s.transaction_id = p_tx and s.step = 'window_clock') and t.paid_at is not null then
      perform public.fn_demo_shadow_record('window_clock', 'refund_window', 'accountant', null, jsonb_build_object('transaction_id', p_tx,
        'paid_at', t.paid_at, 'revealed_at', t.revealed_at, 'refund_deadline', t.refund_deadline,
        'counted_from', 'paid_at (fn_reveal_refund_window_ends)', 'ends_at', v_ends));
    end if;
  end if;

  if v_verdict = 'matched' then
    v_sale := public.fn_accountant_tells_ceo_of_sale(p_tx);
    v_ev := v_ev || jsonb_build_object('sale_made', v_sale);
  elsif v_verdict = 'exception' and c.held_question_id is null and c.ceo_handoff_id is null then
    -- JUDGED, NOT CODED: the accountant's model path decides what to do about it
    v_held := public.fn_seat_duty_reason('accountant', 'accountant.payment_exception',
      'A reveal payment did not reconcile. Decide what the accountant does. The fee is 3% of the quotation excluding VAT, '
      || 'the customer is charged the fee and nothing else, one payment is one reveal. Every refund, an overcharge included, '
      || 'is decided by the CEO (ceo_standing_grant accountant.refund_decision: max AED 0): the accountant recommends, the CEO decides.',
      ('[{"id":"recommend_refund_difference","meaning":"the customer paid money that is not the fee (above the fee, a second payment, a surcharge): recommend to the CEO that the difference is refunded, naming the amount"},'
      || '{"id":"escalate_to_ceo","meaning":"the facts need a decision beyond the accountant''s authority (a dispute, a refund, a missing quote, a wrong fee base): hand the CEO the facts and the accountant''s view"},'
      || '{"id":"recheck_within_the_hour","meaning":"Stripe has not yet given the facts (the charge or the invoice is not final); read them again within the hour. If still unresolved, it goes to the CEO anyway"}]')::jsonb,
      v_ev, jsonb_build_object('transaction_id', p_tx, 'check', 'accountant_reveal_payment_check', 'demo', v_demo,
                               'fixture', v_demo), 'payment_exception:' || p_tx);
    update public.accountant_reveal_payment_check set held_question_id = v_held where transaction_id = p_tx;
    if v_demo then perform public.fn_demo_shadow_record('model_question', 'accountant.payment_exception', 'accountant', 'accountant',
      jsonb_build_object('transaction_id', p_tx, 'held_question_id', v_held, 'findings', f)); end if;
    v_ev := v_ev || jsonb_build_object('held_question_id', v_held, 'judged_by', 'the accountant''s model (accountant.payment_exception)');
  end if;

  -- close (or update) the sales engineer's reveal.reconcile handoff with the outcome, so the sender reads it
  if not p_from_handler and not v_demo then
    select a.id into v_hid from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'accountant' and a.target_id = 'reveal.reconcile:' || p_tx::text and a.status <> 'done'
     order by a.id limit 1;
    if v_hid is not null and v_verdict <> 'waiting_for_facts' then
      update public.accountant_reveal_payment_check set reconcile_handoff_id = v_hid where transaction_id = p_tx;
      begin perform public.fn_seat_handoff_act(v_hid); exception when others then null; end;
    end if;
  end if;
  return jsonb_build_object('ok', true) || v_ev;
end $fn$;
revoke execute on function public.fn_accountant_reconciles_reveal(uuid, boolean) from public, anon, authenticated;
grant execute on function public.fn_accountant_reconciles_reveal(uuid, boolean) to service_role;

-- The handler of reveal.reconcile (sales_engineer -> accountant).
create or replace function public.fn_accountant_reconciles_reveal_handoff(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v jsonb; v_tx uuid;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_tx := (a.detail->>'transaction_id')::uuid;
  update public.accountant_reveal_payment_check set reconcile_handoff_id = p_id where transaction_id = v_tx and reconcile_handoff_id is null;
  v := public.fn_accountant_reconciles_reveal(v_tx, true);
  if v->>'verdict' = 'waiting_for_facts' then
    return v || jsonb_build_object('waiting', 'Stripe''s charge and balance transaction; stripe_webhook reads them and the hourly sweep re-reads them');
  elsif v->>'verdict' = 'exception' then
    return v || jsonb_build_object('waiting', 'the accountant''s judgement and the CEO''s decision on the payment exception');
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_accountant_reconciles_reveal_handoff(bigint) from public, anon, authenticated;

-- ══ 9. THE CEO IS TOLD OF EACH SALE ═══════════════════════════════════════════════════════════════════
create or replace function public.fn_accountant_tells_ceo_of_sale(p_tx uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; i record; cu record; v_demo boolean; v_month numeric; v_n int; v_p jsonb; v_hid bigint; v_start timestamptz;
begin
  select * into t from public.transactions where id = p_tx;
  if not found then return null; end if;
  v_demo := public.fn_reveal_is_demo(p_tx);
  select ii.summary_masked, ii.summary, ii.category, ii.trades, ii.emirate, ii.scope_type into i from public.inquiries ii where ii.id = t.inquiry_id;
  select cc.industry into cu from public.customers cc where cc.id = t.customer_id;
  v_start := (date_trunc('month', now() at time zone 'Asia/Dubai')) at time zone 'Asia/Dubai';
  -- the running month total counts real sales only (a demo sale never reaches a total)
  select coalesce(sum(x.reveal_fee), 0), count(*) into v_month, v_n
    from public.transactions x
   where x.fee_status = 'paid' and coalesce(x.paid_at, x.revealed_at) >= v_start
     and coalesce(x.refund_status, '') not in ('refunded', 'refund_approved', 'succeeded')
     and not public.fn_reveal_is_demo(x.id);
  v_p := jsonb_build_object('transaction_id', p_tx, 'quote_id', t.quote_id, 'inquiry_id', t.inquiry_id, 'customer_id', t.customer_id,
    'what_was_sold', 'the reveal of the chosen supplier''s contact for: ' || coalesce(i.summary_masked, i.summary, i.category, 'a request'),
    'fee_aed', t.reveal_fee, 'quotation_ex_vat_aed', t.quote_amount, 'trade', coalesce(i.category, array_to_string(i.trades, ', ')),
    'emirate', i.emirate, 'customer_type', coalesce(cu.industry, i.scope_type, 'not recorded'),
    'our_invoice_no', (select invoice_no from public.reveal_invoices where transaction_id = p_tx),
    'paid_at', t.paid_at, 'refund_window_ends_at', t.refund_deadline,
    'month_total_aed', v_month, 'sales_this_month', v_n, 'demo', v_demo,
    'note', case when v_demo then 'a demo sale: not counted in the month total' end);
  if v_demo then
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

-- ══ 10. THE EXCEPTION: THE ACCOUNTANT'S JUDGEMENT, THE CEO'S DECISION, THE SALES ENGINEER TOLD ═════════
create or replace function public.fn_accountant_escalates_payment_exception(p_tx uuid, p_by text, p_choice text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.accountant_reveal_payment_check; t public.transactions; v_p jsonb; v_ceo bigint; v_se bigint; v_over bigint;
begin
  select * into c from public.accountant_reveal_payment_check where transaction_id = p_tx for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no check for ' || p_tx); end if;
  select * into t from public.transactions where id = p_tx;
  select coalesce(sum((x->>'over_fils')::bigint), 0) into v_over from jsonb_array_elements(c.findings) x where x ? 'over_fils';
  v_p := jsonb_build_object('transaction_id', p_tx, 'quote_id', t.quote_id, 'inquiry_id', t.inquiry_id, 'customer_id', t.customer_id,
    'findings', c.findings, 'accountant_choice', p_choice, 'accountant_reason', left(coalesce(p_reason, ''), 2000), 'decided_by', p_by,
    'recommended_refund_fils', case when p_choice = 'recommend_refund_difference' then nullif(v_over, 0) end,
    'our_invoice_no', c.our_invoice_no, 'stripe_invoice_number', c.stripe_invoice_number, 'payment_ref', c.payment_ref,
    'expected_fee_fils', c.expected_fee_fils, 'charged_fils', c.charged_fils, 'opened_at', c.opened_at);
  if c.ceo_handoff_id is null then
    if c.is_demo then   -- fn_seat_handoff files nothing for demo work (ruling 1199): the shadow keeps it
      perform public.fn_demo_shadow_record('handoff', 'payment.exception', 'accountant', 'ceo', v_p);
      perform public.fn_demo_shadow_record('handoff', 'payment.exception', 'accountant', 'sales_engineer', v_p);
      perform public.fn_demo_shadow_record('escalation', 'payment.exception', 'accountant', 'ceo', v_p);
    else
      v_ceo := public.fn_seat_handoff('accountant', 'ceo', 'payment.exception', 'transactions', p_tx::text, v_p);
      v_se  := public.fn_seat_handoff('accountant', 'sales_engineer', 'payment.exception', 'transactions', p_tx::text, v_p);
    end if;
  end if;
  update public.accountant_reveal_payment_check
     set decided_by = p_by, decision = p_choice, decision_reason = left(coalesce(p_reason, ''), 2000),
         escalated_at = coalesce(escalated_at, now()), ceo_handoff_id = coalesce(ceo_handoff_id, v_ceo, case when c.is_demo then -1 end)
   where transaction_id = p_tx;
  return jsonb_build_object('ok', true, 'ceo_handoff_id', v_ceo, 'sales_engineer_handoff_id', v_se, 'choice', p_choice);
end $fn$;
revoke execute on function public.fn_accountant_escalates_payment_exception(uuid, text, text, text) from public, anon, authenticated;

-- The accountant's model answered (surface accountant.payment_exception).
create or replace function public.fn_reason_apply_accountant__payment_exception(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_tx uuid; v jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  v_tx := (r.subject->>'transaction_id')::uuid;
  if v_choice = 'recheck_within_the_hour' then
    -- re-read now; whatever it still shows goes to the CEO at the hour (fn_accountant_payment_checks_sweep)
    update public.accountant_reveal_payment_check set decision = v_choice, decided_by = 'accountant model: ' || coalesce(p_result->>'model', '?'),
           decision_reason = left(coalesce(p_result->>'answer', ''), 2000), held_question_id = null
     where transaction_id = v_tx;
    v := public.fn_accountant_reconciles_reveal(v_tx);
    return jsonb_build_object('applied', true, 'choice', v_choice, 'rechecked', v->>'verdict');
  end if;
  v := public.fn_accountant_escalates_payment_exception(v_tx, 'accountant model: ' || coalesce(p_result->>'model', '?'), v_choice, p_result->>'answer');
  return jsonb_build_object('applied', true, 'choice', v_choice) || v;
end $fn$;
revoke execute on function public.fn_reason_apply_accountant__payment_exception(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_accountant__payment_exception(bigint, jsonb) to service_role;

-- The CEO's handler for payment.exception: the CEO decides by reasoning (ceo.payment_exception) and answers on it.
create or replace function public.fn_ceo_takes_payment_exception(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_held bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_held := public.fn_seat_duty_reason('ceo', 'ceo.payment_exception',
    'The accountant hands the CEO a reveal payment that did not reconcile, with its findings and its recommendation. '
    || 'Our rules: the customer pays 3% of the quotation excluding VAT and nothing else; one payment is one reveal; every refund '
    || 'is the CEO''s decision. Decide.',
    ('[{"id":"refund_difference","meaning":"approve refunding the customer the money that is not the fee (the amount the accountant names); the accountant executes it and the sales engineer tells the customer"},'
    || '{"id":"money_is_correct","meaning":"on the facts the charge is right and nothing is owed back; the accountant records why"},'
    || '{"id":"investigate","meaning":"the facts are not enough; the accountant gathers the named facts and hands it back"}]')::jsonb,
    a.detail, jsonb_build_object('handoff_id', a.id, 'transaction_id', a.detail->>'transaction_id'), 'payment_exception_ceo:' || a.id);
  return jsonb_build_object('accepted', true, 'held_question', v_held,
    'waiting', 'the CEO decides this by reasoning (held question ' || v_held || ') and answers on this handoff');
end $fn$;
revoke execute on function public.fn_ceo_takes_payment_exception(bigint) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__payment_exception(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_hid bigint; v_tx uuid;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  v_hid := (r.subject->>'handoff_id')::bigint;
  v_tx := (r.subject->>'transaction_id')::uuid;
  update public.accountant_reveal_payment_check
     set ceo_decision = v_choice, ceo_decided_at = now(),
         -- resolved only when nothing more is owed: an approved refund stays open until the refund settles
         resolved_at = case when v_choice = 'money_is_correct' then now() else resolved_at end,
         resolution = case v_choice when 'money_is_correct' then 'CEO: the charge is right, nothing owed back'
                                    when 'refund_difference' then 'CEO approved refunding the difference; open until the refund settles'
                                    else 'CEO asked for more facts' end,
         -- investigate: the accountant judges again with what it gathers
         held_question_id = case when v_choice = 'investigate' then null else held_question_id end,
         ceo_handoff_id = case when v_choice = 'investigate' then null else ceo_handoff_id end
   where transaction_id = v_tx;
  perform set_config('qd.handoff_closer', 'ceo', true);
  perform public.fn_seat_handoff_complete(v_hid, jsonb_build_object('decided_by', 'ceo', 'choice', v_choice,
    'reasoning', left(coalesce(p_result->>'answer', ''), 3000), 'model', p_result->>'model', 'held_question', p_id));
  perform set_config('qd.handoff_closer', '', true);
  return jsonb_build_object('applied', true, 'handoff_id', v_hid, 'choice', v_choice);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__payment_exception(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__payment_exception(bigint, jsonb) to service_role;

-- The sales engineer is told; it does not contact the customer until the CEO decides.
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
    -- a Stripe TEST-mode payment is a ZZ DEMO rehearsal's (stripe_webhook accepts no other)
    || case when p_demo then jsonb_build_object('rehearsal', 'ZZ DEMO test-mode payment') else '{}'::jsonb end;
  if p_demo or public.fn_seat_work_is_demo(v_p::text, v_p, 'payments', p_payment_ref) then
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

-- ══ 12. AT THE SALE: OUR INVOICE NUMBER, reveal.paid (unchanged + fields), reveal.reconcile, a heal reported back ══
create or replace function public.trg_reveal_receipt()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare v_demo boolean; v_inv text; v_ends timestamptz; v_h record; v_lang_en text; v_lang_ar text; v_paid jsonb;
begin
  if NEW.revealed_at is not null and (TG_OP = 'INSERT' or OLD.revealed_at is null) then
    v_demo := public.fn_reveal_is_demo(NEW.id);
    -- nothing added here may fail the sale: a number that cannot be allocated now is allocated by the reconcile
    begin v_inv := public.fn_reveal_invoice_number(NEW.id); exception when others then v_inv := null; end;
    v_ends := coalesce(NEW.refund_deadline, public.fn_reveal_refund_window_ends(coalesce(NEW.paid_at, NEW.revealed_at)));
    v_lang_en := 'The supplier must respond within the refund window, which ends on '
      || to_char(v_ends at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' (five working days from your payment).';
    v_lang_ar := 'يجب أن يردّ المورّد خلال مهلة الاسترداد التي تنتهي في ' || to_char(v_ends at time zone 'Asia/Dubai', 'DD/MM/YYYY')
      || ' (خمسة أيام عمل من تاريخ الدفع).';
    if v_demo then
      perform public.fn_demo_shadow_record('invoice_number', 'our_invoice_no', 'accountant', null,
        jsonb_build_object('transaction_id', NEW.id, 'our_invoice_no', v_inv));
    end if;
    -- the sales engineer's reveal.paid: the same payload as before, plus fields (none removed). A demo sale's goes to the
    -- shadow (fn_seat_handoff files nothing for demo work, ruling 1199).
    v_paid := jsonb_build_object('transaction_id', NEW.id, 'customer_id', NEW.customer_id, 'supplier_id', NEW.supplier_id,
                         'inquiry_id', NEW.inquiry_id, 'quote_id', NEW.quote_id, 'revealed_at', NEW.revealed_at,
                         'paid_at', NEW.paid_at, 'refund_window_ends_at', v_ends, 'our_invoice_no', v_inv,
                         'refund_window_sentence_en', v_lang_en, 'refund_window_sentence_ar', v_lang_ar);
    if v_demo then perform public.fn_demo_shadow_record('handoff', 'reveal.paid', 'accountant', 'sales_engineer', v_paid);
    else perform public.fn_seat_handoff('accountant', 'sales_engineer', 'reveal.paid', 'transactions', NEW.id::text, v_paid);
    end if;
    -- the accountant is TOLD: the sale was made in the sales engineer's portal; the accountant reconciles and books it
    if v_demo then
      perform public.fn_demo_shadow_record('handoff', 'reveal.reconcile', 'sales_engineer', 'accountant',
        jsonb_build_object('transaction_id', NEW.id, 'quote_id', NEW.quote_id, 'our_invoice_no', v_inv));
      -- a rehearsal's reconcile never fails its sale; the hourly sweep checks a sale that has no check
      begin perform public.fn_accountant_reconciles_reveal(NEW.id, true); exception when others then null; end;
    else
      perform public.fn_seat_handoff('sales_engineer', 'accountant', 'reveal.reconcile', 'transactions', NEW.id::text,
        jsonb_build_object('transaction_id', NEW.id, 'quote_id', NEW.quote_id, 'inquiry_id', NEW.inquiry_id,
                           'customer_id', NEW.customer_id, 'payment_ref', NEW.payment_ref, 'stripe_invoice_id', NEW.stripe_invoice_id,
                           'our_invoice_no', v_inv, 'question', 'Reconcile this payment against our invoice and book it.'));
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
  return NEW;
end $function$;
revoke execute on function public.trg_reveal_receipt() from public, anon, authenticated;

-- ══ 13. THE HOURLY SWEEP: re-read facts, escalate within the hour, never close, purge old shadows ═══════
create or replace function public.fn_accountant_payment_checks_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; n_reread int := 0; n_escalated int := 0; n_purged int := 0;
begin
  -- facts still missing: read again (stripe_webhook may have filled them since)
  for r in select transaction_id from public.accountant_reveal_payment_check where verdict = 'waiting_for_facts' and resolved_at is null loop
    perform public.fn_accountant_reconciles_reveal(r.transaction_id); n_reread := n_reread + 1;
  end loop;
  -- a paid reveal with no check at all (written before this file, or a check that failed): the accountant checks it now
  for r in select t.id from public.transactions t
            where t.fee_status = 'paid' and coalesce(t.paid_at, t.revealed_at) >= now() - interval '30 days'
              and not exists (select 1 from public.accountant_reveal_payment_check k where k.transaction_id = t.id) limit 50 loop
    perform public.fn_accountant_reconciles_reveal(r.id); n_reread := n_reread + 1;
  end loop;
  -- WITHIN THE HOUR: an exception the model has not decided goes to the CEO by code. Nothing here resolves anything.
  for r in select transaction_id from public.accountant_reveal_payment_check
            where verdict = 'exception' and resolved_at is null and ceo_handoff_id is null
              and opened_at <= now() - interval '1 hour' loop
    perform public.fn_accountant_escalates_payment_exception(r.transaction_id, 'code: not judged within the hour', 'escalate_to_ceo',
      'The accountant''s judgement did not arrive within the hour (the model was held or slow), so the facts go to the CEO as they stand.');
    n_escalated := n_escalated + 1;
  end loop;
  delete from public.demo_shadow_trace where keep_until < now();
  get diagnostics n_purged = row_count;
  delete from public.accountant_reveal_payment_check where is_demo and opened_at < now() - interval '14 days';
  return jsonb_build_object('reread', n_reread, 'escalated_to_ceo', n_escalated, 'shadow_purged', n_purged,
    'open_exceptions', (select count(*) from public.accountant_reveal_payment_check where verdict = 'exception' and resolved_at is null and not is_demo));
end $fn$;
revoke execute on function public.fn_accountant_payment_checks_sweep() from public, anon, authenticated;

do $cron$ begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'accountant_payment_checks_hourly';
  perform cron.schedule('accountant_payment_checks_hourly', '23 * * * *', $job$select public.fn_accountant_payment_checks_sweep();$job$);
end $cron$;

-- A dispute opened or moved on a payment re-runs the accountant's check (exception 'disputed' -> judged -> the CEO).
create or replace function public.trg_dispute_reopens_the_payment_check()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_tx uuid;
begin
  v_tx := coalesce(NEW.transaction_id, (select t.id from public.transactions t where t.payment_ref = NEW.payment_intent limit 1));
  if v_tx is null then return NEW; end if;
  update public.accountant_reveal_payment_check set resolved_at = null, verdict = 'exception',
         resolution = 'reopened: a card dispute ' || NEW.status, ceo_handoff_id = null, held_question_id = null
   where transaction_id = v_tx and NEW.status not in ('won');
  perform public.fn_accountant_reconciles_reveal(v_tx);
  return NEW;
exception when others then
  return NEW;   -- recording the dispute never fails on the check; the hourly sweep re-reads it
end $fn$;
revoke execute on function public.trg_dispute_reopens_the_payment_check() from public, anon, authenticated;
drop trigger if exists z60_dispute_reopens_the_payment_check on public.stripe_dispute;
create trigger z60_dispute_reopens_the_payment_check after insert or update of status on public.stripe_dispute
  for each row execute function public.trg_dispute_reopens_the_payment_check();

-- ══ 14. THE BOOKS: section 1 posts through fn_gl_post_reveal_fee and names the invoice; refunds and disputes ═══
create or replace function public.fn_gl_sync_business()
returns integer language plpgsql set search_path to 'public', 'pg_temp' as $function$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2); extra numeric(18,2); lines jsonb; v_orphans jsonb;
        v_jid bigint; v_over numeric(18,2);
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  select num_value into fx        from public.gl_settings where key='usd_to_aed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);
  fx        := coalesce(fx, 3.6725);

  -- TEST MONEY NEVER REACHES THE BOOKS (15 Sep 2026). Every business branch below books only a row that
  -- fn_gl_fixture_or_orphan passes. Journal #690 was an E2E fixture due whose supplier and transaction the
  -- teardown had deleted; it posted the first tick after the bank-booking hold was lifted. A demo reveal's lines are
  -- written to public.demo_shadow_trace by fn_gl_post_reveal_fee instead (13 Nov 2026).

  -- 1) Reveal-fee revenue with Stripe fee split (refunded transactions excluded)
  --    13 Nov 2026 (accountant): posted by fn_gl_post_reveal_fee only once Stripe's own figures are in (stripe_fee_fils
  --    from the balance transaction): Dr 1050 net / Dr 6100 card fee / Cr 4000 the fee / Cr 2300 anything charged above
  --    the fee / Dr 6110 Invoicing fee accrued / Cr 2200. The memo names our invoice (reveal_invoices.invoice_no) and
  --    Stripe's (transactions.stripe_invoice_number). No VAT line. No estimated card fee: a sale whose fee is unread waits.
  for r in
    select t.id, t.stripe_invoice_number
    from public.transactions t
    where t.fee_status='paid' and coalesce(t.reveal_fee,0) > 0 and t.stripe_fee_fils is not null
      and coalesce(t.refund_status,'') not in ('refunded','refund_approved','succeeded')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=t.id::text)
      and public.fn_gl_fixture_or_orphan(t.id, null, null) is null
  loop
    v_jid := public.fn_gl_post_reveal_fee(r.id);
    if v_jid is not null then n := n + 1; end if;
  end loop;

  -- 1b) REFUND PAID OUT: everything the customer paid (total_charged) goes back. Stripe keeps its
  --     processing fee and QuotesDone absorbs it (founder, 14 Sep 2026). 'succeeded' is the status the
  --     refunds-table path writes, and it was missing here, so a Stripe-settled refund never posted.
  --     If the sale was booked, the refund reverses it: the fee through 6900 (refunds expense, which the supplier's
  --     non-response clawback credits back) and anything charged above the fee out of 2300, where the sale put it;
  --     the fee booked at sale stays in 6100 as the absorbed cost. If it was not, the only real movement is the fee.
  --     13 Nov 2026: the memo names the invoice refunded.
  for r in
    select t.id, coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) as amt, coalesce(t.reveal_fee, 0) as fee_amt,
           coalesce(round(t.stripe_fee_fils / 100.0, 2), nullif(t.processing_fee, 0), round(coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0)*fee_pct/100 + fee_fixed, 2)) as fee_absorbed,
           exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=t.id::text) as sale_booked,
           coalesce((select ri.invoice_no from public.reveal_invoices ri where ri.transaction_id = t.id), t.stripe_invoice_number, left(t.id::text, 8)) as inv,
           coalesce(t.refund_resolved_at::date, t.revealed_at::date, current_date) as d
    from public.transactions t
    where coalesce(t.refund_status,'') in ('refunded','refund_approved','succeeded')
      and coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref=t.id::text)
      and public.fn_gl_fixture_or_orphan(t.id, null, null) is null
  loop
    gross := round(r.amt,2);
    if r.sale_booked then
      v_over := greatest(gross - round(r.fee_amt, 2), 0);
      lines := jsonb_build_array(jsonb_build_object('account','6900','debit',gross - v_over));
      if v_over > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','2300','debit',v_over)); end if;
      lines := lines || jsonb_build_array(jsonb_build_object('account','1050','credit',gross));
      perform public.fn_gl_entry(r.d, 'Reveal charge refunded in full to the customer, invoice ' || r.inv || '; the Stripe fee booked at sale stays in 6100, absorbed',
        'refund_paid', r.id::text, lines, 'gl_sync');
      n := n + 1;
    else
      fee := least(round(coalesce(r.fee_absorbed,0),2), gross);
      if fee > 0 then
        perform public.fn_gl_entry(r.d, 'Stripe processing fee absorbed on a reveal refunded in full before its sale was booked, invoice ' || r.inv,
          'refund_paid', r.id::text,
          jsonb_build_array(jsonb_build_object('account','6100','debit',fee),
                            jsonb_build_object('account','1050','credit',fee)), 'gl_sync');
        n := n + 1;
      end if;
    end if;
  end loop;

  -- 1c) A CARD DISPUTE (13 Nov 2026, accountant). Stripe withdraws the disputed amount from the balance when the dispute
  --     opens: Dr 6900 / Cr 1050. A dispute won returns it: the reversal Dr 1050 / Cr 6900. A test-mode or demo dispute is
  --     never booked. Stripe's dispute fee is not on the dispute row, so it is not booked here (it arrives as its own fee).
  for r in
    select d.id, d.amount_fils, d.status, d.transaction_id, coalesce(d.first_seen_at::date, current_date) as d1, coalesce(d.closed_at::date, current_date) as d2
    from public.stripe_dispute d
    where d.livemode and coalesce(d.amount_fils, 0) > 0 and lower(coalesce(d.currency, 'aed')) = 'aed'
      and (d.transaction_id is null or public.fn_gl_fixture_or_orphan(d.transaction_id, null, null) is null)
  loop
    if not exists (select 1 from public.gl_journal g where g.source='dispute_withdrawn' and g.source_ref=r.id) then
      perform public.fn_gl_entry(r.d1, 'Card dispute ' || r.id || ': Stripe withdrew the disputed amount', 'dispute_withdrawn', r.id,
        jsonb_build_array(jsonb_build_object('account','6900','debit', r.amount_fils / 100.0),
                          jsonb_build_object('account','1050','credit', r.amount_fils / 100.0)), 'gl_sync');
      n := n + 1;
    end if;
    if r.status = 'won' and not exists (select 1 from public.gl_journal g where g.source='dispute_won' and g.source_ref=r.id) then
      perform public.fn_gl_entry(r.d2, 'Card dispute ' || r.id || ' won: Stripe returned the disputed amount', 'dispute_won', r.id,
        jsonb_build_array(jsonb_build_object('account','1050','debit', r.amount_fils / 100.0),
                          jsonb_build_object('account','6900','credit', r.amount_fils / 100.0)), 'gl_sync');
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
            'Our invoice ' || coalesce(v_inv, '') || ' is attached to the notice and filed in the customer''s Documents when it is rendered.',
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
declare r record; v text := ''; i int := 0; v_open int;
begin
  for r in
    select t.reveal_fee, t.quote_amount, coalesce(t.paid_at, t.revealed_at) as at, ii.category, ii.emirate,
           coalesce(ri.invoice_no, t.stripe_invoice_number) as inv, k.verdict
      from public.transactions t
      left join public.inquiries ii on ii.id = t.inquiry_id
      left join public.reveal_invoices ri on ri.transaction_id = t.id
      left join public.accountant_reveal_payment_check k on k.transaction_id = t.id
     where t.fee_status = 'paid' and coalesce(t.paid_at, t.revealed_at) >= p_from and coalesce(t.paid_at, t.revealed_at) < p_to
       and not public.fn_transaction_is_demo(t.id)
     order by coalesce(t.paid_at, t.revealed_at)
  loop
    i := i + 1;
    v := v || E'\n   ' || i || ') AED ' || to_char(r.reveal_fee, 'FM999,999,990.00') || ' reveal fee on a quotation of AED '
         || to_char(r.quote_amount, 'FM999,999,990.00') || ' ex-VAT, ' || coalesce(r.category, 'trade not recorded')
         || coalesce(', ' || r.emirate, '') || ', invoice ' || coalesce(r.inv, '(not numbered)')
         || case coalesce(r.verdict, 'waiting_for_facts') when 'matched' then ', reconciled' when 'exception' then ', NOT reconciled: with the CEO' else ', reconcile waiting for Stripe' end;
  end loop;
  select count(*) into v_open from public.accountant_reveal_payment_check where verdict = 'exception' and resolved_at is null and not is_demo;
  return case when i = 0 then E'\n\nSales today: none.' else E'\n\nSales today (' || i || '):' || v end
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
    -- copy did is recorded instead; a copy that itself failed is escalated below, never sent a third time.
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
        if coalesce(v_carried.status, '') !~* 'fail|bounce|error|undeliver|reject' then v_verdict := 'already_on_' || v_channel; end if;
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
                              'recorded_elsewhere', 'test_mode_not_demo', 'rehearsal_torn_down']));

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
  ('payment.unrecorded', 'accountant', 'customer_support',
   'A customer paid a reveal and no sale could be recorded yet: customer_support tells the customer once that the payment arrived and the reveal is being completed; the heal is reported on this handoff.',
   'fn_customer_support_tells_payment_received', interval '1 hour', false,
   'scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql')
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;
