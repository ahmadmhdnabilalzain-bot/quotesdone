-- M05 — the rule that would have refused the send was never asked
--
-- MEASURED 24 Aug 2026 on htdblwldjkcgjvmqkbeh, while deciding PD-NOTIFY-005 ("supplier receives
-- raw customer identity in email"). Its recorded blocker said the case needs a rendered body and a
-- PII detector in the edge functions. Both halves are wrong in the direction that matters:
--
--   public.fn_phase_d_external_deliver(jsonb) was called for step W13-S02 with an approved payload
--   whose body read "contact Ahmad at zz.cust@example.invalid / 0501234567". It returned
--   ok=true, delivered=true and recorded attempt 25981.
--
-- BR-011 -- "no customer identity in a supplier-facing payload" -- refuses that exact string. It is
-- how PD-PRIV-001 is closed in the same session. It refuses on SHAPE as well as on a row match, so
-- it does not depend on public.customers holding rows. The send path never asked it.
--
-- This is the estate's "a finished capability with no entry point", one step worse: the guard
-- exists, it is correct, it is registered at fn_phase_d_rule_check, and nothing on the path that
-- needs it calls it.
--
-- WHOSE STEPS IT GOVERNS IS NOT DECIDED IN THE SEND PATH. fn_phase_d_rule_applies is the estate's
-- own answer to whether a rule governs a step; asking it here means BR-011's scope stays in the
-- register where the frozen Phase B workflow_scope, the step-level applicability and L02's
-- producing-step position all already live. Measured before and after: BR-011 applies to 42 of the
-- 257 steps (W08, W12, W13, W14, W15) and that set does not move.
--
-- Proved both directions, by execution, in aborted transactions:
--   the same call with the identity in the body   -> br011_identity_before_reveal, nothing recorded
--   the same call with the identity removed       -> delivered, attempt recorded
--
-- ROLLBACK: re-apply the previous body,
-- scripts/sql/phase_d_f30_every_remaining_reader_of_the_string_f01_removed.sql
-- GENERATED from the live body by scripts/tmp_diag/gen_m05.mjs.

CREATE OR REPLACE FUNCTION public.fn_phase_d_external_deliver(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_step    text  := nullif(btrim(coalesce(p_input->>'step_id','')),'');
  v_idem    text  := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_case    text  := lower(nullif(btrim(coalesce(p_input->>'mock_case','')),''));
  v_mode    text  := lower(coalesce(nullif(btrim(p_input->>'provider_mode'),''),'mock'));
  v_payload jsonb := p_input->'approved_payload';
  v_ref     text  := nullif(btrim(coalesce(p_input->>'approved_payload_ref','')),'');
  v_effect  bigint := nullif(p_input->>'effect_id','')::bigint;
  v_kind    text  := lower(coalesce(nullif(btrim(p_input->>'effect_kind'),''),'generic'));
  v_prior   public.phase_d_external_attempt%rowtype;
  v_no      int;
  v_sha     text;
  v_reqid   text;
  v_resid   text;
  v_retry   text;
  v_delivered boolean := false;
  v_br011     boolean;      -- M05
  v_br011_ok  boolean;      -- M05
  v_br011_why text;         -- M05
  v_recon   text;
  v_dead    timestamptz;
  v_deadwhy text;
  v_cancel  timestamptz;
  v_cancelwhy text;
  v_id      bigint;
  v_missing text;
  v_cap     int := 3;
begin
  if v_step is null or v_idem is null or v_case is null or v_ref is null then
    raise exception 'fn_phase_d_external_deliver: step_id, idempotency_key, mock_case and approved_payload_ref are all required (pd_external_input_invalid)'
      using errcode = '22023';
  end if;
  if v_mode <> 'mock' then
    raise exception 'fn_phase_d_external_deliver: provider_mode is %; this adapter has no live mode and never sends (pd_external_live_mode_refused)', v_mode
      using errcode = '42501';
  end if;
  if public.fn_phase_d_fixture_context() is null then
    raise exception 'fn_phase_d_external_deliver: no verified Phase D fixture context in this transaction (pd_external_no_test_context)'
      using errcode = '23514';
  end if;
  -- FIELD 2. An intent with no approved payload is not deliverable. This is the field that was
  -- absent, and it is a refusal rather than a column: nothing may be delivered that nobody approved.
  if v_payload is null or jsonb_typeof(v_payload) <> 'object' or v_payload = '{}'::jsonb then
    raise exception 'fn_phase_d_external_deliver: % carries no approved payload. An intent nobody approved is not deliverable. (pd_external_payload_not_approved)', v_step
      using errcode = '22023';
  end if;

  -- THE FOUNDER'S FOUR-MESSAGE REVEAL CONTRACT, enforced on the payload rather than assumed.
  if v_kind = 'reveal' then
    select string_agg(c.contract_key, ', ' order by c.contract_key) into v_missing
      from public.phase_d_external_message_contract c
     where c.effect_kind = 'reveal' and c.required
       and not (coalesce(v_payload->'messages','[]'::jsonb) @> to_jsonb(array[c.contract_key]));
    if v_missing is not null then
      raise exception 'fn_phase_d_external_deliver: a reveal must carry all four messages the founder specified — an email and a WhatsApp to BOTH parties. Missing: %. (pd_external_reveal_contract_incomplete)', v_missing
        using errcode = '23514';
    end if;
  end if;

  -- M05. THE RULE THAT WOULD HAVE REFUSED IT WAS NEVER ASKED.
  --
  -- Measured 24 Aug 2026 while deciding PD-NOTIFY-005: fn_phase_d_external_deliver('W13-S02', ...)
  -- with an approved payload whose body read "contact Ahmad at zz.cust@example.invalid /
  -- 0501234567" returned ok=true, delivered=true, and recorded attempt 25981. BR-011 -- "no customer
  -- identity in a supplier-facing payload" -- refuses that exact string, and refuses it on SHAPE as
  -- well as on a row match, so it works with public.customers at zero. The send path simply never
  -- asked it. That is this estate's "a finished capability with no entry point" one step worse: the
  -- guard exists, it is correct, and nothing calls it.
  --
  -- WHOSE STEPS IT GOVERNS IS NOT DECIDED HERE. fn_phase_d_rule_applies is the estate's own answer
  -- to whether a rule governs a step -- workflow scope, step-level applicability and the producing
  -- step position all live in it -- and this asks that, so a step BR-011 does not govern is
  -- unaffected and the scope moves with the register rather than with this routine.
  select a.applies into v_br011 from public.fn_phase_d_rule_applies('BR-011', v_step) a;
  if coalesce(v_br011, false) then
    select r.ok, r.reason into v_br011_ok, v_br011_why
      from public.fn_phase_d_rule_check('BR-011',
             jsonb_build_object('supplier_payload', v_payload::text)) r;
    if not coalesce(v_br011_ok, false) then
      raise exception 'fn_phase_d_external_deliver: % may not be delivered — %. (br011_identity_before_reveal)',
        v_step, coalesce(v_br011_why, 'BR-011 refused the approved payload')
        using errcode = '23514';
    end if;
  end if;

  v_sha := encode(sha256(convert_to(v_payload::text,'UTF8')),'hex');

  -- FIELD 12. A cancelled intent may not be delivered afterwards.
  select * into v_prior from public.phase_d_external_attempt
   where idempotency_key = v_idem and cancelled_at is not null
   order by attempt_no desc limit 1;
  if found and v_case <> 'cancellation' then
    raise exception 'fn_phase_d_external_deliver: % was cancelled at % and may not be delivered (pd_external_cancelled)',
      v_idem, v_prior.cancelled_at using errcode = '23514';
  end if;

  -- FIELD 9 + duplicate replay. The FIRST delivered attempt owns the result id.
  select * into v_prior from public.phase_d_external_attempt
   where idempotency_key = v_idem and delivered
   order by attempt_no asc limit 1;
  if found then
    -- A duplicate replay adds an attempt row for the audit trail and delivers NOTHING new.
    select coalesce(max(attempt_no),0) + 1 into v_no from public.phase_d_external_attempt where idempotency_key = v_idem;
    insert into public.phase_d_external_attempt
      (effect_id, step_id, idempotency_key, attempt_no, provider_mode, approved_payload_ref,
       approved_payload_sha256, provider_request_id, provider_result_id, provider_outcome,
       provider_detail, retry_class, delivered, reconciled_at, reconciliation_state)
    values (v_effect, v_step, v_idem, v_no, 'mock', v_ref, v_sha,
            format('req_mock_%s_%s', v_idem, v_no), v_prior.provider_result_id, 'duplicate_replay',
            format('replay of attempt %s; no second delivery', v_prior.attempt_no),
            'NOT_APPLICABLE', false, now(), 'MATCHED')
    returning attempt_id into v_id;
    return jsonb_build_object(
      'ok', true, 'replay', true, 'attempt_id', v_id, 'attempt_no', v_no,
      'provider_result_id', v_prior.provider_result_id,
      'delivered_now', false, 'first_delivery_attempt_no', v_prior.attempt_no,
      'provider_mode', 'mock', 'sent', false);
  end if;

  select coalesce(max(attempt_no),0) + 1 into v_no from public.phase_d_external_attempt where idempotency_key = v_idem;
  v_reqid := format('req_mock_%s_%s', v_idem, v_no);

  -- FIELDS 8 + 10 + 11 + 14: what the adapter DOES with each provider answer.
  if v_case = 'success' then
    v_resid := format('res_mock_%s_%s', v_idem, v_no); v_retry := 'NOT_APPLICABLE';
    v_delivered := true; v_recon := 'MATCHED';
  elsif v_case = 'suppression' then
    v_retry := 'NOT_APPLICABLE'; v_recon := 'SUPPRESSED';
  elsif v_case = 'null_result' then
    -- NOT A SUCCESS. quote_compare returned {ok:false} at HTTP 200 for weeks; a provider that
    -- answers with nothing has not delivered, and calling it delivered is that defect again.
    v_retry := 'RETRYABLE'; v_recon := 'NOT_DELIVERED';
  elsif v_case = 'retryable_failure' then
    v_retry := 'RETRYABLE'; v_recon := 'NOT_DELIVERED';
    if v_no >= v_cap then
      v_dead := now();
      v_deadwhy := format('%s retryable attempt(s) reached the cap of %s', v_no, v_cap);
      v_recon := 'DEAD_LETTERED';
    end if;
  elsif v_case = 'terminal_failure' then
    v_retry := 'TERMINAL'; v_dead := now();
    v_deadwhy := 'terminal provider failure; no further attempt is permitted';
    v_recon := 'DEAD_LETTERED';
  elsif v_case = 'cancellation' then
    v_retry := 'NOT_APPLICABLE'; v_cancel := now();
    v_cancelwhy := coalesce(nullif(btrim(p_input->>'cancel_reason'),''), 'cancelled before delivery');
    v_recon := 'CANCELLED';
  elsif v_case = 'duplicate_replay' then
    raise exception 'fn_phase_d_external_deliver: duplicate_replay is not a first attempt. Deliver once, then replay the same idempotency key. (pd_external_replay_without_delivery)'
      using errcode = '22023';
  else
    raise exception 'fn_phase_d_external_deliver: % is not a declared mock case (pd_external_unknown_case)', v_case
      using errcode = '22023';
  end if;

  insert into public.phase_d_external_attempt
    (effect_id, step_id, idempotency_key, attempt_no, provider_mode, approved_payload_ref,
     approved_payload_sha256, provider_request_id, provider_result_id, provider_outcome,
     provider_detail, retry_class, dead_lettered_at, dead_letter_reason,
     cancelled_at, cancel_reason, delivered, reconciled_at, reconciliation_state,
     trace_id)
  values (v_effect, v_step, v_idem, v_no, 'mock', v_ref, v_sha, v_reqid, v_resid, v_case,
          p_input->>'provider_detail', v_retry, v_dead, v_deadwhy, v_cancel, v_cancelwhy,
          v_delivered, now(), v_recon, nullif(p_input->>'trace_id','')::bigint)
  returning attempt_id into v_id;

  return jsonb_build_object(
    'ok', v_case in ('success','suppression','cancellation'),
    'attempt_id', v_id, 'attempt_no', v_no, 'provider_mode', 'mock', 'sent', false,
    'provider_request_id', v_reqid, 'provider_result_id', v_resid,
    'provider_outcome', v_case, 'retry_class', v_retry,
    'retry_permitted', (v_retry = 'RETRYABLE' and v_dead is null),
    'dead_lettered', v_dead is not null, 'dead_letter_reason', v_deadwhy,
    'cancelled', v_cancel is not null,
    'delivered', v_delivered, 'reconciliation_state', v_recon,
    'approved_payload_sha256', v_sha);
end $function$

