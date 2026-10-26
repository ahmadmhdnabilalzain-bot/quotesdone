-- OPERATIONAL 86-CATEGORY ROUTING LAYER (2 Aug 2026).
-- The live catalogue public.catalog_supplier_categories already holds exactly 86 rows and its slugs
-- are production values that other tables and URLs depend on. The supplied route manifests carry an
-- EXPECTED slug which may differ; the pack says resolve by num and never overwrite the live slug.
-- These tables therefore key on catalog_num and hold the expected slug only as evidence, never as a
-- source of truth.

create table if not exists public.kb_operational_route (
  catalog_num int primary key,
  route_key text unique not null,
  expected_catalog_slug text,
  catalog_name text not null,
  route_type text not null,
  coverage_status text not null,
  version text not null,
  manifest jsonb not null,
  ingestion_run_id uuid,
  updated_at timestamptz not null default now()
);

create table if not exists public.kb_operational_route_map (
  catalog_num int not null references public.kb_operational_route(catalog_num) on delete cascade,
  package_slug text not null,
  subcategory_slug text not null,
  priority text not null default 'primary',
  package_zip text,
  package_number int,
  primary key (catalog_num, package_slug, subcategory_slug)
);
create index if not exists kb_op_route_map_pkg_idx on public.kb_operational_route_map (package_slug, subcategory_slug);

-- The deterministic first pass. weight lets a specific phrase ("DEWA NOC") beat a generic one
-- ("electrical"); negative lets a phrase actively push a route DOWN, which is how "lift" is kept
-- away from forklift and pallet-truck requests.
create table if not exists public.kb_operational_alias (
  catalog_num int not null references public.kb_operational_route(catalog_num) on delete cascade,
  language text not null,
  alias text not null,
  alias_norm text not null,
  weight int not null default 2,
  negative boolean not null default false,
  source text,
  primary key (catalog_num, language, alias)
);
create index if not exists kb_op_alias_norm_idx on public.kb_operational_alias (alias_norm);
create index if not exists kb_op_alias_lang_idx on public.kb_operational_alias (language, negative);

create table if not exists public.kb_operational_route_test (
  test_id text primary key,
  catalog_num int,
  input text not null,
  expected_action text not null,
  expected jsonb,
  last_result jsonb,
  last_run_at timestamptz
);
create index if not exists kb_op_route_test_num_idx on public.kb_operational_route_test (catalog_num);

-- ACCEPTANCE VIEW. The pack requires proof that all 86 live routes are mapped and none is empty.
-- Driven from the LIVE catalogue, left-joined to the imported routes, so an unmapped live category
-- shows up as UNMAPPED rather than simply being absent.
create or replace view public.v_kb_operational_86_coverage as
select c.num,
       c.slug  as live_catalog_slug,
       c.name  as live_catalog_name,
       r.route_key,
       r.expected_catalog_slug,
       (r.expected_catalog_slug is distinct from c.slug) as slug_differs,
       r.route_type,
       r.coverage_status,
       count(m.subcategory_slug) as mapped_subcategories,
       count(distinct m.package_slug) as mapped_packages,
       case when r.catalog_num is null then 'UNMAPPED'
            when count(m.subcategory_slug) = 0 then 'EMPTY'
            else 'MAPPED' end as verdict
from public.catalog_supplier_categories c
left join public.kb_operational_route r on r.catalog_num = c.num
left join public.kb_operational_route_map m on m.catalog_num = r.catalog_num
group by c.num, c.slug, c.name, r.route_key, r.expected_catalog_slug, r.route_type, r.coverage_status, r.catalog_num
order by c.num;

comment on view public.v_kb_operational_86_coverage is
  'Acceptance proof for the knowledge import: every live supplier category must read MAPPED with at least one mapped subcategory. slug_differs=true is expected and harmless - the live slug wins by design, the expected slug is kept only as import evidence.';

alter table public.kb_operational_route enable row level security;
alter table public.kb_operational_route_map enable row level security;
alter table public.kb_operational_alias enable row level security;
alter table public.kb_operational_route_test enable row level security;
revoke all on public.kb_operational_route, public.kb_operational_route_map,
              public.kb_operational_alias, public.kb_operational_route_test from anon, authenticated;
