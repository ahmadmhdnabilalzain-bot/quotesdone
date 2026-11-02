-- PROBE for customers_and_suppliers_are_never_given_internal_knowledge.sql. Seat: customer_support. 27 Oct 2026.
-- A pure probe: it defines nothing and ends in raise exception, so every write it makes (the confidentiality flip
-- below, and the decision-log and gap rows fn_sales_assist writes) is rolled back. Nothing reaches a person: it calls
-- four read routines and no sender.
--
-- RUN IT TWICE, each time as ONE query so the raise rolls everything back:
--   * alone, against the live routines: it reports the leak (verdict LEAK);
--   * after the fix file, in the same query: it reports PROBE OK.
--   (scripts/checks/customers_and_suppliers_are_never_given_internal_knowledge.test.mjs does both with --live.)
--
-- THE SUBJECT is one real ops_knowledge row the outside-audience branches admit (runtime-eligible, current, a company
-- scope, no department, a gte and an ml vector). It is asked for by its OWN vectors and its OWN title, so an internal
-- caller is certain to get it back; the probe asserts that too, so "nothing came back" cannot pass for "withheld".
-- POSITIVE CONTROL: the same row is then flipped to confidentiality 'public' (rolled back) and must reach every
-- outside caller, so the filter is the confidentiality and not a broken routine.
do $probe$
declare
  r record; mlv vector(384); res jsonb := '{}'::jsonb; t0 timestamptz; j jsonb; n int; st text;
  fails text[] := '{}';
  ops_in  constant text := 'select count(*) from jsonb_array_elements($1) e where e->>''source'' = ''ops_knowledge''';
