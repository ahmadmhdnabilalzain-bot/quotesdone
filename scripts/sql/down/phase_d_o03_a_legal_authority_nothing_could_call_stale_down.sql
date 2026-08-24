-- DOWN for O03. Classification: ADDITIVE_DDL — one table, one predicate, five committed fixture rows.
-- The table is dropped whole, which takes its rows and its self-FK with it. Nothing else read it
-- before O07 wired GATE-027/GATE-028; run O07's down first, or this DROP fails on the dependency.
DROP FUNCTION IF EXISTS public.fn_phase_d_legal_source_current(text, boolean, date);
DROP TABLE IF EXISTS public.phase_d_legal_source;
