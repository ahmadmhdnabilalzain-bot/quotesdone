-- THE REFUND GUARD REFUSED HIS OWN WORDS.
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE and one assertion block; rehearsable.
--
-- ================================================================================================
-- WHAT WAS MEASURED, ON PRODUCTION, 26 AUG 2026
-- ================================================================================================
--
-- phase_c_a_refund_amount_was_a_number_somebody_typed.sql put a BEFORE trigger on
-- public.founder_approval_request requiring every refund_decision request to carry a subject_ref of
-- the form 'refund:<id>' naming a real refunds row. Ninety minutes later, this:
--
--   select public.fn_founder_command_submit('management@quotesdone.com',
--            'Approve refund for transaction TX-123.', 'probe:cc009', '{}'::jsonb);
--   ERROR: 22023: founder_approval_request: subject_ref TX-123 is not of the form refund:<id>.
--          (founder_approval_subject_malformed)
--   CONTEXT: PL/pgSQL function fn_founder_command_submit(text,text,text,jsonb) line 207
--
-- fn_founder_command_submit mints the inbox item from a regex over his own sentence --
-- coalesce((regexp_match(p_text, '(TX-[A-Za-z0-9_-]+)'))[1], 'UNIDENTIFIED_TRANSACTION') -- so
-- every refund-shaped command he sends now raises, and the raise takes his WHOLE command with it:
-- the founder_command_message row that records his words is written in the same transaction and
-- never survives. Acceptance cases CC-009 and CC-010 are exactly this sentence, and both went red.
--
-- The guard was right about the rule and wrong about where the rule bites. It cannot be relaxed to
-- make the check green -- his instruction of 26 Aug 2026 stands: "how could you issue a random
-- refund figure? ... and currently we have none, so the system shouldnt even allow it". It also
-- cannot stand as written, because the one thing this system must never do is lose what he said.
--
-- ================================================================================================
-- THE DISTINCTION THE GUARD WAS MISSING: AN INTAKE ITEM IS NOT A DECISION
-- ================================================================================================
--
-- Two different rows were being judged by one rule.
--
--   * INTAKE. He says "approve refund for transaction TX-123". The command path records his words
--     and raises a PENDING item for triage. 'TX-123' is a reference HE typed; it is not a claim
--     that a refund exists, and the transaction identifier in this estate is a uuid, so it could
--     never have resolved. This row is a question, and the answer to a question may be "there is
--     no such refund".
--
--   * A DECISION. state 'approved' on a refund_decision request is the founder authorising money to
--     move. That may never stand against a subject that names no refund.
--
-- So the rule moves to where it bites, and gets STRICTER in the place that matters:
--
--   1. A request written as 'refund:<id>' must name a refunds row that exists. This is the arm that
--      caught the PCCR-007 probe's 'refund:zz-audit-probe', and it is unchanged.
--   2. NO refund_decision request may reach state 'approved' unless its subject_ref resolves to a
--      real refunds row. That arm is new, and nothing enforced it before today.
--
-- 'rejected' and 'withdrawn' are deliberately NOT required to resolve: refusing them would trap an
-- unbacked item in his inbox with no way out, and "this names nothing, rejected" is the correct
-- disposal of exactly the row this migration allows in.
--
-- The money is not defended by this trigger and never was. It is defended by
-- a00_refund_amount_is_the_fee_paid on public.refunds (a refund must name a revealed transaction,
-- its amount must equal round(reveal_fee*100), the refund window must have passed),
-- z10_phase_c_refund_decision_guard on public.phase_c_refund_decision (the founder, resolved from a
-- verified session since PCCR-007), and z05_refund_execution_requires_decision. With
-- public.transactions at 0 rows, no refund row can exist, so no refund decision can be approved --
-- which is his third sentence, still true after this file.

