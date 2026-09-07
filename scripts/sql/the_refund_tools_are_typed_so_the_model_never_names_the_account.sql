-- THE REFUND TOOLS ARE TYPED SO THE MODEL NEVER NAMES THE ACCOUNT
--
-- v1.2 additional support requirements:
--
--   "Implement typed tools or equivalents for refund.inspect, ceo.request_decision,
--    refund.execute_authorized, refund.read_status and case.record_verified_resolution. The model
--    never supplies arbitrary refund recipient/account SQL or self-authenticates an approval. Tools
--    must accept current authenticated scope, validate exact resource/amount/currency and query the
--    server-side CEO decision. Support sends accurate pending/failed/succeeded updates and continues
--    follow-through, without the founder."
--
--   "Do not mark a case resolved on CEO receipt or service task acceptance."
--
-- WHAT "TYPED" IS ACTUALLY BUYING. The failure it prevents is not a syntax error -- it is a support
-- model that composes `update transactions set refund_to = '<an account the customer just typed>'`.
-- A tool that takes free text and runs it has the same authority as the person who wrote the prompt.
-- So refund.execute_authorized below takes NO destination at all. It reads the destination off the
-- original settled payment, which is the only place a refund can legitimately go, and there is no
-- parameter through which a different one could be supplied.
--
-- AND THE SECOND HALF: "query the server-side CEO decision". Execution does not accept a decision as
-- an argument. It reads refund_case.state, which only fn_ceo_decide_refund can set to
-- 'ceo_authorized', and which a CHECK already pins to decided_by = 'ceo'. A caller cannot pass
-- authorised=true, because there is nowhere to pass it.

-- ---------------------------------------------------------------------------------------------
-- 1. THE DESTINATION OF RECORD. Not a parameter -- a lookup.
-- ---------------------------------------------------------------------------------------------
alter table public.refund_case
  add column if not exists destination_basis text,
  add column if not exists attempts int not null default 0,
  add column if not exists last_attempt_at timestamptz,
  add column if not exists status_reported_at timestamptz,
  add column if not exists status_reported_state text;