begin
  select o.record_id, o.title, o.embedding_gte into r
    from public.ops_knowledge o
    join public.knowledge_vector_ml v on v.src = 'ops_knowledge' and v.row_id = o.record_id
   where o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
     and o.scope_type = 'company' and o.dept_key is null and o.confidentiality = 'internal'
     and length(o.title) between 12 and 80
   order by o.record_id limit 1;
  if r.record_id is null then raise exception 'CHK<<PROBE FAILED: no subject row>>'; end if;
  select v.embedding into mlv from public.knowledge_vector_ml v where v.src = 'ops_knowledge' and v.row_id = r.record_id limit 1;
  res := res || jsonb_build_object('subject', r.record_id);

  -- 1. fn_reason_retrieve (gte): internal keeps it, every outside audience is refused it
  j := public.fn_reason_retrieve('customer_support', r.embedding_gte, 6, null, null, null, 'internal');
  execute ops_in into n using j; res := res || jsonb_build_object('rr_internal_ops', n);
  if n = 0 then fails := array_append(fails, 'rr_internal_lost_ops'); end if;
  t0 := clock_timestamp();
  j := public.fn_reason_retrieve('customer_support', r.embedding_gte, 6, null, null, null, 'customer');
  res := res || jsonb_build_object('rr_customer_ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
  execute ops_in into n using j; res := res || jsonb_build_object('rr_customer_ops', n);
  if n > 0 then fails := array_append(fails, 'rr_customer_got_internal_ops'); end if;
  j := public.fn_reason_retrieve('sales_engineer', r.embedding_gte, 6, null, null, null, 'supplier');
  execute ops_in into n using j; res := res || jsonb_build_object('rr_supplier_ops', n);
  if n > 0 then fails := array_append(fails, 'rr_supplier_got_internal_ops'); end if;
  j := public.fn_reason_retrieve('customer_support', r.embedding_gte, 6, null, null, null, null);
  execute ops_in into n using j; res := res || jsonb_build_object('rr_null_audience_ops', n);
  if n > 0 then fails := array_append(fails, 'rr_null_audience_got_internal_ops'); end if;

  -- 2. fn_reason_retrieve_ml (multilingual + gte)
  j := public.fn_reason_retrieve_ml('customer_support', mlv, r.embedding_gte, 6, 3, null, null, null, 'internal');
  execute ops_in into n using j; res := res || jsonb_build_object('ml_internal_ops', n);
  if n = 0 then fails := array_append(fails, 'ml_internal_lost_ops'); end if;
  t0 := clock_timestamp();
  j := public.fn_reason_retrieve_ml('customer_support', mlv, r.embedding_gte, 6, 3, null, null, null, 'visitor');
  res := res || jsonb_build_object('ml_visitor_ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
  execute ops_in into n using j; res := res || jsonb_build_object('ml_visitor_ops', n);
  if n > 0 then fails := array_append(fails, 'ml_visitor_got_internal_ops'); end if;

  -- 3. fn_support_corpus_search with p_public = false: the signed-in portal (customers and suppliers)
  select count(*) into n from public.fn_support_corpus_search(r.title, false, 25) s where s.src = 'ops';
  res := res || jsonb_build_object('portal_corpus_ops', n);
  if n > 0 then fails := array_append(fails, 'portal_corpus_got_internal_ops'); end if;
  -- an internal-tagged support row, asked for by its own title (the subject is real; the probe asserts it existed)
  select k.title into st from public.support_knowledge k
   where k.runtime_index_eligible and length(k.title) between 12 and 80
     and (k.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(k.source_ids) x
          where x like 'internal:founder_instruction/%' or x like 'internal:memory/%'))
   order by k.record_id limit 1;
  if st is null then fails := array_append(fails, 'no_internal_support_subject'); end if;
  res := res || jsonb_build_object('support_subject', st);
  select count(*) into n from public.fn_support_corpus_search(st, false, 25) s
   where s.src = 'supportkb' and exists (select 1 from public.support_knowledge k where k.record_id = s.src_id
     and (k.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(k.source_ids) x
          where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')));
  res := res || jsonb_build_object('portal_corpus_internal_support', n);
  if n > 0 then fails := array_append(fails, 'portal_corpus_got_internal_support'); end if;

  -- 4. fn_sales_assist: the portal chat's retrieval (its one production caller answers customers and suppliers)
  j := public.fn_sales_assist(r.title, r.embedding_gte, 0.5, 0.0, 10, 'sales_engineer');
  select count(*) into n from jsonb_array_elements(coalesce(j->'records', '[]'::jsonb)) e where e->>'corpus' = 'ops_knowledge';
  res := res || jsonb_build_object('sales_assist_ops', n);
  if n > 0 then fails := array_append(fails, 'sales_assist_got_internal_ops'); end if;

  -- 5. POSITIVE CONTROL: the same row made public reaches the outside callers (rolled back with everything else)
  update public.ops_knowledge set confidentiality = 'public' where record_id = r.record_id;
  j := public.fn_reason_retrieve('customer_support', r.embedding_gte, 6, null, null, null, 'customer');
  execute ops_in into n using j; res := res || jsonb_build_object('ctl_rr_customer_public_ops', n);
  if n = 0 then fails := array_append(fails, 'ctl_public_row_not_given_to_customer'); end if;
  j := public.fn_reason_retrieve_ml('customer_support', mlv, r.embedding_gte, 6, 3, null, null, null, 'visitor');
  execute ops_in into n using j; res := res || jsonb_build_object('ctl_ml_visitor_public_ops', n);
  if n = 0 then fails := array_append(fails, 'ctl_public_row_not_given_by_ml'); end if;
  select count(*) into n from public.fn_support_corpus_search(r.title, false, 25) s where s.src = 'ops' and s.src_id = r.record_id;
  res := res || jsonb_build_object('ctl_portal_corpus_public_row', n);
  if n = 0 then fails := array_append(fails, 'ctl_public_row_not_in_portal_corpus'); end if;
  j := public.fn_sales_assist(r.title, r.embedding_gte, 0.5, 0.0, 10, 'sales_engineer');
  select count(*) into n from jsonb_array_elements(coalesce(j->'records', '[]'::jsonb)) e
   where e->>'corpus' = 'ops_knowledge' and e->>'record_id' = r.record_id;
  res := res || jsonb_build_object('ctl_sales_assist_public_row', n);
  if n = 0 then fails := array_append(fails, 'ctl_public_row_not_in_sales_assist'); end if;

  res := res || jsonb_build_object('fails', to_jsonb(fails));
  raise exception 'CHK<<%>>', case when cardinality(fails) = 0 then 'PROBE OK ' else 'LEAK ' end || res::text;
end $probe$;
