-- PROBE: the knowledge library tells an outside audience only what it may be told (customer_support, 27 Oct 2026;
-- founder rulings 1338 and 7 Oct). Pure probe, no DDL: run AFTER
-- the_knowledge_library_tells_an_outside_audience_only_what_it_may_be_told.sql in the SAME query through
-- node scripts/qsql.mjs, so the routine replace is rolled back with it; it ALWAYS ends in raise exception CHK<<...>>,
-- which rolls back every fixture row too.
-- Run alone, it reads the LIVE readers (the "before"): they take no audience, so it calls them without one and reports
-- what an outside caller would get.
--
-- FIXTURES: rows of every class, written to the knowledge stores only (kb_chunks, agent_knowledge, support_knowledge,
-- reasoning_knowledge_candidate, knowledge_vector_ml), titled 'ZZ DEMO', reaching the library through its own mirror
-- triggers. A knowledge row has no address: nothing here can reach a person. Each takes the vectors of a distinct real
-- kb_chunks row that is not in the library, and is asked for with exactly those vectors, so it ranks first wherever it
-- is allowed.
--   kb_generated, kb_memory, kb_blank     kb_chunks of source_kind 'generated', 'memory', '' (blank)
--   kb_standard                           kb_chunks 'standard' (a read source)                       -> told outside
--   agent_private                         agent_knowledge of the customer_support seat, validated
--   agent_unvalidated                     agent_knowledge '_global', 'unvalidated'
--   agent_global_ok                       agent_knowledge '_global', 'author_verified'                -> told outside
--   support_internal                      support_knowledge verified, tagged audience:internal
--   support_memory_source                 support_knowledge verified, cited internal:memory/...
--   support_unverified                    support_knowledge 'authored_not_independently_reviewed'
--   support_ok                            support_knowledge 'verified_sourced'                        -> told outside
--   research_pending                      reasoning_knowledge_candidate 'pending_review'
-- PROBE OK only if, for BOTH fn_reason_retrieve_library and fn_reason_retrieve_ml_library, seat customer_support:
--   1. internal and founder get every fixture;
--   2. customer, supplier, visitor, a blank, an unknown value ('staff') and NULL get exactly the three "told outside";
--   3. the library marks kb_generated, kb_memory and kb_blank NOT verified, and kb_standard verified.
-- It also times one real sales_engineer call per reader, outside and internal.
do $probe$
declare
  v_new boolean := to_regprocedure('public.fn_reason_retrieve_library(text,vector,integer,text,text,text,text)') is not null;
  q_gte text; q_ml text;
  v_seed_g vector[]; v_seed_m vector[];
  f_name text[] := '{}'; f_src text[] := '{}'; f_id text[] := '{}'; f_out boolean[] := '{}';
  i int; v_id text; v_aud text; v_res jsonb; has_g boolean; has_m boolean;
  v_fail text := ''; v_seen text := ''; v_ver text;
  v_t0 timestamptz; v_ms text := '';
  v_sg vector; v_sm vector;
  v_uid text := replace(gen_random_uuid()::text, '-', '');
