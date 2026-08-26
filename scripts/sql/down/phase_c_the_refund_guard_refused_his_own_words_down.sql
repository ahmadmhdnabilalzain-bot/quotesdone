-- ROLLBACK for scripts/sql/phase_c_the_refund_guard_refused_his_own_words.sql
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE and an assertion; rehearsable.
--
-- Restores public.fn_founder_approval_names_a_real_refund to the body
-- phase_c_a_refund_amount_was_a_number_somebody_typed.sql deployed on 2026-08-26 at 12:43 UTC,
-- reproduced from that file verbatim.
--
-- WHAT APPLYING THIS REOPENS, named rather than left to be discovered. The restored body requires
-- EVERY refund_decision approval request to carry subject_ref of the form refund:<id> naming a real
-- refunds row. public.fn_founder_command_submit mints that row from a regex over the founder's own
-- sentence -- 'TX-123', or the literal 'UNIDENTIFIED_TRANSACTION' -- so every refund-shaped command
-- he sends raises 22023, and the raise takes the whole command with it, including the
-- founder_command_message row that records his words. Measured on production on 26 Aug 2026, and
-- acceptance cases CC-009 and CC-010 both red.
--
-- It also drops the arm this file added, which nothing else enforces: a refund_decision request
-- reaching state 'approved' with a subject that resolves to no refunds row.

create or replace function public.fn_founder_approval_names_a_real_refund()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare v_id bigint;
begin
  if NEW.action_class is distinct from 'refund_decision' then
    return NEW;
  end if;
  v_id := nullif(regexp_replace(coalesce(NEW.subject_ref,''), '^refund:', ''), '')::bigint;
  if v_id is null or not exists (select 1 from public.refunds r where r.id = v_id) then
    raise exception 'founder_approval_request: subject_ref % names no refund. A refund decision he is asked to make must point at a refund that exists, as refund:<id>. An inbox item that points at nothing is a decision about nothing. (founder_approval_subject_absent)',
      coalesce(NEW.subject_ref,'(null)') using errcode = '23503';
  end if;
  return NEW;
exception when invalid_text_representation then
  raise exception 'founder_approval_request: subject_ref % is not of the form refund:<id>. (founder_approval_subject_malformed)',
    coalesce(NEW.subject_ref,'(null)') using errcode = '22023';
end
$function$;

DO $assert$
DECLARE v_state text;
BEGIN
  BEGIN
    INSERT INTO public.founder_approval_request (action_class, subject_ref, prepared_by_role_id)
    VALUES ('refund_decision','TX-ROLLBACK-ASSERT','payments_and_billing_manager');
    v_state := 'ACCEPTED';
    RAISE EXCEPTION 'ROLLBACK_THIS_CASE';
  EXCEPTION WHEN OTHERS THEN
    IF sqlerrm = 'ROLLBACK_THIS_CASE' THEN v_state := 'ACCEPTED';
    ELSE v_state := 'REFUSED ' || sqlstate; END IF;
  END;
  IF v_state NOT LIKE 'REFUSED%' THEN
    RAISE EXCEPTION 'rollback did not restore the strict body (a free-text subject was %)', v_state
      USING errcode = '23514';
  END IF;
  RAISE NOTICE 'strict subject_ref body restored; a free-text subject is % again', v_state;
END $assert$;
