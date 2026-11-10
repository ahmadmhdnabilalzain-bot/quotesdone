-- A SIGNED-IN SUPPLIER IS FOUND BY INDEX, NOT BY READING EVERY LEAD.
-- Seat: it_engineer. 10 Nov 2026 (founder ledger 1605, the reliability checklist audit:
-- docs/reports/2026-11-10-reliability-checklist-audit.md, item "database indexing").
--
-- ══ MEASURED, 10 Nov 2026 ~17:30Z, htdblwldjkcgjvmqkbeh, read-only ═══════════════════════════════
-- pg_stat_statements (window since its reset of 2 Nov 07:12Z): the PostgREST statement
--   SELECT leads.id FROM leads WHERE leads.claimed_by ilike $1 LIMIT $2 OFFSET $3
--   8,038 calls, 9.9 ms mean, 79 s in total. Its callers are .ilike('claimed_by', <address>) in
--   send_outbox/index.ts:182 (the Reply-To of every automatic answer to a non-supplier address),
--   resilience_ping/ticks/it_engineer/integrations.ts:107, email_triage/account_facts.ts:112 and
--   site_assistant/index.ts:137.
-- EXPLAIN (ANALYZE, BUFFERS) of that statement for an address nobody holds:
--   Seq Scan on leads, Rows Removed by Filter: 20300, shared hit=1977, Execution Time: 9.737 ms.
-- The existing indexes cannot serve it: idx_leads_claimedby is btree on lower(claimed_by) and
--   leads_claimed_by_idx is btree on claimed_by, and a btree answers neither ILIKE nor lower() unless the
--   query says lower(), which a PostgREST filter cannot. 3 of 20,300 leads have claimed_by set.
-- pg_stat_user_tables for leads: 122,481 sequential scans reading 2,453,331,338 rows in all; this
--   statement is one named, fixable part of that, not all of it (most come from inside routines, which
--   pg_stat_statements.track = top does not attribute).
--
-- ══ CHANGE ═══════════════════════════════════════════════════════════════════════════════════════
-- One trigram GIN index on claimed_by, partial on claimed_by IS NOT NULL. pg_trgm 1.6 is installed in
-- schema public. A trigram index answers ILIKE with no wildcard (the callers escape % and _), and the
-- planner proves claimed_by IS NOT NULL from the strict ILIKE clause, so the partial index applies. It
-- holds 3 entries today: it costs nothing to keep and its write cost is paid only when a lead is claimed.
-- The probe (..._probe.sql) proves, in the same rolled-back transaction, that the planner now chooses it.
--
-- ══ NOT CHANGED ══════════════════════════════════════════════════════════════════════════════════
-- The callers (no code changes; their filter stays exactly what it was). login_otp's
-- .ilike('phone', '%' + last9) (a leading wildcard; leads_phone_tail9_idx exists for the same need, and
-- the sign-in path is rare). The unused leads indexes found in the same pass (leads_place_id_key,
-- leads_has_email_idx, the two hnsw embedding indexes: 0 scans) are reported in the audit, not dropped.
-- fn_sales_engineer_email_check_batch (424 ms every 5 minutes, a 20,003-row anti-join that finds
-- nothing due) is a routine rewrite, reported in the audit, not an index.
--
-- CREATE INDEX (not CONCURRENTLY, so the applier may wrap it in a transaction) takes a SHARE lock on
-- leads for the build: 20,300 rows, 3 indexed, well under a second. lock_timeout makes a busy moment
-- fail cleanly and be retried rather than queue writers behind it.
set lock_timeout = '5s';

create index if not exists leads_claimed_by_trgm_idx
  on public.leads using gin (claimed_by public.gin_trgm_ops)
  where claimed_by is not null;

comment on index public.leads_claimed_by_trgm_idx is
  'ILIKE lookups by the signed-in address (send_outbox, site_assistant, email_triage, resilience_ping). '
  'Was a 20,300-row seq scan, 9.9 ms x 8,038 calls (10 Nov 2026). scripts/sql/a_signed_in_supplier_is_found_by_index_not_by_reading_every_lead.sql';

-- VERDICT
select case when to_regclass('public.leads_claimed_by_trgm_idx') is not null
  then 'PROBE OK' else 'PROBE FAILED: leads_claimed_by_trgm_idx is missing' end as verdict;
