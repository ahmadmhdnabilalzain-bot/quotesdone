-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711231217   name: add_locale_to_customers_and_leads
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Persisted language preference so every backend path (notifications, quote
-- comparison, documents, agents) can honour the customer/supplier's choice,
-- instead of only text-detecting. Default 'en'; app sets 'ar' when they switch.
alter table public.customers add column if not exists locale text not null default 'en';
alter table public.leads     add column if not exists locale text not null default 'en';
alter table public.customers add constraint customers_locale_chk check (locale in ('en','ar')) not valid;
alter table public.leads     add constraint leads_locale_chk     check (locale in ('en','ar')) not valid;
