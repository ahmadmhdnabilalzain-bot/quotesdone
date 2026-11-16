-- PROBE: A CUSTOMER IS ANSWERED FROM HIS WHOLE REQUEST, ON EVERY CHANNEL.
--
-- Seat: customer_support. 16 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_customer_is_answered_from_his_whole_request_on_every_channel.sql, in one rolled-back transaction on a LOCAL Postgres 16
-- built from the mirror (13 Nov 2026: nothing is rehearsed on production). It always raises, so every row below is rolled back.
-- Every party is a ZZ DEMO fixture on @example.invalid with a reserved fixture number (+971 50 000 0072); no model is called.
--
-- PROBE OK only if
--   P1 what he asked reaches every customer reading: the budget exactly as he wrote it, the required-by date and his words for
--      it, the emirate and his own site, the materials and brands he asked for, and the note he sent after the request;
--      the same in fn_wa_context (WhatsApp own record, widget) and fn_wa_fact_pack (WhatsApp fact pack);
--   P2 each live quote carries the letter the portal gives it (cheapest first, one letter per supplier, "Supplier A - Option 2"
--      for a second option of the same supplier), its price ex VAT, and with VAT as stated: added on top (price + VAT), not
--      VAT registered (the price), not stated (no total); and the same in words with its unit ("AED 4,600 before VAT, AED 230
--      VAT, AED 4,830 with VAT"), which is how the reply guard lets a reply state it;
--   P3 before the reveal no supplier name is anywhere in either reading; the quote's own words lose the supplier's own name,
--      its own brand value and an e-mail address; the sales engineer's notes ride with the quote;
--   P4 a revealed quote names its supplier; the other stays a letter and a price;
--   P5 a sanctioned supplier's sealed quote is not shown and takes no letter (the letters run A, B with no gap);
--   P6 no comparison rides in the facts (a cache row is raw model output; the portal is its one door), and every live quote
--      has its stored letter, so none is merely counted;
--   P7 an old closed request (fifth newest, completed) keeps the summary keys only;
--   P8 the 3 Nov keys keep their meaning (quotes_received counts live quotes, price_band from two sealed quotes, ref), and a
--      sanctioned supplier's sealed quote is no longer counted or averaged (three shown, three counted, not late);
--   P9 the new routines are closed to anon and authenticated;
--   P10 the request thread with a supplier (its question, his answer) rides on that supplier's quote, and on no other;
--   P11 (wave C) while a customer_matches_supplier flag is open on him, a quote on a request being checked is neither priced nor
--      lettered in either reading, only counted (quotes_being_checked), and not late; a quote he paid to reveal stays.
do $probe$
declare
  fails text := ''; o jsonb := '{}'::jsonb; v jsonb; w jsonb; r jsonb; qa jsonb; t text;
  c1 uuid := gen_random_uuid(); s1 bigint; s2 bigint; s3 bigint; s4 bigint;
  iA uuid := gen_random_uuid(); iB uuid := gen_random_uuid(); iOld uuid := gen_random_uuid();
  q1 uuid := gen_random_uuid(); q2 uuid := gen_random_uuid(); q3 uuid := gen_random_uuid(); q4 uuid := gen_random_uuid();
  q5 uuid := gen_random_uuid(); q6 uuid := gen_random_uuid();
  refA int; refB int; refOld int; f text; n int;
  ph text := 'whatsapp:+971500000072';
begin
  if exists (select 1 from public.customers c where right(regexp_replace(coalesce(c.phone, '') || ' ' || coalesce(c.whatsapp_phone, ''), '[^0-9 ]', '', 'g'), 9) = '500000072') then
    raise exception 'CHK<<PROBE FAILED: a real row already holds the fixture number>>';
  end if;
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, whatsapp_opt, signed_terms_url, locale, created_at)
  values (c1, 'ZZ DEMO Probe Buyer', 'zz-demo-casefacts-probe@example.invalid', '+971500000072', true, true, 'same', 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Glacier Cooling', 'zz-demo-cfp-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Tundra Air', 'zz-demo-cfp-s2@example.invalid') returning id into s2;
  insert into public.leads (company_name, email) values ('ZZ DEMO Banned Breeze', 'zz-demo-cfp-s3@example.invalid') returning id into s3;
  insert into public.leads (company_name, email) values ('ZZ DEMO Open Eye Security', 'zz-demo-cfp-s4@example.invalid') returning id into s4;
  insert into public.sanctions_ban (lead_id, decided_by, note) values (s3, 'ZZ DEMO probe', 'ZZ DEMO probe');

  -- three older closed requests and one completed fifth-newest, then the two live ones
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, budget, created_at)
  values (iOld, c1, 'painting', 'Dubai', 'ZZ DEMO old paint job', 'completed', 'en', 'AED 900', now() - interval '20 days');
  insert into public.inquiries (customer_id, category, emirate, summary, status, lang, created_at)
  select c1, 'cleaning', 'Dubai', 'ZZ DEMO closed ' || g, 'cancelled', 'en', now() - make_interval(days => 10 + g) from generate_series(1, 3) g;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, budget, required_by, delivery_window, spec, created_at)
  values (iA, c1, 'hvac', 'Dubai', 'ZZ DEMO three split units', 'sent', 'en', 'AED 5,000 excluding VAT', current_date + 5, 'before next Friday',
          jsonb_build_object('site_location', 'ZZ DEMO Villa 9, Al Barsha 2, Dubai',
            'customer_requirements', jsonb_build_object('version', 2, 'display', jsonb_build_object('en', jsonb_build_array(
              jsonb_build_object('key', 'material.units', 'label', 'AC units', 'value', 'Daikin'),
              jsonb_build_object('key', 'warranty', 'label', 'Warranty', 'value', 'Yes, at least 2 years'))))),
          now() - interval '2 days'),
         (iB, c1, 'cctv', 'Ajman', 'ZZ DEMO warehouse cameras', 'sent', 'en', 'USD 2,500', current_date + 9, null, '{}'::jsonb, now() - interval '1 day');
  select rfq_no into refA from public.inquiries where id = iA;
  select rfq_no into refB from public.inquiries where id = iB;
  select rfq_no into refOld from public.inquiries where id = iOld;
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select iA, s, 0.9, now() - interval '40 hours', 'ZZ DEMO probe' from unnest(array[s1, s2, s3]) s;
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select iB, s, 0.9, now() - interval '20 hours', 'ZZ DEMO probe' from unnest(array[s2, s4]) s;

  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q::text, 1, 'ZZ DEMO units and installation', b, 'ZZ-77', 'as requested', 1, 'lot', a, 0
    from (values (q1, 'Midea', 4600), (q2, 'Daikin', 4900), (q3, 'Daikin', 5200), (q4, 'Gree', 3000), (q5, null, 7400), (q6, null, 8900)) x(q, b, a);
  insert into public.quotes (id, inquiry_id, supplier_id, option_no, quote_amount, price_ex_vat, vat_treatment, vat_amount, status, created_at,
                             lead_time, warranty, validity, expires_at, payment_terms, review_notes)
  values (q1, iA, s1, 1, 4600, 4600, 'exclusive', 230, 'submitted', now() - interval '30 hours', '3 days from ZZ DEMO Glacier Cooling stock',
          '2 years Midea compressor', '30 days, sales@zz-demo-glacier.example.invalid', now() + interval '30 days', '50% advance',
          '[{"code":"brand_tier_lower","severity":"high","en":"Quotes a mid-range Chinese brand where a premium Japanese brand was asked.","ar":"يعرض علامة صينية متوسطة بدل علامة يابانية ممتازة."}]'::jsonb),
         (q2, iA, s2, 1, 4900, 4900, 'not_registered', null, 'submitted', now() - interval '29 hours', '7 days', '1 year', '15 days', now() + interval '15 days', '50% advance', null),
         (q3, iA, s1, 2, 5200, 5200, null, null, 'submitted', now() - interval '28 hours', '5 days', '2 years', '30 days', now() + interval '30 days', '50% advance', null),
         (q4, iA, s3, 1, 3000, 3000, 'exclusive', 150, 'submitted', now() - interval '27 hours', '2 days', '2 years', '30 days', now() + interval '30 days', '50% advance', null),
         (q5, iB, s4, 1, 7400, 7400, 'not_registered', null, 'submitted', now() - interval '18 hours', '4 days', '1 year', '30 days', now() + interval '30 days', '50% advance', null),
         (q6, iB, s2, 1, 8900, 8900, 'exclusive', 445, 'submitted', now() - interval '17 hours', '6 days', '2 years', '30 days', now() + interval '30 days', '50% advance', null);
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (q1, q2, q3, q4, q5, q6);
  update public.quotes set status = 'submitted' where id in (q1, q2, q3, q4, q5, q6);
  update public.inquiries set status = 'quoted' where id in (iA, iB);
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (q5, iB, s4, c1, 7400, 'paid', now() - interval '2 hours', now() + interval '6 days');
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answered_at, source)
  values (iA, null, 'note', 'ZZ DEMO two units for bedrooms, one for the living room', now() - interval '3 hours', 'rfq_note');
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, answer, source, asked_at, answered_at)
  values (iA, s2, 'question', 'ZZ DEMO is the living room unit wall-mounted or ducted?', 'Wall-mounted', 'portal', now() - interval '20 hours', now() - interval '19 hours');
  insert into public.qd_compare_cache (inquiry_id, quotes_hash, lang, analysis, created_at)
  values (iA::text, 'zz-probe-good', 'en', '{"considered":3,"bottom_line":"ZZ DEMO good reading","cheapest_label":"Supplier A","quotes":[{"label":"Supplier A","price":4600,"spec_deviation":["lower brand tier"]}]}'::jsonb, now() - interval '2 hours'),
         (iA::text, 'zz-probe-failed', 'en', '{"__failed":{"count":1,"detail":"ZZ DEMO"}}'::jsonb, now() - interval '1 hour');

  -- REVIEW 16 Nov: the portal records the letters the first time it shows the quotes (customer_api my_inquiries ->
  -- recordShown -> fn_customer_supplier_letters, arrival order, never a held or sanctioned one); the facts read only those.
  -- The sanctioned supplier is passed too: the function refuses it, as it does for any caller.
  perform public.fn_customer_supplier_letters(array[iA, iB], jsonb_build_array(
            jsonb_build_object('inquiry_id', iA, 'supplier_id', s1), jsonb_build_object('inquiry_id', iA, 'supplier_id', s2),
            jsonb_build_object('inquiry_id', iA, 'supplier_id', s3),
            jsonb_build_object('inquiry_id', iB, 'supplier_id', s4), jsonb_build_object('inquiry_id', iB, 'supplier_id', s2)), 'quote_card');
  v := public.fn_wa_context('customer', ph);
  w := public.fn_wa_fact_pack(ph);
  r := (select x from jsonb_array_elements(v -> 'inquiries') x where (x ->> 'ref')::int = refA);
  if r is null then raise exception 'CHK<<PROBE FAILED: the request is not in the own record: %>>', left(v::text, 400); end if;

  -- P1
  if r -> 'asked' ->> 'budget_as_he_stated_it' is distinct from 'AED 5,000 excluding VAT'
     or (r -> 'asked' ->> 'required_by')::date is distinct from current_date + 5
     or r -> 'asked' ->> 'when_as_he_stated_it' is distinct from 'before next Friday'
     or r -> 'asked' ->> 'site_as_he_gave_it' is distinct from 'ZZ DEMO Villa 9, Al Barsha 2, Dubai'
     or r -> 'asked' -> 'what_he_asked' -> 0 ->> 'value' is distinct from 'Daikin'
     or r -> 'changes_he_sent_after' -> 0 ->> 'text' not like 'ZZ DEMO two units for bedrooms%' then
    fails := fails || ' P1:asked(' || coalesce((r -> 'asked')::text, 'null') || ')'; end if;
  if (select x -> 'asked' from jsonb_array_elements(w -> 'identity' -> 'requests') x where (x ->> 'ref')::int = refA) is distinct from r -> 'asked' then
    fails := fails || ' P1:pack_differs'; end if;

  -- P2 (letters by price over the shown quotes: Glacier 4,600 -> A, Tundra 4,900 -> B, Glacier option 2 -> A)
  select jsonb_object_agg(x ->> 'label', jsonb_build_array(x -> 'price_ex_vat_aed', x -> 'total_with_vat_aed', x ->> 'vat_as_stated')) into qa
    from jsonb_array_elements(r -> 'quotes') x;
  if qa is null or qa -> 'Supplier A – Option 1' -> 0 <> '4600'::jsonb or qa -> 'Supplier A – Option 1' -> 1 <> '4830'::jsonb
     or qa -> 'Supplier B' -> 0 <> '4900'::jsonb or qa -> 'Supplier B' -> 1 <> '4900'::jsonb
     or qa -> 'Supplier A – Option 2' -> 0 <> '5200'::jsonb or qa -> 'Supplier A – Option 2' -> 1 <> 'null'::jsonb
     or qa -> 'Supplier A – Option 2' ->> 2 <> 'VAT not stated' then
    fails := fails || ' P2:quotes(' || coalesce(qa::text, 'null') || ')'; end if;
  t := (select x ->> 'price_as_shown' from jsonb_array_elements(r -> 'quotes') x where x ->> 'label' = 'Supplier A – Option 1');
  if t is distinct from 'AED 4,600 before VAT, AED 230 VAT, AED 4,830 with VAT' then fails := fails || ' P2:price_as_shown(' || coalesce(t, 'null') || ')'; end if;
  o := o || jsonb_build_object('P2_quotes', qa);

  -- P3
  t := (select x ->> 'lead_time_as_stated' || ' | ' || (x ->> 'warranty_as_stated') || ' | ' || (x ->> 'validity_as_stated')
          from jsonb_array_elements(r -> 'quotes') x where x ->> 'label' = 'Supplier A – Option 1');
  if t is null or t ~* 'glacier|midea|@' or t !~ 'the supplier' or t !~ 'a brand \(shown after reveal\)' then fails := fails || ' P3:words(' || coalesce(t, 'null') || ')'; end if;
  if v::text ~* 'Glacier Cooling|Tundra Air|Banned Breeze' or w::text ~* 'Glacier Cooling|Tundra Air|Banned Breeze' then fails := fails || ' P3:name_leak'; end if;
  if (select x -> 'notes_against_your_request' ->> 0 from jsonb_array_elements(r -> 'quotes') x where x ->> 'label' = 'Supplier A – Option 1') not like 'Quotes a mid-range Chinese brand%' then
    fails := fails || ' P3:notes'; end if;
  o := o || jsonb_build_object('P3_words', t);

  -- P4
  r := (select x from jsonb_array_elements(v -> 'inquiries') x where (x ->> 'ref')::int = refB);
  if (select count(*) from jsonb_array_elements(r -> 'quotes') x where x ->> 'supplier' = 'ZZ DEMO Open Eye Security' and (x ->> 'revealed')::boolean) <> 1
     or (select count(*) from jsonb_array_elements(r -> 'quotes') x where x ? 'supplier') <> 1
     or not exists (select 1 from jsonb_array_elements(r -> 'quotes') x where x ->> 'price_ex_vat_aed' = '8900' and x ->> 'total_with_vat_aed' = '9345' and x ->> 'letter' is not null) then
    fails := fails || ' P4:reveal(' || coalesce((r -> 'quotes')::text, 'null') || ')'; end if;
  if r -> 'asked' ->> 'budget_as_he_stated_it' is distinct from 'USD 2,500' then fails := fails || ' P4:usd_budget'; end if;

  -- P5
  r := (select x from jsonb_array_elements(v -> 'inquiries') x where (x ->> 'ref')::int = refA);
  if jsonb_array_length(r -> 'quotes') <> 3 or r::text like '%3000%'
     or (select string_agg(distinct x ->> 'letter', ',' order by x ->> 'letter') from jsonb_array_elements(r -> 'quotes') x) <> 'A,B'
     or exists (select 1 from public.fn_customer_quote_letters(iA) l where l.quote_id = q4) then
    fails := fails || ' P5:sanctioned(' || coalesce((r -> 'quotes')::text, 'null') || ')'; end if;

  -- P10 the request thread with a supplier rides on that supplier's quote only
  if (select x -> 'questions_and_answers' -> 0 ->> 'he_answered' from jsonb_array_elements(r -> 'quotes') x where x ->> 'label' = 'Supplier B') is distinct from 'Wall-mounted'
     or exists (select 1 from jsonb_array_elements(r -> 'quotes') x where x ->> 'label' <> 'Supplier B' and x ? 'questions_and_answers') then
    fails := fails || ' P10:thread(' || coalesce((r -> 'quotes')::text, 'null') || ')'; end if;

  -- P6
  if r ? 'comparison' or (r ->> 'quotes_not_yet_on_his_portal')::int <> 0 then
    fails := fails || ' P6:comparison(' || coalesce((r -> 'comparison')::text, 'null') || ')'; end if;

  -- P7
  r := (select x from jsonb_array_elements(v -> 'inquiries') x where (x ->> 'ref')::int = refOld);
  if r is null or r ? 'asked' or r ? 'quotes' or r ->> 'status' <> 'completed' then fails := fails || ' P7:old(' || coalesce(r::text, 'null') || ')'; end if;

  -- P8
  r := (select x from jsonb_array_elements(v -> 'inquiries') x where (x ->> 'ref')::int = refA);
  if (r ->> 'quotes_received')::int <> 3 or (r ->> 'sealed_quotes')::int <> 3 or r -> 'price_band' ->> 'average_label' <> 'about AED 5,000'
     or (r ->> 'suppliers_received')::int <> 3 or r ->> 'late' <> 'false' then
    fails := fails || ' P8:kept(' || (r - 'asked' - 'quotes' - 'comparison')::text || ')'; end if;

  -- P11 (wave C release, REVIEW_CASEFACTS item 7): while a customer_matches_supplier flag is open on him, no quote on a request
  -- being checked is priced or lettered in any reading (counted under quotes_being_checked), except one he paid to reveal
  insert into public.fraud_flags (kind, subject_type, subject_id, severity, detail, status)
  values ('customer_matches_supplier', 'customer', c1::text, 'medium', jsonb_build_object('lead_ids', jsonb_build_array(s1), 'on', jsonb_build_array('phone')), 'open');
  v := public.fn_wa_context('customer', ph);
  w := public.fn_wa_fact_pack(ph);
  r := (select x from jsonb_array_elements(v -> 'inquiries') x where (x ->> 'ref')::int = refA);
  if r is null or jsonb_array_length(coalesce(r -> 'quotes', '[]'::jsonb)) <> 0 or (r ->> 'quotes_being_checked')::int <> 3 or r -> 'price_band' <> 'null'::jsonb
     or r::text ~ '4600|4,600|4900|5200' or (r ->> 'late')::boolean then
    fails := fails || ' P11:held_shown(' || coalesce(left(r::text, 300), 'null') || ')'; end if;
  if w::text ~ '4,600|4600|4,900|5,200' then fails := fails || ' P11:pack_prices'; end if;
  r := (select x from jsonb_array_elements(v -> 'inquiries') x where (x ->> 'ref')::int = refB);
  if (select count(*) from jsonb_array_elements(r -> 'quotes') x) <> 1 or (r -> 'quotes' -> 0 ->> 'supplier') is distinct from 'ZZ DEMO Open Eye Security'
     or (r ->> 'quotes_being_checked')::int <> 1 then
    fails := fails || ' P11:paid_kept(' || coalesce(left((r -> 'quotes')::text, 300), 'null') || ')'; end if;
  delete from public.fraud_flags where kind = 'customer_matches_supplier' and subject_id = c1::text;

  -- P9
  for f in select unnest(array['public.fn_customer_quote_letters(uuid)', 'public.fn_quote_words_for_customer(text,uuid,boolean)', 'public.fn_customer_inquiry_facts(uuid,integer)', 'public.fn_aed_words(numeric)']) loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then fails := fails || ' P9:' || f; end if;
  end loop;
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname in ('fn_customer_quote_letters', 'fn_quote_words_for_customer', 'fn_aed_words')
     and not (p.prosecdef and array_to_string(p.proconfig, ',') like 'search_path=%');
  if n <> 0 then fails := fails || ' P9:definer_or_search_path'; end if;
  o := o || jsonb_build_object('letter_source', (select l.letter_source from public.fn_customer_quote_letters(iA) l limit 1));

  raise exception 'CHK<<%>>', case when fails = '' then 'PROBE OK ' else 'PROBE FAILED:' || fails || ' ' end
    || regexp_replace(o::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<uuid>', 'g');
end $probe$;
