-- PROBE: A CLOSED REQUEST IS NOT CANCELLED, EDITED OR COMPLETED AGAIN, AND A REVEALED ONE SAYS WHAT TO DO.
-- Seat: sales_engineer. 10 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_closed_request_is_not_cancelled_edited_or_completed_again_and_a_revealed_one_says_what_to_do.sql (or concatenated
-- after it). It always raises, so every row is rolled back; pg_net sends only committed requests. Every party is a
-- ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. cancelling an expired request answers inquiry_closed, leaves it expired, and tells no supplier;
--   2. cancelling a revealed request answers already_revealed in English and Arabic, with no "close it instead";
--   3. cancelling a split request cancels its two parts too, and its supplier is told once per part;
--   4. editing a lost request and adding specs to an expired one are refused.
do $probe$
declare
  fails text := ''; o jsonb := '{}'::jsonb; v jsonb; c uuid := gen_random_uuid(); s1 bigint;
  ux uuid := gen_random_uuid(); ur uuid := gen_random_uuid(); up uuid := gen_random_uuid(); uk1 uuid := gen_random_uuid(); uk2 uuid := gen_random_uuid();
  ul uuid := gen_random_uuid(); qr uuid := gen_random_uuid(); n int;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Cancel Customer', 'zz-demo-cancel@example.invalid', '+971500000144', true, true, 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Cancel Supplier', 'zz-demo-cancel-s1@example.invalid') returning id into s1;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  values (ux, c, 'plumbing', 'Dubai', 'ZZ DEMO cancel probe expired', 'expired', 'en', now() - interval '20 days', 'single'),
         (ur, c, 'plumbing', 'Dubai', 'ZZ DEMO cancel probe revealed', 'revealed', 'en', now() - interval '20 days', 'single'),
         (ul, c, 'plumbing', 'Dubai', 'ZZ DEMO cancel probe lost', 'lost', 'en', now() - interval '10 minutes', 'single'),
         (up, c, 'combined', 'Dubai', 'ZZ DEMO cancel probe split', 'split', 'en', now() - interval '2 days', 'multi');
  insert into public.inquiries (id, customer_id, parent_inquiry_id, category, emirate, summary, status, lang, created_at, scope_type)
  values (uk1, c, up, 'plumbing', 'Dubai', 'ZZ DEMO cancel probe part 1', 'sent', 'en', now() - interval '2 days', 'single'),
         (uk2, c, up, 'electrical', 'Dubai', 'ZZ DEMO cancel probe part 2', 'sent', 'en', now() - interval '2 days', 'single');
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select i, s1, 0.9, now() - interval '2 days', 'ZZ DEMO cancel probe' from unnest(array[ux, uk1, uk2]) i;
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  values (qr::text, 1, 'ZZ DEMO heater and labour', 'ZZ DEMO Brand', 'ZZ-1', '80 litre electric', 1, 'lot', 4000, 500);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  values (qr, ur, s1, 4500, 'revealed', now() - interval '10 days', '1 year', '1 week', '50% advance', 'civil works', '30 days');
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (qr, ur, s1, c, 4500, 'paid', now() - interval '4 days', now() + interval '3 days');

  v := public.fn_cancel_inquiry(ux, c, null);
  o := o || jsonb_build_object('expired', v);
  if v->>'error' is distinct from 'inquiry_closed' or (select status from public.inquiries where id = ux) <> 'expired'
     or exists (select 1 from public.notifications x where x.inquiry_id = ux and x.type = 'rfq_cancelled') then fails := fails || ' 1'; end if;
  v := public.fn_cancel_inquiry(ur, c, null);
  o := o || jsonb_build_object('revealed', v);
  if v->>'error' is distinct from 'already_revealed' or position('close it instead' in coalesce(v->>'message', '')) > 0
     or coalesce(v->>'message_ar', '') = '' or position('I hired this supplier' in coalesce(v->>'message', '')) = 0 then fails := fails || ' 2'; end if;
  v := public.fn_cancel_inquiry(up, c, null);
  o := o || jsonb_build_object('split', v);
  if (select count(*) from public.inquiries where id in (up, uk1, uk2) and status = 'cancelled') <> 3 then fails := fails || ' 3:parts_not_cancelled'; end if;
  select greatest((select count(*) from public.notifications x where x.type = 'rfq_cancelled' and x.inquiry_id in (uk1, uk2)),
                  (select count(*) from public.agent_actions a where a.kind = 'handoff' and a.detail->>'msg_type' = 'rfq_cancelled' and a.detail->>'inquiry_id' in (uk1::text, uk2::text)))
    into n;
  if n <> 2 then fails := fails || ' 3:suppliers_told(' || n || ')'; end if;
  v := public.fn_edit_inquiry(ul, c, '{"summary":"ZZ DEMO changed"}'::jsonb);
  if v->>'error' is distinct from 'not_editable' then fails := fails || ' 4:edit(' || v::text || ')'; end if;
  v := public.fn_inquiry_add_missing_specs(ux, c, '{}'::jsonb, 'customer_portal');
  if v->>'error' is distinct from 'inquiry_closed' then fails := fails || ' 4:specs(' || v::text || ')'; end if;
  if exists (select 1 from public.notifications x where x.inquiry_id in (ux, ur, up, uk1, uk2, ul) and not public.fn_is_demo_email(x.to_email)) then fails := fails || ' X:a_real_address'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:% | %>>', fails, o::text; end if;
  raise exception 'CHK<<PROBE OK %>>', o::text;
end $probe$;
