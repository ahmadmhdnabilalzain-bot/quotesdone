-- PROBE: THE FOUNDER HAS A TRACKED LINK FOR EACH SUPPLIER HE KNOWS. Assigned: marketing. Agent: marketing founder-network kit,
-- 19 Nov 2026. Pure probe: no DDL, never applied; run after the_founder_has_a_tracked_link_for_each_supplier_he_knows.sql on a
-- LOCAL Postgres 16. It always raises, so every row is rolled back. Every party is a ZZ DEMO fixture on @example.invalid; nothing
-- here sends, and the routines it calls write rows only.
-- PROBE OK only if
--   1. each named contact gets one code of the shape f + 9 hex, and the same name (any case, any spacing) gets the same code;
--      a blank name is skipped; no names is refused;
--   2. the link carries the code as its own tags, on /en/supplier and /ar/supplier;
--   3. a registration whose first touch is that link shows in v_founder_network_signups against the contact's name, and a
--      contact who has not registered shows with no company;
--   4. a founder-tagged registration whose code was never minted is listed with no contact; an ordinary tagged registration is
--      not listed at all; and no supplier referral is recorded for any of them;
--   5. fn_founder_network_forget deletes one contact's name and code, answers no_such_code for an unknown one, and leaves the
--      registration made through it (listed with no contact);
--   6. fn_marketing_founder_network_retention, after 90 days, deletes a link nobody registered through, replaces the name on a
--      registered one (the company still shows), and keeps a link made today; the daily duty is on the clock and runnable.
do $probe$
declare
  fails text := ''; j jsonb; c1 text; c2 text; c3 text; c4 text; s_a bigint; s_b bigint; s_c bigint; s_d bigint; n int;
