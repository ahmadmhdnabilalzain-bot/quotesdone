-- PROBE: A CUSTOMER ASKING ON WHATSAPP READS THEIR OWN REQUESTS, AND EVERY ASK CLOSES ITS LOOP.
--
-- Seat: customer_support. 3 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop.sql (apply-on-merge runs both in one
-- rolled-back transaction, then the probe alone after the apply). It always raises, so every row below is rolled back, and
-- pg_net sends only committed requests, so nothing reaches a person. Every party is a ZZ DEMO fixture on @example.invalid
-- and the reserved +97150000012x numbers; qd.probe_files_demo_handoff (local to this transaction) lets the seat handoffs be
-- filed for them. No model is called: the reasoned intent is passed as the classifier would give it.
--
-- The fixtures are written the way the real paths write them: customer A confirmed WhatsApp = the verified mobile
-- (kyc verify_sms -> phone_verified, whatsapp_choose 'same'); customer B confirmed ANOTHER number (whatsapp_verify ->
-- opt 'other', whatsapp_phone, whatsapp_verified_at); C has the number in customers.phone and never confirmed it.
-- A1 and A2 were sent to three suppliers 30 hours ago (inquiry_matches.sent_at), so both are past the 24 h quote time.
--
-- PROBE OK only if
--   1. every format of A's number identifies the customer; A's context carries A1's ref, status, 3 suppliers, 2 quotes and
--      a rounded band, and no quote amount and no supplier name; the status question (EN and AR) answers from it;
--   L1 the late requests open inquiry.status_chase to the sales engineer, the supplier who had not quoted is reminded, and
--      customer_support closes each only after telling the customer (a quote arrived -> WhatsApp; the dated update -> email);
--   2. after a reveal of ONE quote, that quote's supplier and amount are shown and the others stay sealed;
--   3. B sees none of A's rows; C (number never confirmed) is unknown everywhere, the fact pack included;
--   4. both of A's requests are listed, the cancelled one with its status;
--   L2 a change reaches every matched supplier with the phone number removed and is confirmed back;
--   L4 a cancel without its number asks for it; with it, the request is cancelled, 3 suppliers and the customer are told;
--   L3 "talk to a person" is filed, followed up at 23 h by email when the WhatsApp window has closed, and reported to the CEO;
--   5. the founder's number is the founder even when a customer row confirms it (compared in SQL, printed as a boolean).
-- and, for the independent review of #1844 (each case fails against the routines as they stood at f6fb0d8f):
--   R1 a change's supplier copy loses the first name alone, the UPPERCASE name, a landline and a bare domain (EN and AR);
--   R2 a buyer asking my_documents gets their own file, never the supplier template's {{slots}};
--   R3 a second ask after midnight reuses the open chase; a quote the platform already announced closes it with no send;
--   R4 the same change sent twice is filed and mailed once;
--   R5 a cancel is only asked; a later "yes <ref>" (Arabic-Indic digits, any intent) cancels it; another ref does not;
--   R6 a follow-up with no channel leaves the chase pending, three failures file an it_engineer finding;
--   R7 a 19-digit IBAN in the message neither overflows nor hides the request number after it;
--   R8 one sealed quote gives no band; an average under AED 1,000 reads "under AED 1,000";
--   R9 a revealed supplier under a sanctions ban is never named;
--   R13 a supplier invited under 2 hours ago is not reminded; the Arabic path asks quoted suppliers to confirm or revise and
--       claims no count before sending; a change to a request with no supplier says it waits for the match;
--   R14 the founder's 23-hour alert no longer tells him to email them.
do $probe$
declare
  fails text := ''; o jsonb := '{}'::jsonb; v jsonb; r jsonb; t text;
  cA uuid := gen_random_uuid(); cB uuid := gen_random_uuid(); cC uuid := gen_random_uuid(); cF uuid := gen_random_uuid();
  s1 bigint; s2 bigint; s3 bigint; s4 bigint; i1 uuid := gen_random_uuid(); i2 uuid := gen_random_uuid(); i3 uuid := gen_random_uuid();
  i5 uuid := gen_random_uuid(); q1 uuid := gen_random_uuid(); q2 uuid := gen_random_uuid(); q3 uuid := gen_random_uuid();
  q4 uuid := gen_random_uuid(); q5 uuid := gen_random_uuid();
  ref1 int; ref2 int; ref3 int; ref5 int; h1 bigint; h2 bigint; h3 bigint; f text; n int;
  pA text := 'whatsapp:+971500000123'; pB text := 'whatsapp:+971500000124';
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  if exists (select 1 from public.customers c where right(regexp_replace(coalesce(c.phone, '') || ' ' || coalesce(c.whatsapp_phone, ''), '[^0-9 ]', '', 'g'), 9) in ('500000123', '500000124', '500000125'))
     or exists (select 1 from public.leads l where right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9) in ('500000123', '500000124', '500000125')) then
    raise exception 'CHK<<PROBE FAILED: a real row already holds a fixture number>>';
  end if;

  -- the parties, as sign-up writes them
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, whatsapp_opt, signed_terms_url, locale, created_at)
  values (cA, 'ZZ DEMO Khalid Mansoori', 'zz-demo-wa-a@example.invalid', '+971500000123', true, true, 'same', 'demo://terms', 'en', now() - interval '5 days'),
         (cB, 'ZZ DEMO Customer B', 'zz-demo-wa-b@example.invalid', '+971500000199', true, true, 'other', 'demo://terms', 'en', now() - interval '5 days'),
         (cC, 'ZZ DEMO Customer C', 'zz-demo-wa-c@example.invalid', '+971500000125', false, true, null, null, 'en', now() - interval '5 days');
  update public.customers set whatsapp_phone = '+971500000124', whatsapp_verified_at = now() - interval '4 days' where id = cB;
  insert into public.leads (company_name, email) values ('ZZ DEMO Supplier One', 'zz-demo-wa-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Supplier Two', 'zz-demo-wa-s2@example.invalid') returning id into s2;
  insert into public.leads (company_name, email) values ('ZZ DEMO Supplier Three', 'zz-demo-wa-s3@example.invalid') returning id into s3;
  insert into public.leads (company_name, email) values ('ZZ DEMO Supplier Four', 'zz-demo-wa-s4@example.invalid') returning id into s4;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at)
  values (i1, cA, 'Electrical', 'Dubai', 'ZZ DEMO rewire a villa', 'sent', 'en', now() - interval '31 hours'),
         (i2, cA, 'Plumbing', 'Sharjah', 'ZZ DEMO replace water heaters', 'sent', 'en', now() - interval '31 hours');
  select rfq_no into ref1 from public.inquiries where id = i1;
  select rfq_no into ref2 from public.inquiries where id = i2;
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select i, s, 0.9, now() - interval '30 hours', 'ZZ DEMO probe' from unnest(array[i1, i2]) i, unnest(array[s1, s2, s3]) s;
  -- complete quotes, as supplier_api submits them: itemised lines and every term, so trg_quote_quality lets them stand
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q::text, 1, 'ZZ DEMO cable and labour', 'ZZ DEMO Brand', 'ZZ-1', '4 mm2 copper, PVC', 1, 'lot', a, 1000
    from (values (q1, 12400), (q2, 15800), (q3, 14100)) x(q, a);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  values (q1, i1, s1, 12400, 'submitted', now() - interval '20 hours', '1 year', '2 weeks', '50% advance', 'civil works', '30 days'),
         (q2, i1, s2, 15800, 'submitted', now() - interval '10 hours', '1 year', '2 weeks', '50% advance', 'civil works', '30 days');
  -- held by the quality gate (the category's specs are not stated): released as fn_sales_engineer_quote_quality_tick
  -- releases a hold whose hours have passed, so the quotes stand as the customer's portal shows them
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (q1, q2);
  update public.quotes set status = 'submitted' where id in (q1, q2);
  update public.inquiries set status = 'quoted' where id = i1;
  if (select count(*) from public.quotes where inquiry_id = i1 and status = 'submitted') <> 2 then
    raise exception 'CHK<<PROBE FAILED: the fixture quotes did not stand (%)>>', (select jsonb_agg(status) from public.quotes where inquiry_id = i1);
  end if;

  -- 1. IDENTITY in four formats, and the context
  for f in select unnest(array['whatsapp:+971500000123', '+971500000123', '971500000123', '0500000123']) loop
    if public.fn_identify_contact(f)->>'audience' is distinct from 'customer' then fails := fails || ' 1:identify(' || f || ')'; end if;
  end loop;
  v := public.fn_wa_context('customer', pA);
  r := (select x from jsonb_array_elements(v->'inquiries') x where (x->>'ref')::int = ref1);
  if r is null or r->>'status' <> 'quoted' or (r->>'suppliers_received')::int <> 3 or (r->>'quotes_received')::int <> 2
     or (r->'price_band'->>'average_rounded_to_nearest_1000')::numeric <> 14000 or r->'price_band'->>'average_label' <> 'about AED 14,000'
     or r->>'late' <> 'true' then
    fails := fails || ' 1:context(' || coalesce(r::text, 'no A1') || ')'; end if;
  if v::text ~ '12400|15800|Supplier One|Supplier Two|Supplier Three' then fails := fails || ' 1:pre_reveal_leak'; end if;
  o := o || jsonb_build_object('case1_context_A1', r - 'id');

  -- R2. a buyer's own documents, never the supplier template
  v := public.fn_wa_route(pA, 'which documents do you still need from me?', false, false, 'my_documents');
  t := v->>'deterministic_reply';
  if t is null or t like '%{{%' or t not like '%buyer account file%' or t like '%company_name%' then fails := fails || ' R2(' || coalesce(t, 'null') || ')'; end if;
  o := o || jsonb_build_object('R2_my_documents', t);

  -- 1 + L1. the status question, EN and AR, with the intent the classifier gives
  v := public.fn_wa_route(pA, 'what''s happening with my inquiry?', false, false, 'my_requests');
  t := v->>'deterministic_reply';
  if v->>'deterministic_intent' <> 'my_requests' or t not like '%Request ' || ref1 || '%2 quote(s) so far%' or t not like '%Request ' || ref2 || '%0 quote(s)%'
     or t not like '%asked our sales engineer to chase it%' or t not like '%average about AED 14,000 (rounded)%' then fails := fails || ' 1:reply_en(' || coalesce(t, 'null') || ')'; end if;
  if v->'fact_pack'->'identity'->>'kind' <> 'customer' or (v->'fact_pack')::text like '%no job status can be given%' then fails := fails || ' 1:fact_pack'; end if;
  if v::text ~ '12400|15800|Supplier One|Supplier Two' then fails := fails || ' 1:route_leak'; end if;
  o := o || jsonb_build_object('case1_reply_en', t, 'case1_pack_identity_kind', v->'fact_pack'->'identity'->>'kind',
                               'case1_pack_unknown', v->'fact_pack'->'unknown');
  v := public.fn_wa_route(pA, 'وين وصل طلبي؟', false, false, 'my_requests');
  if v->>'needs_model' <> 'true' or v->>'deterministic_reply' not like '%Request ' || ref1 || '%' or v->>'deterministic_reply' not like '%sales engineer%' then
    fails := fails || ' 1:reply_ar(' || coalesce(v->>'deterministic_reply', 'null') || ')'; end if;
  o := o || jsonb_build_object('case1_reply_ar_facts', v->>'deterministic_reply', 'case1_ar_needs_model', v->'needs_model');

  select id into h1 from public.agent_actions where kind = 'handoff' and target_id like 'inquiry.status_chase:' || i1 || ':%';
  select id into h2 from public.agent_actions where kind = 'handoff' and target_id like 'inquiry.status_chase:' || i2 || ':%';
  select count(*) into n from public.agent_actions where kind = 'handoff' and detail->>'type' = 'inquiry.status_chase' and detail->>'inquiry_id' in (i1::text, i2::text);
  if h1 is null or h2 is null or n <> 2 then fails := fails || ' L1:handoffs(' || n || ')'; end if;
  select jsonb_build_object('status', status, 'from', detail->>'from', 'to', agent, 'chased', evidence->'chased', 'quoted', evidence->'suppliers_quoted',
                            'waiting', evidence ? 'waiting') into r from public.agent_actions where id = h1;
  if r->>'status' <> 'pending' or (r->>'quoted')::int <> 2 or r->>'waiting' <> 'true' then fails := fails || ' L1:h1(' || r::text || ')'; end if;
  -- A1 lacks s3's quote, A2 lacks all three: each supplier is reminded exactly ONCE across both (ruling 1209)
  select count(*) into n from public.notifications where type = 'rfq_quote_reminder' and lead_id in (s1, s2, s3);
  if n <> 3 or (select count(distinct lead_id) from public.notifications where type = 'rfq_quote_reminder' and lead_id in (s1, s2, s3)) <> 3
     or (select sum((evidence->>'chased')::int) from public.agent_actions where id in (h1, h2)) <> 3 then
    fails := fails || ' L1:reminders(' || n || ')'; end if;
  o := o || jsonb_build_object('L1_h1', r, 'L1_h2', (select evidence - 'inquiry_id' - 'cites_note' from public.agent_actions where id = h2),
                               'L1_reminder_rows', n);

  -- R3. the same question after midnight: the first chases' keys are made yesterday's, and the open chase is reused
  update public.agent_actions set target_id = 'inquiry.status_chase:' || (detail->>'inquiry_id') || ':20000101',
                                  created_at = created_at - interval '9 hours' where id in (h1, h2);
  v := public.fn_wa_route(pA, 'any news on my requests?', false, false, 'my_requests');
  select count(*) into n from public.agent_actions where kind = 'handoff' and detail->>'type' = 'inquiry.status_chase' and detail->>'inquiry_id' in (i1::text, i2::text);
  if n <> 2 or v->>'deterministic_reply' not like '%has been chasing it since%' then
    fails := fails || ' R3:second_ask(' || n || ' / ' || coalesce(v->>'deterministic_reply', 'null') || ')'; end if;
  o := o || jsonb_build_object('R3_second_ask_chases', n, 'R3_second_ask_reply', v->>'deterministic_reply');

  -- nothing new yet: both stay open
  v := public.fn_customer_support_closes_status_chases();
  if (select status from public.agent_actions where id = h1) <> 'pending' then fails := fails || ' L1:closed_too_early'; end if;
  -- the third supplier quotes; A2's dated update falls due - while A has NO email on file (R6)
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  values (q3, i1, s3, 14100, 'submitted', now() + interval '1 minute', '1 year', '2 weeks', '50% advance', 'civil works', '30 days');
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = q3;
  update public.quotes set status = 'submitted' where id = q3;
  update public.agent_actions set evidence = evidence || jsonb_build_object('next_update_by', now() - interval '1 minute') where id = h2;
  update public.customers set email = null where id = cA;
  v := public.fn_customer_support_closes_status_chases();
  v := public.fn_customer_support_closes_status_chases();
  v := public.fn_customer_support_closes_status_chases();
  v := public.fn_customer_support_closes_status_chases();
  select jsonb_build_object('h2_status', status, 'attempts', detail->'followup_attempts', 'last', detail->>'followup_last_status',
           'finding', (select issue_key from public.it_engineer_finding where issue_key = 'customer_support:status_chase_followup_undelivered:' || h2),
           'fourth_run', v - 'errors')
    into r from public.agent_actions where id = h2;
  if r->>'h2_status' <> 'pending' or (r->>'attempts')::int <> 3 or r->>'last' <> 'no_channel' or r->>'finding' is null
     or (r->'fourth_run'->>'stuck_after_3_tries')::int < 1 then fails := fails || ' R6(' || r::text || ')'; end if;
  o := o || jsonb_build_object('R6_no_channel', r);
  -- the email is back and the finding's cause is cleared: the next tick tells the customer and closes it
  update public.customers set email = 'zz-demo-wa-a@example.invalid' where id = cA;
  update public.agent_actions set detail = detail - 'followup_attempts' where id = h2;
  v := public.fn_customer_support_closes_status_chases();
  select jsonb_build_object('h1', (select jsonb_build_object('status', status, 'outcome', evidence->>'outcome', 'by', evidence->>'verified_by', 'delivery', evidence->>'delivery_status') from public.agent_actions where id = h1),
                            'h2', (select jsonb_build_object('status', status, 'outcome', evidence->>'outcome', 'by', evidence->>'verified_by', 'delivery', evidence->>'delivery_status') from public.agent_actions where id = h2),
                            'followups', (select jsonb_agg(jsonb_build_object('type', type, 'channel', channel, 'status', status) order by id)
                                            from public.notifications where inquiry_id in (i1, i2) and type in ('quote_received', 'inquiry_status_update'))) into r;
  if r->'h1'->>'status' <> 'done' or r->'h1'->>'outcome' <> 'quote_arrived' or r->'h1'->>'by' <> 'customer_support' or r->'h1'->>'delivery' <> 'done'
     or r->'h2'->>'status' <> 'done' or r->'h2'->>'outcome' <> 'dated_update_sent' or r->'h2'->>'delivery' <> 'done'
     or not (r->'followups')::text like '%quote_received%whatsapp%' or not (r->'followups')::text like '%inquiry_status_update%email%'
     or (select count(*) from public.notifications where inquiry_id = i1 and type = 'quote_received') <> 1 then
    fails := fails || ' L1:close(' || r::text || ')'; end if;
  o := o || jsonb_build_object('L1_close', r, 'L1_closer', v);

  -- R1 + R13. an ARABIC change to A1 (quoted by all three), carrying the first name, the UPPERCASE name, a landline, a domain
  v := public.fn_wa_route(pA, 'طلب ' || ref1 || ': نرجو إضافة 6 نقاط كهرباء في المطبخ. KHALID هنا، تواصلوا مع Khalid على 04 345 6789 أو ٠٥٠١٢٣٤٥٦٧ أو alnoor-trading.ae', false, false, 'change_request');
  select answer_as_written into t from public.rfq_clarification where inquiry_id = i1 and kind = 'note' order by id desc limit 1;
  select count(*) into n from public.notifications where inquiry_id = i1 and type = 'rfq_addendum' and body like '%already quoted%written in Arabic%';
  if t is null or t ~* 'khalid|mansoori|345 6789|alnoor|٠٥٠١٢٣٤٥٦٧|0501234567' or t not like '%6 نقاط%' or n <> 3
     or v->>'deterministic_reply' not like '%as soon as its English copy is ready%' or v->>'deterministic_reply' not like '%the 3 who already quoted%'
     or v->>'deterministic_reply' like '%goes to the 3 supplier(s)%' then
    fails := fails || ' R1_ar(' || coalesce(t, 'no note') || ' / ' || n || ' / ' || coalesce(v->>'deterministic_reply', 'null') || ')'; end if;
  o := o || jsonb_build_object('R1_ar_note', t, 'R1_ar_quoted_told', n, 'R1_ar_reply', v->>'deterministic_reply');

  -- 2. A REVEAL OF ONE QUOTE, as reveal_sale.ts writes it
  update public.quotes set status = 'revealed' where id = q1;
  update public.inquiries set status = 'revealed' where id = i1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at, refund_deadline)
  values (q1, i1, s1, cA, 12400, 'paid', now(), now() + interval '7 days');
  v := public.fn_wa_context('customer', pA);
  r := (select x from jsonb_array_elements(v->'inquiries') x where (x->>'ref')::int = ref1);
  if r->'revealed_quotes'->0->>'supplier' <> 'ZZ DEMO Supplier One' or (r->'revealed_quotes'->0->>'amount_aed')::numeric <> 12400
     or jsonb_array_length(r->'revealed_quotes') <> 1 or (r->>'sealed_quotes')::int <> 2 or (r->>'quotes_received')::int <> 3
     or v::text ~ '15800|14100|Supplier Two|Supplier Three' then fails := fails || ' 2:reveal(' || coalesce(r::text, 'null') || ')'; end if;
  o := o || jsonb_build_object('case2_context_A1', r - 'id');

  -- 3. B and the unconfirmed C
  v := public.fn_wa_context('customer', pB);
  if v->>'known' <> 'true' or v->>'name' <> 'ZZ DEMO Customer B' or jsonb_array_length(v->'inquiries') <> 0 or v::text like '%' || ref1 || '%' then
    fails := fails || ' 3:B(' || v::text || ')'; end if;
  if public.fn_identify_contact('whatsapp:+971500000199')->>'audience' <> 'unknown' then fails := fails || ' 3:B_mobile_is_not_her_whatsapp'; end if;
  o := o || jsonb_build_object('case3_B', v - 'account');
  v := jsonb_build_object('identify', public.fn_identify_contact('whatsapp:+971500000125'),
                          'context', public.fn_wa_context('customer', 'whatsapp:+971500000125'),
                          'pack_identity', public.fn_wa_fact_pack('whatsapp:+971500000125')->'identity');
  if v->'identify'->>'audience' <> 'unknown' or v->'context'->>'known' <> 'false' or v->'pack_identity'->>'kind' <> 'unknown' then
    fails := fails || ' 3:C(' || v::text || ')'; end if;
  o := o || jsonb_build_object('case3_C', v);

  -- R8 + R13 + R3. B's request B3: late, one sealed quote; S4 was invited an hour ago
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at)
  values (i3, cB, 'Electrical', 'Abu Dhabi', 'ZZ DEMO office lighting', 'quoted', 'en', now() - interval '31 hours');
  select rfq_no into ref3 from public.inquiries where id = i3;
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  values (i3, s1, 0.9, now() - interval '30 hours', 'ZZ DEMO probe'), (i3, s2, 0.9, now() - interval '30 hours', 'ZZ DEMO probe'),
         (i3, s4, 0.9, now() - interval '1 hour', 'ZZ DEMO probe');
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q::text, 1, 'ZZ DEMO fittings and labour', 'ZZ DEMO Brand', 'ZZ-2', 'LED panel 600x600', 1, 'lot', a, 100
    from (values (q4, 600), (q5, 800)) x(q, a);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  values (q4, i3, s1, 600, 'submitted', now() - interval '20 hours', '1 year', '2 weeks', '50% advance', 'civil works', '30 days');
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = q4;
  update public.quotes set status = 'submitted' where id = q4;
  r := public.fn_customer_inquiry_facts(cB, 10) -> 0;
  if (r->>'sealed_quotes')::int <> 1 or r->'price_band' <> 'null'::jsonb or r->>'late' <> 'true' then fails := fails || ' R8:one_sealed(' || r::text || ')'; end if;
  o := o || jsonb_build_object('R8_one_sealed', r - 'id');
  v := public.fn_wa_route(pB, 'any news on my request?', false, false, 'my_requests');
  select id into h3 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'inquiry.status_chase' and detail->>'inquiry_id' = i3::text;
  select evidence into r from public.agent_actions where id = h3;
  if h3 is null or (r->>'invited_under_2_hours_ago')::int <> 1
     or exists (select 1 from public.notifications where type = 'rfq_quote_reminder' and lead_id = s4)
     or v->>'deterministic_reply' like '%AED 600%' then fails := fails || ' R13:just_invited(' || coalesce(r::text, 'no h3') || ')'; end if;
  o := o || jsonb_build_object('R13_h3_evidence', r - 'inquiry_id' - 'cites_note', 'R8_reply_one_sealed', v->>'deterministic_reply');
  -- the second quote arrives and the platform's own new-quote notice tells B; the band is "under AED 1,000"
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  values (q5, i3, s2, 800, 'submitted', now() + interval '1 minute', '1 year', '2 weeks', '50% advance', 'civil works', '30 days');
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = q5;
  update public.quotes set status = 'submitted' where id = q5;
  insert into public.notifications (type, channel, to_email, to_role, inquiry_id, quote_id, subject, body, status, created_at)
  values ('new_quote', 'email', 'zz-demo-wa-b@example.invalid', 'customer', i3, q5, 'ZZ DEMO new quote', 'ZZ DEMO new quote', 'queued', now() + interval '1 minute');
  r := public.fn_customer_inquiry_facts(cB, 10) -> 0;
  if r->'price_band'->>'average_label' <> 'under AED 1,000' or r->'price_band'->'average_rounded_to_nearest_1000' <> 'null'::jsonb then
    fails := fails || ' R8:floor(' || r::text || ')'; end if;
  o := o || jsonb_build_object('R8_floor_band', r->'price_band');
  v := public.fn_customer_support_closes_status_chases();
  select jsonb_build_object('status', status, 'delivery', evidence->>'delivery_status', 'outcome', evidence->>'outcome',
           'our_sends', (select count(*) from public.notifications where inquiry_id = i3 and type = 'quote_received')) into r
    from public.agent_actions where id = h3;
  if r->>'status' <> 'done' or r->>'delivery' <> 'platform_new_quote_notice' or (r->>'our_sends')::int <> 0 then
    fails := fails || ' R3:platform_told(' || r::text || ')'; end if;
  o := o || jsonb_build_object('R3_platform_told', r);

  -- L2 + R1 + R4. an English change carrying the first name alone, the UPPERCASE name, a mobile, a landline and a domain
  t := 'request ' || ref2 || ': please make it 4 heaters of 80 litres. Khalid here, the MANSOORI family villa, call me on 0501234567 '
       || 'or the office 04 345 6789, see alnoor-trading.ae';
  v := public.fn_wa_route(pA, t, false, false, 'change_request');
  r := jsonb_build_object('reply', v->>'deterministic_reply');
  v := public.fn_wa_route(pA, t, false, false, 'change_request');
  r := r || jsonb_build_object('resend_reply', v->>'deterministic_reply');
  select answer into t from public.rfq_clarification where inquiry_id = i2 and kind = 'note' order by id desc limit 1;
  select count(*) into n from public.notifications where inquiry_id = i2 and type = 'rfq_addendum';
  if t is null or t ~* 'khalid|mansoori|0501234567|345 6789|alnoor' or t not like '%80 litres%' or n <> 3
     or r->>'reply' not like '%sent it to the 3 supplier(s)%' then
    fails := fails || ' L2/R1(' || coalesce(t, 'no note') || ' / ' || n || ' / ' || coalesce(r->>'reply', 'null') || ')'; end if;
  if (select count(*) from public.rfq_clarification where inquiry_id = i2 and kind = 'note') <> 1 or r->>'resend_reply' not like '%not sent again%' then
    fails := fails || ' R4(' || coalesce(r->>'resend_reply', 'null') || ')'; end if;
  o := o || jsonb_build_object('L2_reply', r->>'reply', 'R4_resend_reply', r->>'resend_reply', 'L2_note', t, 'L2_supplier_rows', n);

  -- L4 + R5 + R7. cancel: without the number; then with an IBAN before it (asked, not done); another ref; then "yes" in Arabic digits
  v := public.fn_wa_route(pA, 'please cancel my request', false, false, 'cancel_request');
  if v->>'deterministic_reply' not like '%cancel ' || '%' || ref2 || '%' or (select status from public.inquiries where id = i2) <> 'sent' then
    fails := fails || ' L4:asks(' || coalesce(v->>'deterministic_reply', 'null') || ')'; end if;
  o := o || jsonb_build_object('L4_reply_without_number', v->>'deterministic_reply');
  v := public.fn_wa_route(pA, 'my IBAN is AE070331234567890123456, please cancel request ' || ref2, false, false, 'cancel_request');
  if v->>'deterministic_reply' not like '%reply yes ' || ref2 || ' within 30 minutes%' or (select status from public.inquiries where id = i2) <> 'sent' then
    fails := fails || ' R5/R7:asked(' || coalesce(v->>'deterministic_reply', 'null') || ')'; end if;
  o := o || jsonb_build_object('R5_confirm_prompt', v->>'deterministic_reply');
  -- a "yes" that is a change, not a confirmation, never cancels (re-review); a bare "yes" is told which ref to name
  v := public.fn_wa_route(pA, 'yes, please change the quantity on ' || ref2 || ' to 40', false, false, 'change_request');
  r := jsonb_build_object('yes_change', v->>'deterministic_reply');
  v := public.fn_wa_route(pA, 'yes, edit ' || ref2, false, false, 'none');
  r := r || jsonb_build_object('yes_edit', v->>'deterministic_reply');
  v := public.fn_wa_route(pA, 'yes', false, false, 'none');
  r := r || jsonb_build_object('bare_yes', v->>'deterministic_reply');
  if (select status from public.inquiries where id = i2) <> 'sent' or r->>'bare_yes' not like '%reply yes ' || ref2 || '%' then
    fails := fails || ' R5:not_a_confirmation(' || r::text || ')'; end if;
  o := o || jsonb_build_object('R5_not_a_confirmation', r);
  v := public.fn_wa_route(pA, 'yes ' || ref1, false, false, 'none');
  if (select status from public.inquiries where id = i2) <> 'sent' then fails := fails || ' R5:other_ref_cancelled'; end if;
  o := o || jsonb_build_object('R5_other_ref_reply', v->>'deterministic_reply');
  -- the classifier may read a bare "yes <ref>" as a status question: the confirmation still cancels
  v := public.fn_wa_route(pA, 'نعم ' || translate(ref2::text, '0123456789', '٠١٢٣٤٥٦٧٨٩'), false, false, 'my_requests');
  select count(*) into n from public.notifications where inquiry_id = i2 and type = 'rfq_cancelled';
  if (select status from public.inquiries where id = i2) <> 'cancelled' or n <> 3
     or (select count(*) from public.notifications where inquiry_id = i2 and type = 'inquiry_cancelled' and to_role = 'customer' and channel = 'email') <> 1
     or v->>'deterministic_reply' not like '%is cancelled. The 3 supplier(s)%' then
    fails := fails || ' L4(' || coalesce(v->>'deterministic_reply', 'null') || ' / ' || n || ')'; end if;
  o := o || jsonb_build_object('L4_reply', v->>'deterministic_reply', 'L4_supplier_rows', n);

  -- 4. both requests listed, the cancelled one with its status
  v := public.fn_wa_context('customer', pA);
  if jsonb_array_length(v->'inquiries') <> 2
     or (select x->>'status' from jsonb_array_elements(v->'inquiries') x where (x->>'ref')::int = ref2) <> 'cancelled'
     or (select x->>'status' from jsonb_array_elements(v->'inquiries') x where (x->>'ref')::int = ref1) <> 'revealed' then
    fails := fails || ' 4(' || (v->'inquiries')::text || ')'; end if;
  o := o || jsonb_build_object('case4_list', (select jsonb_agg(jsonb_build_object('ref', x->'ref', 'status', x->'status', 'status_meaning', x->'status_meaning', 'open', x->'open'))
                                               from jsonb_array_elements(v->'inquiries') x));
  v := public.fn_wa_route(pA, 'status of my requests?', false, false, 'my_requests');
  if v->>'deterministic_reply' not like '%Request ' || ref2 || '%cancelled%' then fails := fails || ' 4:reply'; end if;
  o := o || jsonb_build_object('case4_reply', v->>'deterministic_reply');

  -- R13. a change to a request no supplier has yet
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at)
  values (i5, cA, 'Painting', 'Dubai', 'ZZ DEMO repaint a flat', 'open', 'en', now() - interval '1 hour');
  select rfq_no into ref5 from public.inquiries where id = i5;
  v := public.fn_wa_route(pA, 'request ' || ref5 || ': add the two bedrooms as well', false, false, 'change_request');
  if v->>'deterministic_reply' not like '%not with any supplier yet%' or v->>'deterministic_reply' like '%0 supplier%' then
    fails := fails || ' R13:no_match(' || coalesce(v->>'deterministic_reply', 'null') || ')'; end if;
  o := o || jsonb_build_object('R13_no_match_reply', v->>'deterministic_reply');

  -- R9. the revealed supplier is later put under a sanctions ban: never named again
  insert into public.sanctions_ban (lead_id, decided_by, note) values (s1, 'ZZ DEMO probe', 'ZZ DEMO probe');
  v := public.fn_wa_context('customer', pA);
  r := (select x from jsonb_array_elements(v->'inquiries') x where (x->>'ref')::int = ref1);
  if v::text like '%Supplier One%' or r->'revealed_quotes'->0->>'supplier' <> 'a supplier no longer on QuotesDone' then
    fails := fails || ' R9(' || coalesce(r->>'revealed_quotes', 'null') || ')'; end if;
  o := o || jsonb_build_object('R9_revealed_sanctioned', r->'revealed_quotes');

  -- L3. "talk to a person": filed, followed up at 23 h (by email when the WhatsApp window closed), reported to the CEO at 24 h
  r := to_jsonb(public.fn_wa_human_request(pA, true, 'ZZ DEMO Talk to a person', 'ZZ DEMO probe'));
  h1 := (r->>'handoff_id')::bigint;
  update public.agent_actions set created_at = now() - interval '25 hours' where id = h1;
  v := public.fn_wa_human_request_tick();
  v := v || jsonb_build_object('email', public.fn_wa_human_request_email_followup());
  select jsonb_build_object('status', status, 'followed_up', detail ? 'followed_up_at', 'skipped', detail->>'followup_skipped',
           'emailed', detail->'email_followup'->>'status', 'report', (select status from public.support_ceo_report where id = (detail->>'escalated_report_id')::bigint))
    into r from public.agent_actions where id = h1;
  if r->>'status' <> 'pending' or r->>'followed_up' <> 'true' or r->>'report' is null
     or (select count(*) from public.notifications where type = 'support_person_followup' and to_email = 'zz-demo-wa-a@example.invalid' and channel = 'email') <> 1 then
    fails := fails || ' L3(' || r::text || ' / ' || v::text || ')'; end if;
  -- R14. the founder's alert says the email goes automatically
  select string_agg(detail, ' | ') into t from public.founder_alerts where dedupe_key = 'wa_human_followup:' || h1;
  if t is null or t like '%call them or email them%' or t not like '%emails them the follow-up instead%' then
    fails := fails || ' R14(' || coalesce(t, 'no alert') || ')'; end if;
  o := o || jsonb_build_object('L3_person', r, 'L3_ticks', v, 'R14_founder_alert_says_email_goes', t like '%emails them the follow-up instead%');

  -- 5. the founder, even when a customer row confirms his number (nothing printed but booleans)
  select value into f from public.app_secrets where key = 'admin_mfa_phone';
  f := split_part(coalesce(f, ''), ',', 1);
  if length(regexp_replace(f, '[^0-9]', '', 'g')) >= 9 then
    insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, whatsapp_opt)
    values (cF, 'ZZ DEMO Founder Clash', 'zz-demo-wa-f@example.invalid', f, true, true, 'same');
    o := o || jsonb_build_object('case5_founder_is_founder', public.fn_identify_contact('whatsapp:' || f)->>'audience' = 'founder',
                                 'case5_founder_context_is_company', public.fn_wa_context('founder', 'whatsapp:' || f)->>'scope' = 'company');
    if public.fn_identify_contact('whatsapp:' || f)->>'audience' <> 'founder' then fails := fails || ' 5:founder'; end if;
  else
    fails := fails || ' 5:no_founder_number_configured';
  end if;

  raise exception 'CHK<<%>>', case when fails = '' then 'PROBE OK ' else 'PROBE FAILED:' || fails || ' ' end
    || regexp_replace(o::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<uuid>', 'g');
end $probe$;
