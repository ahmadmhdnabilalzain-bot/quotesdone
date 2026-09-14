-- THE ACCOUNTANT'S DUTIES, EACH LOOP CLOSED, ON ZZ DEMO FIXTURES, INSIDE A TRANSACTION THAT ALWAYS
-- ROLLS BACK.
--
-- Run by scripts/checks/the_accountant_closes_every_loop_it_opens.test.mjs, after the accountant's routine
-- files in the SAME batch, so it proves the files as written whether or not they are applied yet. Ends in
-- raise exception 'CHK<<...>>' on success and 'ZZFAIL: ...' on the first failed assertion; either way
-- nothing it wrote survives.
--
-- For every duty that raises findings it proves the whole loop: the duty detects, the IT loop hands the
-- finding to its owning seat, the fix is made, the duty re-checks and closes the finding, and only then
-- does fn_it_loop_reverify close the handoff. The reports-to-CEO duties prove the CEO's receipt and the
-- accountant's completion after it.
--
-- IT CANNOT REACH A PERSON. Every customer and supplier is ZZ DEMO at @example.invalid; Stripe objects are
-- test-mode shapes; app.qd_stub_founder_notify stops customer_support calling fn_notify_founder; the last
-- assertion proves no row queued in this batch is addressed to anyone real; and the rollback means no
-- queued notification is ever committed for send_outbox to see.

create function pg_temp.zz_assert(p_cond boolean, p_msg text) returns void language plpgsql as $f$
begin if not coalesce(p_cond, false) then raise exception 'ZZFAIL: %', p_msg; end if; end $f$;

create function pg_temp.zz_case(p_tag text, p_quote numeric, p_fee numeric, p_total numeric) returns uuid language plpgsql as $f$
declare c uuid; l bigint; i uuid; q uuid; t uuid;
begin
  -- is_demo is a GENERATED column on both tables: the ZZ DEMO name and the @example.invalid address set it.
  insert into public.customers (full_name, email) values ('ZZ DEMO Customer ' || p_tag, 'zz-demo-cust-' || p_tag || '@example.invalid') returning id into c;
  insert into public.leads (company_name, email, claimed_by)
  values ('ZZ DEMO Supplier ' || p_tag, 'zz-demo-sup-' || p_tag || '@example.invalid', 'zz-demo-sup-' || p_tag || '@example.invalid')
  returning id into l;
  insert into public.inquiries (customer_id, summary) values (c, 'ZZ DEMO request ' || p_tag) returning id into i;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount) values (i, l, p_quote) returning id into q;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, app_fee, total_charged,
                                   processing_fee, customer_price, paid_by, payment_ref, fee_status, revealed_at, refund_deadline)
  values (q, i, l, c, p_quote, p_fee, p_fee, p_total, p_total - p_fee, p_quote, 'customer', 'pi_zz_demo_' || p_tag, 'paid', now(), now() + interval '2 days')
  returning id into t;
  return t;
end $f$;

create function pg_temp.zz_open(p_key text) returns boolean language sql as $f$
  select exists (select 1 from public.it_engineer_finding where issue_key = p_key and closed_at is null)
$f$;
create function pg_temp.zz_handoff(p_key text) returns public.agent_actions language sql as $f$
  select a.* from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.detail->>'issue_key' = p_key order by a.id desc limit 1
$f$;
-- Opens the IT loop for the finding (fn_it_loop_tick), asserts a handoff reached the owner, and returns it.
create function pg_temp.zz_loop_opens(p_key text, p_owner text) returns bigint language plpgsql as $f$
declare h public.agent_actions;
begin
  update public.it_engineer_finding set started_at = now() - interval '7 hours' where issue_key = p_key and closed_at is null
     and blast = 'internal';                                   -- internal findings are quiet for six hours by design
  perform public.fn_it_loop_tick();
  h := pg_temp.zz_handoff(p_key);
  perform pg_temp.zz_assert(h.id is not null, 'no it.finding handoff opened for ' || p_key);
  perform pg_temp.zz_assert(h.agent = p_owner, p_key || ' was handed to ' || coalesce(h.agent, '?') || ', not ' || p_owner);
  return h.id;
end $f$;
-- After the fix: the finding is closed by the duty, and the IT engineer closes the handoff.
create function pg_temp.zz_loop_closes(p_key text, p_handoff bigint) returns void language plpgsql as $f$
declare s text;
begin
  perform pg_temp.zz_assert(not pg_temp.zz_open(p_key), p_key || ' is still open after the fix and the re-check');
  perform public.fn_it_loop_reverify();
  select status into s from public.agent_actions where id = p_handoff;
  perform pg_temp.zz_assert(s = 'done', 'handoff ' || p_handoff || ' for ' || p_key || ' reads ' || coalesce(s, '?') || ' after re-verification');
