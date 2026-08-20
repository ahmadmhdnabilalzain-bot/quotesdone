-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d17_the_fixture_had_a_second_door_and_it_was_http.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- OBJECT DROPPED, by name (never `cascade`):
--   public.phase_d_outbound_door — 11 columns, primary key (relation, trigger_name), with
--   phase_d_outbound_door_disposition_check (2 values) and phase_d_outbound_door_evidence_check
--   (two-branch)
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_outbound_door   4 rows — the register of the doors out of the estate. Four rows,
--   but they are the reason a fixture run cannot email a real supplier: each names a relation, the
--   trigger on it that can send, and the disposition that trigger is held at. Losing the register
--   does not re-open the doors; it removes the record of which doors exist.
--
-- ALSO IN d17 AND NOT UNDONE HERE: nine `delete from` statements across the Phase D corpus are
-- recorded in scripts/sql/down/README.md as non-additive changes with no down; two of them are in
-- this file. A delete has no down — the rows are gone and this file will not invent replacements.
--
-- NOT TOUCHED: the three CREATE OR REPLACE FUNCTION bodies in d17. A create-or-replace has no down
-- — see scripts/sql/down/README.md.
-- =================================================================================================

begin;

drop table if exists public.phase_d_outbound_door;

do $ctl$
begin
  if to_regclass('public.phase_d_outbound_door') is not null then
    raise exception 'D17 down did not take: public.phase_d_outbound_door is still present.';
  end if;

  raise notice 'D17 down: phase_d_outbound_door is gone. The two deletes in d17 have no down.';
end $ctl$;

commit;
