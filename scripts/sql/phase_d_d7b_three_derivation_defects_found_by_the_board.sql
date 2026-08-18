-- PHASE D · D7b — THREE DEFECTS IN D7, EVERY ONE FOUND BY ITS OWN BOARD RATHER THAN BY REVIEW.
--
-- fn_phase_d_effect_state() came back with three reds on the increment that had just shipped. All
-- three are recorded here with what the board actually printed, because a board that finds nothing
-- on the day it lands is a board nobody believes afterwards.
--
-- 1. effect_services_that_do_not_resolve = 257 of 257.
--    The check compared the contract's service name against
--    nspname||'.'||proname||'('||pg_get_function_identity_arguments(oid)||')', which yields
--    "public.fn_phase_d_effect_produce(p_input jsonb)" — the PARAMETER NAME is in it. The contract
--    names the signature by type. So a check meant to catch a contract naming a routine nobody
--    deployed instead reported that all 257 were broken, which is the same class of error as an
--    instrument reporting on the wrong subject: the number was red for a reason that had nothing to
--    do with the thing it names. oid::regprocedure renders exactly schema.name(argtypes).
--
-- 2. existing_table_effects_with_no_write_map = 6, and the six split into two DIFFERENT causes,
--    which is why the aggregate was worth breaking apart before fixing anything:
--
--      W13-S01, W13-S03  -> notification, and this is the QUARANTINE working as designed but
--                           classified wrongly. The rule that routes notification objects away from
--                           public.notifications required step_type = 'execution'; W13-S01 is intake
--                           and W13-S03 is decision, so two of the seven W13 steps fell through to
--                           DOMAIN_MUTATION and asked for a writer into the table three outbound
--                           senders read. The step type was never the right discriminator — the
--                           OBJECT is. Every step whose effect object is a notification produces an
--                           intent, recorded as mock, and nothing in Phase D writes
--                           public.notifications at all.
--
--      W16-S05           -> resolved to payment_transaction when the frozen step reads
--                           "Create invoice or receipt evidence" / "Invoice/receipt record". The
--                           object is invoice_receipt and it was already mapped. The phrase matcher
--                           builds '\yinvoice[ _]receipt\y' from the object_id, and the frozen text
--                           says "invoice OR receipt" and "Invoice/receipt" — neither matches. So a
--                           step that names its object twice in eight words was pushed onto the
--                           workflow's primary object. A second, weaker anchor is added: all of the
--                           object_id's words present anywhere in the step text, ranked BELOW the
--                           exact phrase so it only decides what the phrase could not.
--
--      W17-S02/S06/S08   -> refund_dispute_case, genuinely unmapped. public.refunds carries the
--                           founder-approval trigger, and that is left to refuse: a refund written
--                           without his decision SHOULD fail, and Phase D repairs implementation to
--                           the frozen design rather than routing around a guard.
--
-- 3. steps_with_no_effect_ever_produced = 257 is NOT a defect and is not "fixed" here. It is the
--    disclosure check: it counts steps whose effect has actually been produced at least once, it
--    starts at the full 257 and it falls only as real executions land. It is ratcheted in
--    kernel-boards.json with an owner, exactly like the check it replaces.

begin;

-- ---------------------------------------------------------------- 2a. the missing write maps
insert into public.phase_d_object_write_map
  (object_id, target_relation, operation, key_column, owner_column, column_map, quarantine_note)
values
  -- Both transaction objects live in public.transactions. TRANSACTION_RECORD family: one row per
  -- identity, so the operation moves state rather than writing a second row. No CHECK was added to
  -- fee_status here for the reason D2 gave: a live writer using an off-ladder value would then fail
  -- at runtime, and phase_d_payment_state already declares the six rungs as data.
  ('payment_transaction','public.transactions','UPSERT_STATE','id','customer_id',
    '{"id":"business_key","customer_id":"owner_ref","fee_status":"state","quote_id":"quote_id","inquiry_id":"inquiry_id","quote_amount":"quote_amount","payment_ref":"payment_ref","reveal_fee":"reveal_fee"}'::jsonb,
    'No provider is called: a transaction row records what a payment state IS, never a charge.'),
  ('reveal_transaction','public.transactions','UPSERT_STATE','id','customer_id',
    '{"id":"business_key","customer_id":"owner_ref","fee_status":"state","revealed_at":"revealed_at","reveal_fee":"reveal_fee","payment_ref":"payment_ref","supplier_id":"supplier_id"}'::jsonb,
    'Reveal remains gated by BR-020 through fn_phase_d_reveal_permitted; this map does not bypass it.'),
  -- public.refunds carries the founder-approval trigger. It is not bypassed and not disabled: a
  -- Phase D refund write with no founder decision is REFUSED by it, which is the correct behaviour
  -- and is one of the negative cases this object is tested with.
  ('refund_dispute_case','public.refunds','UPSERT_STATE','id','customer_id',
    '{"customer_id":"owner_ref","status":"state","reason_code":"reason_code","requested_by":"requested_by","reason_note":"reason_note","transaction_id":"transaction_id","amount_fils":"amount_fils"}'::jsonb,
    'Every refund needs the founder (his ruling of 17 Aug 2026, any amount). The trigger on this table enforces it and this map is subject to it.')
