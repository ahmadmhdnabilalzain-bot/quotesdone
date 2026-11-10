-- PROBE: A REQUEST THAT REACHED SUPPLIERS ENDS — EXPIRED, LOST OR COMPLETED WITHOUT AWARD — AND EVERYONE IS TOLD.
-- Seat: sales_engineer. 10 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_request_that_reached_suppliers_ends_expired_lost_or_completed_and_everyone_is_told.sql (or concatenated after it:
-- scripts/ci/rehearse_sql.mjs <file> <this>). It always raises, so every row is rolled back; pg_net sends only committed
-- requests. qd.duty_fixtures = 'on' (local) makes the routine see ONLY ZZ DEMO / @example.invalid customers, and every
-- supplier and customer below is one. qd.probe_files_demo_handoff lets the deliveries be filed for them.
-- PROBE OK only if, on one run at now():
--   E  matched 25 days ago, never quoted          -> expired, "no matched supplier quoted in time", a coverage_gap action,
--                                                    both matched suppliers handed an rfq_closed notice
--   R  last quote 16 days ago                     -> still open, ONE reminder (a second run sends none)
--   L  last quote 31 days ago                     -> lost, its suppliers told
--   C  revealed 61 days ago, no hire              -> completed, outcome completed_without_award; the revealed supplier
--                                                    is NOT told "no award", the other is
--   N  revealed 61 days ago, "not yet" 5 days ago -> still revealed
--   F  matched 2 days ago                         -> untouched
--   S  a split parent whose only part (E2) expires -> closed
do $probe$
declare
  fails text := ''; o jsonb := '{}'::jsonb; v jsonb; c uuid := gen_random_uuid(); s1 bigint; s2 bigint;
  uE uuid := gen_random_uuid(); uR uuid := gen_random_uuid(); uL uuid := gen_random_uuid(); uC uuid := gen_random_uuid();
  uN uuid := gen_random_uuid(); uF uuid := gen_random_uuid(); uS uuid := gen_random_uuid(); uE2 uuid := gen_random_uuid();
  xR uuid := gen_random_uuid(); xL uuid := gen_random_uuid(); xC uuid := gen_random_uuid(); xC2 uuid := gen_random_uuid(); xN uuid := gen_random_uuid();
  tC uuid; tN uuid; n int;
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Outcome Customer', 'zz-demo-outcome@example.invalid', '+971500000142', true, true, 'demo://terms', 'en', now() - interval '120 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Outcome Supplier One', 'zz-demo-outcome-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Outcome Supplier Two', 'zz-demo-outcome-s2@example.invalid') returning id into s2;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  select x.id, c, 'plumbing', 'Dubai', 'ZZ DEMO outcome probe ' || x.tag, x.st, 'en', now() - interval '100 days', case when x.st = 'split' then 'multi' else 'single' end
    from (values (uE, 'E', 'sent'), (uR, 'R', 'quoted'), (uL, 'L', 'quoted'), (uC, 'C', 'revealed'), (uN, 'N', 'revealed'), (uF, 'F', 'sent'), (uS, 'S', 'split')) x(id, tag, st);
  insert into public.inquiries (id, customer_id, parent_inquiry_id, category, emirate, summary, status, lang, created_at, scope_type)
  values (uE2, c, uS, 'plumbing', 'Dubai', 'ZZ DEMO outcome probe E2', 'sent', 'en', now() - interval '100 days', 'single');
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select i, s, 0.9, case when i = uF then now() - interval '2 days' else now() - interval '90 days' end, 'ZZ DEMO outcome probe'
    from unnest(array[uE, uR, uL, uC, uN, uF, uE2]) i, unnest(array[s1, s2]) s;
  update public.inquiry_matches set sent_at = now() - interval '25 days' where inquiry_id in (uE, uE2);
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q::text, 1, 'ZZ DEMO heater and labour', 'ZZ DEMO Brand', 'ZZ-1', '80 litre electric', 1, 'lot', 4000, 500 from unnest(array[xR, xL, xC, xC2, xN]) q;
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  values (xR, uR, s1, 4500, 'submitted', now() - interval '16 days', '1 year', '1 week', '50% advance', 'civil works', '30 days'),
         (xL, uL, s1, 4500, 'submitted', now() - interval '31 days', '1 year', '1 week', '50% advance', 'civil works', '30 days'),
         (xC, uC, s1, 4500, 'revealed', now() - interval '70 days', '1 year', '1 week', '50% advance', 'civil works', '30 days'),
         (xC2, uC, s2, 4900, 'submitted', now() - interval '70 days', '1 year', '1 week', '50% advance', 'civil works', '30 days'),
         (xN, uN, s1, 4500, 'revealed', now() - interval '70 days', '1 year', '1 week', '50% advance', 'civil works', '30 days');
  -- the quality gate holds a fresh quote as a draft; released here as fn_sales_engineer_quote_quality_tick releases one
  -- whose hours have passed, so each stands as the customer's portal would show it
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (xR, xL, xC, xC2, xN);
  update public.quotes set status = case when id in (xC, xN) then 'revealed' else 'submitted' end where id in (xR, xL, xC, xC2, xN);
  if exists (select 1 from public.quotes where id in (xR, xL, xC2) and status <> 'submitted') then
    raise exception 'CHK<<PROBE FAILED: the fixture quotes did not stand (%)>>', (select jsonb_agg(status) from public.quotes where id in (xR, xL, xC2));
  end if;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (xC, uC, s1, c, 4500, 'paid', now() - interval '61 days', now() - interval '54 days') returning id into tC;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (xN, uN, s1, c, 4500, 'paid', now() - interval '61 days', now() - interval '54 days') returning id into tN;
  insert into public.customer_followup (transaction_id, stage, lang, asked_at, answered_at, hired)
  values (tN, 'day_fourteen', 'en', now() - interval '47 days', now() - interval '5 days', 'not_yet');

  v := public.fn_sales_engineer_request_outcomes();
  o := o || jsonb_build_object('run1', v - 'acted');
  if (select status || '/' || coalesce(lost_reason, '') from public.inquiries where id = uE) <> 'expired/no matched supplier quoted in time' then fails := fails || ' E:status'; end if;
  if not exists (select 1 from public.agent_actions a where a.kind = 'coverage_gap' and a.detail->>'signal' = 'coverage_gap:no_quote:' || uE) then fails := fails || ' E:coverage'; end if;
  if (select count(*) from public.agent_actions a where a.kind = 'handoff' and a.detail->'prepared'->>'type' = 'rfq_closed' and a.detail->'prepared'->>'inquiry_id' = uE::text) <> 2
     and (select count(*) from public.notifications x where x.type = 'rfq_closed' and x.inquiry_id = uE) <> 2 then
    fails := fails || ' E:suppliers(' || (v->'acted')::text || ')'; end if;
  if (select status from public.inquiries where id = uR) <> 'quoted' then fails := fails || ' R:closed'; end if;
  if not exists (select 1 from public.customer_support_duty_message d where d.stage = 'request.quoted_reminder' and d.subject_key = uR::text) then fails := fails || ' R:no_reminder'; end if;
  if (select status from public.inquiries where id = uL) <> 'lost' then fails := fails || ' L:status'; end if;
  if (select status || '/' || outcome from public.inquiries where id = uC) <> 'completed/completed_without_award' then fails := fails || ' C:status'; end if;
  select count(*) into n from public.notifications x where x.type = 'rfq_closed' and x.inquiry_id = uC and x.lead_id = s1;
  if n > 0 or exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->'prepared'->>'type' = 'rfq_closed'
                         and a.detail->'prepared'->>'inquiry_id' = uC::text and a.detail->'prepared'->>'lead_id' = s1::text) then fails := fails || ' C:revealed_supplier_told'; end if;
  if (select status from public.inquiries where id = uN) <> 'revealed' then fails := fails || ' N:closed_despite_not_yet'; end if;
  if (select status from public.inquiries where id = uF) <> 'sent' then fails := fails || ' F:touched'; end if;
  if (select status from public.inquiries where id = uE2) <> 'expired' or (select status from public.inquiries where id = uS) <> 'closed' then fails := fails || ' S:parent'; end if;
  -- a second run: nothing new, and no second reminder
  v := public.fn_sales_engineer_request_outcomes();
  o := o || jsonb_build_object('run2', v - 'acted');
  if (v->>'expired')::int + (v->>'lost')::int + (v->>'completed_without_award')::int + (v->>'reminded')::int <> 0
     or (select count(*) from public.customer_support_duty_message d where d.stage = 'request.quoted_reminder' and d.subject_key = uR::text) <> 1 then
    fails := fails || ' X:second_run(' || v::text || ')'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id in (uE, uR, uL, uC, uN, uF, uE2) and not public.fn_is_demo_email(x.to_email)) then
    fails := fails || ' X:a_real_address'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:% | %>>', fails, o::text; end if;
  raise exception 'CHK<<PROBE OK %>>', o::text;
end $probe$;
