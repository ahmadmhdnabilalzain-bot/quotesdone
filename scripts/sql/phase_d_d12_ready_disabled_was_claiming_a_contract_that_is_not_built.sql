-- =================================================================================================
-- Phase D — D12. READY_DISABLED was claiming a contract that is not built.
--
-- §2 of the brief lists fourteen things an adapter must have before it may be called
-- EXTERNAL_ADAPTER_READY_DISABLED, and says plainly: *until all fields and mock tests exist, use*
-- **EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT**.
--
-- Twelve steps carry READY_DISABLED. Reconciled field by field against what actually exists:
--
--   durable effect-intent record       PRESENT   phase_d_effect_ledger row per step run
--   recipient / target                 PRESENT   refused as pd_effect_intent_incomplete without one
--   consent or suppression result      PRESENT   consent_basis is required, and suppressed is honoured
--   provider mode                      PRESENT   'mock', and provider_mode has no 'live' value to set
--   idempotency key                    PRESENT   UNIQUE (step_run_id, effect_type)
--   trace                              PRESENT   trace_id on the ledger
--   approved payload / version ref     ABSENT    no approved-version reference is required or stored
--   attempt ledger                     ABSENT    there is no per-attempt record at all
--   mock provider result               ABSENT    nothing records what the mock provider returned
--   request / result ID contract       ABSENT    no provider request id, no provider result id
--   retry classification               ABSENT    no retryable/terminal classification exists
--   dead-letter behaviour              ABSENT    no dead-letter path for an effect intent
--   cancellation behaviour             PARTIAL   fn_kernel_cancel clears queued OUTBOX rows; an
--                                                effect intent in the Phase D ledger has no
--                                                cancellation path of its own
--   reconciliation                     ABSENT    nothing reconciles an intent against a provider
--
-- **Six of fourteen present, one partial, seven absent.** So the status is wrong on its own
-- definition, and the brief's instruction is explicit. All twelve are moved to
-- EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT.
--
-- THIS MAKES A NUMBER WORSE ON PURPOSE. `EXTERNAL_ADAPTER_READY_DISABLED` reads as "the adapter is
-- built and switched off", which is a sentence about safety. What is true is "the intent is
-- recorded and nothing else is built", which is a sentence about scope. A status that overstates
-- readiness on a path that ends at a customer's inbox is the most expensive kind to leave standing.
--
-- NOTHING ABOUT BEHAVIOUR CHANGES. No effect is sent, no provider is called, no mode becomes live.
-- The twelve steps behave exactly as before; only the word describing them becomes accurate.
-- =================================================================================================

begin;

-- The vocabulary has to admit the honest value before a row can carry it.
alter table public.phase_d_step_effect
  drop constraint if exists phase_d_step_effect_depth_ck;

alter table public.phase_d_step_effect
  add constraint phase_d_step_effect_depth_ck
  check (implementation_depth in (
    'SCHEMA_ONLY', 'VALIDATION_ONLY',
    'BUSINESS_EFFECT_CONNECTED', 'CAPABILITY_BOUNDARY_READY',
    'EXTERNAL_ADAPTER_READY_DISABLED', 'EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT'));

update public.phase_d_step_effect
   set implementation_depth = 'EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT'
 where expected_effect_type = 'EXTERNAL_EFFECT_INTENT'
   and implementation_depth = 'EXTERNAL_ADAPTER_READY_DISABLED';

-- ---- the field-by-field reconciliation, as data ---------------------------------------------------

create table if not exists public.phase_d_external_adapter_field (
  field_no    int  primary key,
  field_name  text not null unique,
  state       text not null,
  evidence    text not null,
  constraint phase_d_external_adapter_field_state_ck
    check (state in ('PRESENT','PARTIAL','ABSENT'))
);

insert into public.phase_d_external_adapter_field (field_no, field_name, state, evidence) values
  (1,  'durable effect-intent record', 'PRESENT',
       'phase_d_effect_ledger carries one row per (step_run_id, effect_type)'),
  (2,  'approved payload/version reference', 'ABSENT',
       'no approved-version reference is required by fn_phase_d_effect_produce or stored on the ledger'),
  (3,  'recipient/target', 'PRESENT',
       'fn_phase_d_effect_produce raises pd_effect_intent_incomplete when the payload names no recipient'),
  (4,  'consent or suppression result', 'PRESENT',
       'consent_basis is required; a payload marked suppressed records external_intent:SUPPRESSED'),
  (5,  'provider mode', 'PRESENT',
       'provider_mode is mock and has no live value to set, so this cannot become a send by changing a parameter'),
  (6,  'idempotency key', 'PRESENT',
       'UNIQUE (step_run_id, effect_type) on phase_d_effect_ledger, read from pg_constraint by the D10 duplicate case'),
  (7,  'attempt ledger', 'ABSENT',
       'there is no per-attempt record; the ledger holds one row per effect and no attempt history'),
  (8,  'mock provider result', 'ABSENT',
       'result_reference records the intent, not what a mock provider returned'),
  (9,  'request/result ID contract', 'ABSENT',
       'no provider request id and no provider result id exist anywhere on the path'),
  (10, 'retry classification', 'ABSENT',
       'nothing classifies a failure as retryable or terminal for an effect intent'),
  (11, 'dead-letter behaviour', 'ABSENT',
       'phase_c_event_outbox has status=dead_letter for EVENTS; an effect intent has no dead-letter path'),
  (12, 'cancellation behaviour', 'PARTIAL',
       'fn_kernel_cancel clears queued outbox rows beneath a cancelled run; an effect intent in the Phase D ledger has no cancellation path of its own'),
  (13, 'trace', 'PRESENT',
       'trace_id is carried on phase_d_effect_ledger'),
  (14, 'reconciliation', 'ABSENT',
       'nothing reconciles a recorded intent against any provider-side record')
