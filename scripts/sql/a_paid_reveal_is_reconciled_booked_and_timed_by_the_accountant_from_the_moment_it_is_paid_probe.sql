-- PROBE: A PAID REVEAL IS RECONCILED, BOOKED AND TIMED BY THE ACCOUNTANT FROM THE MOMENT IT IS PAID (13 Nov 2026; seat: accountant).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back. Run it after the file
-- (and, for the hand-over assertions marked [owner], after the_it_engineer_closes_every_loop_it_opens.sql's fn_seat_handoff),
-- or, BEFORE the apply, on a LOCAL copy of the schema (docs/runbooks/local-database.md), with the files in front of it in
-- one rolled-back transaction. Never rehearsed on production (coordinator, 13 Nov 2026: rehearsals there held locks
-- that timed out live readers); docs/runbooks/a_paid_reveal_release_13_nov_2026.md is the release.
--
-- Fixtures: the only rows production has, all ZZ DEMO at example.invalid: transaction 29ac49f5 (quote f99c6e2f, fee 777.60,
-- card fee 3,448 fils) and the unpaid ZZ DEMO quote 7ca86d2e (65,960 ex-VAT). Nobody can be reached: every identity is a
-- demo one, nothing is committed, pg_net and the outbox send only committed rows. The invoice sequence is never touched.
--   A. TEST MODE: the chain is in demo_shadow_trace only (reveal.paid, reveal.reconcile, reconcile, journal, window clock,
--      our ZZ-TEST number); no agent_actions, no gl_journal, no brief line, no sequence number; a replay keeps ONE number;
--      unjudged, it reaches the CEO (shadow) at 45 minutes and never closes itself.
--   C. LIVE, CLEAN (qd.probe_files_demo_handoff on): matched by code, reveal.reconcile closed with evidence, journal
--      1050 743.12 / 6100 34.48 / 4000 777.60 and nothing else, a second journal refused, sale.made, a real brief line.
--   B. LIVE, OVERCHARGED, ON A DEMO IDENTITY (switch off), inserted already carrying a paid_at 7 days old: the window counts from it
--      to 23:59:59 Dubai; booked anyway with Cr 2300 38.77; exceptions live_payment_on_test_identity + charged_above_fee;
--      at 45 minutes the CEO [owner] and the founder (finance_alert) are told; the CEO's 'refund_difference' requests exactly
--      38.77 through fn_refund_request with the CEO's approval record; the check stays open until Stripe confirms; a
--      dispute is a new occurrence and its fee is booked. The CEO's task closes and the customer is told only once the
--      executor has submitted the return to Stripe.
--   E. A NON-DEMO CUSTOMER (review 3, item 1): the same fixture with every demo mark removed inside this rolled-back
--      transaction by removing every contact detail (so nobody can be reached by any channel). An overcharge
--      return skips the second seat and only it: a refused decision sets the CEO's task to 'blocked' with the reason, cancels
--      the refund and hands the check back to the CEO as a new occurrence, and tells the customer nothing; a decision that
--      goes through leaves the task open and the customer untold until the refund is submitted to Stripe; a Stripe
--      failure afterwards hands it back again.
--   F. NOTHING TO BOOK (review 3, item 5): a live sale with a zero fee closes with that reason, the CEO's task list shows
--      it, and it is neither re-read every hour nor listed as "not yet booked".
do $probe$
declare
  c_tx constant uuid := '29ac49f5-1f4e-4dc5-989a-479143f7ac8c';
  c_q2 constant uuid := '7ca86d2e-5f34-401b-a42c-6b2d219721ce';
  v_bad text[] := '{}'; v_t0 timestamptz := now(); v_rev timestamptz; v_paid timestamptz; n int; m int; v_dl timestamptz;
  v_steps text[]; j record; v_dr numeric; v_cr numeric; v_memo text; v_ev jsonb; v_inv text; v_inv2 text; v_sweep jsonb;
  v_seq0 bigint; v_seq1 bigint; v_brief text; v_tx2 uuid; v_cust uuid; v_fee bigint; v_ret jsonb; v_owner boolean; v_k record;
  v_settle text := 'not tried'; v_gl text := 'not run'; v_ctid tid; v_ctid2 tid; v_tx3 uuid; v_p jsonb; v_task bigint;
  v_tx4 uuid; v_tx5 uuid; v_def text; v_ret2 jsonb; v_task2 bigint; v_rid bigint; v_e text := 'not run'; v_q4 uuid; v_q5 uuid; v_cols text; v_sel text;
begin
  select revealed_at into v_rev from public.transactions where id = c_tx;
  if v_rev is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: transaction 29ac49f5 is not in production'); end if;
  v_paid := v_rev - interval '3 minutes';
  perform set_config('qd.probe_invoice_number', 'probe', true);   -- a live probe sale takes no number from the company's series
  select last_value + case when is_called then 0 else -1 end into v_seq0 from public.reveal_invoice_no_seq;
  v_owner := position('fn_payload_names_a_live_payment' in pg_get_functiondef('public.fn_seat_handoff(text,text,text,text,text,jsonb)'::regprocedure)) > 0;

  -- ── 0. EXISTING ROWS (coordinator (a)): the backfill read Stripe's evidence, and no old test payment is real revenue ──
  if (select livemode from public.transactions where id = c_tx) is distinct from false then
    v_bad := v_bad || 'existing: 29ac49f5 (its Stripe links carry /test_) is not test mode after the backfill'::text;
  end if;
  select count(*) into n from public.gl_journal g join public.transactions t on g.source_ref = t.id::text
   where g.source = 'reveal_fee' and t.livemode is distinct from true;
  if n <> 0 then v_bad := v_bad || ('existing: ' || n || ' reveal_fee journal(s) for a payment not known to be live')::text; end if;

  -- ── A. TEST MODE ────────────────────────────────────────────────────────────────────────────────
  update public.transactions set livemode = false, paid_at = v_paid, paid_at_source = null, refund_deadline = null, refund_status = null,
         stripe_amount_received_fils = 81637, stripe_bt_amount_fils = 81637, stripe_bt_currency = 'aed', stripe_fee_fils = 3448 where id = c_tx;
  select refund_deadline into v_dl from public.transactions where id = c_tx;
  if v_dl is distinct from public.fn_reveal_refund_window_ends(v_paid) then v_bad := v_bad || ('A: the window does not count from paid_at: ' || coalesce(v_dl::text, 'null'))::text; end if;
  if to_char(v_dl at time zone 'Asia/Dubai', 'HH24:MI:SS') <> '23:59:59' then v_bad := v_bad || ('A: the window does not end at 23:59:59 Dubai: ' || v_dl)::text; end if;
  update public.transactions set revealed_at = null where id = c_tx;
  update public.transactions set revealed_at = v_rev where id = c_tx;     -- the sale, as the insert fires it
  v_inv := public.fn_reveal_invoice_number(c_tx);
  update public.transactions set revealed_at = null where id = c_tx;     -- a replay of the same sale
  update public.transactions set revealed_at = v_rev where id = c_tx;
  v_inv2 := public.fn_reveal_invoice_number(c_tx);
  select count(*) into n from public.reveal_invoices where transaction_id = c_tx;
  if v_inv is distinct from 'ZZ-TEST-INV-29AC49F5' or v_inv2 is distinct from v_inv or n <> 1 then
    v_bad := v_bad || ('A: a replay changed or added an invoice number: ' || coalesce(v_inv, 'null') || ' / ' || coalesce(v_inv2, 'null') || ' rows ' || n)::text;
  end if;
  select array_agg(distinct step || ':' || kind) into v_steps from public.demo_shadow_trace where transaction_id = c_tx and recorded_at >= v_t0;
  foreach v_memo in array array['handoff:reveal.paid', 'handoff:reveal.reconcile', 'reconcile:reveal.reconcile', 'journal:reveal_fee',
                                'window_clock:refund_window', 'invoice_number:our_invoice_no'] loop
    if not (v_memo = any(coalesce(v_steps, '{}'))) then v_bad := v_bad || ('A: shadow lacks ' || v_memo)::text; end if;
  end loop;
  select payload into v_ev from public.demo_shadow_trace where transaction_id = c_tx and step = 'journal' and recorded_at >= v_t0 order by id desc limit 1;
  if not coalesce(v_ev->'lines' @> '[{"account":"2300","credit":38.77}]'::jsonb, false) then v_bad := v_bad || 'A: shadow journal lacks Cr 2300 38.77'::text; end if;
  if coalesce(v_ev->>'lines', '') ~ '6110|2200' then v_bad := v_bad || 'A: the journal still accrues the Invoicing fee'::text; end if;
  select count(*) into n from public.agent_actions where created_at >= v_t0 and (target_id like '%' || c_tx::text || '%' or detail->>'transaction_id' = c_tx::text);
  if n <> 0 then v_bad := v_bad || ('A: a test-mode payment filed ' || n || ' real handoff(s)')::text; end if;
  select count(*) into n from public.gl_journal where source_ref = c_tx::text;
  if n <> 0 then v_bad := v_bad || ('A: a test-mode payment reached the real ledger: ' || n)::text; end if;
  v_brief := public.fn_founder_brief_sale_lines(v_rev - interval '1 day', v_rev + interval '1 day');
  if v_brief !~ 'Sales today: none' then v_bad := v_bad || ('A: a test-mode payment reached the founder brief: ' || v_brief)::text; end if;
  update public.accountant_reveal_payment_check set opened_at = now() - interval '50 minutes' where transaction_id = c_tx;
  v_sweep := public.fn_accountant_payment_checks_sweep();
  select count(*) into n from public.demo_shadow_trace where transaction_id = c_tx and recorded_at >= v_t0 and step = 'escalation' and kind = 'payment.exception';
  if n <> 1 then v_bad := v_bad || ('A: the unjudged exception did not reach the CEO at 45 minutes (shadow): ' || n)::text; end if;
  select count(*) into n from public.accountant_reveal_payment_check where transaction_id = c_tx and resolved_at is not null;
  if n <> 0 then v_bad := v_bad || 'A: the exception closed itself'::text; end if;

  -- ── C. LIVE, CLEAN (the probe switch makes the demo identity count as clean) ─────────────────────────
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  delete from public.accountant_reveal_payment_check where transaction_id = c_tx;
  update public.transactions set livemode = true, processing_fee = 0, total_charged = reveal_fee, stripe_amount_received_fils = 77760,
         stripe_bt_amount_fils = 77760, stripe_invoice_total_fils = 77760 where id = c_tx;
  update public.transactions set revealed_at = null where id = c_tx;
  update public.transactions set revealed_at = v_rev where id = c_tx;
  select a.status, a.evidence into j from public.agent_actions a
   where a.kind = 'handoff' and a.agent = 'accountant' and a.target_id = 'reveal.reconcile:' || c_tx::text and a.created_at >= v_t0;
  if j.status is distinct from 'done' or j.evidence->>'verdict' is distinct from 'matched' then
    v_bad := v_bad || ('C: reveal.reconcile to the accountant is ' || coalesce(j.status, 'missing') || ' / ' || coalesce(j.evidence->>'verdict', 'no verdict'))::text;
  end if;
  select sum(l.debit), sum(l.credit), max(g.memo), count(*),
         count(*) filter (where (l.account_code = '1050' and l.debit = 743.12) or (l.account_code = '6100' and l.debit = 34.48) or (l.account_code = '4000' and l.credit = 777.60))
    into v_dr, v_cr, v_memo, m, n
    from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id where g.source = 'reveal_fee' and g.source_ref = c_tx::text;
  if v_dr is null then v_bad := v_bad || 'C: no reveal_fee journal'::text;
  else
    if v_dr <> v_cr then v_bad := v_bad || ('C: journal not balanced: ' || v_dr || ' / ' || v_cr)::text; end if;
    if n <> 3 or m <> 3 then v_bad := v_bad || ('C: the journal is not exactly 1050 743.12 / 6100 34.48 / 4000 777.60 (' || n || ' of ' || m || ' lines)')::text; end if;
    if v_memo !~ 'PQZAIUL8-0001' or position(v_inv in v_memo) = 0 then v_bad := v_bad || ('C: the journal does not name both invoices: ' || v_memo)::text; end if;
  end if;
  begin
    perform public.fn_gl_entry(current_date, 'probe: a second reveal_fee journal', 'reveal_fee', c_tx::text,
      '[{"account":"1050","debit":1},{"account":"4000","credit":1}]'::jsonb, 'probe');
    v_bad := v_bad || 'C: a second reveal_fee journal for one sale was accepted'::text;
  exception when unique_violation then null;
  end;
  select count(*) into n from public.agent_actions a where a.kind = 'handoff' and a.agent = 'ceo' and a.detail->>'type' = 'sale.made'
     and a.detail->>'transaction_id' = c_tx::text and a.status = 'done' and a.created_at >= v_t0;
  if n <> 1 then v_bad := v_bad || ('C: sale.made to the CEO: ' || n)::text; end if;
  v_brief := public.fn_founder_brief_sale_lines(v_rev - interval '1 day', v_rev + interval '1 day');
  if v_brief !~ '1\) AED 777\.60 reveal fee' then v_bad := v_bad || ('C: the brief does not list the sale: ' || v_brief)::text; end if;
  perform set_config('qd.probe_files_demo_handoff', '', true);

  -- ── B. LIVE, OVERCHARGED, ON A DEMO IDENTITY, INSERTED WITH paid_at ─────────────────────────────────
  select i.customer_id, round(q.price_ex_vat * 0.03 * 100)::bigint into v_cust, v_fee
    from public.quotes q join public.inquiries i on i.id = q.inquiry_id where q.id = c_q2;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, app_fee, total_charged, processing_fee,
         customer_price, paid_by, payment_ref, fee_status, livemode, paid_at, stripe_fee_fils, stripe_amount_received_fils, stripe_bt_amount_fils, stripe_bt_currency)
  select q.id, q.inquiry_id, q.supplier_id, v_cust, q.quote_amount, v_fee / 100.0, v_fee / 100.0, (v_fee + 3877) / 100.0, 0,
         q.quote_amount, 'customer', 'pi_zz_probe_w1_overcharge', 'paid', true, now() - interval '7 days', 6000, v_fee + 3877, v_fee + 3877, 'aed'
    from public.quotes q where q.id = c_q2
  returning id into v_tx2;
  -- a replay of a live sale keeps its ONE number, and does not rewrite it (the row is the same row)
  select ctid, invoice_no into v_ctid, v_inv from public.reveal_invoices where transaction_id = v_tx2;
  update public.transactions set revealed_at = null where id = v_tx2;
  update public.transactions set revealed_at = now() where id = v_tx2;
  v_inv2 := public.fn_reveal_invoice_number(v_tx2);
  select ctid into v_ctid2 from public.reveal_invoices where transaction_id = v_tx2;
  select count(*) into n from public.reveal_invoices where transaction_id = v_tx2;
  if v_inv is null or v_inv2 is distinct from v_inv or v_ctid2 is distinct from v_ctid or n <> 1 then
    v_bad := v_bad || ('B: a replay of a live sale changed its invoice number or rewrote it: ' || coalesce(v_inv, 'null') || ' / ' || coalesce(v_inv2, 'null'))::text;
  end if;
  select refund_deadline into v_dl from public.transactions where id = v_tx2;
  if v_dl is distinct from public.fn_reveal_refund_window_ends(now() - interval '7 days') then
    v_bad := v_bad || ('B: a sale inserted with paid_at counts its window from elsewhere: ' || coalesce(v_dl::text, 'null'))::text;
  end if;
  select * into v_k from public.accountant_reveal_payment_check where transaction_id = v_tx2;
  if v_k.verdict is distinct from 'exception' or not v_k.findings @> '[{"code":"charged_above_fee"}]'::jsonb
     or not v_k.findings @> '[{"code":"live_payment_on_test_identity"}]'::jsonb then
    v_bad := v_bad || ('B: the live overcharge on a demo identity was not an exception with both findings: ' || coalesce(v_k.findings::text, 'no check'))::text;
  end if;
  select count(*) into n from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
   where g.source = 'reveal_fee' and g.source_ref = v_tx2::text and l.account_code = '2300' and l.credit = 38.77;
  if n <> 1 then v_bad := v_bad || 'B: a live payment on a demo identity was not booked with Cr 2300 38.77'::text; end if;
  update public.accountant_reveal_payment_check set opened_at = now() - interval '50 minutes' where transaction_id = v_tx2;
  v_sweep := public.fn_accountant_payment_checks_sweep();
  select * into v_k from public.accountant_reveal_payment_check where transaction_id = v_tx2;
  if v_k.escalated_at is null then v_bad := v_bad || 'B: not escalated within the hour'::text; end if;
  select count(*) into n from public.notifications where created_at >= v_t0 and type = 'founder_alert' and subject ~ ('Payment exception on reveal ' || left(v_tx2::text, 8));
  if n = 0 then v_bad := v_bad || 'B: the founder was not told in the same hour'::text; end if;
  if v_owner then
    select count(*) into n from public.agent_actions where kind = 'handoff' and agent = 'ceo' and detail->>'type' = 'payment.exception' and detail->>'transaction_id' = v_tx2::text;
    if n <> 1 then v_bad := v_bad || ('B [owner]: payment.exception to the CEO: ' || n)::text; end if;
  end if;
  -- the CEO decides 'refund_difference': what fn_reason_apply_ceo__payment_exception does, without a model
  update public.accountant_reveal_payment_check set ceo_decision = 'refund_difference', ceo_decided_at = now() where transaction_id = v_tx2;
  v_ret := public.fn_payment_check_returns_difference(v_tx2, 'ceo', 'probe: the customer paid AED 38.77 above the fee');
  select count(*) into n from public.refunds where transaction_id = v_tx2 and reason_code = 'overcharge_return' and amount_fils = 3877 and refund_decision_id is not null;
  if n <> 1 then v_bad := v_bad || ('B: the return of exactly 38.77 was not requested and approved through the refund path: ' || coalesce(v_ret::text, 'null'))::text; end if;
  select count(*) into n from public.accountant_reveal_payment_check where transaction_id = v_tx2 and resolved_at is null and refund_id is not null;
  if n <> 1 then v_bad := v_bad || 'B: the check did not stay open after the decision'::text; end if;
  v_task := nullif(v_ret->'refund'->>'ceo_task_id', '')::bigint;
  if not coalesce((v_ret->>'ok')::boolean, false) then v_bad := v_bad || ('B: the decided return did not go through: ' || coalesce(v_ret::text, 'null'))::text; end if;
  if not exists (select 1 from public.ceo_task where task_id = v_task and state in ('open', 'working')) then
    v_bad := v_bad || 'B: the CEO''s task closed before the refund was submitted'::text;
  end if;
  if exists (select 1 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'overcharge.customer_notice' and detail->>'transaction_id' = v_tx2::text) then
    v_bad := v_bad || 'B: the customer was told before the refund was submitted'::text;
  end if;
  -- the accountant's executor submits it (accountant/actions/refunds.ts writes exactly this)
  update public.refunds set status = 'processing', stripe_refund_id = 're_zz_probe_w1' where transaction_id = v_tx2 and reason_code = 'overcharge_return';
  if not exists (select 1 from public.ceo_task where task_id = v_task and state = 'done' and evidence ~ 're_zz_probe_w1') then
    v_bad := v_bad || 'B: submitting the refund did not close the CEO''s task with the Stripe refund as evidence'::text;
  end if;
  if v_owner and not exists (select 1 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'overcharge.customer_notice' and detail->>'transaction_id' = v_tx2::text) then
    v_bad := v_bad || 'B [owner]: the customer was not told once the refund was submitted'::text;
  end if;
  begin
    update public.refunds set status = 'succeeded', settled_at = now() where transaction_id = v_tx2 and reason_code = 'overcharge_return';
    select case when resolved_at is not null then 'closed on settle' else 'NOT closed on settle' end into v_settle from public.accountant_reveal_payment_check where transaction_id = v_tx2;
    if v_settle <> 'closed on settle' then v_bad := v_bad || 'B: Stripe''s confirmation did not close the check'::text; end if;
  exception when others then v_settle := 'settle refused here: ' || left(sqlerrm, 160);
  end;
  -- a dispute on the same payment is a NEW occurrence that reaches everyone again
  insert into public.stripe_dispute (id, livemode, payment_intent, transaction_id, amount_fils, currency, reason, status, fee_fils)
  values ('dp_zz_probe_w1', true, 'pi_zz_probe_w1_overcharge', v_tx2, v_fee + 3877, 'aed', 'fraudulent', 'needs_response', 5500);
  select * into v_k from public.accountant_reveal_payment_check where transaction_id = v_tx2;
  if v_k.exception_count < 2 or not v_k.findings @> '[{"code":"disputed"}]'::jsonb then
    v_bad := v_bad || ('B: a dispute did not open a new occurrence: count ' || v_k.exception_count)::text;
  end if;
  begin
    perform public.fn_gl_sync_business();
    select string_agg(g.source || ' ' || l.account_code || ' ' || l.debit || '/' || l.credit, '; ' order by g.id, l.line_no) into v_gl
      from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
     where g.source_ref in ('dp_zz_probe_w1', 'refund:' || (select id from public.refunds where transaction_id = v_tx2 limit 1));
    if coalesce(v_gl, '') !~ 'dispute_fee 6100 55\.00' then v_bad := v_bad || ('B: the dispute fee was not booked: ' || coalesce(v_gl, 'nothing'))::text; end if;
    if v_settle = 'closed on settle' and coalesce(v_gl, '') !~ 'refund_paid 2300 38\.77' then v_bad := v_bad || ('B: the return was not booked out of 2300: ' || coalesce(v_gl, 'nothing'))::text; end if;
  exception when others then v_gl := 'fn_gl_sync_business raised: ' || left(sqlerrm, 200); v_bad := v_bad || v_gl;
  end;
  -- review 2, item 2: the overcharge return left the sale itself untouched; its fee's ladder still runs; no stale CEO task
  select count(*) into n from public.transactions where id = v_tx2 and refund_status = 'window_open' and refund_requested_at is null and refund_amount_aed is null;
  if n <> 1 then v_bad := v_bad || 'B: the overcharge return wrote the sale''s own refund status'::text; end if;
  if public.fn_refund_state(v_tx2)->>'state' in ('refunded', 'refund_rejected') then
    v_bad := v_bad || ('B: after an overcharge return the fee is no longer refundable: ' || (public.fn_refund_state(v_tx2)->>'state'))::text;
  end if;
  if v_task is not null and exists (select 1 from public.ceo_task where task_id = v_task and state in ('open', 'working')) then
    v_bad := v_bad || 'B: the "Decide refund" task was left open'::text;
  end if;
  -- review 2, item 7: a second return of the same overcharge is refused; the return is booked at 38.77, not the whole charge
  begin
    perform public.fn_refund_request(3877, 'overcharge_return', 'ceo', null, null, null, c_q2, 'pi_zz_probe_w1_overcharge', null, 'probe: a second return', v_tx2);
    v_bad := v_bad || 'B: a second overcharge return on one payment was accepted'::text;
  exception when others then null;
  end;
  if v_settle = 'closed on settle' and coalesce(v_gl, '') !~ 'refund_paid 1050 0\.00/38\.77' then v_bad := v_bad || ('B: the return was not credited to 1050 at 38.77: ' || coalesce(v_gl, ''))::text; end if;
  -- one reader of the window counts from the payment (fn_refund_state's chase day), not from when the row was written
  if (public.fn_refund_state(v_tx2)->>'chase_due_at')::timestamptz is distinct from public.fn_add_working_days(now() - interval '7 days', 3) then
    v_bad := v_bad || ('B: fn_refund_state does not count from paid_at: ' || coalesce(public.fn_refund_state(v_tx2)->>'chase_due_at', 'null'))::text;
  end if;

  -- ── E. A NON-DEMO CUSTOMER: THE RETURN SKIPS THE SECOND SEAT AND ONLY IT; A FAILURE GOES BACK TO THE CEO ─────────────
  -- demo-ness is generated from the contact details (any example/invalid domain or 050 000 00xx number IS demo), so the
  -- non-demo fixture has NO contact detail at all: it cannot be reached by any channel, and it all rolls back
  update public.customers set email = null, phone = null, whatsapp_phone = null, full_name = 'Probe W1 customer without contact' where id = v_cust;
  update public.inquiries set provenance = coalesce(provenance, '{}'::jsonb) - 'qd_run', brief_source = null
   where id = (select inquiry_id from public.quotes where id = c_q2);
  update public.leads set email = null, claimed_by = null, phone = null, tags = '{}', company_name = 'Probe W1 supplier without contact', source = 'probe'
   where id = (select supplier_id from public.quotes where id = c_q2);
  -- one sale per quote (transactions_quote_id_uidx): E and F each sell a copy of the fixture quote (another option number)
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position),
         string_agg(case column_name when 'id' then 'gen_random_uuid()' when 'option_no' then '18 + %s' else quote_ident(column_name) end, ', ' order by ordinal_position)
    into v_cols, v_sel
    from information_schema.columns where table_schema = 'public' and table_name = 'quotes' and is_generated = 'NEVER';
  execute format('insert into public.quotes (' || v_cols || ') select ' || replace(v_sel, '%s', '1') || ' from public.quotes where id = %L returning id', c_q2) into v_q4;
  execute format('insert into public.quotes (' || v_cols || ') select ' || replace(v_sel, '%s', '2') || ' from public.quotes where id = %L returning id', c_q2) into v_q5;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, app_fee, total_charged, processing_fee,
         customer_price, paid_by, payment_ref, fee_status, livemode, paid_at, stripe_fee_fils, stripe_amount_received_fils, stripe_bt_amount_fils, stripe_bt_currency)
  select q.id, q.inquiry_id, q.supplier_id, v_cust, q.quote_amount, v_fee / 100.0, v_fee / 100.0, (v_fee + 3877) / 100.0, 0,
         q.quote_amount, 'customer', 'pi_zz_probe_w1_nondemo', 'paid', true, now() - interval '1 day', 6000, v_fee + 3877, v_fee + 3877, 'aed'
    from public.quotes q where q.id = v_q4
  returning id into v_tx4;
  if public.fn_transaction_is_demo(v_tx4) then v_bad := v_bad || 'E: the fixture still counts as demo'::text; end if;
  if (select findings from public.accountant_reveal_payment_check where transaction_id = v_tx4) @> '[{"code":"live_payment_on_test_identity"}]'::jsonb then
    v_bad := v_bad || 'E: the non-demo payment is flagged as on a test identity'::text;
  end if;
  perform public.fn_accountant_escalates_payment_exception(v_tx4, 'probe', 'recommend_refund_difference', 'probe: charged 38.77 above the fee');
  -- 1. the decision is refused (forced here): blocked, cancelled, handed back, nobody told
  v_def := pg_get_functiondef('public.fn_refund_decide(bigint,boolean,text,text)'::regprocedure);
  execute $redef$create or replace function public.fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text default null)
    returns jsonb language plpgsql as $f$ begin return jsonb_build_object('ok', false, 'error', 'probe: the decision is refused'); end $f$$redef$;
  update public.accountant_reveal_payment_check set ceo_decision = 'refund_difference', ceo_decided_at = now() where transaction_id = v_tx4;
  v_ret2 := public.fn_payment_check_returns_difference(v_tx4, 'ceo', 'probe: return the difference');
  execute v_def;
  v_task2 := nullif(v_ret2->'refund'->>'ceo_task_id', '')::bigint;
  v_rid := nullif(v_ret2->'refund'->>'refund_id', '')::bigint;
  select * into v_k from public.accountant_reveal_payment_check where transaction_id = v_tx4;
  if coalesce((v_ret2->>'ok')::boolean, true) then v_bad := v_bad || 'E: a refused decision was reported as done'::text; end if;
  if not exists (select 1 from public.ceo_task where task_id = v_task2 and state = 'blocked' and blocked_reason ~ 'probe: the decision is refused') then
    v_bad := v_bad || ('E: the CEO''s task is not blocked with the reason: ' || coalesce((select state || ' ' || coalesce(blocked_reason, '') from public.ceo_task where task_id = v_task2), 'no task'))::text;
  end if;
  if not exists (select 1 from public.refunds where id = v_rid and status = 'cancelled') then v_bad := v_bad || 'E: the refused refund was not cancelled'::text; end if;
  if v_k.refund_id is not null or v_k.ceo_decision is not null or v_k.exception_count < 2 or v_k.ceo_handoff_id is null then
    v_bad := v_bad || ('E: the check was not handed back to the CEO: refund ' || coalesce(v_k.refund_id::text, '-') || ', decision ' || coalesce(v_k.ceo_decision, '-') || ', occurrence ' || v_k.exception_count)::text;
  end if;
  if v_owner then
    select count(*) into n from public.agent_actions where kind = 'handoff' and agent = 'ceo' and detail->>'type' = 'payment.exception' and detail->>'transaction_id' = v_tx4::text;
    if n <> 2 then v_bad := v_bad || ('E [owner]: the CEO was not asked again: ' || n || ' payment.exception hand-over(s)')::text; end if;
  end if;
  if exists (select 1 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'overcharge.customer_notice' and detail->>'transaction_id' = v_tx4::text) then
    v_bad := v_bad || 'E: the customer was told of a return that was refused'::text;
  end if;
  -- 2. the CEO decides again and it goes through: NO second-seat review is opened; the task waits for the submission
  update public.accountant_reveal_payment_check set ceo_decision = 'refund_difference', ceo_decided_at = now() where transaction_id = v_tx4;
  v_ret2 := public.fn_payment_check_returns_difference(v_tx4, 'ceo', 'probe: return the difference, again');
  v_task2 := nullif(v_ret2->'refund'->>'ceo_task_id', '')::bigint;
  v_rid := nullif(v_ret2->'refund'->>'refund_id', '')::bigint;
  if not coalesce((v_ret2->>'ok')::boolean, false) or (v_ret2->'decide'->'second_seat'->>'state') is distinct from 'not_required' then
    v_bad := v_bad || ('E: the overcharge return did not skip the second seat: ' || coalesce(v_ret2->>'decide', v_ret2::text))::text;
  end if;
  if exists (select 1 from public.seat_deliberation where subject_table = 'refunds' and subject_id = v_rid::text) then
    v_bad := v_bad || 'E: a second-seat review was opened for an overcharge return'::text;
  end if;
  if not exists (select 1 from public.refunds where id = v_rid and status = 'approved') then v_bad := v_bad || 'E: the approved return is not approved'::text; end if;
  if not exists (select 1 from public.ceo_task where task_id = v_task2 and state in ('open', 'working')) then
    v_bad := v_bad || 'E: the CEO''s task closed before the refund was submitted'::text;
  end if;
  if exists (select 1 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'overcharge.customer_notice' and detail->>'transaction_id' = v_tx4::text) then
    v_bad := v_bad || 'E: the customer was told before the refund was submitted'::text;
  end if;
  update public.refunds set status = 'processing', stripe_refund_id = 're_zz_probe_w1_nondemo' where id = v_rid;
  if not exists (select 1 from public.ceo_task where task_id = v_task2 and state = 'done' and evidence ~ 're_zz_probe_w1_nondemo') then
    v_bad := v_bad || 'E: submitting the refund did not close the CEO''s task'::text;
  end if;
  select count(*) into n from public.agent_actions where kind = 'handoff' and detail->>'type' = 'overcharge.customer_notice' and detail->>'transaction_id' = v_tx4::text;
  if n <> 1 then v_bad := v_bad || ('E: the customer notice after submission: ' || n || ' hand-over(s)')::text; end if;
  -- 3. Stripe fails it afterwards: back to the CEO again, with a blocked task naming Stripe's reason
  update public.refunds set status = 'failed', failure_reason = 'probe: card closed' where id = v_rid;
  select * into v_k from public.accountant_reveal_payment_check where transaction_id = v_tx4;
  if v_k.refund_id is not null or v_k.exception_count < 3
     or not exists (select 1 from public.ceo_task where state = 'blocked' and blocked_reason ~ 'probe: card closed') then
    v_bad := v_bad || ('E: a refund Stripe failed was not handed back with a blocked task: occurrence ' || v_k.exception_count)::text;
  end if;
  v_e := 'ran';

  -- ── F. NOTHING TO BOOK: A ZERO FEE CLOSES WITH ITS REASON ──────────────────────────────────────────────────────────
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, app_fee, total_charged, processing_fee,
         customer_price, paid_by, payment_ref, fee_status, livemode, paid_at)
  select q.id, q.inquiry_id, q.supplier_id, v_cust, q.quote_amount, 0, 0, 0, 0, q.quote_amount, 'customer', 'pi_zz_probe_w1_zero', 'paid', true, now() - interval '2 hours'
    from public.quotes q where q.id = v_q5
  returning id into v_tx5;
  perform public.fn_accountant_reconciles_reveal(v_tx5);
  select * into v_k from public.accountant_reveal_payment_check where transaction_id = v_tx5;
  if v_k.verdict is distinct from 'nothing_to_book' or v_k.resolved_at is null or coalesce(v_k.resolution, '') !~ 'zero fee' then
    v_bad := v_bad || ('F: a zero-fee sale did not close as nothing to book: ' || coalesce(v_k.verdict, 'no check') || ' / ' || coalesce(v_k.resolution, ''))::text;
  end if;
  if not exists (select 1 from public.ceo_task where title = 'Nothing to book on reveal ' || left(v_tx5::text, 8) and state = 'done' and detail ~ 'zero fee') then
    v_bad := v_bad || 'F: the CEO''s task list does not show the nothing-to-book close'::text;
  end if;
  if exists (select 1 from public.fn_accountant_payment_checks_to_read(100) x where x.transaction_id = v_tx5) then
    v_bad := v_bad || 'F: a nothing-to-book sale is still re-read every hour'::text;
  end if;
  v_brief := public.fn_founder_brief_sale_lines(now() - interval '1 day', now() + interval '1 day');
  if v_brief ~ ('\(' || left(v_tx5::text, 8) || '\)') or v_brief !~ 'Closed with nothing to book' then
    v_bad := v_bad || ('F: the brief lists a zero-fee sale as unbooked, or not as closed: ' || v_brief)::text;
  end if;

  -- ── D. MODE UNKNOWN, A NOTICE THAT FAILS, A MONTH ENDING IN .00 (review 2, items 1, 5, 6; coordinator (b)) ──────────
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, app_fee, total_charged, processing_fee,
         customer_price, paid_by, payment_ref, fee_status, livemode, paid_at, stripe_fee_fils, stripe_amount_received_fils, stripe_bt_amount_fils, stripe_bt_currency)
  select q.id, q.inquiry_id, q.supplier_id, i.customer_id, q.quote_amount, round(q.price_ex_vat * 0.03, 2), round(q.price_ex_vat * 0.03, 2), round(q.price_ex_vat * 0.03, 2), 0,
         q.quote_amount, 'customer', 'pi_zz_probe_w1_unknown', 'paid', null, now() - interval '1 hour', 2000, round(q.price_ex_vat * 3)::bigint, round(q.price_ex_vat * 3)::bigint, 'aed'
    from public.quotes q join public.inquiries i on i.id = q.inquiry_id where q.id = '3f0e7209-ad36-44fd-8418-1b07da8d1417'
  returning id into v_tx3;
  select count(*) into n from public.gl_journal where source = 'reveal_fee' and source_ref = v_tx3::text;
  if n <> 0 then v_bad := v_bad || 'D: a payment whose Stripe mode is unknown was booked'::text; end if;
  if exists (select 1 from public.reveal_invoices where transaction_id = v_tx3 and invoice_no is not null) then v_bad := v_bad || 'D: a payment of unknown mode took an invoice number'::text; end if;
  if public.fn_founder_brief_sale_lines(now() - interval '1 day', now() + interval '1 day') !~ 'Stripe mode not known' then v_bad := v_bad || 'D: the brief does not list the payment of unknown mode'::text; end if;
  update public.accountant_reveal_payment_check set resolved_at = now(), resolution = 'probe: the CEO says the money is correct' where transaction_id = v_tx3;
  if (select resolved_at from public.accountant_reveal_payment_check where transaction_id = v_tx3) is not null then
    v_bad := v_bad || 'D: a paid sale with no journal was resolved'::text;
  end if;
  if not public.fn_payload_names_a_live_payment('{"livemode": true, "payment_ref": "pi_x"}'::jsonb) then v_bad := v_bad || 'D: a payload Stripe says is live is not filed'::text; end if;
  -- the CEO notice fails: the books are still written, a finding is raised, the sweep retries
  execute $redef$create or replace function public.fn_accountant_tells_ceo_of_sale(p_tx uuid) returns jsonb language plpgsql as $f$ begin raise exception 'probe: sale.made refused'; end $f$$redef$;
  update public.transactions set livemode = true where id = v_tx3;
  perform public.fn_accountant_reconciles_reveal(v_tx3);
  select * into v_k from public.accountant_reveal_payment_check where transaction_id = v_tx3;
  if v_k.verdict is distinct from 'matched' or v_k.sale_notice_at is not null
     or not exists (select 1 from public.gl_journal where source = 'reveal_fee' and source_ref = v_tx3::text)
     or not exists (select 1 from public.it_engineer_finding where issue_key = 'reveal:sale_notice_failed:' || v_tx3 and closed_at is null) then
    v_bad := v_bad || ('D: a failing CEO notice undid or hid the books: ' || coalesce(v_k.verdict, 'no check'))::text;
  end if;
  -- no number in a hand-over carries more than two decimals (fn_handoff_redact turned 135.000... into "[phone]")
  if (select revenue_aed::text from public.fn_reveal_month_revenue(now())) ~ '\.[0-9]{3,}' then v_bad := v_bad || 'D: the month total carries more than two decimals'::text; end if;
  v_p := jsonb_build_object('month_total_aed', (select revenue_aed from public.fn_reveal_month_revenue(now())), 'fee_aed', round(13500 / 100.0, 2));
  begin perform public.fn_handoff_redact(v_p); exception when others then v_bad := v_bad || ('D: a sale.made payload breaks fn_handoff_redact: ' || sqlerrm)::text; end;
  perform set_config('qd.probe_files_demo_handoff', '', true);

  select last_value + case when is_called then 0 else -1 end into v_seq1 from public.reveal_invoice_no_seq;
  if v_seq1 is distinct from v_seq0 then v_bad := v_bad || ('the probe took a real invoice number: ' || v_seq0 || ' -> ' || v_seq1)::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end,
    'owner_fn_seat_handoff', v_owner, 'shadow_steps', v_steps, 'journal_debits', v_dr, 'journal_credits', v_cr, 'memo', v_memo,
    'settle', v_settle, 'gl_b', v_gl, 'return', v_ret, 'return_e', v_ret2, 'e', v_e, 'sweep', v_sweep);
end $probe$;
