-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260606224832   name: create_leads_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists public.leads (
  id            bigint generated always as identity primary key,
  sector        text,
  sub_type      text,
  company_name  text not null,
  phone         text,
  phone_e164    text,
  website       text,
  maps_website  text,
  domain        text,
  street        text,
  city          text,
  emirate       text,
  rating        numeric,
  reviews       integer,
  rating_maps   numeric,
  reviews_maps  integer,
  categories    text,
  maps_url      text,
  place_id      text unique,
  email         text,
  email_domain  text,
  email_verified text,
  instagram     text,
  whatsapp      text,
  facebook      text,
  website_status text,
  permanently_closed boolean default false,
  enrich_source text,
  source        text,
  scraped_at    date,
  contacted     boolean default false,
  signed        boolean default false,
  notes         text,
  created_at    timestamptz default now()
);

create index if not exists leads_email_idx    on public.leads (email);
create index if not exists leads_emirate_idx  on public.leads (emirate);
create index if not exists leads_sector_idx   on public.leads (sector);
create index if not exists leads_has_email_idx on public.leads ((email is not null));

-- temporary load access for the anon/publishable key (revoked after load)
grant usage on schema public to anon;
grant select, insert on public.leads to anon;
grant usage, select on sequence public.leads_id_seq to anon;

