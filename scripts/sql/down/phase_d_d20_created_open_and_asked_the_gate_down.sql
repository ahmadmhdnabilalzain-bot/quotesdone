-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of scripts/sql/phase_d_d20_created_open_and_asked_the_gate.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- OBJECTS DROPPED, by name, in dependency-safe order (never `cascade`):
--   1. trigger    a00_phase_d_stage_payment_state on public.phase_d_fixture_stage
--                 (BEFORE INSERT OR UPDATE OF working_state, object_id FOR EACH ROW)
--   2. constraint public.phase_d_fixture_stage_contributes_kind_check
--   3. column     public.phase_d_fixture_stage.contributes_kind        (attnum 10, default
--                 'RESULT_KEY', not null)
--   4. column     public.phase_d_fixture_stage.working_state_evidence  (attnum  9, made not null at
--                 d20:124-126)
--   5. column     public.phase_d_fixture_stage.working_state           (attnum  8, made not null at
--                 d20:124-126)
--
-- The trigger reads working_state and object_id, so it goes first; the constraint is on
-- contributes_kind, so it goes before that column. The two SET NOT NULL statements at d20:124-126
-- have no separate down: dropping the columns takes the nullability with them.
--
-- THE CONSTRAINT HAS NO PREDECESSOR TO RESTORE. phase_d_fixture_stage_contributes_kind_check was
-- introduced by d20 at :128-132 over a column d20 itself created at :86. There is no earlier
-- definition anywhere in the repo; dropping it is the whole revert.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   No rows are deleted. public.phase_d_fixture_stage keeps all 25 rows; each loses three columns.
--   working_state and working_state_evidence are HAND-AUTHORED declarations — the state each object
--   is in when the business is working, plus a PHASE_D_DECLARATION or DERIVED sentence saying where
--   that state came from. They are not re-derivable by measurement; they are recoverable only by
--   re-running d20, which carries the same literals.
--
-- LEFT BEHIND ON PURPOSE: public.fn_phase_d_stage_payment_state_declared(), the trigger function
-- d20 created. A create-or-replace has no down — see scripts/sql/down/README.md — and dropping a
-- function another file may still name is a larger blast radius than leaving an unused one behind.
-- After this rollback it exists with nothing to fire on.
-- =================================================================================================


do $pre$
begin
  if to_regclass('public.phase_d_fixture_stage') is null then
    raise exception 'D20 down: public.phase_d_fixture_stage does not exist. The d9c down has already run; there is nothing here to revert.';
  end if;
end $pre$;

drop trigger if exists a00_phase_d_stage_payment_state on public.phase_d_fixture_stage;

alter table public.phase_d_fixture_stage
  drop constraint if exists phase_d_fixture_stage_contributes_kind_check;

alter table public.phase_d_fixture_stage
  drop column if exists contributes_kind,
  drop column if exists working_state_evidence,
  drop column if exists working_state;

do $ctl$
declare v_left text := '';
begin
  if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
              join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relname = 'phase_d_fixture_stage'
               and t.tgname = 'a00_phase_d_stage_payment_state' and not t.tgisinternal) then
    v_left := v_left || 'trigger a00_phase_d_stage_payment_state ';
  end if;

  if exists (select 1 from pg_constraint
              where conname = 'phase_d_fixture_stage_contributes_kind_check'
                and conrelid = 'public.phase_d_fixture_stage'::regclass) then
    v_left := v_left || 'constraint phase_d_fixture_stage_contributes_kind_check ';
  end if;

  select v_left || coalesce(string_agg('column ' || a.attname || ' ', ''), '')
    into v_left
    from pg_attribute a
   where a.attrelid = 'public.phase_d_fixture_stage'::regclass
     and a.attnum > 0 and not a.attisdropped
     and a.attname in ('working_state','working_state_evidence','contributes_kind');

  if v_left <> '' then
    raise exception 'D20 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D20 down: the payment-state trigger, the contributes_kind check and the three d20 columns are gone; all 25 fixture-stage rows survive.';
end $ctl$;

