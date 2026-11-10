-- PROBE: A FOLLOW-UP "YES" COMPLETES THE REQUEST AND TELLS THE LOSING SUPPLIERS, ONCE, WHICHEVER DOOR COMES FIRST.
-- Seat: sales_engineer. 10 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_follow_up_yes_completes_the_request_and_tells_the_losing_suppliers.sql (or concatenated after it). It always raises,
-- so every row is rolled back; pg_net sends only committed requests. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. yes on request A: status completed, outcome hired, completed_at set, hired_supplier_id the revealed supplier; the
--      supplier who lost is handed one job_awarded_other notice and the winner none; a second yes changes nothing;
--   2. request B, completed first by Hire (as complete_inquiry writes it): a yes afterwards sends no second notice;
--   3. request C, "no": nothing completed, nobody told.
do $probe$
declare
  fails text := ''; o jsonb := '{}'::jsonb; v jsonb; c uuid := gen_random_uuid(); s1 bigint; s2 bigint;
  ia uuid := gen_random_uuid(); ib uuid := gen_random_uuid(); ic uuid := gen_random_uuid();
  qa1 uuid := gen_random_uuid(); qa2 uuid := gen_random_uuid(); qb1 uuid := gen_random_uuid(); qb2 uuid := gen_random_uuid();
  qc1 uuid := gen_random_uuid(); ta uuid; tb uuid; tc uuid; ka uuid; kb uuid; kc uuid; r public.inquiries;
  told_a int; told_b int;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Followup Customer', 'zz-demo-followup@example.invalid', '+971500000143', true, true, 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Winner Supplier', 'zz-demo-fu-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Loser Supplier', 'zz-demo-fu-s2@example.invalid') returning id into s2;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  select x, c, 'plumbing', 'Dubai', 'ZZ DEMO follow-up probe', 'revealed', 'en', now() - interval '20 days', 'single' from unnest(array[ia, ib, ic]) x;
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q::text, 1, 'ZZ DEMO heater and labour', 'ZZ DEMO Brand', 'ZZ-1', '80 litre electric', 1, 'lot', 4000, 500 from unnest(array[qa1, qa2, qb1, qb2, qc1]) q;
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  select q, i, s, 4500, 'submitted', now() - interval '15 days', '1 year', '1 week', '50% advance', 'civil works', '30 days'
    from (values (qa1, ia, s1), (qa2, ia, s2), (qb1, ib, s1), (qb2, ib, s2), (qc1, ic, s1)) x(q, i, s);
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (qa1, qa2, qb1, qb2, qc1);
  update public.quotes set status = case when id in (qa1, qb1, qc1) then 'revealed' else 'submitted' end where id in (qa1, qa2, qb1, qb2, qc1);
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (qa1, ia, s1, c, 4500, 'paid', now() - interval '4 days', now() + interval '3 days') returning id into ta;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (qb1, ib, s1, c, 4500, 'paid', now() - interval '4 days', now() + interval '3 days') returning id into tb;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (qc1, ic, s1, c, 4500, 'paid', now() - interval '4 days', now() + interval '3 days') returning id into tc;
  insert into public.customer_followup (transaction_id, stage, lang) values (ta, 'day_three', 'en') returning token into ka;
  insert into public.customer_followup (transaction_id, stage, lang) values (tb, 'day_three', 'en') returning token into kb;
  insert into public.customer_followup (transaction_id, stage, lang) values (tc, 'day_three', 'en') returning token into kc;

  -- 1
  v := public.fn_customer_followup_answer(ka, 'yes', 5, 'ZZ DEMO a good job, on time');
  o := o || jsonb_build_object('yes_a', v->'recorded');
  select * into r from public.inquiries where id = ia;
  if r.status <> 'completed' or r.outcome <> 'hired' or r.completed_at is null or r.hired_supplier_id <> s1 then fails := fails || ' 1:not_completed(' || r.status || '/' || coalesce(r.outcome, '') || ')'; end if;
  select count(*) into told_a from public.agent_actions a where a.kind = 'handoff' and a.detail->>'msg_type' = 'job_awarded_other' and a.detail->>'inquiry_id' = ia::text;
  -- a filed handoff becomes a notification row: either is the one notice, never both counted
  told_a := greatest(told_a, (select count(*) from public.notifications x where x.type = 'job_awarded_other' and x.inquiry_id = ia));
  if told_a <> 1 or exists (select 1 from public.notifications x where x.type = 'job_awarded_other' and x.inquiry_id = ia and x.lead_id = s1)
     then fails := fails || ' 1:losers(' || told_a || ')'; end if;
  v := public.fn_customer_followup_answer(ka, 'yes');
  if not coalesce((v->>'already')::boolean, false) then fails := fails || ' 1:second_yes'; end if;

  -- 2: Hire came first, as complete_inquiry writes it
  update public.inquiries set status = 'completed', hired_supplier_id = s1, completed_at = now(), outcome = 'hired' where id = ib;
  v := public.fn_customer_followup_answer(kb, 'yes');
  select count(*) into told_b from public.agent_actions a where a.kind = 'handoff' and a.detail->>'msg_type' = 'job_awarded_other' and a.detail->>'inquiry_id' = ib::text;
  -- a filed handoff becomes a notification row: either is the one notice, never both counted
  told_b := greatest(told_b, (select count(*) from public.notifications x where x.type = 'job_awarded_other' and x.inquiry_id = ib));
  if told_b <> 0 or v->'recorded' ? 'completed' then fails := fails || ' 2:told_after_hire(' || told_b || ')'; end if;

  -- 3: no
  v := public.fn_customer_followup_answer(kc, 'no');
  if (select status from public.inquiries where id = ic) <> 'revealed' then fails := fails || ' 3:no_completed'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id in (ia, ib, ic) and not public.fn_is_demo_email(x.to_email)) then fails := fails || ' X:a_real_address'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:% | %>>', fails, o::text; end if;
  raise exception 'CHK<<PROBE OK %>>', o::text;
end $probe$;