create or replace function public.fn_founder_approval_names_a_real_refund()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare v_tail text; v_id bigint; v_backed boolean;
begin
  if NEW.action_class is distinct from 'refund_decision' then
    return NEW;
  end if;

  -- Only a subject_ref written as refund:<id> is CLAIMING to name a refund. Anything else is a
  -- reference the founder typed, and it is judged at the decision boundary below, not here.
  v_tail   := case when coalesce(NEW.subject_ref,'') ~ '^refund:'
                   then substring(NEW.subject_ref from 8) else null end;
  v_id     := case when v_tail ~ '^[0-9]+$' then v_tail::bigint else null end;
  v_backed := v_id is not null and exists (select 1 from public.refunds r where r.id = v_id);

  if v_tail is not null and v_id is null then
    raise exception 'founder_approval_request: subject_ref % is written as refund:<id> and the id is not a number. (founder_approval_subject_malformed)',
      coalesce(NEW.subject_ref,'(null)') using errcode = '22023';
  end if;

  if v_tail is not null and not v_backed then
    raise exception 'founder_approval_request: subject_ref % names no refund. A row that says refund:<id> is claiming a refund exists; this one does not. (founder_approval_subject_absent)',
      coalesce(NEW.subject_ref,'(null)') using errcode = '23503';
  end if;

  if coalesce(NEW.state,'') = 'approved' and not v_backed then
    raise exception 'founder_approval_request %: a refund decision may not be APPROVED against subject_ref %, which does not resolve to a row in public.refunds. He approves money leaving, and money that no refund record accounts for is not his decision to have made. (founder_approval_approved_without_a_refund)',
      coalesce(NEW.request_id::text,'(new)'), coalesce(NEW.subject_ref,'(null)')
      using errcode = '23514',
            hint = 'Create the refund first -- it must name the revealed transaction whose reveal_fee it returns -- then point subject_ref at it as refund:<id>. An intake item raised from his own words may sit pending, and may be rejected, but may not be approved.';
  end if;

  return NEW;
end
$function$;

-- The trigger itself is unchanged and is not re-created: a00_founder_approval_names_a_real_refund
-- already fires BEFORE INSERT OR UPDATE on public.founder_approval_request. CREATE OR REPLACE
-- preserves the ACL, so the REVOKE from the previous file stands and is not repeated here.

