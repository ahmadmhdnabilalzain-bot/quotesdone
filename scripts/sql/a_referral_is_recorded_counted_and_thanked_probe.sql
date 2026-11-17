-- PROBE: A REFERRAL IS RECORDED, COUNTED AND THANKED. Seats: customer_support (the customer's word), sales_engineer (the supplier's
-- link), ceo (the count). Agent: W3_PEOPLE, 16 Nov 2026. Pure probe: no DDL, never applied; run after
-- a_referral_is_recorded_counted_and_thanked.sql on a LOCAL Postgres 16. It always raises, so every row is rolled back. Every party
-- is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. only an APPROVED supplier gets a referral link; it is one stable code, carried as the link's own tags;
--   2. a registration whose first touch is that link records the referrer once; his own code, an unknown code and an ordinary
--      tagged visit record nothing (and the touch itself is still kept);
--   3. the CEO's reading counts registrations per referrer, and the channel row says the instrument is on;
--   4. a customer's "how did you hear about us" is kept, in his words, on his FIRST request only, once;
--   5. a referrer who is a customer (his verified number or address, exactly) is thanked ONCE, through the sales engineer's writer,
--      without naming the new customer; a name alone matches nobody and thanks nobody; a customer cannot refer himself.
do $probe$
declare
  fails text := ''; s_ref bigint; s_new bigint; s_self bigint; s_other bigint; s_pending bigint; j jsonb; v_code text; n int;
  c_ref uuid := gen_random_uuid(); c_new uuid := gen_random_uuid(); c_name uuid := gen_random_uuid(); c_old uuid := gen_random_uuid();
