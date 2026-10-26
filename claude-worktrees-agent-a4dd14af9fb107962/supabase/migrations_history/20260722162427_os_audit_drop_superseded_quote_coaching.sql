-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722162427   name: os_audit_drop_superseded_quote_coaching
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- fn_quote_coaching: superseded by the richer live fn_quote_coach(uuid); zero callers/refs/schema-deps. PITR-recoverable.
drop function if exists public.fn_quote_coaching(text);