on conflict (object_id) do update set
  target_relation = excluded.target_relation, operation = excluded.operation,
  key_column = excluded.key_column, owner_column = excluded.owner_column,
  column_map = excluded.column_map, quarantine_note = excluded.quarantine_note;

-- The same validation D7 ran, re-run over the three new maps. A map that would fail at runtime must
-- not deploy, and that has to be true of every file that adds one, not only of the first.
do $$
declare m record; c record; v_missing text[]; v_bad text[]; v_req text[]; v_declared text[];
begin
  for m in select * from public.phase_d_object_write_map
            where object_id in ('payment_transaction','reveal_transaction','refund_dispute_case') loop
    v_bad := '{}';
    for c in select k from jsonb_object_keys(m.column_map) k loop
      if not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = split_part(m.target_relation,'.',1)
                        and ic.table_name   = split_part(m.target_relation,'.',2)
                        and ic.column_name  = c.k) then
        v_bad := v_bad || c.k;
      end if;
    end loop;
    if cardinality(v_bad) > 0 then
      raise exception 'phase_d_object_write_map: % declares column(s) % that % does not have',
        m.object_id, array_to_string(v_bad, ', '), m.target_relation;
    end if;
    select coalesce(array_agg(ic.column_name order by ic.ordinal_position), '{}') into v_req
      from information_schema.columns ic
     where ic.table_schema = split_part(m.target_relation,'.',1)
       and ic.table_name   = split_part(m.target_relation,'.',2)
       and ic.is_nullable = 'NO' and ic.column_default is null and ic.is_identity = 'NO'
       and ic.is_generated = 'NEVER';
    select coalesce(array_agg(k), '{}') into v_declared from jsonb_object_keys(m.column_map) k;
    select coalesce(array_agg(r), '{}') into v_missing
      from unnest(v_req) r where not (r = any (v_declared));
    if cardinality(v_missing) > 0 then
      raise exception 'phase_d_object_write_map: % cannot write % — required column(s) % are not in the map',
        m.object_id, m.target_relation, array_to_string(v_missing, ', ');
    end if;
  end loop;
end $$;

-- The widened resolution vocabulary lands BEFORE the rows that use it. A constraint altered
-- after the insert refuses the insert, which is what the first attempt did.
alter table public.phase_d_step_effect drop constraint if exists phase_d_step_effect_resolution_ck;
alter table public.phase_d_step_effect add constraint phase_d_step_effect_resolution_ck check (object_resolution in ('MATCHED_STEP_TEXT','MATCHED_ALL_TOKENS','SOLE_OBJECT_OF_WORKFLOW','WORKFLOW_PRIMARY_OBJECT','NO_DOMAIN_OBJECT'));

-- ---------------------------------------------------------------- 2b. re-derive the 257 contracts
-- Two changes to the derivation, both in the same statement so the 257 stay internally consistent:
--   * MATCHED_ALL_TOKENS, a weaker anchor ranked below the exact phrase;
--   * the notification rule keys on the OBJECT, not on step_type.
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
  select s.step_id,
         (select string_agg(t, '+' order by t) from unnest(array[
            'send','sends','deliver','delivers','publish','publishes','notify','notifies',
            'dispatch','transmit','charge','charges','email','present','provider']) t
           where lower(coalesce(s.required_action,'')) ~ ('\y' || t || '\y')) as tokens,
         (lower(coalesce(s.required_action,'')) ~ '\y(receive|receives|received|accept|accepts|authenticate)\y')
           as inbound_veto
    from public.phase_b_workflow_step s
   where s.step_type not in ('review','analysis','measurement')
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
      when ob.tokens is not null and not ob.inbound_veto         then 'EXTERNAL_EFFECT_INTENT'
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
        format('outbound token(s) matched in required_action: %s%s', ob.tokens,
               case when ob.inbound_veto then ' — VETOED, the action also names an inbound verb'
                    else '' end) end,
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

