-- PHASE D · D7d — THE LEXICON MATCHED NOUNS, AND ONE OF THEM WAS THE PAYMENT LADDER.
--
-- The outbound-verb detector in D7/D7b classified 29 of 257 steps as EXTERNAL_EFFECT_INTENT. Read
-- one at a time against the frozen text, several were wrong, and one was wrong in a way that
-- mattered more than the others:
--
--   W16-S04  "Apply only an allowed transaction-state transition using the provider event"
--
-- 'provider' is a NOUN there. That step is the payment-state transition — the single most important
-- domain write in this estate and the subject of BR-020 — and classifying it as an external intent
-- meant it would record a mock and write nothing to public.transactions at all. The same noun
-- problem caught 'dispatch' twice (W08-S06 a decision, W12-S06 an assignment row) and 'charge' once.
--
-- This is the negation-blind-detector shape from the same family as scoring "I cannot assume
-- quantity" as an automatic failure: a keyword list that cannot tell a verb from a noun, and cannot
-- tell "present X and RECORD it" from "present X".
--
-- MEASURED BEFORE WRITING THIS FILE, not after — which is the correction D7b and D7c both needed
-- and neither made. The tightened rule selects exactly 12 steps, each read against its own frozen
-- required_action:
--
--   W03-S07       publish approved marketing assets                     -> social publication
--   W13-S01..S07  every step of notification delivery                   -> quarantined by object
--   W15-S04       publish the comparison and notify the customer        -> customer notification
--   W16-S02       present the approved payment method                   -> provider-hosted checkout
--   W17-S07       execute the approved action, preserve provider evidence -> refund at the provider
--   W20-S06       publish the approved content revision                 -> social publication
--
-- Nothing else in the 257 crosses a provider boundary in Phase D. All 12 remain mock, and
-- provider_mode still has no 'live' value that could be set.

begin;

with candidate as (
  select s.step_id, s.workflow_id, o.object_id,
         length(replace(o.object_id, '_', ' ')) as tok_len
    from public.phase_b_workflow_step s
    join public.phase_b_business_object o
      on o.governing_workflow_id <> 'ALL'
     and s.workflow_id = any (string_to_array(o.governing_workflow_id, '/'))
),
scored as (
  select c.step_id, c.object_id, c.tok_len,
         -- 1 = the object_id appears as a phrase; 2 = every word of it appears somewhere.
         case when lower(concat_ws(' ', s.step_name, s.required_action, s.required_output))
                     ~ ('\y' || replace(c.object_id, '_', '[ _]') || '\y') then 1
              when not exists (
                select 1 from unnest(string_to_array(c.object_id,'_')) w
                 where length(w) > 2
                   and lower(concat_ws(' ', s.step_name, s.required_action, s.required_output))
                         !~ ('\y' || w || '\y')) then 2
              else null end as anchor
    from candidate c
    join public.phase_b_workflow_step s on s.step_id = c.step_id
),
matched as (
  select step_id, object_id, anchor,
         row_number() over (partition by step_id order by anchor, tok_len desc, object_id) as rn
    from scored where anchor is not null
),
counts as (select step_id, count(*) as n from candidate group by 1),
sole as (
  select c.step_id, min(c.object_id) as object_id
    from candidate c join counts n on n.step_id = c.step_id and n.n = 1
   group by 1
),
resolved as (
  select s.step_id, s.workflow_id, s.step_type,
         coalesce(m.object_id, so.object_id, w.primary_object) as object_id,
         case when m.object_id is not null and m.anchor = 1 then 'MATCHED_STEP_TEXT'
              when m.object_id is not null and m.anchor = 2 then 'MATCHED_ALL_TOKENS'
              when so.object_id is not null then 'SOLE_OBJECT_OF_WORKFLOW'
              else 'WORKFLOW_PRIMARY_OBJECT' end as object_resolution,
         coalesce(n.n, 0) as candidates
    from public.phase_b_workflow_step s
    join public.phase_b_workflow w on w.workflow_id = s.workflow_id
    left join matched m  on m.step_id = s.step_id and m.rn = 1
    left join sole    so on so.step_id = s.step_id
    left join counts  n  on n.step_id = s.step_id
),
outbound as (
  -- THE LEXICON MATCHED NOUNS. 'dispatch', 'charge' and 'provider' each appear as a NOUN in the
  -- frozen text and each produced a wrong classification:
  --   W08-S06 "Approve the exact brief and file revision set for dispatch eligibility"  — a decision
  --   W12-S06 "Create one assignment ... using a stable dispatch idempotency key"       — a domain row
  --   W16-S04 "Apply only an allowed transaction-state transition using the provider event"
  --                                                                                     — the payment
  --                             ladder, the single most important domain write in the estate, which
  --                             the first derivation turned into a mock intent writing nothing.
  -- Only outbound VERBS remain, plus two further discriminators, both textual and auditable:
  --   * an action that also names record/supersede has its effect in the RECORD, not in a send —
  --     "Present the current approved terms and record immutable acceptance evidence" (W04-S04) is a
  --     terms-acceptance write, while "Present the approved test/live payment method" (W16-S02) is a
  --     provider-hosted checkout;
  --   * closure and handoff steps never match: a closure closes, and a handoff's artefact is the
  --     kernel's handoff run. W18-S03 "Send a complete handoff" is not an email.
  select s.step_id,
         (select string_agg(t, '+' order by t) from unnest(array[
            'send','sends','deliver','delivers','publish','publishes','notify','notifies',
            'email','present']) t
           where lower(coalesce(s.required_action,'')) ~ ('\y' || t || '\y')) as tokens,
         (lower(coalesce(s.required_action,'')) ~ '\y(receive|receives|received|accept|accepts|authenticate)\y')
           as inbound_veto,
         (lower(coalesce(s.required_action,'')) ~ '\y(record|records|recorded|supersede|supersedes)\y')
           as effect_is_the_record,
         (lower(coalesce(s.required_action,'')) ~ '\yexecutes?\y'
          and lower(coalesce(s.required_action,'')) ~ '\yprovider\y') as executes_at_a_provider
    from public.phase_b_workflow_step s
   where s.step_type not in ('review','analysis','measurement','closure','handoff')
)
insert into public.phase_d_step_effect (
  step_id, workflow_id, step_type, expected_effect_type, effect_object_id, object_resolution,
  effect_relation, effect_service, effect_operation, expected_state_transition,
  completion_condition, result_reference, trace_reference, implementation_depth,
  actual_caller, effect_evidence)
