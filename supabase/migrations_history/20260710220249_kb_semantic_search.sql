-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710220249   name: kb_semantic_search
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.kb_chunks add column if not exists embedding_gte vector(384);

create or replace function public.kb_match(query_embedding vector(384), match_count int default 8, p_category text default null)
returns table(id bigint, category text, title text, citation text, content text, similarity double precision)
language sql stable set search_path to 'public','pg_temp' as $$
  select id, category, title, citation, content, 1 - (embedding_gte <=> query_embedding) as similarity
  from public.kb_chunks
  where embedding_gte is not null
    and (p_category is null or category = p_category)
  order by embedding_gte <=> query_embedding
  limit match_count;
$$;
