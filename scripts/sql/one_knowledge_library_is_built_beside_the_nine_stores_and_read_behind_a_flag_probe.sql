-- PROBE (pure, aborted transaction, commits nothing): the library readers against the legacy readers, per seat and
-- language, on the exam's own questions. Seat: it_engineer. 5 Oct 2026. Ledger 1085 stage 2, phase 1.
-- Run it with the library file in front of it before that file is applied, or alone once it is.
--
-- One management-API call must finish inside the gateway's ~100 s, so the probe samples :per questions per seat and
-- language (the first by id), fills the eight small stores in full, and brings into the library only the kb_chunks
-- rows the LEGACY readers put in their candidate pool for a sampled question (their own kb queries: 20 nearest by gte,
-- 20 by ml), FIRST, so kb_chunks is the primary of a merged text as in the real fill order. Both readers therefore rank
-- the same kb pool, and the comparison measures the library and its plumbing, not index luck: a first version that
-- loaded each question's 30 truly nearest kept kb rows found kb rows scoring 0.907 that the legacy HNSW walk over
-- 148,326 rows had missed, and they displaced seat rows (ceo/en 0.444 -> 0.361) - better kb retrieval, which the exam
-- counts as a loss. That effect belongs to the trim (#1204) and to the index, and is measured by the read-only exam
-- run over the filled library before the flag is set (phase 2). The gte path is scored with the
-- question's own vector; the ml path with the question's gte vector plus, as the ml query, the ml vector of the
-- question's first expected record (the questions carry no ml vector until #1203), so its recall is an upper-bound
-- comparison of the two readers, not a language score. Output per path and seat/language: [questions, sum of recall@5
-- before, sum after, how many result lists are identical], so slices add up.
-- The HNSW indexes are dropped for the fill and the three gte ones rebuilt before reading (a bulk build is faster than
-- 20,000 inserts); the ml one is not (see below), so the library's kb ml branch is exact here and approximate live.
set local hnsw.iterative_scan = 'relaxed_order';
set local hnsw.ef_search = 100;
do $$
declare
  per constant integer := 6;    -- questions per seat and language
  skip constant integer := 0;   -- leave out the first `skip` of each group: run again with 6, 12 ... for more
  t timestamptz := clock_timestamp(); s text; r record; v jsonb; v_gte jsonb; v_ml jsonb; v_kb integer; t_fill interval;
begin
  if exists (select 1 from public.app_secrets where key = 'knowledge_library_read' and value = 'library') then
    raise exception 'CHK<<the flag is on: the legacy readers would read the library too, so nothing can be compared>>';
  end if;
  -- BEFORE THE APPLY ONLY: the probe drops and rebuilds the library's indexes, which on a live library would lock
  -- readers out for the length of the run. After the apply the read-only exam over the filled library replaces it.
  if (select xmin from pg_class where oid = 'public.knowledge_library'::regclass) <> pg_current_xact_id()::xid then
    raise exception 'CHK<<the library already exists: run this probe only with the library file in front of it, before the apply>>';
  end if;
  -- the writer path, on ZZ DEMO rows: an insert, a text edit and a delete of agent_knowledge reach the library
  declare d bigint; n1 int; c1 text; n2 int; begin
    insert into public.agent_knowledge (agent_key, topic, content) values ('ceo', 'ZZ DEMO library probe', 'ZZ DEMO library probe text one')
      returning id into d;
    select count(*) into n1 from public.knowledge_library_origin where origin_store = 'agent_knowledge' and origin_id = d::text;
    update public.agent_knowledge set content = 'ZZ DEMO library probe text two' where id = d;
    select l.content into c1 from public.knowledge_library l join public.knowledge_library_origin o on o.library_id = l.id
     where o.origin_store = 'agent_knowledge' and o.origin_id = d::text;
    delete from public.agent_knowledge where id = d;
    select count(*) into n2 from public.knowledge_library where content like 'ZZ DEMO library probe text%';
    if n1 <> 1 or c1 is distinct from 'ZZ DEMO library probe text two' or n2 <> 0 then
      raise exception 'CHK<<{"verdict": "PROBE FAILED", "writer_path": [%, "%", %]}>>', n1, c1, n2;
    end if;
  end;
  drop index public.knowledge_library_kb_hnsw, public.knowledge_library_ops_hnsw, public.knowledge_library_sales_hnsw,
             public.knowledge_vector_ml_library_hnsw;
  create temp table qd_q on commit drop as
    select x.*, (select v.embedding from public.knowledge_vector_ml v where v.row_id = x.expected[1]
                  and v.src in ('sales_knowledge', 'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge',
                                'ceo_knowledge', 'support_knowledge') limit 1) m
      from (select q.*, row_number() over (partition by seat, lang order by id) rn
              from public.seat_knowledge_eval_question q where q.embedding is not null) x where rn > skip and rn <= skip + per;
  -- the legacy readers' kb_chunks pool for each sampled question: their own two kb queries and settings. (An exact
  -- search on both sides was tried: it does not finish inside the gateway's limit. So both readers walk an HNSW
  -- index with relaxed_order, which can order the 6th neighbour differently over different row sets; that noise
  -- averages out over the exam, and same_ids shows how often it moves a list.)
  create temp table qd_kb on commit drop as
    select k.id from qd_q q cross join lateral (
      select c.id from public.kb_chunks c where c.embedding_gte is not null order by c.embedding_gte <=> q.embedding limit 20) k
    union
    select k.row_id::bigint from qd_q q cross join lateral (
      select v.row_id from public.knowledge_vector_ml v where v.src = 'kb_chunks' and q.m is not null
       order by v.embedding <=> q.m limit 20) k;
  for r in select id from qd_kb order by id loop
    if public.fn_knowledge_library_sync('kb_chunks', r.id::text) = 'absent' then
      -- an uncited qd_kb_pack row (#1204 deletes it; the library never takes it): held here ONLY so both readers
      -- rank the same pool, then the share of results it fills is reported as qd_rows
      with c as (select * from public.kb_chunks where id = r.id),
      l as (insert into public.knowledge_library (origin_store, origin_id, title, content, seats, source_ref, verified, embedding_gte)
            select 'kb_chunks', c.id::text, c.title, c.content, '{*}', c.citation, true, c.embedding_gte from c returning id)
      insert into public.knowledge_library_origin (origin_store, origin_id, library_id, source_ref)
      select 'kb_chunks', r.id::text, l.id, null from l;
      insert into public.knowledge_vector_ml (src, row_id, text_hash, embedding, embedded_at)
      select 'knowledge_library', o.library_id::text, v.text_hash, v.embedding, now()
        from public.knowledge_library_origin o join public.knowledge_vector_ml v on v.src = 'kb_chunks' and v.row_id = o.origin_id
       where o.origin_store = 'kb_chunks' and o.origin_id = r.id::text;
    end if;
  end loop;
  select count(*) into v_kb from public.knowledge_library_origin where origin_store = 'kb_chunks';
  foreach s in array array['ops_knowledge', 'agent_knowledge', 'sales_knowledge', 'ceo_knowledge', 'support_knowledge',
                           'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge'] loop
    loop
      v := public.fn_knowledge_library_fill_page(s, 5000);
      exit when (v->>'page')::int = 0 or (v->>'left')::int = 0;
    end loop;
  end loop;
  create index knowledge_library_kb_hnsw on public.knowledge_library using hnsw (embedding_gte vector_cosine_ops) where origin_store = 'kb_chunks';
  create index knowledge_library_ops_hnsw on public.knowledge_library using hnsw (embedding_gte vector_cosine_ops) where origin_store = 'ops_knowledge';
  create index knowledge_library_sales_hnsw on public.knowledge_library using hnsw (embedding_gte vector_cosine_ops) where origin_store = 'sales_knowledge';
  -- NOT rebuilt here: with only the sampled kb rows in the library, kb_chunks would be ~3% of that index instead of
  -- ~80%, and the filtered walk of the kb ml branch takes ~4 s a call. Without it the branch is read exactly.
  t_fill := clock_timestamp() - t;

  create temp table qd_r on commit drop as
    select q.id, q.seat, q.lang, q.expected,
           public.fn_reason_retrieve(q.seat, q.embedding, 6) ga, public.fn_reason_retrieve_library(q.seat, q.embedding, 6) gb,
           case when q.m is not null then public.fn_reason_retrieve_ml(q.seat, q.m, q.embedding, 6) end ma,
           case when q.m is not null then public.fn_reason_retrieve_ml_library(q.seat, q.m, q.embedding, 6) end mb
      from qd_q q;
  create temp table qd_s on commit drop as
    select rr.seat, rr.lang, x.path, x.before, x.after, x.same
      from qd_r rr cross join lateral (values ('gte', rr.ga, rr.gb), ('ml', rr.ma, rr.mb)) p(path, a, b)
      cross join lateral (select p.path,
        (select count(distinct regexp_replace(e->>'id', '@ar$', '')) from jsonb_array_elements(p.a) with ordinality t(e, i)
          where i <= 5 and regexp_replace(e->>'id', '@ar$', '') = any(rr.expected))::numeric
          / (select count(distinct e) from unnest(rr.expected) e) before,
        (select count(distinct regexp_replace(e->>'id', '@ar$', '')) from jsonb_array_elements(p.b) with ordinality t(e, i)
          where i <= 5 and regexp_replace(e->>'id', '@ar$', '') = any(rr.expected))::numeric
          / (select count(distinct e) from unnest(rr.expected) e) after,
        ((select array_agg((e->>'source') || ':' || (e->>'id')) from jsonb_array_elements(p.a) e)
          is not distinct from (select array_agg((e->>'source') || ':' || (e->>'id')) from jsonb_array_elements(p.b) e))::int same) x
     where p.a is not null;
  -- per path and seat/language: [questions, sum of recall before, sum after, lists identical] - sums, so slices add up
  select jsonb_object_agg(k, o) into v_gte from (
    select seat || '/' || lang k, jsonb_build_array(count(*), round(sum(before), 3), round(sum(after), 3), sum(same)) o
      from qd_s where path = 'gte' group by seat, lang) z;
  select jsonb_object_agg(k, o) into v_ml from (
    select seat || '/' || lang k, jsonb_build_array(count(*), round(sum(before), 3), round(sum(after), 3), sum(same)) o
      from qd_s where path = 'ml' group by seat, lang) z;
  raise exception 'CHK<<{"verdict": "%", "worst_drop": %, "fill": "%", "secs": %, "kb_rows": %, "library_rows": %, "gte": %, "ml": %}>>',
    -- the slice's verdict is on each PATH over every question of the slice: with 6 questions a group, one swapped
    -- 5th place moves a group by 0.06-0.17. The per-seat rule (no seat/language drops more than 0.02) is applied to
    -- the sums of all slices, which is what the output is shaped for.
    case when (select max(d) from (select avg(before) - avg(after) d from qd_s group by path) z) <= 0.02 then 'PROBE OK' else 'PROBE FAILED' end,
    (select round(max(d), 3) from (select avg(before) - avg(after) d from qd_s group by path, seat, lang) z),
    t_fill, round(extract(epoch from clock_timestamp() - t)), v_kb, (select count(*) from public.knowledge_library), v_gte, v_ml;
end $$;
