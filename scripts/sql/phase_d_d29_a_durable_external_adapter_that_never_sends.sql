-- =================================================================================================
-- Phase D — D29. Section 9: a durable external-effect adapter that never sends anything.
--
-- Before this file, 8 of the 14 contract fields were ABSENT or PARTIAL and the 12 external steps
-- were classified EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT — a classification D12 introduced precisely
-- because READY_DISABLED was claiming a contract that did not exist.
--
--   2  approved payload/version reference   ABSENT
--   7  attempt ledger                       ABSENT
--   8  mock provider result                 ABSENT
--   9  request/result ID contract           ABSENT
--   10 retry classification                 ABSENT
--   11 dead-letter behaviour                ABSENT
--   12 cancellation behaviour               PARTIAL
--   14 reconciliation                       ABSENT
--
-- NOTHING HERE CAN SEND. There is no live provider mode: provider_mode is CHECKed to 'mock' on the
-- attempt ledger, the deliver routine refuses any other value, and it makes no network call of any
-- kind — no net.http_*, no pg_net, no edge function. The D17 outbound guard sits underneath it and
-- refuses any Phase D write that leaves a request in net.http_request_queue, so a future change
-- that tried to send would be refused by a check written before it.
--
-- WHAT "DURABLE" MEANS HERE. Every attempt is a row. A caller cannot learn the outcome without the
-- row existing, so the ledger cannot drift from what happened — the failure mode D9 recorded as a
-- ledger written inside a transaction that rolls back with the rows it describes.
--
-- THE SEVEN CASES ARE THE PROVIDER'S ANSWER, NOT THE CALLER'S WISH. In mock mode the caller names
-- the case because there is no provider to ask; that is stated rather than dressed up. What the
-- adapter owns is what it DOES with each answer, and that is what the cases prove:
--
--   success               delivered, result id recorded, reconciles
--   suppression           consent/suppression refused it; no delivery, no retry, reconciles as suppressed
--   null_result           provider returned nothing; NOT treated as success — this is the
--                         quote_compare shape, {ok:false} at HTTP 200, and it is a failure here
--   retryable_failure     classified RETRYABLE, a further attempt is permitted up to the cap
--   terminal_failure      classified TERMINAL, no further attempt, dead-lettered immediately
--   duplicate_replay      the same idempotency key returns the FIRST attempt's result and adds no
--                         second delivery
--   cancellation          cancelled before delivery; a later deliver on a cancelled intent refuses
--
-- THE FOUNDER'S REVEAL CONTRACT IS ENCODED, NOT ENABLED. He stated that a reveal notifies BOTH
-- parties: an email to each and a WhatsApp to each, on their registered numbers — four messages.
-- trg_reveal_receipt today contains exactly one insert into public.notifications, to_role='customer',
-- naming no channel and no phone. Section 9 is required to be built to what he described, so
-- phase_d_external_message_contract carries the four required messages for a reveal and the adapter
-- REFUSES a reveal payload that does not carry all four. Nothing is enabled, nothing is sent, and
-- the trigger is not touched — the gap between his contract and the trigger is measured by
-- fn_phase_d_external_state() and reported rather than quietly closed.
-- =================================================================================================

begin;

