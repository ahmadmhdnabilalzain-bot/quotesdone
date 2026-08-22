-- F38 - a fix made the headline fall, because success was being converted into an earlier stop
--
-- MEASURED, and this is the whole finding. F36 let the five capability-dependent first steps
-- actually execute. Total EXECUTED dispatches across the thirty workflows then went DOWN, 45 -> 36,
-- and the five workflows that had just been fixed drove FEWER steps than before:
--
--   W11  steps_driven 0 of 7   run state waiting_handoff
--        stopped at W11-S01 :: k3_run_not_active -- "workflow run N is in state waiting_handoff,
--        not active - a step cannot be completed against a run that is not running"
--
-- fn_phase_d_handler_execute section 7 hands its completed step to the frozen kernel. When the
-- handler succeeds the kernel closes that step run itself, opens the successor, and where the step
-- ends in a handoff moves the run to waiting_handoff. This driver then called
-- fn_kernel_step_complete for the step that had just been closed, was refused -- correctly -- and
-- treated the refusal as the end of the drive.
--
-- So every handler success cost the drive the remainder of its workflow. The better Phase D got,
-- the worse this number looked, which is the most misleading shape an instrument can have.
--
-- NOTHING IN THE KERNEL CHANGES. fn_kernel_step_complete is right to refuse a completed step and
-- right to refuse a run that is not active. What was wrong is the driver's assumption that every
-- step needs an actor to close it. It now re-reads the step run after the dispatch and, when the
-- kernel has already moved it out of every open state, takes the next piece of work.
--
-- AND IT COUNTS THE TWO APART. The founder's ruling of 22 Aug 2026 section 4 asks for the
-- execution-input classes to be reported separately. A step closed by the handler's own effect is
-- CANONICAL_HANDLER_EFFECT and is now counted in steps_closed_by_the_handler; a step closed through
-- fn_kernel_step_complete by this driver standing in for its owner is CANONICAL_ACTOR_INPUT and
-- stays in steps_driven. Folding them was how "0 of 30 closed unaided" and "30 of 30 completed"
-- could both be true and neither be useful.
--
-- THE REST OF THE ROUTINE IS BYTE-IDENTICAL. Three anchors, each required to match exactly once.

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
  v_cap_fixture text;      -- F17: the committed CAPABILITY_RESULT row for this step
  v_cap_req   jsonb;       -- F17
  v_cap_res   jsonb;       -- F17
  v_caps      jsonb := '[]'::jsonb;   -- F17: what the capability path did, per step
  v_capn      int := 0;    -- F17: capability results accepted
  v_redisp    jsonb;
  sr2         public.phase_c_workflow_step_run%rowtype;  -- F38: the step run, re-read after dispatch
  v_handler_closed int := 0;          -- F38: steps the handler closed through the kernel itself
  v_rtask     bigint;                 -- F35: the task the internal review decides
  v_rrev      text;                   -- F35: the reviewer, frozen-declared or independence-tested
  v_rdec      jsonb;                  -- F35: what fn_kernel_review_decide returned
  v_revs      jsonb := '[]'::jsonb;   -- F35: what the review path did, per step
  v_revn      int := 0;               -- F35: internal reviews recorded
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
            -- NO run_id IN A REPRODUCIBLE DELIVERABLE. This read "...on run 25384", and a run_id is
            -- different every drive, so the committed CSV could never reproduce byte-for-byte and
            -- phase_d_deliverables_match_production.test.mjs failed on thirty lines that differed
            -- only in that number. The run_id is on the row already, as run_id; a reason is a
            -- reason.
            'reason', 'no step run is open and no handoff run is open; the run is as far as the kernel will take it');
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

    -- ---- F17. THE CAPABILITY RESULT ARRIVES, AND THE STEP IS DISPATCHED AGAIN ------------------
    -- The founder's section C sequence is: capability request -> capability result -> output
    -- validation -> evidence/provenance -> handler continuation. F05 built the first four and left
    -- the fifth to the caller, because the request is opened INSIDE fn_kernel_open_step and there is
    -- no moment between the open and the refusal for anyone to answer it. This is that moment: the
    -- kernel opened the step, the handler asked and was refused for want of an answer, and the
    -- driver -- standing in for whoever supplies the capability -- submits the pre-authored fixture
    -- result through the canonical acceptance service and asks the estate to dispatch the step
    -- again.
    --
    -- Nothing here bypasses anything. fn_phase_d_capability_result_accept still requires a verified
    -- Phase D fixture context, still validates the payload against the step's own output contract,
    -- still records the fixture id, version and hash, and still refuses provider_mode = provider
    -- while the hold stands. If any of that refuses, the step stays refused and the refusal is
    -- recorded below rather than swallowed.
    if found and d.refusal_code = 'pd_capability_unavailable'
       and public.fn_phase_d_fixture_context() is not null then
      select c.fixture_id into v_cap_fixture
        from public.phase_d_fixture_catalogue c
       where c.scope = 'CAPABILITY_RESULT' and c.step_id = sr.step_id
       order by c.fixture_id limit 1;
      begin
        if v_cap_fixture is null then
          raise exception 'no committed CAPABILITY_RESULT fixture for step % (pd_capability_fixture_unknown)', sr.step_id
            using errcode = '23503';
        end if;
        v_cap_req := public.fn_phase_d_capability_request_open(jsonb_build_object(
          'step_run_id', sr.step_run_id, 'requested_by', sr.accountable_role_id));
        v_cap_res := public.fn_phase_d_capability_result_accept(jsonb_build_object(
          'request_id',    v_cap_req->'request_id',
          'provider_mode', 'fixture',
          'fixture_id',    v_cap_fixture,
          'accepted_by',   sr.accountable_role_id));
        v_capn := v_capn + 1;
        -- HANDLER CONTINUATION: the same door the kernel used, on the same step run.
        v_redisp := public.fn_phase_d_dispatch_step(jsonb_build_object(
          'step_run_id',     sr.step_run_id,
          'actor_role_id',   sr.accountable_role_id,
          'opened_by_kind',  'capability_result',
          'opened_by_ref',   format('%s:result=%s', v_cap_fixture, v_cap_res->>'result_id'),
          'idempotency_key', format('%s:%s:%s:cap', v_label, sr.step_id, sr.step_run_id)));
        v_caps := v_caps || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'request_id', v_cap_req->'request_id',
          'result_id', v_cap_res->'result_id', 'provider_mode', v_cap_res->>'provider_mode',
          'fixture_id', v_cap_res->>'fixture_id', 'fixture_version', v_cap_res->'fixture_version',
          'fixture_hash', v_cap_res->>'fixture_hash',
          'redispatch_outcome', v_redisp->>'outcome',
          'redispatch_refusal', v_redisp->>'refusal_code'));
        select * into d from public.phase_d_dispatch
         where step_run_id = sr.step_run_id order by dispatch_id desc limit 1;
      exception when others then
        v_caps := v_caps || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'fixture_id', v_cap_fixture, 'ok', false,
          'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
          'reason', left(SQLERRM, 300)));
      end;
      v_cap_fixture := null;
    end if;

    -- ---- THE INTERNAL REVIEW, THROUGH THE KERNEL'S OWN DOOR, THEN ASK AGAIN (F35) -----------
    -- The mirror of the capability block above, for the other input class the handler cannot
    -- invent. F34 made fn_phase_d_handler_execute read the verdict and the reviewer from the review
    -- the estate RECORDED -- phase_c_task.reviewer_role_id and the sealed TRACE-ROLE-ACTION -- and
    -- refuse with pd_review_not_recorded when there is none. There is none at step-open time,
    -- because the kernel dispatches the handler the instant the step opens and no review has
    -- happened yet. This is the moment one can: the step is open and owned, the handler has said
    -- what it is missing, and the driver -- standing in for the reviewer -- records the decision
    -- through fn_kernel_review_decide and asks the estate to dispatch the step again.
    --
    -- NOTHING IS BYPASSED. fn_kernel_review_decide refuses a reviewer the frozen registry did not
    -- name where it names one, refuses a reviewer who resolves to the creator, refuses a review
    -- with no stated reason, and seals its own trace. The reviewer is never chosen by preference
    -- here: it is the frozen independent_reviewer_role_id, or a candidate the kernel's own
    -- independence test allows. If it refuses, the step stays refused and the refusal is recorded.
    if found and d.refusal_code = 'pd_review_not_recorded' then
      begin
        select t.task_id into v_rtask from public.phase_c_task t
         where t.run_id = sr.run_id and t.step_id = sr.step_id
         order by t.task_id desc limit 1;

        select s2.independent_reviewer_role_id into v_rrev
          from public.phase_b_workflow_step s2 where s2.step_id = sr.step_id;
        v_rrev := nullif(btrim(coalesce(v_rrev,'')),'');
        if v_rrev is null then
          v_rrev := (select c from unnest(v_cands) c
                      where public.fn_kernel_reviewer_independent(sr.accountable_role_id, c)
                      limit 1);
        end if;
        if v_rrev is null and v_caller_reviewer is not null
           and public.fn_kernel_reviewer_independent(sr.accountable_role_id, v_caller_reviewer) then
          v_rrev := v_caller_reviewer;
        end if;

        if v_rtask is null then
          raise exception 'step % has no task to review (pd_review_no_task)', sr.step_id
            using errcode = '23503';
        end if;
        if v_rrev is null then
          raise exception 'step % is owned by % and no candidate role passes the kernel independence test against it (pd_review_no_independent_reviewer)',
            sr.step_id, sr.accountable_role_id using errcode = '23503';
        end if;

        -- The stated reason is the committed rationale fixture, not a sentence written here.
        v_rdec := public.fn_kernel_review_decide(jsonb_build_object(
          'task_id',          v_rtask,
          'reviewer_role_id', v_rrev,
          'decision',         'approved',
          'reason',           coalesce(
                                public.fn_phase_d_fixture_output(sr.step_id,'rationale') #>> '{}',
                                'PHASE_D_FIXTURE_DO_NOT_PUBLISH - no committed rationale fixture')));

        if coalesce((v_rdec->>'ok')::boolean, false) then
          v_redisp := public.fn_phase_d_dispatch_step(jsonb_build_object(
            'step_run_id',     sr.step_run_id,
            'actor_role_id',   sr.accountable_role_id,
            'opened_by_kind',  'internal_review',
            'opened_by_ref',   format('task=%s;reviewer=%s', v_rtask, v_rrev),
            'idempotency_key', format('%s:%s:%s:rev', v_label, sr.step_id, sr.step_run_id)));
          select * into d from public.phase_d_dispatch
           where step_run_id = sr.step_run_id order by dispatch_id desc limit 1;
        end if;

        v_revn := v_revn + 1;
        v_revs := v_revs || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'task_id', v_rtask, 'reviewer_role_id', v_rrev,
          'review_ok', v_rdec->'ok', 'review_error', v_rdec->>'error',
          'redispatch_outcome', v_redisp->>'outcome',
          'redispatch_refusal', v_redisp->>'refusal_code'));
      exception when others then
        v_revs := v_revs || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'ok', false,
          'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
          'reason', left(SQLERRM, 300)));
      end;
    end if;

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

    -- ---- F38. THE HANDLER MAY HAVE ALREADY COMPLETED THIS STEP -----------------------------
    -- fn_phase_d_handler_execute section 7 hands the completed step to the FROZEN KERNEL itself.
    -- When it succeeds, the kernel closes the step run, opens the successor, and -- where the step
    -- ends in a handoff -- moves the whole run to waiting_handoff. The driver then arrived at its
    -- own fn_kernel_step_complete for a step that was already closed, against a run that was no
    -- longer active, and was refused:
    --
    --   k3_run_not_active: workflow run N is in state waiting_handoff, not active
    --
    -- and the drive stopped there. MEASURED, and it is the reason a fix made the headline fall:
    -- after F36 let the five capability steps execute, total EXECUTED across the estate went from
    -- 45 to 36, because every workflow whose handler succeeded early now died at the next
    -- iteration. Success in one place was being converted into an earlier stop.
    --
    -- The kernel is right on both counts and neither is touched. What was wrong is that this
    -- driver assumed every step needs an actor to close it. A step the HANDLER closed is closed;
    -- the driver re-reads the step run and, if the kernel has moved it out of every open state,
    -- takes the next piece of work instead of trying to close it twice.
    --
    -- This is also the §4 distinction the founder asked for: a step closed here is
    -- CANONICAL_HANDLER_EFFECT, and a step closed below is CANONICAL_ACTOR_INPUT. They are counted
    -- apart because they are different claims.
    select * into sr2 from public.phase_c_workflow_step_run where step_run_id = sr.step_run_id;
    if found and sr2.state not in
       ('ready','active','not_ready','waiting_input','waiting_review','blocked') then
      v_handler_closed := v_handler_closed + 1;
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'closed_by', 'CANONICAL_HANDLER_EFFECT', 'step_run_state', sr2.state));
      continue;
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
    -- phase_b_workflow.allowed_terminal_states is TEXT, not an array: 'completed; cancelled;
    -- superseded'. My first draft wrote `v_run_state = any((select allowed_terminal_states ...))`,
    -- which Postgres parses as the SUBQUERY form of ANY — so it compared the run state against the
    -- whole semicolon-separated string as one value and was false for every run ever driven.
    -- closure_verdict could therefore only ever read STOPPED, and this deliverable reported 0 of 30
    -- closing while runs were reaching 'completed'. Caught by the deliverable's own reproduction
    -- test, not by reading the code.
    'terminal', exists (
       select 1 from public.phase_b_workflow w2,
            lateral unnest(string_to_array(coalesce(w2.allowed_terminal_states,''), ';')) s
        where w2.workflow_id = v_wf and btrim(s) = v_run_state),
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
    'capability_results_accepted', v_capn,
    'capability_path', v_caps,
    'steps_closed_by_the_handler', v_handler_closed,
    'internal_reviews_recorded', v_revn,
    'review_path', v_revs,
    'steps', v_steps,
    'handoffs', v_handoffs);
end $function$
;
