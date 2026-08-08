-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711192125   name: drop_duplicate_index_inquiry_matches
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Remove redundant duplicate unique index on inquiry_matches (hot table, written
-- on every dispatch). Uniqueness remains enforced by the constraint-backed twin
-- inquiry_matches_inquiry_id_supplier_id_key. Clears 1 performance-advisor WARN.
drop index if exists public.uq_inquiry_match;
