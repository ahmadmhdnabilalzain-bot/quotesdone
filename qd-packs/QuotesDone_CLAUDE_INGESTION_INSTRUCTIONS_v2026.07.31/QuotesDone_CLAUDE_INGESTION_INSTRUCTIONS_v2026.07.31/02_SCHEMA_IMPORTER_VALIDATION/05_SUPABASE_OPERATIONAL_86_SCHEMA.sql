-- QuotesDone operational 86-category knowledge crosswalk
create table if not exists public.kb_operational_route (
  catalog_num int primary key, route_key text unique not null, expected_catalog_slug text, catalog_name text not null,
  route_type text not null, coverage_status text not null, version text not null, manifest jsonb not null, updated_at timestamptz default now()
);
create table if not exists public.kb_operational_route_map (
  catalog_num int not null references public.kb_operational_route(catalog_num) on delete cascade,
  package_slug text not null, subcategory_slug text not null, priority text not null default 'primary', package_zip text,
  primary key(catalog_num,package_slug,subcategory_slug)
);
create table if not exists public.kb_operational_alias (
  catalog_num int not null references public.kb_operational_route(catalog_num) on delete cascade,
  language text not null, alias text not null, weight int not null default 2, negative boolean not null default false, source text,
  primary key(catalog_num,language,alias)
);
create table if not exists public.kb_operational_route_test (
  test_id text primary key, catalog_num int, input text not null, expected_action text not null, expected jsonb, last_result jsonb, last_run_at timestamptz
);
create or replace view public.v_kb_operational_86_coverage as
select c.num, c.slug as live_catalog_slug, c.name as live_catalog_name, r.route_key, r.route_type, r.coverage_status,
       count(m.subcategory_slug) as mapped_subcategories,
       case when r.catalog_num is null then 'UNMAPPED' when count(m.subcategory_slug)=0 then 'EMPTY' else 'MAPPED' end as verdict
from public.catalog_supplier_categories c
left join public.kb_operational_route r on r.catalog_num=c.num
left join public.kb_operational_route_map m on m.catalog_num=r.catalog_num
group by c.num,c.slug,c.name,r.route_key,r.route_type,r.coverage_status,r.catalog_num
order by c.num;
-- Importer must resolve live slugs by catalog_supplier_categories.num and must never replace the live catalogue slug with an inferred slug.
