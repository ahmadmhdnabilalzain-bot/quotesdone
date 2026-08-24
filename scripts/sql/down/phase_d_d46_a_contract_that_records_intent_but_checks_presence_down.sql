-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d46_a_contract_that_records_intent_but_checks_presence.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- WHY THIS FILE IS NOT ONE OF THE TWENTY-THREE. The A/B/neither classification in
-- scripts/sql/down/README.md was taken over the 58 Phase D files tracked at recon; d46 post-dates
-- it, and that README recorded it as "A by the scan — none yet" precisely because its objects had
-- not been confirmed against the database. They are confirmed now: all six columns were read out of
-- pg_attribute at attnums 10–15 of public.phase_d_handler_schema, and both constraints out of
-- pg_constraint on htdblwldjkcgjvmqkbeh, under exactly the names used below.
--
-- OBJECTS DROPPED, by name, in dependency-safe order (never `cascade`):
--   1. constraint public.phase_d_handler_schema_field_types_ck
--      — CHECK (jsonb_typeof(field_types) = 'object' AND field_types <> '{}'::jsonb)
--   2. constraint public.phase_d_handler_schema_version_ck
--      — CHECK (schema_version >= 1)
--   3. column public.phase_d_handler_schema.schema_version        (attnum 10, int)
--   4. column public.phase_d_handler_schema.field_types           (attnum 11, jsonb)
--   5. column public.phase_d_handler_schema.enum_domains          (attnum 12, jsonb)
--   6. column public.phase_d_handler_schema.optional_keys         (attnum 13, text[])
--   7. column public.phase_d_handler_schema.additional_properties (attnum 14, boolean)
--   8. column public.phase_d_handler_schema.type_source           (attnum 15, text)
--
-- The constraints are on the first two of the six columns, so they go first. The six SET NOT NULL
-- statements at d46:107-113 have no separate down: dropping the columns takes the nullability with
-- them.
--
-- NEITHER CONSTRAINT HAS A PREDECESSOR TO RESTORE. Both were introduced by d46 at :119-124, inside
-- an `if not exists (select 1 from pg_constraint where conname = …)` guard, over columns d46 itself
-- created at :54-59. There is no earlier definition anywhere in the repo; dropping them is the whole
-- revert, and that same guard means a re-apply of d46 after this rollback re-creates them.
--
-- ROW COUNT AT RISK: none deleted. public.phase_d_handler_schema keeps all 514 rows; each loses six
-- columns. The values in them are DERIVED, not typed: d46:73 writes them from what
-- public.fn_phase_c_output_validate actually does, which is why `select type_source, count(*) from
-- public.phase_d_handler_schema group by 1` returns exactly two distinct sentences over 257 output
-- schemas and 257 input schemas rather than a free-text column. They are therefore recoverable by
-- re-running d46, and are not recoverable by retyping.
--
-- WHAT THE ROLLBACK COSTS, STATED PLAINLY. d46 exists because a schema that accepts every payload
-- is not a schema: before it, public.fn_phase_d_schema_validate checked only that the schema exists,
-- the payload is an object, every required key is present, and no required key is empty — so a
-- status of 12345, a status of "purple-elephant", and an invented `__proto__` key were all valid.
-- Dropping these six columns removes the only place a type, a domain, an optionality marker or a
-- schema version is recorded. It does not by itself restore the old validator; see below.
--
-- KNOWN CONSUMERS — both raise on a missing column after this rollback, and both are expected to:
--   public.fn_phase_d_schema_validate(text, jsonb)  — d46:134, reads field_types, enum_domains,
--                                                     optional_keys, additional_properties
--   public.fn_phase_d_contract_state()              — d46:261, the board over the same columns
-- Measured: those two are the only routines on htdblwldjkcgjvmqkbeh whose body names any of the six
-- columns (`select proname from pg_proc … where prosrc like …`, one unrelated hit on
-- fn_enqueue_doc_backups discarded by inspection).
--
-- NOT TOUCHED: the two CREATE OR REPLACE FUNCTION bodies in d46, nor the revoke/grant pair at
-- d46:322-323 on fn_phase_d_contract_state(). A create-or-replace has no down — see
-- scripts/sql/down/README.md. Reverting d46 properly means reverting the validator too, and only
-- the column half is DDL.
-- =================================================================================================


do $pre$
begin
  if to_regclass('public.phase_d_handler_schema') is null then
    raise exception 'D46 down: public.phase_d_handler_schema does not exist. The d1 down has already run and took these columns with it; there is nothing here to revert.';
  end if;
end $pre$;

alter table public.phase_d_handler_schema
  drop constraint if exists phase_d_handler_schema_field_types_ck;

alter table public.phase_d_handler_schema
  drop constraint if exists phase_d_handler_schema_version_ck;

alter table public.phase_d_handler_schema
  drop column if exists schema_version,
  drop column if exists field_types,
  drop column if exists enum_domains,
  drop column if exists optional_keys,
  drop column if exists additional_properties,
  drop column if exists type_source;

do $ctl$
declare v_left text := '';
begin
  select coalesce(string_agg('constraint ' || conname || ' ', ''), '')
    into v_left
    from pg_constraint
   where conrelid = 'public.phase_d_handler_schema'::regclass
     and conname in ('phase_d_handler_schema_field_types_ck','phase_d_handler_schema_version_ck');

  select v_left || coalesce(string_agg('column ' || a.attname || ' ', ''), '')
    into v_left
    from pg_attribute a
   where a.attrelid = 'public.phase_d_handler_schema'::regclass
     and a.attnum > 0 and not a.attisdropped
     and a.attname in ('schema_version','field_types','enum_domains','optional_keys',
                       'additional_properties','type_source');

  if v_left <> '' then
    raise exception 'D46 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D46 down: the two schema checks and the six type/version/optionality columns are gone; all 514 handler schemas survive. fn_phase_d_schema_validate and fn_phase_d_contract_state now raise on a missing column, which is the expected post-rollback state.';
end $ctl$;

