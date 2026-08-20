-- E32 - the deliverable driver never used the door production uses
--
-- THE FINDING, IN THE INDEPENDENT AUDITOR'S WORDS: "fn_phase_d_drive_workflow calls
-- fn_kernel_workflow_start and fn_kernel_review_decide - and then fn_phase_d_handler_execute
-- DIRECTLY. The string step_complete does not occur anywhere in its 45,340-character body."
--
-- That is exactly right, and it was worse than a missing call. fn_phase_d_handler_execute accepts
-- 'context', 'gate_evidence', 'business_key', 'owner_ref', 'effect_state' and 'effect_payload'
-- FROM ITS CALLER. The kernel dispatch accepts none of them: fn_phase_d_dispatch_step resolves
-- every one of those itself, from fn_phase_d_step_inputs and fn_phase_d_step_context, and passes
-- 'execution_context','production' as a literal. So the driver was not merely taking a different
-- route to the same place - it was reaching an entry point where a harness can hand the rules
-- whatever it likes, and it did:
--
--     v_fix := public.fn_phase_d_fixture_context(sr.step_run_id, v_label);
--     ... 'context', v_fix || v_parents || v_extra
--
-- with the routine's own comment reading "v_fix invents a typed value for every key the step
-- DECLARES it needs". The audit measured 21 of 57 declared context keys supplied only by that
-- fixture, and they were the governance ones - founder_authority_ref, artifact_sha256,
-- evidence_authority, monetary_state.
--
-- E30 AND E31 ALREADY BROKE THE FORGERY, AND THE MEASUREMENT IS THE PROOF. Re-running the
-- deliverable builder unchanged, immediately after those two files:
--
--     139 business effects -> 0.   12 of 30 deterministic closures -> 0.   30 of 30 workflows
--     now stop at their FIRST step, every one on pd_rule_refused.
--
--     W04-S01  BR-025: acceptance names version zz-terms-v1 at digest a4ce8236c105, which matches
--              0 rows in public.legal_documents whose displayed body hashes to that digest
--     W08-S01  BR-036: artifact_sha256 "zz demo - artifact_sha25" is not a SHA-256 digest
--     W16-S01  BR-043: exception (unnamed) names authority "ZZ DEMO - exception_authority_ref for
--              W16-S01", which resolves to no row in founder_command or employee_authority
--
-- Every number in that deliverable had been bought with invented evidence. Nothing about the
-- estate changed to produce that collapse; only the rules' willingness to accept a placeholder.
--
-- THIS FILE REMOVES THE ENTRY POINT RATHER THAN LEAVING IT AIMED SOMEWHERE ELSE. The driver now
-- uses the four canonical doors and nothing else - fn_kernel_workflow_start,
-- fn_kernel_review_decide, fn_kernel_step_complete, fn_phase_d_handoff_accept (which is the D9
-- contract path into fn_kernel_handoff_accept) - and it READS the dispatch rows the kernel's own
-- openers produced. It cannot supply a context, because the door does not take one. The whole
-- fixture-context apparatus, and the invented business_key, owner_ref, effect_state and
-- effect_payload that went with it, is deleted rather than disabled.
--
-- WHAT THAT CHANGES ABOUT WHAT THE DELIVERABLE MEANS, and this correction matters more than the
-- numbers. D36 wired the Phase D dispatch into fn_kernel_workflow_start and fn_kernel_open_step -
-- the two kernel OPENERS - and NOT into fn_kernel_step_complete. Verified here by reading every
-- routine whose body names fn_phase_d_dispatch_step: fn_kernel_open_step and
-- fn_kernel_workflow_start, and no other kernel routine. So the deterministic handler attempts a
-- step when the kernel OPENS it, and a refusal does not stop the workflow - it leaves the step for
-- an actor, which is what a refusal should mean.
--
-- The old deliverable therefore reported a number that was never a Phase D claim. "12 of 30
-- workflows close deterministically" measured how far a harness could push the KERNEL while
-- feeding the rules placeholders. What Phase D actually claims is narrower and checkable: of the
-- step-openings the kernel produces, how many can the deterministic handler complete unaided, and
-- for every one it cannot, the machine refusal code and the reason. Both numbers are now in the
-- row, named for what they measure.
--
-- WHAT THE DRIVER STILL SUPPLIES, STATED PLAINLY SO NOBODY HAS TO INFER IT.
-- A handoff packet carries the SENDING ROLE'S WORK PRODUCT - the frozen contracts name keys like
-- legal_position_memorandum, campaign_asset_set, root_cause_and_corrective_action_report. Those
-- are what a person hands over, not facts about this estate, and a driver standing in for that
-- person has to put something in them. Two things make that safe to do and I checked both rather
-- than assuming:
--   1. NO BUSINESS RULE READS A PACKET VALUE. fn_phase_d_step_context carries the packet KEY NAMES
--      from phase_d_handoff_contract, never the values a handoff was accepted with. Read back off
--      a live drive: context.packet = ["department_mandate_register",
--      "source_business_object_version","acceptance_evidence","unresolved_blockers",
--      "requested_next_action"] - names, with provenance "phase_d_handoff_contract for this step".
--   2. The ZZ DEMO marker stays on every such value, so fn_phase_d_fixture_residue() still matches
--      it if one ever reaches a business relation.
-- Everything derivable is derived instead: business_object_id from the run, object_version from
-- the handoff run, output from the sending step's own output_hash, evidence_refs from the effect
-- ledger rows that step actually produced, requested_action from the frozen registry.
--
-- execution_context is now REFUSED unless it is production. The kernel dispatch passes the literal
-- 'production' and has no other mode, so a driver that accepted 'test' would be offering a
-- boundary it cannot honour - and 'test' is the one value that disables both fail-closed
-- boundaries in the handler.
--
-- CREATE OR REPLACE preserves the ACL (SECURITY DEFINER, EXECUTE to postgres and service_role).