end $f$;

do $zz$
declare
  r jsonb := '{}'::jsonb; v jsonb; h bigint; h2 bigint; t uuid; t2 uuid; t3 uuid; l bigint; d bigint; v_m date; v_n bigint;
  v_start bigint := (select coalesce(max(id), 0) from public.notifications);
begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);

  -- ── 1. BANK: a paid test-mode payout the ZZ DEMO statement does not show, then does ──────────────
  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines) values ('zz_probe_stmt', 'zz_demo', date_trunc('month', current_date), 'parsed', 1);
  perform public.fn_accountant_bank_statement_ingest('zz_demo', 'zz_probe_stmt', null,
    jsonb_build_array(jsonb_build_object('value_date', current_date, 'description', 'ZZ DEMO ACCOUNT MAINTENANCE CHARGE', 'amount_aed', -200)));
  perform public.fn_accountant_payouts_record(false, jsonb_build_array(jsonb_build_object('id', 'po_zz_probe_1', 'amount', 25000,
    'currency', 'aed', 'status', 'paid', 'arrival_date', extract(epoch from (current_date - 10)::timestamp at time zone 'Asia/Dubai')::bigint,
    'created', extract(epoch from now())::bigint, 'automatic', true, 'txn_count', 1, 'txn_net', 25000)));
  perform public.fn_accountant_bank_reconcile();
  perform pg_temp.zz_assert(pg_temp.zz_open('acct:bank:missing:po_zz_probe_1'), 'bank: the missing payout raised no finding');
  h := pg_temp.zz_loop_opens('acct:bank:missing:po_zz_probe_1', 'accountant');
  perform public.fn_accountant_bank_statement_ingest('zz_demo', 'zz_probe_stmt_2', null,
    jsonb_build_array(jsonb_build_object('value_date', current_date - 9, 'description', 'ZZ DEMO STRIPE PAYOUT', 'amount_aed', 250)));
  v := public.fn_accountant_bank_reconcile();
  perform pg_temp.zz_assert((select bank_line_id is not null from public.stripe_payout where id = 'po_zz_probe_1'), 'bank: the payout did not match the new line');
  perform pg_temp.zz_loop_closes('acct:bank:missing:po_zz_probe_1', h);
  r := r || jsonb_build_object('1_bank', jsonb_build_object('finding', 'acct:bank:missing:po_zz_probe_1', 'handoff', h, 'matched', true, 'closed', true));

  -- ── 11. COSTS: Stripe's own fee and the bank charge, drafts only on demo and under the hold ───────
  v := public.fn_accountant_book_stripe_fees(false, jsonb_build_array(jsonb_build_object('id', 'txn_zz_probe_fee', 'type', 'stripe_fee',
    'amount', -525, 'currency', 'aed', 'created', extract(epoch from now())::bigint, 'description', 'ZZ DEMO Billing - Invoicing')));
  perform pg_temp.zz_assert((v->>'drafted')::int = 1 and (v->>'posted')::int = 0, 'costs: the test-mode Stripe fee was not drafted: ' || v::text);
  v := public.fn_accountant_book_bank_charges();
  perform pg_temp.zz_assert(exists (select 1 from public.gl_journal where source = 'bank_charge' and status = 'draft' and memo like 'ZZ DEMO%'),
    'costs: the ZZ DEMO bank charge was not prepared as a draft');
  perform pg_temp.zz_assert(not exists (select 1 from public.gl_journal where source in ('bank_charge', 'stripe_fee_bt_test') and status = 'posted'),
    'costs: a bank or test-mode entry was POSTED');
  r := r || jsonb_build_object('11_costs', jsonb_build_object('stripe_fee_drafted', 1, 'bank_charge_drafted', true, 'posted', 0));

  -- ── 2. COLLECTIONS: an overdue supplier charge, held until the legal timeline is confirmed ────────
  t := pg_temp.zz_case('acct1', 3433.33, 103.00, 108.82);
  select supplier_id into l from public.transactions where id = t;
  insert into public.supplier_dues (transaction_id, supplier_id, quote_id, amount_due, admin_fee, interest_amount, total_claim, currency,
                                    reveal_date, due_date, status)
  select t, l, quote_id, 108.82, 250, 0, 358.82, 'AED', current_date - 40, current_date - 35, 'due' from public.transactions where id = t
  returning id into d;
  perform public.fn_accountant_collections_tick();
  perform pg_temp.zz_assert(pg_temp.zz_open('acct:collections:held_basis:' || d), 'collections: an unconfirmed timeline did not hold the notices');
  perform pg_temp.zz_assert(pg_temp.zz_open('acct:collections:overdue:' || d), 'collections: 35 days overdue raised no CEO finding');
  h := pg_temp.zz_loop_opens('acct:collections:overdue:' || d, 'ceo');
  update public.decision_policy set value = '{"confirmed": true, "source": "ZZ DEMO probe", "articles": ["zz"]}'::jsonb where key = 'supplier_charge_recovery_basis';
  insert into public.decision_policy (key, value, description) values
    ('supplier_charge_reminder_template', '{"subject_en":"ZZ DEMO reminder {{reminder_no}} on charge {{due_id}}","body_en":"ZZ DEMO {{company}} owes AED {{total_aed}}, {{days_overdue}} days after {{due_date}}.","subject_ar":"ZZ DEMO","body_ar":"ZZ DEMO {{total_aed}}"}'::jsonb, 'ZZ DEMO probe'),
    ('supplier_charge_final_demand_template', '{"subject_en":"ZZ DEMO final demand on charge {{due_id}}","body_en":"ZZ DEMO pay AED {{total_aed}} by {{pay_by}}.","subject_ar":"ZZ DEMO","body_ar":"ZZ DEMO {{pay_by}}"}'::jsonb, 'ZZ DEMO probe')
  on conflict (key) do update set value = excluded.value;
  perform public.fn_accountant_collections_tick();
  perform pg_temp.zz_assert(exists (select 1 from public.notifications n where n.id > v_start and n.type = 'nonresponse_charge_reminder'
    and n.to_email = 'zz-demo-sup-acct1@example.invalid'), 'collections: the reminder never reached the outbox through the sales engineer and support');
  perform pg_temp.zz_assert(exists (select 1 from public.notifications n where n.id > v_start and n.type = 'nonresponse_final_demand'
    and n.to_email = 'zz-demo-sup-acct1@example.invalid'), 'collections: the final demand never reached the outbox');
  update public.supplier_dues set legal_escalated_at = now() - interval '20 days' where id = d;
  perform public.fn_accountant_collections_tick();
  perform pg_temp.zz_assert(pg_temp.zz_open('acct:collections:filing:' || d), 'collections: an expired final demand did not make the filing pack due');
  h2 := pg_temp.zz_loop_opens('acct:collections:filing:' || d, 'ceo');
  v := public.fn_accountant_record_filing_outcome(d, 'paid_after_demand', 'ZZ DEMO');
  perform public.fn_accountant_collections_tick();
  perform pg_temp.zz_loop_closes('acct:collections:overdue:' || d, h);
  perform pg_temp.zz_loop_closes('acct:collections:filing:' || d, h2);
  r := r || jsonb_build_object('2_collections', jsonb_build_object('due', d, 'overdue_handoff', h, 'filing_handoff', h2,
    'reminder_and_demand_queued', true, 'closed_by', 'filing outcome recorded'));

  -- ── 3. SUBSCRIPTIONS: the 1,001st supplier unpaid, dunned, escalated, then paid and reminded ───────
  -- leads_approved_implies_verified: an approved supplier is a verified one.
  insert into public.leads (company_name, email, claimed_by, claimed, verified, approval_status, registration_submitted_at)
  values ('ZZ DEMO Supplier 1001', 'zz-demo-sup-1001@example.invalid', 'zz-demo-sup-1001@example.invalid', true, true, 'approved', now() - interval '40 days')
  returning id into l;
  update public.leads set founding_rank = 100001, subscription_exempt = false, subscription_paid_until = null where id = l;
  perform public.fn_accountant_subscription_tick();
  perform pg_temp.zz_assert(pg_temp.zz_open('acct:subscriptions:unpaid:' || l), 'subscriptions: an unpaid 1,001st supplier raised no finding');
  perform pg_temp.zz_assert(exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer'
    and detail->>'notice' = 'subscription_dunning' and (detail->>'supplier_id')::bigint = l), 'subscriptions: no dunning notice went to the sales engineer');
  h := pg_temp.zz_loop_opens('acct:subscriptions:unpaid:' || l, 'sales_engineer');
  update public.leads set subscription_paid_until = current_date + 5 where id = l;
  perform public.fn_accountant_subscription_tick();
  perform pg_temp.zz_assert(exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer'
    and detail->>'notice' = 'subscription_renewal' and (detail->>'supplier_id')::bigint = l), 'subscriptions: no renewal reminder before paid_until ran out');
  perform pg_temp.zz_loop_closes('acct:subscriptions:unpaid:' || l, h);
  r := r || jsonb_build_object('3_subscriptions', jsonb_build_object('supplier', l, 'handoff', h, 'dunning', true, 'renewal_reminder', true));

  -- ── 4. VAT: turnover at 85% of the threshold warns the CEO, asks the founder, and the CEO signs ────
  perform public.fn_gl_entry(current_date, 'ZZ DEMO VAT probe revenue', 'zz_demo', 'vat_probe',
    jsonb_build_array(jsonb_build_object('account', '1050', 'debit', 318750), jsonb_build_object('account', '4000', 'credit', 318750)), 'zz_demo');
  v := public.fn_accountant_vat_threshold_check(true);
  perform pg_temp.zz_assert((v->>'fraction_reached')::numeric = 0.8, 'vat: 85% did not read as the 0.8 fraction: ' || coalesce(v->>'fraction_reached', 'null'));
  perform pg_temp.zz_assert(exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'customer_support'
    and target_id = 'delivery.request:vat_decision:0.8'), 'vat: the founder''s decision request was not handed to customer_support');
  perform public.fn_ceo_accountant_reports_sweep(); perform public.fn_accountant_reports_complete();
  perform pg_temp.zz_assert((select status from public.support_ceo_report where idempotency_key = 'vat_threshold:0.8:' || to_char(current_date, 'YYYY-MM')) = 'completed',
    'vat: the CEO report was not acknowledged and completed');
  r := r || jsonb_build_object('4_vat', jsonb_build_object('fraction', 0.8, 'founder_asked', true, 'ceo_signed', true));

  -- ── 6. EXPENSES: a booked receipt with no document behind it ─────────────────────────────────────
  insert into public.expense_entries (vendor, category, amount, currency, charged_on, source, note)
  values ('ZZ DEMO Vendor', 'Usage', 10, 'AED', current_date, 'receipt', 'ZZ DEMO probe') returning id into v_n;
  perform public.fn_accountant_expense_duty();
  perform pg_temp.zz_assert(pg_temp.zz_open('acct:expenses:no_document'), 'expenses: a receipt with no document raised no finding');
  h := pg_temp.zz_loop_opens('acct:expenses:no_document', 'accountant');
  update public.expense_entries set doc_path = 'zz/demo.pdf', doc_kind = 'vendor_document' where id = v_n;
  perform public.fn_accountant_expense_duty();
  perform pg_temp.zz_loop_closes('acct:expenses:no_document', h);
  r := r || jsonb_build_object('6_expenses', jsonb_build_object('entry', v_n, 'handoff', h, 'closed', true));

  -- ── 7. DISPUTES: a test-mode chargeback on a ZZ DEMO payment, 20 hours before Stripe's deadline ────
  t2 := pg_temp.zz_case('acct2', 3433.33, 103.00, 108.82);
  v := public.fn_accountant_dispute_record(jsonb_build_object('id', 'dp_zz_probe_other', 'amount', 100, 'currency', 'aed',
    'payment_intent', 'pi_not_ours', 'status', 'needs_response'), false);
  perform pg_temp.zz_assert(v ? 'ignored', 'disputes: a test-mode dispute on a non-demo payment was recorded');
  perform public.fn_accountant_dispute_record(jsonb_build_object('id', 'dp_zz_probe_1', 'amount', 10882, 'currency', 'aed',
    'payment_intent', 'pi_zz_demo_acct2', 'charge', 'ch_zz', 'status', 'needs_response', 'reason', 'fraudulent',
    'evidence_details', jsonb_build_object('due_by', extract(epoch from now() + interval '20 hours')::bigint, 'has_evidence', false)), false);
  v := public.fn_accountant_dispute_evidence('dp_zz_probe_1');
  perform pg_temp.zz_assert((v->>'ok')::boolean and v#>>'{fields,customer_email_address}' = 'zz-demo-cust-acct2@example.invalid',
    'disputes: the evidence was not assembled from the records: ' || v::text);
  perform public.fn_accountant_disputes_tick();
  perform pg_temp.zz_assert(pg_temp.zz_open('acct:disputes:dp_zz_probe_1'), 'disputes: an unanswered dispute inside 24h raised no finding');
  perform pg_temp.zz_assert(exists (select 1 from public.support_ceo_report where idempotency_key = 'dispute:dp_zz_probe_1:t24'), 'disputes: no T-24h alert to the CEO');
  h := pg_temp.zz_loop_opens('acct:disputes:dp_zz_probe_1', 'accountant');
  perform public.fn_accountant_dispute_submitted('dp_zz_probe_1', true, '{"status": "under_review"}'::jsonb);
  perform public.fn_accountant_disputes_tick();
  perform pg_temp.zz_loop_closes('acct:disputes:dp_zz_probe_1', h);
  r := r || jsonb_build_object('7_disputes', jsonb_build_object('dispute', 'dp_zz_probe_1', 'handoff', h, 'ceo_t24', true, 'closed_by', 'evidence submitted'));

  -- ── 9. RESERVE: a reveal inside its window is held, not earned ───────────────────────────────────
  v := public.fn_accountant_refund_reserve();
  perform pg_temp.zz_assert((v->>'demo_held_aed')::numeric >= 108.82 * 2, 'reserve: the ZZ DEMO reveals in their window are not held: ' || (v->>'demo_held_aed'));
  r := r || jsonb_build_object('9_reserve', jsonb_build_object('demo_held_aed', v->>'demo_held_aed'));

  -- ── 10. CHARGE AUDIT: AED 0.05 more than the formula, then resolved ─────────────────────────────
  t3 := pg_temp.zz_case('acct3', 3433.33, 103.00, 108.82);
  perform pg_temp.zz_assert(exists (select 1 from public.fn_accountant_charge_audit_candidates(500) c where c.transaction_id = t3),
    'charge audit: the reveal is not a candidate');
  v := public.fn_accountant_charge_audit_record(jsonb_build_array(jsonb_build_object('transaction_id', t3, 'livemode', false,
    'basis', 'international', 'quote_amount', 3433.33, 'rate', 0.03, 'expected_total', 108.82, 'expected_processing', 5.82,
    'actual_total', 108.87, 'actual_fee_fils', 540, 'shortfall_aed', 0, 'evidence', '{}'::jsonb)));
  perform pg_temp.zz_assert(pg_temp.zz_open('acct:charge_audit:charge:' || t3), 'charge audit: a 0.05 overcharge raised no finding');
  h := pg_temp.zz_loop_opens('acct:charge_audit:charge:' || t3, 'accountant');
  perform public.fn_accountant_charge_audit_resolve(t3, 'ZZ DEMO: AED 0.05 refunded to the customer');
  perform public.fn_accountant_charge_audit_record('[]'::jsonb);
  perform pg_temp.zz_loop_closes('acct:charge_audit:charge:' || t3, h);
  r := r || jsonb_build_object('10_charge_audit', jsonb_build_object('transaction', t3, 'handoff', h, 'closed_by', 'resolution recorded'));

  -- ── 8. CLOSE: last month closed, filed, signed for by the CEO, completed ─────────────────────────
  v_m := (date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month')::date;
  delete from public.accountant_month_close where month = v_m;
  v := public.fn_accountant_month_close(v_m);
  perform pg_temp.zz_assert(exists (select 1 from public.accountant_month_close where month = v_m and ceo_report_id is not null), 'close: no close row with its CEO report');
  v := public.fn_accountant_month_close_document(v_m);
  perform pg_temp.zz_assert(jsonb_array_length(v->'blocks') > 5 and position('profit_and_loss,net_result' in v->>'csv') > 0, 'close: the document did not build');
  perform public.fn_ceo_accountant_reports_sweep(); perform public.fn_accountant_reports_complete();
  perform pg_temp.zz_assert((select r2.status from public.support_ceo_report r2 join public.accountant_month_close c on c.ceo_report_id = r2.id
                              where c.month = v_m) = 'completed', 'close: the CEO did not sign for the close, or the accountant did not complete it');
  r := r || jsonb_build_object('8_close', jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'ceo_signed', true));

  -- ── THE HOUR, END TO END ─────────────────────────────────────────────────────────────────────────
  v := public.fn_accountant_duties('{"stripe": {"live": {"basis": "not_configured"}, "test": {"basis": "not_configured"}}, "charge_audit": null}'::jsonb);
  perform pg_temp.zz_assert((v->>'ok')::boolean, 'duties: a stage failed: ' || (v->'errors')::text);
  r := r || jsonb_build_object('duties_hour', 'ok');

  -- ── NOTHING IN THIS BATCH WAS ADDRESSED TO A REAL PERSON ─────────────────────────────────────────
  perform pg_temp.zz_assert(not exists (select 1 from public.notifications n where n.id > v_start
    and coalesce(n.to_email, '') not like '%@example.invalid'), 'a queued notification in this batch is addressed outside @example.invalid');

  raise exception 'CHK<<%>>', r::text;
end
$zz$;