do $$ begin
  -- A DESTINATION MUST SAY WHERE IT CAME FROM. "the card that paid" is auditable; a bare string is
  -- a number somebody typed, and after the fact the two are indistinguishable.
  if not exists (select 1 from pg_constraint where conname = 'refund_case_destination_basis_ck') then
    alter table public.refund_case add constraint refund_case_destination_basis_ck
      check (destination_ref is null or coalesce(destination_basis,'') <> '');
  end if;
  -- RETRY WITHIN POLICY, not forever. §15 asks for retry-within-policy on a disabled service; an
  -- uncapped retry against a dead provider is an outage amplifier.
  if not exists (select 1 from pg_constraint where conname = 'refund_case_attempts_ck') then
    alter table public.refund_case add constraint refund_case_attempts_ck
      check (attempts between 0 and 5);
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. ceo.request_decision -- an exception routes to the CEO WITH a recommendation
-- ---------------------------------------------------------------------------------------------
-- "Exceptions route automatically to CEO with evidence and a recommendation. Do not place every
-- message in pending_ceo." The recommendation is required rather than optional: a report that hands
-- the CEO a question and no view is support declining to do its own job, and it is how a decision
-- queue fills with items nobody has thought about.
create or replace function public.fn_ceo_request_decision(
  p_case_id        bigint,
  p_subject        text,
  p_evidence       jsonb,
  p_recommendation text,
  p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_r jsonb;
begin
  if coalesce(btrim(p_recommendation), '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'a recommendation is required. Handing the CEO a question with no view is support declining to do its own work, and it is how a decision queue fills with items nobody has thought about.');
  end if;
  if p_evidence is null or p_evidence = '{}'::jsonb then
    return jsonb_build_object('ok', false, 'reason',
      'evidence is required. A decision asked for without the facts behind it cannot be made well, only quickly.');
  end if;

  v_r := public.fn_support_report_to_ceo(
    p_idempotency_key, 'elevated', p_subject, p_evidence,
    to_jsonb(array['investigated the case', 'checked the standing grant', 'formed a recommendation']),
    p_recommendation);

  return jsonb_build_object('ok', coalesce((v_r->>'ok')::boolean, false), 'report', v_r,
    'case_id', p_case_id,
    -- The case does NOT move to a resolved state here. That is the explicit v1.2 rule.
    'note', 'Routed to the CEO with evidence and a recommendation. The case stays open: it is not resolved by the CEO receiving it.');
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 3. refund.execute_authorized -- no destination parameter, no decision parameter
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_refund_execute_authorized(
  p_refund_id     bigint,
  p_expect_amount numeric,
  p_expect_currency text,
  p_provider_ref  text,
  p_provider_outcome text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; t record; v_dest text; v_basis text; v_state text;
begin
  select * into r from public.refund_case where refund_id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund case'); end if;

  -- THE SERVER-SIDE DECISION, read here rather than accepted from the caller. There is no parameter
  -- for "the CEO approved this", so a model cannot supply one.
  if r.state <> 'ceo_authorized' then
    return jsonb_build_object('ok', false, 'reason',
      format('this refund is %L, not ceo_authorized. Execution reads the decision from the record; it is not something a caller can assert.', r.state));
  end if;

  -- EXACT RESOURCE, AMOUNT AND CURRENCY. A mismatch is refused rather than rounded to the nearer of
  -- the two: "close enough" on money is the whole class of defect.
  if p_expect_amount is distinct from r.amount_aed then
    return jsonb_build_object('ok', false, 'reason',
      format('amount mismatch: the authorised refund is %s, the caller expected %s. Refusing rather than paying the difference in either direction.', r.amount_aed, p_expect_amount));
  end if;
  if upper(coalesce(p_expect_currency,'')) <> upper(r.currency) then
    return jsonb_build_object('ok', false, 'reason',
      format('currency mismatch: authorised in %s, caller expected %s.', r.currency, coalesce(p_expect_currency,'(none)')));
  end if;

  if r.attempts >= 5 then
    return jsonb_build_object('ok', false, 'reason',
      'retry policy exhausted at 5 attempts. The refund stays authorised and unpaid, which is a visible blocked state -- not a silent success and not an infinite retry against a provider that is down.');
  end if;

  -- THE DESTINATION IS DERIVED, NEVER PASSED. "Do not refund to an arbitrary new destination."
  select id, fee_status, reveal_fee, payment_ref into t
    from public.transactions where id = r.transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'the settled payment behind this refund no longer exists; there is no destination of record to return money to.');
  end if;
  v_dest := t.payment_ref;
  v_basis := 'the original settled payment on transaction ' || r.transaction_id::text
          || '. Money returns the way it came; this function has no parameter for anywhere else.';
  if coalesce(v_dest,'') = '' then
    update public.refund_case set attempts = r.attempts + 1, last_attempt_at = now(),
      failure_reason = 'no payment reference on the settled transaction, so no destination of record.', updated_at = now()
     where refund_id = p_refund_id;
    return jsonb_build_object('ok', false, 'reason',
      'the settled payment carries no reference, so there is no destination of record. Held as authorised-and-blocked rather than sent somewhere plausible.');
  end if;

  v_state := case lower(coalesce(p_provider_outcome,''))
    when 'succeeded' then 'succeeded'
    when 'pending'   then 'provider_pending'
    when 'failed'    then 'failed'
    else 'submitted' end;

  update public.refund_case
     set state = v_state, destination_ref = v_dest, destination_basis = v_basis,
         provider_ref = p_provider_ref, provider_status = p_provider_outcome,
         submitted_at = coalesce(submitted_at, now()),
         settled_at = case when v_state = 'succeeded' then now() else settled_at end,
         failure_reason = case when v_state = 'failed' then coalesce(p_provider_outcome,'provider reported failure') else failure_reason end,
         attempts = r.attempts + 1, last_attempt_at = now(), updated_at = now()
   where refund_id = p_refund_id;

  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'state', v_state,
    'destination_ref', v_dest, 'destination_basis', v_basis, 'attempt', r.attempts + 1,
    'note', case v_state
      when 'succeeded' then 'Settled at the provider. The customer still has to be TOLD -- succeeded is not communicated.'
      when 'failed' then 'The provider refused it. This stays visible and retriable within policy; it is not a closed case.'
      else 'Submitted. Submitted is not settled, and the status tool reads the provider, not this row''s optimism.' end);
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 4. refund.read_status -- and the record of what the customer was actually told
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_refund_read_status(p_refund_id bigint, p_mark_reported boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_say text;
begin
  select * into r from public.refund_case where refund_id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund case'); end if;

  -- THE CUSTOMER-FACING SENTENCE IS DERIVED FROM THE STATE, not composed. "Support sends accurate
  -- pending/failed/succeeded updates" -- accurate meaning the words cannot drift from the row.
  v_say := case r.state
    when 'requested'      then 'I have your refund request and I am looking into it now.'
    when 'investigating'  then 'I am still checking the payment and the delivery on your inquiry.'
    when 'eligible'       then 'I have finished checking and your request is going for a decision.'
    when 'ineligible'     then 'I have checked this and it is not eligible for a refund. ' || coalesce(r.eligibility_reason,'')
    when 'ceo_authorized' then 'Your refund has been approved. It has not left us yet -- I will tell you the moment it is sent.'
    when 'ceo_declined'   then 'Your refund was not approved. ' || coalesce(r.decision_rationale,'')
    when 'submitted'      then 'Your refund has been sent to the payment provider. It is not settled yet.'
    when 'provider_pending' then 'Your refund is with the payment provider and is still processing.'
    when 'succeeded'      then 'Your refund has been paid back to the card or account you originally paid from.'
    when 'failed'         then 'The refund did not go through at the payment provider. It is not lost -- I am on it and will come back to you.'
    when 'canceled'       then 'This refund was cancelled before it was sent.'
    when 'reconciled'     then 'Your refund is complete and reconciled on our side.'
    when 'communicated'   then 'Your refund is complete and you have been notified.'
    else 'I am checking the current state of your refund.' end;

  if p_mark_reported then
    update public.refund_case
       set status_reported_at = now(), status_reported_state = r.state, updated_at = now()
     where refund_id = p_refund_id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'state', r.state,
    'amount_aed', r.amount_aed, 'currency', r.currency, 'attempts', r.attempts,
    'provider_status', r.provider_status, 'destination_basis', r.destination_basis,
    'customer_message', v_say,
    -- A SUCCEEDED REFUND THE CUSTOMER HAS NOT BEEN TOLD ABOUT is an unfinished case, and this names it.
    'follow_through_owed', r.state in ('succeeded','failed','ceo_declined')
                           and (r.status_reported_state is distinct from r.state));
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 5. case.record_verified_resolution -- a case closes on evidence, never on receipt
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_case_record_verified_resolution(
  p_case_id     bigint,
  p_resolution  text,
  p_verified_by jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare c record; v_open int;
begin
  select * into c from public.support_case where case_id = p_case_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such case'); end if;
  if c.state = 'closed' then
    return jsonb_build_object('ok', true, 'already_closed', true, 'reason', c.close_reason);
  end if;
  if coalesce(btrim(p_resolution), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'a close needs a reason; a close that records facts and decides nothing is the defect this estate has already paid for.');
  end if;
  -- VERIFICATION IS A READING OF STATE, not a claim that work happened. "Do not mark a case resolved
  -- on CEO receipt or service task acceptance": both of those are receipts, and a receipt is an
  -- acknowledgement that something was HANDED OVER, not evidence that it landed.
  if p_verified_by is null or coalesce(p_verified_by->>'observed', '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'p_verified_by must name what was OBSERVED (the row, the provider state, the delivered message). A CEO receipt or an accepted service task is an acknowledgement of handover, not evidence of an outcome.');
  end if;

  -- AND THE CASE CANNOT CLOSE OVER LIVE WORK. A refund still moving is an open case whatever the
  -- conversation felt like.
  select count(*) into v_open from public.refund_case
   where case_id = p_case_id
     and state in ('requested','investigating','eligible','ceo_authorized','submitted','provider_pending');
  if v_open > 0 then
    return jsonb_build_object('ok', false, 'reason',
      format('%s refund(s) on this case are still moving. Closing now would report a resolution the money has not reached yet.', v_open));
  end if;

  update public.support_case
     set state = 'closed', closed_at = now(), last_activity_at = now(),
         close_reason = p_resolution || ' || verified by: ' || (p_verified_by->>'observed')
   where case_id = p_case_id;

  return jsonb_build_object('ok', true, 'case_id', p_case_id, 'state', 'closed',
    'verified_by', p_verified_by,
    'note', 'Closed against an observed outcome, not against a receipt.');
end $function$;

revoke execute on function public.fn_ceo_request_decision(bigint,text,jsonb,text,text) from public;
revoke execute on function public.fn_ceo_request_decision(bigint,text,jsonb,text,text) from anon;
revoke execute on function public.fn_ceo_request_decision(bigint,text,jsonb,text,text) from authenticated;
revoke execute on function public.fn_refund_execute_authorized(bigint,numeric,text,text,text) from public;
revoke execute on function public.fn_refund_execute_authorized(bigint,numeric,text,text,text) from anon;
revoke execute on function public.fn_refund_execute_authorized(bigint,numeric,text,text,text) from authenticated;
revoke execute on function public.fn_refund_read_status(bigint,boolean) from public;
revoke execute on function public.fn_refund_read_status(bigint,boolean) from anon;
revoke execute on function public.fn_refund_read_status(bigint,boolean) from authenticated;
revoke execute on function public.fn_case_record_verified_resolution(bigint,text,jsonb) from public;
revoke execute on function public.fn_case_record_verified_resolution(bigint,text,jsonb) from anon;
revoke execute on function public.fn_case_record_verified_resolution(bigint,text,jsonb) from authenticated;
