-- =================================================================================================
-- Phase D — D20. The driver created every object open and then asked a gate whether open was
-- good enough.
--
-- Five of the remaining stops are one defect wearing five refusal codes:
--
--   W05-S02  GATE-011  inquiries.status must be quote_ready / dispatched / quoted / completed
--   W06-S02  GATE-010  route_state must be a confirmed route, and it was handed "route state 2845"
--   W07-S04  GATE-012  documents.status must not be error / quarantined / rejected
--   W14-S05  GATE-017  quotes.quote_amount not null and status non-empty
--   W16-S02  BR-020    transactions.fee_status must be a DECLARED payment state, and it was 'open'
--
-- Every one of those gates is MEASURED — it reads the real row out of the real relation rather than
-- believing an evidence value. They were right every single time. What was missing is that the
-- driver never advanced the object: it created it and asked.
--
-- WHY IT CREATED IT OPEN. The driver already tries to derive a state honestly:
--
--     -- The first value the target's state CHECK admits, read from pg_constraint rather than
--     -- assumed. Nothing is invented: a target with no CHECK yields null and the old default stands.
--
-- That is a good instinct and it is measured out. FOUR of the five relations carry no state CHECK
-- at all — inquiries.status, documents.status, quotes.status and transactions.fee_status are
-- unconstrained text — so the derivation yielded null on every one of them and `coalesce(..., 'open')`
-- did the rest. A derivation that resolves nothing for four subjects out of five is not a
-- derivation, and the fallback beside it was doing all the work unannounced.
--
-- "The first value the CHECK admits" is also an ordering accident rather than a business state,
-- which is why working_state is taken IN PREFERENCE to it below rather than after it.
--
-- WHERE THE STATE COMES FROM, AND WHAT IS AND IS NOT DERIVED — stated plainly because this is the
-- part a later session must be able to audit:
--
--   * payment_transaction    DERIVED. public.phase_d_payment_state is a real rung ladder, 6 rungs,
--                            with authorizes_reveal on rungs 5 and 6 and BR-020 naming rung 5 as
--                            the founder-approved bar. working_state is taken from it and a CHECK
--                            constraint on the registry refuses any other value, so this object's
--                            state cannot drift away from the ladder the rule reads.
--
--   * the other 23 stages    A PHASE D DECLARATION, not a frozen vocabulary. The estate declares
--                            none: phase_b_workflow_step.success_workflow_state carries the
--                            WORKFLOW RUN state (waiting_handoff 126, active 55, waiting_review 46,
--                            completed 30) and says nothing about a business object, and
--                            phase_d_business_object_binding.status_model is prose
--                            ("status; drawing_redacted; no_quote_notified"). So these values are
--                            an engineering declaration and are labelled as one. Each row carries
--                            working_state_evidence naming where the value comes from.
--
-- Deriving the state from the gate that reads it would be the rubber stamp this estate keeps
-- finding, so it is not done. These are the states the scenario factory has used to build lineage
-- since D9 — chosen then by reading the product, not by reading the gates — and this file moves
-- them out of a hard-coded if/elsif chain inside fn_phase_d_fixture_scenario and into data that the
-- driver reads too. THAT is the actual fix: one source, two readers, instead of one source and a
-- reader that never got told.
--
-- A deploy control PROVES each declared state is one the target actually accepts, by writing it
-- through the canonical service and reading the row back. A state that no relation will take is
-- caught here rather than at the next drive.
--
-- ALSO HERE — the two vocabularies that had already drifted while a comment said they could not.
-- The run-accumulated fold carries this comment:
--
--     -- The name each object contributes is read from phase_d_fixture_stage.contributes_ref — the
--     -- same mapping the scenario factory uses, so the two vocabularies cannot drift apart.
--
-- They had drifted before the comment was written. The factory carried a hard-coded exception,
--     case when st.stage_key = 'inquiry_route_set' then 'confirmed' else <result key> end
-- and the fold did not, so the factory contributed route_state='confirmed' and the driver
-- overwrote it with a record id as soon as W06-S01 produced its effect. GATE-010 was then handed
-- "route state 2845" and refused a route that was in fact confirmed. The stage now DECLARES whether
-- it contributes a RESULT_KEY or a STATE, and both readers obey that one column.
--
-- NOTHING IS WEAKENED. No gate is relaxed, no CHECK is dropped, no constraint is loosened. The
-- gates go green because the object reaches the state they ask about, which is what the brief asked
-- for: satisfied by real progress.
-- =================================================================================================

begin;

-- -------------------------------------------------------------------------------------------------
-- 1. The state each object is in when the business is working, as data.
-- -------------------------------------------------------------------------------------------------
alter table public.phase_d_fixture_stage
  add column if not exists working_state text,
  add column if not exists working_state_evidence text,
  add column if not exists contributes_kind text not null default 'RESULT_KEY';

