-- PROBE: A PAID REVEAL CLOSES THE REQUEST (OR KEEPS IT OPEN WITH A DATE), TELLS EVERY UNCHOSEN SUPPLIER ONCE, OWNS THE
-- FOLLOW-UP, APPLIES THE MODEL'S ANSWER, AND A REFUND RE-OPENS IT.
-- Seat: sales_engineer. 13 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql (node scripts/ci/rehearse_sql.mjs <file> <probe>). It always
-- raises, so every row is rolled back; pg_net sends only committed requests. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   A. three quotes, one paid: the reveal.paid hand-over is answered with a request outcome; the request reads outcome
--      'revealed', pipeline 'revealed', status 'revealed', open until the refund deadline; the two unchosen suppliers get one
--      quote_not_selected notice each and the chosen one none; connect_check + hire_check rows and the response watch exist;
--      the model was not asked (demo) and the record says so; acting again changes nothing;
--      the duty after the date closes it: status 'closed', each unchosen supplier one request_closed notice; a repeat
--      delivery writing 'revealed' leaves it closed;
--   B. one quote, paid: closed at the payment, nobody else to tell;
--   C. two quotes, paid, then the model answers close_now: closed, decided_by 'model', the other supplier told it is closed;
--   D. refund.paid on B: the request is re-opened (status 'revealed', record 'reopened');
--   X. nothing addressed to a real address.
do $probe$
declare
  fails text := ''; o jsonb := '{}'::jsonb; v jsonb; c uuid := gen_random_uuid(); s1 bigint; s2 bigint; s3 bigint;
  ia uuid := gen_random_uuid(); ib uuid := gen_random_uuid(); ic uuid := gen_random_uuid();
  qa1 uuid := gen_random_uuid(); qa2 uuid := gen_random_uuid(); qa3 uuid := gen_random_uuid(); qb1 uuid := gen_random_uuid();
  qc1 uuid := gen_random_uuid(); qc2 uuid := gen_random_uuid(); ta uuid; tb uuid; tc uuid; h bigint; hq bigint;
  r public.inquiries; rr public.request_reveal_outcome; n int;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Reveal Close Customer', 'zz-demo-revclose@example.invalid', '+971500000187', true, true, 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Chosen Supplier', 'zz-demo-rc-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Second Supplier', 'zz-demo-rc-s2@example.invalid') returning id into s2;
  insert into public.leads (company_name, email) values ('ZZ DEMO Third Supplier', 'zz-demo-rc-s3@example.invalid') returning id into s3;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  select x, c, 'plumbing', 'Dubai', 'ZZ DEMO reveal close probe', 'quoted', 'en', now() - interval '10 days', 'single' from unnest(array[ia, ib, ic]) x;
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q::text, 1, 'ZZ DEMO heater and labour', 'ZZ DEMO Brand', 'ZZ-1', '80 litre electric', 1, 'lot', 4000, 500 from unnest(array[qa1, qa2, qa3, qb1, qc1, qc2]) q;
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, price_ex_vat, vat_treatment, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  select q, i, s, 4500, 4500, 'exclusive', 'submitted', now() - interval '5 days', '1 year', '1 week', '50% advance', 'civil works', '30 days'
    from (values (qa1, ia, s1), (qa2, ia, s2), (qa3, ia, s3), (qb1, ib, s1), (qc1, ic, s1), (qc2, ic, s2)) x(q, i, s);
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (qa1, qa2, qa3, qb1, qc1, qc2);
  -- the quality gate files a new quote as a draft; released, each reads as the live quotation a customer compares
  update public.quotes set status = 'submitted' where id in (qa1, qa2, qa3, qb1, qc1, qc2);

  -- A: the payment (the sale row the accountant's code writes; trg_reveal_receipt files reveal.paid and the seat acts at once)
  update public.quotes set status = 'revealed' where id = qa1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, fee_status, revealed_at)
  values (qa1, ia, s1, c, 4500, 135, 'paid', now()) returning id into ta;
  update public.inquiries set status = 'revealed' where id = ia;
  select id into h from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer' and target_id = 'reveal.paid:' || ta;
  if h is null then fails := fails || ' A:no_handoff'; end if;
  if (select evidence->'request'->>'state' from public.agent_actions where id = h) is distinct from 'open_for_more' then
    fails := fails || ' A:answer(' || coalesce((select left(evidence::text, 300) from public.agent_actions where id = h), 'null') || ')'; end if;
  select * into r from public.inquiries where id = ia;
  if r.outcome is distinct from 'revealed' or r.pipeline_stage is distinct from 'revealed' or r.status <> 'revealed' or r.reveal_open_until is null then
    fails := fails || ' A:request(' || r.status || '/' || coalesce(r.outcome, '-') || '/' || coalesce(r.pipeline_stage, '-') || ')'; end if;
  select count(*) into n from public.notifications x where x.inquiry_id = ia and x.type = 'quote_not_selected';
  if n <> 2 or exists (select 1 from public.notifications x where x.inquiry_id = ia and x.type = 'quote_not_selected' and x.lead_id = s1) then fails := fails || ' A:not_chosen(' || n || ')'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id = ia and x.type in ('quote_not_selected', 'request_closed')
              and (x.body ilike '%ZZ DEMO Chosen%' or x.body ilike '%4,500%' or x.body ilike '%4500%' or x.body ilike '%Reveal Close Customer%')) then fails := fails || ' A:names_or_price'; end if;
  if (select count(*) from public.reveal_followup where transaction_id = ta) <> 2 then fails := fails || ' A:followups'; end if;
  if not exists (select 1 from public.supplier_response_watch where transaction_id = ta) then fails := fails || ' A:watch'; end if;
  select * into rr from public.request_reveal_outcome where transaction_id = ta;
  if rr.state is distinct from 'open_for_more' or rr.model_status not like 'not asked: demo%' or rr.other_live_quotes <> 2 then fails := fails || ' A:record'; end if;
  v := public.fn_sales_engineer_closes_on_reveal(h);
  if not coalesce((v->>'already')::boolean, false) then fails := fails || ' A:not_idempotent'; end if;
  o := o || jsonb_build_object('a_paid', jsonb_build_object('state', rr.state, 'open_until', rr.open_until, 'told', jsonb_array_length(rr.unchosen_told)));
  -- the duty after the date
  update public.request_reveal_outcome set open_until = now() - interval '1 minute' where transaction_id = ta;
  perform set_config('qd.duty_fixtures', 'on', true);
  v := public.fn_sales_engineer_reveal_aftercare_tick();
  o := o || jsonb_build_object('a_tick', v);
  if (select status from public.inquiries where id = ia) <> 'closed' then fails := fails || ' A:not_closed_by_duty'; end if;
  select count(*) into n from public.notifications x where x.inquiry_id = ia and x.type = 'request_closed';
  if n <> 2 then fails := fails || ' A:closed_notices(' || n || ')'; end if;
  v := public.fn_sales_engineer_reveal_aftercare_tick();
  if (select count(*) from public.notifications x where x.inquiry_id = ia and x.type = 'request_closed') <> 2 then fails := fails || ' A:told_twice'; end if;
  update public.inquiries set status = 'revealed' where id = ia;   -- a repeat delivery of the same sale (markRevealed)
  if (select status from public.inquiries where id = ia) <> 'closed' then fails := fails || ' A:repeat_reopened'; end if;

  -- B: one quote
  update public.quotes set status = 'revealed' where id = qb1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, fee_status, revealed_at)
  values (qb1, ib, s1, c, 4500, 135, 'paid', now()) returning id into tb;
  select * into r from public.inquiries where id = ib;
  if r.status <> 'closed' or r.outcome is distinct from 'revealed' then fails := fails || ' B:not_closed(' || r.status || ')'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id = ib and x.type in ('quote_not_selected', 'request_closed')) then fails := fails || ' B:told_someone'; end if;

  -- C: two quotes, the model answers close_now
  update public.quotes set status = 'revealed' where id = qc1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, fee_status, revealed_at)
  values (qc1, ic, s1, c, 4500, 135, 'paid', now()) returning id into tc;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, expires_at)
  values ('sales_engineer', 'sales_engineer.reveal_paid', 'ZZ DEMO probe question', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('transaction_id', tc, 'inquiry_id', ic, 'quote_id', qc1), 'probe', now() + interval '1 day')
  returning id into hq;
  v := public.fn_reason_apply_sales_engineer__reveal_paid(hq, '{"decision":{"choice":"close_now"},"answer":"ZZ DEMO the recommended quotation was revealed","model":"probe/model"}'::jsonb);
  select * into rr from public.request_reveal_outcome where transaction_id = tc;
  if rr.state <> 'closed' or rr.decided_by <> 'model' or (select status from public.inquiries where id = ic) <> 'closed' then fails := fails || ' C:model_not_applied(' || coalesce(rr.state, '-') || ')'; end if;
  if (select count(*) from public.notifications x where x.inquiry_id = ic and x.type = 'request_closed' and x.lead_id = s2) <> 1 then fails := fails || ' C:other_not_told'; end if;
  begin
    v := public.fn_reason_apply_sales_engineer__reveal_paid(hq, '{"decision":{"choice":"maybe"}}'::jsonb);
    fails := fails || ' C:bad_choice_accepted';
  exception when others then null;
  end;

  -- D: refund.paid on B re-opens it
  perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', 'probe-refund-' || tb,
    jsonb_build_object('transaction_id', tb, 'customer_id', c, 'supplier_id', s1, 'inquiry_id', ib, 'quote_id', qb1, 'amount_aed', '139.05'));
  if (select status from public.inquiries where id = ib) <> 'revealed' or (select state from public.request_reveal_outcome where transaction_id = tb) <> 'reopened' then
    fails := fails || ' D:not_reopened'; end if;

  if exists (select 1 from public.notifications x where x.inquiry_id in (ia, ib, ic) and not public.fn_is_demo_email(x.to_email)) then fails := fails || ' X:a_real_address'; end if;
  if fails <> '' then raise exception 'CHK<<PROBE FAILED:% | %>>', fails, o::text; end if;
  raise exception 'CHK<<PROBE OK %>>', o::text;
end $probe$;
