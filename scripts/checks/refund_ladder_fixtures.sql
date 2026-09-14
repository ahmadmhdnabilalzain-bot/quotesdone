-- THE REFUND LADDER, END TO END, ON ZZ DEMO FIXTURES, INSIDE A TRANSACTION THAT ALWAYS ROLLS BACK.
--
-- Run by scripts/checks/payments_are_the_accountant.test.mjs AFTER the routine file
-- (scripts/sql/payments_are_the_accountant_and_the_seats_close_every_refund_together.sql)
-- in the SAME statement batch, so it proves the file as written whether or not they are applied yet.
-- It ends in raise exception 'CHK<<...>>' on success and 'ZZFAIL: ...' on the first failed assertion;
-- either way nothing it wrote survives.
--
-- IT CANNOT REACH A PERSON. Every customer and supplier is ZZ DEMO with an @example.invalid address and
-- no WhatsApp opt-in; the one supplier WhatsApp number (+999000555) is outside every national plan and
-- is used only as the FROM of a stubbed inbound message; app.qd_stub_founder_notify makes customer_support
-- record the founder summary instead of calling fn_notify_founder; and the rollback means no queued
-- notification is ever committed for send_outbox to see. Stripe is represented by the shapes its webhook
-- hands fn_refund_settle -- no Stripe call is made (there is no test-mode secret key in app_secrets).

create function pg_temp.zz_assert(p_cond boolean, p_msg text) returns void language plpgsql as $f$
begin if not coalesce(p_cond, false) then raise exception 'ZZFAIL: %', p_msg; end if; end $f$;

create function pg_temp.zz_case(p_tag text, p_days int, p_total numeric, p_fee numeric, p_whatsapp text default null)
returns uuid language plpgsql as $f$
declare c uuid; l bigint; i uuid; q uuid; t uuid;
begin
  insert into public.customers (full_name, email) values ('ZZ DEMO Customer ' || p_tag, 'zz-demo-cust-' || p_tag || '@example.invalid') returning id into c;
  insert into public.leads (company_name, email, claimed_by, whatsapp)
  values ('ZZ DEMO Supplier ' || p_tag, 'zz-demo-sup-' || p_tag || '@example.invalid', 'zz-demo-sup-' || p_tag || '@example.invalid', p_whatsapp)
  returning id into l;
  insert into public.inquiries (customer_id, summary) values (c, 'ZZ DEMO request ' || p_tag) returning id into i;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount) values (i, l, 3433.33) returning id into q;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, app_fee, total_charged,
                                   processing_fee, customer_price, paid_by, payment_ref, fee_status, revealed_at)
  values (q, i, l, c, 3433.33, p_fee, p_fee, p_total, nullif(p_total - p_fee, 0), 3433.33, 'customer', 'pi_zz_demo_' || p_tag, 'paid',
          now() - make_interval(days => p_days))
  returning id into t;
  return t;
end $f$;

create function pg_temp.zz_h(p_target text) returns text language sql as $f$
  select status from public.agent_actions where kind = 'handoff' and target_id = p_target order by id desc limit 1
$f$;

create function pg_temp.zz_req(p_tx uuid, p_step text) returns bigint language sql as $f$
  select id from public.agent_actions
   where kind = 'handoff' and agent = 'customer_support' and detail->>'transaction_id' = p_tx::text and detail->>'step' = p_step
   order by id desc limit 1
$f$;

-- delivery stubbed: the outbox row is marked sent as send_outbox would, and the watch window closed
create function pg_temp.zz_send(p_req bigint) returns void language plpgsql as $f$
begin
  update public.notifications n set status = 'sent', sent_at = now(), provider_message_id = 'zz-stub-' || n.id
   where n.id = (select coalesce((a.detail->>'retry_notification_id')::bigint, (a.evidence->>'notification_id')::bigint)
                   from public.agent_actions a where a.id = p_req);
  update public.agent_actions set detail = detail || jsonb_build_object('watch_until', now() - interval '1 minute') where id = p_req;
end $f$;

