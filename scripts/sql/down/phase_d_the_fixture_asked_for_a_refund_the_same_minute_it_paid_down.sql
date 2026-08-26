-- ROLLBACK for scripts/sql/phase_d_the_fixture_asked_for_a_refund_the_same_minute_it_paid.sql
--
-- NO TRANSACTION CONTROL. One UPDATE and an assertion; rehearsable.
--
-- THE ROUTINE IS NOT RESTORED HERE. fn_phase_d_fixture_scenario comes back by re-applying the file
-- it was forked from, which is still in the tree:
--   node scripts/apply_sql.mjs \
--     scripts/sql/phase_d_o13_a_package_identified_two_ways_and_a_comparison_nobody_published.sql \
--     --apply --ddl
--
-- THIS FILE REMOVES THE ONE MAPPED COLUMN. public.phase_d_object_write_map for payment_transaction
-- stops carrying revealed_at, so the fixture's reveal time is dropped again and public.transactions
-- takes its default of now(). trg_reveal_window then stamps refund_deadline three working days out,
-- and stage 230 refund_dispute_case is refused with refund_window_not_yet_open -- one fewer fixture
-- stage, and PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv stops reproducing on
-- fixture_stages_created. That is the state this rollback returns to, said plainly.

update public.phase_d_object_write_map
   set column_map = column_map - 'revealed_at'
 where object_id = 'payment_transaction';

DO $assert$
DECLARE v_map jsonb;
BEGIN
  SELECT column_map INTO v_map FROM public.phase_d_object_write_map
   WHERE object_id = 'payment_transaction';
  IF v_map IS NULL OR (v_map ? 'revealed_at') THEN
    RAISE EXCEPTION 'the payment_transaction write map still carries revealed_at' USING errcode = '23514';
  END IF;
  RAISE NOTICE 'payment_transaction write map restored to % key(s)',
    (SELECT count(*) FROM jsonb_object_keys(v_map));
END $assert$;
