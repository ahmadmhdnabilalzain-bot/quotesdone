-- DOWN. REMOVE THE con.conname TIEBREAKER FROM fn_schema_export'S CONSTRAINTS SECTION.
--
-- NO TRANSACTION CONTROL. Restores the ORDER BY as it stood, by re-applying the definition without
-- the tiebreaker. Nothing else in the routine differs.
--
-- APPLYING THIS returns the CONSTRAINTS section to `order by contype-rank, c.relname` with no third
-- key, so two CHECK constraints on one table are tied again and come out in heap-scan order. The
-- export stays deterministic for a given catalogue and starts moving 76 lines the next time a
-- migration drops and recreates a constraint -- which is the state that reddened CI on PR #471 with
-- a diff whose line count and character count were both unchanged.
--
-- The mirror must be regenerated after applying this, or the next run of
-- scripts/checks/export_from_either_source_is_identical.mjs reports NO for the same reason:
--
--   node scripts/checks/export_from_either_source_is_identical.mjs --write

-- Re-apply the pre-tiebreaker definition by taking the current one and removing the third ORDER BY
-- key. Done as a statement rather than a pasted body so this file cannot drift from the routine it
-- reverses: a hand-copied 5KB body would be a second source of truth for one object.
DO $down$
DECLARE v_src text; v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_src FROM pg_proc
   WHERE proname = 'fn_schema_export' AND pronamespace = 'public'::regnamespace;
  v_new := replace(v_src,
    'end, c.relname, con.conname) from pg_constraint con',
    'end, c.relname) from pg_constraint con');
  IF v_new = v_src THEN
    RAISE NOTICE 'fn_schema_export already has no tiebreaker; nothing to revert';
    RETURN;
  END IF;
  EXECUTE v_new;
  RAISE NOTICE 'fn_schema_export: tiebreaker removed';
END $down$;
