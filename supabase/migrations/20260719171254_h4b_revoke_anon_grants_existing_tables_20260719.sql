-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719171254   name: h4b_revoke_anon_grants_existing_tables_20260719
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- H4b: revoke the blanket anon/authenticated grants on existing public tables, so RLS is the
-- SECOND barrier rather than the ONLY one. Inert today (deny-all RLS), service_role retained.
-- Keep category_specs (its anon SELECT policy is the one legitimate public-read path).
do $$
declare r record; n int := 0;
begin
  for r in
    select c.relname
    from pg_class c join pg_namespace nsp on nsp.oid = c.relnamespace
    where nsp.nspname = 'public' and c.relkind = 'r'
      and c.relname <> 'category_specs'
      and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('authenticated', c.oid, 'SELECT'))
  loop
    begin
      execute format('revoke all on table public.%I from anon, authenticated', r.relname);
      n := n + 1;
    exception when others then
      raise notice 'skipped %: %', r.relname, sqlerrm;
    end;
  end loop;
  raise notice 'H4b revoked anon/authenticated on % tables', n;
end $$;
