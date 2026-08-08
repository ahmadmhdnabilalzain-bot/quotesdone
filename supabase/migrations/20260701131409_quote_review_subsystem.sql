-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260701131409   name: quote_review_subsystem
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- One review per (inquiry, supplier). Holds the agent<->supplier detailing session + binding freeze.
create table if not exists quote_reviews (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null,
  supplier_id bigint not null,
  status text not null default 'open',            -- open | complete
  original_file_path text,
  original_file_name text,
  extracted jsonb,                                -- raw quote_extract proposal (line_items etc.)
  currency text default 'AED',
  total_amount numeric,                           -- current committed total
  completed_at timestamptz,
  committed_hash text,                            -- sha256 of frozen committed items = tamper-proof record
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(inquiry_id, supplier_id)
);

-- The recorded conversation: agent questions + supplier answers, with attachments (e.g. sub-quotes).
create table if not exists quote_review_messages (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references quote_reviews(id) on delete cascade,
  role text not null,                             -- agent | supplier
  body text,
  attachments jsonb default '[]'::jsonb,          -- [{path,name,kind}]
  created_at timestamptz default now()
);

-- The confirmed, detailed line items = the binding spec sheet.
create table if not exists quote_committed_items (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references quote_reviews(id) on delete cascade,
  seq int default 0,
  description text,                               -- generic line label (e.g. "CCTV cameras")
  brand text,                                     -- committed brand (internal + customer unless hide_brand)
  model text,                                     -- committed model / part no.
  spec text,                                      -- committed spec (resolution, size, storage, tier...)
  qty text,
  unit_price numeric,
  line_amount numeric,
  warranty text,
  source text default 'own',                      -- own | outsourced
  sub_quote_path text,                            -- attached sub-supplier quotation (proof)
  sub_cost numeric,                               -- outsourced base cost
  markup_pct numeric,                             -- supplier's markup on the sub-cost
  customer_description text,                       -- curated anonymized text shown to the customer
  hide_brand boolean default false,               -- true when the brand is supplier-identifying
  confirmed boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists idx_qreviews_sup on quote_reviews(supplier_id);
create index if not exists idx_qrmsg_review on quote_review_messages(review_id, created_at);
create index if not exists idx_qcitems_review on quote_committed_items(review_id, seq);

-- Link the final quote row to its review + freeze markers.
alter table quotes add column if not exists review_id uuid;
alter table quotes add column if not exists review_status text;       -- open | complete
alter table quotes add column if not exists committed_at timestamptz;
alter table quotes add column if not exists committed_hash text;
alter table quotes add column if not exists committed_items jsonb;     -- frozen snapshot at submit

alter table quote_reviews enable row level security;
alter table quote_review_messages enable row level security;
alter table quote_committed_items enable row level security;

