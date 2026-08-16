-- K1 — THE FROZEN BASELINE RECORDS BECOME APPEND-ONLY.
--
-- public.org_phase_baseline holds exactly two rows, 'A' and 'B' (primary key: phase). They are the
-- founder-approved record of what each phase WAS at the moment it was approved: the final commit,
-- the counts, the organisation fingerprint, the registry digests, the migrations and rollbacks. Four
-- routines read them — fn_phase_a_baseline_drift, fn_phase_a_freeze_guard, fn_phase_b_baseline_drift,
-- fn_phase_b_freeze_guard — and NONE of them writes. Nothing in the database is supposed to.
--
-- WHY THIS IS NEEDED, from the rows themselves. The phase 'A' note currently carries the PACR-001
-- paragraph FOUR TIMES, word for word. scripts/sql/pacr_001_the_baseline_records_the_approved_graph.sql
-- appends that paragraph with `note = b.note || ...` and was applied four times; nothing objected,
-- nothing recorded that it had happened before, and the only surviving evidence that the frozen
-- record was rewritten at all is the duplication in its own prose. An UPDATE that silently repeats
-- is the mildest version of this. The dangerous version is an UPDATE that lands once, changes a
-- digest, and leaves the baseline agreeing with a database it no longer describes — at which point
-- every drift check built on it reports green about the wrong subject.
--
-- WHAT THIS DOES: a BEFORE UPDATE OR DELETE trigger that refuses, always, with errcode 23514. There
-- is no reason-string escape hatch and no role exemption. A frozen record with a bypass is a record
-- whose bypass gets used at 2am.
--
-- HOW A LEGITIMATE CHANGE IS MADE — the change-request path, which the error message names:
--   1. Write scripts/sql/pacr_NNN_<what_changed_and_why>.sql, the way PACR-001 was written: it must
--      state the founder approval, and it must RECOMPUTE every digest in place rather than transcribe
--      one from a script's output.
--   2. That file drops trigger a00_org_phase_baseline_append_only, makes the change, and recreates
--      the trigger, all inside one transaction. The drop stays in the file, in the repository, as the
--      permanent record that the freeze was opened, by whom, and for what.
--   3. Append the file to scripts/sql/MANIFEST.txt. scripts/checks/canonical_routines.test.mjs fails
--      on a file that is not in the manifest, so step 3 is not optional.
-- The trigger does not need to know about any of that. It only needs to make step 2 impossible to
-- skip by accident, and impossible to do without leaving the record.
--
-- NOTHING IN PHASE A OR PHASE B IS MODIFIED. No baseline row is read, written, or re-recorded here;
-- this file adds one guard function and one trigger and touches nothing else.
--
-- Rollback: scripts/sql/rollback/kernel_k1_baseline_append_only.rollback.sql
-- Rehearsal: scripts/sql/kernel_k1_baseline_append_only.REHEARSAL.md

create or replace function public.fn_org_phase_baseline_append_only()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  raise exception
    'org_phase_baseline is append-only: % on the frozen phase % baseline is refused',
    tg_op, coalesce(old.phase, '?')
    using errcode = '23514',
          hint = 'These rows are the founder-approved record of what a phase WAS when it was '
              || 'approved, and four drift checks read them as the fixed point they measure '
              || 'against. To change one, raise a Phase change request: write '
              || 'scripts/sql/pacr_NNN_<what_and_why>.sql which drops trigger '
              || 'a00_org_phase_baseline_append_only, makes the change with every digest '
              || 'RECOMPUTED in place, recreates the trigger in the same transaction, and is '
              || 'appended to scripts/sql/MANIFEST.txt. The dropped trigger in that file is the '
              || 'record that the freeze was deliberately opened.';
end $$;

-- A trigger function is invoked by the trigger machinery and not through EXECUTE, so this REVOKE is
-- not what stops anyone calling it — but it is SECURITY DEFINER, and a SECURITY DEFINER function
-- left executable by anon in this project has been a real finding before. Every new one gets the
-- same two lines, without arguing about whether this particular body could do harm.
revoke all on function public.fn_org_phase_baseline_append_only() from public;
grant execute on function public.fn_org_phase_baseline_append_only() to service_role;

drop trigger if exists a00_org_phase_baseline_append_only on public.org_phase_baseline;
create trigger a00_org_phase_baseline_append_only
  before update or delete on public.org_phase_baseline
  for each row execute function public.fn_org_phase_baseline_append_only();
