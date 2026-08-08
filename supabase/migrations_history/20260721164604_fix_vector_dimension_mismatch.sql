-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721164604   name: fix_vector_dimension_mismatch
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #75: match_suppliers compared against leads.embedding = vector(256), but every caller generates
-- gte-small vectors = 384 dims. Result: "different vector dimensions 256 and 384" on EVERY call,
-- caught and swallowed, so hybrid retrieval silently degraded to an unranked fallback on 100% of RFQs.
--
-- Root cause was a half-finished migration: embed_leads writes leads.embedding_gte (384, the live
-- embedder), but nothing ever read that column, while leads.embedding (256, 4,635 rows) was still
-- being read and is no longer written by anything.
--
-- Fix: read the column the live embedder actually writes. This makes the legacy fallback path work
-- again; it is no longer the primary path (capability gates are), but a silently-broken fallback is
-- worse than no fallback.
create or replace function public.match_suppliers(
  query_embedding vector,
  match_count integer default 10,
  p_emirate text default null,
  p_role text default null,
  p_product text default null,
  p_min_rating numeric default null
)
returns table(id bigint, company_name text, emirate text, business_role text, products text, services text,
              phone text, email text, whatsapp text, website text, rating numeric, reviews integer,
              capability_summary text, similarity double precision)
language sql stable
set search_path to 'public','pg_temp'
as $$
  select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
         l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
         1 - (l.embedding_gte <=> query_embedding) as similarity
  from public.leads l
  left join public.supplier_perf sp on sp.supplier_id = l.id
  where l.embedding_gte is not null
    and coalesce(l.matching_blocked,false)=false
    and (p_emirate is null or l.emirate ilike p_emirate)
    and (p_role    is null or l.business_role = p_role)
    and (p_product is null or l.products ilike '%'||p_product||'%' or l.capability_summary ilike '%'||p_product||'%')
    and (p_min_rating is null or l.rating >= p_min_rating)
  order by ( (1 - (l.embedding_gte <=> query_embedding))
             + 0.05 * coalesce(sp.perf_score,0)
             + case when l.claimed then 0.03 else 0 end
             + case when l.approval_status = 'approved' then 0.02 else 0 end ) desc
  limit match_count;
$$;

-- the 384-dim column had no ANN index
create index if not exists idx_leads_embedding_gte
  on public.leads using hnsw (embedding_gte vector_cosine_ops);

comment on column public.leads.embedding is
  'LEGACY vector(256). No longer written by anything and no longer read since the 2026-07-21 dimension fix. Retained for rollback only; safe to drop once embedding_gte coverage is complete.';
