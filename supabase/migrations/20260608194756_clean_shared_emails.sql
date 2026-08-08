-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260608194756   name: clean_shared_emails
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.leads add column if not exists email_shared boolean default false;

-- flag mild duplicates (2-5 companies share the email): keep but mark cautious
with g as (select email, count(*) c from leads where email is not null and email<>'' group by email having count(*) between 2 and 5)
update leads l set email_shared = true
from g where l.email = g.email;

-- null out junk emails (shared by >5 companies = scrape artifact, no single real owner)
with g as (select email, count(*) c from leads where email is not null and email<>'' group by email having count(*) > 5)
update leads l set email = null, email_domain = null, email_verified = null, email_shared = false
from g where l.email = g.email;
