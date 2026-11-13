-- PROBE: A PAID REVEAL IS RECONCILED, BOOKED AND TIMED BY THE ACCOUNTANT FROM THE MOMENT IT IS PAID (13 Nov 2026; seat: accountant).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back. Run it after the file
-- (and, for the hand-over assertions marked [owner], after the_it_engineer_closes_every_loop_it_opens.sql's fn_seat_handoff),
-- or with them in one rolled-back transaction:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql \
--     scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid_probe.sql
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
--      dispute is a new occurrence and its fee is booked.
do $probe$
declare
  c_tx constant uuid := '29ac49f5-1f4e-4dc5-989a-479143f7ac8c';
  c_q2 constant uuid := '7ca86d2e-5f34-401b-a42c-6b2d219721ce';
  v_bad text[] := '{}'; v_t0 timestamptz := now(); v_rev timestamptz; v_paid timestamptz; n int; m int; v_dl timestamptz;
  v_steps text[]; j record; v_dr numeric; v_cr numeric; v_memo text; v_ev jsonb; v_inv text; v_inv2 text; v_sweep jsonb;
  v_seq0 bigint; v_seq1 bigint; v_brief text; v_tx2 uuid; v_cust uuid; v_fee bigint; v_ret jsonb; v_owner boolean; v_k record;
  v_settle text := 'not tried'; v_gl text := 'not run'; v_ctid tid; v_ctid2 tid;
begin
  select revealed_at into v_rev from public.transactions where id = c_tx;
  if v_rev is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: transaction 29ac49f5 is not in production'); end if;
  v_paid := v_rev - interval '3 minutes';
  perform set_config('qd.probe_invoice_number', 'probe', true);   -- a live probe sale takes no number from the company's series
  select last_value + case when is_called then 0 else -1 end into v_seq0 from public.reveal_invoice_no_seq;
  v_owner := position('fn_payload_names_a_live_payment' in pg_get_functiondef('public.fn_seat_handoff(text,text,text,text,text,jsonb)'::regprocedure)) > 0;

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
  begin
    update public.refunds set status = 'succeeded', stripe_refund_id = 're_zz_probe_w1', settled_at = now() where transaction_id = v_tx2 and reason_code = 'overcharge_return';
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
  select last_value + case when is_called then 0 else -1 end into v_seq1 from public.reveal_invoice_no_seq;
  if v_seq1 is distinct from v_seq0 then v_bad := v_bad || ('the probe took a real invoice number: ' || v_seq0 || ' -> ' || v_seq1)::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end,
    'owner_fn_seat_handoff', v_owner, 'shadow_steps', v_steps, 'journal_debits', v_dr, 'journal_credits', v_cr, 'memo', v_memo,
    'settle', v_settle, 'gl_b', v_gl, 'return', v_ret, 'sweep', v_sweep);
end $probe$;
