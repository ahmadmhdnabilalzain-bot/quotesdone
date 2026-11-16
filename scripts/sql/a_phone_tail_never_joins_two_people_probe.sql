-- a_phone_tail_never_joins_two_people_probe.sql — a PURE probe (customer_support, agent PROFILE_SPLIT, 16 Nov 2026). It always
-- raises CHK<<...>>, so every row it writes rolls back. Its people are ZZ DEMO with @example.invalid addresses, created here; the
-- UAE numbers are reserved fixtures (+971 50 000 00xx) and their twins carry country code 999, which no country has: nothing it
-- writes could reach a real person even if it committed. Run after a_phone_tail_never_joins_two_people.sql, in the same
-- rolled-back transaction (node scripts/ci/rehearse_sql.mjs <file> <probe>, LOCAL Postgres 16 only).
-- Proves:
--   1. two customers whose phones share the last nine digits (+971 / +999) and whose e-mails differ get two profiles; the
--      second's open cases do not list the first's case; the IT engineer has the collision; each verified number names its own
--      owner; the same with no accounts (an address and a number each);
--   2. two unnamed WhatsApp handsets on one tail in two countries are two profiles; the same handset again is the same one;
--   3. an unverified handset never selects the named customer whose phone tail it shares;
--   4. a supplier holding an address another supplier's profile carries is kept apart and recorded;
--   5. ONE PERSON ACROSS CHANNELS STAYS ONE: a WhatsApp handset, then the customer with that verified number by e-mail, then
--      WhatsApp again (phone only, as the case read asks) all read one profile and its case;
--   6. a tail two profiles share is not owed to the catch-up (it reads turns by tail);
--   7. the WhatsApp reply's timeline names the confirmed owner only; an unverified number reads only its own exchanges;
--   8. the repair: the finder flags a profile holding two handsets; the split's dry run changes nothing, the real run moves
--      the named case and its owner keeps the rest; the new routines are service_role only.
do $probe$
declare
  v_a uuid; v_b uuid; v_e uuid; v_f uuid; v_l1 bigint; v_l2 bigint;
  pa bigint; pb bigint; pc bigint; pd bigint; q1 bigint; q2 bigint; q1b bigint; pe bigint; he bigint; pl1 bigint; pl2 bigint;
  qf bigint; pf_mail bigint; pf_wa bigint; z bigint; z2 bigint;
  v_ref_a text; v_ref_e text; v_ref_f text; v_ref_q1 text; r jsonb; v_owner text; n int;
