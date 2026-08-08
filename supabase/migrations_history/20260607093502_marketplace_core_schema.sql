-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260607093502   name: marketplace_core_schema
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- ---- margin engine (single source of truth for the tier table) ----
create or replace function public.margin_rate(amount numeric)
returns numeric immutable language sql as $$
  select case
    when amount < 2000  then 0.10
    when amount < 5000  then 0.08
    when amount < 10000 then 0.06
    when amount < 20000 then 0.05
    when amount < 50000 then 0.04
    else 0.03 end
$$;

-- ---- customers (identity hidden from suppliers until reveal) ----
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text,
  phone text,
  email text,
  created_at timestamptz default now()
);

-- ---- inquiries ----
create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id),
  category text,
  emirate text,
  role_needed text,
  raw_input text,           -- original voice/text
  spec jsonb,               -- structured required fields
  summary text,             -- anonymized one-liner shown to suppliers
  keywords text[],
  status text default 'open',   -- open | matched | quoted | revealed | closed | cancelled
  created_at timestamptz default now()
);
create index if not exists inq_status_idx on public.inquiries(status);

-- ---- which suppliers an inquiry was sent to ----
create table if not exists public.inquiry_matches (
  id bigint generated always as identity primary key,
  inquiry_id uuid references public.inquiries(id) on delete cascade,
  supplier_id bigint references public.leads(id),
  similarity numeric,
  sent_at timestamptz default now(),
  unique(inquiry_id, supplier_id)
);

-- ---- quotes (margin computed automatically) ----
create table if not exists public.quotes (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid references public.inquiries(id) on delete cascade,
  supplier_id bigint references public.leads(id),
  quote_amount numeric not null check (quote_amount > 0),
  notes text,
  margin_rate    numeric generated always as (public.margin_rate(quote_amount)) stored,
  app_fee        numeric generated always as (round(quote_amount * public.margin_rate(quote_amount), 2)) stored,
  customer_price numeric generated always as (round(quote_amount * (1 + public.margin_rate(quote_amount)), 2)) stored,
  status text default 'submitted',  -- submitted | accepted | rejected | expired
  created_at timestamptz default now(),
  unique(inquiry_id, supplier_id)
);

-- ---- reveal / transaction (fee owed by supplier to the app) ----
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid references public.quotes(id),
  inquiry_id uuid references public.inquiries(id),
  supplier_id bigint references public.leads(id),
  customer_id uuid references public.customers(id),
  quote_amount numeric,
  app_fee numeric,
  customer_price numeric,
  fee_status text default 'pending',   -- pending | invoiced | paid
  revealed_at timestamptz default now()
);

alter table public.customers     enable row level security;
alter table public.inquiries     enable row level security;
alter table public.inquiry_matches enable row level security;
alter table public.quotes        enable row level security;
alter table public.transactions  enable row level security;

