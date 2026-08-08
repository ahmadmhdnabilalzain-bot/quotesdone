-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722162458   name: os_audit_drop_dead_kb_search_match_explain
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Both unreferenced across all 185 edge functions + src + pg (bodies/cron/triggers/views/defaults/constraints/policies).
-- fn_kb_search: unused logging wrapper (live path is kb_match/kb_query). fn_match_explain: unused debug variant of live match_suppliers. PITR-recoverable.
drop function if exists public.fn_kb_search(text, text, text, integer);
drop function if exists public.fn_match_explain(vector, integer, text, text, text, numeric);