begin
  update public.decision_policy set value = 'true'::jsonb where key = 'demo_rehearsal_active';

  -- 1. two customers, one tail, two countries, two e-mails
  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt)
  values ('ZZ DEMO tail A', 'zz-tail-a@example.invalid', '+971500000091', true, 'same') returning id into v_a;
  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt)
  values ('ZZ DEMO tail B', 'zz-tail-b@example.invalid', '+999500000091', true, 'same') returning id into v_b;
  pa := public.fn_support_profile_resolve('customer', v_a::text, null, null);
  v_ref_a := public.fn_support_case_route(pa, 'new', null, 'widget', 'ZZ DEMO A wants 12 windows', 'en') ->> 'case_ref';
  perform public.fn_support_case_summary_write(v_ref_a, 0, '{"asked":"windows","said_or_did":"asked sizes","promised":[],"open":[]}',
    'ASKED: ZZ DEMO windows', 'ZZ DEMO windows', 'customer_support', 'probe');
  pb := public.fn_support_profile_resolve('customer', v_b::text, null, null);
  if pb = pa then raise exception 'CHK<<PROBE FAILED (1): two customers sharing a phone tail resolved to ONE profile %>>', pa; end if;
  r := public.fn_support_open_cases('customer', v_b::text, null, null);
  if (r ->> 'profile')::bigint = pa or exists (select 1 from jsonb_array_elements(r -> 'cases') c where c ->> 'case_ref' = v_ref_a) then
    raise exception 'CHK<<PROBE FAILED (1): B is handed A''s case: %>>', r;
  end if;
  if public.fn_support_profile_resolve('customer', v_a::text, null, null) <> pa then
    raise exception 'CHK<<PROBE FAILED (1): A no longer finds his own profile>>';
  end if;
  if not exists (select 1 from public.it_engineer_finding f where f.issue_key = 'customer_support:profile_identity_collision:' || pb
                    and f.evidence ->> 'key' = 'phone_tail' and f.evidence -> 'kept_apart_from' @> to_jsonb(pa)) then
    raise exception 'CHK<<PROBE FAILED (1): the collision was not recorded for the IT engineer>>';
  end if;
  select string_agg(o.customer_id::text, ',') into v_owner from public.fn_whatsapp_owner('whatsapp:+999500000091') o;
  if v_owner is distinct from v_b::text then raise exception 'CHK<<PROBE FAILED (1): +999 names % not B>>', v_owner; end if;
  select string_agg(o.customer_id::text, ',') into v_owner from public.fn_whatsapp_owner('+971500000091') o;
  if v_owner is distinct from v_a::text then raise exception 'CHK<<PROBE FAILED (1): +971 names % not A>>', v_owner; end if;
  pc := public.fn_support_profile_resolve('unknown', null, 'zz-tail-c@example.invalid', '+971500000092');
  pd := public.fn_support_profile_resolve('unknown', null, 'zz-tail-d@example.invalid', '+999500000092');
  if pc = pd then raise exception 'CHK<<PROBE FAILED (1): two addresses with one phone tail resolved to ONE profile>>'; end if;

  -- 2. two unnamed handsets, one tail, two countries
  q1 := public.fn_support_profile_resolve('unknown', null, null, 'whatsapp:+971500000093');
  q2 := public.fn_support_profile_resolve('unknown', null, null, 'whatsapp:+999500000093');
  q1b := public.fn_support_profile_resolve('unknown', null, null, 'whatsapp:+971500000093');
  if q1 = q2 then raise exception 'CHK<<PROBE FAILED (2): two handsets in two countries are one profile>>'; end if;
  if q1b <> q1 then raise exception 'CHK<<PROBE FAILED (2): the same handset found another profile>>'; end if;

  -- 3. an unverified handset does not select the named customer on its tail
  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt)
  values ('ZZ DEMO tail E', 'zz-tail-e@example.invalid', '+971500000094', false, 'same') returning id into v_e;
  pe := public.fn_support_profile_resolve('customer', v_e::text, null, null);
  v_ref_e := public.fn_support_case_route(pe, 'new', null, 'portal', 'ZZ DEMO E asks about a refund', 'en') ->> 'case_ref';
  he := public.fn_support_profile_resolve('unknown', null, null, 'whatsapp:+971500000094');
  if he = pe then raise exception 'CHK<<PROBE FAILED (3): an unverified number selected the customer''s profile>>'; end if;
  if exists (select 1 from jsonb_array_elements(public.fn_support_open_cases('unknown', null, null, 'whatsapp:+971500000094') -> 'cases') c
              where c ->> 'case_ref' = v_ref_e) then
    raise exception 'CHK<<PROBE FAILED (3): the unverified handset reads the customer''s case>>';
  end if;

  -- 4. two suppliers, one e-mail
  -- (leads.email is unique, so the address first moves: L1's profile keeps it, and L2 now holds it)
  insert into public.leads (company_name, email) values ('ZZ DEMO tail L1', 'zz-tail-l@example.invalid') returning id into v_l1;
  pl1 := public.fn_support_profile_resolve('supplier', v_l1::text, null, null);
  update public.leads set email = 'zz-tail-l1-new@example.invalid' where id = v_l1;
  insert into public.leads (company_name, email) values ('ZZ DEMO tail L2', 'zz-tail-l@example.invalid') returning id into v_l2;
  pl2 := public.fn_support_profile_resolve('supplier', v_l2::text, null, null);
  if pl1 = pl2 then raise exception 'CHK<<PROBE FAILED (4): two suppliers with one e-mail are one profile>>'; end if;
  if not exists (select 1 from public.it_engineer_finding f where f.issue_key = 'customer_support:profile_identity_collision:' || pl2
                    and f.evidence ->> 'key' = 'email') then
    raise exception 'CHK<<PROBE FAILED (4): the e-mail collision was not recorded>>';
  end if;

  -- 5. one person across channels: WhatsApp first, then e-mail as a customer with that verified number, then WhatsApp again
  r := public.fn_support_touch('whatsapp', 'in', 'unknown', null, null, 'whatsapp:+971500000095', 'ZZ DEMO I need a plumber', null, 'en');
  v_ref_f := r ->> 'case_ref';
  qf := public.fn_support_profile_resolve('unknown', null, null, 'whatsapp:+971500000095');
  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt)
  values ('ZZ DEMO tail F', 'zz-tail-f@example.invalid', '+971500000095', true, 'same') returning id into v_f;
  r := public.fn_support_touch('email', 'in', 'customer', v_f::text, 'zz-tail-f@example.invalid', null, 'ZZ DEMO about my plumber request', null, 'en');
  pf_mail := public.fn_support_profile_resolve('customer', v_f::text, 'zz-tail-f@example.invalid', null);
  pf_wa := public.fn_support_profile_resolve('unknown', null, null, 'whatsapp:+971500000095');
  if v_ref_f is null or pf_mail <> qf or pf_wa <> qf or r ->> 'case_ref' is distinct from v_ref_f then
    raise exception 'CHK<<PROBE FAILED (5): one person across channels is not one profile and one case: wa % mail % wa-again % (case % then %)>>',
      qf, pf_mail, pf_wa, v_ref_f, r ->> 'case_ref';
  end if;
  if not exists (select 1 from public.support_customer_profile p where p.id = qf and p.customer_id = v_f and p.email = 'zz-tail-f@example.invalid'
                    and p.phone_prefix = '971') then
    raise exception 'CHK<<PROBE FAILED (5): the handset''s profile did not take the customer''s name>>';
  end if;
  if not exists (select 1 from jsonb_array_elements(public.fn_support_open_cases('visitor', null, null, 'whatsapp:+971500000095') -> 'cases') c
                  where c ->> 'case_ref' = v_ref_f) then
    raise exception 'CHK<<PROBE FAILED (5): the WhatsApp case read (phone only) does not find the person''s case>>';
  end if;

  -- 6. a tail two profiles share is not owed to the catch-up
  insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, created_at, meta)
  values ('whatsapp:+971500000093', 'whatsapp:+12183166814', 'ZZ DEMO', 'ZZ DEMO I need 12 windows', 'ZZ DEMO what sizes?', 'en', false, false,
          now() - interval '10 minutes', jsonb_build_object('stage', 'handled', 'probe', true, 'send_error', 'captured: reserved fixture mobile'));
  select c.case_ref into v_ref_q1 from public.support_case c where c.customer_profile_id = q1 and c.state <> 'closed' order by c.case_id desc limit 1;
  if v_ref_q1 is null then raise exception 'CHK<<PROBE FAILED (6): the handset''s message opened no case on its profile>>'; end if;
  update public.support_case set last_inbound_at = now() - interval '10 minutes', last_channel = 'whatsapp' where case_ref = v_ref_q1;
  if exists (select 1 from jsonb_array_elements(public.fn_support_case_summaries_owed(20)) e where e ->> 'case_ref' = v_ref_q1) then
    raise exception 'CHK<<PROBE FAILED (6): a tail two profiles share is owed to the catch-up (it would read both people''s turns)>>';
  end if;

  -- 7. the reply's timeline: the confirmed owner only
  if not (public.fn_contact_timeline('+971500000094', 5) -> 'customer_ids') @> to_jsonb(v_e::text) then
    raise exception 'CHK<<PROBE FAILED (7): the fixture did not reproduce the timeline''s tail match>>';
  end if;
  r := public.fn_contact_timeline_for_sender('whatsapp:+971500000094', 5);
  if (r ->> 'known')::boolean or r -> 'customer_ids' <> '[]'::jsonb then
    raise exception 'CHK<<PROBE FAILED (7): an unverified number reads the customer''s timeline: %>>', r -> 'customer_ids';
  end if;
  r := public.fn_contact_timeline_for_sender('whatsapp:+971500000095', 5);
  if r -> 'customer_ids' <> jsonb_build_array(v_f::text) then
    raise exception 'CHK<<PROBE FAILED (7): the confirmed owner''s timeline is not his own: %>>', r -> 'customer_ids';
  end if;
  r := public.fn_contact_timeline_for_sender('zz-tail-a@example.invalid', 5);
  if not (r -> 'customer_ids') @> to_jsonb(v_a::text) then raise exception 'CHK<<PROBE FAILED (7): an e-mail timeline changed>>'; end if;

  -- 8. the repair. A profile joined before today: two handsets of two countries on one unnamed profile.
  insert into public.support_customer_profile (party_kind, phone_tail, created_at) values ('unknown', '500000096', now() - interval '1 hour')
  returning id into z;
  insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, created_at, meta)
  values ('whatsapp:+971500000096', 'whatsapp:+12183166814', 'ZZ DEMO', 'ZZ DEMO hello', null, 'en', false, false, now(), '{"probe":true}'),
         ('whatsapp:+999500000096', 'whatsapp:+12183166814', 'ZZ DEMO', 'ZZ DEMO hi', null, 'en', false, false, now(), '{"probe":true}');
  z2 := public.fn_support_profile_resolve('unknown', null, null, 'whatsapp:+999500000096');
  if z2 = z then raise exception 'CHK<<PROBE FAILED (8): the second country''s handset joined the first''s profile>>'; end if;
  r := public.fn_support_profile_collisions();
  if not exists (select 1 from jsonb_array_elements(r -> 'items') i where (i ->> 'profile_id')::bigint = z
                    and i -> 'reasons' ? 'two_country_prefixes_on_one_tail') then
    raise exception 'CHK<<PROBE FAILED (8): the finder does not flag a profile holding two handsets: %>>', r;
  end if;
  if exists (select 1 from jsonb_array_elements(r -> 'items') i where (i ->> 'profile_id')::bigint in (pa, pb, qf)) then
    raise exception 'CHK<<PROBE FAILED (8): the finder flags a profile that holds one person>>';
  end if;
  -- the split: the portal case on E's profile is (says the reviewer) the unverified handset's
  r := public.fn_support_profile_split(pe, array[v_ref_e], 'unknown', null, null, '+971500000094', '', 'probe');
  if (r ->> 'ok')::boolean then raise exception 'CHK<<PROBE FAILED (8): a split without a reviewer ran>>'; end if;
  r := public.fn_support_profile_split(pe, array[v_ref_e], 'unknown', null, null, '+971500000094', 'ZZ DEMO probe reviewer', 'probe');
  if not (r ->> 'ok')::boolean or not (r ->> 'dry_run')::boolean
     or (select customer_profile_id from public.support_case where case_ref = v_ref_e) <> pe then
    raise exception 'CHK<<PROBE FAILED (8): the dry run changed something or refused: %>>', r;
  end if;
  r := public.fn_support_profile_split(pe, array[v_ref_e], 'unknown', null, null, '+971500000094', 'ZZ DEMO probe reviewer', 'probe', false);
  if not (r ->> 'ok')::boolean or (select customer_profile_id from public.support_case where case_ref = v_ref_e) = pe
     or (select customer_profile_id from public.support_case where case_ref = v_ref_e) <> (r ->> 'target_profile')::bigint
     or not exists (select 1 from public.support_customer_profile p where p.id = pe and p.customer_id = v_e)
     or not exists (select 1 from public.agent_actions a where a.id = (r ->> 'action_id')::bigint and a.kind = 'support_profile_split') then
    raise exception 'CHK<<PROBE FAILED (8): the split did not move the case or took E''s name: %>>', r;
  end if;
  r := public.fn_support_profile_split(pa, array['QD-NOT-A-CASE'], 'unknown', null, null, '+999500000091', 'ZZ DEMO probe reviewer', 'probe', false);
  if (r ->> 'ok')::boolean then raise exception 'CHK<<PROBE FAILED (8): a split of a case not on the profile ran>>'; end if;

  select count(*) into n from unnest(array['public.fn_phone_prefix(text)', 'public.fn_contact_timeline_for_sender(text,integer)',
    'public.fn_support_profile_collisions()', 'public.fn_support_profile_split(bigint,text[],text,text,text,text,text,text,boolean)',
    'public.fn_support_profile_resolve(text,text,text,text)', 'public.fn_whatsapp_owner(text,boolean)',
    'public.fn_support_case_summaries_owed(integer)']) f
   where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
      or not has_function_privilege('service_role', f, 'execute');
  if n > 0 then raise exception 'CHK<<PROBE FAILED: % routine(s) open to anon/authenticated or closed to service_role>>', n; end if;
  if public.fn_phone_prefix('+971 50 000 0091') <> '971' or public.fn_phone_prefix('00971500000091') <> '971'
     or public.fn_phone_prefix('+9710500000091') <> '971' or public.fn_phone_prefix('0500000091') is not null
     or public.fn_phone_prefix('500000091') is not null then
    raise exception 'CHK<<PROBE FAILED: fn_phone_prefix reads a number wrongly>>';
  end if;

  raise exception 'CHK<<PROBE OK: one tail, two people -> % and %; two handsets -> % and %; one person on three channels -> %; split moved % off %>>',
    pa, pb, q1, q2, qf, v_ref_e, pe;
end
$probe$;