-- -------------------------------------------------------------------------------------------------
-- 1. The attempt ledger. Fields 7, 8, 9, 10, 11, 12, 14 live here.
-- -------------------------------------------------------------------------------------------------
create table if not exists public.phase_d_external_attempt (
  attempt_id              bigserial primary key,
  effect_id               bigint,
  step_id                 text not null,
  idempotency_key         text not null,
  attempt_no              int  not null,
  provider_mode           text not null,
  -- field 2: what was approved to be sent, and which version of it
  approved_payload_ref    text not null,
  approved_payload_sha256 text not null,
  -- field 9: the request/result identifier contract
  provider_request_id     text not null,
  provider_result_id      text,
  -- field 8: what the mock provider answered
  provider_outcome        text not null,
  provider_detail         text,
  -- field 10: retry classification
  retry_class             text not null,
  -- field 11: dead-letter
  dead_lettered_at        timestamptz,
  dead_letter_reason      text,
  -- field 12: cancellation
  cancelled_at            timestamptz,
  cancel_reason           text,
  -- field 14: reconciliation
  reconciled_at           timestamptz,
  reconciliation_state    text,
  delivered               boolean not null default false,
  trace_id                bigint,
  created_at              timestamptz not null default now(),
  constraint phase_d_external_attempt_mock_only
    check (provider_mode = 'mock'),
  constraint phase_d_external_attempt_outcome_check
    check (provider_outcome in ('success','suppression','null_result','retryable_failure',
                                'terminal_failure','duplicate_replay','cancellation')),
  constraint phase_d_external_attempt_retry_class_check
    check (retry_class in ('RETRYABLE','TERMINAL','NOT_APPLICABLE')),
  constraint phase_d_external_attempt_reconciliation_check
    check (reconciliation_state is null
           or reconciliation_state in ('MATCHED','SUPPRESSED','NOT_DELIVERED','DEAD_LETTERED','CANCELLED')),
  -- A delivered attempt must carry the result id it was delivered under. This is the check that
  -- stops "delivered" becoming a boolean nobody can trace to anything.
  constraint phase_d_external_attempt_delivered_has_result
    check (not delivered or provider_result_id is not null),
  constraint phase_d_external_attempt_once_per_try unique (idempotency_key, attempt_no)
);

revoke all on public.phase_d_external_attempt from anon, authenticated;
revoke truncate on public.phase_d_external_attempt from service_role, authenticated, anon;

comment on table public.phase_d_external_attempt is
  'One row per external-effect delivery ATTEMPT, mock only. Fields 7-14 of the Phase D external '
  'adapter contract. provider_mode is CHECKed to mock and no routine here makes a network call.';

-- -------------------------------------------------------------------------------------------------
-- 2. The message contract. His four messages on a reveal, recorded as a requirement.
-- -------------------------------------------------------------------------------------------------
create table if not exists public.phase_d_external_message_contract (
  contract_key   text primary key,
  effect_kind    text not null,
  to_party       text not null,
  channel        text not null,
  required       boolean not null default true,
  source         text not null,
  note           text not null
);

revoke all on public.phase_d_external_message_contract from anon, authenticated;

delete from public.phase_d_external_message_contract;
insert into public.phase_d_external_message_contract
  (contract_key, effect_kind, to_party, channel, required, source, note) values
 ('reveal.customer.email',    'reveal', 'customer', 'email',    true,
  'founder, stated directly: a reveal notifies BOTH parties, an email to each and a WhatsApp to each on their registered numbers',
  'trg_reveal_receipt sends this one today and only this one'),
 ('reveal.supplier.email',    'reveal', 'supplier', 'email',    true,
  'founder, stated directly', 'not sent today; trg_reveal_receipt inserts one row with to_role=customer'),
 ('reveal.customer.whatsapp', 'reveal', 'customer', 'whatsapp', true,
  'founder, stated directly', 'not sent today; the trigger names no channel and no phone'),
 ('reveal.supplier.whatsapp', 'reveal', 'supplier', 'whatsapp', true,
  'founder, stated directly', 'not sent today; the trigger names no channel and no phone');