-- ---------------------------------------------------------------- 1. the check reads the right shape
create or replace function public.fn_phase_d_effect_state()
returns table(check_name text, expected text, actual text, ok boolean)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare n int; m int; v text;
begin
  select count(*) into m from public.phase_b_workflow_step;

  select count(*) into n from public.phase_d_step_effect;
  check_name := 'every_frozen_step_declares_an_effect';
  expected := m::text; actual := n::text; ok := (n = m); return next;

  select count(*) into n from public.phase_d_step_effect where expected_effect_type is null;
  check_name := 'steps_with_no_expected_effect_type';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_step_effect
   where expected_effect_type not in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST')
     and effect_object_id is null;
  check_name := 'domain_effects_with_no_object';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- oid::regprocedure renders schema.name(argtypes) — the shape the contract stores. The previous
  -- body compared against pg_get_function_identity_arguments, which includes the PARAMETER NAME,
  -- so every one of the 257 contracts "did not resolve" while all of them did.
  select count(*) into n from public.phase_d_step_effect e
   where not exists (
     select 1 from pg_proc p join pg_namespace nn on nn.oid = p.pronamespace
      where nn.nspname = 'public' and p.oid::regprocedure::text = e.effect_service);
  check_name := 'effect_services_that_do_not_resolve';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_step_effect e
    join public.phase_d_business_object_binding ob on ob.object_id = e.effect_object_id
   where e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT')
     and ob.relation_kind = 'EXISTING_TABLE'
     and not exists (select 1 from public.phase_d_object_write_map w where w.object_id = ob.object_id);
  check_name := 'existing_table_effects_with_no_write_map';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n
    from public.phase_d_object_write_map w
    cross join lateral jsonb_object_keys(w.column_map) k
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema = split_part(w.target_relation,'.',1)
                        and c.table_name   = split_part(w.target_relation,'.',2)
                        and c.column_name  = k);
  check_name := 'write_map_columns_absent_from_the_target';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_object_write_map w
    join public.phase_d_business_object_binding ob on ob.object_id = w.object_id
   where ob.governing_workflow_id = 'ALL' and ob.canonical_relation like 'public.phase_c_%';
  check_name := 'kernel_owned_objects_with_a_phase_d_writer';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- THE QUARANTINE, AS A CHECK RATHER THAN AS A COMMENT. If a later increment maps a notification
  -- object onto public.notifications, this goes red before an outbound sender ever sees the row.
  select count(*) into n from public.phase_d_object_write_map
   where target_relation = 'public.notifications';
  check_name := 'phase_d_write_maps_into_the_outbound_notification_table';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_step_effect
   where effect_object_id in ('notification','notification_attempt')
     and expected_effect_type <> 'EXTERNAL_EFFECT_INTENT';
  check_name := 'notification_effects_not_classified_as_intent';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_effect_ledger
   where provider_mode not in ('none','mock','disabled');
  check_name := 'ledger_rows_claiming_a_live_external_effect';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from (
    select step_run_id, effect_type from public.phase_d_effect_ledger
     group by 1,2 having count(*) > 1) d;
  check_name := 'duplicate_effects_for_one_step_run';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- DISCLOSURE, NOT A PASS. Counts steps whose effect has actually been produced at least once,
  -- which is a different question from whether the path exists. Reported as the gap so it FALLS,
  -- and ratcheted with an owner.
  select count(distinct step_id) into n from public.phase_d_effect_ledger;
  check_name := 'steps_with_no_effect_ever_produced';
  expected := '0'; actual := (m - n)::text; ok := (n = m); return next;

  select string_agg(x.t || '=' || x.c, ' ' order by x.t) into v
    from (select expected_effect_type t, count(*)::text c
            from public.phase_d_step_effect group by 1) x;
  check_name := 'effect_type_distribution';
  expected := 'informational'; actual := coalesce(v,'(none)'); ok := true; return next;

  select string_agg(x.t || '=' || x.c, ' ' order by x.t) into v
    from (select implementation_depth t, count(*)::text c
            from public.phase_d_step_effect group by 1) x;
  check_name := 'implementation_depth_distribution';
  expected := 'informational'; actual := coalesce(v,'(none)'); ok := true; return next;

  select string_agg(x.t || '=' || x.c, ' ' order by x.t) into v
    from (select object_resolution t, count(*)::text c
            from public.phase_d_step_effect group by 1) x;
  check_name := 'object_resolution_distribution';
  expected := 'informational'; actual := coalesce(v,'(none)'); ok := true; return next;
end $fn$;

commit;
