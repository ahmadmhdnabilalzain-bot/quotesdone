-- PROBE: A CUSTOMER ASKS ONE SUPPLIER ABOUT ITS QUOTE BEFORE PAYING, AND HEARS BACK.
-- Seat: sales_engineer. Agent: CUSTOMER_W2, 16 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_change_to_a_sent_request_is_a_revision_every_quote_names_and_every_supplier_is_told.sql and
-- a_customer_asks_one_supplier_about_its_quote_before_paying_and_hears_back.sql on a LOCAL Postgres 16. It always raises, so
-- every row it writes is rolled back. Every party is a ZZ DEMO fixture on @example.invalid. No model is called: the sales
-- engineer's reading is passed to fn_reason_held_resolve as the model would return it.
-- PROBE OK only if
--   1. a demo customer's question files no reasoning (nothing is paid for test traffic);
--   2. 'answered_from_quote' stores the answer with the supplier's name, its brand and a phone removed, answered_by
--      sales_engineer, and tells the customer by e-mail without the supplier's name;
--   3. 'relay_to_supplier' writes the supplier copy with the customer's phone and name removed, sets a reply date about 24 hours
--      out, and writes ONLY the quoted supplier, never the other one, with no customer identity;
--   4. the customer's facts carry both questions under that quote's letter: who asked, who answered, the answer, and the due
--      date of the relayed one; and the request's revision and the quote's priced revision;
--   5. past its date the customer is told once and the supplier reminded once; a second run tells nobody;
--   6. the supplier's answer is told to the customer;
--   7. an unknown choice raises; an Arabic supplier copy is never relayed and goes to the sales engineer's queue; a customer
--      question without its quote is refused by the table.
do $probe$
declare
  fails text := ''; c uuid := gen_random_uuid(); i uuid := gen_random_uuid(); q1 uuid := gen_random_uuid(); q2 uuid := gen_random_uuid();
  s1 bigint; s2 bigint; v jsonb; n int; h bigint; k1 bigint; k2 bigint; k3 bigint; r record; t text; qa jsonb;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  select 'delivery.request', s, 'customer_support', 'probe copy of the production row', 'fn_customer_support_acts_on_handoff', null, false,
         'scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql'
    from unnest(array['sales_engineer', 'customer_support']) s
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, locale, created_at)
  values (c, 'ZZ DEMO Question Customer', 'zz-demo-ask-c@example.invalid', '+971500000151', true, true, 'en', now() - interval '5 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Scaffold Masters', 'zz-demo-ask-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Other Painter', 'zz-demo-ask-s2@example.invalid') returning id into s2;
  insert into public.inquiries (id, customer_id, category, emirate, summary, budget, status, lang, created_at)
  values (i, c, 'Painting', 'Dubai', 'ZZ DEMO paint a villa exterior', 'AED 40,000', 'quoted', 'en', now() - interval '3 days');
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select i, s, 0.9, now() - interval '70 hours', 'ZZ DEMO probe' from unnest(array[s1, s2]) s;
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q::text, 1, 'ZZ DEMO exterior paint and labour', 'Zeltra', 'ZX-9', 'two coats elastomeric', 1, 'lot', a, 5000
    from (values (q1, 36000), (q2, 41000)) x(q, a);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, warranty, lead_time, payment_terms, exclusions, scope, validity)
  values (q1, i, s1, 36000, 'submitted', now() - interval '60 hours', '2 years', '10 days', '50% advance', 'none',
          'Scaffolding included; Zeltra ZX-9 paint, two coats', '30 days'),
         (q2, i, s2, 41000, 'submitted', now() - interval '50 hours', '1 year', '12 days', '40% advance', 'scaffolding', 'Paint only', '30 days');
  -- the quality gate holds a fixture quote for its flags (fn_quote_quality_gate); a hold already released lets it stand, as on
  -- production once its hours have passed
  insert into public.quote_quality_hold (quote_id, inquiry_id, supplier_id, fixture, flags, fixes_en, accepted_md5, held_at, release_due, released_at, release_reason)
  select q.id, q.inquiry_id, q.supplier_id, true, '[]'::jsonb, '', '', now(), now(), now(), 'waited_24h'
    from public.quotes q where q.id in (q1, q2)
  on conflict (quote_id) do update set released_at = now(), release_reason = 'waited_24h', superseded_at = null;
  update public.quotes set status = 'submitted' where id in (q1, q2);
  if (select count(*) from public.quotes where id in (q1, q2) and status = 'submitted') <> 2 then fails := fails || ' [0: the fixture quotes are not live]'; end if;
  -- his portal showed both quotes: their letters are recorded (customer_api my_inquiries -> recordShown)
  perform public.fn_customer_supplier_letters(array[i], jsonb_build_array(jsonb_build_object('inquiry_id', i, 'supplier_id', s1),
            jsonb_build_object('inquiry_id', i, 'supplier_id', s2)), 'quote_card');

  -- 1. his first question, as customer_api writes it
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, question_as_written, asked_by, quote_id, source)
  values (i, s1, 'question', 'Does the price include scaffolding?', 'Does the price include scaffolding?', 'customer', q1, 'portal') returning id into k1;
  if public.fn_sales_engineer_customer_question_file(k1) is not null then fails := fails || ' [1: a demo question filed a reasoning question]'; end if;

  -- 2. answered from the quote
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('sales_engineer', 'sales_engineer.customer_question', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('inquiry_id', i, 'quote_id', q1, 'clarification_id', k1, 'customer_id', c), 'probe', 'probe_cq:' || k1) returning id into h;
  v := public.fn_reason_held_resolve(h, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO', 'decision', jsonb_build_object('choice', 'answered_from_quote',
        'fields', jsonb_build_object('answer', jsonb_build_object('value', 'Yes: the quote says scaffolding by ZZ DEMO Scaffold Masters is included, with Zeltra paint. Call 0500000999.')))));
  select * into r from public.rfq_clarification where id = k1;
  if r.answered_by is distinct from 'sales_engineer' or r.answered_at is null then fails := fails || ' [2: not answered by the sales engineer: ' || v::text || ']'; end if;
  if r.answer ilike '%Scaffold Masters%' or r.answer ilike '%Zeltra%' or r.answer like '%0500000999%' or r.answer not like '%the supplier%' then
    fails := fails || ' [2: the answer names the supplier, its brand or a phone: ' || coalesce(r.answer, 'null') || ']'; end if;
  select count(*) into n from public.notifications where quote_id = q1 and to_role = 'customer' and body like '%answered from the quote itself%' and body like '%Supplier A%' and body not ilike '%Scaffold Masters%';
  if n <> 1 then fails := fails || ' [2: the customer was not told (' || n || ')]'; end if;

  -- 3. relayed to the supplier
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, question_as_written, asked_by, quote_id, source)
  values (i, s1, 'question', 'Can you start on Sunday?', 'Can you start on Sunday? I am ZZ DEMO Question Customer.', 'customer', q1, 'portal') returning id into k2;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('sales_engineer', 'sales_engineer.customer_question', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('inquiry_id', i, 'quote_id', q1, 'clarification_id', k2, 'customer_id', c), 'probe', 'probe_cq:' || k2) returning id into h;
  v := public.fn_reason_held_resolve(h, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO', 'decision', jsonb_build_object('choice', 'relay_to_supplier',
        'fields', jsonb_build_object('question_en', jsonb_build_object('value', 'Could you start on Sunday? (ZZ DEMO Question Customer, +971500000151)')))));
  select * into r from public.rfq_clarification where id = k2;
  if r.relayed_at is null or r.reply_by not between now() + interval '23 hours' and now() + interval '25 hours' then fails := fails || ' [3: not relayed with a 24 h date: ' || v::text || ']'; end if;
  if r.question like '%500000151%' or r.question ilike '%Question Customer%' then fails := fails || ' [3: the supplier copy names the customer: ' || r.question || ']'; end if;
  select count(*) into n from public.notifications where quote_id = q1 and lead_id = s1 and to_role = 'supplier' and body like '%Please answer by%';
  if n <> 1 then fails := fails || ' [3: the quoted supplier was not written (' || n || ')]'; end if;
  if exists (select 1 from public.notifications where lead_id = s2 and inquiry_id = i) then fails := fails || ' [3: the other supplier was written]'; end if;
  if exists (select 1 from public.notifications where inquiry_id = i and to_role = 'supplier' and (body like '%500000151%' or body ilike '%Question Customer%')) then
    fails := fails || ' [3: a supplier notice names the customer]'; end if;

  -- 4. his facts
  select z.q -> 'questions_and_answers' into qa
    from jsonb_array_elements(public.fn_customer_inquiry_facts(c, 10)) f(j), jsonb_array_elements(f.j -> 'quotes') z(q)
   where f.j ->> 'id' = i::text and jsonb_typeof(z.q -> 'questions_and_answers') = 'array';
  if qa is null or jsonb_array_length(qa) <> 2 then fails := fails || ' [4: the thread is not under the quote: ' || coalesce(qa::text, 'null') || ']';
  else
    if not (qa -> 0 ->> 'asked_by' like 'you%' and qa -> 0 ->> 'answered_by' like 'your sales engineer%') then fails := fails || ' [4: who asked / answered: ' || (qa -> 0)::text || ']'; end if;
    if qa -> 1 ->> 'state' not like 'asked of the supplier, answer due by%' then fails := fails || ' [4: no due date: ' || (qa -> 1)::text || ']'; end if;
  end if;
  if (select f.j -> 'asked' ->> 'revision' from jsonb_array_elements(public.fn_customer_inquiry_facts(c, 10)) f(j) where f.j ->> 'id' = i::text) is distinct from '1' then
    fails := fails || ' [4: the facts carry no revision]'; end if;
  if exists (select 1 from jsonb_array_elements(public.fn_customer_inquiry_facts(c, 10)) f(j), jsonb_array_elements(f.j -> 'quotes') z(q)
              where f.j ->> 'id' = i::text and not (z.q ? 'priced_revision')) then fails := fails || ' [4: a quote carries no priced revision]'; end if;
  if public.fn_customer_inquiry_facts(c, 10)::text ilike '%Scaffold Masters%' then fails := fails || ' [4: the facts name the supplier]'; end if;

  -- 5. past its date
  update public.rfq_clarification set reply_by = now() - interval '1 minute' where id = k2;
  perform set_config('qd.duty_fixtures', 'on', true);
  v := public.fn_sales_engineer_customer_questions(now());
  if (v->>'overdue_told')::int <> 1 then fails := fails || ' [5: ' || v::text || ']'; end if;
  select count(*) into n from public.notifications where inquiry_id = i and to_role = 'customer' and body like '%has not yet answered%';
  if n <> 1 then fails := fails || ' [5: the customer was told ' || n || ' times]'; end if;
  select count(*) into n from public.notifications where inquiry_id = i and lead_id = s1 and body like '%still waiting for your answer%';
  if n <> 1 then fails := fails || ' [5: the supplier was reminded ' || n || ' times]'; end if;
  v := public.fn_sales_engineer_customer_questions(now());
  if (v->>'overdue_told')::int <> 0 then fails := fails || ' [5: a second run told again]'; end if;

  -- 6. the supplier answers (messages_api clarify_reply writes these columns)
  update public.rfq_clarification set answer = 'Yes, Sunday works.', answered_at = now(), answered_by = 'supplier' where id = k2;
  v := public.fn_customer_question_answered_tell(k2);
  if not coalesce((v->>'told')::boolean, false) then fails := fails || ' [6: ' || v::text || ']'; end if;

  -- 7. an unknown choice; an Arabic supplier copy; a question with no quote
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, question_as_written, asked_by, quote_id, source)
  values (i, s2, 'question', 'A question from the customer, held for the sales engineer.', 'هل السعر يشمل السقالات؟', 'customer', q2, 'portal') returning id into k3;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('sales_engineer', 'sales_engineer.customer_question', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('inquiry_id', i, 'quote_id', q2, 'clarification_id', k3, 'customer_id', c), 'probe', 'probe_cq:' || k3) returning id into h;
  begin
    perform public.fn_reason_apply_sales_engineer__customer_question(h, jsonb_build_object('decision', jsonb_build_object('choice', 'ask_the_customer')));
    fails := fails || ' [7: an unknown choice was accepted]';
  exception when others then if sqlerrm not like 'CHOICE_NOT_AN_OPTION%' then fails := fails || ' [7: ' || sqlerrm || ']'; end if;
  end;
  v := public.fn_reason_apply_sales_engineer__customer_question(h, jsonb_build_object('decision', jsonb_build_object('choice', 'relay_to_supplier',
        'fields', jsonb_build_object('question_en', jsonb_build_object('value', 'هل السعر يشمل السقالات؟')))));
  if (select relayed_at from public.rfq_clarification where id = k3) is not null then fails := fails || ' [7: Arabic was relayed]'; end if;
  if not exists (select 1 from public.agent_actions where kind = 'customer_question_waiting' and target_id = k3::text) then fails := fails || ' [7: not handed to the seat]'; end if;
  if exists (select 1 from public.notifications where lead_id = s2 and inquiry_id = i) then fails := fails || ' [7: the other supplier was written]'; end if;
  begin
    insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, asked_by, source) values (i, s1, 'question', 'x', 'customer', 'portal');
    fails := fails || ' [7: a customer question without its quote was accepted]';
  exception when check_violation then null;
  end;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK>>';
end $probe$;