-- -------------------------------------------------------------------------------------------------
-- 3. The adapter. It records, classifies, reconciles — and cannot send.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_phase_d_external_deliver(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
  if coalesce(nullif(btrim(current_setting('app.phase_d_test_context', true)),''),'') <> 'on' then
    raise exception 'fn_phase_d_external_deliver: app.phase_d_test_context is not on (pd_external_no_test_context)'
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
end $fn$;

revoke all on function public.fn_phase_d_external_deliver(jsonb) from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- 4. The runner: seven cases for every one of the 12 external steps.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_phase_d_run_external_cases()
returns table(step_id text, mock_case text, passed boolean, detail text)
language plpgsql
set search_path to 'public', 'pg_temp'
as $run$
declare
  st record; c text; v jsonb; v_idem text; v_pass boolean; v_detail text;
  v_pay jsonb;
  CASES text[] := array['success','suppression','null_result','retryable_failure',
                        'terminal_failure','duplicate_replay','cancellation'];
begin
  if coalesce(nullif(btrim(current_setting('app.phase_d_test_context', true)),''),'') <> 'on' then
    raise exception 'fn_phase_d_run_external_cases: app.phase_d_test_context is not on'
      using errcode = '23514';
  end if;

  for st in select e.step_id as sid from public.phase_d_step_effect e
             where e.expected_effect_type = 'EXTERNAL_EFFECT_INTENT' order by e.step_id
  loop
    foreach c in array CASES loop
      v_idem := format('zz-ext-%s-%s', st.sid, c);
      v_pay  := jsonb_build_object('subject', 'ZZ DEMO — ' || st.sid, 'body', 'ZZ DEMO — mock only');
      v_pass := false; v_detail := '';
      begin
        if c = 'duplicate_replay' then
          v := public.fn_phase_d_external_deliver(jsonb_build_object(
                 'step_id', st.sid, 'idempotency_key', v_idem, 'mock_case', 'success',
                 'approved_payload_ref', 'zz-approved-v1', 'approved_payload', v_pay));
          v := public.fn_phase_d_external_deliver(jsonb_build_object(
                 'step_id', st.sid, 'idempotency_key', v_idem, 'mock_case', 'success',
                 'approved_payload_ref', 'zz-approved-v1', 'approved_payload', v_pay));
          v_pass := coalesce((v->>'replay')::boolean,false)
                    and coalesce((v->>'delivered_now')::boolean,true) = false
                    and (select count(*) from public.phase_d_external_attempt
                          where idempotency_key = v_idem and delivered) = 1;
          v_detail := format('replay=%s deliveries=%s', v->>'replay',
                        (select count(*) from public.phase_d_external_attempt
                          where idempotency_key = v_idem and delivered));
        elsif c = 'cancellation' then
          v := public.fn_phase_d_external_deliver(jsonb_build_object(
                 'step_id', st.sid, 'idempotency_key', v_idem, 'mock_case', 'cancellation',
                 'approved_payload_ref', 'zz-approved-v1', 'approved_payload', v_pay));
          -- a later delivery on a cancelled intent must be REFUSED
          begin
            perform public.fn_phase_d_external_deliver(jsonb_build_object(
              'step_id', st.sid, 'idempotency_key', v_idem, 'mock_case', 'success',
              'approved_payload_ref', 'zz-approved-v1', 'approved_payload', v_pay));
            v_detail := 'a cancelled intent was delivered afterwards';
          exception when others then
            v_pass := position('pd_external_cancelled' in SQLERRM) > 0;
            v_detail := 'later delivery refused: ' || left(SQLERRM, 60);
          end;
        else
          v := public.fn_phase_d_external_deliver(jsonb_build_object(
                 'step_id', st.sid, 'idempotency_key', v_idem, 'mock_case', c,
                 'approved_payload_ref', 'zz-approved-v1', 'approved_payload', v_pay));
          v_pass := case c
            when 'success'           then coalesce((v->>'delivered')::boolean,false)
                                          and (v->>'provider_result_id') is not null
                                          and (v->>'reconciliation_state') = 'MATCHED'
            when 'suppression'       then coalesce((v->>'delivered')::boolean,true) = false
                                          and (v->>'reconciliation_state') = 'SUPPRESSED'
            when 'null_result'       then coalesce((v->>'delivered')::boolean,true) = false
                                          and (v->>'reconciliation_state') = 'NOT_DELIVERED'
            when 'retryable_failure' then (v->>'retry_class') = 'RETRYABLE'
                                          and coalesce((v->>'delivered')::boolean,true) = false
            when 'terminal_failure'  then (v->>'retry_class') = 'TERMINAL'
                                          and coalesce((v->>'dead_lettered')::boolean,false)
            else false end;
          v_detail := format('outcome=%s retry=%s delivered=%s recon=%s',
                             v->>'provider_outcome', v->>'retry_class', v->>'delivered',
                             v->>'reconciliation_state');
        end if;
      exception when others then
        v_pass := false; v_detail := 'raised: ' || left(SQLERRM, 90);
      end;
      step_id := st.sid; mock_case := c; passed := v_pass; detail := v_detail;
      return next;
    end loop;
  end loop;
end $run$;

revoke all on function public.fn_phase_d_run_external_cases() from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- 5. The 14 fields, recomputed FROM THE MECHANISM. No state is typed.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_phase_d_external_field_state()
returns table(field_no int, field_name text, state text, evidence text)
language sql stable
set search_path to 'public', 'pg_temp'
as $f$
with src as (
  select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_phase_d_external_deliver'
),
col as (
  select a.attname from pg_attribute a
   where a.attrelid = to_regclass('public.phase_d_external_attempt') and a.attnum > 0 and not a.attisdropped
)
select 1, 'durable effect-intent record',
       case when to_regclass('public.phase_d_effect_ledger') is not null then 'PRESENT' else 'ABSENT' end,
       'phase_d_effect_ledger carries one row per (step_run_id, effect_type)'
union all select 2, 'approved payload/version reference',
       case when exists (select 1 from src where prosrc like '%pd_external_payload_not_approved%')
             and exists (select 1 from col where attname = 'approved_payload_ref')
             and exists (select 1 from col where attname = 'approved_payload_sha256')
            then 'PRESENT' else 'ABSENT' end,
       'the adapter REFUSES an intent with no approved payload, and records its ref and sha256'
union all select 3, 'recipient/target',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                          where n.nspname='public' and p.proname='fn_phase_d_effect_produce'
                            and p.prosrc like '%pd_effect_intent_incomplete%') then 'PRESENT' else 'ABSENT' end,
       'fn_phase_d_effect_produce raises pd_effect_intent_incomplete when the payload names no recipient'
