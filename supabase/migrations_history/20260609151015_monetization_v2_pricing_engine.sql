-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260609151015   name: monetization_v2_pricing_engine
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================
-- Monetization v2: customer-paid reveal fee + supplier registration
-- ============================================================

-- 1) Single source of truth for all pricing parameters
create table if not exists public.pricing_config (
  id int primary key default 1,
  promo_reveal_rate      numeric not null default 0.02,   -- launch promo: 2%
  promo_reveal_cap       numeric not null default 250,    -- capped at AED 250
  standard_reveal_rate   numeric not null default 0.02,   -- after promo (TBD; defaults to promo for now)
  standard_reveal_cap    numeric not null default 250,    -- after promo (TBD)
  promo_until            timestamptz,                     -- set to launch + 1 month when you go live
  supplier_free_count    int     not null default 1000,   -- first 1000 suppliers register free
  supplier_reg_fee       numeric not null default 100,    -- AED 100 thereafter
  supplier_reg_period    text    not null default 'yearly',
  refund_window_working_days int not null default 3,      -- customer refund deadline
  updated_at timestamptz default now(),
  constraint pricing_config_singleton check (id = 1)
);
insert into public.pricing_config (id) values (1) on conflict (id) do nothing;
alter table public.pricing_config enable row level security; -- locked: service role only

-- 2) Working-days helper (UAE workweek = Mon-Fri; weekend Sat-Sun)
create or replace function public.add_working_days(start_ts timestamptz, n int)
returns timestamptz language plpgsql immutable as $$
declare d timestamptz := start_ts; added int := 0;
begin
  while added < n loop
    d := d + interval '1 day';
    if extract(isodow from d) < 6 then added := added + 1; end if; -- 1..5 = Mon..Fri
  end loop;
  return d;
end $$;

-- 3) Reveal-fee engine: promo-aware, capped, rounded
create or replace function public.reveal_fee(amount numeric, at_time timestamptz default now())
returns numeric language sql stable as $$
  select case when amount is null or amount <= 0 then 0 else (
    select least(
      round(amount * (case when c.promo_until is not null and at_time <= c.promo_until
                           then c.promo_reveal_rate else c.standard_reveal_rate end), 2),
      (case when c.promo_until is not null and at_time <= c.promo_until
            then c.promo_reveal_cap else c.standard_reveal_cap end)
    ) from public.pricing_config c where c.id = 1
  ) end
$$;

-- 4) Supplier registration + extra onboarding doc columns
alter table public.leads
  add column if not exists registration_status   text,          -- 'free' | 'paid' | 'due'
  add column if not exists registration_paid_at  timestamptz,
  add column if not exists registration_expires_at timestamptz,
  add column if not exists registration_fee_due  numeric,
  add column if not exists egr_doc_path text,
  add column if not exists egr_doc_name text,
  add column if not exists egr_number   text;

-- how many suppliers have already registered (for the free-1000 gate)
create or replace function public.registered_supplier_count()
returns int language sql stable as $$
  select count(*)::int from public.leads
  where claimed = true or source in ('self_registered','email_inbound')
$$;

-- 5) Customer-paid reveal fee fields on transactions
alter table public.transactions
  add column if not exists reveal_fee      numeric,
  add column if not exists paid_by         text default 'customer',
  add column if not exists payment_ref     text,        -- processor transaction id (when wired)
  add column if not exists refund_deadline timestamptz,
  add column if not exists refund_status   text;        -- null | 'requested' | 'approved' | 'rejected';
