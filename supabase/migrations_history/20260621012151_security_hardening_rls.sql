-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260621012151   name: security_hardening_rls
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- 1) Lock the 4 tables that had RLS OFF + anon read/write
alter table public.deploy_state   enable row level security;
alter table public.health_state   enable row level security;
alter table public.seo_categories enable row level security;
alter table public.yello_staging  enable row level security;

-- 2) Strip stray anon/authenticated grants on internal + sensitive tables
revoke all on public.deploy_state, public.health_state, public.seo_categories, public.yello_staging,
                public.app_secrets, public.customer_phone_otps, public.customers, public.transactions,
                public.inbound_messages, public.scrape_runs, public.doc_reviews
  from anon, authenticated;

-- 3) Stop anon/signed-in users from invoking internal SECURITY DEFINER functions via RPC
revoke execute on function public.run_auto_deploy()        from anon, authenticated, public;
revoke execute on function public.run_health_check()       from anon, authenticated, public;
revoke execute on function public.run_no_quote_nudges()    from anon, authenticated, public;
revoke execute on function public.run_reveal_nudges()      from anon, authenticated, public;
revoke execute on function public.notify_new_quote_sms()   from anon, authenticated, public;
revoke execute on function public.trg_inquiry_received()   from anon, authenticated, public;
revoke execute on function public.trg_reveal_receipt()     from anon, authenticated, public;
revoke execute on function public.funnel_metrics(integer)  from anon, authenticated;

-- 4) Pin search_path on the flagged functions (defense-in-depth)
alter function public.run_auto_deploy()       set search_path = public, pg_temp;
alter function public.run_health_check()      set search_path = public, pg_temp;
alter function public.run_no_quote_nudges()   set search_path = public, pg_temp;
alter function public.run_reveal_nudges()     set search_path = public, pg_temp;
alter function public.funnel_metrics(integer) set search_path = public, pg_temp;
alter function public.notify_new_quote_sms()  set search_path = public, pg_temp;
alter function public.match_suppliers_kw(text[], text, text, text, numeric, integer)          set search_path = public, pg_temp;
alter function public.match_suppliers_kw(text[], text, text, text, numeric, integer, boolean) set search_path = public, pg_temp;