union all select 4, 'consent or suppression result',
       case when exists (select 1 from src where prosrc like '%SUPPRESSED%') then 'PRESENT' else 'ABSENT' end,
       'a suppression case records reconciliation_state=SUPPRESSED and delivers nothing'
union all select 5, 'provider mode',
       case when exists (select 1 from pg_constraint c
                          where c.conrelid = to_regclass('public.phase_d_external_attempt')
                            and c.conname = 'phase_d_external_attempt_mock_only') then 'PRESENT' else 'ABSENT' end,
       'provider_mode is CHECKed to mock on the ledger and the adapter refuses any other value'
union all select 6, 'idempotency key',
       case when exists (select 1 from pg_constraint c
                          where c.conrelid = to_regclass('public.phase_d_external_attempt')
                            and c.conname = 'phase_d_external_attempt_once_per_try') then 'PRESENT' else 'ABSENT' end,
       'UNIQUE (idempotency_key, attempt_no); the first delivered attempt owns the result id'
union all select 7, 'attempt ledger',
       case when to_regclass('public.phase_d_external_attempt') is not null then 'PRESENT' else 'ABSENT' end,
       'public.phase_d_external_attempt: one row per attempt, with attempt_no'
union all select 8, 'mock provider result',
       case when exists (select 1 from col where attname = 'provider_outcome')
             and exists (select 1 from pg_constraint c
                          where c.conrelid = to_regclass('public.phase_d_external_attempt')
                            and c.conname = 'phase_d_external_attempt_outcome_check')
            then 'PRESENT' else 'ABSENT' end,
       'provider_outcome is CHECKed to the seven declared cases'
union all select 9, 'request/result ID contract',
       case when exists (select 1 from col where attname = 'provider_request_id')
             and exists (select 1 from col where attname = 'provider_result_id')
             and exists (select 1 from pg_constraint c
                          where c.conrelid = to_regclass('public.phase_d_external_attempt')
                            and c.conname = 'phase_d_external_attempt_delivered_has_result')
            then 'PRESENT' else 'ABSENT' end,
       'every attempt carries a request id; a DELIVERED attempt must carry a result id, by CHECK'
