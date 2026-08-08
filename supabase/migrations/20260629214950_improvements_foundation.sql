-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260629214950   name: improvements_foundation
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- 1) Supplier performance view (feedback loop + scorecard source)
create or replace view supplier_perf as
with base as (
  select l.id as supplier_id,
         l.company_name,
         coalesce(l.app_rating, l.rating)::numeric as rating,
         (select count(*) from inquiry_matches m where m.supplier_id = l.id) as matched,
         (select count(*) from quotes q where q.supplier_id = l.id) as quoted,
         (select count(*) from inquiries i where i.hired_supplier_id = l.id) as won,
         (select count(*) from reviews r where r.supplier_id = l.id) as review_count
  from leads l
  where l.claimed = true
)
select b.*,
       round(quoted::numeric / nullif(matched,0), 3) as quote_rate,
       round(won::numeric    / nullif(quoted,0), 3)  as win_rate,
       round( coalesce(rating,0)/5.0*0.50
            + coalesce(won::numeric/nullif(quoted,0),0)*0.35
            + least(quoted,10)/10.0*0.15 , 3) as perf_score
from base b;

-- 2) Fraud guard: disposable-email blocklist + helper
create table if not exists app_blocked_domains (
  domain text primary key,
  reason text default 'disposable',
  created_at timestamptz default now()
);
insert into app_blocked_domains(domain) values
 ('mailinator.com'),('guerrillamail.com'),('10minutemail.com'),('yopmail.com'),
 ('trashmail.com'),('sharklasers.com'),('getnada.com'),('dispostable.com'),
 ('maildrop.cc'),('temp-mail.org'),('tempmail.com'),('throwawaymail.com'),
 ('fakeinbox.com'),('mailnesia.com'),('mintemail.com'),('mohmal.com'),
 ('emailondeck.com'),('discard.email'),('spam4.me'),('grr.la'),
 ('moakt.com'),('luxusmail.org'),('tempr.email'),('inboxkitten.com')
on conflict (domain) do nothing;

create or replace function is_disposable_email(p_email text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from app_blocked_domains d
    where d.domain = lower(split_part(p_email,'@',2))
  );
$$;
revoke execute on function is_disposable_email(text) from anon, authenticated, public;

-- 3) PDPL self-service request store
create table if not exists pdpl_requests (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('export','delete')),
  email text not null,
  role text,
  details text,
  status text not null default 'received',
  created_at timestamptz default now(),
  handled_at timestamptz,
  handled_by text
);
alter table pdpl_requests enable row level security;

-- 4) Founder alert log
create table if not exists founder_alerts (
  id uuid primary key default gen_random_uuid(),
  level text default 'info',
  event text not null,
  detail text,
  channel text,
  created_at timestamptz default now()
);
alter table founder_alerts enable row level security;

-- 5) Duplicate-inquiry detector (trigram text similarity, last 48h, same customer)
create extension if not exists pg_trgm;
create or replace function recent_duplicate_inquiry(p_customer uuid, p_summary text, p_window interval default interval '48 hours')
returns uuid language sql stable security definer set search_path = public, pg_temp as $$
  select i.id
  from inquiries i
  where i.customer_id = p_customer
    and i.created_at > now() - p_window
    and p_summary is not null and length(p_summary) > 12
    and similarity(coalesce(i.summary,''), p_summary) > 0.55
  order by i.created_at desc
  limit 1;
$$;
revoke execute on function recent_duplicate_inquiry(uuid,text,interval) from anon, authenticated, public;

