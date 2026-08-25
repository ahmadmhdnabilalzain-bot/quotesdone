-- Q07 DOWN. REMOVE THE HASH AND THE SEAL FROM founder_command_clarification.
--
-- NO TRANSACTION CONTROL. Six statements.
--
-- APPLYING THIS RETURNS THE TABLE TO WHAT IT WAS ON 24 AUG 2026: zero triggers, no hash on the
-- founder's own words, and nothing stopping an answer, its timestamp or the question that produced
-- it from being edited or deleted afterwards. It exists so Q07 is reversible, not because reverting
-- is advisable.
--
-- The five backfilled hashes go with the column. They were derivations of text that is still there,
-- so nothing is lost that cannot be recomputed — which is exactly why the backfill was legitimate
-- and why removing it is survivable.

DROP TRIGGER IF EXISTS a00_founder_command_clarification_answer_is_sealed
  ON public.founder_command_clarification;
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard
  ON public.founder_command_clarification;
DROP FUNCTION IF EXISTS public.fn_founder_command_clarification_answer_is_sealed();

ALTER TABLE public.founder_command_clarification
  DROP CONSTRAINT IF EXISTS founder_command_clarification_hash_accompanies_answer,
  DROP CONSTRAINT IF EXISTS founder_command_clarification_answer_hash_shape;

ALTER TABLE public.founder_command_clarification
  DROP COLUMN IF EXISTS answer_hash;

DO $ctl$
DECLARE v_trg int; v_col int;
BEGIN
  SELECT count(*) INTO v_trg FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
   WHERE c.relname = 'founder_command_clarification' AND NOT t.tgisinternal;
  SELECT count(*) INTO v_col FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'founder_command_clarification'
     AND column_name = 'answer_hash';
  IF v_trg <> 0 OR v_col <> 0 THEN
    RAISE EXCEPTION 'Q07 down did not take: % trigger(s), % answer_hash column(s) remain', v_trg, v_col
      USING errcode = '23514';
  END IF;
  RAISE NOTICE 'Q07 down: founder_command_clarification is back to 0 triggers and no answer_hash';
END $ctl$;
