-- =================================================================================================
-- Phase D — D24. A table became an enforcing table and nobody gave it the estate's truncate guard.
--
-- Caught by the end-of-session sweep, not by anything in D20:
--
--     fn_kernel_truncate_protection_state
--       enforcing_tables_without_a_truncate_guard   expected 0, got 1 of 79
--       enforcing_tables_still_granting_truncate    expected 0, got 1 of 79
--
-- The table is public.phase_d_fixture_stage. D20 put a BEFORE INSERT OR UPDATE trigger on it —
-- a00_phase_d_stage_payment_state, which refuses a payment working_state that is not a rung of
-- phase_d_payment_state — and that is what makes a table "enforcing" in this estate: the board
-- derives the population from pg_trigger by looking for a row-level trigger whose function raises,
-- rather than from a typed list. So the table joined a population of 79 the moment the trigger
-- landed, and arrived there without the two things every other member has.
--
-- WHY IT MATTERS, and it is recorded in this repository's own memory: a ROW TRIGGER CANNOT SEE
-- TRUNCATE. Every row-level guard in the estate — a00_ prefixes, CHECK constraints, the payment
-- ladder trigger added in D20 — is silently bypassed by a single TRUNCATE, and phase_d_fixture_stage
-- is now the registry the driver reads working_state, working_payload and contributes_kind from.
-- Truncating it would not raise; it would just make every driven object open again, with no state,
-- and the next drive would report gate refusals that look like business defects.
--
-- The board is derived, so it found this on its own. That is the argument for a population read
-- from pg_trigger instead of a list somebody remembers to update: D20 could not have known it was
-- joining a guarded population, and the check knew.
--
-- Two things, exactly as the other 78 have them:
--   * a STATEMENT-level BEFORE TRUNCATE trigger, using the kernel's own guard function
--   * TRUNCATE revoked from the client roles
--
-- Nothing else about the table changes, and no row is touched.
-- =================================================================================================

begin;

drop trigger if exists z00_kernel_truncate_guard on public.phase_d_fixture_stage;
create trigger z00_kernel_truncate_guard
  before truncate on public.phase_d_fixture_stage
  for each statement execute function public.fn_kernel_truncate_guard();

revoke truncate on public.phase_d_fixture_stage from service_role, authenticated, anon;

-- The other tables this session created carry no raising row trigger, so they are not in the
-- enforcing population. They are revoked anyway rather than left to become a finding later.
revoke truncate on public.phase_d_outbound_door from service_role, authenticated, anon;

do $ctl$
declare v_bad int; v_detail text;
begin
  select count(*) into v_bad
    from public.fn_kernel_truncate_protection_state() where not ok;
  if v_bad > 0 then
    select string_agg(check_name || ' = ' || actual, '; ') into v_detail
      from public.fn_kernel_truncate_protection_state() where not ok;
    raise exception 'D24 control: the truncate board is still red: %', v_detail;
  end if;

  -- THE GUARD MUST FIRE. A statement trigger that has never refused anything is indistinguishable
  -- from an absent one, and this whole file exists because an absent one looked fine.
  begin
    truncate table public.phase_d_fixture_stage;
    raise exception 'D24 control: TRUNCATE on phase_d_fixture_stage succeeded. The guard is not firing, and the registry the driver reads its states from can be emptied without a word.';
  exception
    when others then
      if SQLERRM like 'D24 control:%' then raise; end if;
      -- refused, which is the point
  end;

  if (select count(*) from public.phase_d_fixture_stage) <> 25 then
    raise exception 'D24 control: the positive control did not roll back; phase_d_fixture_stage holds % rows and 25 are expected.',
      (select count(*) from public.phase_d_fixture_stage);
  end if;
end $ctl$;

commit;
