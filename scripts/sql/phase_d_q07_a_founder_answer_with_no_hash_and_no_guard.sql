-- Q07. A FOUNDER ANSWER WITH NO HASH AND NO GUARD.
--
-- NO TRANSACTION CONTROL. One implicit transaction under a simple-query batch; rehearsable.
--
-- WHY THIS FILE EXISTS. On 24 Aug 2026 the founder submitted two governance decisions. The first
-- was a NEW COMMAND and it produced a complete record: `founder_command_message` 37730 carrying
-- `raw_text`, `raw_text_hash = sha256(raw_text)`, `z10_founder_command_message_immutable` refusing
-- UPDATE and DELETE, `z00_kernel_truncate_guard` refusing TRUNCATE, and a
-- `TRACE-FOUNDER-COMMAND` row. Everything an audit needs.
--
-- The second — his PCCR-006 approval — was typed as the ANSWER to the clarification on that same
-- command, which is the natural thing to do in a thread. phase_d_q01 fixed the defect that threw it
-- away. But even once it lands, it lands somewhere with none of that:
--
--   select tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid
--    where c.relname = 'founder_command_clarification' and not t.tgisinternal;
--   -> 0 rows
--
-- No hash. No immutability. No truncate guard. `founder_command_clarification.answer_text` holds
-- the founder's own words on the governance path and anything with write access could edit them
-- afterwards, and nothing would say so. `founder_command_message` has had all three since it was
-- built; its sibling never got them.
--
-- THIS DOES NOT MAKE A CLARIFICATION ANSWER EQUAL TO A COMMAND, AND IT SHOULD NOT.
-- A command carries its own message row, its own idempotency key and its own root trace; an answer
-- is an append to an existing thread and has none of those by design. What this file makes true is
-- narrower and it is the part that matters for a DECISION: the words are hashed at write time, and
-- once written neither the words nor the timestamp can move. For a governance approval the stronger
-- record is still a NEW COMMAND, and that is what should be asked for.
--
-- WHY A TRIGGER AND NOT A CHANGE TO THE ROUTINE. `fn_founder_command_clarify` is a FROZEN Phase C
-- subject — `chief_of_staff_command_path`, alongside `fn_founder_command_submit` and
-- `fn_founder_command_control`. Editing it needs a Phase C change request and the founder's
-- approval in a verified session, which is the very thing that is blocked. A BEFORE trigger on the
-- table is additive, touches no frozen routine, and covers EVERY writer rather than the one routine
-- that happens to be the writer today. The frozen digest is asserted unchanged at the end of this
-- file.
--
-- THE TRUNCATE GUARD GOES ON IN THE SAME MIGRATION AS THE RAISING TRIGGER. A table that refuses
-- UPDATE and DELETE and permits TRUNCATE is not append-only; it is append-only until somebody finds
-- the other door.
--
-- ROLLBACK: scripts/sql/down/phase_d_q07_a_founder_answer_with_no_hash_and_no_guard_down.sql

-- ------------------------------------------------------------------------------------------------
-- 1. THE HASH COLUMN. Nullable, because a clarification exists from the moment it is ASKED and is
--    answered later; the hash is a fact about the answer and cannot precede it.

ALTER TABLE public.founder_command_clarification
  ADD COLUMN IF NOT EXISTS answer_hash text;

ALTER TABLE public.founder_command_clarification
  DROP CONSTRAINT IF EXISTS founder_command_clarification_answer_hash_shape;
ALTER TABLE public.founder_command_clarification
  ADD CONSTRAINT founder_command_clarification_answer_hash_shape CHECK (
    answer_hash IS NULL OR answer_hash ~ '^[0-9a-f]{64}$');

-- The hash and the answer travel together or not at all. An answer with no hash is the state this
-- file exists to make impossible; a hash with no answer is a hash of nothing.
ALTER TABLE public.founder_command_clarification
  DROP CONSTRAINT IF EXISTS founder_command_clarification_hash_accompanies_answer;
ALTER TABLE public.founder_command_clarification
  ADD CONSTRAINT founder_command_clarification_hash_accompanies_answer CHECK (
    (nullif(btrim(answer_text), '') IS NULL) = (answer_hash IS NULL)) NOT VALID;

-- ------------------------------------------------------------------------------------------------
-- 2. THE GUARD. Stamps the hash, then refuses to let the record move.