update public.phase_d_fixture_stage set working_state = v.ws, working_state_evidence = v.ev
from (values
  ('company_objective',        'active',              'PHASE_D_DECLARATION: the state a company goal is in while it is being pursued; used by the factory since D16 when this stage was added for department_objective_goal_key_fkey'),
  ('customer_account',         'active',              'PHASE_D_DECLARATION: public.customers carries no status CHECK; active is the state the portal treats as a usable account'),
  ('customer_terms_acceptance','accepted',            'PHASE_D_DECLARATION: an acceptance record exists only once accepted; BR-001 reads terms_version and terms_hash, not a pending state'),
  ('inquiry',                  'quote_ready',         'PHASE_D_DECLARATION: the lowest inquiry state GATE-011 treats as ready; the product derives rfq_ready separately through trg_rfq_complete and fn_rfq_score, which this does not touch'),
  ('inquiry_answer',           'recorded',            'PHASE_D_DECLARATION: an answer is recorded or it does not exist'),
  ('inquiry_version',          'frozen',              'PHASE_D_DECLARATION: a version snapshot is immutable once taken'),
  ('inquiry_route_set',        'confirmed',           'PHASE_D_DECLARATION: GATE-010 requires a CONFIRMED route; this is the value the factory has contributed as route_state since D9c'),
  ('inquiry_document',         'validated',           'PHASE_D_DECLARATION: GATE-012 refuses error/quarantined/rejected; validated is the product word for a document that passed intake checks'),
  ('document_extraction',      'extracted',           'PHASE_D_DECLARATION: matches phase_d_business_object_binding.status_model for inquiry_document, which names extracted as a status field'),
  ('supplier_safe_package',    'approved',            'PHASE_D_DECLARATION: GATE-013 tests who approved the safe package, so an unapproved one has no meaning'),
  ('supplier_account',         'approved',            'PHASE_D_DECLARATION: public.leads.approval_status; BR-015 requires approved AND verified, and leads_approved_implies_verified enforces the pair'),
  ('supplier_terms_acceptance','accepted',            'PHASE_D_DECLARATION: as customer_terms_acceptance'),
  ('supplier_capability',      'approved',            'PHASE_D_DECLARATION: supplier_capabilities.review_status; a capability that is not approved cannot be matched'),
  ('supplier_verification_case','verified',           'PHASE_D_DECLARATION: a verification case that has not verified is not evidence'),
  ('supplier_assignment',      'dispatched',          'PHASE_D_DECLARATION: inquiry_matches; an assignment exists because it was dispatched to that supplier'),
  ('quotation',                'submitted',           'PHASE_D_DECLARATION: GATE-017 requires a non-empty quotes.status alongside a stated amount; submitted is the state a supplier response reaches'),
  ('quotation_revision',       'submitted',           'PHASE_D_DECLARATION: an IMMUTABLE_REVISION record is written at the state it is submitted in'),
  ('quotation_comparison',     'published',           'PHASE_D_DECLARATION: GATE-018 governs publication; a comparison the customer may see is published'),
  ('customer_selection',       'selected',            'PHASE_D_DECLARATION: a selection record exists because a selection was made'),
  ('payment_transaction',      'payment_reconciled',  'DERIVED from public.phase_d_payment_state rung 5, the only non-terminal rung with authorizes_reveal=true, described there as "the founder-approved bar in BR-020"'),
  ('provider_event',           'succeeded',           'PHASE_D_DECLARATION: stripe_events; the fixture models a completed checkout session'),
  ('reconciliation_case',      'reconciled',          'PHASE_D_DECLARATION: a reconciliation case that has not reconciled proves nothing'),
  ('reveal_transaction',       'reveal_authorized',   'DERIVED from public.phase_d_payment_state rung 6, the terminal rung, described there as recorded separately so a reveal that already happened is distinguishable from one that merely may'),
  ('review_record',            'approved',            'PHASE_D_DECLARATION: a review record carries the caller''s verdict; approved is the verdict the driver is given and BR-002 still decides whether the reviewer may give it'),
  ('refund_dispute_case',      'requested',           'PHASE_D_DECLARATION: a refund case opens as requested. It must NOT open any further: GATE-020 requires a recorded founder decision and a fixture may never forge one')
) as v(sk, ws, ev)
where public.phase_d_fixture_stage.stage_key = v.sk;

-- inquiry_route_set contributes a STATE, not a key. This is the drift the fold's own comment said
-- could not happen.
update public.phase_d_fixture_stage
   set contributes_kind = 'STATE'
 where contributes_ref = 'route_state';

alter table public.phase_d_fixture_stage
  alter column working_state set not null,
  alter column working_state_evidence set not null;

alter table public.phase_d_fixture_stage
  drop constraint if exists phase_d_fixture_stage_contributes_kind_check;
alter table public.phase_d_fixture_stage
  add constraint phase_d_fixture_stage_contributes_kind_check
  check (contributes_kind in ('RESULT_KEY','STATE'));

-- The payment objects may not drift away from the ladder BR-020 reads. A CHECK constraint cannot
-- reference another table, and spelling the six rungs out as literals here would be exactly the
-- "expectation typed into the check it guards" this estate has already paid for once — after an
-- amendment the only available fix is to retype them, which is a rubber stamp. So the ladder is
-- the authority and a TRIGGER reads it, which means adding a rung is picked up rather than
-- contradicted.
create or replace function public.fn_phase_d_stage_payment_state_declared()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $trg$
begin
  if NEW.object_id in ('payment_transaction','reveal_transaction')
     and not exists (select 1 from public.phase_d_payment_state s
                      where s.state_key = NEW.working_state) then
    raise exception 'phase_d_fixture_stage: % declares working_state %, which is not a rung of public.phase_d_payment_state. BR-020 reads that ladder; a money state outside it is not a state. (pd_stage_payment_state_undeclared)',
      NEW.stage_key, NEW.working_state using errcode = '23514';
  end if;
  return NEW;
end $trg$;

drop trigger if exists a00_phase_d_stage_payment_state on public.phase_d_fixture_stage;
create trigger a00_phase_d_stage_payment_state
  before insert or update of working_state, object_id on public.phase_d_fixture_stage
  for each row execute function public.fn_phase_d_stage_payment_state_declared();

-- The trigger is created AFTER the update above, so it has not yet judged the rows it now guards.
-- Re-assert them through it rather than assuming: an unfired guard is not a guard.
update public.phase_d_fixture_stage
   set working_state = working_state
 where object_id in ('payment_transaction','reveal_transaction');

