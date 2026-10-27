-- THE IDLE CLOSE KEEPS ITS FIXTURE SWITCH AND THE OBJECTION EXCLUSION (customer_support, 27 Oct 2026).
--
-- CAUSE: #1496 (two_more_fenced_seat_duties_keep_their_fixture_switch.sql, MANIFEST line 2070) gave
-- fn_support_case_idle_close the qd.duty_fixtures switch. #1566 (the_support_desk_takes_an_objection_to_an_automated_decision.sql,
-- MANIFEST line 2085) then redefined it from the OLDER body (#1348) to add the objection exclusion, and so put back the
-- unconditional demo exclusion. Production's body (read 27 Oct 2026) is #1566's: with the switch on the duty still skips
-- every ZZ DEMO case, so no rolled-back probe can prove it (two_more_fenced_seat_duties_keep_their_fixture_switch.test.mjs
-- fails: "(b) with the switch on the duty did not close the ZZ DEMO case").
--
-- WHAT THIS DOES: the one body that carries BOTH -- the objection exclusion (legal finding 1, ledger 1152) and the demo
-- predicate equal to the switch (fixture run: ONLY demo cases; every real run and cron: ONLY real ones, so a fixture run
-- can never close a real case). Nothing else changes. CREATE OR REPLACE keeps the ACL (revoked when first created).
-- Prevented by: scripts/checks/two_more_fenced_seat_duties_keep_their_fixture_switch.test.mjs (its static test now reads
-- the CANONICAL body -- the last file that defines the routine -- not only the file that first added the switch).
--   node scripts/apply_sql.mjs scripts/sql/the_idle_close_keeps_its_fixture_switch_and_the_objection_exclusion.sql --apply --ddl --seat customer_support

create or replace function public.fn_support_case_idle_close()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo cases
  v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int); n int;
begin
  update public.support_case
     set state = 'closed', closed_at = now(),
         close_reason = 'resolved — answered, and no reply from the customer in ' || v_days || ' days (closed by customer_support)'
   where state = 'waiting_customer' and last_activity_at < now() - make_interval(days => v_days)
     and category is distinct from 'automated_decision_objection'   -- legal finding 1: closed only by a reply
     and public.fn_party_is_demo(party_kind, party_id) = v_fx;       -- a fixture run can never close a real case
  get diagnostics n = row_count;
  return jsonb_build_object('closed', n);
end $function$;
