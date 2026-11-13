-- PROBE: A PAID REVEAL IS RECONCILED, BOOKED AND TIMED BY THE ACCOUNTANT FROM THE MOMENT IT IS PAID (13 Nov 2026; seat: accountant).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back. Run it after
-- a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql, or with it in one
-- rolled-back transaction:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql \
--     scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid_probe.sql
--
-- It uses the ONE paid reveal production keeps: transaction 29ac49f5 (ZZ DEMO customer at example.invalid, Stripe test
-- mode, charged AED 816.37 for a fee of AED 777.60, card fee 3,448 fils). Nobody can be reached: the customer and the
-- supplier are demo identities, nothing is committed, and pg_net sends only on commit.
--   A. AS A DEMO (the real rule): the chain is written to demo_shadow_trace and nowhere else: the sales engineer's
--      reveal.paid, the accountant's reveal.reconcile, the reconcile with the overcharge found, the journal it would post
--      (Cr 2300 38.77), the window clock counted from paid_at, our demo invoice number; one hour later, the escalation to
--      the CEO. No agent_actions row, no gl_journal row.
--   B. AS A REAL SALE (qd.probe_files_demo_handoff on, the established probe switch), with the charge set to exactly the
--      fee: reveal.reconcile reaches the accountant and is closed with a matched verdict and evidence; the journal posts
--      Dr 1050 743.12 / Dr 6100 34.48 / Cr 4000 777.60 / Dr 6110 4.09 / Cr 2200 4.09, balanced, naming our invoice and
--      Stripe's, with no VAT line; sale.made reaches the CEO.
do $probe$
declare
  c_tx constant uuid := '29ac49f5-1f4e-4dc5-989a-479143f7ac8c';
  v_bad text[] := '{}'; v_t0 timestamptz := now(); v_rev timestamptz; v_paid timestamptz; n int; v_dl timestamptz;
  v_steps text[]; j record; v_dr numeric; v_cr numeric; v_memo text; v_ev jsonb; v_inv text; v_sweep jsonb;
