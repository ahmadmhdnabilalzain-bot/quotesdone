-- THE INTERNET ROLES HOLD NO SEQUENCE AND NO TABLE-MAINTENANCE GRANT (27 Oct 2026; seat: it_engineer; founder ledger 1143,
-- pre-launch security audit: docs/reports/security/prelaunch_audit_27_oct.md, finding M2).
--
-- MEASURED on production, read-only, 27 Oct 2026 (has_sequence_privilege / has_table_privilege, as postgres):
--   * 99 sequences in public grant USAGE, SELECT and UPDATE to anon AND to authenticated (leads_id_seq, notifications_id_seq,
--     gl_journal_id_seq, inbound_messages_id_seq, ...). UPDATE on a sequence is setval(): rewinding leads_id_seq would make
--     every later insert collide with an existing key. Owner postgres, so postgres can revoke them (proved below).
--   * 4 tables grant anon and authenticated more than SELECT: templates, undo_log, legal_documents (TRIGGER) and
--     category_specs (TRIGGER, REFERENCES, MAINTAIN). TRUNCATE is held by neither role on any relation today; it is in the
--     revoke and in the check because TRUNCATE ignores RLS entirely.
--
-- WHY NOTHING NEEDS THEM: neither role holds INSERT, UPDATE or DELETE on any relation in public (asserted in
-- scripts/checks/anon_cannot_execute_security_definer.test.mjs), so neither ever advances a sequence; every client write goes
-- through an edge function holding service_role or a SECURITY DEFINER routine running as postgres. None of these grants is
-- reachable over PostgREST today (sequences and maintenance are not REST verbs), so this is defence in depth: one exposed
-- invoker routine that calls setval() or one GraphQL change would otherwise make them live.
--
-- WHAT IS NOT IN THIS FILE, and why: net.http_post/http_get/http_delete and the net.http_request_queue / net._http_response
-- tables are executable/readable/writable by anon and authenticated (pg_net's default). Those objects belong to
-- supabase_admin; a revoke issued as postgres is a silent no-op (proved 27 Oct in an aborted transaction: every privilege
-- still true afterwards). What keeps them unreachable is that PostgREST exposes only public and graphql_public, and that no
-- client-executable routine calls net.*. Both are now asserted by the same check, and the residual is in the report.
--
-- PROVED 27 Oct 2026 on production in an aborted transaction (DO block ending in raise exception, nothing committed):
--   BEFORE seq_anon=99 seq_auth=99 tbl_extra=8  ->  AFTER seq_anon=0 seq_auth=0 tbl_extra=0,
--   anon/authenticated SELECT on category_specs and anon SELECT on blog_posts unchanged, service_role keeps leads_id_seq.
--   The exact statements of this file plus its verdict query, run the same way, returned verdict=PROBE OK.
--
-- Applied at merge by the release operator only (apply-at-merge-never-before):
--   node scripts/apply_sql.mjs scripts/sql/the_internet_roles_hold_no_sequence_and_no_table_maintenance_grant.sql --apply --ddl
-- (--ddl because the file defines no function; a bare --apply reports "nothing to do".)
-- No BEGIN/COMMIT of its own: apply_sql sends the file as one implicit transaction, and a file that commits itself is
-- committed by any check that replays it inside an aborted transaction (.claude/memory/a-check-that-replays-sql-can-commit-it.md).

revoke all on all sequences in schema public from anon, authenticated;

revoke trigger, references, truncate, maintain
  on public.templates, public.undo_log, public.legal_documents, public.category_specs
  from anon, authenticated;

-- VERDICT (read-only): no sequence and no maintenance privilege left for either internet role, and the two reads the public
-- site and the spec guide depend on are untouched.
select case
  when exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace cross join (values ('anon'), ('authenticated')) r(x)
                where n.nspname = 'public' and c.relkind = 'S'
                  and (has_sequence_privilege(r.x, c.oid, 'USAGE') or has_sequence_privilege(r.x, c.oid, 'UPDATE')
                    or has_sequence_privilege(r.x, c.oid, 'SELECT')))
    then 'PROBE FAILED: a public sequence is still usable by anon or authenticated'
  when exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace cross join (values ('anon'), ('authenticated')) r(x)
                where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm')
                  and (has_table_privilege(r.x, c.oid, 'TRUNCATE') or has_table_privilege(r.x, c.oid, 'TRIGGER')
                    or has_table_privilege(r.x, c.oid, 'REFERENCES') or has_table_privilege(r.x, c.oid, 'MAINTAIN')))
    then 'PROBE FAILED: a relation still grants TRUNCATE/TRIGGER/REFERENCES/MAINTAIN to anon or authenticated'
  when not (has_table_privilege('anon', 'public.blog_posts', 'SELECT') and has_table_privilege('anon', 'public.category_specs', 'SELECT')
            and has_table_privilege('authenticated', 'public.category_specs', 'SELECT'))
    then 'PROBE FAILED: the public-content SELECT grants were lost'
  when not has_sequence_privilege('service_role', 'public.leads_id_seq', 'USAGE')
    then 'PROBE FAILED: service_role lost a sequence it writes through'
  else 'PROBE OK' end as verdict;
