-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260626204054   name: harden_rls_and_search_path
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #1: close the RLS hole on the 4 exposed tables (service role bypasses RLS; nothing legit uses anon here)
alter table public.templates        enable row level security;
alter table public.legal_documents  enable row level security;
alter table public.undo_log         enable row level security;
alter table public.agent_action_log enable row level security;

revoke select, insert, update, delete, truncate, references
  on public.templates, public.legal_documents, public.undo_log, public.agent_action_log
  from anon, authenticated;

-- #3: pin search_path on every SECURITY DEFINER function that lacks it
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef and p.proconfig is null
  loop
    execute format('alter function %s set search_path = public, pg_temp', r.sig);
  end loop;
end $$;
