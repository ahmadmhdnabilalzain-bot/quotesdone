-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d9c_a_scenario_built_in_the_order_reality_builds_it.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- OBJECT DROPPED, by name (never `cascade`):
--   public.phase_d_fixture_stage — with phase_d_fixture_stage_pkey (stage_no int),
--   phase_d_fixture_stage_stage_key_key UNIQUE (stage_key), and
--   phase_d_fixture_stage_object_id_fkey -> phase_d_business_object_binding(object_id)
--   ON DELETE RESTRICT
--
-- THIS DOWN IS A PRECONDITION FOR THE d2 DOWN. That RESTRICT is why: while this table exists,
-- `drop table public.phase_d_business_object_binding` fails. Run this file first if the intent is
-- to roll d2 back too.
--
-- ALSO REMOVED AS A SIDE EFFECT, because they are columns / constraints / triggers of the table
-- this file drops:
--   working_state, working_state_evidence, contributes_kind        (added by d20)
--   phase_d_fixture_stage_contributes_kind_check                   (added by d20)
--   trigger a00_phase_d_stage_payment_state                        (added by d20)
--   working_payload, working_payload_evidence                      (added by d23)
--   trigger z00_kernel_truncate_guard                              (added by d24)
--   Running the d20, d23 and d24 downs first is therefore unnecessary, and running them afterwards
--   will fail on a missing table.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_fixture_stage   25 rows — the ordered stages the scenario factory builds in, and
--   after d20/d23 also the working state and working payload each stage contributes. Hand-authored;
--   not re-derivable from anything else on the box.
--
-- NOT TOUCHED: the three CREATE OR REPLACE FUNCTION bodies in d9c, nor
-- fn_phase_d_stage_payment_state_declared() (created by d20). A create-or-replace has no down — see
-- scripts/sql/down/README.md. That trigger function survives with nothing to fire on.
-- =================================================================================================

begin;

drop table if exists public.phase_d_fixture_stage;

do $ctl$
begin
  if to_regclass('public.phase_d_fixture_stage') is not null then
    raise exception 'D9c down did not take: public.phase_d_fixture_stage is still present.';
  end if;

  raise notice 'D9c down: phase_d_fixture_stage is gone, and with it the d20/d23/d24 additions to that table.';
end $ctl$;

commit;
