-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d23_a_state_can_require_a_companion_column.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- OBJECTS DROPPED, by name (never `cascade`):
--   column public.phase_d_fixture_stage.working_payload           (attnum 11, jsonb not null
--          default '{}'::jsonb, added at d23:36)
--   column public.phase_d_fixture_stage.working_payload_evidence  (attnum 12, text, added at d23:37)
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   No rows are deleted. public.phase_d_fixture_stage keeps all 25 rows; each loses two columns.
--   working_payload is the companion the working_state added by d20 requires — a state that names
--   no payload is a state nothing can be built from — and working_payload_evidence says where each
--   payload came from. Hand-authored, recoverable only by re-running d23.
--
-- NOT TOUCHED: the one CREATE OR REPLACE FUNCTION body in d23. A create-or-replace has no down —
-- see scripts/sql/down/README.md. Any routine that reads working_payload will raise on a missing
-- column after this rollback. Expected.
-- =================================================================================================

begin;

do $pre$
begin
  if to_regclass('public.phase_d_fixture_stage') is null then
    raise exception 'D23 down: public.phase_d_fixture_stage does not exist. The d9c down has already run; there is nothing here to revert.';
  end if;
end $pre$;

alter table public.phase_d_fixture_stage
  drop column if exists working_payload,
  drop column if exists working_payload_evidence;

do $ctl$
declare v_left text := '';
begin
  select coalesce(string_agg(a.attname, ', '), '')
    into v_left
    from pg_attribute a
   where a.attrelid = 'public.phase_d_fixture_stage'::regclass
     and a.attnum > 0 and not a.attisdropped
     and a.attname in ('working_payload','working_payload_evidence');

  if v_left <> '' then
    raise exception 'D23 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D23 down: working_payload and working_payload_evidence are gone; all 25 fixture-stage rows survive.';
end $ctl$;

commit;