CREATE OR REPLACE FUNCTION public.fn_founder_command_clarification_answer_is_sealed()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if TG_OP = 'DELETE' then
    raise exception
      'founder_command_clarification is append-only: clarification % on command % may not be '
      'deleted. What the founder was asked, and what he answered, is the record — deleting it '
      'leaves a command whose interpretation nobody can account for. '
      '(fcc_clarification_immutable)', OLD.clarification_id, OLD.command_id
      using errcode = '42501';
  end if;

  -- The hash is DERIVED here and never taken from the caller. A caller-supplied hash is a claim
  -- about text, and the text is right there.
  --
  -- sha256(convert_to(...)) and NOT digest(text,'sha256'): digest is pgcrypto's and pgcrypto is not
  -- on this function's pinned search_path, so the first rehearsal raised 42883. sha256 is a
  -- pg_catalog builtin, always reachable, and produces the identical digest for UTF8 text. It is
  -- what fn_phase_d_domain_source_digest already uses for the same reason.
  if nullif(btrim(NEW.answer_text), '') is not null then
    NEW.answer_hash := encode(sha256(convert_to(NEW.answer_text, 'UTF8')), 'hex');
  else
    NEW.answer_hash := null;
  end if;

  if TG_OP = 'UPDATE' then
    -- The question never moves.
    if NEW.question is distinct from OLD.question then
      raise exception
        'founder_command_clarification %: the question asked may not be edited after it was asked '
        '(fcc_question_immutable)', OLD.clarification_id using errcode = '42501';
    end if;
    -- ANSWERING is the one permitted transition: null -> text, once.
    if nullif(btrim(OLD.answer_text), '') is not null
       and NEW.answer_text is distinct from OLD.answer_text then
      raise exception
        'founder_command_clarification %: the answer was recorded at % and may not be changed. An '
        'answer that can be edited after the fact records the editor, not the founder. Ask a new '
        'clarification, or submit a new command. (fcc_answer_immutable)',
        OLD.clarification_id, OLD.answered_at using errcode = '42501';
    end if;
    if OLD.answered_at is not null and NEW.answered_at is distinct from OLD.answered_at then
      raise exception
        'founder_command_clarification %: answered_at may not be moved (fcc_answered_at_immutable)',
        OLD.clarification_id using errcode = '42501';
    end if;
    if NEW.command_id is distinct from OLD.command_id then
      raise exception
        'founder_command_clarification %: a clarification may not be moved to another command '
        '(fcc_command_immutable)', OLD.clarification_id using errcode = '42501';
    end if;
  end if;

  return NEW;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_founder_command_clarification_answer_is_sealed() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_founder_command_clarification_answer_is_sealed() TO service_role;

DROP TRIGGER IF EXISTS a00_founder_command_clarification_answer_is_sealed
  ON public.founder_command_clarification;
CREATE TRIGGER a00_founder_command_clarification_answer_is_sealed
  BEFORE INSERT OR UPDATE OR DELETE ON public.founder_command_clarification
  FOR EACH ROW EXECUTE FUNCTION public.fn_founder_command_clarification_answer_is_sealed();

-- THE OTHER DOOR, CLOSED IN THE SAME FILE. A table that refuses UPDATE and DELETE and permits
-- TRUNCATE is append-only until somebody finds the other door.
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.founder_command_clarification;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.founder_command_clarification
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

-- REVOKING FROM PUBLIC IS NOT ENOUGH, AND fn_kernel_truncate_protection_state SAID SO.
-- The first apply of this file revoked TRUNCATE from PUBLIC only, and the board went red with
--   enforcing_tables_still_granting_truncate  1 of 92
-- because service_role held it through its OWN grant, not through PUBLIC. Measured: this table read
-- service_role=arwdDxtm while its sibling public.founder_command_message reads service_role=arwdxtm
-- — the D is TRUNCATE, and the sibling has never had it. Both revokes are here so the ACL matches
-- the table this one exists to be as trustworthy as.
REVOKE TRUNCATE ON public.founder_command_clarification FROM PUBLIC;
REVOKE TRUNCATE ON public.founder_command_clarification FROM service_role;