select
  r.step_id, r.workflow_id, r.step_type,
  eff.effect_type,
  case when eff.effect_type in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST') then null
       else r.object_id end,
  case when eff.effect_type in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST') then 'NO_DOMAIN_OBJECT'
       else r.object_resolution end,
  case when eff.effect_type in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST') then null
       when eff.effect_type = 'EXTERNAL_EFFECT_INTENT' then 'public.phase_d_effect_ledger'
       else b.canonical_relation end,
  case when eff.effect_type = 'KERNEL_ONLY_TRANSITION'
         then 'public.fn_kernel_step_complete(jsonb)'
       else 'public.fn_phase_d_effect_produce(jsonb)' end,
  eff.operation, eff.transition, eff.completion, eff.result_ref,
  'public.phase_c_trace via run_id and step_run_id; public.phase_d_effect_ledger.effect_id',
  eff.depth,
  'public.fn_phase_d_handler_execute(jsonb)',
  eff.evidence
from resolved r
left join public.phase_d_business_object_binding b on b.object_id = r.object_id
left join outbound ob on ob.step_id = r.step_id
cross join lateral (
  select
    case
      when hb.capability_dependency <> 'NONE'                    then 'CAPABILITY_REQUEST'
      when hb.provider_dependency  <> 'NONE'                     then 'EXTERNAL_EFFECT_INTENT'
      -- THE OBJECT DECIDES, NOT THE STEP TYPE. public.notifications is read by three outbound
      -- senders. Whether the step that produces the record is intake, decision or execution makes
      -- no difference to whether writing that table can become a live send.
      when r.object_id in ('notification','notification_attempt')  then 'EXTERNAL_EFFECT_INTENT'
      when ob.executes_at_a_provider and not ob.inbound_veto     then 'EXTERNAL_EFFECT_INTENT'
      when ob.tokens is not null and not ob.inbound_veto
           and not ob.effect_is_the_record                        then 'EXTERNAL_EFFECT_INTENT'
      when r.step_type = 'measurement'                           then 'MEASUREMENT_RECORD'
      when r.step_type = 'review'                                then 'REVIEW_VERDICT'
      when r.step_type in ('closure','handoff')                  then 'KERNEL_ONLY_TRANSITION'
      when b.policy_family in ('VERSIONED','IMMUTABLE_REVISION') then 'VERSIONED_ARTIFACT'
      else 'DOMAIN_MUTATION'
    end as effect_type
  from public.phase_d_handler_binding hb where hb.step_id = r.step_id
) t0
cross join lateral (
  select
    t0.effect_type,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION'  then 'KERNEL_STEP_RUN'
      when 'CAPABILITY_REQUEST'      then 'CAPABILITY_REQUEST_RECORD'
      when 'EXTERNAL_EFFECT_INTENT'  then 'EXTERNAL_INTENT_RECORD'
      when 'MEASUREMENT_RECORD'      then 'MEASUREMENT_RECORD'
      when 'REVIEW_VERDICT'          then 'REVIEW_VERDICT_RECORD'
      when 'VERSIONED_ARTIFACT'      then 'OBJECT_VERSION_WRITE'
      else 'OBJECT_STATE_WRITE'
    end as operation,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION' then
        format('step run %s -> completed; workflow run -> %s',
               r.step_id, coalesce(s2.success_workflow_state,'(frozen successor state)'))
      when 'CAPABILITY_REQUEST' then
        'no state moves: the capability is unavailable in Phase D and the step refuses'
      when 'EXTERNAL_EFFECT_INTENT' then
        'intent recorded as mock; no provider state moves and nothing is sent'
      when 'MEASUREMENT_RECORD' then
        'no object state moves: a measurement observes, it does not mutate'
      when 'REVIEW_VERDICT' then
        format('review_record appended with the caller''s verdict; %s', coalesce(s2.required_output,''))
      else format('%s -> %s', coalesce(b.status_model,'(declared state model)'),
                  coalesce(nullif(s2.required_output,''),'(frozen required_output)'))
    end as transition,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION' then
        'fn_kernel_step_complete returned ok and the step run reached completed; for a closure step '
        || 'the run also reached a frozen terminal state'
      when 'CAPABILITY_REQUEST' then
        'the executor raised pd_capability_unavailable and no business row was written'
      when 'EXTERNAL_EFFECT_INTENT' then
        'a phase_d_effect_ledger row exists with provider_mode = mock and no provider request id'
      when 'MEASUREMENT_RECORD' then
        'a ledger row carries a numerator and a NON-ZERO denominator, both supplied by the caller'
      when 'REVIEW_VERDICT' then
        'a review_record row names a reviewer who resolves independently of the accountable owner'
      else format('a row exists in %s carrying the declared state, readable back in the same transaction',
                  coalesce(b.canonical_relation,'(bound relation)'))
    end as completion,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION' then 'phase_c_workflow_step_run.step_run_id'
      else 'phase_d_effect_ledger.effect_id + result_reference'
    end as result_ref,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION'   then 'BUSINESS_EFFECT_CONNECTED'
      when 'CAPABILITY_REQUEST'       then 'CAPABILITY_BOUNDARY_READY'
      when 'EXTERNAL_EFFECT_INTENT'   then 'EXTERNAL_ADAPTER_READY_DISABLED'
      else 'BUSINESS_EFFECT_CONNECTED'
    end as depth,
    concat_ws(' | ',
      format('step_type=%s', r.step_type),
      format('object=%s anchored by %s from %s candidate(s)',
             coalesce(r.object_id,'(none)'), r.object_resolution, r.candidates),
      case when b.policy_family is not null then format('policy_family=%s', b.policy_family) end,
      case when r.object_id in ('notification','notification_attempt') then
        'QUARANTINED: no Phase D path writes public.notifications, which three outbound senders read'
        end,
      case when ob.tokens is not null then
        format('outbound verb(s) matched in required_action: %s%s%s', ob.tokens,
               case when ob.inbound_veto then ' — VETOED, the action also names an inbound verb'
                    else '' end,
               case when ob.effect_is_the_record
                    then ' — VETOED, the action also names record/supersede so the effect is the record'
                    else '' end) end,
      case when ob.executes_at_a_provider then
        'execute+provider conjunction matched in required_action' end,
      case when hb2.capability_dependency <> 'NONE' then
        format('capability=%s', hb2.capability_dependency) end
    ) as evidence
  from public.phase_b_workflow_step s2
  join public.phase_d_handler_binding hb2 on hb2.step_id = s2.step_id
  where s2.step_id = r.step_id
) eff
on conflict (step_id) do update set
  workflow_id = excluded.workflow_id, step_type = excluded.step_type,
  expected_effect_type = excluded.expected_effect_type,
  effect_object_id = excluded.effect_object_id,
  object_resolution = excluded.object_resolution,
  effect_relation = excluded.effect_relation, effect_service = excluded.effect_service,
  effect_operation = excluded.effect_operation,
  expected_state_transition = excluded.expected_state_transition,
  completion_condition = excluded.completion_condition,
  result_reference = excluded.result_reference, trace_reference = excluded.trace_reference,
  implementation_depth = excluded.implementation_depth, actual_caller = excluded.actual_caller,
  effect_evidence = excluded.effect_evidence, derived_at = now();

update public.phase_d_handler_binding b
   set business_object_writes = case when e.effect_object_id is null then '{}'::text[]
                                     else array[e.effect_object_id] end
  from public.phase_d_step_effect e
 where e.step_id = b.step_id;

do $$
declare n int;
begin
  select count(*) into n from public.phase_d_step_effect
   where expected_effect_type = 'EXTERNAL_EFFECT_INTENT';
  if n <> 12 then
    raise exception 'phase_d_step_effect: expected 12 external-effect intents after the tightened lexicon, got %. Every one was read against its own frozen required_action before this file was written; a different number means the derivation moved and the reading no longer applies.', n;
  end if;
end $$;

commit;
