-- REFERENCE ONLY. Reconcile with current schema before creating anything.

create table if not exists public.supplier_catalog (
  id uuid primary key default gen_random_uuid(),
  supplier_id bigint not null references public.leads(id),
  source_document_path text,
  source_hash text,
  version integer not null default 1,
  status text not null default 'processing',
  extracted_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique(supplier_id, source_hash)
);

create table if not exists public.supplier_product (
  id uuid primary key default gen_random_uuid(),
  supplier_id bigint not null references public.leads(id),
  catalog_id uuid references public.supplier_catalog(id),
  external_key text,
  name text not null,
  category_slug text,
  subcategory_slug text,
  brand text,
  model text,
  description text,
  attributes jsonb not null default '{}'::jsonb,
  certifications jsonb not null default '[]'::jsonb,
  documents jsonb not null default '[]'::jsonb,
  status text not null default 'draft',
  evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(supplier_id, external_key)
);

create table if not exists public.supplier_product_variant (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.supplier_product(id) on delete cascade,
  sku text,
  attributes jsonb not null default '{}'::jsonb,
  price_policy jsonb,
  lead_time_policy jsonb,
  active boolean not null default true,
  unique(product_id, sku)
);

create table if not exists public.supplier_opportunity_score (
  supplier_id bigint not null references public.leads(id),
  inquiry_id uuid not null references public.inquiries(id),
  score numeric not null,
  eligibility boolean not null,
  reasons jsonb not null default '[]'::jsonb,
  risks jsonb not null default '[]'::jsonb,
  calculated_at timestamptz not null default now(),
  algorithm_version text not null,
  primary key(supplier_id, inquiry_id)
);

create table if not exists public.supplier_negotiation_policy (
  supplier_id bigint primary key references public.leads(id),
  policy jsonb not null default '{}'::jsonb,
  approved_by text,
  approved_at timestamptz,
  updated_at timestamptz not null default now()
);

-- Add strict RLS so suppliers can only see/edit their own rows and customers never see private supplier commercial policy.