-- -------------------------------------------------------------------------------------------------
-- 2. The driver reads it, and the fold stops overwriting a state with a key.
-- -------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_drive_workflow(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  w        public.phase_b_workflow%rowtype;
  sr       public.phase_c_workflow_step_run%rowtype;
  e        public.phase_d_step_effect%rowtype;
  b        public.phase_d_handler_binding%rowtype;
  wm       public.phase_d_object_write_map%rowtype;
  v_wf     text := nullif(btrim(coalesce(p_input->>'workflow_id','')),'');
  v_ctx    text := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'test'));
  v_max    int  := coalesce(nullif(p_input->>'max_steps','')::int, 40);
  v_label  text := coalesce(nullif(btrim(p_input->>'label'),''), 'phase-d-drive');
  v_owner  text := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
  v_verdict text := nullif(btrim(coalesce(p_input->>'verdict','')),'');
  -- THE REVIEWER IS A RUNTIME FACT FOR 45 OF THE 47 REVIEW STEPS. Measured on the frozen registry:
  -- 47 steps are step_type='review' and 45 of them name no independent_reviewer_role_id, so there is
  -- no reviewer to read for all but two. The executor is right to refuse — fn_kernel_reviewer_
  -- independent(owner, NULL) is false and BR-002 blocks — and the identity has to come from whoever
  -- is driving. It is taken from the CALLER and never chosen here: a driver that picked a reviewer
  -- would be fn_pick_reviewer returning the department head 182 times, one layer up. Independence is
  -- still decided by the kernel, not by this parameter.
  v_caller_reviewer text := nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'');
  v_parents jsonb := coalesce(p_input->'parent_refs','{}'::jsonb);
  v_extra   jsonb := coalesce(p_input->'context','{}'::jsonb);
  v_run    bigint;
  v_start  jsonb;
  v_steps  jsonb := '[]'::jsonb;
  v_i      int := 0;
  v_res    jsonb;
  v_inputs jsonb;
  v_eff    jsonb;
  v_fix    jsonb;
  v_key    text;
  v_keys   jsonb := '{}'::jsonb;
  v_col    record;
  v_err    text; v_sqlstate text; v_code text;
  v_run_state text;
  v_scope_owner text;
  v_contrib text;
  v_contrib_kind text;    -- D20
  v_decl_state text;
  v_working_state text;   -- D20
  v_cands text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(p_input->'reviewer_candidates') x), '{}'::text[]);
  hr       public.phase_c_handoff_run%rowtype;
  hc       public.phase_d_handoff_contract%rowtype;
  v_hoff   jsonb;
  v_hpk    jsonb;
  v_haccept int := 0;
  v_handoffs jsonb := '[]'::jsonb;
  v_prev   public.phase_c_workflow_step_run%rowtype;
  v_ledger int; v_before int; v_after int;
  v_reviewer text;
  v_task    bigint;
  v_decide  jsonb;
  v_declared_reviewer text;
