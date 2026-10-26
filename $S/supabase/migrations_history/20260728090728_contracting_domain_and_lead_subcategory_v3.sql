-- WHY DOMAIN 67 EXISTS. Domain 16 (construction-civil-and-building-materials) deliberately lists only
-- MATERIALS - steel, cement, aggregates, formwork, roofing, road materials. Nothing in any of the
-- three taxonomies covers a firm that actually EXECUTES construction, yet 2,613 leads (12.8% of the
-- base) are exactly that, and "build my villa extension" or "renovate this floor" is an ordinary RFQ
-- for a UAE quote marketplace. Without this domain those requests match nobody and receive no quotes.
insert into catalog_domains (slug, num, name, sort) values
  ('general-contracting-and-civil-works', 67, 'General Contracting & Civil Works', 67)
on conflict (slug) do nothing;

insert into catalog_subcategories (domain_slug, name, slug, sort) values
  ('general-contracting-and-civil-works', 'General building contracting',           'general-building-contracting',            1),
  ('general-contracting-and-civil-works', 'Villa & residential construction',       'villa-and-residential-construction',      2),
  ('general-contracting-and-civil-works', 'Commercial & industrial construction',   'commercial-and-industrial-construction',  3),
  ('general-contracting-and-civil-works', 'Renovation & refurbishment',             'renovation-and-refurbishment',            4),
  ('general-contracting-and-civil-works', 'Demolition & dismantling',               'demolition-and-dismantling',              5),
  ('general-contracting-and-civil-works', 'Civil & infrastructure works',           'civil-and-infrastructure-works',          6),
  ('general-contracting-and-civil-works', 'Earthworks, excavation & piling',        'earthworks-excavation-and-piling',        7),
  ('general-contracting-and-civil-works', 'Road works, asphalt & paving',           'road-works-asphalt-and-paving',           8),
  ('general-contracting-and-civil-works', 'Steel structure erection',               'steel-structure-erection',                9),
  ('general-contracting-and-civil-works', 'Handyman & small works',                 'handyman-and-small-works',               10),
  ('general-contracting-and-civil-works', 'Electromechanical contracting',          'electromechanical-contracting',          11)
on conflict do nothing;

-- Lifts and escalators are missing from all three taxonomies as well: the only near match anywhere is
-- "Lifting equipment inspection", which is a TIC service, not a lift supplier. 86 leads, and a trade
-- every multi-storey building in the UAE has to procure.
insert into catalog_subcategories (domain_slug, name, slug, sort) values
  ('mep-mechanical-electrical-plumbing', 'Lifts, elevators & escalators', 'lifts-elevators-and-escalators', 900)
on conflict do nothing;

-- slug was already unique across all 456 rows but was never constrained, so nothing could reference it.
create unique index if not exists catalog_subcategories_slug_uidx on catalog_subcategories (slug);
alter table catalog_subcategories drop constraint if exists catalog_subcategories_slug_key;
alter table catalog_subcategories add constraint catalog_subcategories_slug_key unique using index catalog_subcategories_slug_uidx;

-- Classification now targets the CANONICAL taxonomy. The earlier lead_category table pointed at
-- catalog_supplier_categories, which no production function reads; it is retained only so the two
-- runs can be compared, and is superseded by this one.
create table if not exists lead_subcategory (
  lead_id bigint not null references leads(id) on delete cascade,
  sub_slug text not null references catalog_subcategories(slug) on delete cascade,
  domain_slug text not null,
  score int not null default 0,
  is_primary boolean not null default false,
  method text not null default 'keyword_v2',
  evidence text,
  created_at timestamptz not null default now(),
  primary key (lead_id, sub_slug)
);
create index if not exists lead_subcategory_sub_idx    on lead_subcategory (sub_slug);
create index if not exists lead_subcategory_domain_idx on lead_subcategory (domain_slug);
create unique index if not exists lead_subcategory_primary_uidx on lead_subcategory (lead_id) where is_primary;

create table if not exists subcategory_keyword (
  id bigserial primary key,
  sub_slug text not null references catalog_subcategories(slug) on delete cascade,
  pattern text not null,
  weight int not null default 2,
  negative boolean not null default false,
  note text,
  created_at timestamptz not null default now()
);
create unique index if not exists subcategory_keyword_uidx on subcategory_keyword (sub_slug, pattern);
create index if not exists subcategory_keyword_slug_idx on subcategory_keyword (sub_slug);

alter table lead_subcategory    enable row level security;
alter table subcategory_keyword enable row level security;
revoke all on lead_subcategory, subcategory_keyword from anon, authenticated;