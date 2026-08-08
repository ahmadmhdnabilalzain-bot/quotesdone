-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260608194324   name: matcher_uses_service_emirates
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

drop function if exists public.match_suppliers_kw(text[],text,text,text,numeric,integer);
create or replace function public.match_suppliers_kw(
  p_keywords text[] default '{}'::text[],
  p_category text default null,
  p_emirate text default null,
  p_role text default null,
  p_min_rating numeric default null,
  p_limit integer default 8
) returns table(
  id bigint, company_name text, emirate text, business_role text, products text, services text,
  phone text, email text, whatsapp text, website text, rating numeric, reviews integer,
  capability_summary text, match_score integer, in_emirate boolean
)
language sql stable as $function$
  with base as (
    select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
           l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
           (
             (select count(*) from unnest(p_keywords) k
                where l.products ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%'
                   or l.categories ilike '%'||k||'%' or l.company_name ilike '%'||k||'%')::int
             + case when p_category is not null and l.sector = p_category then 2 else 0 end
           ) as match_score,
           coalesce(
             p_emirate is not null and (
               l.emirate ilike p_emirate
               or exists (select 1 from unnest(coalesce(l.service_emirates, '{}')) se where se ilike p_emirate)
             ), false) as in_emirate
    from public.leads l
    where coalesce(l.permanently_closed, false) = false
      and (p_role is null or l.business_role = p_role)
      and (p_min_rating is null or l.rating >= p_min_rating)
      and (
        (p_category is not null and l.sector = p_category)
        or exists (select 1 from unnest(p_keywords) k
                     where l.products ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%'
                        or l.categories ilike '%'||k||'%' or l.company_name ilike '%'||k||'%')
      )
  )
  select id, company_name, emirate, business_role, products, services, phone, email, whatsapp,
         website, rating, reviews, capability_summary, match_score, in_emirate
  from base
  order by in_emirate desc, match_score desc, rating desc nulls last, reviews desc nulls last
  limit coalesce(p_limit, 8);
$function$;
