-- PROBE: THE SUPPLIER IS KNOWN ON EVERY CHANNEL.
--
-- Seat: customer_support. 16 Nov 2026. Pure probe: no DDL, never applied. Run after the_supplier_is_known_on_every_channel.sql,
-- in one rolled-back transaction on a LOCAL Postgres 16 built from the mirror (13 Nov 2026: nothing is rehearsed on
-- production). It always raises, so every row below is rolled back. Every party is a ZZ DEMO fixture on @example.invalid,
-- demo by its name and address (is_demo is generated); no real row is read or written, and no model is called.
--
-- PROBE OK only if
--   P1 a healthy supplier with no job in 30 days is told his confirmed trades (with label and open/closed), services and
--      emirates, that he receives requests now, and why no job came: his trade is not open to customers and no request was
--      posted in his trades and emirates;
--   P2 a request posted in his trade and emirate that did not reach him is counted, and the reason says it went elsewhere;
--   P3 once one reaches him: jobs_sent_30d = 1, why_no_jobs is empty, recent_jobs names the job by number with HIS OWN quote;
--   P4 a held supplier reads every gate that holds him: licence expired (with the date), held for unanswered requests,
--      the strike limit, marked busy, services not confirmed; licence_expired true and licence_days_left negative;
--      receives_requests_now false; the collaboration record is his;
--   P5 an unregistered listing reads not_registered;
--   P6 no reading carries another supplier's company or a customer's name, e-mail or phone;
--   P7 fn_wa_context stays closed to anon and authenticated.
do $probe$
declare
  fails text := ''; a jsonb; b jsonb; c jsonb; txt text; codes text[];
  sA bigint; sB bigint; sC bigint; cust uuid := gen_random_uuid(); iX uuid := gen_random_uuid(); iY uuid := gen_random_uuid();
  ref int; today date := (now() at time zone 'Asia/Dubai')::date;
