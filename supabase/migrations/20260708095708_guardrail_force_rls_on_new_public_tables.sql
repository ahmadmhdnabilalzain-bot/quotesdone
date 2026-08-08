-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708095708   name: guardrail_force_rls_on_new_public_tables
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Guardrail: auto-enable Row-Level Security on any newly created public table.
-- With RLS on and no policy, the table is deny-all to anon/authenticated (the service-role
-- gateway still works). Prevents the rls_disabled_in_public advisor from ever firing again.
create or replace function public.fn_enforce_rls_on_new_tables()
returns event_trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare r record;
begin
  for r in
    select object_identity, schema_name, object_type
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO')
      and object_type = 'table'
      and schema_name = 'public'
  loop
    execute format('alter table %s enable row level security', r.object_identity);
  end loop;
end
$fn$;

drop event trigger if exists trg_enforce_rls_new_tables;
create event trigger trg_enforce_rls_new_tables
  on ddl_command_end
  when tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO')
  execute function public.fn_enforce_rls_on_new_tables();