create function pg_temp.zz_fail(p_req bigint) returns void language plpgsql as $f$
begin
  update public.notifications n set status = 'failed', last_error = 'zz stub: bounced'
   where n.id = (select coalesce((a.detail->>'retry_notification_id')::bigint, (a.evidence->>'notification_id')::bigint)
                   from public.agent_actions a where a.id = p_req);
end $f$;

create function pg_temp.zz_evidence(p_tx uuid, p_step text) returns void language sql as $f$
  insert into public.refund_ladder_evidence (transaction_id, step, result, delivered, evidence)
  values (p_tx, p_step, 'no_response_confirmation', true, '{"zz":"inner loop proven in scenario 1; fast path"}'::jsonb)
$f$;

create function pg_temp.zz_approved(p_tag text) returns uuid language plpgsql as $f$
declare t uuid; rf bigint; v jsonb;
begin
  t := pg_temp.zz_case(p_tag, 10, 103.00, 100.00);
  update public.transactions set customer_notified_at = revealed_at + interval '1 day' where id = t;
  perform pg_temp.zz_evidence(t, 'chase'); perform pg_temp.zz_evidence(t, 'final_call');
  rf := (public.fn_refund_open_from_customer(t, 'customer')->>'refund_id')::bigint;
  v := public.fn_ceo_refund_review(rf, 'zz');
  perform pg_temp.zz_assert(v->>'outcome' = 'approved', p_tag || ': the CEO did not approve a clean case ' || v::text);
  return t;
end $f$;

create function pg_temp.zz_why(p_tx uuid) returns text language sql as $f$
  select coalesce((select string_agg('incident #' || id || ' ' || status || ' kinds=' || kinds::text || ' fixes=' || fixes::text, ' | ') from public.refund_incident where transaction_id = p_tx), 'no incident')
      || ' || now failing: ' || coalesce((select string_agg((f->>'item') || ' [' || coalesce(f->>'kind', '') || '] ' || coalesce(f->>'reason', '') || ' ' || coalesce((f->'evidence')::text, ''), ' ; ')
                                         from jsonb_array_elements(public.fn_ceo_refund_checklist(p_tx, 'verify', false)->'failed') f), 'nothing')
      || ' || breaker=' || public.fn_refunds_paused()::text
      || ' || handoffs not done: ' || coalesce((select string_agg(target_id || '=' || status || coalesce(' ERR ' || (detail->>'error'), '') || coalesce(' AWAIT ' || (detail->>'awaiting'), ''), ' ; ') from public.agent_actions where kind = 'handoff' and status <> 'done' and (detail->>'transaction_id' = p_tx::text or target_id like '%' || p_tx::text || '%')), 'none')
$f$;

do $zz$
declare
  res jsonb := '{}'::jsonb; v jsonb; r bigint; n int; k int; v_err text; nid bigint; inc bigint; fix bigint;
  tx1 uuid; tx2 uuid; tx3 uuid; tx4 uuid; tx5 uuid; t7 uuid; rf bigint; d1 public.supplier_dues; v_orig public.notifications;
begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);

  -- ── 1. THE HAPPY LADDER: reveal -> chase -> complaint -> final call -> CEO -> Stripe -> charge ──
  tx1 := pg_temp.zz_case('s1', 10, 103.00, 100.00);
  perform pg_temp.zz_assert(pg_temp.zz_h('reveal.paid:' || tx1) = 'done', 's1 reveal.paid handoff not done');
  perform pg_temp.zz_assert(pg_temp.zz_h('delivery.request:reveal_receipt:' || tx1) = 'done', 's1 support did not deliver the reveal receipt');
  perform pg_temp.zz_assert(exists (select 1 from public.company_event e where e.event_type = 'handoff.reveal.paid.done'
                                     and e.entity_id = (select id::text from public.agent_actions where target_id = 'reveal.paid:' || tx1)),
                            's1 the handoff is not in the event stream');
  update public.transactions set customer_notified_at = revealed_at + interval '1 day' where id = tx1;
  perform public.fn_sales_engineer_ladder_step(tx1, 'chase');
  r := pg_temp.zz_req(tx1, 'chase'); perform pg_temp.zz_send(r);
  v := public.fn_customer_support_delivery_watch(r);
  perform pg_temp.zz_assert(exists (select 1 from public.refund_ladder_evidence where transaction_id = tx1 and step = 'chase'
                                     and result = 'no_response_confirmation' and delivered), 's1 chase: no confirmation attached ' || v::text);
  v := public.fn_refund_open_from_customer(tx1, 'customer'); rf := (v->>'refund_id')::bigint;
  perform pg_temp.zz_assert(rf is not null, 's1 refund not opened ' || v::text);
  perform pg_temp.zz_assert(pg_temp.zz_h('refund.requested:' || rf) = 'done' and pg_temp.zz_h('refund.request_checked:' || rf) = 'done', 's1 refund request handoffs');
  perform pg_temp.zz_assert((select (evidence->>'money_ok')::boolean from public.agent_actions where target_id = 'refund.requested:' || rf),
                            's1 the accountant''s money check failed');
  perform public.fn_sales_engineer_ladder_step(tx1, 'final_call', rf);
  r := pg_temp.zz_req(tx1, 'final_call'); perform pg_temp.zz_send(r);
  perform public.fn_customer_support_delivery_watch(r);
  perform pg_temp.zz_assert((select refund_decision_id from public.refunds where id = rf) is not null,
    's1 the CEO did not approve: ' || coalesce((select failed::text from public.refund_ceo_review where refund_id = rf order by cycle desc limit 1), 'no review ran'));
  perform public.fn_refund_settle('re_zz_s1', 'succeeded', 10300, 'pi_zz_demo_s1');
  select * into d1 from public.supplier_dues where transaction_id = tx1 and coalesce(status, '') <> 'cancelled';
  perform pg_temp.zz_assert(d1.amount_due = 103.00 and d1.admin_fee = 250.00, 's1 charge figures ' || coalesce(d1.amount_due::text, 'no charge'));
  perform pg_temp.zz_assert(not exists (select 1 from public.refund_incident where transaction_id = tx1),
    's1 an incident opened on a clean refund: ' || coalesce((select evidence->>'failed' from public.refund_incident where transaction_id = tx1 limit 1), ''));
  perform pg_temp.zz_assert(not public.fn_refunds_paused(), 's1 the breaker is on');
  perform pg_temp.zz_assert(pg_temp.zz_h('delivery.request:refund_issued:' || tx1) = 'done'
                            and pg_temp.zz_h('delivery.request:nonresponse_charge:' || d1.id) = 'done', 's1 the two outcome messages');
  -- the arithmetic, the accrual, and idempotency
  v := public.fn_accountant_nonresponse_charge(tx1, d1.due_date + 30);
  perform pg_temp.zz_assert((v->>'interest_days')::int = 30 and (v->>'interest_aed')::numeric = 2.61 and (v->>'total_aed')::numeric = 355.61,
                            's1 interest after 30 days ' || v::text);
  v := public.fn_accountant_nonresponse_charge(tx1, d1.due_date - 1);
  perform pg_temp.zz_assert((v->>'interest_aed')::numeric = 0, 's1 interest before the due date');
  n := public.fn_supplier_dues_accrue_interest(d1.due_date + 30);
  k := public.fn_supplier_dues_accrue_interest(d1.due_date + 30);
  perform pg_temp.zz_assert(k = 0 and (select interest_amount from public.supplier_dues where id = d1.id) = 2.61, 's1 accrual is not idempotent ' || n || '/' || k);
  v := public.fn_accountant_raise_nonresponse_charge(tx1);
  perform pg_temp.zz_assert(not (v->>'created')::boolean and (v->>'due_id')::bigint = d1.id, 's1 the charge was raised twice');
  -- support is up to date: the customer's timeline carries the handoffs about them
  v := public.fn_contact_timeline('zz-demo-cust-s1@example.invalid', 200);
  perform pg_temp.zz_assert(coalesce((v->'counts'->>'handoff')::int, 0) >= 3, 's1 the case timeline does not show the handoffs: ' || coalesce(v->>'counts', 'null'));
  perform pg_temp.zz_assert(exists (select 1 from public.notifications where to_email = 'zz-demo-cust-s1@example.invalid'
                                     and requested_by = 'sales_engineer' and sender = 'customer_support'), 's1 a delivery does not name the seat that asked');
  res := res || jsonb_build_object('1_timeline_handoff_events', (v->'counts'->>'handoff')::int);
  res := res || jsonb_build_object('1_happy_ladder', 'approved, settled, charged AED 103 + 250, both told, no incident',
                                   '1_interest_30_days_aed', 2.61, '1_accrual_second_run_changed', k);

  -- ── 2. REJECT -> ACCOUNTANT FIXES -> RE-CHECK -> APPROVE ─────────────────────────────────────
  tx2 := pg_temp.zz_case('s2', 10, 103.00, 100.00);
  update public.transactions set customer_notified_at = revealed_at + interval '1 day' where id = tx2;
  perform pg_temp.zz_evidence(tx2, 'chase'); perform pg_temp.zz_evidence(tx2, 'final_call');
  rf := (public.fn_refund_open_from_customer(tx2, 'customer')->>'refund_id')::bigint;
  update public.transactions set total_charged = 105.00, processing_fee = 5.00 where id = tx2;   -- the processing part recorded late
  v := public.fn_ceo_refund_review(rf, 'zz');
  perform pg_temp.zz_assert((select array_agg(outcome order by cycle) from public.refund_ceo_review where refund_id = rf) = array['rejected', 'approved'],
    's2 loop ' || coalesce((select array_agg(outcome order by cycle)::text from public.refund_ceo_review where refund_id = rf), 'none') || ' ' || v::text);
  perform pg_temp.zz_assert((select amount_fils from public.refunds where id = rf) = 10500, 's2 the accountant did not fix the amount');
  perform pg_temp.zz_assert(exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'accountant'
                                     and detail->>'type' = 'refund.remediate' and detail->>'refund_id' = rf::text and status = 'done'), 's2 no accountant task');
  res := res || jsonb_build_object('2_accountant_fix', 'rejected (amount) -> accountant set AED 105 -> re-checked -> approved');

  -- ── 3. REJECT -> SALES ENGINEER RUNS THE INNER LOOP -> RE-CHECK -> APPROVE ───────────────────
  tx3 := pg_temp.zz_case('s3', 10, 103.00, 100.00);
  update public.transactions set customer_notified_at = revealed_at + interval '1 day' where id = tx3;
  perform pg_temp.zz_evidence(tx3, 'chase');
  rf := (public.fn_refund_open_from_customer(tx3, 'customer')->>'refund_id')::bigint;
  v := public.fn_ceo_refund_review(rf, 'zz');
  perform pg_temp.zz_assert(v->>'outcome' = 'rejected' and exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer'
                              and detail->>'type' = 'refund.remediate' and detail->>'refund_id' = rf::text and status = 'pending'), 's3 no sales engineer task ' || v::text);
  r := pg_temp.zz_req(tx3, 'final_call');
  perform pg_temp.zz_assert(r is not null, 's3 the sales engineer did not ask support for the final call');
  perform pg_temp.zz_send(r); perform public.fn_customer_support_delivery_watch(r);
  perform pg_temp.zz_assert((select array_agg(outcome order by cycle) from public.refund_ceo_review where refund_id = rf) = array['rejected', 'approved'],
    's3 loop ' || coalesce((select array_agg(outcome order by cycle)::text from public.refund_ceo_review where refund_id = rf), 'none'));
  res := res || jsonb_build_object('3_sales_engineer_fix', 'rejected (no final call) -> sales engineer -> support delivered and confirmed silence -> approved');

  -- ── 4. DELIVERY FAILS, SUPPORT RETRIES AND REPORTS, AMBIGUOUS -> REJECTED AGAIN -> ESCALATED ──
  tx4 := pg_temp.zz_case('s4', 10, 103.00, 100.00);
  update public.transactions set customer_notified_at = revealed_at + interval '1 day' where id = tx4;
  perform pg_temp.zz_evidence(tx4, 'chase');
  rf := (public.fn_refund_open_from_customer(tx4, 'customer')->>'refund_id')::bigint;
  v := public.fn_ceo_refund_review(rf, 'zz');
  for k in 1..3 loop
    r := pg_temp.zz_req(tx4, 'final_call');
    perform pg_temp.zz_fail(r); perform public.fn_customer_support_delivery_watch(r);
    perform pg_temp.zz_assert((select (detail->>'retries')::int from public.agent_actions where id = r) = 1, 's4 support did not retry a failed delivery (cycle ' || k || ')');
    perform pg_temp.zz_fail(r); perform public.fn_customer_support_delivery_watch(r);
    perform pg_temp.zz_assert(exists (select 1 from public.refund_ladder_evidence where request_handoff_id = r and not delivered),
                              's4 support did not report the failed delivery (cycle ' || k || ')');
  end loop;
  perform pg_temp.zz_assert((select array_agg(outcome order by cycle) from public.refund_ceo_review where refund_id = rf) = array['rejected', 'rejected', 'rejected', 'escalated'],
    's4 loop ' || coalesce((select array_agg(outcome order by cycle)::text from public.refund_ceo_review where refund_id = rf), 'none'));
  perform pg_temp.zz_assert(exists (select 1 from public.agent_actions where target_id = 'delivery.request:refund_loop_stuck:' || rf
                                     and status = 'done' and (evidence->>'stubbed')::boolean), 's4 the stuck loop did not reach the founder summary');
  perform pg_temp.zz_assert((select refund_decision_id from public.refunds where id = rf) is null, 's4 money was approved while the loop was open');
  -- the gates hold throughout
  begin
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', rf::text, 'approved', 'ceo', 103, 'ZZ DEMO forced approval');
    v_err := 'NOT REFUSED';
  exception when others then v_err := sqlerrm; end;
  perform pg_temp.zz_assert(v_err like 'the CEO may not approve this refund%', 's4 a forced ceo_approval was not refused: ' || v_err);
  perform pg_temp.zz_assert(public.fn_refund_decide(rf, true, 'ceo', 'zz')->>'error' = 'no_ceo_approval', 's4 fn_refund_decide approved without a CEO approval');
  begin
    insert into public.refund_case (transaction_id, state, eligibility, decision, decided_by, decided_at, decision_rationale, amount_aed, currency)
    values (tx4, 'ceo_authorized', 'supplier_nonresponse', 'approved', 'ceo', now(), 'ZZ DEMO forced', 103, 'AED');
    v_err := 'NOT REFUSED';
  exception when others then v_err := sqlerrm; end;
  perform pg_temp.zz_assert(v_err <> 'NOT REFUSED', 's4 a forced refund_case authorisation was not refused');
  res := res || jsonb_build_object('4_failed_delivery_and_escalation', 'retried once, reported delivered=false, rejected x3, escalated to the founder summary (stubbed); forced approvals refused');

  -- ── 5. THE SUPPLIER REPLIES ON WHATSAPP: PROOF -> THE NON-RESPONSE PATH STOPS ─────────────────
  tx5 := pg_temp.zz_case('s5', 10, 103.00, 100.00, '+999000555');
  update public.transactions set customer_notified_at = revealed_at + interval '1 day' where id = tx5;
  perform public.fn_sales_engineer_ladder_step(tx5, 'chase');
  r := pg_temp.zz_req(tx5, 'chase');
  update public.notifications set status = 'sent', sent_at = now() where id = (select (evidence->>'notification_id')::bigint from public.agent_actions where id = r);
  insert into public.wa_messages (wa_from, inbound, created_at) values ('+999000555', 'ZZ DEMO reply: we called the customer', now());
  perform public.fn_customer_support_delivery_watch(r);
  perform pg_temp.zz_assert(exists (select 1 from public.refund_ladder_evidence where transaction_id = tx5 and result = 'proof_of_response'
                                     and evidence->'reply'->>'channel' = 'whatsapp'), 's5 no WhatsApp proof attached');
  rf := (public.fn_refund_open_from_customer(tx5, 'customer')->>'refund_id')::bigint;
  v := public.fn_ceo_refund_review(rf, 'zz');
  perform pg_temp.zz_assert(v->>'outcome' = 'declined' and (select status from public.refunds where id = rf) = 'rejected', 's5 not declined ' || v::text);
  perform pg_temp.zz_assert(pg_temp.zz_h('delivery.request:refund_declined:' || tx5) = 'done', 's5 the customer was not told');
  res := res || jsonb_build_object('5_whatsapp_proof', 'proof attached, refund declined, customer told why');

  -- ── 6. MISMATCH: UNDER-REFUND -> TOP-UP -> CHARGE REISSUED -> RESUMED ─────────────────────────
  t7 := pg_temp.zz_approved('7a'); rf := (select id from public.refunds where transaction_id = t7 and requested_by = 'customer');
  update public.refunds set status = 'processing', stripe_refund_id = 're_zz_main_7a' where id = rf;
  insert into public.refunds (transaction_id, stripe_payment_intent, stripe_refund_id, amount_fils, amount_source, reason_code, reason_note, requested_by, status, decided_by, decided_at)
  values (t7, 'pi_zz_demo_7a', 're_zz_part_7a', 10000, 'webhook_event', 'other', 'ZZ DEMO partial refund reported by Stripe', 'stripe_webhook', 'succeeded', 'stripe_dashboard', now());
  update public.transactions set refund_status = 'succeeded', refund_amount_aed = 100, refund_confirmed_at = now() where id = t7;
  inc := (select id from public.refund_incident where transaction_id = t7 order by id desc limit 1);
  perform pg_temp.zz_assert(inc is not null and public.fn_refunds_paused() and (select 'under_refund' = any(kinds) from public.refund_incident where id = inc),
                            's6 under-refund did not pause and open an incident');
  fix := (select id from public.agent_actions where target_id = 'incident.fix:' || inc || ':refund_difference');
  perform pg_temp.zz_assert(pg_temp.zz_h('incident.fix:' || inc || ':refund_difference') = 'pending', 's6 no top-up task for the accountant');
  insert into public.refunds (transaction_id, stripe_payment_intent, stripe_refund_id, amount_fils, amount_source, reason_code, reason_note, requested_by, status, decided_by, decided_at)
  values (t7, 'pi_zz_demo_7a', 're_zz_topup_7a', 300, 'stripe_api', 'other', 'ZZ DEMO top-up by the accountant runtime', 'stripe_webhook', 'succeeded', 'stripe_dashboard', now());
  perform public.fn_seat_handoff_complete(fix, jsonb_build_object('stripe_refund_id', 're_zz_topup_7a', 'amount_fils', 300));
  perform pg_temp.zz_assert((select status from public.refund_incident where id = inc) = 'fixed' and not public.fn_refunds_paused(),
    's6 not resumed: ' || pg_temp.zz_why(t7));
  perform pg_temp.zz_assert((select amount_due from public.supplier_dues where transaction_id = t7 and status <> 'cancelled') = 103.00, 's6 the charge is not the exact amount refunded');
  res := res || jsonb_build_object('6_under_refund', 'paused, topped up AED 3, charge reissued at AED 103, resumed');

  -- ── 7. MISMATCH: STRIPE FAILED -> ONE RETRY -> STILL PENDING -> CUSTOMER TOLD IN PROGRESS -> SETTLES ──
  t7 := pg_temp.zz_approved('7b'); rf := (select id from public.refunds where transaction_id = t7 and requested_by = 'customer');
  update public.refunds set status = 'processing', stripe_refund_id = 're_zz_f1_7b' where id = rf;
  perform public.fn_refund_settle('re_zz_f1_7b', 'failed', null, 'pi_zz_demo_7b', null, 'card_declined');
  inc := (select id from public.refund_incident where transaction_id = t7 order by id desc limit 1);
  perform pg_temp.zz_assert(inc is not null and pg_temp.zz_h('incident.fix:' || inc || ':retry_refund') = 'pending', 's7 no retry task');
  update public.refunds set status = 'processing', stripe_refund_id = 're_zz_f2_7b', failure_reason = null where id = rf;
  perform public.fn_seat_handoff_complete((select id from public.agent_actions where target_id = 'incident.fix:' || inc || ':retry_refund'),
                                          jsonb_build_object('stripe_refund_id', 're_zz_f2_7b'));
  perform pg_temp.zz_assert((select status from public.refund_incident where id = inc) = 'paused' and public.fn_refunds_paused(), 's7 not paused after the retry: ' || pg_temp.zz_why(t7));
  perform pg_temp.zz_assert(pg_temp.zz_h('delivery.request:refund_in_progress:' || t7) = 'done', 's7 the customer was not told it is in progress');
  perform public.fn_refund_settle('re_zz_f2_7b', 'succeeded', 10300, 'pi_zz_demo_7b');
  perform pg_temp.zz_assert((select status from public.refund_incident where id = inc) = 'fixed' and not public.fn_refunds_paused()
                            and exists (select 1 from public.supplier_dues where transaction_id = t7 and amount_due = 103.00), 's7 did not resume after settling: ' || pg_temp.zz_why(t7));
  res := res || jsonb_build_object('7_stripe_failed', 'retried once, stayed paused, customer told in progress, resumed when Stripe settled');

  -- ── 8. MISMATCH: DUPLICATE REFUND -> STRIPE WILL NOT CANCEL -> BOOKED AS LOSS ─────────────────
  t7 := pg_temp.zz_approved('7c');
  perform public.fn_refund_settle('re_zz_d1_7c', 'succeeded', 10300, 'pi_zz_demo_7c');
  perform pg_temp.zz_assert(not exists (select 1 from public.refund_incident where transaction_id = t7), 's8 the first refund was not clean');
  insert into public.refunds (stripe_payment_intent, stripe_refund_id, amount_fils, amount_source, reason_code, reason_note, requested_by, status, decided_by, decided_at)
  values ('pi_zz_demo_7c', 're_zz_d2_7c', 10300, 'webhook_event', 'other', 'ZZ DEMO duplicate issued from the dashboard', 'stripe_webhook', 'succeeded', 'stripe_dashboard', now());
  inc := (select id from public.refund_incident where transaction_id = t7 order by id desc limit 1);
  perform pg_temp.zz_assert(inc is not null and pg_temp.zz_h('incident.fix:' || inc || ':cancel_duplicate') = 'pending', 's8 the duplicate did not open a cancel task');
  perform public.fn_accountant_incident_fix_failed((select id from public.agent_actions where target_id = 'incident.fix:' || inc || ':cancel_duplicate'),
                                                   'ZZ DEMO: Stripe cannot cancel a refund that has succeeded');
  perform pg_temp.zz_assert((select status from public.refund_incident where id = inc) = 'fixed'
                            and exists (select 1 from public.gl_journal where source = 'refund_over_loss' and source_ref = t7 || ':' || inc), 's8 the loss was not booked: ' || pg_temp.zz_why(t7));
  perform pg_temp.zz_assert((select amount_due from public.supplier_dues where transaction_id = t7 and status <> 'cancelled') = 103.00, 's8 the supplier was charged for the duplicate');
  res := res || jsonb_build_object('8_duplicate_refund', 'stopped, cancel refused by Stripe, AED 103 booked as company loss, supplier charge stays AED 103');

  -- ── 9. MISMATCH: WRONG CHARGE ALREADY SENT -> CANCEL, REISSUE, CORRECTION TO THE SAME RECIPIENTS ──
  t7 := pg_temp.zz_approved('7d');
  perform public.fn_refund_settle('re_zz_7d', 'succeeded', 10300, 'pi_zz_demo_7d');
  select * into d1 from public.supplier_dues where transaction_id = t7 and status <> 'cancelled';
  nid := (select (evidence->>'notification_id')::bigint from public.agent_actions where target_id = 'delivery.request:nonresponse_charge:' || d1.id);
  update public.notifications set status = 'sent', sent_at = now(), cc_emails = array['zz-demo-accounts-7d@example.invalid'] where id = nid;
  select * into v_orig from public.notifications where id = nid;
  update public.supplier_dues set admin_fee = 200 where id = d1.id;
  v := public.fn_ceo_refund_verify(t7);
  perform pg_temp.zz_assert((select admin_fee from public.supplier_dues where id = d1.id) = 250, 's9 not reissued: ' || pg_temp.zz_why(t7));
  perform pg_temp.zz_assert(exists (select 1 from public.notifications where type = 'nonresponse_charge_correction' and to_email = v_orig.to_email
                                     and 'zz-demo-accounts-7d@example.invalid' = any(cc_emails)), 's9 the correction did not go to whoever got the original');
  perform pg_temp.zz_assert((select status from public.refund_incident where transaction_id = t7 order by id desc limit 1) = 'fixed', 's9 not fixed: ' || pg_temp.zz_why(t7));
  res := res || jsonb_build_object('9_wrong_charge_sent', 'reissued in place at AED 250 admin, correction sent to the original To and Cc');

  -- ── 10. MISMATCH: MISSED HANDOFF -> RE-TRIGGERED -> RESUMED ──────────────────────────────────
  t7 := pg_temp.zz_approved('7e');
  update public.customers set email = null where id = (select customer_id from public.transactions where id = t7);
  perform public.fn_refund_settle('re_zz_7e', 'succeeded', 10300, 'pi_zz_demo_7e');
  inc := (select id from public.refund_incident where transaction_id = t7 order by id desc limit 1);
  perform pg_temp.zz_assert((select status from public.refund_incident where id = inc) = 'paused'
                            and (select 'missed_handoff' = any(kinds) from public.refund_incident where id = inc), 's10 the missed message did not pause');
  update public.customers set email = 'zz-demo-cust-7e@example.invalid' where id = (select customer_id from public.transactions where id = t7);
  v := public.fn_ceo_incident_advance(inc, 0);
  perform pg_temp.zz_assert(v->>'status' = 'fixed' and pg_temp.zz_h('delivery.request:refund_issued:' || t7) = 'done', 's10 not re-triggered ' || v::text);
  res := res || jsonb_build_object('10_missed_handoff', 'paused while the customer could not be reached, re-triggered, delivered, resumed');

  -- ── 11. MISMATCH: OVER-REFUND -> BOOKED AS LOSS, SUPPLIER CHARGED ONLY THE APPROVED AMOUNT ────
  t7 := pg_temp.zz_approved('7f');
  insert into public.refunds (transaction_id, stripe_payment_intent, stripe_refund_id, amount_fils, amount_source, reason_code, reason_note, requested_by, status, decided_by, decided_at)
  values (t7, 'pi_zz_demo_7f', 're_zz_o_7f', 11000, 'webhook_event', 'other', 'ZZ DEMO over-refund reported by Stripe', 'stripe_webhook', 'succeeded', 'stripe_dashboard', now());
  update public.transactions set refund_status = 'succeeded', refund_amount_aed = 110, refund_confirmed_at = now() where id = t7;
  inc := (select id from public.refund_incident where transaction_id = t7 order by id desc limit 1);
  perform pg_temp.zz_assert((select status from public.refund_incident where id = inc) = 'fixed'
                            and exists (select 1 from public.gl_journal where source = 'refund_over_loss' and source_ref = t7 || ':' || inc)
                            and (select amount_due from public.supplier_dues where transaction_id = t7 and status <> 'cancelled') = 103.00,
    's11 over-refund ' || coalesce((select status || ' ' || kinds::text from public.refund_incident where id = inc), 'no incident'));
  perform pg_temp.zz_assert(not public.fn_refunds_paused(), 's11 left paused');
  res := res || jsonb_build_object('11_over_refund', 'AED 7 booked as company loss, supplier charged the approved AED 103');

  res := res || jsonb_build_object('handoff_events_in_stream', (select count(*) from public.company_event where event_type like 'handoff.%' and occurred_at > now() - interval '1 hour'),
                                   'founder_summaries_stubbed', (select count(*) from public.agent_actions where kind = 'handoff' and agent = 'customer_support'
                                                                  and detail->>'recipient_role' = 'founder' and (evidence->>'stubbed')::boolean));
  raise exception 'CHK<<%>>', res::text;
end $zz$;
