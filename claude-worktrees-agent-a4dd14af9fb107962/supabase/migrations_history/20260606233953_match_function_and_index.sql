-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260606233953   name: match_function_and_index
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create index if not exists leads_embedding_idx
  on public.leads using hnsw (embedding vector_cosine_ops);

create or replace function public.match_suppliers(
  query_embedding vector(256),
  match_count int default 10,
  p_emirate text default null,
  p_role text default null,
  p_product text default null,
  p_min_rating numeric default null
)
returns table (
  id bigint, company_name text, emirate text, business_role text,
  products text, services text, phone text, email text, whatsapp text,
  website text, rating numeric, reviews integer, capability_summary text,
  similarity float
)
language sql stable
as $$
  select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
         l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
         1 - (l.embedding <=> query_embedding) as similarity
  from public.leads l
  where l.embedding is not null
    and (p_emirate is null or l.emirate ilike p_emirate)
    and (p_role    is null or l.business_role = p_role)
    and (p_product is null or l.products ilike '%'||p_product||'%' or l.capability_summary ilike '%'||p_product||'%')
    and (p_min_rating is null or l.rating >= p_min_rating)
  order by l.embedding <=> query_embedding
  limit match_count;
$$;

-- re-secure base table
revoke select, insert, update on public.leads from anon;
alter table public.leads enable row level security;

