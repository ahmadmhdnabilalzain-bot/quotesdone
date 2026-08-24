-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d49_a_freeze_with_no_way_to_record_an_amendment.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- WHY THIS FILE IS NOT ONE OF THE TWENTY-THREE. The A/B/neither classification in
-- scripts/sql/down/README.md was taken over the 58 Phase D files tracked at recon. d49 post-dates
-- it. It is here because it carries additive DDL by the same test the twenty-three were found by,
-- and because every object named below was read out of pg_class, pg_constraint and pg_attribute on
-- htdblwldjkcgjvmqkbeh under exactly that name — not read out of the file.
--
-- THE TABLE IS NAMED phase_c_*, AND IT IS STILL d49's TO DROP. scripts/sql/down/README.md carries
-- the opposite rule for public.phase_d_preflight_requirement: a Phase C file created it, so no
-- Phase D down may drop it. This is the mirror case and it resolves the other way — the name says
-- Phase C because the subject is the Phase C freeze, but the CREATE TABLE is at
-- scripts/sql/phase_d_d49_a_freeze_with_no_way_to_record_an_amendment.sql:47-60 and nowhere else.
-- The test is which file creates the object, never which phase the name mentions.
--
-- OBJECT DROPPED, by name (never `cascade`):
--   table public.phase_c_freeze_amendment — 8 columns, with phase_c_freeze_amendment_pkey
--   (amendment_id bigint GENERATED ALWAYS AS IDENTITY, sequence
--   phase_c_freeze_amendment_amendment_id_seq), phase_c_freeze_amendment_once UNIQUE
--   (object_identity, prior_digest, new_digest) backed by the unique index of the same name,
--   phase_c_freeze_amendment_moves (prior_digest <> new_digest),
--   phase_c_freeze_amendment_reason_ck (length(btrim(reason)) >= 80) and
--   phase_c_freeze_amendment_evidence_ck (length(btrim(evidence)) >= 40). Row-level security is on
--   with 0 policies; the grants d49:63-64 makes (`revoke all … from public, anon, authenticated`
--   then `grant select, insert … to service_role`) go with the table.
--
-- The identity sequence and the unique index are owned by the table and go with it; they are named
-- above so the operator sees all three objects listed rather than two disappearing implicitly, and
-- the control block below asserts each is actually gone.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh by `select count(*) from
-- public.phase_c_freeze_amendment` at the time of writing):
--   public.phase_c_freeze_amendment   2 rows
--
-- Two is small and not cheap. The rows are:
--   canonical_step_engine              -> fn_kernel_open_step(p_input jsonb)
--   canonical_workflow_start_service   -> fn_kernel_workflow_start(p_input jsonb)
-- the two kernel routines d36 replaced to put the Phase D dispatch on the kernel's own open path.
-- Each row pins prior_digest to the exact body it excuses, so a later edit on top of it reads as
-- drift again — that pinning is the entire mechanism, and it is what is destroyed here.
--
-- RE-RUNNING d49 DOES NOT RESTORE THESE ROWS; IT WRITES WHATEVER IS TRUE THEN. d49:76-105 computes
-- prior_digest from public.phase_c_frozen_subject and new_digest with
-- encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex') over the live definition —
-- neither is a literal, deliberately, because a literal there would be the rubber stamp the file
-- exists to avoid. So if either kernel body has moved since, a re-apply records a DIFFERENT
-- amendment under the same subject, and the amendment these two rows recorded is gone. Export them
-- before running this file if the pinning matters:
--
--     create table zz_backup_phase_c_freeze_amendment as
--       select * from public.phase_c_freeze_amendment;
--
-- (that backup is a suggestion in a comment, not a statement this file executes.)
--
-- KNOWN CONSUMER: public.fn_phase_c_freeze_drift() is the only routine on htdblwldjkcgjvmqkbeh
-- whose body references phase_c_freeze_amendment (measured over pg_proc.prosrc). d49:106 replaced it
-- to read this table instead of a digest somebody retyped into phase_c_frozen_subject. After this
-- rollback it raises on a missing relation — and until it is also reverted, the Phase C freeze board
-- is down, not green. Expected, and worth saying out loud: a freeze monitor that raises is louder
-- than one that quietly reports 0 red.
--
-- NOT TOUCHED: the one CREATE OR REPLACE FUNCTION body in d49. A create-or-replace has no down —
-- see scripts/sql/down/README.md. Reverting d49 properly means reverting fn_phase_c_freeze_drift()
-- as well, and only the table half is DDL.
-- =================================================================================================


drop table if exists public.phase_c_freeze_amendment;

do $ctl$
declare v_left text := '';
begin
  if to_regclass('public.phase_c_freeze_amendment')      is not null then v_left := v_left || 'public.phase_c_freeze_amendment ';      end if;
  if to_regclass('public.phase_c_freeze_amendment_once') is not null then v_left := v_left || 'public.phase_c_freeze_amendment_once '; end if;

  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relkind = 'S'
                and c.relname = 'phase_c_freeze_amendment_amendment_id_seq') then
    v_left := v_left || 'sequence public.phase_c_freeze_amendment_amendment_id_seq ';
  end if;

  if v_left <> '' then
    raise exception 'D49 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D49 down: phase_c_freeze_amendment, its unique index and its identity sequence are gone, and the two kernel amendments with them. fn_phase_c_freeze_drift() now raises on a missing relation.';
end $ctl$;