begin
  -- the calls, in the new signature or (before this file) the old one, which takes no audience
  if v_new then
    q_gte := 'select public.fn_reason_retrieve_library(p_seat => $1, p_embedding => $2, p_k => 6, p_audience => $4)';
    q_ml  := 'select public.fn_reason_retrieve_ml_library(p_seat => $1, p_embedding => $3, p_embedding_gte => $2, p_k => 6, p_audience => $4)';
  else
    q_gte := 'select public.fn_reason_retrieve_library(p_seat => $1, p_embedding => $2, p_k => 6) where $4 is null or $4 is not null';
    q_ml  := 'select public.fn_reason_retrieve_ml_library(p_seat => $1, p_embedding => $3, p_embedding_gte => $2, p_k => 6) where $4 is null or $4 is not null';
  end if;

  -- 12 distinct real vectors, from kb_chunks rows the library does not hold
  select array_agg(g order by id), array_agg(m order by id) into v_seed_g, v_seed_m from (
    select c.id, c.embedding_gte g, v.embedding m from public.kb_chunks c
      join public.knowledge_vector_ml v on v.src = 'kb_chunks' and v.row_id = c.id::text
     where c.embedding_gte is not null
       and not exists (select 1 from public.knowledge_library_origin o where o.origin_store = 'kb_chunks' and o.origin_id = c.id::text)
     order by c.id limit 12) s;
  if coalesce(array_length(v_seed_g, 1), 0) < 12 then raise exception 'CHK<<PROBE FAILED: fewer than 12 seed vectors>>'; end if;

  -- kb_chunks
  for i in 1..4 loop
    insert into public.kb_chunks (source_kind, title, content, citation, embedding_gte)
    values ((array['generated', 'memory', '', 'standard'])[i], 'ZZ DEMO probe kb ' || i,
            'ZZ DEMO probe kb row ' || i || ' ' || v_uid, 'ZZ DEMO citation', v_seed_g[i])
    returning id::text into v_id;
    insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding) values ('kb_chunks', v_id, 'zz-demo-probe', v_seed_m[i]);
    f_name := f_name || (array['kb_generated', 'kb_memory', 'kb_blank', 'kb_standard'])[i];
    f_src := f_src || 'kb_chunks'::text; f_id := f_id || v_id; f_out := f_out || (i = 4);
  end loop;

  -- agent_knowledge
  for i in 1..3 loop
    insert into public.agent_knowledge (agent_key, topic, content, validation_status, embedding_gte)
    values ((array['customer_support', '_global', '_global'])[i], 'ZZ DEMO probe agent ' || i,
            'ZZ DEMO probe agent row ' || i || ' ' || v_uid, (array['author_verified', 'unvalidated', 'author_verified'])[i], v_seed_g[4 + i])
    returning id::text into v_id;
    insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding) values ('agent_knowledge', v_id, 'zz-demo-probe', v_seed_m[4 + i]);
    f_name := f_name || (array['agent_private', 'agent_unvalidated', 'agent_global_ok'])[i];
    f_src := f_src || 'agent_knowledge'::text; f_id := f_id || v_id; f_out := f_out || (i = 3);
  end loop;

  -- support_knowledge
  for i in 1..4 loop
    v_id := 'ZZ-DEMO-probe-support-' || i || '-' || v_uid;
    insert into public.support_knowledge (record_id, record_version, record_kind, title, tags, review_status, source_ids, body,
                                          pack_id, pack_version, embedding_gte)
    values (v_id, '1', 'fact', 'ZZ DEMO probe support ' || i,
            case when i = 1 then array['audience:internal'] else '{}'::text[] end,
            (array['verified_sourced', 'verified_sourced', 'authored_not_independently_reviewed', 'verified_sourced'])[i],
            case when i = 2 then array['internal:memory/zz_demo_probe'] else '{}'::text[] end,
            'ZZ DEMO probe support row ' || i || ' ' || v_uid, 'verified:zz_demo_probe', '1', v_seed_g[7 + i]);
    insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding) values ('support_knowledge', v_id, 'zz-demo-probe', v_seed_m[7 + i]);
    f_name := f_name || (array['support_internal', 'support_memory_source', 'support_unverified', 'support_ok'])[i];
    f_src := f_src || 'support_knowledge'::text; f_id := f_id || v_id; f_out := f_out || (i = 4);
  end loop;

  -- research, pending review
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, embedding_gte, status)
  values ('customer_support', 'ZZ DEMO probe question', 'ZZ DEMO probe finding ' || v_uid,
          '[{"url": "https://example.invalid/zz-demo-probe"}]'::jsonb, v_seed_g[12], 'pending_review')
  returning id::text into v_id;
  insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding) values ('reasoning_knowledge_candidate', v_id, 'zz-demo-probe', v_seed_m[12]);
  f_name := f_name || 'research_pending'::text; f_src := f_src || 'research'::text; f_id := f_id || v_id; f_out := f_out || false;

  -- every library fixture reached the library through the triggers
  for i in 1..array_length(f_name, 1) loop
    continue when f_src[i] = 'research';
    if not exists (select 1 from public.knowledge_library_origin o where o.origin_store = f_src[i] and o.origin_id = f_id[i]) then
      v_fail := v_fail || format(' %s never reached the library;', f_name[i]);
    end if;
  end loop;

  -- 3. the verified column
  select string_agg(format('%s=%s', f_name[j], l.verified), ',' order by j) into v_ver
    from generate_subscripts(f_name, 1) j
    join public.knowledge_library_origin o on o.origin_store = 'kb_chunks' and o.origin_id = f_id[j]
    join public.knowledge_library l on l.id = o.library_id;
  v_seen := v_seen || ' verified[' || coalesce(v_ver, '') || '];';
  if exists (select 1 from generate_subscripts(f_name, 1) j
               join public.knowledge_library_origin o on o.origin_store = 'kb_chunks' and o.origin_id = f_id[j]
               join public.knowledge_library l on l.id = o.library_id
              where l.verified is distinct from (f_name[j] = 'kb_standard')) then
    v_fail := v_fail || ' a kb_chunks library row is marked verified wrongly;';
  end if;

  -- 1 and 2. every audience, every fixture, both readers
  foreach v_aud in array array['internal', 'founder', 'customer', 'supplier', 'visitor', ' ', 'staff', '<null>'] loop
    for i in 1..array_length(f_name, 1) loop
      -- fixture i was written with seed vector i (kb 1-4, agent 5-7, support 8-11, research 12)
      execute q_gte into v_res using 'customer_support'::text, v_seed_g[i], v_seed_m[i], nullif(v_aud, '<null>');
      has_g := coalesce(v_res @> jsonb_build_array(jsonb_build_object('source', f_src[i], 'id', f_id[i])), false);
      execute q_ml into v_res using 'customer_support'::text, v_seed_g[i], v_seed_m[i], nullif(v_aud, '<null>');
      has_m := coalesce(v_res @> jsonb_build_array(jsonb_build_object('source', f_src[i], 'id', f_id[i])), false);
      if v_aud in ('internal', 'founder') then
        if not (has_g and has_m) then v_fail := v_fail || format(' %s lost %s (gte=%s ml=%s);', v_aud, f_name[i], has_g, has_m); end if;
      elsif f_out[i] then
        if not (has_g and has_m) then v_fail := v_fail || format(' %s lost the allowed %s (gte=%s ml=%s);', v_aud, f_name[i], has_g, has_m); end if;
      elsif has_g or has_m then
        v_fail := v_fail || format(' %s got %s (gte=%s ml=%s);', quote_literal(v_aud), f_name[i], has_g, has_m);
      end if;
    end loop;
  end loop;

  -- the cost of the rule on a real call: sales_engineer, a real verified sales_knowledge row's vectors
  select s.embedding_gte, v.embedding into v_sg, v_sm from public.sales_knowledge s
    join public.knowledge_vector_ml v on v.src = 'sales_knowledge' and v.row_id = s.record_id
   where s.embedding_gte is not null order by s.record_id limit 1;
  foreach v_aud in array array['customer', 'internal'] loop
    v_t0 := clock_timestamp();
    execute q_gte into v_res using 'sales_engineer'::text, v_sg, v_sm, v_aud;
    v_ms := v_ms || format(' gte/%s %s ms %s rows;', v_aud, round(extract(epoch from clock_timestamp() - v_t0) * 1000), jsonb_array_length(v_res));
    v_t0 := clock_timestamp();
    execute q_ml into v_res using 'sales_engineer'::text, v_sg, v_sm, v_aud;
    v_ms := v_ms || format(' ml/%s %s ms %s rows;', v_aud, round(extract(epoch from clock_timestamp() - v_t0) * 1000), jsonb_array_length(v_res));
  end loop;

  if v_fail = '' then
    raise exception 'CHK<<PROBE OK (%): outside audiences get only kb_standard, agent_global_ok, support_ok from both library readers; internal and founder get all 12 fixtures |%|%>>',
      case when v_new then 'with this file' else 'LIVE' end, v_seen, v_ms;
  end if;
  raise exception 'CHK<<PROBE FAILED (%):% |%|%>>', case when v_new then 'with this file' else 'LIVE' end, v_fail, v_seen, v_ms;
end $probe$;
