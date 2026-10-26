-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260615220924   name: prelaunch_security_hardening
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- 1) Lock down doc_reviews (service-role edge functions still work; anon/authenticated get nothing)
alter table public.doc_reviews enable row level security;

-- 2) Remove public/anon/authenticated execute on the invite enqueue RPC (cron uses postgres/service role)
revoke execute on function public.enqueue_supplier_invites(int) from anon, authenticated, public;

-- 3) Pin search_path on our security-definer / helper functions (clears the mutable-search_path warnings)
alter function public.reveal_fee(numeric, timestamptz) set search_path = public;
alter function public.add_working_days(timestamptz, integer) set search_path = public;
alter function public.registered_supplier_count() set search_path = public;
alter function public.recompute_supplier_rating(bigint) set search_path = public;
alter function public.enqueue_supplier_invites(int) set search_path = public;

-- confirm auto-approve toggle state (testing flag that should be OFF for public launch)
select auto_approve_suppliers from pricing_config where id=1;