on conflict (field_no) do update
  set field_name = excluded.field_name, state = excluded.state, evidence = excluded.evidence;

comment on table public.phase_d_external_adapter_field is
  'Phase D §2: the fourteen fields an external adapter must carry before it may be called READY_DISABLED, each with its measured state. 6 PRESENT, 1 PARTIAL, 7 ABSENT — which is why the twelve steps read CONTRACT_NOT_BUILT.';

-- ---- the board ------------------------------------------------------------------------------------

create or replace function public.fn_phase_d_adapter_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  select 'external_effect_steps', '12',
         (select count(*)::text from public.phase_d_step_effect
           where expected_effect_type = 'EXTERNAL_EFFECT_INTENT'),
         (select count(*) from public.phase_d_step_effect
           where expected_effect_type = 'EXTERNAL_EFFECT_INTENT') = 12
  union all
  -- THE CHECK THIS FILE EXISTS FOR. No step may claim a built adapter while any of the fourteen
  -- fields is absent. It is not a ratchet: the moment all fourteen are PRESENT this permits
  -- READY_DISABLED again, and until then it forbids it.
  select 'steps_claiming_a_built_adapter_while_a_field_is_absent', '0',
         (select count(*)::text from public.phase_d_step_effect
           where implementation_depth = 'EXTERNAL_ADAPTER_READY_DISABLED'
             and exists (select 1 from public.phase_d_external_adapter_field
                          where state <> 'PRESENT')),
         not exists (select 1 from public.phase_d_step_effect
                      where implementation_depth = 'EXTERNAL_ADAPTER_READY_DISABLED'
                        and exists (select 1 from public.phase_d_external_adapter_field
                                     where state <> 'PRESENT'))
  union all
  select 'adapter_contract_fields_reconciled', '14',
         (select count(*)::text from public.phase_d_external_adapter_field),
         (select count(*) from public.phase_d_external_adapter_field) = 14
  union all
  select 'adapter_contract_fields_present', 'informational',
         (select count(*)::text from public.phase_d_external_adapter_field where state='PRESENT'), true
  union all
  select 'adapter_contract_fields_absent_or_partial', 'informational — D9 of the brief is not started',
         (select count(*)::text from public.phase_d_external_adapter_field where state<>'PRESENT'), true
  union all
  -- provider_mode must have no way to become a send.
  select 'effect_ledger_rows_in_a_live_provider_mode', '0',
         (select count(*)::text from public.phase_d_effect_ledger where provider_mode = 'live'),
         not exists (select 1 from public.phase_d_effect_ledger where provider_mode = 'live');
$fn$;

revoke all on function public.fn_phase_d_adapter_state() from public;
grant execute on function public.fn_phase_d_adapter_state() to service_role;
revoke all on public.phase_d_external_adapter_field from anon, authenticated;
grant select on public.phase_d_external_adapter_field to service_role;
alter table public.phase_d_external_adapter_field enable row level security;

do $ctl$
declare v_ready int; v_notbuilt int; v_absent int;
begin
  select count(*) into v_ready from public.phase_d_step_effect
   where implementation_depth = 'EXTERNAL_ADAPTER_READY_DISABLED';
  select count(*) into v_notbuilt from public.phase_d_step_effect
   where implementation_depth = 'EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT';
  select count(*) into v_absent from public.phase_d_external_adapter_field where state <> 'PRESENT';

  if v_ready <> 0 then
    raise exception 'D12: % step(s) still claim EXTERNAL_ADAPTER_READY_DISABLED while % of the 14 contract fields are not PRESENT',
      v_ready, v_absent;
  end if;
  if v_notbuilt <> 12 then
    raise exception 'D12: % steps read CONTRACT_NOT_BUILT; 12 external effect intents were measured', v_notbuilt;
  end if;
  if v_absent = 0 then
    raise exception 'D12: every contract field reads PRESENT, which contradicts the measurement this file records — the reconciliation is not measuring anything';
  end if;
  raise notice 'D12: 12 steps moved to EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT; % of 14 fields absent or partial.', v_absent;
end $ctl$;

commit;
