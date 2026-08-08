-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260609160319   name: ratings_and_reviews
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Customer-given app ratings (one per completed deal)
create table if not exists public.reviews (
  id bigint generated always as identity primary key,
  supplier_id bigint references public.leads(id),
  customer_id uuid references public.customers(id),
  inquiry_id uuid references public.inquiries(id),
  transaction_id uuid references public.transactions(id) unique,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz default now()
);
alter table public.reviews enable row level security;  -- locked: service role only

-- Maintained aggregates on the supplier
alter table public.leads
  add column if not exists app_rating numeric,
  add column if not exists app_reviews int default 0;

-- Recompute a supplier's in-app rating from the reviews table
create or replace function public.recompute_supplier_rating(p_supplier bigint)
returns void language sql as $$
  update public.leads l set
    app_rating  = (select round(avg(rating)::numeric, 2) from public.reviews r where r.supplier_id = p_supplier),
    app_reviews = (select count(*)::int from public.reviews r where r.supplier_id = p_supplier)
  where l.id = p_supplier;
$$;