-- ================================================================================================
-- SELF-VERIFICATION. Each case is its own subtransaction; the file raises only when a case behaves
-- wrongly, because an abort would take the DDL with it. The cases that must be ACCEPTED end in a
-- deliberate raise so the accepted row is rolled back with its subtransaction and nothing survives.
-- ================================================================================================
do $verify$
declare log text := ''; ok boolean := true; v jsonb; v_txn uuid; v_ref bigint; v_req bigint;
begin
  -- 1. HIS OWN WORDS. The command that was refused ninety minutes ago must land.
  begin
    v := public.fn_founder_command_submit('management@quotesdone.com',
           'Approve refund for transaction TX-123.', 'verify:refund_guard:cc009', '{}'::jsonb);
    log := log || 'HIS_REFUND_COMMAND=ACCEPTED(appr='
                || (select count(*)::text from public.founder_approval_request
                     where command_id = (v->>'command_id')::bigint) || ') ';
    raise exception 'ROLLBACK_THIS_CASE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_THIS_CASE' then
      log := log || 'HIS_REFUND_COMMAND=REFUSED(' || sqlstate || ':' || left(sqlerrm, 90) || ')(WRONG) ';
      ok := false;
    end if;
  end;

  -- 2. The PCCR-007 probe's item, which is what the original arm was written for.
  begin
    insert into public.founder_approval_request
      (action_class, subject_ref, prepared_by_role_id, amount_note, evidence, state)
    values ('refund_decision','refund:zz-audit-probe','payments_and_billing_manager','AED 10.00',
            '{}'::jsonb,'pending');
    log := log || 'CLAIMS_A_REFUND_THAT_IS_NOT_AN_ID=ACCEPTED(WRONG) '; ok := false;
  exception when others then
    log := log || 'CLAIMS_A_REFUND_THAT_IS_NOT_AN_ID=REFUSED(' || sqlstate || ') ';
  end;

  -- 3. A well-formed id that names nothing.
  begin
    insert into public.founder_approval_request
      (action_class, subject_ref, prepared_by_role_id, amount_note, evidence, state)
    values ('refund_decision','refund:999999999','payments_and_billing_manager','AED 10.00',
            '{}'::jsonb,'pending');
    log := log || 'CLAIMS_A_REFUND_THAT_DOES_NOT_EXIST=ACCEPTED(WRONG) '; ok := false;
  exception when others then
    log := log || 'CLAIMS_A_REFUND_THAT_DOES_NOT_EXIST=REFUSED(' || sqlstate || ') ';
  end;

  -- 4. THE NEW ARM, FORCED TO FIRE. An intake item is raised from his words and then moved to
  -- 'approved' with nothing behind it. A guard that has never refused anything is indistinguishable
  -- from no guard, so this drives the UPDATE path directly rather than trusting that no caller
  -- would try it -- today no routine in this estate writes that state at all.
  begin
    insert into public.founder_approval_request
      (action_class, subject_ref, prepared_by_role_id, amount_note, evidence, state)
    values ('refund_decision','TX-123','payments_and_billing_manager','AED 10.00',
            '{}'::jsonb,'pending')
    returning request_id into v_req;
    update public.founder_approval_request set state = 'approved' where request_id = v_req;
    log := log || 'APPROVED_WITH_NO_REFUND=ACCEPTED(WRONG) '; ok := false;
    raise exception 'ROLLBACK_THIS_CASE';
  exception when others then
    if sqlerrm = 'ROLLBACK_THIS_CASE' then null;
    else log := log || 'APPROVED_WITH_NO_REFUND=REFUSED(' || sqlstate || ') '; end if;
  end;

  -- 5. THE POSITIVE CONTROL. A real chain -- revealed transaction, refund for exactly the fee paid,
  -- window passed -- is accepted, and may be approved. Rolled back with its subtransaction.
  begin
    insert into public.transactions (id, revealed_at, reveal_fee, fee_status, paid_by, payment_ref)
    values (gen_random_uuid(), now() - interval '60 days', 10.00, 'paid','customer','verify:refund_guard')
    returning id into v_txn;
    insert into public.refunds (transaction_id, currency, reason_code, status, requested_by,
      requested_at, within_auto_window, amount_fils)
    select t.id,'AED','service_not_delivered','requested','zz-verify@example.invalid', now(), false,
           round(t.reveal_fee * 100)::bigint
      from public.transactions t where t.id = v_txn
    returning id into v_ref;
    insert into public.founder_approval_request
      (action_class, subject_ref, prepared_by_role_id, amount_note, evidence, state)
    values ('refund_decision','refund:'||v_ref,'payments_and_billing_manager','AED 10.00',
            '{}'::jsonb,'pending')
    returning request_id into v_req;
    update public.founder_approval_request set state = 'approved' where request_id = v_req;
    log := log || 'A_REAL_REFUND_MAY_BE_APPROVED=ACCEPTED ';
    raise exception 'ROLLBACK_THIS_CASE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_THIS_CASE' then
      log := log || 'A_REAL_REFUND_MAY_BE_APPROVED=REFUSED(' || sqlstate || ':' || left(sqlerrm, 90) || ')(WRONG) ';
      ok := false;
    end if;
  end;

  log := log || '| refunds=' || (select count(*) from public.refunds)
             || ' approval_requests=' || (select count(*) from public.founder_approval_request)
             || ' transactions=' || (select count(*) from public.transactions)
             || ' commands=' || (select count(*) from public.founder_command) || ' ';

  if not ok then
    raise exception 'REFUND_SUBJECT_GUARD_FAILED | %', log using errcode = '23514';
  end if;
  raise notice 'REFUND_SUBJECT_GUARD_VERIFIED | %', log;
end
$verify$;