CREATE OR REPLACE FUNCTION public.fn_phase_d_drive_workflow(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  w         public.phase_b_workflow%rowtype;
  sr        public.phase_c_workflow_step_run%rowtype;
  hr        public.phase_c_handoff_run%rowtype;
  hc        public.phase_d_handoff_contract%rowtype;
  d         public.phase_d_dispatch%rowtype;
  v_prev    public.phase_c_workflow_step_run%rowtype;
  v_wf      text := nullif(btrim(coalesce(p_input->>'workflow_id','')),'');
  v_label   text := coalesce(nullif(btrim(p_input->>'label'),''), 'phase-d-drive');
  v_ctx     text := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_max     int  := coalesce(nullif(p_input->>'max_steps','')::int, 40);
  v_boid    text := nullif(btrim(coalesce(p_input->>'business_object_id','')),'');
  v_caller_reviewer text := nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'');
  v_cands   text[] := coalesce((select array_agg(x)
                                  from jsonb_array_elements_text(p_input->'reviewer_candidates') x),
                               '{}'::text[]);
  v_run     bigint;
  v_start   jsonb;
  v_steps   jsonb := '[]'::jsonb;
  v_handoffs jsonb := '[]'::jsonb;
  v_i       int := 0;
  v_driven  int := 0;
  v_haccept int := 0;
  v_dispatched int := 0;
  v_executed   int := 0;
  v_before  bigint;
  v_declared text;
  v_rev     text;
  v_task    bigint;
  v_decide  jsonb;
  v_hoff    jsonb;
  v_hpk     jsonb;
  v_err     text; v_sqlstate text; v_code text;
  v_run_state text;
  v_stopped jsonb := null;        -- where the DRIVE could go no further, and why
  v_first_refusal jsonb := null;  -- where the deterministic HANDLER first declined, and why