begin
  -- fixtures only: the leads triggers (the mandatory-six gate among them) are not what is proven here, so the rows are
  -- written with triggers off (a superuser-only setting: on a hosted database the probe stops at this line), then back on
  perform set_config('session_replication_role', 'replica', true);
  insert into public.customers (id, full_name, email, phone, locale, created_at)
  values (cust, 'ZZ DEMO Probe Buyer Sukayna', 'zz-demo-supknown-buyer@example.invalid', '+971500000093', 'en', now() - interval '40 days');

  insert into public.leads (company_name, email, claimed, claimed_by, approval_status, verified, license_expiry, trade_license_no)
  values ('ZZ DEMO Polar Duct Works', 'zz-demo-supknown-a@example.invalid', true, 'zz-demo-supknown-a@example.invalid', 'approved', true,
          today + 200, 'ZZ-DEMO-1001') returning id into sA;
  insert into public.leads (company_name, email, claimed, claimed_by, approval_status, verified, license_expiry, trade_license_no, chat_strikes)
  values ('ZZ DEMO Held Steel Rival', 'zz-demo-supknown-b@example.invalid', true, 'zz-demo-supknown-b@example.invalid', 'approved', true,
          today - 10, 'ZZ-DEMO-1002', 3) returning id into sB;
  insert into public.leads (company_name, email) values ('ZZ DEMO Unclaimed Glass', 'zz-demo-supknown-c@example.invalid') returning id into sC;

  -- A: confirmed HVAC in Dubai (the trade closed to customers); B: unconfirmed, held, busy
  insert into public.supplier_capabilities (supplier_id, trades, services, coverage_emirates, confirmed_at, roles)
  values (sA, array['hvac'], array['hvac.zz_demo_unknown_service'], array['Dubai'], now() - interval '20 days', array['installer']);
  insert into public.supplier_capabilities (supplier_id, trades, coverage_emirates) values (sB, array['hvac'], array['Dubai']);
  insert into public.trade_customer_opening (trade, verified_suppliers, open_at, is_open)
  values ('hvac', 0, 10, false) on conflict (trade) do update set is_open = false;
  update public.leads set collaboration_hold_at = now() - interval '2 days', matching_blocked = true, matching_block_reason = 'collaboration_hold' where id = sB;
  insert into public.supplier_collaboration (lead_id, consecutive_ignored, total_ignored, warned_at, held_at)
  values (sB, 3, 4, now() - interval '5 days', now() - interval '2 days');
  insert into public.supplier_availability (supplier_id, state, busy_until, set_by) values (sB, 'busy', today + 7, 'ZZ DEMO probe');
  perform set_config('session_replication_role', 'origin', true);

  -- P1
  a := public.fn_wa_context('supplier', 'zz-demo-supknown-a@example.invalid');
  codes := array(select x ->> 'code' from jsonb_array_elements(a -> 'matching' -> 'why_no_jobs') x);
  if not coalesce((a -> 'services' ->> 'confirmed')::boolean, false) then fails := fails || ' P1:confirmed'; end if;
  if (a -> 'services' -> 'trades' -> 0 ->> 'code') is distinct from 'hvac'
     or (a -> 'services' -> 'trades' -> 0 ->> 'open_to_customers') is distinct from 'false'
     or coalesce(a -> 'services' -> 'trades' -> 0 ->> 'label', '') = '' then fails := fails || ' P1:trades=' || coalesce(a -> 'services' ->> 'trades', 'null'); end if;
  if (a -> 'services' -> 'emirates_covered') is distinct from '["dubai"]'::jsonb then fails := fails || ' P1:emirates=' || coalesce(a -> 'services' ->> 'emirates_covered', 'null'); end if;
  if jsonb_array_length(coalesce(a -> 'services' -> 'services', '[]')) <> 1 then fails := fails || ' P1:services'; end if;
  if not coalesce((a -> 'matching' ->> 'receives_requests_now')::boolean, false) then fails := fails || ' P1:receives'; end if;
  if (a -> 'matching' ->> 'jobs_sent_30d') is distinct from '0' then fails := fails || ' P1:jobs30'; end if;
  if codes is distinct from array['trades_not_open_to_customers', 'no_requests_in_his_trades'] then fails := fails || ' P1:why=' || array_to_string(codes, ','); end if;
  if (a -> 'profile' ->> 'licence_expired') is distinct from 'false' or (a -> 'profile' ->> 'licence_days_left') is distinct from '200' then fails := fails || ' P1:licence'; end if;

  -- P2: a request in his trade and emirate, 3 days old, not sent to him
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at)
  values (iX, cust, 'hvac', 'Dubai', 'ZZ DEMO probe split units', 'sent', 'en', now() - interval '3 days');
  a := public.fn_wa_context('supplier', 'zz-demo-supknown-a@example.invalid');
  codes := array(select x ->> 'code' from jsonb_array_elements(a -> 'matching' -> 'why_no_jobs') x);
  if (a -> 'matching' ->> 'requests_in_his_trades_30d') is distinct from '1' then fails := fails || ' P2:demand=' || coalesce(a -> 'matching' ->> 'requests_in_his_trades_30d', 'null'); end if;
  if codes is distinct from array['trades_not_open_to_customers', 'requests_matched_others'] then fails := fails || ' P2:why=' || array_to_string(codes, ','); end if;
  if position('every approved supplier whose confirmed trade' in a::text) = 0 or position('fit what was asked best' in a::text) > 0 then fails := fails || ' P2:wording'; end if;

  -- P3: it reaches him, and he quotes
  perform set_config('session_replication_role', 'replica', true);
  insert into public.inquiry_matches (inquiry_id, supplier_id, sent_at) values (iX, sA, now() - interval '2 days');
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at)
  values (iY, cust, 'hvac', 'Dubai', 'ZZ DEMO probe second job', 'sent', 'en', now() - interval '1 day');
  insert into public.inquiry_matches (inquiry_id, supplier_id, sent_at) values (iY, sB, now() - interval '1 day');
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (iX, sA, 4200, 'submitted');
  perform set_config('session_replication_role', 'origin', true);
  select rfq_no into ref from public.inquiries where id = iX;
  a := public.fn_wa_context('supplier', 'zz-demo-supknown-a@example.invalid');
  if (a -> 'matching' ->> 'jobs_sent_30d') is distinct from '1' then fails := fails || ' P3:jobs30'; end if;
  if jsonb_array_length(a -> 'matching' -> 'why_no_jobs') <> 0 then fails := fails || ' P3:why=' || coalesce(a -> 'matching' ->> 'why_no_jobs', 'null'); end if;
  if jsonb_array_length(a -> 'recent_jobs') <> 1 or (a -> 'recent_jobs' -> 0 ->> 'job') is distinct from ref::text
     or (a -> 'recent_jobs' -> 0 ->> 'my_quote') is distinct from 'submitted' or (a -> 'recent_jobs' -> 0 ->> 'emirate') is distinct from 'Dubai'
     then fails := fails || ' P3:recent=' || coalesce(a ->> 'recent_jobs', 'null'); end if;

  -- P4
  b := public.fn_wa_context('supplier', 'zz-demo-supknown-b@example.invalid');
  codes := array(select x ->> 'code' from jsonb_array_elements(b -> 'matching' -> 'why_no_jobs') x);
  if not (codes @> array['licence_expired', 'held_for_unanswered_requests', 'strike_limit', 'marked_unavailable', 'services_not_confirmed'])
     or 'matching_paused' = any (codes) then fails := fails || ' P4:why=' || array_to_string(codes, ','); end if;
  if position(to_char(today - 10, 'DD Mon YYYY') in (b -> 'matching' ->> 'why_no_jobs')) = 0 then fails := fails || ' P4:expiry date not said'; end if;
  if (b -> 'profile' ->> 'licence_expired') is distinct from 'true' or (b -> 'profile' ->> 'licence_days_left') is distinct from '-10' then fails := fails || ' P4:licence'; end if;
  if (b -> 'matching' ->> 'receives_requests_now') is distinct from 'false' then fails := fails || ' P4:receives'; end if;
  if (b -> 'matching' -> 'collaboration' ->> 'unanswered_in_a_row') is distinct from '3' or (b -> 'matching' -> 'collaboration' ->> 'on_hold') is distinct from 'true'
     then fails := fails || ' P4:collaboration'; end if;
  if (b -> 'matching' -> 'availability' ->> 'state') is distinct from 'busy' then fails := fails || ' P4:availability'; end if;
  if jsonb_array_length(b -> 'recent_jobs') <> 1 or (b -> 'recent_jobs' -> 0 ->> 'my_quote') is not null then fails := fails || ' P4:recent'; end if;

  -- P8 (review fix): a paused reason a supplier must never be told is not repeated; a hard gate hides the demand reasons
  perform set_config('session_replication_role', 'replica', true);
  update public.leads set collaboration_hold_at = null, matching_blocked = true,
         matching_block_reason = 'Banned: sanctions screening hit confirmed (ZZ DEMO list)' where id = sB;
  perform set_config('session_replication_role', 'origin', true);
  b := public.fn_wa_context('supplier', 'zz-demo-supknown-b@example.invalid');
  codes := array(select x ->> 'code' from jsonb_array_elements(b -> 'matching' -> 'why_no_jobs') x);
  if position('sanctions' in b::text) > 0 or position('Banned' in b::text) > 0 then fails := fails || ' P8:reason leaked'; end if;
  if not ('matching_paused' = any (codes)) or position('our team will explain' in b::text) = 0 then fails := fails || ' P8:generic words'; end if;
  if (b -> 'matching' ->> 'paused_reason') is not null then fails := fails || ' P8:paused_reason'; end if;
  if codes && array['trades_not_open_to_customers', 'no_requests_in_his_trades', 'requests_matched_others'] then fails := fails || ' P8:demand beside gates=' || array_to_string(codes, ','); end if;
  perform set_config('session_replication_role', 'replica', true);
  update public.leads set matching_block_reason = 'insurance_expired' where id = sB;
  perform set_config('session_replication_role', 'origin', true);
  b := public.fn_wa_context('supplier', 'zz-demo-supknown-b@example.invalid');
  if (b -> 'matching' ->> 'paused_reason') is distinct from 'insurance_expired' or position('insurance certificate' in b::text) = 0 then fails := fails || ' P8:insurance'; end if;
  perform set_config('session_replication_role', 'replica', true);
  update public.leads set matching_block_reason = 'compliance_review' where id = sB;
  perform set_config('session_replication_role', 'origin', true);
  b := public.fn_wa_context('supplier', 'zz-demo-supknown-b@example.invalid');
  if (b -> 'matching' ->> 'paused_reason') is not null or position('compliance_review' in b::text) > 0 or position('our team will explain' in b::text) = 0 then fails := fails || ' P8:compliance_review'; end if;

  -- P5
  c := public.fn_wa_context('supplier', 'zz-demo-supknown-c@example.invalid');
  codes := array(select x ->> 'code' from jsonb_array_elements(c -> 'matching' -> 'why_no_jobs') x);
  if not (codes @> array['not_registered', 'not_approved', 'licence_not_verified', 'services_not_confirmed']) then fails := fails || ' P5:why=' || array_to_string(codes, ','); end if;

  -- P6: his reading is his own
  txt := a::text || ' ' || b::text || ' ' || c::text;
  if position('Sukayna' in txt) > 0 or position('zz-demo-supknown-buyer' in txt) > 0 or position('500000093' in txt) > 0
     or position('ZZ DEMO probe split units' in txt) > 0 then fails := fails || ' P6:customer identity'; end if;
  if position('Held Steel Rival' in a::text) > 0 or position('Polar Duct' in b::text) > 0 or position('Polar Duct' in c::text) > 0
     or position('4200' in b::text) > 0 then fails := fails || ' P6:another supplier'; end if;

  -- P7
  if has_function_privilege('anon', 'public.fn_wa_context(text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_wa_context(text,text)', 'execute') then fails := fails || ' P7:grant'; end if;

  if fails = '' then
    raise exception 'CHK<<PROBE OK: trades %, emirates %, why(A,none) %, why(B) %>>', a -> 'services' -> 'trades', a -> 'services' -> 'emirates_covered',
      jsonb_array_length(a -> 'matching' -> 'why_no_jobs'), (select string_agg(x ->> 'code', ',') from jsonb_array_elements(b -> 'matching' -> 'why_no_jobs') x);
  end if;
  raise exception 'CHK<<PROBE FAILED:%>>', coalesce(fails, ' (a check read a missing field)');
end $probe$;