union all select 10, 'retry classification',
       case when exists (select 1 from pg_constraint c
                          where c.conrelid = to_regclass('public.phase_d_external_attempt')
                            and c.conname = 'phase_d_external_attempt_retry_class_check')
            then 'PRESENT' else 'ABSENT' end,
       'retry_class is RETRYABLE / TERMINAL / NOT_APPLICABLE, by CHECK; a null result is RETRYABLE and never a success'
union all select 11, 'dead-letter behaviour',
       case when exists (select 1 from col where attname = 'dead_lettered_at')
             and exists (select 1 from src where prosrc like '%reached the cap of%') then 'PRESENT' else 'ABSENT' end,
       'a terminal failure dead-letters immediately; a retryable one dead-letters at the attempt cap'
union all select 12, 'cancellation behaviour',
       case when exists (select 1 from col where attname = 'cancelled_at')
             and exists (select 1 from src where prosrc like '%pd_external_cancelled%') then 'PRESENT' else 'ABSENT' end,
       'a cancelled intent is recorded and a later delivery on it is REFUSED with pd_external_cancelled'
union all select 13, 'trace',
       case when exists (select 1 from col where attname = 'trace_id') then 'PRESENT' else 'ABSENT' end,
       'trace_id is carried on the attempt and on phase_d_effect_ledger'
union all select 14, 'reconciliation',
       case when exists (select 1 from pg_constraint c
                          where c.conrelid = to_regclass('public.phase_d_external_attempt')
                            and c.conname = 'phase_d_external_attempt_reconciliation_check')
            then 'PRESENT' else 'ABSENT' end,
       'every attempt reconciles to MATCHED / SUPPRESSED / NOT_DELIVERED / DEAD_LETTERED / CANCELLED, by CHECK'
$f$;

revoke all on function public.fn_phase_d_external_field_state() from public, anon, authenticated;

-- The stored table is now a projection of the mechanism rather than a hand-maintained opinion.
delete from public.phase_d_external_adapter_field;
insert into public.phase_d_external_adapter_field (field_no, field_name, state, evidence)
select field_no, field_name, state, evidence from public.fn_phase_d_external_field_state();

-- -------------------------------------------------------------------------------------------------
-- 6. The board.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_phase_d_external_state()
returns table(check_name text, expected text, actual text, state text, detail text)
language sql stable
set search_path to 'public', 'pg_temp'
as $b$
select 'all_fourteen_contract_fields_present',
       '14',
       (select count(*)::text from public.fn_phase_d_external_field_state() where state = 'PRESENT'),
       case when (select count(*) from public.fn_phase_d_external_field_state() where state <> 'PRESENT') = 0
            then 'GREEN' else 'RED' end,
       coalesce((select string_agg(field_no || ' ' || field_name, ', ' order by field_no)
                   from public.fn_phase_d_external_field_state() where state <> 'PRESENT'),
                'every field is backed by a constraint or a refusal in the adapter')
union all
select 'the_stored_field_table_matches_the_mechanism',
       '0',
       (select count(*)::text from public.fn_phase_d_external_field_state() m
          join public.phase_d_external_adapter_field t on t.field_no = m.field_no
         where t.state is distinct from m.state),
       case when exists (select 1 from public.fn_phase_d_external_field_state() m
                           join public.phase_d_external_adapter_field t on t.field_no = m.field_no
                          where t.state is distinct from m.state) then 'RED' else 'GREEN' end,
       'the table is a projection of the live mechanism; a hand-edited state is the defect this replaces'