begin
  if v_wf is null then
    raise exception 'fn_phase_d_drive_workflow: workflow_id is required' using errcode = '22023';
  end if;
  -- The kernel dispatch hard-codes 'execution_context','production'. Accepting any other value
  -- here would be this routine promising a mode it has no way to pass on.
  if v_ctx <> 'production' then
    raise exception 'fn_phase_d_drive_workflow: execution_context % is not available. This driver goes through fn_kernel_step_complete, and fn_phase_d_dispatch_step executes the handler in production context with no other mode. (pd_drive_context_unavailable)',
      v_ctx using errcode = '22023';
  end if;

  select * into w from public.phase_b_workflow where workflow_id = v_wf;
  if not found then
    raise exception 'fn_phase_d_drive_workflow: % is not a frozen workflow', v_wf using errcode = '23503';
  end if;

  select count(*) into v_before from public.phase_d_effect_ledger;

  -- THE ARRIVAL NAMES THE OBJECT IT IS ABOUT. E25 derives business_key from the run's
  -- business_object_id and only when it carries the '<object>:' prefix of the object the step
  -- writes - 'inquiry:<uuid>' is an identity, a bare object name is not. The previous driver
  -- passed w.primary_object, which is the object's NAME, so the prefix test was false on every
  -- run it started and the derivation E25 built could never fire through this path.
  v_boid := coalesce(v_boid, w.primary_object || ':' || v_label);

  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id',        v_wf,
    'business_object_id', v_boid,
    'source_kind',        'autonomous',
    'source_ref',         format('zz-phase-d-%s-%s', v_label, v_wf),
    'requested_by',       w.accountable_role_id,
    'trigger_ctx',        jsonb_build_object('driver','fn_phase_d_drive_workflow',
                                             'path','kernel doors only')));
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

    -- ---- NO OPEN STEP RUN IS NOT NECESSARILY A STOPPED RUN -----------------------------------
    -- The kernel opens no successor until the receiving owner accepts the handoff.
    if not found then
      select * into hr from public.phase_c_handoff_run
       where run_id = v_run and status = 'open'
       order by handoff_run_id limit 1;
      -- A DRIVER THAT STOPS WITHOUT SAYING WHY IS THE INSTRUMENT GAP THIS ESTATE KEEPS FINDING.
      -- Both of these were a bare `exit when not found` in my first draft, so a run that ended in
      -- waiting_handoff with no D9 contract reported a stop with an empty reason, and a reader
      -- would have taken the blank for "nothing went wrong".
      if not found then
        if v_stopped is null then
          v_stopped := jsonb_build_object(
            'at', (select state from public.phase_c_workflow_run where run_id = v_run),
            'refused_with','pd_drive_no_open_work',
            'reason', format('no step run is open and no handoff run is open on run %s; the run is as far as the kernel will take it', v_run));
        end if;
        exit;
      end if;

      select * into hc from public.phase_d_handoff_contract where handoff_id = hr.handoff_id;
      if not found then
        if v_stopped is null then
          v_stopped := jsonb_build_object('at', hr.handoff_id, 'refused_with','pd_handoff_contract_absent',
            'reason', format('handoff %s is open and public.phase_d_handoff_contract holds no row for it, so this driver has no packet contract to satisfy', hr.handoff_id));
        end if;
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', false, 'refused_with', 'pd_handoff_contract_absent'));
        exit;
      end if;

      select * into v_prev from public.phase_c_workflow_step_run
       where step_run_id = hr.from_step_run_id;

      -- Derived where the estate can derive it; a labelled caller assertion for the work-product
      -- keys, which are what the sending PERSON hands over and no business rule ever reads.
      v_hpk := coalesce((select jsonb_object_agg(k, format('ZZ DEMO - %s declared by the driver standing in for %s', k, hc.sending_role_id))
                           from unnest(hc.packet_keys) k), '{}'::jsonb)
             || jsonb_build_object(
                  'business_object_id',
                    coalesce((select business_object_id from public.phase_c_workflow_run
                               where run_id = v_run), v_boid),
                  'object_version', coalesce(hr.object_version, 1),
                  'output', coalesce(v_prev.output_hash,
                                     'no output hash recorded on the sending step run'),
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
          'handoff_run_id',  hr.handoff_run_id,
          'actor_role_id',   hc.receiving_role_id,
          'packet',          v_hpk,
          'idempotency_key', format('%s:%s:%s', v_label, hr.handoff_id, hr.handoff_run_id)));
        v_haccept := v_haccept + 1;
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', v_hoff->'ok', 'to_step_id', v_hoff->>'to_step_id',
          'accountable_after', v_hoff->>'accountable_after'));
        continue;
      exception when others then
        v_sqlstate := SQLSTATE; v_err := SQLERRM;
        v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', false, 'refused_with', v_code, 'sqlstate', v_sqlstate,
          'reason', left(v_err, 400)));
        if v_stopped is null then
          v_stopped := jsonb_build_object('at', hr.handoff_id, 'refused_with', v_code,
                                          'reason', left(v_err, 400));
        end if;
        -- A driver that skipped a refused handoff would report a closure the workflow never reached.
        exit;
      end;
    end if;

    -- ---- WHAT THE DETERMINISTIC HANDLER DID WITH THIS STEP ------------------------------------
    -- It has already happened. The dispatch fires when the kernel OPENS the step, so by the time
    -- this loop sees an open step run the row is on the table. Reading it is the whole of what this
    -- driver has to do to measure Phase D; it never calls the handler itself.
    select * into d from public.phase_d_dispatch
     where step_run_id = sr.step_run_id order by dispatch_id desc limit 1;
    if found then
      v_dispatched := v_dispatched + 1;
      if d.outcome = 'EXECUTED' then v_executed := v_executed + 1; end if;
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'ok', (d.outcome = 'EXECUTED'), 'dispatch_outcome', d.outcome,
        'refused_with', nullif(d.refusal_code,''), 'reason', left(coalesce(d.reason,''), 400),
        'unresolved_keys', to_jsonb(coalesce(d.unresolved_keys,'{}'::text[])),
        'effect_id', d.effect_id));
      -- TWO SUBJECTS, TWO FIELDS. My first draft folded both into one 'stopped' object, and the
      -- deliverable then reported W21 as stopping at W21-S01 when the drive had in fact reached
      -- W21-S07 -- because step 1's dispatch refused, as nearly every dispatch does, and that was
      -- the first thing to claim the field. Where the HANDLER first declined is a Phase D fact;
      -- where the DRIVE could go no further is a fact about this harness and the kernel.
      if d.outcome <> 'EXECUTED' and v_first_refusal is null then
        v_first_refusal := jsonb_build_object('at', sr.step_id,
                                              'refused_with', nullif(d.refusal_code,''),
                                              'reason', left(coalesce(d.reason,''), 400));
      end if;
    else
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'ok', false, 'dispatch_outcome', 'NOT_DISPATCHED',
        'refused_with', 'pd_no_dispatch_row',
        'reason', 'the kernel opened this step and no phase_d_dispatch row exists for it'));
      if v_first_refusal is null then
        v_first_refusal := jsonb_build_object('at', sr.step_id, 'refused_with','pd_no_dispatch_row',
          'reason','the kernel opened this step and no phase_d_dispatch row exists for it');
      end if;
    end if;

    -- ---- A STEP THAT NEEDS AN INDEPENDENT VERDICT GETS ONE, THROUGH THE KERNEL'S OWN DOOR ------
    -- The reviewer is never chosen here: it is the one the frozen registry declares, or one the
    -- CALLER offered, and fn_kernel_review_decide decides independence either way. A driver that
    -- picked a reviewer would be fn_pick_reviewer returning the department head, one layer up.
    select s.independent_reviewer_role_id into v_declared
      from public.phase_b_workflow_step s where s.step_id = sr.step_id;
    v_rev := nullif(btrim(coalesce(v_declared,'')),'');
    if v_rev is null then
      v_rev := (select c from unnest(v_cands) c
                 where public.fn_kernel_reviewer_independent(sr.accountable_role_id, c) limit 1);
    end if;
    if v_rev is null and v_caller_reviewer is not null
       and public.fn_kernel_reviewer_independent(sr.accountable_role_id, v_caller_reviewer) then
      v_rev := v_caller_reviewer;
    end if;
    if v_rev is not null then
      select t.task_id into v_task from public.phase_c_task t
       where t.run_id = v_run and t.step_id = sr.step_id order by t.task_id desc limit 1;
      if v_task is not null then
        begin
          v_decide := public.fn_kernel_review_decide(jsonb_build_object(
            'task_id', v_task, 'reviewer_role_id', v_rev, 'decision', 'approved',
            'reason', format('%s: an independent reviewer approves %s', v_label, sr.step_id)));
        exception when others then
          -- Recorded, never swallowed: a verdict that could not be written is why the step may
          -- refuse a moment later, and a driver that hid it would make that refusal unexplainable.
          v_decide := jsonb_build_object('ok', false, 'error', left(SQLERRM, 240));
        end;
      end if;
    end if;

    -- ---- THE DOOR PRODUCTION USES ------------------------------------------------------------
    -- fn_kernel_step_complete, with what an ACTOR supplies and nothing else. No context, no gate
    -- evidence, no business_key, no owner_ref, no effect payload: the kernel dispatch resolves all
    -- of those from fn_phase_d_step_inputs and fn_phase_d_step_context, and will not accept them
    -- from a caller. That is the property this file exists to restore.
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id',      sr.step_run_id,
        'actor_role_id',    sr.accountable_role_id,
        'outcome',          'pass',
        'idempotency_key',  format('%s:%s:%s', v_label, sr.step_id, sr.step_run_id),
        'inputs',           jsonb_build_object('driver','fn_phase_d_drive_workflow',
                                               'note','no business content is supplied by this driver'),
        'output',           jsonb_build_object('status','completed',
                                               'output', format('%s completed %s', v_label, sr.step_id)),
        'evidence_refs',    jsonb_build_array(jsonb_build_object('driver_run', v_label)),
        'requested_action', 'proceed',
        'acceptance_criteria', format('%s drove %s through the kernel', v_label, sr.step_id),
        'object_version',   1));
      v_driven := v_driven + 1;
    exception when others then
      v_sqlstate := SQLSTATE; v_err := SQLERRM;
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'ok', false, 'kernel_refused', true, 'refused_with', v_code,
        'sqlstate', v_sqlstate, 'reason', left(v_err, 400)));
      v_stopped := jsonb_build_object('at', sr.step_id, 'refused_with', v_code,
                                      'reason', left(v_err, 400),
                                      'refused_by', 'fn_kernel_step_complete');
      exit;
    end;
  end loop;

  select state into v_run_state from public.phase_c_workflow_run where run_id = v_run;

  return jsonb_build_object(
    'ok', true,
    'workflow_id', v_wf,
    'run_id', v_run,
    'label', v_label,
    -- Named for what it measures, not for what a reader might hope it measures.
    'path', 'fn_kernel_workflow_start -> fn_kernel_review_decide -> fn_kernel_step_complete -> fn_phase_d_handoff_accept',
    'steps_in_workflow', (select count(*) from public.phase_b_workflow_step where workflow_id = v_wf),
    'steps_driven', v_driven,
    'handoffs_accepted', v_haccept,
    'open_handoffs_left', (select count(*) from public.phase_c_handoff_run
                            where run_id = v_run and status = 'open'),
    -- What Phase D actually did: how many step-openings the kernel dispatched to the
    -- deterministic handler, and how many of those the handler completed unaided.
    -- COUNTED FROM THE TABLE, NOT FROM THIS LOOP. The first version incremented these as the loop
    -- walked the open steps, and it reported dispatches_executed = 0 on a run that had produced
    -- three effect-ledger rows. The reason is the whole of E33: a step whose handler EXECUTES has
    -- its task closed in the same statement that opened it, so it is never an open step and this
    -- loop never sees it. An instrument that counts only what it walks past cannot count the thing
    -- that finishes before the walk reaches it. The population is every dispatch the kernel
    -- produced for this run.
    'dispatches_seen', (select count(*) from public.phase_d_dispatch where run_id = v_run),
    'dispatches_executed', (select count(*) from public.phase_d_dispatch
                             where run_id = v_run and outcome = 'EXECUTED'),
    'dispatch_outcomes', (select coalesce(jsonb_object_agg(o, n), '{}'::jsonb) from (
        select coalesce(nullif(refusal_code,''), outcome) o, count(*) n
          from public.phase_d_dispatch where run_id = v_run group by 1) z),
    'steps_loop_walked', v_dispatched,
    'effects_for_this_run', (select count(*) from public.phase_d_effect_ledger where run_id = v_run),
    'effects_total_delta', (select count(*) from public.phase_d_effect_ledger) - v_before,
    'run_state', v_run_state,
    'terminal', coalesce(v_run_state = any(
       (select allowed_terminal_states from public.phase_b_workflow where workflow_id = v_wf)), false),
    -- Where the DRIVE could go no further. Null only when the run reached a terminal state with
    -- nothing open, which is the one case where "it stopped" needs no explanation.
    'stopped', coalesce(v_stopped, case when v_i > v_max
      then jsonb_build_object('at','(step budget)','refused_with','pd_drive_max_steps',
             'reason', format('the drive ran %s steps and max_steps is %s', v_i - 1, v_max))
      else null end),
    -- Where the deterministic HANDLER first declined. This is the Phase D subject, and it is a
    -- different question from the one above. Read from the dispatch table in dispatch order for
    -- the same reason the counts are: the loop does not see every dispatched step.
    'first_handler_refusal', coalesce(
      (select jsonb_build_object('at', step_id, 'refused_with', nullif(refusal_code,''),
                                 'reason', left(coalesce(reason,''), 400))
         from public.phase_d_dispatch
        where run_id = v_run and outcome <> 'EXECUTED'
        order by dispatch_id limit 1), v_first_refusal),
    'steps', v_steps,
    'handoffs', v_handoffs);
end $function$;