begin
  -- an approved fixture skips the registration gate (its documents are not the subject here); triggers are off for this one row only
  set local session_replication_role = replica;
  -- 17 Nov 2026: an approved fixture still carries the founder's mandatory six as evidence (a_seeded_approved_supplier_carries_
  -- the_mandatory_six.test.mjs); these storage rows are the probe's own and roll back with it
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'suppliers/zz-demo-w3r-licence.pdf'), ('supplier-docs', 'suppliers/zz-demo-w3r-profile.pdf')
  on conflict do nothing;
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_phone_verified, owner_email_verified, license_doc_path,
                            company_profile_doc_path, signed_terms_path, approval_status, verified)
  values ('ZZ DEMO W3R Referrer', 'zz-demo-w3r-a@example.invalid', 'zz-demo-w3r-a@example.invalid', true, 'Dubai', '+971500000751', true, true,
          'suppliers/zz-demo-w3r-licence.pdf', 'suppliers/zz-demo-w3r-profile.pdf', 'demo://terms', 'approved', true)
  returning id into s_ref;
  set local session_replication_role = origin;
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, approval_status)
  values ('ZZ DEMO W3R Pending', 'zz-demo-w3r-p@example.invalid', 'zz-demo-w3r-p@example.invalid', true, 'Dubai', '+971500000752', true, 'pending')
  returning id into s_pending;

  -- 1. the link
  j := public.fn_supplier_referral_link(s_pending);
  if coalesce((j->>'ok')::boolean, true) or j->>'code' is distinct from 'not_approved' then fails := fails || ' 1:unapproved(' || coalesce(j::text, '') || ')'; end if;
  j := public.fn_supplier_referral_link(s_ref);
  v_code := j->>'referral_code';
  if not coalesce((j->>'ok')::boolean, false) or v_code is null or v_code !~ '^[A-Za-z0-9._-]{6,40}$' then fails := fails || ' 1:link(' || coalesce(j::text, '') || ')'; end if;
  if coalesce(j->>'url', '') !~ ('utm_source=referral&utm_medium=supplier&utm_content=' || coalesce(v_code, '#')) then fails := fails || ' 1:url'; end if;
  if public.fn_supplier_referral_link(s_ref)->>'referral_code' is distinct from v_code then fails := fails || ' 1:not_stable'; end if;

  -- 2. a registration through it, once; his own code, an unknown code and an ordinary touch record nothing
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified)
  values ('ZZ DEMO W3R New Co', 'zz-demo-w3r-n@example.invalid', 'zz-demo-w3r-n@example.invalid', true, 'Sharjah', '+971500000753', true) returning id into s_new;
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified)
  values ('ZZ DEMO W3R Other Co', 'zz-demo-w3r-o@example.invalid', 'zz-demo-w3r-o@example.invalid', true, 'Sharjah', '+971500000754', true) returning id into s_other;
  j := public.fn_marketing_first_touch_record(s_new, jsonb_build_object('utm_source', 'referral', 'utm_medium', 'supplier', 'utm_content', v_code,
         'landing_path', '/en/supplier', 'first_seen_at', now() - interval '1 hour'));
  if not coalesce((j->>'recorded')::boolean, false) then fails := fails || ' 2:touch(' || coalesce(j::text, '') || ')'; end if;
  perform public.fn_marketing_first_touch_record(s_new, jsonb_build_object('utm_source', 'referral', 'utm_medium', 'supplier', 'utm_content', v_code));
  select count(*) into n from public.supplier_referral where referred_lead_id = s_new and referrer_lead_id = s_ref;
  if n <> 1 then fails := fails || ' 2:recorded(' || n || ')'; end if;
  perform public.fn_marketing_first_touch_record(s_ref, jsonb_build_object('utm_source', 'referral', 'utm_medium', 'supplier', 'utm_content', v_code));
  if exists (select 1 from public.supplier_referral where referred_lead_id = s_ref) then fails := fails || ' 2:self'; end if;
  perform public.fn_marketing_first_touch_record(s_other, jsonb_build_object('utm_source', 'referral', 'utm_medium', 'supplier', 'utm_content', 'zzdemonocode'));
  if exists (select 1 from public.supplier_referral where referred_lead_id = s_other) then fails := fails || ' 2:unknown_code'; end if;
  if not exists (select 1 from public.marketing_first_touch where lead_id = s_other) then fails := fails || ' 2:touch_lost'; end if;

  -- 3. the CEO reads it, per referrer; the channel is on
  j := public.fn_ceo_referrals(30);
  if coalesce((j->'suppliers'->>'registered_through_a_link')::int, 0) < 1
     or not exists (select 1 from jsonb_array_elements(j->'suppliers'->'by_referrer') x where x->>'supplier' = 'ZZ DEMO W3R Referrer' and (x->>'registered')::int = 1) then
    fails := fails || ' 3:ceo(' || coalesce(left((j->'suppliers')::text, 300), '') || ')'; end if;
  -- the channel row as production holds it (a local database built from the schema has no rows)
  insert into public.ceo_supplier_channel (channel, owner_seat, rule) values ('supplier_referral', 'sales_engineer', 'ZZ DEMO probe row')
  on conflict (channel) do nothing;
  perform public.fn_ceo_supplier_channel_measure();
  if (select state from public.ceo_supplier_channel where channel = 'supplier_referral') is distinct from 'on' then
    fails := fails || ' 3:channel(' || coalesce((select state || ': ' || state_why from public.ceo_supplier_channel where channel = 'supplier_referral'), 'no row') || ')'; end if;

  -- 4 and 5. the customer's word
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c_ref, 'ZZ DEMO W3R Referring Customer', 'zz-demo-w3r-cref@example.invalid', '+971500000755', true, true, 'demo://terms', 'en', now() - interval '90 days'),
         (c_new, 'ZZ DEMO W3R Newcomer Nadia', 'zz-demo-w3r-cnew@example.invalid', '+971500000756', true, true, 'demo://terms', 'en', now()),
         (c_name, 'ZZ DEMO W3R Name Only', 'zz-demo-w3r-cname@example.invalid', '+971500000757', true, true, 'demo://terms', 'en', now()),
         (c_old, 'ZZ DEMO W3R Old Customer', 'zz-demo-w3r-cold@example.invalid', '+971500000758', true, true, 'demo://terms', 'en', now() - interval '90 days');
  insert into public.inquiries (id, customer_id, category, emirate, summary, raw_input, scope_type, trades, spec, status, lang, created_at)
  values (gen_random_uuid(), c_old, 'plumbing', 'Dubai', 'ZZ DEMO earlier job', 'ZZ DEMO', 'single', array['plumbing'], '{}'::jsonb, 'completed', 'en', now() - interval '60 days');

  j := public.fn_customer_referral_record(c_new, 'ZZ DEMO my neighbour sent me, he used you for his AC', '050 000 0755', 'intake-zz-1');
  if not coalesce((j->>'recorded')::boolean, false) or (j->>'referrer_is_customer')::boolean is not true then fails := fails || ' 5:match(' || coalesce(j::text, '') || ')'; end if;
  j := public.fn_customer_referral_record(c_new, 'ZZ DEMO again, my neighbour', '+971500000755', 'intake-zz-2');
  if coalesce((j->>'recorded')::boolean, false) then fails := fails || ' 4:twice'; end if;
  select count(*) into n from public.notifications where type = 'customer_referral_thanks' and lower(to_email) = 'zz-demo-w3r-cref@example.invalid';
  if n <> 1 then fails := fails || ' 5:thanks(' || n || ')'; end if;
  if exists (select 1 from public.notifications where type = 'customer_referral_thanks' and (body ~* 'Nadia|Newcomer|w3r-cnew' or subject ~* 'Nadia')) then fails := fails || ' 5:named_the_new_customer'; end if;
  if (select words from public.customer_referral where customer_id = c_new) !~ 'neighbour sent me' then fails := fails || ' 4:words'; end if;

  j := public.fn_customer_referral_record(c_name, 'ZZ DEMO Ahmed sent me', null, 'intake-zz-3');
  if not coalesce((j->>'recorded')::boolean, false) or (j->>'referrer_is_customer')::boolean then fails := fails || ' 5:name_only(' || coalesce(j::text, '') || ')'; end if;
  j := public.fn_customer_referral_record(c_ref, 'ZZ DEMO I found you myself', '+971500000755', 'intake-zz-4');
  if (j->>'referrer_is_customer')::boolean then fails := fails || ' 5:self_referral'; end if;
  j := public.fn_customer_referral_record(c_old, 'ZZ DEMO Instagram', null, 'intake-zz-5');
  if coalesce((j->>'recorded')::boolean, false) then fails := fails || ' 4:not_first_request'; end if;
  select count(*) into n from public.notifications where type = 'customer_referral_thanks';
  if n <> 1 then fails := fails || ' 5:thanks_total(' || n || ')'; end if;
  j := public.fn_ceo_referrals(30);
  if coalesce((j->'customers'->>'said_how_they_heard')::int, 0) < 3 or coalesce((j->'customers'->>'named_a_customer')::int, 0) < 1 then
    fails := fails || ' 3:ceo_customers(' || coalesce((j->'customers')::text, '') || ')'; end if;

  if coalesce(fails, 'a check wrote null') <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: approved-only stable link; a registration through it recorded once, never his own or an unknown code; the CEO counts per referrer and the channel is on; the customer''s word kept once on his first request; a customer referrer thanked once without naming the newcomer; a name alone thanks nobody>>';
end $probe$;
