-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724045224   name: marketing_library_store
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Queryable UAE marketing knowledge library. Full depth lives here (retrieved on demand),
-- NOT in agent_knowledge (which loads into context every call). The agent pulls only the
-- few relevant chunks it needs via fn_marketing_library_search.
create table if not exists public.marketing_library (
  id          bigserial primary key,
  category    text not null,     -- consolidated file, e.g. '01_Regulation_Governance_and_Marketing_Operations'
  domain      text,              -- finer domain label if present
  title       text not null,     -- section heading
  content     text not null,     -- section body
  tags        text,              -- keyword hints for retrieval
  source_file text,
  tsv tsvector generated always as (
    to_tsvector('english', coalesce(title,'') || ' ' || coalesce(tags,'') || ' ' || coalesce(content,''))
  ) stored,
  created_at  timestamptz default now()
);
create index if not exists idx_marketing_library_tsv on public.marketing_library using gin(tsv);
create index if not exists idx_marketing_library_category on public.marketing_library(category);

-- Retrieval: websearch-style query, ranked. The marketing agent calls this to pull depth
-- (e.g. 'UAE PDPL consent WhatsApp') and injects the top chunks into its generation prompt.
create or replace function public.fn_marketing_library_search(p_query text, p_limit int default 5)
returns table(id bigint, category text, title text, content text, rank real)
language sql stable as $$
  select l.id, l.category, l.title, l.content,
         ts_rank(l.tsv, websearch_to_tsquery('english', p_query)) as rank
  from public.marketing_library l
  where l.tsv @@ websearch_to_tsquery('english', p_query)
  order by rank desc, l.id
  limit greatest(1, least(coalesce(p_limit,5), 20));
$$;