-- ------------------------------------------------------------------------------------------------
-- 3. THE FIVE ANSWERS THAT ARE ALREADY ON THE RECORD.
--
-- This file's first rehearsal asserted that no answered clarification lacks a hash and FAILED with
-- "5 answered clarification(s) carry no hash" — which is the assertion doing its job on the
-- author's own wrong assumption. The header of an earlier draft said there were none answered at
-- all; that was true of command 36607 and false of the table. Measured 25 Aug 2026:
--
--   9  command 223   2026-08-16 10:35:14+00
--   18 command 270   2026-08-16 22:39:28+00
--   20 command 273   2026-08-16 22:42:07+00
--   21 command 338   2026-08-17 15:23:54+00
--   96 command 1681  2026-08-18 04:49:08+00
--
-- All five are marketing clarifications from the command-router work of 16-18 Aug. None is a
-- governance decision.
--
-- THE BACKFILL IS A DERIVATION, NOT AN INVENTION. The hash is computed from the answer_text that is
-- already stored, by the same expression the trigger uses. It adds no fact: it records the digest of
-- words the estate has held since August. What it CANNOT do is prove those words were never edited
-- before today, because until this file there was nothing stopping that — and that limitation is the
-- reason the file exists rather than something it papers over.

UPDATE public.founder_command_clarification
   SET answer_hash = encode(sha256(convert_to(answer_text, 'UTF8')), 'hex')
 WHERE nullif(btrim(answer_text), '') IS NOT NULL AND answer_hash IS NULL;

-- Now that every answered row carries one, the shape constraint can be validated over the whole
-- table rather than left NOT VALID.
ALTER TABLE public.founder_command_clarification
  VALIDATE CONSTRAINT founder_command_clarification_hash_accompanies_answer;

-- ------------------------------------------------------------------------------------------------
-- 4. ASSERTIONS.

DO $assert$
DECLARE
  v_trg      int;
  v_trunc    int;
  v_unhashed int;
  v_frozen   text;
  v_live     text;
BEGIN
  SELECT count(*) INTO v_trg FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
   WHERE c.relname = 'founder_command_clarification'
     AND t.tgname = 'a00_founder_command_clarification_answer_is_sealed' AND t.tgenabled <> 'D';
  SELECT count(*) INTO v_trunc FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
   WHERE c.relname = 'founder_command_clarification'
     AND t.tgname = 'z00_kernel_truncate_guard' AND t.tgenabled <> 'D';
  IF v_trg <> 1 OR v_trunc <> 1 THEN
    RAISE EXCEPTION 'Q07: seal trigger % , truncate guard % — both must be 1', v_trg, v_trunc
      USING errcode = '23514';
  END IF;

  -- No ANSWERED clarification may be left without a hash. Section 3 backfilled the five that
  -- existed; this is the check that section 3 was complete, over the WHOLE table and not over the
  -- rows this file happened to touch.
  SELECT count(*) INTO v_unhashed FROM public.founder_command_clarification
   WHERE nullif(btrim(answer_text),'') IS NOT NULL AND answer_hash IS NULL;
  IF v_unhashed <> 0 THEN
    RAISE EXCEPTION 'Q07: % answered clarification(s) carry no hash', v_unhashed USING errcode = '23514';
  END IF;

  -- THE FROZEN ROUTINE WAS NOT TOUCHED. Asserted against public.phase_c_frozen_subject, not assumed
  -- from the fact that this file contains no CREATE for it.
  SELECT f.digest INTO v_frozen FROM public.phase_c_frozen_subject f
   WHERE f.object_identity = 'fn_founder_command_clarify(p_command_id bigint, p_answer text, p_actor text)';
  SELECT encode(digest(pg_get_functiondef(p.oid), 'sha256'), 'hex') INTO v_live
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'fn_founder_command_clarify';
  IF v_frozen IS NULL OR v_live IS DISTINCT FROM v_frozen THEN
    RAISE EXCEPTION 'Q07: fn_founder_command_clarify drifted from its frozen digest (frozen %L, live %L)',
      coalesce(v_frozen,'(none)'), coalesce(v_live,'(none)') USING errcode = '23514';
  END IF;

  IF has_table_privilege('service_role','public.founder_command_clarification','TRUNCATE')
     OR has_table_privilege('anon','public.founder_command_clarification','TRUNCATE')
     OR has_table_privilege('authenticated','public.founder_command_clarification','TRUNCATE') THEN
    RAISE EXCEPTION 'Q07: a role still holds TRUNCATE on founder_command_clarification. A raising '
      'trigger makes a table enforcing, and an enforcing table that still grants TRUNCATE is '
      'append-only until somebody finds the other door.' USING errcode = '42501';
  END IF;

  RAISE NOTICE 'Q07 OK: seal trigger on, truncate guard on, % answered clarification(s) without a '
    'hash, frozen chief_of_staff_command_path digest unchanged', v_unhashed;
END $assert$;
