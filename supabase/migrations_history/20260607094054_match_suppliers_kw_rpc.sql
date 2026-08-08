-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260607094054   name: match_suppliers_kw_rpc
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create or replace function public.match_suppliers_kw(
  p_keywords text[] default '{}',
  p_category text default null,
  p_emirate  text default null,
  p_role     text default null,
  p_min_rating numeric default null,
  p_limit int default 8
)
returns table (
  id bigint, company_name text, emirate text, business_role text,
  products text, services text, phone text, email text, whatsapp text,
  website text, rating numeric, reviews integer, capability_summary text,
  match_score int
)
language sql stable as $$
  select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
         l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
         (
           (select count(*) from unnest(p_keywords) k
              where l.products ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%'
                 or l.categories ilike '%'||k||'%' or l.company_name ilike '%'||k||'%')::int
           + case when p_category is not null and l.sector = p_category then 1 else 0 end
         ) as match_score
  from public.leads l
  where (p_emirate is null or l.emirate ilike p_emirate)
    and (p_role    is null or l.business_role = p_role)
    and (p_min_rating is null or l.rating >= p_min_rating)
    and (
      (p_category is not null and l.sector = p_category)
      or exists (select 1 from unnest(p_keywords) k
                   where l.products ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%'
                      or l.categories ilike '%'||k||'%' or l.company_name ilike '%'||k||'%')
    )
  order by match_score desc, l.rating desc nulls last, l.reviews desc nulls last
  limit coalesce(p_limit, 8);
$$;