union all
select 'the_adapter_cannot_send',
       '0',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname in ('fn_phase_d_external_deliver','fn_phase_d_run_external_cases')
           and p.prosrc ~* 'net\.http_|pg_net|functions/v1/'),
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                          where n.nspname='public' and p.proname in ('fn_phase_d_external_deliver','fn_phase_d_run_external_cases')
                            and p.prosrc ~* 'net\.http_|pg_net|functions/v1/') then 'RED' else 'GREEN' end,
       'no routine in this adapter references a network call of any kind'
union all
select 'the_founder_reveal_contract_is_four_messages',
       '4',
       (select count(*)::text from public.phase_d_external_message_contract where effect_kind='reveal' and required),
       case when (select count(*) from public.phase_d_external_message_contract where effect_kind='reveal' and required) = 4
            then 'GREEN' else 'RED' end,
       'an email and a WhatsApp to BOTH parties, as he stated; the adapter refuses a reveal payload missing any of them'
union all
-- DISCLOSED. This is the gap between his contract and what the product does today. Phase D measures
-- it and does not close it: trg_reveal_receipt is live product behaviour and the senders are held.
select 'reveal_messages_the_live_trigger_actually_sends',
       'disclosed',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname = 'trg_reveal_receipt'
           and p.prosrc ilike '%insert into public.notifications%'),
       'DISCLOSED',
       'trg_reveal_receipt contains ONE insert into public.notifications, to_role=customer, naming no '
       || 'channel and no phone. His contract is four messages to two parties. Phase D records the '
       || 'contract and refuses a non-conforming payload; closing the gap in the trigger is a product '
       || 'change under the automation hold, not a Phase D increment.'
$b$;

revoke all on function public.fn_phase_d_external_state() from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- 7. DEPLOY-TIME CONTROLS.
-- -------------------------------------------------------------------------------------------------
do $ctl$
declare
  v_total int; v_pass int; v_fail text; v_red int; v_net int; v_max bigint; v_absent text;
begin
  perform set_config('app.phase_d_test_context','on', true);

  select coalesce(max(id),0) into v_max from net.http_request_queue;

  begin
    select count(*), count(*) filter (where passed) into v_total, v_pass
      from public.fn_phase_d_run_external_cases();
    select string_agg(step_id || '/' || mock_case || ': ' || detail, ' | ')
      into v_fail from public.fn_phase_d_run_external_cases() where not passed;
    raise exception 'PHASE_D_D29_CTL_ROLLBACK';
  exception when others then
    if SQLERRM <> 'PHASE_D_D29_CTL_ROLLBACK' then
      raise exception 'D29 control: the case runner failed with: %', SQLERRM;
    end if;
  end;

  -- 12 external steps x 7 cases. The denominator is derived, never typed.
  if v_total <> (select count(*) * 7 from public.phase_d_step_effect
                  where expected_effect_type = 'EXTERNAL_EFFECT_INTENT') then
    raise exception 'D29 control: the runner produced % case(s) and the derived denominator is %',
      v_total, (select count(*) * 7 from public.phase_d_step_effect
                 where expected_effect_type = 'EXTERNAL_EFFECT_INTENT');
  end if;
  if v_pass <> v_total then
    raise exception 'D29 control: % of % cases passed. Failures: %', v_pass, v_total, coalesce(v_fail,'(none captured)');
  end if;

  select count(*) into v_net from net.http_request_queue where id > v_max;
  if v_net <> 0 then
    raise exception 'D29 control: the external case run enqueued % outbound request(s). This adapter must never send.', v_net;
  end if;

  select string_agg(field_no || ' ' || field_name, ', ' order by field_no) into v_absent
    from public.fn_phase_d_external_field_state() where state <> 'PRESENT';
  if v_absent is not null then
    raise exception 'D29 control: contract field(s) still not present: %', v_absent;
  end if;

  select count(*) into v_red from public.fn_phase_d_external_state() where state = 'RED';
  if v_red > 0 then
    raise exception 'D29 control: fn_phase_d_external_state() has % red check(s).', v_red;
  end if;

  raise notice 'D29: %/% external cases pass, 14/14 contract fields present, 0 outbound.', v_pass, v_total;
end $ctl$;

commit;
