-- =================================================================================================
-- PHASE D DOWN — reverses the two constraint changes in
-- scripts/sql/phase_d_d44_an_endpoint_that_ignores_an_id_has_not_refused.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- WHY THIS FILE IS NOT ONE OF THE TWENTY-THREE. The A/B/neither classification in
-- scripts/sql/down/README.md was taken over the 58 Phase D files tracked at recon. d44 post-dates
-- it. It is here because it carries additive DDL by the same test the twenty-three were found by —
-- a comment-stripped scan of scripts/sql/phase_d_*.sql for CREATE TABLE / ADD COLUMN /
-- ADD CONSTRAINT / DROP CONSTRAINT / CREATE INDEX / CREATE TRIGGER — and because both constraints
-- were read back from pg_constraint on htdblwldjkcgjvmqkbeh under exactly the names used below.
--
-- OBJECTS REVERTED, by name (never `cascade`), in this order:
--   1. constraint public.phase_d_section8_probe_result_verdict_check, from the 4-value definition
--      d44:104-108 back to the 3-value predecessor.
--   2. constraint public.phase_d_injected_defect_status_check, from the 4-value definition
--      d44:110-114 back to the 3-value predecessor.
--
-- BOTH PREDECESSORS ARE IN THE REPO AND ARE QUOTED HERE RATHER THAN RETYPED FROM MEMORY.
--
--   (1) scripts/sql/phase_d_d34_the_seven_probes_that_were_never_run.sql:32, an inline column check
--       inside the CREATE TABLE at :29-36:
--
--           verdict     text not null check (verdict in ('REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN')),
--
--       d34 gives that check no name, so the name below —
--       phase_d_section8_probe_result_verdict_check — is the one Postgres generated and the one
--       d44:105 dropped. It is restored under the same name so a later reader finds one identity,
--       not two.
--
--   (2) scripts/sql/phase_d_d31_seventy_five_injected_defects.sql:39-40, a named table constraint
--       inside the CREATE TABLE at :30-41, quoted verbatim:
--
--           constraint phase_d_injected_defect_status_check
--             check (status in ('REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN'))
--
-- The current definitions on htdblwldjkcgjvmqkbeh, for comparison — both read back with
-- pg_get_constraintdef(oid):
--     CHECK (verdict = ANY (ARRAY['REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN','NOT_DISCRIMINATED']))
--     CHECK (status  = ANY (ARRAY['REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN','NOT_DISCRIMINATED']))
-- NOT_DISCRIMINATED is the one value d44 added to each.
--
-- CHANGE (1) IS BLOCKED BY DATA TODAY, AND THAT IS THE POINT. Measured on htdblwldjkcgjvmqkbeh by
-- `select verdict, count(*) from public.phase_d_section8_probe_result group by 1`:
-- REFUSED_AS_REQUIRED 21 · NOT_DISCRIMINATED 2, over 23 rows. Two rows carry the value the d34
-- predecessor does not allow. Those two are the whole subject of d44: they were published as
-- refusals on an HTTP 200 that could not tell a refusal from an ignored parameter, and d44
-- reclassified them. Narrowing the constraint back without re-running the probes would mean
-- rewriting two measured rows so that a DDL statement succeeds, and putting back the exact claim
-- d44 removed. This file will not do that. It refuses first, names the count, and leaves the
-- operator to re-run scripts/phase_d/run_section8_security_probes.mjs first.
--
-- CHANGE (2) SUCCEEDS TODAY. `select count(*) from public.phase_d_injected_defect_result` returns 0
-- on htdblwldjkcgjvmqkbeh, so no row can violate the 3-value predecessor. The pre-flight block below
-- re-measures both rather than trusting these two paragraphs; the population can change.
--
-- ROW COUNT AT RISK: none deleted. 23 rows in public.phase_d_section8_probe_result and 11 in
-- public.phase_d_section8_defect_map are read, 0 written. This file changes two constraint
-- definitions and no data.
--
-- NOT UNDONE HERE: d44's five `update` statements — two on public.phase_d_section8_probe_result
-- (:127, :141) reclassifying PD-AUTH-002 and PD-PRIV-004, two on
-- public.phase_d_section8_defect_map (:154, :162) correcting their justifications, and the one
-- inside the control block at :267. An update has no down: the prior text is gone, and a down that
-- retyped a plausible replacement would be fabricating the observation it claims to restore. If the
-- constraint really is to be narrowed, the probes have to be re-run — which rewrites those rows
-- from what is observed rather than from what somebody remembers.
-- =================================================================================================


