-- PHASE D · D9c — A FIXTURE CANNOT SATISFY A FOREIGN KEY, AND MATCHING ONE WOULD BE WORSE.
--
-- With the state read from its CHECK constraint, W01 reached step 3 of 8 and stopped on:
--
--   insert or update on table "department_objective" violates foreign key constraint
--   "department_objective_goal_key_fkey"
--
-- The generator had produced a goal_key that points at no company goal. That is the right outcome
-- of the wrong attempt: a fixture must not fill a foreign key at all. It either violates the
-- constraint, as here, or — the case that would not have shown up as an error — happens to match an
-- existing row and silently attaches the test to real business data.
--
-- FK columns are now skipped unless the caller names the parent in parent_refs. For a nullable
-- column the write proceeds without it; for a mandatory one the write refuses and names the column,
-- which is the honest signal that this workflow needs real parent data built in the same aborted
-- transaction, in the order reality produces it.
--
-- STATE OF THE SWEEP AT THIS POINT, measured across W01-W13:
--   closed 2 of 13 — W02 (9/9 steps, 9 effects, 8 handoffs accepted) and W04 (7/7, 7 effects)
--   the rest stop on a rule, a gate, or a missing parent, and not one stops on a defect in the
--   implementation.

-- PHASE D · D9b — THE STATE IS A CONSTRAINED VALUE, AND IT TOOK A DIFFERENT ROUTE TO THE COLUMN.
--
-- D9 took W02 to closure — 9 of 9 steps, 9 effects, 8 handoffs accepted, run terminal — and W01 to
-- step 3 of 8, where it stopped on:
--
--   new row for relation "department_objective" violates check constraint
--   "department_objective_status_check"
--
-- fn_phase_d_fixture_for_column already reads CHECK constraints, and it never saw this column.
-- fn_phase_d_object_write injects state, owner_ref and business_key into the payload ITSELF, so a
-- write map pointing a status column at 'state' bypasses the column loop entirely and received the
-- driver's hard-coded literal 'open'. Same defect class as customers_locale_chk one file earlier,
-- arriving by a route the first fix did not cover.
--
-- Where the map points a column at 'state' and that column enumerates its values, the state is now
-- read from the constraint. Where it does not, 'open' stands.

-- PHASE D · D9 — A RUN WITH NO OPEN STEP IS WAITING FOR SOMEBODY TO ACCEPT THE HANDOFF.
--
-- The first workflow sweep read like this:
--
--   W01  1/8 steps  1 effect  state=waiting_handoff  stop=W01-S01:ok
--   W02  1/9 steps  1 effect  state=waiting_review   stop=W02-S01:ok
--
-- Both stopped after a step that SUCCEEDED, which is the tell. The driver's loop looks for an open
-- step run and exits when there is none, and a run in waiting_handoff has none by design: the
-- frozen kernel opens the successor step only when the receiving role accepts the handoff. So the
-- report was describing this routine's missing call, not the workflow — and "W01 stops after step 1"
-- would have gone into a closure as a finding about W01.
--
-- Accountability sits with the SENDER until acceptance. That is the whole point of the handoff
-- contract, and fn_kernel_handoff_accept is where it transfers.
--
-- FOUR THINGS THE DRIVER MAY NOT DO, each enforced by the kernel rather than promised here:
--
--   * It may not choose who accepts. The receiver is read off the handoff run, and
--     fn_kernel_handoff_accept independently refuses anyone else with k3_not_the_receiver.
--   * It may not fabricate the packet. fn_phase_c_handoff_packet_valid requires
--     business_object_id, object_version, output, evidence_refs and requested_action; those come
--     from the handoff run's own recorded facts and from THE EFFECTS THIS RUN ACTUALLY WROTE.
--   * It may not accept a handoff twice — the kernel refuses a non-open one with
--     k3_handoff_not_open.
--   * It may not hide a refusal. A refused acceptance carries its machine code into the report and
--     stops the drive, so a partial run cannot read as a closure.
--
-- W02's waiting_review is NOT addressed here and is not claimed to be. A run waiting on a review
-- decision needs a different call, and guessing at it would be this same mistake in a new place.

begin;

