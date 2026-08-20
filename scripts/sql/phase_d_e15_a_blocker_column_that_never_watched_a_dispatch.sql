-- E15 — a blocker column that never watched a dispatch
--
-- `fn_phase_d_effect_reachability()` returns one row per step and a `blocker` column saying why the
-- step has produced no effect. Its arithmetic was sound — 21+70+74+78+14 = 257, one row per step —
-- and its causation was invented. Measured 2026-08-20 on the live body:
--
--   * 144 of 257 rows stated "the only driver, fn_phase_d_drive_workflow". D36 wired the dispatch
--     into both kernel openers, so that has been false since 20 August. I drove one.
--   * 222 of 257 named the fixture rule.
--   * 0 of 257 named a blocker anyone had observed, because the function never looked at a dispatch.
--     Every reason was derived from what the effect WOULD write, which is a fact about the contract,
--     not a fact about what happened.
--
-- The repair is to make the column read the attempt. `public.phase_d_dispatch` is where a real
-- attempt is recorded; when a step has one, its own last outcome, refusal code and reason ARE the
-- blocker and nothing needs deriving. When it has none, the function says exactly that — "no
-- dispatch has been committed for this step" — and then, separately and labelled as such, reports
-- the contract-level precondition that would have to be met. A precondition is not a cause, and the
-- two are no longer printed in the same voice.
--
-- `blocker_source` is the new column that makes the difference legible: `OBSERVED_DISPATCH` or
-- `CONTRACT_PRECONDITION_NOT_YET_OBSERVED`. A reader can no longer take the second for the first.
--
-- What a driven probe actually finds, for the record (aborted transaction, all 30 workflows through
-- fn_kernel_workflow_start / step_complete / handoff_accept / review_decide, execution_context
-- 'production', residue 0, ai_cost_log delta 0, active cron delta 0):
--   254 dispatch rows, 2 EXECUTED — W01-S05 and W21-S08 — and 2 rows in phase_d_effect_ledger.
-- `scripts/checks/phase_d_dispatch_reaches_executed.test.mjs` is that probe, and it runs in the
-- default suite, so the claim is re-runnable rather than recorded here as a number.
--
-- The preconditions the drive confirmed, in the order the dispatch meets them:
--   1. capability_dependency or provider_dependency other than NONE -> the boundary raises for any
--      execution_context but 'test', and the refusal is the contract. 21 steps.
--   2. an effect whose branch in fn_phase_d_effect_produce demands business_key and owner_ref that
--      only a caller can supply. That refusal is deliberate: a record written under an owner the
--      routine chose would be the auto-vivified account defect in a new place.
--   3. an applicable hard rule or gate whose evidence is a fact about a business subject that does
--      not exist while the business tables are at zero.
-- Applicability is asked of `fn_phase_d_rule_applies`, not assumed from `rule_ids`. Bound is not
-- applicable, and counting bindings as blockers is how both prior audits and I over-stated the
-- blast radius of BR-043. Stated precisely, because the loose version of this sentence is the same
-- mistake in the other direction: BR-043 refused nothing in ANY of the drives run on 2026-08-20 —
-- it appears in none of the 254 dispatch refusals — because its predicate returns NOT_APPLICABLE
-- when the call names no policy exception, and no call did. It is NOT incapable of refusing.
-- Driven directly: no exception named -> NOT_APPLICABLE; `policy_exception` named with no
-- `exception_authority_ref` -> ENFORCED_FAIL; both named -> ENFORCED_PASS. It is one of the 40 of 54
-- that fn_phase_d_rule_can_refuse() counts as able to refuse, and that count is right.
--
-- CREATE OR REPLACE with a changed return signature needs the DROP first; the routine is
-- SECURITY INVOKER and the new one is created without a grant to PUBLIC by the REVOKE below.

drop function if exists public.fn_phase_d_effect_reachability();