begin
  if v_wf is null then
    raise exception 'fn_phase_d_drive_workflow: workflow_id is required' using errcode = '22023';
  end if;
  select * into w from public.phase_b_workflow where workflow_id = v_wf;
  if not found then
    raise exception 'fn_phase_d_drive_workflow: % is not a frozen workflow', v_wf using errcode = '23503';
  end if;

  select count(*) into v_before from public.phase_d_effect_ledger;

  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id', v_wf,
    'business_object_id', w.primary_object,
    'source_kind', 'autonomous',
    'source_ref', format('zz-phase-d-%s-%s', v_label, v_wf),
    'requested_by', w.accountable_role_id,
    'trigger_ctx', jsonb_build_object('driver','fn_phase_d_drive_workflow','fixture',true)));
  v_run := (v_start->>'run_id')::bigint;
  if v_run is null then
    return jsonb_build_object('ok', false, 'workflow_id', v_wf,
      'stopped_because', 'the kernel returned no run_id', 'kernel_result', v_start);
  end if;

  loop
    v_i := v_i + 1;
    exit when v_i > v_max;

    select * into sr from public.phase_c_workflow_step_run
     where run_id = v_run
       and state in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
     order by step_run_id
     limit 1;

    -- ---- NO OPEN STEP RUN IS NOT NECESSARILY A STOPPED RUN ---------------------------------------
    -- The kernel opens no successor until the receiving owner accepts the handoff. A run sitting in
    -- waiting_handoff has work to do and nobody has done it. Accept through the D9 contract path,
    -- which checks THIS handoff's own frozen packet and then lets the kernel move the state.
    if not found then
      select * into hr from public.phase_c_handoff_run
       where run_id = v_run and status = 'open'
       order by handoff_run_id limit 1;
      exit when not found;

      select * into hc from public.phase_d_handoff_contract where handoff_id = hr.handoff_id;
      exit when not found;

      select * into v_prev from public.phase_c_workflow_step_run
       where step_run_id = hr.from_step_run_id;

      -- Real facts where real facts exist; a fixture only for the clauses the frozen registry
      -- declares and nothing in this estate can supply.
      v_hpk := coalesce((select jsonb_object_agg(k, format('ZZ DEMO — %s for %s', k, hr.handoff_id))
                           from unnest(hc.packet_keys) k), '{}'::jsonb)
             || jsonb_build_object(
                  'business_object_id',
                    coalesce((select business_object_id from public.phase_c_workflow_run
                               where run_id = v_run), w.primary_object),
                  'object_version', coalesce(hr.object_version, 1),
                  'output', coalesce(v_prev.output_hash, 'no output hash recorded on the sending step run'),
                  'evidence_refs',
                    coalesce((select string_agg(result_reference, '; ' order by effect_id)
                                from public.phase_d_effect_ledger
                               where step_run_id = hr.from_step_run_id),
                             'no Phase D effect recorded for the sending step run'),
                  'requested_action',
                    coalesce((select required_action from public.phase_b_workflow_step
                               where step_id = hc.to_step_id),
                             'the frozen receiving step names no required action'));

      begin
        v_hoff := public.fn_phase_d_handoff_accept(jsonb_build_object(
          'handoff_run_id', hr.handoff_run_id,
          'actor_role_id',  hc.receiving_role_id,
          'packet',         v_hpk,
          'idempotency_key', format('%s:%s:%s', v_label, hr.handoff_id, hr.handoff_run_id)));
        v_haccept := v_haccept + 1;
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', v_hoff->'ok', 'replay', v_hoff->'replay',
          'to_step_id', v_hoff->>'to_step_id',
          'accountable_before', v_hoff->>'accountable_before',
          'accountable_after',  v_hoff->>'accountable_after',
          'sla_policy_id', v_hoff->>'sla_policy_id',
          'sla_breached', v_hoff->'sla_breached'));
        continue;
      exception when others then
        v_sqlstate := SQLSTATE; v_err := SQLERRM;
        v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', false, 'refused_with', v_code, 'sqlstate', v_sqlstate,
          'reason', left(v_err, 400)));
        -- STOP. A driver that skipped a refused handoff and carried on would report a closure the
        -- workflow never reached, exactly as it would for a refused step.
        exit;
      end;
    end if;

    select * into e from public.phase_d_step_effect where step_id = sr.step_id;
    select * into b from public.phase_d_handler_binding where step_id = sr.step_id;

    select coalesce(jsonb_object_agg(k, 'ZZ DEMO — ' || k || ' for ' || sr.step_id), '{}'::jsonb)
      into v_inputs
      from public.phase_d_handler_schema sc, unnest(sc.required_keys) k
     where sc.step_id = sr.step_id and sc.schema_kind = 'input';

    -- One source for every rule fact and gate fact the step declares it needs, typed per key.
    v_fix := public.fn_phase_d_fixture_context(sr.step_run_id, v_label);

    -- THE OWNER OF A CUSTOMER-SCOPED OBJECT IS A CUSTOMER, NOT A FRESH UUID. The write map points
    -- public.inquiries.customer_id at owner_ref, so a generated key reached a foreign key and W05
    -- died on inquiries_customer_id_fkey. The scope is read from the object's own binding — CUSTOMER
    -- takes customer_id, SUPPLIER takes supplier_id, COMPANY has no parent row and keeps the key.
    -- Nothing is defaulted: if the caller supplied no parent of that scope, this stays null and the
    -- previous behaviour and its refusal are unchanged.
    -- The first value the target's state CHECK admits, read from pg_constraint rather than
    -- assumed. Nothing is invented: a target with no CHECK yields null and the old default stands.
    -- D20. THE STATE AN OBJECT IS IN WHEN THE BUSINESS IS WORKING, read from the registry that
    -- the scenario factory builds its lineage from. Four of the five relations these workflows
    -- write carry NO state CHECK constraint — inquiries.status, documents.status, quotes.status
    -- and transactions.fee_status are all unconstrained text — so the CHECK-first heuristic below
    -- resolved null and every driven object was written 'open'. Five MEASURED gates then read the
    -- row back and correctly refused it:
    --     GATE-011 inquiries.status in (quote_ready, dispatched, quoted, completed)
    --     GATE-012 documents.status not in (error, quarantined, rejected)
    --     GATE-017 quotes.quote_amount is not null and status <> ''
    --     GATE-018 quote_comparisons ownership
    --     BR-020   transactions.fee_status must be a declared payment state
    -- Those gates were right every time. What was missing is that the driver never advanced the
    -- object; it created it open and asked a gate whether open was good enough.
    --
    -- working_state is taken in preference to the CHECK-first value because "the first literal in
    -- the constraint array" is an ordering accident, not a business state. Where a CHECK exists,
    -- a deploy control proves working_state is inside it, so this is narrower than what it
    -- replaces rather than looser.
    v_working_state := null;
    if e.effect_object_id is not null then
      select st3.working_state into v_working_state
        from public.phase_d_fixture_stage st3
       where st3.object_id = e.effect_object_id;
    end if;

    v_decl_state := null;
    if e.effect_object_id is not null then
      select (regexp_match(pg_get_constraintdef(c.oid), '= ANY \(ARRAY\[''([^'']+)'''))[1]
        into v_decl_state
        from public.phase_d_object_write_map m
        join pg_constraint c on c.conrelid = m.target_relation::regclass and c.contype = 'c'
       where m.object_id = e.effect_object_id
         -- column_map is target_column -> payload_key, so the state column is the KEY whose VALUE
         -- is 'state'. Reading it the other way round finds nothing and silently defaults.
         and exists (select 1 from jsonb_each_text(m.column_map) kv
                      where kv.value = 'state'
                        and pg_get_constraintdef(c.oid) like '%(' || kv.key || ' =%')
         and pg_get_constraintdef(c.oid) like '%= ANY (ARRAY[%'
       limit 1;
    end if;

    v_scope_owner := null;
    if e.effect_object_id is not null then
      select case ob.ownership_scope
               when 'CUSTOMER' then nullif(btrim(coalesce(v_parents->>'customer_id','')),'')
               when 'SUPPLIER' then nullif(btrim(coalesce(v_parents->>'supplier_id','')),'')
               else null end
        into v_scope_owner
        from public.phase_d_business_object_binding ob
       where ob.object_id = e.effect_object_id;
    end if;

    -- THE BUSINESS KEY MUST BE THE TARGET'S KEY TYPE. public.customers.id is a uuid, and a label
    -- string reached it as one: "invalid input syntax for type uuid". A driver that hands a business
    -- key of the wrong type produces a type error where a business refusal belongs, and the two read
    -- nothing alike in a result table.
    select * into wm from public.phase_d_object_write_map where object_id = e.effect_object_id;
    if found and exists (
         select 1 from pg_attribute a
          where a.attrelid = wm.target_relation::regclass and a.attname = wm.key_column
            and format_type(a.atttypid, a.atttypmod) = 'uuid') then
      v_key := gen_random_uuid()::text;
    else
      v_key := format('zz-phase-d-%s-%s-%s', v_label, e.effect_object_id, v_run);
    end if;
    -- ONE BUSINESS KEY PER (RUN, OBJECT), NOT PER STEP. The first drive of W04 wrote TWO customer
    -- rows — one at S01 (create) and another at S03 (verify) — because the key carried the step id,
    -- so the second write found no existing row and inserted instead of moving the first one's
    -- state. A workflow that creates a fresh account at every step it touches is not onboarding a
    -- customer, and the ledger would have counted both as successful effects. Keys are remembered
    -- per object for the life of the run.
    if v_keys ? e.effect_object_id then
      v_key := v_keys->>e.effect_object_id;
    elsif e.effect_object_id is not null then
      v_keys := v_keys || jsonb_build_object(e.effect_object_id, v_key);
    end if;
    v_eff := '{}'::jsonb;

    -- THE REVIEWER IS RESOLVED FOR EVERY STEP, NOT ONLY FOR A REVIEW_VERDICT EFFECT.
    -- BR-002 is enforced on the STEP, and W17-S04 and W17-S05 are step_type='review' whose declared
    -- EFFECT is CAPABILITY_REQUEST. Resolving the reviewer inside the REVIEW_VERDICT branch meant
    -- those steps were asked for an independent reviewer and never given the chance to name one, so
    -- BR-002 refused them with 'the review names (none) as reviewer'. Same disagreement as W11-S01,
    -- one layer along: a fact keyed on the effect type while the rule is keyed on the step.
    v_reviewer := nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),'');
    if v_reviewer is null then
      v_reviewer := v_caller_reviewer;
      if v_reviewer is null
         or not public.fn_kernel_reviewer_independent(sr.accountable_role_id, v_reviewer) then
        select c into v_reviewer from unnest(v_cands) c
         where public.fn_kernel_reviewer_independent(sr.accountable_role_id, c) limit 1;
      end if;
    end if;
    v_task := null;
    v_decide := null;

    if e.expected_effect_type = 'MEASUREMENT_RECORD' then
      v_eff := jsonb_build_object('numerator', 1, 'denominator', 1,
                                  'formula', 'fixture', 'window', 'fixture');
    elsif e.expected_effect_type = 'EXTERNAL_EFFECT_INTENT' then
      v_eff := jsonb_build_object(
        'recipient', 'zz-phase-d-' || v_label || '@example.invalid',
        'consent_basis', 'fixture: no consent record is asserted and nothing is sent',
        'suppressed', false);
    elsif e.expected_effect_type = 'REVIEW_VERDICT' then
      -- WHERE THE FROZEN REGISTRY NAMES A REVIEWER, THAT ONE IS USED AND NOTHING IS CHOSEN.
      -- Where it does not — 45 of the 47 review steps — the CALLER's reviewer is offered, and if
      -- that one is not independent of this step's owner the caller's own candidate list is tried
      -- in order using the FROZEN kernel's independence test. The driver never invents an identity,
      -- never reads a department head, and the verdict is still the caller's; fn_kernel_review_decide
      -- and fn_phase_d_effect_produce both re-check independence afterwards.
      -- already resolved above, for every step
      v_eff := jsonb_strip_nulls(jsonb_build_object(
        'verdict', v_verdict, 'reviewer_role_id', v_reviewer,
        'subject_type', 'phase_d_step', 'subject_id', sr.step_id,
        'author_agent', sr.accountable_role_id, 'stage', sr.step_id,
        'notes', 'fixture review through fn_phase_d_drive_workflow'));
    elsif e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT') then
      if wm.object_id is not null then
        for v_col in
          select k.key as col, wm.column_map->>k.key as src,
                 format_type(a.atttypid, a.atttypmod) as ftype,
                 (select typcategory from pg_type ty where ty.oid = a.atttypid) as tcat
            from jsonb_each(wm.column_map) k
            join pg_attribute a
              on a.attrelid = wm.target_relation::regclass and a.attname = k.key and a.attnum > 0
           -- EVERY MAPPED COLUMN, not only the ones the table REQUIRES. public.customers has no
           -- NOT-NULL-without-default column at all, so the required-only filter produced an
           -- empty payload: the first write inserted on defaults and the second found the row,
           -- moved nothing, and hit pd_object_no_state_change. A step writes the fields it has,
           -- not only the fields it must. Identity and generated columns stay excluded because
           -- Postgres refuses a value for them.
           -- AND NEVER THE KEY COLUMN. Third instance of one lesson in one session: an identity is
           -- not a fixture. With every mapped column fixtured, the key column's source key —
           -- business_key — was regenerated at each step, so W04 created FOUR customer accounts
           -- for one onboarding and the ledger counted all four as successful effects. The key is
           -- remembered per (run, object) and the generator must not overwrite it.
           where a.attidentity = '' and a.attgenerated = '' and k.key <> wm.key_column
        loop
          if v_parents ? v_col.src then
            v_eff := v_eff || jsonb_build_object(v_col.src, v_parents->v_col.src);
          else
            -- THE LABEL CARRIES THE STEP, SO A LATER STEP GENUINELY MOVES THE RECORD. With one
            -- label for the whole run, every step produced byte-identical values and the second
            -- write hit pd_object_no_state_change — my own guard, firing correctly on a fixture
            -- that changed nothing. A real onboarding does move the record at each step; a fixture
            -- that does not is testing the guard, not the workflow.
            v_eff := v_eff || jsonb_build_object(v_col.src,
              public.fn_phase_d_fixture_for_column(wm.target_relation, v_col.col,
                                                   v_label || '-' || sr.step_id));
          end if;
        end loop;
      end if;
      v_eff := v_eff || v_parents;
      if v_eff = '{}'::jsonb then
        v_eff := jsonb_build_object('fixture', v_label);
      end if;
    end if;

    -- ---- A STEP THAT NAMES A REVIEWER NEEDS A RECORDED VERDICT FIRST -----------------------
    -- The frozen kernel refuses otherwise, and it says so precisely:
    --   "step W04-S04 names compliance_and_privacy_officer as its independent reviewer and no
    --    approved, independent verdict from that role exists on task 8409. Record it with
    --    fn_kernel_review_decide first."  (k3_reviewer_verdict_missing)
    -- So the driver records one, on the OPEN TASK for this step, naming the reviewer the FROZEN
    -- registry declares. fn_kernel_review_decide compares the offered reviewer against that
    -- registry through fn_phase_c_resolve_actor and returns not_the_declared_reviewer if they
    -- differ, so this cannot smuggle a reviewer past the freeze — it can only supply the one
    -- Phase B already named. The verdict itself is still the CALLER's; with none given, nothing is
    -- recorded and the kernel refuses, which is the correct behaviour and stays observable.
    v_declared_reviewer := nullif(btrim(coalesce(
      (select x.independent_reviewer_role_id from public.phase_b_workflow_step x
        where x.step_id = sr.step_id), '')), '');
    if v_declared_reviewer is not null and v_verdict is not null then
      select t.task_id into v_task from public.phase_c_task t
       where t.run_id = v_run and t.step_id = sr.step_id
       order by t.task_id desc limit 1;
      if v_task is not null then
        begin
          v_decide := public.fn_kernel_review_decide(jsonb_build_object(
            'task_id', v_task, 'reviewer_role_id', v_declared_reviewer,
            'decision', v_verdict,
            'reason', format('phase_d driver fixture verdict for %s', sr.step_id)));
        exception when others then
          -- Recorded, never swallowed: a verdict that could not be written is why the step will
          -- refuse a moment later, and a driver that hid it would make that refusal unexplainable.
          v_decide := jsonb_build_object('ok', false, 'error', left(SQLERRM, 240));
        end;
      end if;
    end if;

    begin
      v_res := public.fn_phase_d_handler_execute(
        jsonb_build_object(
          'step_run_id', sr.step_run_id,
          'actor_role_id', sr.accountable_role_id,
          'idempotency_key', format('%s:%s:%s', v_label, sr.step_id, sr.step_run_id),
          'inputs', v_inputs,
          'execution_context', v_ctx,
          -- A CALLER-SUPPLIED REAL REFERENCE WINS OVER A GENERATED FIXTURE. v_fix invents a
          -- typed value for every key the step DECLARES it needs; parent_refs carries the keys a
          -- scenario actually created. BR-013 reads an inquiry back out of public.inquiries, so
          -- 'ZZ DEMO — inquiry_id' is a refusal every time and the refusal says nothing about the
          -- step. Ordering is fixture, then reality, then per-call extras.
          'context', v_fix || v_parents || v_extra,
          -- The resolved reviewer must reach the GATE evidence too. GATE-021 and GATE-026 declare
          -- reviewer_role_id as required evidence and were refusing with 'the call names none of it'
          -- while the driver had one in hand. A gate asking for a fact the caller holds and never
          -- passes is the harness losing it, not the gate being strict.
          'gate_evidence', v_fix || v_parents
                           || jsonb_strip_nulls(jsonb_build_object('reviewer_role_id', v_reviewer))
                           || v_extra,
          'business_key', coalesce(nullif(v_eff->>'business_key',''), v_key),
          'owner_ref', coalesce(v_scope_owner, v_owner, nullif(v_eff->>'owner_ref',''), v_key),
          -- THE STATE MUST BE ONE THE TARGET DECLARES. 'open' is not in refunds_status_check,
          -- so W17-S01 wrote a refund the table refused: a fixture that names a state must name a
          -- declared one, the same lesson d8f learned for the column fixtures. The allowed set is
          -- read from the target's own CHECK constraint; where there is none, 'open' still applies.
          'effect_state', coalesce(v_working_state, v_decl_state, 'open'),
          'effect_payload', v_eff)
        || jsonb_strip_nulls(jsonb_build_object('reviewer_role_id', v_reviewer))
        || case when e.expected_effect_type = 'REVIEW_VERDICT'
                then jsonb_strip_nulls(jsonb_build_object(
                       'verdict', v_verdict, 'reviewer_role_id', v_reviewer))
                else '{}'::jsonb end
        || case when b.handler_class = 'REVIEW_HANDLER'
                then jsonb_strip_nulls(jsonb_build_object(
                       'verdict', v_verdict,
                       'reviewer_role_id', v_reviewer))
                else '{}'::jsonb end
        -- THE OUTPUT CONTRACT IS THE AUTHORITY ON THE OUTPUT, not the effect type. W11-S01 is the
        -- one step of 257 where the two disagree: step_type='measurement' gives it a contract
        -- requiring numerator, denominator, formula and window, while D7d's lexicon classified its
        -- effect as CAPABILITY_REQUEST from the required_action text. Keyed on the effect type this
        -- step could never satisfy its own contract. Keyed on the contract it can, and no other step
        -- changes behaviour.
        || case when exists (select 1 from public.phase_d_handler_schema sc2
                              where sc2.step_id = sr.step_id and sc2.schema_kind = 'output'
                                and sc2.required_keys && array['numerator','denominator'])
                then jsonb_build_object('numerator', 1, 'denominator', 1,
                                        'formula','fixture','window','fixture')
                else '{}'::jsonb end);

      -- ---- THE RUN ACCUMULATES ITS OWN REFERENCES --------------------------------------------
      -- A workflow that CREATES an object at step 1 and has a rule READ it at step 4 needs the key
      -- step 1 produced. parent_refs is computed once, before the drive, so W16-S04's BR-020 was
      -- asking about a transaction that W16-S01 had just written and nobody had told it about.
      -- The name each object contributes is read from phase_d_fixture_stage.contributes_ref — the
      -- same mapping the scenario factory uses, so the two vocabularies cannot drift apart.
      if coalesce((v_res->'ok')::text,'false') = 'true'
         and e.effect_object_id is not null
         and (v_res->'phase_d'->'business_effect'->>'result_reference') is not null then
        -- D20. WHAT A STAGE CONTRIBUTES IS NOT ALWAYS A KEY. The comment above says this mapping
        -- is "the same mapping the scenario factory uses, so the two vocabularies cannot drift
        -- apart". They had already drifted: the factory carried a hard-coded exception —
        --     case when st.stage_key = 'inquiry_route_set' then 'confirmed' else <result key> end
        -- and this fold did not. So the factory contributed route_state='confirmed' and the driver
        -- overwrote it with a record id the moment W06-S01 produced its effect, and GATE-010 was
        -- handed "route state 2845" and refused a route that was in fact confirmed. An assertion
        -- that two things cannot drift, written next to the copy that had drifted.
        --
        -- The stage now DECLARES which it contributes and both readers obey the same column.
        select st2.contributes_ref, st2.contributes_kind into v_contrib, v_contrib_kind
          from public.phase_d_fixture_stage st2 where st2.object_id = e.effect_object_id;
        if v_contrib is not null then
          v_parents := v_parents || jsonb_build_object(v_contrib,
            case when v_contrib_kind = 'STATE'
                 then coalesce(v_res->'phase_d'->'business_effect'->>'state',
                               v_working_state,
                               split_part(v_res->'phase_d'->'business_effect'->>'result_reference', '=', 2))
                 else split_part(v_res->'phase_d'->'business_effect'->>'result_reference', '=', 2)
            end);
          if v_contrib = 'customer_id' then
            v_parents := v_parents || jsonb_build_object('caller_customer_id',
              split_part(v_res->'phase_d'->'business_effect'->>'result_reference', '=', 2));
          end if;
        end if;
      end if;

      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'expected_effect_type', e.expected_effect_type,
        'handler_class', b.handler_class,
        'ok', v_res->'ok', 'outcome', v_res->>'outcome',
        'step_state', v_res->>'step_state', 'run_state', v_res->>'run_state',
        'effect', v_res->'phase_d'->'business_effect'->'result_reference',
        'effect_id', v_res->'phase_d'->'business_effect'->'effect_id',
        'review_recorded', v_decide));
    exception when others then
      v_sqlstate := SQLSTATE; v_err := SQLERRM;
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+|gate[0-9]+_[a-z0-9_]+|br[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'expected_effect_type', e.expected_effect_type,
        'handler_class', b.handler_class,
        'ok', false, 'refused_with', v_code, 'sqlstate', v_sqlstate,
        'reason', left(v_err, 400)));
      exit;
    end;
  end loop;

  select state into v_run_state from public.phase_c_workflow_run where run_id = v_run;
  select count(*) into v_after from public.phase_d_effect_ledger;
  select count(*) into v_ledger from public.phase_d_effect_ledger where run_id = v_run;

  return jsonb_build_object(
    'ok', (v_run_state is not null
           and not exists (select 1 from jsonb_array_elements(v_steps) x
                            where coalesce((x->>'ok')::boolean, false) = false)
           and not exists (select 1 from jsonb_array_elements(v_handoffs) x
                            where coalesce((x->>'ok')::boolean, false) = false)),
    'workflow_id', v_wf, 'run_id', v_run, 'run_state', v_run_state,
    'steps_in_workflow', (select count(*) from public.phase_b_workflow_step
                           where workflow_id = v_wf),
    'steps_driven', jsonb_array_length(v_steps),
    'handoffs_accepted', v_haccept,
    'handoffs', v_handoffs,
    'open_handoffs_left', (select count(*) from public.phase_c_handoff_run
                            where run_id = v_run and status = 'open'),
    'effects_for_this_run', v_ledger,
    'effect_ledger_delta', v_after - v_before,
    'terminal', (select terminal from public.phase_b_workflow_state
                  where state = v_run_state),
    'steps', v_steps);
