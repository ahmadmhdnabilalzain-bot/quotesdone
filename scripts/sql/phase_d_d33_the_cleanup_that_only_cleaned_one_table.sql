-- =================================================================================================
-- Phase D — D33. The cleanup that only cleaned one table.
--
-- D32 found that D31's control had committed its probe rows and cleaned 14 of them out of
-- public.phase_d_external_attempt. It cleaned that table and stopped there.
--
-- The kernel board caught the rest:
--
--     fn_phase_d_fixture_state.fixture_rows_surviving_in_business_tables — expected 0, got 1
--
-- One row in public.customers: full_name 'ZZ DEMO — idem001', email null, created 10:01:42 — the
-- same second as the D31 deploy. The PD-IDEM-001 probe writes a customer_account through the
-- canonical service to prove that two writes of one identity resolve to one row, and that write
-- committed with everything else in that file.
--
-- THE LESSON, WHICH IS THE SAME ONE TWICE: a cleanup scoped to the table you happened to look at is
-- not a cleanup. D32 measured the leak in one relation and inferred the rest was clean, which is the
-- narrow-check-broad-claim shape this estate has a standing rule against. The right question was
-- never "is the attempt ledger empty" but "does fn_phase_d_fixture_residue() report zero", which is
-- the check that already existed and was not consulted.
--
-- It was found by a BOARD rather than by the file that caused it, which is the argument for the
-- board being derived and run every session.
-- =================================================================================================

begin;

-- Scoped to the fixture convention AND to rows the residue function itself counts. Nothing else in
-- public.customers is touched; the table held 0 rows before this session and holds 1 now.
delete from public.customers
 where full_name like 'ZZ DEMO — %'
   and email is null;

do $ctl$
declare v_left int; v_red int; v_detail text;
begin
  select coalesce(sum(surviving_rows),0) into v_left from public.fn_phase_d_fixture_residue();
  if v_left <> 0 then
    select string_agg(relation || '=' || surviving_rows, ', ') into v_detail
      from public.fn_phase_d_fixture_residue() where surviving_rows > 0;
    raise exception 'D33 control: fixture rows still survive: %', v_detail;
  end if;

  select count(*) into v_red from public.fn_phase_d_fixture_state() where not ok;
  if v_red > 0 then
    select string_agg(check_name || ' = ' || actual, '; ') into v_detail
      from public.fn_phase_d_fixture_state() where not ok;
    raise exception 'D33 control: fn_phase_d_fixture_state() is not green: %', v_detail;
  end if;

  if (select count(*) from public.phase_d_external_attempt) <> 0 then
    raise exception 'D33 control: the attempt ledger is not empty.';
  end if;

  raise notice 'D33: fixture residue 0 across every business relation the residue function watches.';
end $ctl$;

commit;