CREATE OR REPLACE FUNCTION public.fn_phase_d_effect_reachability()
 RETURNS TABLE(step_id text, workflow_id text, expected_effect_type text, reachability text,
               blocker text, blocker_source text, writes_relation text, has_produced_an_effect boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- THE JOIN IS ON WHAT THE BRANCH WRITES, NOT ON WHAT THE ROW DECLARES. fn_phase_d_effect_produce
  -- hardcodes 'review_record' for every REVIEW_VERDICT step and writes only the ledger for
  -- EXTERNAL_EFFECT_INTENT and MEASUREMENT_RECORD, so e.effect_object_id is the wrong key for 60 of
  -- the 257 and reading it was the E5 defect.
  with resolved as (
    select e.step_id, e.workflow_id, e.expected_effect_type,
           case
             when e.expected_effect_type = 'CAPABILITY_REQUEST'
               then '(nothing — the branch raises pd_capability_unavailable)'
             when e.expected_effect_type in
                  ('KERNEL_ONLY_TRANSITION','EXTERNAL_EFFECT_INTENT','MEASUREMENT_RECORD')
               then 'public.phase_d_effect_ledger'
             else (select ob.canonical_relation
                     from public.phase_d_business_object_binding ob
                    where ob.object_id = case when e.expected_effect_type = 'REVIEW_VERDICT'
                                              then 'review_record' else e.effect_object_id end)
           end as writes_relation,
           case
             when e.expected_effect_type in
                  ('CAPABILITY_REQUEST','KERNEL_ONLY_TRANSITION','EXTERNAL_EFFECT_INTENT',
                   'MEASUREMENT_RECORD')
               then null
             else (select ob.relation_kind
                     from public.phase_d_business_object_binding ob
                    where ob.object_id = case when e.expected_effect_type = 'REVIEW_VERDICT'
                                              then 'review_record' else e.effect_object_id end)
           end as relation_kind
      from public.phase_d_step_effect e
  ),
  -- THE ATTEMPT, WHERE THERE IS ONE. Last dispatch per step, by dispatch_id. This is the only
  -- source in the function that is a record of something that happened.
  observed as (
    select distinct on (d.step_id)
           d.step_id, d.outcome, d.refusal_code, d.reason, d.unresolved_keys, d.dispatched_at
      from public.phase_d_dispatch d
     order by d.step_id, d.dispatch_id desc
  ),
  -- THE PRECONDITIONS, LABELLED AS PRECONDITIONS. Applicability is asked of fn_phase_d_rule_applies
  -- for every rule bound to the step; a rule that is bound but not applicable blocks nothing.
  pre as (
    select hb.step_id,
           (hb.capability_dependency <> 'NONE') as capability_held,
           (hb.provider_dependency   <> 'NONE') as provider_held,
           (select array_agg(rid order by rid) from unnest(hb.rule_ids) rid
             where (select a.applies from public.fn_phase_d_rule_applies(rid, hb.step_id) a)) as applicable_rules
      from public.phase_d_handler_binding hb
  )
  select r.step_id, r.workflow_id, r.expected_effect_type,
         case
           when r.expected_effect_type = 'CAPABILITY_REQUEST' then 'REFUSAL_IS_THE_DECLARED_EFFECT'
           when r.writes_relation = 'public.phase_d_effect_ledger' then 'WRITES_ONLY_THE_PHASE_D_LEDGER'
           when r.relation_kind = 'PHASE_D_OBJECT_VIEW' then 'WRITES_ONLY_THE_PHASE_D_OBJECT_STORE'
           when r.writes_relation in ('public.customers','public.inquiries','public.quotes',
                                      'public.transactions','public.notifications')
             then 'WRITES_A_ZERO_RESIDUE_TABLE'
           when r.relation_kind = 'EXISTING_TABLE' then 'WRITES_AN_EXISTING_TABLE_NOT_UNDER_THE_RULE'
           else 'UNRESOLVED'
         end,
         -- blocker
         case
           when o.step_id is not null and o.outcome = 'EXECUTED'
             then format('none — the last dispatch of this step reached EXECUTED at %s', o.dispatched_at)
           when o.step_id is not null
             then format('%s (%s): %s', o.outcome, coalesce(o.refusal_code,'(no code)'),
                         left(coalesce(o.reason,'(no reason recorded)'), 400))
           when p.capability_held or p.provider_held
             then 'PRECONDITION: the capability or provider boundary raises for any execution_context '
                  || 'other than test, and the kernel path hard-codes production. The refusal is the '
                  || 'contract, not a defect.'
           when r.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT')
             then 'PRECONDITION: fn_phase_d_effect_produce requires a caller-supplied business_key '
                  || 'and owner_ref for a step that writes ' || coalesce(r.writes_relation,'a business object')
                  || '. It refuses rather than choosing them, deliberately.'
           when coalesce(cardinality(p.applicable_rules),0) > 0
             then 'PRECONDITION: ' || cardinality(p.applicable_rules)::text
                  || ' hard rule(s) apply to this step and read facts about a business subject — '
                  || array_to_string(p.applicable_rules, ', ')
           else 'PRECONDITION: none identified at contract level; no dispatch has been committed for '
                || 'this step, so nothing here is a measurement of why.'
         end,
         -- blocker_source: the whole point of this file
         case when o.step_id is not null then 'OBSERVED_DISPATCH'
              else 'CONTRACT_PRECONDITION_NOT_YET_OBSERVED' end,
         coalesce(r.writes_relation, '(unresolved — no binding for the object this branch writes)'),
         exists (select 1 from public.phase_d_effect_ledger l where l.step_id = r.step_id)
    from resolved r
    left join observed o on o.step_id = r.step_id
    left join pre p      on p.step_id = r.step_id;
$function$;

-- A function CREATEd in public arrives EXECUTE-to-PUBLIC. ALTER DEFAULT PRIVILEGES does not prevent
-- it here, measured; the revoke in the same migration is the only mechanism that does.
revoke execute on function public.fn_phase_d_effect_reachability() from public;
revoke execute on function public.fn_phase_d_effect_reachability() from anon;
revoke execute on function public.fn_phase_d_effect_reachability() from authenticated;