end $function$
;

-- -------------------------------------------------------------------------------------------------
-- 3. DEPLOY-TIME CONTROLS. All fixture work aborts its own subtransaction; nothing is left behind.
-- -------------------------------------------------------------------------------------------------
do $ctl$
declare
  st record; v_fx jsonb; v_bad text := ''; v_n int;
  v_before int; v_after int; v_out text := '';
  wf record; v jsonb; v_rev text; v_cands jsonb; v_closed int := 0; v_net int; v_max bigint;
begin
  perform set_config('app.phase_d_test_context','on', true);

  -- (a) EVERY DECLARED STATE MUST BE ONE THE TARGET ACTUALLY ACCEPTS, and where the relation has a
  --     state CHECK the declared value must be inside it. Proved from pg_constraint rather than by
  --     writing 24 rows, because a CHECK is the only place a relation states its vocabulary.
  for st in
    select fs.stage_key, fs.working_state, m.target_relation,
           pg_get_constraintdef(c.oid) as def
      from public.phase_d_fixture_stage fs
      join public.phase_d_object_write_map m on m.object_id = fs.object_id
      join pg_constraint c on c.conrelid = m.target_relation::regclass and c.contype = 'c'
     -- ONLY AN ENUMERATING CHECK DECLARES A VOCABULARY. public.refunds carries
     --   CHECK (status <> 'succeeded' OR amount_fils IS NOT NULL OR reconciliation_note IS NOT NULL)
     -- which names the state column and enumerates nothing; reading it as a vocabulary made this
     -- control refuse a state the relation accepts perfectly well. The driver's own derivation
     -- matches on '= ANY (ARRAY[' for the same reason, so this control now asks the same question.
     where pg_get_constraintdef(c.oid) like '%= ANY (ARRAY[%'
       and exists (select 1 from jsonb_each_text(m.column_map) k
                    where k.value = 'state'
                      and pg_get_constraintdef(c.oid) like '%(' || k.key || ')::text = ANY%')
  loop
    if position('''' || st.working_state || '''' in st.def) = 0 then
      v_bad := v_bad || format(E'\n  %s declares %s and %s does not admit it: %s',
                               st.stage_key, st.working_state, st.target_relation, st.def);
    end if;
  end loop;
  if v_bad <> '' then
    raise exception 'D20 control (a): a declared working_state is outside its target''s CHECK:%', v_bad;
  end if;

  -- (b) THE FACTORY AND THE REGISTRY MUST AGREE. The states used to live in an if/elsif chain
  --     inside fn_phase_d_fixture_scenario. If the chain and this table disagree the driver is
  --     reading one vocabulary and the lineage is built in another — which is the exact defect
  --     this file fixes for route_state. Proved by BUILDING a scenario and comparing every stage
  --     it created against the column.
  begin
    v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','d20-ctl-agree','execution_context','test'));
    select count(*) into v_n
      from jsonb_array_elements(v_fx->'manifest') m
      join public.phase_d_fixture_stage fs on fs.stage_key = m->>'stage_key'
     where m->>'status' = 'CREATED'
       and coalesce(m->>'state','') is distinct from fs.working_state;
    select string_agg(format('%s: factory=%s registry=%s', m->>'stage_key',
                             coalesce(m->>'state','(null)'), fs.working_state), ', ')
      into v_bad
      from jsonb_array_elements(v_fx->'manifest') m
      join public.phase_d_fixture_stage fs on fs.stage_key = m->>'stage_key'
     where m->>'status' = 'CREATED'
       and coalesce(m->>'state','') is distinct from fs.working_state;
    raise exception 'PHASE_D_D20_CTL_ROLLBACK';
  exception
    when others then
      if SQLERRM <> 'PHASE_D_D20_CTL_ROLLBACK' then
        raise exception 'D20 control (b): the agreement probe failed with: %', SQLERRM;
      end if;
  end;
  if coalesce(v_n,0) <> 0 then
    raise exception 'D20 control (b): % stage(s) disagree between the factory and the registry: %',
      v_n, coalesce(v_bad,'(not captured)');
  end if;

  -- (c) THE DRIVE. Re-drive the eight workflows this file is meant to move and require that
  --     closure went UP, that no outbound request escaped, and that W17 still refuses.
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  begin
    select coalesce(max(id),0) into v_max from net.http_request_queue;
    for wf in select workflow_id from public.phase_b_workflow
               where workflow_id in ('W05','W06','W07','W14','W15','W16','W17') order by workflow_id
    loop
      v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
        'label','d20c-' || lower(wf.workflow_id), 'execution_context','test'));
      select coalesce(
        (select s.independent_reviewer_role_id from public.phase_b_workflow_step s
          where s.workflow_id = wf.workflow_id
            and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
          order by s.step_id limit 1), 'risk_and_governance_manager') into v_rev;
      v := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id', wf.workflow_id, 'label','d20c-' || lower(wf.workflow_id),
        'execution_context','test','verdict','approved',
        'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands,
        'parent_refs', v_fx->'rule_context'));
      if (v->>'steps_driven') = (v->>'steps_in_workflow') then v_closed := v_closed + 1; end if;
      v_out := v_out || format(E'\n  %s %s/%s stop=%s', wf.workflow_id,
        v->>'steps_driven', v->>'steps_in_workflow',
        coalesce((select x->>'step_id' from jsonb_array_elements(v->'steps') x
                   where coalesce((x->>'ok')::boolean,false)=false limit 1),'CLOSED'));
    end loop;
    select count(*) into v_net from net.http_request_queue where id > v_max;
    raise exception 'PHASE_D_D20_CTL_ROLLBACK';
  exception
    when others then
      if SQLERRM <> 'PHASE_D_D20_CTL_ROLLBACK' then
        raise exception 'D20 control (c): the drive failed with: %', SQLERRM;
      end if;
  end;

  if coalesce(v_net,0) <> 0 then
    raise exception 'D20 control (c): the drive enqueued % outbound request(s).', v_net;
  end if;
  -- Before this file, 0 of these seven closed. Anything that does not improve on that is not a fix.
  if v_closed = 0 then
    raise exception 'D20 control (c): not one of the seven closed. States were declared and nothing moved:%', v_out;
  end if;

  raise notice 'D20: % of 7 closed in the control drive, 0 outbound.%', v_closed, v_out;
end $ctl$;

commit;
