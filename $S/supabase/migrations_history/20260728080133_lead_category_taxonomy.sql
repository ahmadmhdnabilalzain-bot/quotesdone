-- Two genuine holes in the 84-category catalogue, confirmed against the lead data and already
-- flagged by lead_trade_map ("NO CATALOGUE CATEGORY"). 496 signage + 104 printing + 86 lift leads had
-- nowhere to sit, which means any buyer asking for a shopfront sign or a lift service contract would
-- have received zero quotes.
insert into catalog_supplier_categories (slug, num, name, regulated, sort) values
  ('signage-and-printing-suppliers', 85, 'Signage & Printing Suppliers', false, 85),
  ('lifts-and-escalator-suppliers',  86, 'Lifts & Escalator Suppliers',  true,  86)
on conflict (slug) do nothing;

-- The lexicon. Classification is deterministic and auditable: every assignment can be traced back to
-- the exact patterns that fired. Deliberately NOT an LLM pass - 20,464 leads through a model is real
-- money for a job that keyword evidence does better and repeatably.
create table if not exists category_keyword (
  id bigserial primary key,
  slug text not null references catalog_supplier_categories(slug) on delete cascade,
  pattern text not null,          -- lowercase; matched on word boundaries against the normalised haystack
  weight int not null default 2,  -- 3 decisive, 2 strong, 1 weak/supporting
  negative boolean not null default false,  -- fires against the slug instead of for it
  note text,
  created_at timestamptz not null default now()
);
create unique index if not exists category_keyword_uidx on category_keyword (slug, pattern);
create index if not exists category_keyword_slug_idx on category_keyword (slug);

-- Many-to-many, because a real electromechanical contractor serves electrical AND plumbing AND HVAC.
-- leads.sector is deliberately left untouched: route_inquiry and the invite system read it today, so
-- this lands as a pure addition that cannot break matching while it is being validated.
create table if not exists lead_category (
  lead_id bigint not null references leads(id) on delete cascade,
  slug text not null references catalog_supplier_categories(slug) on delete cascade,
  score int not null default 0,
  is_primary boolean not null default false,
  method text not null default 'keyword_v1',
  evidence text,                  -- the patterns that fired, so a wrong assignment is diagnosable
  created_at timestamptz not null default now(),
  primary key (lead_id, slug)
);
create index if not exists lead_category_slug_idx on lead_category (slug);
create unique index if not exists lead_category_primary_uidx on lead_category (lead_id) where is_primary;

alter table category_keyword enable row level security;
alter table lead_category   enable row level security;
revoke all on category_keyword from anon, authenticated;
revoke all on lead_category   from anon, authenticated;