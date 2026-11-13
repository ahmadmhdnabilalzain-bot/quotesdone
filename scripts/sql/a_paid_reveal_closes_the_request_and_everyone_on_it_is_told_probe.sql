-- PROBE: A PAID REVEAL RECORDS THE REQUEST'S OUTCOME, KEEPS ANOTHER REVEAL POSSIBLE WHILE THE QUOTATIONS ARE VALID, TAKES NO
-- NEW QUOTATION, TELLS EVERY OTHER SUPPLIER ONCE PER EVENT, ENDS ON THE REQUEST'S OWN DATE, AND A REFUND RE-OPENS IT.
-- Seat: sales_engineer. 13 Nov 2026 (revised after review "WORKFLOW W2 SALES 1"). Pure probe: no DDL, never applied. Run
-- after a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql (node scripts/ci/rehearse_sql.mjs <file> <probe>).
-- It always raises, so every row is rolled back. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   A. four quotations (one still in the 24-hour quality hold), the first paid: the receipt and the chosen supplier's notice
--      exist; status stays 'revealed', outcome and stage 'revealed'; reveal_open_until is the latest expiry of the remaining
--      live quotations (the held one included); the three others get one neutral notice each, the chosen none; acting again
--      changes nothing; a SECOND paid reveal tells nobody again; a new supplier's quotation is refused, an existing
--      supplier's second option is not; a withdrawal moves the date; the duty ends the period on the request's date only,
--      tells each remaining supplier once that it ended, and never says the customer went ahead with anyone;
--   B. one quotation, paid: the period ends at the payment, nobody else to tell, status still 'revealed';
--   D. a period that ended, then refund.paid: re-opened, the date in the future, the outcome cleared, each supplier told
--      "ended" now told once "open again"; the duty then leaves it open; a second refund hand-over tells nobody again;
--   E. a refund for a reveal with no recorded period (paid before this file) changes nothing;
--   Z. a zero-rated and an exempt quotation can be stored;
--   X. nothing to a real address; nothing in Arabic to a supplier.
do $probe$
declare
  fails text := ''; o jsonb := '{}'::jsonb; v jsonb; c uuid := gen_random_uuid(); s1 bigint; s2 bigint; s3 bigint; s4 bigint; s5 bigint;
  ia uuid := gen_random_uuid(); ib uuid := gen_random_uuid(); idq uuid := gen_random_uuid(); iz uuid := gen_random_uuid();
  qa1 uuid := gen_random_uuid(); qa2 uuid := gen_random_uuid(); qa3 uuid := gen_random_uuid(); qa4 uuid := gen_random_uuid();
  qb1 uuid := gen_random_uuid(); qd1 uuid := gen_random_uuid(); qd2 uuid := gen_random_uuid(); qd3 uuid := gen_random_uuid();
  icap uuid := gen_random_uuid(); qc1 uuid := gen_random_uuid(); qc2 uuid := gen_random_uuid(); tcap uuid; hb bigint;
  ta uuid; ta2 uuid; tb uuid; td uuid; h bigint; r public.inquiries; rr public.request_reveal_outcome; n int; u timestamptz;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  perform set_config('qd.duty_fixtures', 'on', true);
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Reveal Period Customer', 'zz-demo-revperiod@example.invalid', '+971500000187', true, true, 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Chosen Supplier', 'zz-demo-rp-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Second Supplier', 'zz-demo-rp-s2@example.invalid') returning id into s2;
  insert into public.leads (company_name, email) values ('ZZ DEMO Third Supplier', 'zz-demo-rp-s3@example.invalid') returning id into s3;
  insert into public.leads (company_name, email) values ('ZZ DEMO Held Supplier', 'zz-demo-rp-s4@example.invalid') returning id into s4;
  insert into public.leads (company_name, email) values ('ZZ DEMO Late Supplier', 'zz-demo-rp-s5@example.invalid') returning id into s5;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  select x, c, 'plumbing', 'Dubai', 'ZZ DEMO reveal period probe', 'quoted', 'en', now() - interval '10 days', 'single' from unnest(array[ia, ib, idq, iz, icap]) x;
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q::text, 1, 'ZZ DEMO heater and labour', 'ZZ DEMO Brand', 'ZZ-1', '80 litre electric', 1, 'lot', 4000, 500
    from unnest(array[qa1, qa2, qa3, qa4, qb1, qd1, qd2, qd3, qc1, qc2]) q;
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, price_ex_vat, vat_treatment, status, created_at, expires_at, warranty, lead_time, payment_terms, exclusions, validity)
  select q, i, s, 4500, 4500, 'exclusive', 'submitted', now() - interval '5 days', now() + make_interval(days => dd), '1 year', '1 week', '50% advance', 'civil works', '30 days'
    from (values (qa1, ia, s1, 25), (qa2, ia, s2, 5), (qa3, ia, s3, 12), (qa4, ia, s4, 20), (qb1, ib, s1, 25),
                 (qd1, idq, s1, 25), (qd2, idq, s2, 25), (qd3, idq, s3, 25), (qc1, icap, s1, 40), (qc2, icap, s2, 40)) x(q, i, s, dd);
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (qa1, qa2, qa3, qb1, qd1, qd2, qd3, qc1, qc2);
  update public.quotes set status = 'submitted' where id in (qa1, qa2, qa3, qb1, qd1, qd2, qd3, qc1, qc2);
  -- qa4 stays in the 24-hour quality hold: a 'draft' with an unreleased hold, which counts as live
  update public.quotes set status = 'draft' where id = qa4;
  if not exists (select 1 from public.quote_quality_hold where quote_id = qa4 and released_at is null) then
    insert into public.quote_quality_hold (quote_id, inquiry_id, flags, held_at, release_due)
    values (qa4, ia, '["zz_probe"]'::jsonb, now(), now() + interval '24 hours');
  end if;

  -- A: the payment (the sale row the accountant's code writes; trg_reveal_receipt files reveal.paid and the seat acts at once)
  update public.quotes set status = 'revealed' where id = qa1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, fee_status, revealed_at)
  values (qa1, ia, s1, c, 4500, 135, 'paid', now()) returning id into ta;
  update public.inquiries set status = 'revealed' where id = ia;
  select id into h from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer' and target_id = 'reveal.paid:' || ta;
  if h is null then fails := fails || ' A:no_handoff'; end if;
  if (select evidence->'request'->>'state' from public.agent_actions where id = h) is distinct from 'reveal_open' then
    fails := fails || ' A:answer(' || coalesce((select left(evidence::text, 300) from public.agent_actions where id = h), 'null') || ')'; end if;
  -- the original messages still go: the customer's receipt and the chosen supplier's notice
  if not exists (select 1 from public.notifications x where x.type = 'reveal_receipt' and x.inquiry_id = ia) then fails := fails || ' A:no_receipt'; end if;
  if not exists (select 1 from public.notifications x where x.type = 'quote_accepted' and x.inquiry_id = ia and x.lead_id = s1) then fails := fails || ' A:no_chosen_notice'; end if;
  select * into r from public.inquiries where id = ia;
  if r.status <> 'revealed' or r.outcome is distinct from 'revealed' or r.pipeline_stage is distinct from 'revealed' then
    fails := fails || ' A:request(' || r.status || '/' || coalesce(r.outcome, '-') || '/' || coalesce(r.pipeline_stage, '-') || ')'; end if;
  select expires_at into u from public.quotes where id = qa4;
  if r.reveal_open_until is distinct from u then fails := fails || ' A:until(' || coalesce(r.reveal_open_until::text, 'null') || ' vs ' || u || ')'; end if;
  select count(*) into n from public.notifications x where x.inquiry_id = ia and x.type = 'quote_not_selected';
  if n <> 3 or exists (select 1 from public.notifications x where x.inquiry_id = ia and x.type = 'quote_not_selected' and x.lead_id = s1) then fails := fails || ' A:others(' || n || ')'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id = ia and x.type = 'quote_not_selected'
              and (x.body not like 'The customer has opened one quotation on request %. Your quotation remains available to the customer while it is valid. Nothing is needed from you now.'
                   or x.body ~* 'ZZ DEMO|4,?500|went ahead|another supplier| until ')) then fails := fails || ' A:wording'; end if;
  v := public.fn_sales_engineer_records_reveal(h);
  if not coalesce((v->>'already')::boolean, false) then fails := fails || ' A:not_idempotent'; end if;
  -- a second paid reveal on the same request tells nobody a second time
  update public.quotes set status = 'revealed' where id = qa2;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, fee_status, revealed_at)
  values (qa2, ia, s2, c, 4500, 135, 'paid', now()) returning id into ta2;
  if (select count(*) from public.notifications x where x.inquiry_id = ia and x.type = 'quote_not_selected') <> 3 then fails := fails || ' A:second_reveal_told_again'; end if;
  if (select count(*) from public.request_reveal_outcome where inquiry_id = ia) <> 2 then fails := fails || ' A:second_record'; end if;
  -- no NEW quotation; an existing supplier's second option is fine
  begin
    insert into public.quotes (inquiry_id, supplier_id, quote_amount, price_ex_vat, vat_treatment, status, validity) values (ia, s5, 4000, 4000, 'exclusive', 'submitted', '30 days');
    fails := fails || ' A:new_quote_taken';
  exception when others then
    if sqlerrm not like 'REQUEST_REVEALED%' then fails := fails || ' A:new_quote_other_error(' || left(sqlerrm, 80) || ')'; end if;
  end;
  begin
    insert into public.quotes (inquiry_id, supplier_id, option_no, quote_amount, price_ex_vat, vat_treatment, status, validity, expires_at) values (ia, s3, 2, 4100, 4100, 'exclusive', 'submitted', '3 days', now() + interval '3 days');
  exception when others then
    if sqlerrm like 'REQUEST_REVEALED%' then fails := fails || ' A:existing_supplier_refused'; end if;
  end;
  -- a withdrawal moves the date
  update public.quotes set status = 'withdrawn' where id = qa4;
  if (select reveal_open_until from public.inquiries where id = ia) >= u then fails := fails || ' A:withdrawal_kept_date'; end if;
  -- the duty: nothing before the date, then the end on the request's own date
  v := public.fn_sales_engineer_reveal_period_tick();
  if (select count(*) from public.request_reveal_outcome where inquiry_id = ia and state = 'ended') > 0 then fails := fails || ' A:ended_early'; end if;
  update public.inquiries set reveal_open_until = now() - interval '1 minute' where id = ia;
  v := public.fn_sales_engineer_reveal_period_tick();
  o := o || jsonb_build_object('a_tick', v);
  if (select count(*) from public.request_reveal_outcome where inquiry_id = ia and state <> 'ended') > 0 then fails := fails || ' A:not_ended'; end if;
  if (select status from public.inquiries where id = ia) <> 'revealed' then fails := fails || ' A:status_moved'; end if;
  select count(*) into n from public.notifications x where x.inquiry_id = ia and x.type = 'request_ended';
  if n <> 1 or exists (select 1 from public.notifications x where x.inquiry_id = ia and x.type = 'request_ended' and x.lead_id in (s1, s2, s4)) then fails := fails || ' A:ended_notices(' || n || ')'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id = ia and x.type = 'request_ended' and x.body ~* 'went ahead') then fails := fails || ' A:false_went_ahead'; end if;
  v := public.fn_sales_engineer_reveal_period_tick();
  if (select count(*) from public.notifications x where x.inquiry_id = ia and x.type = 'request_ended') <> 1 then fails := fails || ' A:ended_twice'; end if;

  -- B: one quotation
  update public.quotes set status = 'revealed' where id = qb1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, fee_status, revealed_at)
  values (qb1, ib, s1, c, 4500, 135, 'paid', now()) returning id into tb;
  update public.inquiries set status = 'revealed' where id = ib;
  select * into rr from public.request_reveal_outcome where transaction_id = tb;
  if rr.state is distinct from 'ended' or (select status from public.inquiries where id = ib) <> 'revealed' then fails := fails || ' B:not_ended(' || coalesce(rr.state, '-') || ')'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id = ib and x.type in ('quote_not_selected', 'request_ended')) then fails := fails || ' B:told_someone'; end if;

  -- D: ended, then a refund re-opens it
  update public.quotes set status = 'revealed' where id = qd1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, fee_status, revealed_at)
  values (qd1, idq, s1, c, 4500, 135, 'paid', now()) returning id into td;
  update public.inquiries set status = 'revealed', reveal_open_until = now() - interval '1 minute' where id = idq;
  v := public.fn_sales_engineer_reveal_period_tick();
  if (select count(*) from public.notifications x where x.inquiry_id = idq and x.type = 'request_ended') <> 2 then fails := fails || ' D:not_ended_first'; end if;
  update public.transactions set refund_status = 'refunded' where id = td;
  perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', 'probe-refund-' || td,
    jsonb_build_object('transaction_id', td, 'customer_id', c, 'supplier_id', s1, 'inquiry_id', idq, 'quote_id', qd1, 'amount_aed', '139.05'));
  select * into r from public.inquiries where id = idq;
  if (select state from public.request_reveal_outcome where transaction_id = td) <> 'reopened' or r.reveal_open_until <= now()
     or r.outcome is not null or r.status <> 'revealed' then fails := fails || ' D:not_reopened(' || coalesce(r.outcome, '-') || ')'; end if;
  if (select count(*) from public.notifications x where x.inquiry_id = idq and x.type = 'request_reopened') <> 2 then fails := fails || ' D:reopen_notices'; end if;
  if not exists (select 1 from public.notifications x where x.inquiry_id = idq and x.type = 'refund_issued' and x.to_role = 'customer'
                  and x.body like '%You can still open another of the quotations you received on this request while they remain valid.%')
     or exists (select 1 from public.notifications x where x.inquiry_id = idq and x.type = 'refund_issued' and x.body like '%post the request again%')
     then fails := fails || ' D:refund_message'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id = idq and x.type in ('request_ended', 'request_reopened') and x.body ~* 'went ahead') then fails := fails || ' D:false_went_ahead'; end if;
  v := public.fn_sales_engineer_reveal_period_tick();
  if (select state from public.request_reveal_outcome where transaction_id = td) <> 'reopened' then fails := fails || ' D:duty_ended_reopened'; end if;
  perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', 'probe-refund-again-' || td,
    jsonb_build_object('transaction_id', td, 'customer_id', c, 'supplier_id', s1, 'inquiry_id', idq, 'quote_id', qd1, 'amount_aed', '139.05'));
  if (select count(*) from public.notifications x where x.inquiry_id = idq and x.type = 'request_reopened') <> 2 then fails := fails || ' D:reopened_twice'; end if;

  -- F: a refund on a request with a recorded period but no live quotation left (B) is NOT re-opened, and says "post again"
  perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', 'probe-refund-nolive-' || tb,
    jsonb_build_object('transaction_id', tb, 'customer_id', c, 'supplier_id', s1, 'inquiry_id', ib, 'quote_id', qb1, 'amount_aed', '139.05'));
  if (select state from public.request_reveal_outcome where transaction_id = tb) <> 'ended'
     or (select reveal_open_until from public.inquiries where id = ib) > now() then fails := fails || ' F:reopened_with_nothing_live'; end if;
  if not exists (select 1 from public.notifications x where x.inquiry_id = ib and x.type = 'refund_issued' and x.body like '%post the request again%')
     then fails := fails || ' F:refund_message'; end if;

  -- C: quotations valid beyond 30 days: the period is capped at 30 days after the first paid reveal
  update public.quotes set status = 'revealed' where id = qc1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, fee_status, revealed_at)
  values (qc1, icap, s1, c, 4500, 135, 'paid', now()) returning id into tcap;
  if (select reveal_open_until from public.inquiries where id = icap) is distinct from now() + interval '30 days' then
    fails := fails || ' C:not_capped(' || coalesce((select reveal_open_until::text from public.inquiries where id = icap), 'null') || ')'; end if;

  -- G: a request step that raises is a finding and an event; the hand-over still answers with the messages
  hb := public.fn_seat_handoff('accountant', 'sales_engineer', 'reveal.paid', 'transactions', 'probe-bad-' || c,
    jsonb_build_object('transaction_id', 'not-a-uuid', 'customer_id', c, 'inquiry_id', icap));
  if hb is null or (select status from public.agent_actions where id = hb) = 'failed'
     or (select evidence->'request'->>'error' from public.agent_actions where id = hb) is null then fails := fails || ' G:handoff'; end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'reveal_request_step:' || hb) then fails := fails || ' G:no_finding'; end if;
  if not exists (select 1 from public.company_event where dedupe_key = 'request.step_failed:' || hb) then fails := fails || ' G:no_event'; end if;

  -- E: a reveal with no recorded period (paid before this file): a refund changes nothing
  delete from public.request_reveal_outcome where transaction_id = tb;
  update public.inquiries set reveal_open_until = null where id = ib;
  perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', 'probe-refund-old-' || tb,
    jsonb_build_object('transaction_id', tb, 'customer_id', c, 'supplier_id', s1, 'inquiry_id', ib, 'quote_id', qb1, 'amount_aed', '139.05'));
  if (select reveal_open_until from public.inquiries where id = ib) is not null then fails := fails || ' E:old_reveal_touched'; end if;

  -- Z: zero-rated and exempt are storable
  begin
    insert into public.quotes (inquiry_id, supplier_id, quote_amount, price_ex_vat, vat_treatment, status, validity)
    values (iz, s2, 3000, 3000, 'zero_rated', 'submitted', '30 days'), (iz, s3, 3000, 3000, 'exempt', 'submitted', '30 days');
  exception when others then fails := fails || ' Z:' || left(sqlerrm, 120);
  end;

  if exists (select 1 from public.notifications x where x.inquiry_id in (ia, ib, idq, iz) and not public.fn_is_demo_email(x.to_email)) then fails := fails || ' X:a_real_address'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id in (ia, ib, idq) and x.to_role = 'supplier'
              and x.type in ('quote_not_selected', 'request_ended', 'request_reopened') and (x.body || x.subject) ~ '[؀-ۿ]') then fails := fails || ' X:arabic_to_a_supplier'; end if;
  if fails <> '' then raise exception 'CHK<<PROBE FAILED:% | %>>', fails, o::text; end if;
  raise exception 'CHK<<PROBE OK %>>', o::text;
end $probe$;