create or replace function public.fn_phase_d_drive_workflow(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
  v_ledger int; v_before int; v_after int;
  v_reviewer text;
  v_task    bigint;
  v_decide  jsonb;
  v_declared_reviewer text;
  v_hr       public.phase_c_handoff_run%rowtype;
  v_packet   jsonb;
  v_accept   jsonb;
  v_handoffs jsonb := '[]'::jsonb;
  v_evidence jsonb;
  v_state   text;
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

    -- ---- NO OPEN STEP RUN IS NOT THE END OF THE WORKFLOW ---------------------------------------
    -- A run in waiting_handoff has no open step run BY DESIGN: the frozen kernel opens the
    -- successor only when the receiving role ACCEPTS the handoff. The first sweep read that as
    -- "W01 stops after step 1", which described this routine's missing call and not the workflow.
    -- Accountability sits with the sender until acceptance, and fn_kernel_handoff_accept is where
    -- it transfers.
    --
    -- The packet is built from what this run ACTUALLY PRODUCED — the handoff run's own recorded
    -- object and version, and the phase_d_effect_ledger rows this run really wrote. A packet
    -- assembled from placeholders would accept a handoff for work that does not exist, which is
    -- precisely the accountability gap the contract exists to close.
    if not found then
      select * into v_hr from public.phase_c_handoff_run
       where run_id = v_run and status = 'open'
       order by handoff_run_id limit 1;
      exit when not found;

      select jsonb_agg(jsonb_build_object(
               'effect_id', l.effect_id, 'step_id', l.step_id,
               'effect_type', l.effect_type, 'result_reference', l.result_reference))
        into v_evidence
        from public.phase_d_effect_ledger l
       where l.run_id = v_run;

      v_packet := jsonb_build_object(
        'business_object_id', v_hr.business_object_id,
        'object_version',     coalesce(v_hr.object_version, 1),
        'requested_action',   coalesce(v_hr.requested_action, 'accept and continue'),
        'output',             format('handoff %s from step run %s', v_hr.handoff_id,
                                     coalesce(v_hr.from_step_run_id::text, '(none)')),
        'evidence_refs',      coalesce(v_evidence, '[]'::jsonb),
        'acceptance_criteria', coalesce(v_hr.acceptance_criteria, ''));

      begin
        -- The RECEIVER accepts, and only the receiver. The identity is read off the handoff run,
        -- and fn_kernel_handoff_accept independently refuses anyone else with k3_not_the_receiver.
        v_accept := public.fn_kernel_handoff_accept(jsonb_build_object(
          'handoff_run_id', v_hr.handoff_run_id,
          'actor_role_id',  v_hr.receiving_role_id,
          'packet',         v_packet));
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_run_id', v_hr.handoff_run_id, 'handoff_id', v_hr.handoff_id,
          'receiving_role_id', v_hr.receiving_role_id, 'ok', true,
          'evidence_refs_carried', jsonb_array_length(coalesce(v_evidence, '[]'::jsonb))));
        continue;
      exception when others then
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_run_id', v_hr.handoff_run_id, 'handoff_id', v_hr.handoff_id,
          'receiving_role_id', v_hr.receiving_role_id, 'ok', false,
          'refused_with', coalesce((regexp_match(SQLERRM,
            '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+|gate[0-9]+_[a-z0-9_]+|br[0-9]+_[a-z0-9_]+)\)'))[1],
            '(none)'),
          'reason', left(SQLERRM, 300)));
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
    v_reviewer := null;
    v_state := 'open';
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
      v_reviewer := coalesce(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''),
                             v_caller_reviewer);
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
             -- AND NEVER A FOREIGN KEY THE CALLER DID NOT SUPPLY. W01-S03 stopped on
             --   violates foreign key constraint "department_objective_goal_key_fkey"
             -- because the generator produced a plausible-looking goal_key that points at no
             -- company goal. A fixture cannot satisfy a foreign key: it either violates the
             -- constraint, as here, or — far worse — happens to match and silently attaches the
             -- test to somebody's real row. Where the caller names the parent in parent_refs it is
             -- used; otherwise the column is left unwritten, which is honest for a nullable column
             -- and a clean refusal for a mandatory one.
             and (v_parents ? (wm.column_map->>k.key)
                  or not exists (select 1 from pg_constraint fk
                                  where fk.conrelid = a.attrelid and fk.contype = 'f'
                                    and a.attnum = any (fk.conkey)))
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

      -- THE STATE IS A CONSTRAINED VALUE TOO, AND IT DOES NOT COME THROUGH THE COLUMN LOOP.
      -- The writer injects state/owner_ref/business_key itself, so a map pointing a status column
      -- at 'state' never met fn_phase_d_fixture_for_column and got the driver's literal 'open':
      --   new row for relation "department_objective" violates check constraint
      --   "department_objective_status_check"
      -- Same class as customers_locale_chk one file earlier, reached by a different route. Where
      -- the map points a column at 'state' and that column enumerates its values, the state is
      -- read from the constraint; otherwise it stays 'open'.
      v_state := 'open';
      if wm.object_id is not null then
        select public.fn_phase_d_fixture_for_column(wm.target_relation, k.key, v_label) #>> '{}'
          into v_state
          from jsonb_each_text(wm.column_map) k
         where k.value = 'state'
         limit 1;
        v_state := coalesce(v_state, 'open');
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
          'context', v_fix || v_extra,
          'gate_evidence', v_fix || v_extra,
          'business_key', coalesce(nullif(v_eff->>'business_key',''), v_key),
          'owner_ref', coalesce(v_owner, nullif(v_eff->>'owner_ref',''), v_key),
          'effect_state', v_state,
          'effect_payload', v_eff)
        || case when e.expected_effect_type = 'REVIEW_VERDICT'
                then jsonb_strip_nulls(jsonb_build_object(
                       'verdict', v_verdict, 'reviewer_role_id', v_reviewer))
                else '{}'::jsonb end
        || case when b.handler_class = 'REVIEW_HANDLER'
                then jsonb_strip_nulls(jsonb_build_object(
                       'verdict', v_verdict,
                       'reviewer_role_id',
                         coalesce(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''),
                                  v_caller_reviewer)))
                else '{}'::jsonb end
        || case when e.expected_effect_type = 'MEASUREMENT_RECORD'
                then jsonb_build_object('numerator', 1, 'denominator', 1,
                                        'formula','fixture','window','fixture')
                else '{}'::jsonb end);

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
    'effects_for_this_run', v_ledger,
    'handoffs_accepted', (select count(*) from jsonb_array_elements(v_handoffs) x
                           where (x->>'ok')::boolean),
    'handoffs', v_handoffs,
    'effect_ledger_delta', v_after - v_before,
    'terminal', (select terminal from public.phase_b_workflow_state
                  where state = v_run_state),
    'steps', v_steps);
end $fn$;



commit;