do $pre$
declare v_probe_bad int; v_defect_bad int;
begin
  if to_regclass('public.phase_d_section8_probe_result') is null then
    raise exception 'D44 down: public.phase_d_section8_probe_result does not exist. The d34 down has already run and took this constraint with it; there is nothing here to revert.';
  end if;
  if to_regclass('public.phase_d_injected_defect_result') is null then
    raise exception 'D44 down: public.phase_d_injected_defect_result does not exist. The d31 down has already run and took this constraint with it; there is nothing here to revert.';
  end if;

  select count(*) into v_probe_bad
    from public.phase_d_section8_probe_result
   where verdict = 'NOT_DISCRIMINATED';

  select count(*) into v_defect_bad
    from public.phase_d_injected_defect_result
   where status = 'NOT_DISCRIMINATED';

  if v_probe_bad > 0 or v_defect_bad > 0 then
    raise exception 'D44 down refuses: % rows in public.phase_d_section8_probe_result and % rows in public.phase_d_injected_defect_result carry NOT_DISCRIMINATED, which the d34:32 / d31:39-40 predecessor constraints do not allow. Re-run scripts/phase_d/run_section8_security_probes.mjs first. This file will not rewrite measured rows to make a DDL statement succeed.', v_probe_bad, v_defect_bad;
  end if;
end $pre$;

alter table public.phase_d_section8_probe_result
  drop constraint if exists phase_d_section8_probe_result_verdict_check;
alter table public.phase_d_section8_probe_result
  add  constraint phase_d_section8_probe_result_verdict_check
  check (verdict in ('REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN'));

alter table public.phase_d_injected_defect_result
  drop constraint if exists phase_d_injected_defect_status_check;
alter table public.phase_d_injected_defect_result
  add  constraint phase_d_injected_defect_status_check
  check (status in ('REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN'));

do $ctl$
declare v_probe text; v_defect text;
begin
  select pg_get_constraintdef(oid) into v_probe
    from pg_constraint
   where conname = 'phase_d_section8_probe_result_verdict_check'
     and conrelid = 'public.phase_d_section8_probe_result'::regclass;

  select pg_get_constraintdef(oid) into v_defect
    from pg_constraint
   where conname = 'phase_d_injected_defect_status_check'
     and conrelid = 'public.phase_d_injected_defect_result'::regclass;

  if v_probe is null then
    raise exception 'D44 down did not take: phase_d_section8_probe_result_verdict_check is absent, so the table now has no verdict constraint at all.';
  end if;
  if v_defect is null then
    raise exception 'D44 down did not take: phase_d_injected_defect_status_check is absent, so the table now has no status constraint at all.';
  end if;
  if position('NOT_DISCRIMINATED' in v_probe) > 0 then
    raise exception 'D44 down did not take: the probe constraint still allows NOT_DISCRIMINATED -> %', v_probe;
  end if;
  if position('NOT_DISCRIMINATED' in v_defect) > 0 then
    raise exception 'D44 down did not take: the defect constraint still allows NOT_DISCRIMINATED -> %', v_defect;
  end if;

  raise notice 'D44 down: both verdict domains are back to the three values of d34:32 and d31:39-40. The rows d44 reclassified are NOT restored — re-run the probes.';
end $ctl$;

