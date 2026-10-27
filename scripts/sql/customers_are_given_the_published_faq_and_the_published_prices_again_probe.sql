-- PROBE for customers_are_given_the_published_faq_and_the_published_prices_again.sql. Seat: customer_support. 27 Oct 2026.
-- A pure probe: it defines nothing and ends in raise exception, so every write in the request is rolled back (the 20
-- rows the data file changes, the routines #1640 and #1660 replace, and the decision-log and gap rows fn_sales_assist
-- writes). Nothing reaches a person: it calls read routines and no sender.
--
-- RUN IT AS ONE QUERY, after the three files it tests, in their merge order, so the raise rolls all of them back:
--   knowledge_the_ai_wrote_itself_is_withheld_from_customers.sql (#1640)
--   customers_and_suppliers_are_never_given_internal_knowledge.sql (#1660)
--   customers_are_given_the_published_faq_and_the_published_prices_again.sql (this PR)
--   this probe
-- (Once they are applied, run it alone.) It must print PROBE OK.
--
-- WHAT IT ASSERTS, on the four outside paths #1660 closes (fn_reason_retrieve, fn_reason_retrieve_ml, the portal corpus
-- fn_support_corpus_search(q, false) and the portal chat fn_sales_assist):
--   1. #1660's own leak test still holds: an internal ops row asked for by its own vectors and title reaches the internal
--      caller and NO outside caller, and every ops row any outside call returns is one of the 16 published-FAQ rows.
--   2. Exactly 16 ops rows are public, and they are the 16 qd-company:faq-* rows.
--   3. Customers now receive them: each of the 16 by its own multilingual vector to a visitor and by its title in the
--      portal corpus; the two with a gte vector also to a customer through think() and through the portal chat.
--   4. The 2 retagged entries (English rows) reach the portal corpus, the portal chat and think() for a customer; their
--      Arabic twins (stale penalty, transliterated brand: review of #1661) still reach no outside caller.
--   5. The held entry what-does-it-cost-published-prices (en + @ar) still reaches no outside caller.
--   6. Ten customer and supplier questions (the review's set) return no ops row outside the 16.
do $probe$
declare
  c_faq constant text[] := array[
    'qd-company:faq-arabic', 'qd-company:faq-company-identity', 'qd-company:faq-company-policies',
    'qd-company:faq-customer', 'qd-company:faq-documents', 'qd-company:faq-financial', 'qd-company:faq-future-vision',
    'qd-company:faq-integrations', 'qd-company:faq-marketplace', 'qd-company:faq-operations', 'qd-company:faq-quotation',
    'qd-company:faq-rfq', 'qd-company:faq-security', 'qd-company:faq-smart-engine', 'qd-company:faq-supplier',
    'qd-company:faq-technical'];
  c_sup constant text[] := array['customer_support:company-pricing', 'customer_support:company-hard-rules-marketplace'];
  c_ar_held constant text[] := array['customer_support:company-pricing@ar', 'customer_support:company-hard-rules-marketplace@ar'];
  c_held constant text[] := array['customer_support:what-does-it-cost-published-prices',
    'customer_support:what-does-it-cost-published-prices@ar',
    'customer_support:company-pricing@ar', 'customer_support:company-hard-rules-marketplace@ar'];
  c_questions constant text[] := array[
    'How much is the fee to use QuotesDone?', 'Will the supplier see my name and phone number?',
    'How long until I receive quotes?', 'Can I get a refund of the reveal fee?', 'How many suppliers will quote on my job?',
    'What documents do I need to register as a supplier?', 'When do I pay and how much as a supplier?',
    'What happens if I do not respond after a reveal?', 'Is there a subscription fee for suppliers?',
    'How do I send a quotation?'];
  r record; f record; mlv vector(384); j jsonb; n int; m int; q text; t0 timestamptz := clock_timestamp();
  res jsonb := '{}'::jsonb; fails text[] := '{}';
  other_ops int := 0;      -- ops rows outside the 16 returned to ANY outside caller (must stay 0)
  faq_hits int := 0;
begin
  -- 2. exactly the 16 are public
  select count(*) into n from public.ops_knowledge where confidentiality = 'public';
  res := res || jsonb_build_object('public_ops', n);
  if n <> 16 or exists (select 1 from public.ops_knowledge where confidentiality = 'public' and record_id <> all (c_faq))
     or (select count(*) from public.ops_knowledge where record_id = any (c_faq) and confidentiality = 'public') <> 16 then
    fails := array_append(fails, 'public_set_is_not_the_16_faq_rows');
  end if;

  -- 1. #1660's leak test, on its own subject (a real internal row the outside branches would otherwise admit)
  select o.record_id, o.title, o.embedding_gte into r
    from public.ops_knowledge o
    join public.knowledge_vector_ml v on v.src = 'ops_knowledge' and v.row_id = o.record_id
   where o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
     and o.scope_type = 'company' and o.dept_key is null and o.confidentiality = 'internal'
     and length(o.title) between 12 and 80
   order by o.record_id limit 1;
  if r.record_id is null then raise exception 'CHK<<PROBE FAILED: no internal subject row>>'; end if;
  select v.embedding into mlv from public.knowledge_vector_ml v where v.src = 'ops_knowledge' and v.row_id = r.record_id limit 1;
  res := res || jsonb_build_object('subject', r.record_id);

  j := public.fn_reason_retrieve('customer_support', r.embedding_gte, 6, null, null, null, 'internal');
  select count(*) into n from jsonb_array_elements(j) e where e->>'source' = 'ops_knowledge';
  res := res || jsonb_build_object('rr_internal_ops', n);
  if n = 0 then fails := array_append(fails, 'rr_internal_lost_ops'); end if;
  j := public.fn_reason_retrieve_ml('customer_support', mlv, r.embedding_gte, 6, 3, null, null, null, 'internal');
  select count(*) into n from jsonb_array_elements(j) e where e->>'source' = 'ops_knowledge';
  res := res || jsonb_build_object('ml_internal_ops', n);
  if n = 0 then fails := array_append(fails, 'ml_internal_lost_ops'); end if;

  foreach q in array array['customer', 'supplier', 'visitor', null] loop
    j := public.fn_reason_retrieve(case when q = 'supplier' then 'sales_engineer' else 'customer_support' end,
                                   r.embedding_gte, 6, null, null, null, q);
    select count(*) into n from jsonb_array_elements(j) e where e->>'source' = 'ops_knowledge' and e->>'id' <> all (c_faq);
    other_ops := other_ops + n;
    if n > 0 then fails := array_append(fails, 'rr_' || coalesce(q, 'null') || '_got_internal_ops'); end if;
  end loop;
  j := public.fn_reason_retrieve_ml('customer_support', mlv, r.embedding_gte, 6, 3, null, null, null, 'visitor');
  select count(*) into n from jsonb_array_elements(j) e where e->>'source' = 'ops_knowledge' and e->>'id' <> all (c_faq);
  other_ops := other_ops + n;
  if n > 0 then fails := array_append(fails, 'ml_visitor_got_internal_ops'); end if;
  select count(*) into n from public.fn_support_corpus_search(r.title, false, 25) s where s.src = 'ops' and s.src_id <> all (c_faq);
  other_ops := other_ops + n;
  if n > 0 then fails := array_append(fails, 'portal_corpus_got_internal_ops'); end if;
  j := public.fn_sales_assist(r.title, r.embedding_gte, 0.5, 0.0, 10, 'sales_engineer');
  select count(*) into n from jsonb_array_elements(coalesce(j->'records', '[]'::jsonb)) e
   where e->>'corpus' = 'ops_knowledge' and e->>'record_id' <> all (c_faq);
  other_ops := other_ops + n;
  if n > 0 then fails := array_append(fails, 'sales_assist_got_internal_ops'); end if;

  -- 3. the 16 published-FAQ rows now reach customers
  for f in select o.record_id, o.title, o.embedding_gte, v.embedding as ml
             from public.ops_knowledge o
             left join public.knowledge_vector_ml v on v.src = 'ops_knowledge' and v.row_id = o.record_id
            where o.record_id = any (c_faq) order by o.record_id loop
    if f.ml is not null then
      j := public.fn_reason_retrieve_ml('customer_support', f.ml, f.embedding_gte, 6, 3, null, null, null, 'visitor');
      if exists (select 1 from jsonb_array_elements(j) e where e->>'source' = 'ops_knowledge' and e->>'id' = f.record_id)
        then faq_hits := faq_hits + 1; else fails := array_append(fails, 'ml_visitor_missing:' || f.record_id); end if;
      select count(*) into n from jsonb_array_elements(j) e where e->>'source' = 'ops_knowledge' and e->>'id' <> all (c_faq);
      other_ops := other_ops + n;
    else
      fails := array_append(fails, 'no_ml_vector:' || f.record_id);
    end if;
    if f.embedding_gte is not null then
      j := public.fn_reason_retrieve('customer_support', f.embedding_gte, 6, null, null, null, 'customer');
      if not exists (select 1 from jsonb_array_elements(j) e where e->>'source' = 'ops_knowledge' and e->>'id' = f.record_id)
        then fails := array_append(fails, 'rr_customer_missing:' || f.record_id); end if;
      select count(*) into n from jsonb_array_elements(j) e where e->>'source' = 'ops_knowledge' and e->>'id' <> all (c_faq);
      other_ops := other_ops + n;
    end if;
  end loop;
  res := res || jsonb_build_object('faq_rows_reached_by_ml_visitor', faq_hits);
  -- by title in the portal corpus: all 16
  for f in select o.record_id, o.title from public.ops_knowledge o where o.record_id = any (c_faq) loop
    select count(*) into n from public.fn_support_corpus_search(f.title, false, 25) s where s.src = 'ops' and s.src_id = f.record_id;
    if n = 0 then fails := array_append(fails, 'portal_corpus_missing:' || f.record_id); end if;
  end loop;
  -- the portal chat, with its production floors: its ops branch is vector-only, so it can reach the FAQ rows that carry
  -- a gte vector (2 of 16 today; the other 14 are embedding_status 'pending'). The published FAQ itself is a corpus of
  -- its own there (company_faq), so the portal chat is not short of these answers either way.
  for f in select o.record_id, o.title, o.embedding_gte from public.ops_knowledge o
            where o.record_id = any (c_faq) and o.embedding_gte is not null loop
    j := public.fn_sales_assist(f.title, f.embedding_gte);
    if not exists (select 1 from jsonb_array_elements(coalesce(j->'records', '[]'::jsonb)) e
                    where e->>'corpus' = 'ops_knowledge' and e->>'record_id' = f.record_id)
      then fails := array_append(fails, 'sales_assist_missing:' || f.record_id); end if;
    select count(*) into n from jsonb_array_elements(coalesce(j->'records', '[]'::jsonb)) e
     where e->>'corpus' = 'ops_knowledge' and e->>'record_id' <> all (c_faq);
    other_ops := other_ops + n;
  end loop;

  -- 4. the retagged entries reach the portal corpus, the portal chat and think() for a customer
  for f in select s.record_id, s.title, s.embedding_gte from public.support_knowledge s where s.record_id = any (c_sup) loop
    select count(*) into n from public.fn_support_corpus_search(f.title, false, 25) x where x.src = 'supportkb' and x.src_id = f.record_id;
    if n = 0 then fails := array_append(fails, 'portal_corpus_missing:' || f.record_id); end if;
    if f.record_id not like '%@ar' then
      j := public.fn_sales_assist(f.title, f.embedding_gte);   -- production floors
      if not exists (select 1 from jsonb_array_elements(coalesce(j->'records', '[]'::jsonb)) e
                      where e->>'corpus' = 'support_knowledge' and e->>'record_id' = f.record_id)
        then fails := array_append(fails, 'sales_assist_missing:' || f.record_id); end if;
      j := public.fn_reason_retrieve('customer_support', f.embedding_gte, 6, null, null, null, 'customer');
      if not exists (select 1 from jsonb_array_elements(j) e where e->>'source' = 'support_knowledge' and e->>'id' = f.record_id)
        then fails := array_append(fails, 'rr_customer_missing:' || f.record_id); end if;
      select count(*) into n from jsonb_array_elements(j) e where e->>'source' = 'ops_knowledge' and e->>'id' <> all (c_faq);
      other_ops := other_ops + n;
    end if;
  end loop;
  -- INFORMATION, not asserted: the review's S2 question at production floors. The portal chat admits a row with no
  -- vector only on an all-terms lexical match, and no published row contains every term of this question.
  j := public.fn_sales_assist('When do I pay and how much?',
         (select embedding_gte from public.support_knowledge where record_id = 'customer_support:company-pricing'));
  res := res || jsonb_build_object('info_s2_cited', j->'cited');

  -- 5. the held entry still reaches no outside caller
  for f in select s.record_id, s.title, s.embedding_gte from public.support_knowledge s where s.record_id = any (c_held) loop
    select count(*) into n from public.fn_support_corpus_search(f.title, false, 25) x where x.src = 'supportkb' and x.src_id = any (c_held);
    if n > 0 then fails := array_append(fails, 'held_row_in_portal_corpus:' || f.record_id); end if;
    j := public.fn_reason_retrieve('customer_support', f.embedding_gte, 6, null, null, null, 'customer');
    if exists (select 1 from jsonb_array_elements(j) e where e->>'id' = any (c_held))
      then fails := array_append(fails, 'held_row_to_customer:' || f.record_id); end if;
    j := public.fn_sales_assist(f.title, f.embedding_gte, 0.5, 0.0, 10, 'sales_engineer');   -- wide open floors
    if exists (select 1 from jsonb_array_elements(coalesce(j->'candidates', '[]'::jsonb)) e where e->>'record_id' = any (c_held))
      then fails := array_append(fails, 'held_row_in_sales_assist:' || f.record_id); end if;
  end loop;
  select count(*) into n from public.support_knowledge where record_id = any (c_held) and tags @> array['audience:internal'];
  if n <> 4 then fails := array_append(fails, 'held_rows_changed'); end if;
  if exists (select 1 from public.support_knowledge where record_id = any (c_ar_held) and structured_data ? 'retag')
    then fails := array_append(fails, 'arabic_twin_retagged'); end if;

  -- 6. the review's ten questions: whatever ops rows come back are the published FAQ, nothing else
  faq_hits := 0;
  foreach q in array c_questions loop
    select count(*) filter (where s.src_id <> all (c_faq)), count(*) filter (where s.src_id = any (c_faq)) into n, m
      from public.fn_support_corpus_search(q, false, 8) s where s.src = 'ops';
    other_ops := other_ops + n; faq_hits := faq_hits + m;
    if n > 0 then fails := array_append(fails, 'portal_corpus_internal_ops_for: ' || q); end if;
  end loop;
  res := res || jsonb_build_object('ten_questions_faq_ops_hits', faq_hits);

  -- 18 rows exactly as the data file left them
  select count(*) into n from public.support_knowledge where record_id = any (c_sup) and tags @> array['kind:published_terms']
     and not tags && array['audience:internal', 'kind:company'] and structured_data ? 'retag';
  if n <> 2 then fails := array_append(fails, 'support_rows_not_retagged'); end if;

  res := res || jsonb_build_object('other_ops_to_outside', other_ops, 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000),
                                   'fails', to_jsonb(fails));
  raise exception 'CHK<<%>>', case when cardinality(fails) = 0 and other_ops = 0 then 'PROBE OK ' else 'PROBE FAILED ' end || res::text;
end $probe$;
