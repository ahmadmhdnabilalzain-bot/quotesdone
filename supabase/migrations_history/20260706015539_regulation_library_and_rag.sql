-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706015539   name: regulation_library_and_rag
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Regulation Library
create table if not exists regulations (
  id bigint generated always as identity primary key,
  authority text not null,
  jurisdiction text,
  categories text[] default '{}',
  title text not null,
  doc_ref text,
  summary text,
  key_requirements jsonb default '[]'::jsonb,
  source_url text,
  effective_date date,
  version int not null default 1,
  status text not null default 'active',
  body text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists regulations_cats on regulations using gin(categories);
alter table regulations enable row level security;
revoke all on regulations from anon, authenticated;

-- Unified retrieval corpus (RAG source of truth)
create table if not exists kb_chunks (
  id bigint generated always as identity primary key,
  source_kind text not null,   -- regulation | trade | material | standard
  source_id text,
  category text,
  title text,
  content text not null,
  citation text,
  effective_date date,
  fts tsvector generated always as (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(content,''))) stored,
  created_at timestamptz default now()
);
create index if not exists kb_chunks_fts on kb_chunks using gin(fts);
create index if not exists kb_chunks_cat on kb_chunks(category);
alter table kb_chunks enable row level security;
revoke all on kb_chunks from anon, authenticated;

-- Retrieval: FTS ranked, category-boosted, cited snippets
create or replace function kb_query(p_query text, p_category text default null, p_limit int default 8)
returns table(source_kind text, category text, title text, snippet text, citation text, effective_date date, rank real)
language sql stable as $$
  with q as (select websearch_to_tsquery('english', coalesce(p_query,'')) as tsq)
  select c.source_kind, c.category, c.title, left(c.content, 700) as snippet, c.citation, c.effective_date,
    (ts_rank(c.fts, q.tsq) + case when p_category is not null and c.category = p_category then 0.4 else 0 end)::real as rank
  from kb_chunks c, q
  where coalesce(p_query,'') = '' or c.fts @@ q.tsq
  order by rank desc nulls last, c.effective_date desc nulls last
  limit greatest(1, least(coalesce(p_limit,8), 25));
$$;
revoke all on function kb_query(text,text,int) from anon, authenticated;

-- Knowledge Factory refresh: rebuild retrieval corpus from all sources (idempotent)
create or replace function kb_sync() returns jsonb language plpgsql as $$
declare n int;
begin
  delete from kb_chunks where source_kind in ('regulation','trade');
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'regulation', r.id::text, cat, r.title,
    coalesce(r.summary,'') || case when jsonb_array_length(coalesce(r.key_requirements,'[]'::jsonb))>0
      then E'\nKey requirements: ' || (select string_agg(x, '; ') from jsonb_array_elements_text(r.key_requirements) x) else '' end,
    r.authority || ' — ' || r.title || coalesce(' [' || r.source_url || ']','') || coalesce(' (effective ' || r.effective_date::text || ')',''),
    r.effective_date
  from regulations r
  left join lateral unnest(case when array_length(r.categories,1) is null then array[null::text] else r.categories end) as cat on true
  where r.status = 'active';
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'trade', ak.id::text, ak.agent_key, ak.topic, ak.content,
    'QuotesDone trade knowledge: ' || coalesce(ak.agent_key,'') || ' / ' || coalesce(ak.topic,''), null
  from agent_knowledge ak;
  select count(*) into n from kb_chunks;
  return jsonb_build_object('chunks', n);
end $$;
revoke all on function kb_sync() from anon, authenticated;
