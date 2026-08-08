-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726141141   name: revoke_anon_execute_on_os_secdef_rpcs
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- These OS RPCs are SECURITY DEFINER and were anon-executable via PostgREST, bypassing the
-- os_api admin gate (anon could read suppliers/customers/marketing directly). The os_api edge
-- function invokes them with the service-role key, which is unaffected by these grants.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('fn_agents_board','fn_customers_board','fn_entity_activity',
        'fn_entity_comment_add','fn_marketing_blog_publish','fn_marketing_studio',
        'fn_os_dashboard_viz','fn_rfq_board','fn_suppliers_board')
  loop
    execute format('revoke execute on function %s from anon, authenticated, public', r.sig);
  end loop;
end $$;
