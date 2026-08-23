-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of scripts/sql/phase_d_d1_handler_registry_and_executor.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row counts below, accepts them, and runs it.
--
-- OBJECTS DROPPED, by name, in FK-safe order (never `cascade`):
--   1. public.phase_d_handler_binding  — with phase_d_handler_binding_pkey, _handler_id_key,
--      _step_id_fkey, _input_schema_id_fkey, _output_schema_id_fkey, _phase_d_status_check,
--      _external_effect_policy_check
--   2. public.phase_d_handler_schema   — with phase_d_handler_schema_pkey,
--      _step_id_schema_kind_key, _step_id_fkey, _required_keys_check, _schema_kind_check
--
-- Order is not cosmetic: phase_d_handler_binding.input_schema_id and .output_schema_id are foreign
-- keys onto phase_d_handler_schema.schema_id, so the schema table cannot be dropped first without
-- `cascade`, and `cascade` is exactly what this file exists to avoid.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.3 "Data at risk on a drop" and
-- D.1 item 17):
--   public.phase_d_handler_schema     514 rows  (257 input + 257 output)
--   public.phase_d_handler_binding    257 rows
--   771 rows destroyed. Neither table is reconstructible from anything else on the box: the schemas
--   carry source_text and source_digest captured from the frozen Phase B registry at import time.
--
-- ALSO REMOVED AS A SIDE EFFECT, because they are columns of a table this file drops:
--   phase_d_handler_binding.business_write_wired            (added by d6)
--   phase_d_handler_binding.application_connection          (added by d42)
--   phase_d_handler_binding.application_connection_evidence (added by d42)
--   phase_d_handler_binding.application_connection_measured_at (added by d42)
--   phase_d_handler_binding_app_conn_ck                     (added by d42)
--   phase_d_handler_schema.schema_version, .field_types, .enum_domains, .optional_keys,
--     .additional_properties, .type_source                  (six columns added by d46:54-59)
--   phase_d_handler_schema_field_types_ck, phase_d_handler_schema_version_ck (added by d46:119-124)
--   Running the d6, d42 and d46 downs first is therefore unnecessary, and running them afterwards
--   will fail on a missing table.
--
-- NOT TOUCHED: the four CREATE OR REPLACE FUNCTION bodies in d1 (fn_phase_d_schema_validate and
-- the executor family). A create-or-replace has no down — see scripts/sql/down/README.md.
-- =================================================================================================

begin;

drop table if exists public.phase_d_handler_binding;
drop table if exists public.phase_d_handler_schema;

do $ctl$
declare v_left text := '';
begin
  if to_regclass('public.phase_d_handler_binding') is not null then
    v_left := v_left || 'public.phase_d_handler_binding ';
  end if;
  if to_regclass('public.phase_d_handler_schema') is not null then
    v_left := v_left || 'public.phase_d_handler_schema ';
  end if;

  if v_left <> '' then
    raise exception 'D1 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D1 down: phase_d_handler_binding and phase_d_handler_schema are gone.';
end $ctl$;


-- ---- ROUTINES THIS FILE INTRODUCED ------------------------------------------------------
-- Added 23 Aug 2026. Every routine below is defined by no other file under scripts/sql/, so
-- re-applying a predecessor cannot restore it and dropping it is the whole of its reversal.
-- Anything still calling one of them will raise on a missing function after this rollback.
drop function if exists public.fn_phase_d_slug(p_text text);
commit;