begin
  -- 1. minting
  j := public.fn_founder_network_links(array['ZZ DEMO FNK Khalid - Gulf Steel', '  ', 'ZZ DEMO FNK Omar - Coast Joinery']);
  if not coalesce((j->>'ok')::boolean, false) or jsonb_array_length(j->'links') <> 2 then fails := fails || ' 1:mint(' || coalesce(j::text, '') || ')'; end if;
  c1 := j->'links'->0->>'link_code'; c2 := j->'links'->1->>'link_code';
  if coalesce(c1, '') !~ '^f[0-9a-f]{9}$' or coalesce(c2, '') !~ '^f[0-9a-f]{9}$' or c1 = c2 then fails := fails || ' 1:shape'; end if;
  j := public.fn_founder_network_links(array['zz demo fnk khalid - gulf steel ']);
  if j->'links'->0->>'link_code' is distinct from c1 then fails := fails || ' 1:stable(' || coalesce(j::text, '') || ')'; end if;
  select count(*) into n from public.founder_network_link where contact ilike 'ZZ DEMO FNK%';
  if n <> 2 then fails := fails || ' 1:rows=' || n; end if;
  j := public.fn_founder_network_links('{}'::text[]);
  if coalesce((j->>'ok')::boolean, true) then fails := fails || ' 1:empty_accepted'; end if;

  -- 2. the link
  j := public.fn_founder_network_links(array['ZZ DEMO FNK Khalid - Gulf Steel']);
  if j->'links'->0->>'en' is distinct from ('https://quotesdone.com/en/supplier?utm_source=founder&utm_medium=personal&utm_campaign=founder-network&utm_content=' || c1)
     or j->'links'->0->>'ar' is distinct from ('https://quotesdone.com/ar/supplier?utm_source=founder&utm_medium=personal&utm_campaign=founder-network&utm_content=' || c1)
  then fails := fails || ' 2:url(' || coalesce(j::text, '') || ')'; end if;

  -- 3. a registration through it (the same call supplier_api create_company makes with the browser's kept first touch)
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, approval_status)
  values ('ZZ DEMO FNK Gulf Steel', 'zz-demo-fnk-a@example.invalid', 'zz-demo-fnk-a@example.invalid', true, 'Dubai', '+971500000761', true, 'pending')
  returning id into s_a;
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, approval_status)
  values ('ZZ DEMO FNK Own Tag', 'zz-demo-fnk-b@example.invalid', 'zz-demo-fnk-b@example.invalid', true, 'Dubai', '+971500000762', true, 'pending')
  returning id into s_b;
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, approval_status)
  values ('ZZ DEMO FNK Social Visit', 'zz-demo-fnk-c@example.invalid', 'zz-demo-fnk-c@example.invalid', true, 'Dubai', '+971500000763', true, 'pending')
  returning id into s_c;
  j := public.fn_marketing_first_touch_record(s_a, jsonb_build_object('utm_source', 'founder', 'utm_medium', 'personal',
         'utm_campaign', 'founder-network', 'utm_content', c1, 'landing_path', '/ar/supplier', 'first_seen_at', now()));
  if not coalesce((j->>'recorded')::boolean, false) then fails := fails || ' 3:touch(' || coalesce(j::text, '') || ')'; end if;
  perform public.fn_marketing_first_touch_record(s_b, jsonb_build_object('utm_source', 'founder', 'utm_content', 'my-own-tag', 'landing_path', '/en/supplier'));
  perform public.fn_marketing_first_touch_record(s_c, jsonb_build_object('utm_source', 'linkedin', 'utm_medium', 'social', 'utm_content', c2, 'landing_path', '/en/supplier'));

  select count(*) into n from public.v_founder_network_signups
   where contact = 'ZZ DEMO FNK Khalid - Gulf Steel' and link_code = c1 and lead_id = s_a and company_name = 'ZZ DEMO FNK Gulf Steel' and is_demo;
  if n <> 1 then fails := fails || ' 3:registered_row=' || n; end if;
  select count(*) into n from public.v_founder_network_signups where contact = 'ZZ DEMO FNK Omar - Coast Joinery' and lead_id is null;
  if n <> 1 then fails := fails || ' 3:not_yet_row=' || n; end if;

  -- 4. an unminted founder tag is listed without a contact; a social visit carrying a code is not a founder registration
  select count(*) into n from public.v_founder_network_signups where contact is null and link_code = 'my-own-tag' and lead_id = s_b;
  if n <> 1 then fails := fails || ' 4:unminted=' || n; end if;
  select count(*) into n from public.v_founder_network_signups where lead_id = s_c;
  if n <> 0 then fails := fails || ' 4:social_listed=' || n; end if;
  select count(*) into n from public.supplier_referral where referred_lead_id in (s_a, s_b, s_c);
  if n <> 0 then fails := fails || ' 4:supplier_referral=' || n; end if;

  -- 5. forget
  c3 := public.fn_founder_network_links(array['ZZ DEMO FNK Said - Desert Glass'])->'links'->0->>'link_code';
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified, approval_status)
  values ('ZZ DEMO FNK Desert Glass', 'zz-demo-fnk-d@example.invalid', 'zz-demo-fnk-d@example.invalid', true, 'Dubai', '+971500000764', true, 'pending')
  returning id into s_d;
  perform public.fn_marketing_first_touch_record(s_d, jsonb_build_object('utm_source', 'founder', 'utm_medium', 'personal', 'utm_content', c3, 'landing_path', '/en/supplier'));
  j := public.fn_founder_network_forget(c3);
  if j->>'code' is distinct from 'forgotten' then fails := fails || ' 5:forget(' || coalesce(j::text, '') || ')'; end if;
  select count(*) into n from public.founder_network_link where code = c3 or contact ilike 'ZZ DEMO FNK Said%';
  if n <> 0 then fails := fails || ' 5:still_there=' || n; end if;
  j := public.fn_founder_network_forget('fzzzzzzzzz');
  if j->>'code' is distinct from 'no_such_code' then fails := fails || ' 5:unknown(' || coalesce(j::text, '') || ')'; end if;
  select count(*) into n from public.v_founder_network_signups where lead_id = s_d and contact is null;
  if n <> 1 then fails := fails || ' 5:registration_kept=' || n; end if;

  -- 6. retention: Khalid (registered) and Omar (not) made 100 days ago; Hamad made today
  c4 := public.fn_founder_network_links(array['ZZ DEMO FNK Hamad - New Today'])->'links'->0->>'link_code';
  update public.founder_network_link set created_at = now() - interval '100 days' where code in (c1, c2);
  j := public.fn_marketing_founder_network_retention();
  if not coalesce((j->>'ok')::boolean, false) then fails := fails || ' 6:run(' || coalesce(j::text, '') || ')'; end if;
  if exists (select 1 from public.founder_network_link where code = c2) then fails := fails || ' 6:unregistered_kept'; end if;
  if (select contact from public.founder_network_link where code = c1) is distinct from ('ZZ DEMO lead ' || s_a) then
    fails := fails || ' 6:name_kept(' || coalesce((select contact from public.founder_network_link where code = c1), 'gone') || ')'; end if;
  select count(*) into n from public.v_founder_network_signups where link_code = c1 and company_name = 'ZZ DEMO FNK Gulf Steel' and is_demo;
  if n <> 1 then fails := fails || ' 6:company_lost=' || n; end if;
  if not exists (select 1 from public.founder_network_link where code = c4) then fails := fails || ' 6:fresh_deleted'; end if;
  if not exists (select 1 from public.seat_duty where duty = 'marketing.founder_network_retention' and enabled and every = interval '1 day')
     or not public.fn_seat_duty_routine_exists('fn_marketing_founder_network_retention') then fails := fails || ' 6:duty'; end if;

  if coalesce(fails, 'a check wrote null') <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: one stable code per named contact; the link carries it on /en and /ar; a registration through it shows against his name, one not yet registered shows empty; an unminted founder tag is listed without a contact; a social visit is not; no supplier referral recorded; forget deletes one name and keeps the registration; after 90 days an unregistered link is deleted, a registered one loses the name, today''s stays; the daily duty is runnable>>';
end $probe$;