begin
  select revealed_at into v_rev from public.transactions where id = c_tx;
  if v_rev is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: transaction 29ac49f5 is not in production'); end if;
  v_paid := v_rev - interval '3 minutes';

  -- ── A. the demo shadow ──────────────────────────────────────────────────────────────────────────
  update public.transactions set paid_at = v_paid, stripe_amount_received_fils = 81637, stripe_bt_amount_fils = 81637,
         stripe_bt_currency = 'aed', stripe_fee_fils = 3448 where id = c_tx;
  select refund_deadline into v_dl from public.transactions where id = c_tx;
  if v_dl is distinct from public.fn_reveal_refund_window_ends(v_paid) then
    v_bad := v_bad || ('the window does not count from paid_at: ' || coalesce(v_dl::text, 'null') || ' vs ' || public.fn_reveal_refund_window_ends(v_paid));
  end if;
  update public.transactions set revealed_at = null where id = c_tx;
  update public.transactions set revealed_at = v_rev where id = c_tx;     -- the sale, as the insert fires it

  select array_agg(distinct step || ':' || kind) into v_steps from public.demo_shadow_trace where transaction_id = c_tx and recorded_at >= v_t0;
  foreach v_memo in array array['handoff:reveal.paid', 'handoff:reveal.reconcile', 'reconcile:reveal.reconcile', 'journal:reveal_fee',
                                'window_clock:refund_window', 'invoice_number:our_invoice_no'] loop
    if not (v_memo = any(coalesce(v_steps, '{}'))) then v_bad := v_bad || ('shadow lacks ' || v_memo); end if;
  end loop;
  select payload into v_ev from public.demo_shadow_trace where transaction_id = c_tx and step = 'reconcile' and recorded_at >= v_t0 order by id desc limit 1;
  if not coalesce(v_ev->'findings' @> '[{"code":"charged_above_fee"}]'::jsonb, false) then v_bad := v_bad || ('the overcharge was not found: ' || coalesce(v_ev->>'findings', 'null')); end if;
  if v_ev->>'expected_fee_fils' is distinct from '77760' then v_bad := v_bad || ('expected fee is not 3% ex-VAT: ' || coalesce(v_ev->>'expected_fee_fils', 'null')); end if;
  select payload into v_ev from public.demo_shadow_trace where transaction_id = c_tx and step = 'journal' and recorded_at >= v_t0 order by id desc limit 1;
  if not coalesce(v_ev->'lines' @> '[{"account":"2300","credit":38.77}]'::jsonb, false) then v_bad := v_bad || ('shadow journal lacks Cr 2300 38.77: ' || coalesce(v_ev->>'lines', 'null')); end if;
  if coalesce(v_ev->>'memo', '') !~ 'ZZ-DEMO-INV-29AC49F5' then v_bad := v_bad || 'shadow journal does not name the demo invoice'::text; end if;
  select count(*) into n from public.agent_actions where created_at >= v_t0 and (target_id like '%' || c_tx::text || '%' or detail->>'transaction_id' = c_tx::text);
  if n <> 0 then v_bad := v_bad || ('a demo payment filed ' || n || ' real handoff(s)'); end if;
  select count(*) into n from public.gl_journal where source_ref = c_tx::text;
  if n <> 0 then v_bad := v_bad || ('a demo payment reached the real ledger: ' || n); end if;
  -- an hour later, unjudged (a fixture is never sent to a model): the CEO is told, in the shadow
  update public.accountant_reveal_payment_check set opened_at = now() - interval '2 hours' where transaction_id = c_tx;
  v_sweep := public.fn_accountant_payment_checks_sweep();
  select count(*) into n from public.demo_shadow_trace where transaction_id = c_tx and recorded_at >= v_t0 and step = 'escalation' and kind = 'payment.exception';
  if n <> 1 then v_bad := v_bad || ('the unjudged exception did not reach the CEO within the hour (shadow): ' || n); end if;
  select count(*) into n from public.accountant_reveal_payment_check where transaction_id = c_tx and resolved_at is not null;
  if n <> 0 then v_bad := v_bad || 'the exception closed itself'::text; end if;

  -- ── B. the real path on the same fixture, the charge exactly the fee ─────────────────────────────
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  delete from public.accountant_reveal_payment_check where transaction_id = c_tx;
  update public.transactions set processing_fee = 0, total_charged = reveal_fee, stripe_amount_received_fils = 77760, stripe_bt_amount_fils = 77760,
         stripe_invoice_total_fils = 77760 where id = c_tx;
  update public.transactions set revealed_at = null where id = c_tx;
  update public.transactions set revealed_at = v_rev where id = c_tx;

  select a.status, a.evidence into j from public.agent_actions a
   where a.kind = 'handoff' and a.agent = 'accountant' and a.target_id = 'reveal.reconcile:' || c_tx::text and a.created_at >= v_t0;
  if j.status is distinct from 'done' or j.evidence->>'verdict' is distinct from 'matched' then
    v_bad := v_bad || ('reveal.reconcile to the accountant is ' || coalesce(j.status, 'missing') || ' / ' || coalesce(j.evidence->>'verdict', 'no verdict'));
  end if;
  select sum(l.debit), sum(l.credit), max(g.memo) into v_dr, v_cr, v_memo
    from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id where g.source = 'reveal_fee' and g.source_ref = c_tx::text;
  if v_dr is null then v_bad := v_bad || 'no reveal_fee journal'::text;
  else
    if v_dr <> v_cr then v_bad := v_bad || ('journal not balanced: ' || v_dr || ' / ' || v_cr); end if;
    select count(*) into n from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
     where g.source = 'reveal_fee' and g.source_ref = c_tx::text
       and ((l.account_code = '1050' and l.debit = 743.12) or (l.account_code = '6100' and l.debit = 34.48)
         or (l.account_code = '4000' and l.credit = 777.60) or (l.account_code = '6110' and l.debit = 4.09) or (l.account_code = '2200' and l.credit = 4.09));
    if n <> 5 then v_bad := v_bad || ('journal lines are not 1050 743.12 / 6100 34.48 / 4000 777.60 / 6110 4.09 / 2200 4.09 (' || n || ' of 5)'); end if;
    select count(*) into n from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
     where g.source = 'reveal_fee' and g.source_ref = c_tx::text and l.account_code in ('2100', '1150');
    if n <> 0 then v_bad := v_bad || 'the reveal journal carries a VAT line'::text; end if;
    v_inv := (select invoice_no from public.reveal_invoices where transaction_id = c_tx);
    if v_memo !~ 'PQZAIUL8-0001' or position(coalesce(v_inv, '#') in v_memo) = 0 then v_bad := v_bad || ('the journal does not name both invoices: ' || v_memo); end if;
  end if;
  select count(*) into n from public.agent_actions a where a.kind = 'handoff' and a.agent = 'ceo' and a.detail->>'type' = 'sale.made'
     and a.detail->>'transaction_id' = c_tx::text and a.status = 'done' and a.created_at >= v_t0;
  if n <> 1 then v_bad := v_bad || ('sale.made to the CEO: ' || n); end if;
  select count(*) into n from public.accountant_reveal_payment_check where transaction_id = c_tx and verdict = 'matched' and decided_by = 'code';
  if n <> 1 then v_bad := v_bad || 'the check is not a code match'::text; end if;
  if public.fn_founder_brief_sale_lines(v_rev - interval '1 day', v_rev + interval '1 day') !~ 'Sales today' then v_bad := v_bad || 'the founder brief has no sales line'::text; end if;

  -- the torn-down rehearsal payments are labelled and resolved; no live item was touched
  select count(*) into n from public.accountant_reveal_reconcile_item where resolved_at is null and outcome = 'test_mode_not_demo' and demo and not livemode
     and not exists (select 1 from public.quotes q where q.id::text = quote_id);
  if n <> 0 then v_bad := v_bad || (n || ' torn-down rehearsal payment(s) still open')::text; end if;
  select count(*) into n from public.accountant_reveal_reconcile_item where outcome = 'rehearsal_torn_down' and livemode;
  if n <> 0 then v_bad := v_bad || (n || ' live payment(s) labelled a rehearsal')::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end,
    'shadow_steps', v_steps, 'sweep', v_sweep, 'journal_debits', v_dr, 'journal_credits', v_cr, 'memo', v_memo,
    'window_ends', v_dl);
end $probe$;
