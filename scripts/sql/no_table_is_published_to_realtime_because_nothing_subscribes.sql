-- NO TABLE IS PUBLISHED TO REALTIME, BECAUSE NOTHING SUBSCRIBES (it_engineer, 17 Nov 2026).
--
-- Security audit of 17 Nov 2026 (docs/reports/2026-11-17-security-audit.md, finding 3). twin_realtime.sql (Aug 2026)
-- put 13 tables in the supabase_realtime publication for the July OS console's live twin, each behind one
-- os_owner_admin_read policy keyed on fn_role_of(jwt e-mail). That policy does not ask for an aal2 session. Nothing
-- leaks today, because neither anon nor authenticated holds SELECT on any of the 13 (SELECT, 17 Nov), and Realtime
-- delivers only what the role can SELECT. But one future grant would stream customer, supplier and money rows to any
-- one-factor session on an admin address, past the 10 Nov two-step door.
--
-- CHOSEN BY EVIDENCE: drop the tables from the publication, rather than add aal2 to the 13 policies.
--   * READ, 17 Nov: no `.channel(`, `postgres_changes`, `.subscribe(` or realtime client anywhere in src/,
--     supabase/functions, public/ or the live scripts (only scripts/archive and retired checks mention them). The
--     console that subscribed was removed with the OS (9 Sep 2026); admin screens read through the
--     _shared/admin_session.ts doors, which require aal2.
--   * SELECT, 17 Nov: pg_replication_slots is empty, so Realtime holds no slot and streams no table change today.
-- With no subscriber, the publication membership is surface with no use; removing it closes the stream whatever a
-- policy or a grant says later.
--
-- WHAT THIS DOES NOT CHANGE: the 13 os_owner_admin_read policies stay. With no client grant they admit nobody, and
-- dropping them would leave 13 tables with RLS on and no policy (apply-discipline 3, and 13 new advisor lints).
-- supabase_realtime itself stays (owner postgres; Supabase manages it), and supabase_realtime_messages_publication is
-- not touched.
--
-- ROLLBACK: alter publication supabase_realtime add table public.ai_cost_log, public.customers, ... (the 13 below);
-- the publication half of scripts/sql/twin_realtime.sql does exactly that.
--
-- No routine, no table, no grant. ALTER PUBLICATION ... DROP TABLE takes SHARE UPDATE EXCLUSIVE on each table, which
-- does not stop reads or writes.
--   node scripts/apply_sql.mjs scripts/sql/no_table_is_published_to_realtime_because_nothing_subscribes.sql --apply --ddl

do $$
declare t text;
  twin text[] := array['ai_cost_log','customers','edge_health_probe','expenses','gl_journal','inquiries','kb_chunks',
                       'leads','org_agents','risk_register','transactions','vision_horizon','workflow'];
begin
  foreach t in array twin loop
    if exists (select 1 from pg_publication_tables
                where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime drop table public.%I', t);
    end if;
  end loop;
end $$;

-- verdict row
select case
  when not exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    then 'PROBE FAILED: the supabase_realtime publication is gone'
  when exists (select 1 from pg_publication_tables
                where pubname = 'supabase_realtime' and schemaname = 'public'
                  and tablename in ('ai_cost_log','customers','edge_health_probe','expenses','gl_journal','inquiries',
                                    'kb_chunks','leads','org_agents','risk_register','transactions','vision_horizon','workflow'))
    then 'PROBE FAILED: a sensitive table is still published to Realtime'
  when exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'public'
                  and c.relname in ('ai_cost_log','customers','edge_health_probe','expenses','gl_journal','inquiries',
                                    'kb_chunks','leads','org_agents','risk_register','transactions','vision_horizon','workflow')
                  and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('authenticated', c.oid, 'SELECT')))
    then 'PROBE FAILED: a client role can SELECT one of the 13 tables'
  else 'PROBE OK' end as verdict;
