-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d42_route_state_was_my_own_placeholder.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- WHY THIS FILE IS NOT ONE OF THE TWENTY-ONE. The WORKLIST's A/B/neither classification was taken
-- over the 58 Phase D files tracked at recon. d42 post-dates it. It is here because it carries
-- additive DDL by the same test the other twenty-one were found by — a comment-stripped scan of
-- scripts/sql/phase_d_*.sql for CREATE TABLE / ADD COLUMN / ADD CONSTRAINT / CREATE INDEX /
-- CREATE TRIGGER — and because its four objects were confirmed present on htdblwldjkcgjvmqkbeh by
-- reading pg_attribute and pg_constraint, not by reading the file.
--
-- OBJECTS DROPPED, by name, in dependency-safe order (never `cascade`):
--   1. constraint public.phase_d_handler_binding_app_conn_ck — check (application_connection is
--      null or application_connection in ('KERNEL_INTERNAL_ONLY','API_CONNECTED',
--      'FRONTEND_CONNECTED','AUTONOMOUS_SOURCE_CONNECTED_HELD','FULL_APPLICATION_PATH_CONNECTED'))
--   2. column public.phase_d_handler_binding.application_connection
--   3. column public.phase_d_handler_binding.application_connection_evidence
--   4. column public.phase_d_handler_binding.application_connection_measured_at
--
-- The constraint is on the first of the three columns, so it goes first. It has no predecessor to
-- restore: d42 added it at :328-331 over a column d42 itself created at :321. Dropping it is the
-- whole revert. d42 guards the ADD with `if not exists (select 1 from pg_constraint where conname =
-- …)`, so a re-apply after this rollback re-creates it.
--
-- ROW COUNT AT RISK: none deleted. public.phase_d_handler_binding keeps all 257 rows; each loses
-- three columns. application_connection is a MEASURED value, not a declaration — d42 writes it only
-- from fn_phase_d_application_connection_measure(), from what phase_c_source_cutover and
-- founder_command_workflow_link actually hold — so it is re-derivable by re-running that routine
-- after re-applying d42, and is not recoverable by retyping.
--
-- NOT UNDONE HERE: d42's first and third changes. (1) It removes the route_state placeholder from
-- D37's resolver and (3) it adds actual_caller — both are CREATE OR REPLACE FUNCTION bodies, and a
-- create-or-replace has no down (see scripts/sql/down/README.md). Running this file reverts the
-- connection column only; the resolver keeps d42's behaviour.
-- =================================================================================================

begin;

do $pre$
begin
  if to_regclass('public.phase_d_handler_binding') is null then
    raise exception 'D42 down: public.phase_d_handler_binding does not exist. The d1 down has already run and took these columns with it; there is nothing here to revert.';
  end if;
end $pre$;

alter table public.phase_d_handler_binding
  drop constraint if exists phase_d_handler_binding_app_conn_ck;

alter table public.phase_d_handler_binding
  drop column if exists application_connection,
  drop column if exists application_connection_evidence,
  drop column if exists application_connection_measured_at;

do $ctl$
declare v_left text := '';
begin
  if exists (select 1 from pg_constraint
              where conname = 'phase_d_handler_binding_app_conn_ck'
                and conrelid = 'public.phase_d_handler_binding'::regclass) then
    v_left := v_left || 'constraint phase_d_handler_binding_app_conn_ck ';
  end if;

  select v_left || coalesce(string_agg('column ' || a.attname || ' ', ''), '')
    into v_left
    from pg_attribute a
   where a.attrelid = 'public.phase_d_handler_binding'::regclass
     and a.attnum > 0 and not a.attisdropped
     and a.attname like 'application\_connection%';

  if v_left <> '' then
    raise exception 'D42 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D42 down: the app_conn check and the three application_connection columns are gone; all 257 handler bindings survive.';
end $ctl$;

commit;
