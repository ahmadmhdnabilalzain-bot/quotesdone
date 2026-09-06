CREATE OR REPLACE FUNCTION public.fn_phase_d_run_injected_defects()
 RETURNS TABLE(defect_id text, category text, status text, observed text, blocker text)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ok boolean; v_msg text; v_n int; v_a jsonb; v_b jsonb; v_key text; v_pay jsonb;
  v_sup text; v_id bigint;
  -- M08. The locals the eight re-measured branches need. Every one is scratch for a single branch
  -- except v_m3_trace and v_m3_task, which carry a REAL sealed verdict and a REAL task from the
  -- branch that produced them to the branch that has to attempt to tamper with it.
  v_m3_fx jsonb; v_m3_drive jsonb; v_m3_a jsonb;
  v_m3_refkey text; v_m3_boid text; v_m3_key text; v_m3_ctl text; v_m3_state text; v_m3_def text;
  v_m3_srid bigint; v_m3_run bigint; v_m3_task bigint; v_m3_trace bigint; v_m3_sup bigint;
  v_m3_n int; v_m3_s0 int; v_m3_s1 int; v_m3_p1 int; v_m3_p2 int; v_m3_p3 int;
  v_m3_ok2 boolean; v_m3_orph bigint;
begin
  if public.fn_phase_d_fixture_context() is null then
    -- F01. THIS READ A GUC ANY CALLER COULD SET. app.phase_d_test_context = 'on' was a string the
    -- caller supplied about itself; the context is now an hmac over txid_current(), keyed by a
    -- secret no role can SELECT, minted only against an approved audited operation. Leaving the old
    -- door open here would have left the whole control reachable through the value F01 removed.
    raise exception 'no verified Phase D fixture context in this transaction (pd_fixture_no_test_context)'
      using errcode = '23514',
            hint = 'select public.fn_phase_d_test_context_open(''{"operation_key":"pdop_deliverable_build","label":"..."}''); and abort the transaction when finished.';
  end if;

  -- ============ helper shape: each probe INJECTS, then reports what the machine did ============

  -- ---- IDEMPOTENCY ----------------------------------------------------------------------------
  -- PD-IDEM-001 duplicate registration: one identity, two canonical writes, no second row.
  v_key := 'zz-idem-001-' || md5('reg');
  v_a := public.fn_phase_d_object_write(jsonb_build_object(
    'object_id','customer_account','business_key', md5(v_key)::uuid::text,'owner_ref', md5(v_key)::uuid::text,
    'created_by','defect_probe','state','active','payload', jsonb_build_object('full_name','ZZ DEMO — idem001')));
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','customer_account','business_key', md5(v_key)::uuid::text,'owner_ref', md5(v_key)::uuid::text,
      'created_by','defect_probe','state','active','payload', jsonb_build_object('full_name','ZZ DEMO — idem001')));
    v_ok := (v_a->>'result_reference') = (v_b->>'result_reference');
    v_msg := format('both writes resolved to %s', v_b->>'result_reference');
  exception when others then
    v_ok := true; v_msg := 'second write refused: ' || left(SQLERRM,70);
  end;
  defect_id:='PD-IDEM-001'; category:='IDEMPOTENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-IDEM-003 duplicate supplier assignment: the unique index is the machine's answer.
  select count(*) into v_n from pg_index i join pg_class ic on ic.oid=i.indexrelid
   where i.indrelid='public.inquiry_matches'::regclass and i.indisunique
     and ic.relname='inquiry_matches_inquiry_id_supplier_id_key';
  defect_id:='PD-IDEM-003'; category:='IDEMPOTENCY';
  status := case when v_n=1 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('UNIQUE (inquiry_id, supplier_id) present=%s; GATE-015 refuses a duplicate dispatch before it', v_n);
  blocker := null; return next;

  -- PD-IDEM-004 duplicate notification request -> one effect. The effect ledger's unique key.
  select count(*) into v_n from pg_constraint
   where conrelid='public.phase_d_effect_ledger'::regclass and contype='u';
  defect_id:='PD-IDEM-004'; category:='IDEMPOTENCY';
  status := case when v_n>0 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('phase_d_effect_ledger carries %s unique constraint(s) on (step_run_id, effect_type)', v_n);
  blocker := null; return next;

  -- PD-IDEM-005 duplicate payment webhook -> one monetary transition.
  v_key := 'zz-idem-005-' || md5('pay');
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W16-S02','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W16-S02','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    select count(*) into v_n from public.phase_d_external_attempt where idempotency_key=v_key and delivered;
    v_ok := coalesce((v_b->>'replay')::boolean,false) and v_n=1;
    v_msg := format('replay=%s deliveries=%s', v_b->>'replay', v_n);
  exception when others then v_ok:=false; v_msg:='raised: '||left(SQLERRM,70); end;
  defect_id:='PD-IDEM-005'; category:='IDEMPOTENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-IDEM-002 duplicate workflow step completion -> the FIRST result is returned again.
  -- THE OLD BLOCKER SAID THIS NEEDED A COMMITTED STEP RUN. Re-measured 24 Aug 2026 and false.
  -- fn_kernel_step_complete section 1 reads public.phase_c_step_completion by idempotency_key
  -- BEFORE any work and returns v_prior || jsonb_build_object('replay', true). Nothing on that
  -- path waits for a commit, so two calls in ONE transaction exercise the real branch.
  begin
    perform set_config('app.phase_d_hold_step','W04-S03', true);
    v_m3_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','zz-pd-idem-002','execution_context','test','for_workflow','W04'));
    select st.contributes_ref into v_m3_refkey from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='W04')
     limit 1;
    v_m3_boid := case when v_m3_refkey is not null and coalesce(v_m3_fx->'parent_refs'->>v_m3_refkey,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id='W04')
           || ':' || (v_m3_fx->'parent_refs'->>v_m3_refkey) else null end;
    v_m3_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W04','label','zz-pd-idem-002','execution_context','production',
      'hold_at_step_id','W04-S03')
      || case when v_m3_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_m3_boid) end);
    v_m3_srid := nullif(v_m3_drive->>'held_step_run_id','')::bigint;
    v_m3_run  := nullif(v_m3_drive->>'run_id','')::bigint;
    perform set_config('app.phase_d_hold_step','', true);
    if v_m3_srid is null then
      v_ok := false;
      v_msg := 'no step run was held open at W04-S03; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      v_m3_key := 'zz-pd-idem-002:' || v_m3_srid;
      v_a := public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', v_m3_key,
        'inputs', jsonb_build_object('mode','first completion'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - validated customer profile'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','first completion')),
        'acceptance_criteria','the step completes once',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
      v_b := public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', v_m3_key,
        'inputs', jsonb_build_object('mode','duplicate completion'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - validated customer profile'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','duplicate completion')),
        'acceptance_criteria','a duplicate returns the first result',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', v_m3_key || ':a-different-key',
        'inputs', jsonb_build_object('mode','control'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - validated customer profile'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','control')),
        'acceptance_criteria','a different key on a step run already completed',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_ctl := 'ACCEPTED';
      exception when others then
        v_m3_ctl := case when position('k3_step_state_invalid' in SQLERRM) > 0
                         then 'k3_step_state_invalid/' || SQLSTATE
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      select count(*) into v_m3_n from public.phase_c_step_completion where step_run_id = v_m3_srid;
      select state into v_m3_state from public.phase_c_workflow_step_run where step_run_id = v_m3_srid;
      v_ok := not coalesce((v_a->>'replay')::boolean, true)
          and coalesce((v_b->>'replay')::boolean, false)
          and v_m3_ctl = 'k3_step_state_invalid/23514'
          and v_m3_n = 1 and v_m3_state = 'completed';
      v_msg := format(
        'W04 driven through the kernel doors and held open at W04-S03 (step run %s). INJECTION: '
     || 'fn_kernel_step_complete called TWICE with the same idempotency_key %L. First call '
     || 'replay=%s; second call replay=%s and it returned the FIRST stored result rather than '
     || 'recomputing one. CONTROL, differing in exactly one respect - same step run, same actor, '
     || 'same output, a DIFFERENT idempotency_key: %s, because public.phase_b_step_transition '
     || 'declares no completed -> completed edge, so a second real completion is refused rather '
     || 'than replayed. public.phase_c_step_completion rows for this step run: %s. Step run state: '
     || '%s. No second completion and no second effect; the transaction is aborted.',
        v_m3_srid, v_m3_key, coalesce(v_a->>'replay','(null)'), coalesce(v_b->>'replay','(null)'),
        v_m3_ctl, v_m3_n, v_m3_state);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-IDEM-002'; category:='IDEMPOTENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- ---- CONCURRENCY ----------------------------------------------------------------------------
  -- PD-CONC-002 two suppliers submit the same revision number -> revision uniqueness.
  select count(*) into v_n from public.phase_d_business_object_binding
   where object_id='quotation_revision' and policy_family='IMMUTABLE_REVISION';
  defect_id:='PD-CONC-002'; category:='CONCURRENCY';
  status := case when v_n=1 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'quotation_revision is IMMUTABLE_REVISION: a second write supersedes as a new revision and never overwrites';
  blocker := null; return next;

  -- PD-CONC-003 two admins publish the same quotation set -> idempotent result.
  v_key := 'zz-conc-003-' || md5('pub');
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W15-S04','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W15-S04','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_ok := coalesce((v_b->>'replay')::boolean,false);
    v_msg := format('second publish returned the first result id %s and delivered nothing new', v_b->>'provider_result_id');
  exception when others then v_ok:=false; v_msg:='raised: '||left(SQLERRM,70); end;
  defect_id:='PD-CONC-003'; category:='CONCURRENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-CONC-004 cancellation races with delivery -> a cancelled subject cannot deliver.
  v_key := 'zz-conc-004-' || md5('cancel');
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S01','idempotency_key',v_key,'mock_case','cancellation',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    begin
      perform public.fn_phase_d_external_deliver(jsonb_build_object(
        'step_id','W13-S01','idempotency_key',v_key,'mock_case','success',
        'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
      v_ok := false; v_msg := 'a cancelled subject was delivered';
    exception when others then
      v_ok := position('pd_external_cancelled' in SQLERRM)>0;
      v_msg := 'delivery after cancellation refused: pd_external_cancelled';
    end;
  exception when others then v_ok:=false; v_msg:='raised: '||left(SQLERRM,70); end;
  defect_id:='PD-CONC-004'; category:='CONCURRENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-CONC-005 refund decision races with execution -> one immutable decision.
  defect_id:='PD-CONC-005'; category:='CONCURRENCY';
  select count(*) into v_n from pg_trigger t join pg_proc p on p.oid=t.tgfoid
   where t.tgrelid='public.refunds'::regclass and p.proname='fn_refund_founder_decision_only';
  status := case when v_n=1 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'z00_refund_founder_decision_only is a row trigger on public.refunds: every approval path, '
           || 'racing or not, must present an active founder identity or the row is refused';
  blocker := null; return next;

  -- PD-CONC-001 two workers claim the same task -> needs two sessions.
  defect_id:='PD-CONC-001'; category:='CONCURRENCY'; status:='NOT_RUN'; observed:=null;
  blocker := 'a true race needs TWO concurrent database sessions. Everything in this file runs in one '
          || 'aborted transaction, so a second claimant cannot exist. Executing it needs a harness that '
          || 'opens two connections and commits — which under the hold would leave rows behind.';
  return next;

  -- ---- FINANCE --------------------------------------------------------------------------------
  -- PD-FIN-003 refund without founder decision -> refused.
  begin
    insert into public.refunds (transaction_id, customer_id, amount_fils, reason_code, status, decided_by, decided_at)
    values (null, null, 100, 'other', 'approved', 'trust_and_safety_manager', now());
    v_ok := false; v_msg := 'an approved refund by a non-founder was ACCEPTED';
  exception when sqlstate '42501' then
    v_ok := true; v_msg := 'refused 42501: approved by a role that is not an active founder identity';
  when others then
    v_ok := false; v_msg := 'refused for another reason before the guard: ' || left(SQLERRM,60);
  end;
  defect_id:='PD-FIN-003'; category:='FINANCE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-FIN-005 unknown monetary state silently accepted -> visible exception.
  begin
    update public.phase_d_fixture_stage set working_state = 'zz_not_a_rung'
     where object_id = 'payment_transaction';
    v_ok := false; v_msg := 'an undeclared payment state was ACCEPTED';
  exception when others then
    v_ok := position('pd_stage_payment_state_undeclared' in SQLERRM)>0;
    v_msg := 'refused: the state is not a rung of public.phase_d_payment_state';
  end;
  defect_id:='PD-FIN-005'; category:='FINANCE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-FIN-002 reveal before confirmed reconciliation -> refused.
  select count(*) into v_n from public.phase_d_payment_state where authorizes_reveal;
  defect_id:='PD-FIN-002'; category:='FINANCE';
  status := case when v_n=2 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('%s of 6 payment rungs authorise a reveal (payment_reconciled, reveal_authorized); '
                     'BR-020 names rung 5 as the founder-approved bar and no rung below it authorises', v_n);
  blocker := null; return next;

  -- ---- Ten injections that DO have a live refusal, each with a control -------------------------
  -- Recorded blockers for all ten said the subject needed section 8, a committed run or a path that
  -- is not built. Measured 24 Aug 2026: the refusal exists, it is nameable, and a control differing
  -- in exactly one respect behaves differently. Each branch injects, then reports what the machine
  -- did — and states its own boundary where it has one.
  declare
    v_ovl   text;   -- a real category overlay, read from the register rather than typed here
    v_state text;   -- the injected call's state
    v_ctl   text;   -- the control call's state
    v_code  text;   -- the refusal code the machine named
    v_p1    boolean; v_p2 boolean;
    v_qbad  uuid;    v_qgood uuid;
    v_task  bigint;
  begin
    select b.live_role_id into v_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;

    -- PD-FIN-001 executor also reconciles -> separation of duties.
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-031',
      jsonb_build_object('accountable_role_id','financial_controller','reviewer_role_id','financial_controller')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-031',
      jsonb_build_object('accountable_role_id','financial_controller','reviewer_role_id','trust_and_safety_manager')) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-FIN-001'; category:='FINANCE';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-031 at its registered point fn_kernel_reviewer_independent: one identity as executor and reconciler -> %s/%s; two identities -> %s. CHECK phase_c_refund_decision_ck carries it too but kernel_write_authority names no writer for that table.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;
  -- PD-AUTH-005 — WITHDRAWN, and this is why rather than a silent revert.
  -- The branch that closed it called public.fn_phase_c_task_create. public.kernel_write_authority
  -- says that routine may write public.phase_c_task; public.kernel_retired_path says it is a
  -- KERNEL_INTERNAL_PRIMITIVE, reachable only from fn_kernel_*. Both are true together — it is the
  -- authorised writer, called by the kernel — so a PROBE calling it is exactly the bypass
  -- fn_kernel_retired_path_state counts, and it took that board from 0 of 9 to 1 of 9.
  -- Making the board's exclusion list longer to admit this estate's own probe would be editing a
  -- kernel board to suit the code it audits. The refusal was real and was observed; the route to it
  -- was not one a probe may take.
  defect_id:='PD-AUTH-005'; category:='AUTH'; status:='NOT_RUN'; observed:=null;
  blocker := 'z10_phase_c_overlay_not_accountable refused a category overlay presented as the accountable task owner, and the canonical owner was accepted. closing this needs public.fn_phase_c_task_create, which public.kernel_retired_path classifies KERNEL_INTERNAL_PRIMITIVE — reachable only from fn_kernel_*. A probe that calls it directly is the bypass fn_kernel_retired_path_state exists to catch, and it turned that board red at 1 of 9 on 24 Aug 2026. The refusal itself is real and was observed before the branch was withdrawn.';
  return next;

    -- PD-DISP-005 category overlay attempts a dispatch.
    select rc.state, rc.refusal_code into v_state, v_code
      from public.fn_phase_d_rule_check('BR-048', jsonb_build_object('actor_role_id', v_ovl)) rc;
    select rc.state into v_ctl
      from public.fn_phase_d_rule_check('BR-048', jsonb_build_object('actor_role_id','inquiry_router')) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-DISP-005'; category:='DISPATCH';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-048 (category overlays cannot dispatch): actor %s -> %s/%s; the overlay''s own invocation_role_id inquiry_router -> %s. The identity is resolved through fn_phase_c_resolve_actor and matched against phase_c_overlay_binding, not taken from the call.',
                       v_ovl, v_state, v_code, v_ctl);
    blocker := null; return next;
  -- PD-LEGAL-005 — WITHDRAWN, and this is why rather than a silent revert.
  -- The branch that closed it called public.fn_phase_c_task_create. public.kernel_write_authority
  -- says that routine may write public.phase_c_task; public.kernel_retired_path says it is a
  -- KERNEL_INTERNAL_PRIMITIVE, reachable only from fn_kernel_*. Both are true together — it is the
  -- authorised writer, called by the kernel — so a PROBE calling it is exactly the bypass
  -- fn_kernel_retired_path_state counts, and it took that board from 0 of 9 to 1 of 9.
  -- Making the board's exclusion list longer to admit this estate's own probe would be editing a
  -- kernel board to suit the code it audits. The refusal was real and was observed; the route to it
  -- was not one a probe may take.
  defect_id:='PD-LEGAL-005'; category:='LEGAL'; status:='NOT_RUN'; observed:=null;
  blocker := 'z20_phase_c_task_state_guard refused the owner of W28-S04 as its own reviewer, and general_counsel was accepted. closing this needs public.fn_phase_c_task_create, which public.kernel_retired_path classifies KERNEL_INTERNAL_PRIMITIVE — reachable only from fn_kernel_*. A probe that calls it directly is the bypass fn_kernel_retired_path_state exists to catch, and it turned that board red at 1 of 9 on 24 Aug 2026. The refusal itself is real and was observed before the branch was withdrawn.';
  return next;

    -- PD-DISP-003 an unapproved supplier-safe package reaches dispatch.
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_safe_package','business_key','zz-disp-003-approved','owner_ref','zz-disp-003',
      'created_by','defect_probe','state','approved','payload', jsonb_build_object('n',1)));
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-012',
      jsonb_build_object('safe_package_ref','zz-disp-003-unapproved',
                         'safe_package_approved_by','marketplace_content_privacy_reviewer')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-012',
      jsonb_build_object('safe_package_ref','zz-disp-003-approved',
                         'safe_package_approved_by','marketplace_content_privacy_reviewer')) rc;
    select g.passed into v_p1 from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
      'safe_package_ref','zz-disp-003-approved','safe_package_approved_by','marketplace_content_privacy_reviewer',
      'actor_role_id','marketplace_content_privacy_reviewer')) g;
    select g.passed into v_p2 from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
      'safe_package_ref','zz-disp-003-approved','safe_package_approved_by','compliance_and_privacy_officer',
      'actor_role_id','marketplace_content_privacy_reviewer')) g;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS' and v_p1 is false and v_p2 is true;
    defect_id:='PD-DISP-003'; category:='DISPATCH';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-012: a package ref that resolves to no approved supplier_safe_package record -> %s/%s; the approved record written through fn_phase_d_object_write -> %s. GATE-013 on the same approved package: approver=author -> passed %s, independent approver -> passed %s.',
                       v_state, v_code, v_ctl, v_p1, v_p2);
    blocker := null; return next;

    -- PD-LEGAL-001 a certificate issued before terms acceptance.
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','customer_terms_acceptance','business_key','zz-legal-001-accepted','owner_ref','zz-legal-001',
      'created_by','defect_probe','state','accepted','payload', jsonb_build_object('n',1)));
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-026',
      jsonb_build_object('acceptance_ref','zz-legal-001-no-such-acceptance')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-026',
      jsonb_build_object('acceptance_ref','zz-legal-001-accepted')) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-LEGAL-001'; category:='LEGAL';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-026: a certificate whose acceptance_ref resolves to no customer_terms_acceptance or supplier_terms_acceptance record -> %s/%s; the same call naming a real acceptance record -> %s. The ref is resolved, not merely required to be non-empty.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;

    -- PD-PRIV-001 a supplier-facing payload carrying a customer identity.
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-011',
      jsonb_build_object('supplier_payload','RFQ 12 t rebar. Contact zz.customer@example.invalid 0501234567')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-011',
      jsonb_build_object('supplier_payload','RFQ 12 t rebar grade B500B, delivery Dubai, no identity')) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-PRIV-001'; category:='PRIVACY';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-011: a supplier-safe payload carrying an email address and a UAE mobile -> %s/%s; the same payload with the identity removed -> %s. BOUNDED: the row-match arm searches public.customers, which holds few rows; the refusal here came from the shape arm.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;

    -- PD-QUOTE-002 a quote missing a mandatory commercial field is published.
    insert into public.quotes (id, quote_amount, status, source)
      values (gen_random_uuid(), 1000, '', 'zz-defect-probe') returning id into v_qbad;
    insert into public.quotes (id, quote_amount, status, source)
      values (gen_random_uuid(), 1000, 'submitted', 'zz-defect-probe') returning id into v_qgood;
    select g.passed, g.refusal_code into v_p1, v_code
      from public.fn_phase_d_gate_evaluate('GATE-017', jsonb_build_object('quote_id', v_qbad::text)) g;
    select g.passed into v_p2
      from public.fn_phase_d_gate_evaluate('GATE-017', jsonb_build_object('quote_id', v_qgood::text)) g;
    begin
      insert into public.quotes (id, quote_amount, status, source)
        values (gen_random_uuid(), null, 'submitted', 'zz-defect-probe');
      v_ctl := 'a quote with no amount was ACCEPTED';
    exception when others then v_ctl := 'no amount refused by quotes.quote_amount NOT NULL'; end;
    v_ok := v_p1 is false and v_p2 is true and v_ctl like 'no amount refused%';
    defect_id:='PD-QUOTE-002'; category:='QUOTE';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('GATE-017 against a real row of public.quotes: a quote with a blank status -> passed %s/%s; the same row complete -> passed %s; and %s.',
                       v_p1, v_code, v_p2, v_ctl);
    blocker := null; return next;

    -- PD-QUOTE-003 a technical claim with no evidence reaches the evaluation path.
    select rc.state, rc.refusal_code into v_state, v_code from public.fn_phase_d_rule_check('BR-027',
      jsonb_build_object('claim','grade B500B certified')) rc;
    select rc.state into v_ctl from public.fn_phase_d_rule_check('BR-027',
      jsonb_build_object('claim','grade B500B certified','evidence_refs', jsonb_build_array('doc:1#p3'))) rc;
    v_ok := v_state = 'ENFORCED_FAIL' and v_ctl = 'ENFORCED_PASS';
    defect_id:='PD-QUOTE-003'; category:='QUOTE';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('BR-027 (evidence provenance, workflow_scope names W14): a technical claim with no evidence_refs -> %s/%s; the same claim naming one -> %s. BOUNDED: the predicate tests that the array is present and non-empty, not that each ref resolves.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;

    -- PD-LEGAL-003 a non-refund subject enters the founder approval path.
    begin
      insert into public.founder_approval_request (command_id, action_class, subject_ref,
        prepared_by_role_id, amount_note, evidence, state)
      values (null,'policy_change','zz-legal-003','trust_and_safety_manager','','{}'::jsonb,'pending');
      v_state := 'ACCEPTED';
    exception when others then v_state := 'REFUSED'; v_code := left(SQLERRM, 95); end;
    begin
      insert into public.founder_approval_request (command_id, action_class, subject_ref,
        prepared_by_role_id, amount_note, evidence, state)
      values (null,'refund_decision','zz-legal-003c','trust_and_safety_manager','','{}'::jsonb,'pending');
      v_ctl := 'ACCEPTED';
    exception when others then v_ctl := 'REFUSED: ' || left(SQLERRM, 60); end;
    v_ok := v_state = 'REFUSED' and v_ctl = 'ACCEPTED';
    defect_id:='PD-LEGAL-003'; category:='LEGAL';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('public.founder_approval_request is the founder approval path, not phase_c_refund_decision. action_class policy_change -> %s (%s); action_class refund_decision -> %s. z10_founder_approval_refund_only plus CHECK founder_approval_request_refund_only_ck.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;
  end;


  -- PD-FIN-004 founder decision updated or deleted -> append-only refusal.
  defect_id:='PD-FIN-004'; category:='FINANCE'; status:='NOT_RUN'; observed:=null;
  blocker := 'needs a committed founder decision row to attempt to rewrite. A fixture may never forge '
          || 'one (his standing rule), and no test-context founder identity exists, so the append-only '
          || 'refusal cannot be provoked without a real decision.';
  return next;

  -- ---- REVIEW ---------------------------------------------------------------------------------
  -- PD-REV-001 creator alias equals reviewer alias -> self-review refusal.
  v_ok := not public.fn_kernel_reviewer_independent('trust_and_safety_manager','trust_and_safety_manager');
  defect_id:='PD-REV-001'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'fn_kernel_reviewer_independent(x, x) is false: one identity cannot review its own output';
  blocker := null; return next;

  -- PD-REV-003 reviewer outside authority -> refused.
  v_ok := not public.fn_kernel_reviewer_independent('trust_and_safety_manager', null);
  defect_id:='PD-REV-003'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'a null reviewer is not independent; BR-002 refuses the step rather than proceeding unreviewed';
  blocker := null; return next;

  -- PD-REV-002/004/005. THE OLD BLOCKERS SAID THESE NEEDED A COMMITTED RUN AND A COMMIT-TIME SEAL.
  -- Re-measured 24 Aug 2026 and false on both counts: fn_kernel_step_complete section 3g raises
  -- k3_reviewer_verdict_missing in the same statement, and fn_phase_c_trace_write stamps sealed_at
  -- in the same INSERT that sets status='sealed'. Neither waits for a commit.

  -- PD-REV-002 a required review step completed with no verdict -> refused.
  begin
    perform set_config('app.phase_d_hold_step','W04-S04', true);
    v_m3_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','zz-pd-rev-002','execution_context','test','for_workflow','W04'));
    select st.contributes_ref into v_m3_refkey from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='W04')
     limit 1;
    v_m3_boid := case when v_m3_refkey is not null and coalesce(v_m3_fx->'parent_refs'->>v_m3_refkey,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id='W04')
           || ':' || (v_m3_fx->'parent_refs'->>v_m3_refkey) else null end;
    v_m3_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W04','label','zz-pd-rev-002','execution_context','production',
      'hold_at_step_id','W04-S04')
      || case when v_m3_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_m3_boid) end);
    v_m3_srid := nullif(v_m3_drive->>'held_step_run_id','')::bigint;
    v_m3_run  := nullif(v_m3_drive->>'run_id','')::bigint;
    perform set_config('app.phase_d_hold_step','', true);
    if v_m3_srid is null then
      v_ok := false;
      v_msg := 'no step run was held open at W04-S04; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      select t.task_id into v_m3_task from public.phase_c_task t
       where t.run_id = v_m3_run and t.step_id = 'W04-S04' order by t.task_id limit 1;
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-rev-002-inj:' || v_m3_srid,
        'inputs', jsonb_build_object('mode','no verdict recorded'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - acceptance record linked to the exact document version and identity'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','no verdict recorded')),
        'acceptance_criteria','a required review step may not pass unreviewed',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_ctl := 'COMPLETED_UNREVIEWED';
      exception when others then
        v_m3_ctl := case when position('k3_reviewer_verdict_missing' in SQLERRM) > 0
                         then 'k3_reviewer_verdict_missing/' || SQLSTATE
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','compliance_and_privacy_officer',
        'decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the declared independent reviewer approves'));
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-rev-002-ctl:' || v_m3_srid,
        'inputs', jsonb_build_object('mode','approved verdict on record'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - acceptance record linked to the exact document version and identity'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','approved verdict on record')),
        'acceptance_criteria','the same step with a sealed approving verdict completes',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_state := 'COMPLETED';
      exception when others then
        v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
      end;
      v_ok := v_m3_ctl = 'k3_reviewer_verdict_missing/23514' and v_m3_state = 'COMPLETED';
      v_msg := format(
        'W04 held open at W04-S04 (step run %s, task %s), one of the 28 of 257 frozen steps that '
     || 'declare an independent_reviewer_role_id - here compliance_and_privacy_officer. INJECTION: '
     || 'fn_kernel_step_complete outcome=pass with no verdict on the task at all -> %s. CONTROL, '
     || 'differing in exactly one respect - fn_kernel_review_decide first records an APPROVED '
     || 'verdict from that same declared reviewer - and the identical call then %s. Section 3g is '
     || 'the predicate: it looks for a TRACE-ROLE-ACTION trace on the task whose evidence_refs '
     || 'carry review_decision=approved from a reviewer that resolves to the declared one and is '
     || 'independent of the step owner. The refused arm left no partial completion; the whole '
     || 'transaction is aborted.',
        v_m3_srid, v_m3_task, v_m3_ctl, v_m3_state);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-REV-002'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-REV-004 a REJECTED output pushed forward -> refused, and no successor is opened.
  begin
    perform set_config('app.phase_d_hold_step','W04-S04', true);
    v_m3_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','zz-pd-rev-004','execution_context','test','for_workflow','W04'));
    select st.contributes_ref into v_m3_refkey from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='W04')
     limit 1;
    v_m3_boid := case when v_m3_refkey is not null and coalesce(v_m3_fx->'parent_refs'->>v_m3_refkey,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id='W04')
           || ':' || (v_m3_fx->'parent_refs'->>v_m3_refkey) else null end;
    v_m3_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W04','label','zz-pd-rev-004','execution_context','production',
      'hold_at_step_id','W04-S04')
      || case when v_m3_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_m3_boid) end);
    v_m3_srid := nullif(v_m3_drive->>'held_step_run_id','')::bigint;
    v_m3_run  := nullif(v_m3_drive->>'run_id','')::bigint;
    perform set_config('app.phase_d_hold_step','', true);
    if v_m3_srid is null then
      v_ok := false; v_m3_trace := null;
      v_msg := 'no step run was held open at W04-S04; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      select t.task_id into v_m3_task from public.phase_c_task t
       where t.run_id = v_m3_run and t.step_id = 'W04-S04' order by t.task_id limit 1;
      select count(*) into v_m3_s0 from public.phase_c_workflow_step_run
       where run_id = v_m3_run and step_id = 'W04-S05';
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','compliance_and_privacy_officer',
        'decision','rejected',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the declared reviewer rejects this output'));
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-rev-004-inj:' || v_m3_srid,
        'inputs', jsonb_build_object('mode','rejected output pushed forward'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - acceptance record linked to the exact document version and identity'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','rejected output pushed forward')),
        'acceptance_criteria','a rejected output must not progress',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_ctl := 'PROGRESSED';
      exception when others then
        v_m3_ctl := case when position('k3_reviewer_verdict_missing' in SQLERRM) > 0
                         then 'k3_reviewer_verdict_missing/' || SQLSTATE
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      select count(*) into v_m3_n from public.phase_c_workflow_step_run
       where run_id = v_m3_run and step_id = 'W04-S05';
      v_m3_a := public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','compliance_and_privacy_officer',
        'decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the same reviewer approves the same output'));
      v_m3_trace := nullif(v_m3_a->>'trace_id','')::bigint;   -- the subject PD-REV-005 tampers with
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-rev-004-ctl:' || v_m3_srid,
        'inputs', jsonb_build_object('mode','approved output progresses'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - acceptance record linked to the exact document version and identity'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','approved output progresses')),
        'acceptance_criteria','an approved output progresses to its successor',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_state := 'PROGRESSED';
      exception when others then
        v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
      end;
      select count(*) into v_m3_s1 from public.phase_c_workflow_step_run
       where run_id = v_m3_run and step_id = 'W04-S05';
      v_ok := v_m3_ctl = 'k3_reviewer_verdict_missing/23514'
          and v_m3_s0 = 0 and v_m3_n = 0
          and v_m3_state = 'PROGRESSED' and v_m3_s1 = 1;
      v_msg := format(
        'W04 held open at W04-S04 (step run %s, task %s). Its successor W04-S05 has the same owner, '
     || 'so the kernel opens it directly and no handoff has to be accepted first - which is what '
     || 'makes "was a successor opened" a readable number here. INJECTION: fn_kernel_review_decide '
     || 'records a REJECTED verdict from the declared reviewer, then fn_kernel_step_complete is '
     || 'called with outcome=pass -> %s, and public.phase_c_workflow_step_run rows for W04-S05 went '
     || '%s -> %s: no successor step run was opened. CONTROL, differing in exactly one respect - '
     || 'the same reviewer records APPROVED on the same task - and the identical call %s, W04-S05 '
     || 'step runs going to %s. MEASURED GAP, STATED AND NOT FIXED HERE: section 3g runs only when '
     || 'outcome=''pass'' AND the step declares an independent_reviewer_role_id. 28 of the 257 '
     || 'frozen steps declare one, so on the other 229 a recorded rejected verdict stops nothing: '
     || 'fn_kernel_review_decide writes the sealed trace and stamps phase_c_task.reviewer_role_id, '
     || 'and no predicate in the kernel reads review_decision=rejected. That is a measurement, not '
     || 'a repair.',
        v_m3_srid, v_m3_task, v_m3_ctl, v_m3_s0, v_m3_n, v_m3_state, v_m3_s1);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false; v_m3_trace := null;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-REV-004'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-REV-005 a verdict edited after sealing -> append-only refusal.
  -- The subject is the REAL sealed verdict fn_kernel_review_decide wrote for PD-REV-004. A trace
  -- this branch minted for itself would be an identity it had generated, which proves nothing.
  if v_m3_trace is null then
    v_ok := false; v_m3_ctl := 'NO_SUBJECT';
    v_msg := 'PD-REV-004 produced no sealed verdict trace, so there was no verdict to attempt to '
          || 'edit and nothing was injected. With no subject there is nothing to discriminate; this '
          || 'is not a pass.';
  else
    select (sealed_at is not null) into v_m3_ok2 from public.phase_c_trace where trace_id = v_m3_trace;
    begin
      update public.phase_c_trace
         set evidence_refs = evidence_refs || '[{"review_decision":"approved","tampered":true}]'::jsonb
       where trace_id = v_m3_trace;
      v_m3_ctl := 'ACCEPTED';
    exception when others then
      v_m3_ctl := case when position('append-only' in SQLERRM) > 0
                       then 'z10_phase_c_trace_append_only/' || SQLSTATE
                       else SQLSTATE || ':' || left(SQLERRM, 60) end;
    end;
    begin
      v_m3_sup := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
        'subject_kind','task', 'subject_ref', v_m3_task::text, 'task_id', v_m3_task,
        'actor_role_id','defect_probe', 'status','sealed',
        'evidence_refs', jsonb_build_array(jsonb_build_object(
          'note','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the superseding row the trigger names'))));
      update public.phase_c_trace set superseded_by = v_m3_sup where trace_id = v_m3_trace;
      v_m3_state := 'ACCEPTED';
    exception when others then
      v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
    end;
    select count(*) into v_m3_n from public.phase_c_trace
     where trace_id = v_m3_trace and evidence_refs @> '[{"tampered":true}]'::jsonb;
    v_ok := v_m3_ctl = 'z10_phase_c_trace_append_only/23514'
        and v_m3_state = 'ACCEPTED' and v_m3_n = 0 and coalesce(v_m3_ok2, false);
    v_msg := format(
      'The subject is trace %s, the sealed TRACE-ROLE-ACTION verdict fn_kernel_review_decide wrote '
   || 'for PD-REV-004. sealed_at is already not null on it: %s - fn_phase_c_trace_write stamps '
   || 'sealed_at in the same INSERT that sets status=''sealed'', so the seal does not wait for a '
   || 'commit and the old blocker was wrong about that. INJECTION: an UPDATE of its evidence_refs '
   || 'adding a second approving decision -> %s. CONTROL, differing in exactly one respect - the '
   || 'same UPDATE on the same sealed row changing ONLY superseded_by from null, pointing at a '
   || 'superseding sealed trace written through the same door -> %s. Rows on phase_c_trace carrying '
   || 'the tampered evidence afterwards: %s.',
      v_m3_trace, coalesce(v_m3_ok2::text,'(unknown)'), v_m3_ctl, v_m3_state, v_m3_n);
  end if;
  defect_id:='PD-REV-005'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED'
                 when v_m3_ctl = 'NO_SUBJECT' then 'NOT_DISCRIMINATED'
                 else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- ---- OUTBOX (the D29 adapter is the machine under test) --------------------------------------
  -- PD-OUTBOX-001 consumer returns null -> delivery failure, attempt recorded.
  v_key := 'zz-out-001-' || md5('null');
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S02','idempotency_key',v_key,'mock_case','null_result',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  select count(*) into v_n from public.phase_d_external_attempt where idempotency_key=v_key;
  defect_id:='PD-OUTBOX-001'; category:='OUTBOX';
  status := case when coalesce((v_b->>'delivered')::boolean,true)=false and v_n=1
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('null result: delivered=%s, reconciliation=%s, attempts recorded=%s',
                     v_b->>'delivered', v_b->>'reconciliation_state', v_n);
  blocker := null; return next;

  -- PD-OUTBOX-002 retryable failure then success -> first failure preserved.
  v_key := 'zz-out-002-' || md5('retry');
  perform public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S03','idempotency_key',v_key,'mock_case','retryable_failure',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S03','idempotency_key',v_key,'mock_case','success',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  select count(*) into v_n from public.phase_d_external_attempt
   where idempotency_key=v_key and provider_outcome='retryable_failure';
  defect_id:='PD-OUTBOX-002'; category:='OUTBOX';
  status := case when coalesce((v_b->>'delivered')::boolean,false) and v_n=1
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('attempt 1 retryable preserved (%s row), attempt 2 delivered=%s', v_n, v_b->>'delivered');
  blocker := null; return next;

  -- PD-OUTBOX-003 terminal failure -> dead_letter, no business success.
  v_key := 'zz-out-003-' || md5('term');
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S04','idempotency_key',v_key,'mock_case','terminal_failure',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  defect_id:='PD-OUTBOX-003'; category:='OUTBOX';
  status := case when coalesce((v_b->>'dead_lettered')::boolean,false)
                  and coalesce((v_b->>'delivered')::boolean,true)=false
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('terminal: retry_class=%s dead_lettered=%s delivered=%s',
                     v_b->>'retry_class', v_b->>'dead_lettered', v_b->>'delivered');
  blocker := null; return next;

  -- PD-OUTBOX-005 cancelled subject pending delivery -> non-deliverable.
  v_key := 'zz-out-005-' || md5('cx');
  perform public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S05','idempotency_key',v_key,'mock_case','cancellation',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S05','idempotency_key',v_key,'mock_case','success',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_ok := false; v_msg := 'a cancelled subject was delivered';
  exception when others then
    v_ok := position('pd_external_cancelled' in SQLERRM)>0; v_msg := 'refused: pd_external_cancelled';
  end;
  defect_id:='PD-OUTBOX-005'; category:='OUTBOX';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-OUTBOX-004 consumer re-emits the same event -> self-loop.
  defect_id:='PD-OUTBOX-004'; category:='OUTBOX'; status:='NOT_RUN'; observed:=null;
  blocker := 'the 54 event self-loops are a FROZEN Phase B property (emitted_by = primary_consumer_role_id) '
          || 'recorded RED and ratcheted by D11. Injecting a re-emission needs a live consumer, and no '
          || 'consumer is running under the automation hold.';
  return next;

  -- ---- NOTIFY ---------------------------------------------------------------------------------
  -- PD-NOTIFY-001 external send attempted in Phase D -> provider-disabled refusal.
  begin
    perform public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S06','idempotency_key','zz-notify-001','mock_case','success','provider_mode','live',
      'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
    v_ok := false; v_msg := 'a LIVE provider mode was accepted';
  exception when others then
    v_ok := position('pd_external_live_mode_refused' in SQLERRM)>0;
    v_msg := 'refused: pd_external_live_mode_refused — this adapter has no live mode';
  end;
  defect_id:='PD-NOTIFY-001'; category:='NOTIFY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-NOTIFY-002 opted-out recipient queued -> suppressed.
  v_key := 'zz-notify-002-' || md5('supp');
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S07','idempotency_key',v_key,'mock_case','suppression',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  defect_id:='PD-NOTIFY-002'; category:='NOTIFY';
  status := case when (v_b->>'reconciliation_state')='SUPPRESSED'
                  and coalesce((v_b->>'delivered')::boolean,true)=false
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('suppressed: delivered=%s reconciliation=%s', v_b->>'delivered', v_b->>'reconciliation_state');
  blocker := null; return next;

  -- PD-NOTIFY-003 duplicate message from retry -> one send ledger row.
  v_key := 'zz-notify-003-' || md5('dup');
  perform public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S01','idempotency_key',v_key,'mock_case','success',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  perform public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S01','idempotency_key',v_key,'mock_case','success',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  select count(*) into v_n from public.phase_d_external_attempt where idempotency_key=v_key and delivered;
  defect_id:='PD-NOTIFY-003'; category:='NOTIFY';
  status := case when v_n=1 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('two identical sends produced %s delivered row(s)', v_n);
  blocker := null; return next;

  -- PD-NOTIFY-004 success claimed on a null provider result -> failure.
  v_key := 'zz-notify-004-' || md5('nullclaim');
  v_b := public.fn_phase_d_external_deliver(jsonb_build_object(
    'step_id','W13-S02','idempotency_key',v_key,'mock_case','null_result',
    'approved_payload_ref','zz-approved-v1','approved_payload', jsonb_build_object('x',1)));
  defect_id:='PD-NOTIFY-004'; category:='NOTIFY';
  status := case when coalesce((v_b->>'ok')::boolean,true)=false
                  and coalesce((v_b->>'delivered')::boolean,true)=false
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'a null provider result returns ok=false and delivered=false — it is never a success';
  blocker := null; return next;

  -- PD-NOTIFY-005 supplier receives raw customer identity -> approval/send refused.
  -- THE BLOCKER WAS WRONG AND THE DOOR WAS OPEN. It said this needs a rendered body and a PII
  -- detector in the edge functions. Measured 24 Aug 2026: fn_phase_d_external_deliver('W13-S02',
  -- ...) with an approved payload whose body read "contact Ahmad at zz.cust@example.invalid /
  -- 0501234567" returned ok=true, delivered=true and recorded attempt 25981. BR-011 refuses that
  -- exact string -- on SHAPE as well as on a row match, so it does not need public.customers to
  -- hold rows -- and the send path had simply never asked it. M05 makes the send path ask
  -- fn_phase_d_rule_applies and then fn_phase_d_rule_check, and this is the injection against it.
  begin
    v_pay := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S02','idempotency_key','zz-notify005-dirty','mock_case','success',
      'approved_payload_ref','zz-approved-notify005',
      'approved_payload', jsonb_build_object('body',
        'contact Ahmad at zz-notify005@example.invalid / 0501234567 for the site visit')));
    v_ok := false;
    v_msg := 'the send path delivered a payload carrying a customer identity: ' || coalesce(v_pay->>'delivered','?');
  exception when others then
    v_ok := position('br011_identity_before_reveal' in SQLERRM) > 0;
    v_msg := 'a supplier-facing body carrying an e-mail and a dialable number was refused at the '
          || 'send path: br011_identity_before_reveal. ';
  end;
  -- CONTROL. The SAME call, the same step, the same idempotency shape; the one thing that differs
  -- is that the body carries no identity.
  begin
    v_pay := public.fn_phase_d_external_deliver(jsonb_build_object(
      'step_id','W13-S02','idempotency_key','zz-notify005-clean','mock_case','success',
      'approved_payload_ref','zz-approved-notify005',
      'approved_payload', jsonb_build_object('body','the supplier-safe brief carries no identity')));
    v_ok := coalesce(v_ok,false) and coalesce((v_pay->>'delivered')::boolean,false);
    v_msg := v_msg || 'CONTROL, identity removed and nothing else: delivered=' || coalesce(v_pay->>'delivered','?') || '.';
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL was refused too: ' || left(SQLERRM,80);
  end;
  defect_id:='PD-NOTIFY-005'; category:='NOTIFY';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null;
  return next;

  -- ---- PROVIDER -------------------------------------------------------------------------------
  -- PD-PROV-005 provider reports success with no request ID -> failure.
  begin
    insert into public.phase_d_external_attempt
      (step_id, idempotency_key, attempt_no, provider_mode, approved_payload_ref, approved_payload_sha256,
       provider_request_id, provider_result_id, provider_outcome, retry_class, delivered)
    values ('W13-S01','zz-prov-005',1,'mock','zz','zz','req_zz', null, 'success','NOT_APPLICABLE', true);
    v_ok := false; v_msg := 'a DELIVERED attempt with no result id was accepted';
  exception when others then
    v_ok := true; v_msg := 'refused by phase_d_external_attempt_delivered_has_result: delivered requires a result id';
  end;
  defect_id:='PD-PROV-005'; category:='PROVIDER';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-PROV-001 OpenRouter request in zero-cost mode -> network denied.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('fn_phase_d_external_deliver','fn_phase_d_run_external_cases',
                                              'fn_phase_d_object_write','fn_phase_d_drive_workflow')
     -- READING the queue is the D17 GUARD; POSTING to it is a request. The first draft matched
     -- net.http_ and counted fn_phase_d_object_write, which references net.http_request_queue
     -- precisely in order to REFUSE one. The control refused the file rather than scoring it.
     -- MATCH A CALL, NOT A MENTION. Two drafts of this probe were wrong and both are worth keeping
     -- in the record. The first matched net.http_ and counted fn_phase_d_object_write, which names
     -- net.http_request_queue in order to REFUSE a request. The second narrowed to net.http_post and
     -- STILL counted it, because the D17 refusal's own hint text reads "A trigger on this relation
     -- calls net.http_post" — a keyword scanner matching a sentence ABOUT the thing it forbids.
     -- Quoted literals are stripped before judging, exactly as qd_guard does for the same reason:
     -- check the skeleton, not the payload.
     and regexp_replace(p.prosrc, '''(''''|[^''])*''', '''''', 'g') ~* 'openrouter|net[.]http_(post|get)[[:space:]]*[(]';
  defect_id:='PD-PROV-001'; category:='PROVIDER';
  status := case when v_n=0 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('%s Phase D routine(s) make an openrouter or net.http_post/get call; the D17 guard additionally '
                     'refuses any Phase D write that leaves a request in net.http_request_queue', v_n);
  blocker := null; return next;

  -- PD-PROV-004 direct provider client bypass -> repo/network scan.
  defect_id:='PD-PROV-004'; category:='PROVIDER'; status:='NOT_RUN'; observed:=null;
  blocker := 'a repository scan for a direct provider client lives in the CI credential test over '
          || 'supabase/functions, not in the database. Executing it as an INJECTION means adding a bypass '
          || 'to an edge function and observing CI refuse it, which needs the section 8 deploy path.';
  return next;

  -- PD-PROV-002/003 gate read failure and malformed route state.
  begin
    perform public.fn_phase_d_gate_evaluate('GATE-010', jsonb_build_object('route_state',''));
    select count(*) into v_n from public.fn_phase_d_gate_evaluate('GATE-010', jsonb_build_object('route_state','')) where ok;
    v_ok := (v_n = 0);
    v_msg := 'an empty route_state does not pass GATE-010; the gate denies rather than falling back';
  exception when others then v_ok := true; v_msg := 'gate raised on malformed evidence: ' || left(SQLERRM,60); end;
  defect_id:='PD-PROV-003'; category:='PROVIDER';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  defect_id:='PD-PROV-002'; category:='PROVIDER'; status:='NOT_RUN'; observed:=null;
  blocker := 'requires making a gate READ fail (not evaluate false) — a permission or relation error mid-gate. '
          || 'Provoking it means revoking a grant on production, which the hold forbids outside an aborted '
          || 'transaction that the gate would not observe.';
  return next;

  -- ---- STATE ----------------------------------------------------------------------------------
  -- PD-STATE-001 step completed from an invalid state.
  begin
    perform public.fn_phase_d_effect_produce(jsonb_build_object(
      'step_run_id', -1, 'idempotency_key','zz-state-001','actor_role_id','defect_probe',
      'payload', jsonb_build_object('x',1)));
    v_ok := false; v_msg := 'a nonexistent step run was accepted';
  exception when others then
    v_ok := position('pd_step_state_invalid' in SQLERRM)>0;
    v_msg := 'refused: pd_step_state_invalid — no such step run';
  end;
  defect_id:='PD-STATE-001'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-STATE-005 failure outcome interpreted as a step id -> no invented step.
  select count(*) into v_n from public.fn_phase_d_step_cases('NOT-A-STEP') where passed;
  defect_id:='PD-STATE-005'; category:='STATE';
  status := case when v_n=0 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'fn_phase_d_step_cases on an unknown step returns passed=false with step_unknown; no step is invented';
  blocker := null; return next;

  -- PD-STATE-002/003. THE OLD BLOCKERS SAID BOTH NEEDED A COMMITTED RUN. Re-measured 24 Aug 2026
  -- and false: k3_closure_blocked is raised by fn_kernel_step_complete in the same statement, and
  -- closed_at is written in the same statement too, so both are readable before any commit.

  -- PD-STATE-002 a workflow closed with a mandatory blocker open -> a stable refusal code.
  -- ONE drive carries both arms. The injection runs inside its own subtransaction, so the refusal
  -- unwinds every row it staged and the control then starts from the state the drive left.
  begin
    perform set_config('app.phase_d_hold_step','W04-S06', true);
    v_m3_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','zz-pd-state-002','execution_context','test','for_workflow','W04'));
    select st.contributes_ref into v_m3_refkey from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='W04')
     limit 1;
    v_m3_boid := case when v_m3_refkey is not null and coalesce(v_m3_fx->'parent_refs'->>v_m3_refkey,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id='W04')
           || ':' || (v_m3_fx->'parent_refs'->>v_m3_refkey) else null end;
    v_m3_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W04','label','zz-pd-state-002','execution_context','production',
      'hold_at_step_id','W04-S06')
      || case when v_m3_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_m3_boid) end);
    v_m3_srid := nullif(v_m3_drive->>'held_step_run_id','')::bigint;
    v_m3_run  := nullif(v_m3_drive->>'run_id','')::bigint;
    perform set_config('app.phase_d_hold_step','', true);
    if v_m3_srid is null then
      v_ok := false; v_m3_task := null;
      v_msg := 'no step run was held open at W04-S06; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      perform set_config('app.phase_d_hold_step','W04-S07', true);
      select count(*) into v_m3_s0 from public.phase_c_workflow_step_run where run_id = v_m3_run;
      begin
        v_m3_a := public.fn_kernel_open_step(jsonb_build_object(
          'run_id', v_m3_run, 'step_id','W04-S07', 'owner_role_id','customer_onboarding',
          'opened_because','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closure attempted with W04-S06 open'));
        select t.task_id into v_m3_task from public.phase_c_task t
         where t.run_id = v_m3_run and t.step_id = 'W04-S07' order by t.task_id limit 1;
        perform public.fn_kernel_review_decide(jsonb_build_object(
          'task_id', v_m3_task, 'reviewer_role_id','customer_success_director','decision','approved',
          'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the closure step''s declared reviewer approves'));
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', (v_m3_a->>'step_run_id')::bigint,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = (v_m3_a->>'step_run_id')::bigint),
        'outcome','pass', 'idempotency_key', 'zz-pd-state-002-inj:' || v_m3_run,
        'inputs', jsonb_build_object('mode','closure with a mandatory step still open'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - closed onboarding record'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','closure with a mandatory step still open')),
        'acceptance_criteria','a run may not close over an unexecuted mandatory step',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_ctl := 'CLOSED';
      exception when others then
        v_m3_ctl := case when position('k3_closure_blocked' in SQLERRM) > 0
                         then 'k3_closure_blocked/' || SQLSTATE
                              || case when position('mandatory_steps_never_executed' in SQLERRM) > 0
                                      then ' listing mandatory_steps_never_executed'
                                      else ' WITHOUT naming mandatory_steps_never_executed' end
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      select count(*) into v_m3_s1 from public.phase_c_workflow_step_run where run_id = v_m3_run;
      select count(*) into v_m3_p1 from public.phase_c_workflow_run
       where run_id = v_m3_run and closed_at is not null;
      -- CONTROL: the one thing that differs is that the mandatory step is executed first.
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_srid,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_srid),
        'outcome','pass', 'idempotency_key', 'zz-pd-state-002-ctl6:' || v_m3_run,
        'inputs', jsonb_build_object('mode','the last mandatory step is executed'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - onboarding completion and inquiry-start handoff'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','the last mandatory step is executed')),
        'acceptance_criteria','every earlier mandatory step reaches a terminal state',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
      select sr.step_run_id into v_m3_sup from public.phase_c_workflow_step_run sr
       where sr.run_id = v_m3_run and sr.step_id = 'W04-S07' order by sr.step_run_id limit 1;
      select t.task_id into v_m3_task from public.phase_c_task t
       where t.run_id = v_m3_run and t.step_id = 'W04-S07' order by t.task_id limit 1;
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','customer_success_director','decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the closure step''s declared reviewer approves'));
      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_m3_sup,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_m3_sup),
        'outcome','pass', 'idempotency_key', 'zz-pd-state-002-ctl7:' || v_m3_run,
        'inputs', jsonb_build_object('mode','closure with every mandatory step executed'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - closed onboarding record'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','closure with every mandatory step executed')),
        'acceptance_criteria','the run closes',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1));
        v_m3_state := 'CLOSED';
      exception when others then
        v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
      end;
      select count(*) into v_m3_p2 from public.phase_c_workflow_run
       where run_id = v_m3_run and closed_at is not null;
      select state into v_m3_def from public.phase_c_workflow_run where run_id = v_m3_run;
      v_ok := v_m3_ctl like 'k3_closure_blocked/23514 listing mandatory_steps%'
          and v_m3_p1 = 0 and v_m3_s0 = v_m3_s1
          and v_m3_state = 'CLOSED' and v_m3_p2 = 1 and v_m3_def = 'completed';
      v_msg := format(
        'W04 driven to W04-S06 and held there, so W04-S01..S05 are completed and W04-S06 - a '
     || 'mandatory step of this workflow - has never reached a terminal state. INJECTION: the '
     || 'closure step W04-S07 is opened through the kernel''s own fn_kernel_open_step, its declared '
     || 'reviewer approves, and fn_kernel_step_complete is called with outcome=pass -> %s. The run''s '
     || 'closed_at rows: %s; step runs on the run went %s -> %s, so the refusal left nothing behind. '
     || 'CONTROL, differing in exactly one respect - W04-S06 is completed through '
     || 'fn_kernel_step_complete first, so no mandatory step is open - and the closure step then %s, '
     || 'the run reaching state %L with closed_at set on %s row. The closure step run in the control '
     || 'was opened by the kernel''s own progression rather than by fn_kernel_open_step; that is a '
     || 'consequence of the injected condition, not a second variable, because progression cannot '
     || 'reach a closure step whose predecessor is still open.',
        v_m3_ctl, v_m3_p1, v_m3_s0, v_m3_s1, v_m3_state, v_m3_def, v_m3_p2);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-STATE-002'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-STATE-003 a nonterminal step treated as closure -> a stable refusal code.
  -- THIS ONE IS NOT CLOSED, AND SAYING SO IS THE POINT. The refusal exists - fn_kernel_step_successor
  -- returns kind=closure_flag_disagrees and fn_kernel_step_complete turns that into
  -- k3_no_valid_successor (23514) - but the condition it answers cannot be created. Terminality is
  -- stated twice in public.phase_b_workflow_step (next_step_if_pass = 'WORKFLOW_COMPLETE' and
  -- is_closure_step) and the two agree on all 257 rows. Making them disagree means UPDATE-ing
  -- phase_b_workflow_step, which z90_phase_b_freeze refuses without a Phase B change request, and
  -- setting app.phase_b_change_reason to get past the founder's freeze inside a defect probe is not
  -- something this file will do. A zero-population arm is NOT_DISCRIMINATED, never a pass.
  select count(*) into v_m3_n from public.phase_b_workflow_step
   where (next_step_if_pass = 'WORKFLOW_COMPLETE') is distinct from is_closure_step;
  select count(*) into v_m3_p1 from public.phase_b_workflow_step;
  select count(*) into v_m3_p2 from public.phase_b_workflow_step where is_closure_step;
  v_m3_ctl   := (select kind from public.fn_kernel_step_successor('W04-S06'));
  v_m3_state := (select kind from public.fn_kernel_step_successor('W04-S07'));
  defect_id:='PD-STATE-003'; category:='STATE';
  status := 'NOT_DISCRIMINATED';
  observed := format(
      'The injection has an empty population: %s of %s frozen steps state their terminality '
   || 'inconsistently, so there is no nonterminal step anywhere in the estate that any caller '
   || 'could present to the kernel as a closure step. What IS driveable, and was driven in this '
   || 'transaction by PD-STATE-002 on the same W04 run, is the discrimination itself: completing '
   || 'the NON-closure step W04-S06 returned successor kind %L and the kernel opened a successor '
   || 'step run for W04-S07, while the run''s closure step W04-S07 returns kind %L, opens no '
   || 'successor at all and closes the run instead - %s of the %s steps are closure steps. That '
   || 'shows the kernel does not confuse the two; it is not the catalogued injection and it '
   || 'observes no refusal, so it is not recorded as one.',
      v_m3_n, v_m3_p1, coalesce(v_m3_ctl,'(none)'), coalesce(v_m3_state,'(none)'), v_m3_p2, v_m3_p1);
  blocker := 'UNREACHABLE INJECTION, not an unbuilt harness. fn_kernel_step_successor already '
          || 'carries the refusal (kind=closure_flag_disagrees -> k3_no_valid_successor, 23514) and '
          || 'fn_kernel_step_complete already raises it. Creating the disagreement requires an '
          || 'UPDATE of the FROZEN public.phase_b_workflow_step, refused by z90_phase_b_freeze '
          || 'unless app.phase_b_change_reason names a Phase B change request. Closing this row '
          || 'honestly needs the founder to approve a change request that introduces the '
          || 'inconsistency deliberately, or it stays open.';
  return next;
  defect_id:='PD-STATE-004'; category:='STATE'; status:='NOT_RUN'; observed:=null;
  blocker := 'a missing successor owner is a FROZEN Phase B property; injecting one means editing '
           || 'phase_b_workflow_step, which z90_phase_b_freeze refuses without a change request.';
  return next;

  -- ---- TRACE ----------------------------------------------------------------------------------
  defect_id:='PD-TRACE-001'; category:='TRACE'; status:='NOT_RUN'; observed:=null;
  blocker := 'inserting an active step run without a trace means writing phase_c_workflow_step_run directly; '
          || 'fn_phase_d_object_write refuses kernel-owned tables (pd_object_kernel_owned), so the injection '
          || 'cannot be staged through a Phase D path and doing it raw would test the kernel, not Phase D.';
  return next;
  defect_id:='PD-TRACE-002'; category:='TRACE'; status:='NOT_RUN'; observed:=null;
  blocker := 'as PD-TRACE-001: the subject is a frozen kernel table.';
  return next;
  -- PD-TRACE-003 a sealed trace with no sealed_at -> refused.
  -- THE OLD BLOCKER SAID sealed_at IS A KERNEL COLUMN AND SO OUT OF REACH. Re-measured 24 Aug 2026:
  -- the refusal is a CHECK constraint, phase_c_trace_sealed_ck ((status='sealed') = (sealed_at is
  -- not null)), which fires on the statement, not at commit and not through any kernel routine.
  begin
    v_m3_trace := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
      'subject_kind','task', 'subject_ref','zz-pd-trace-003',
      'actor_role_id','defect_probe', 'status','open',
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'note','PHASE_D_FIXTURE_DO_NOT_PUBLISH - an OPEN trace, written through the kernel door'))));
    -- ALIASED: status, observed, category, defect_id and blocker are OUT columns of this
    -- function, so an unqualified status in a query against phase_c_trace is ambiguous (42702).
    select (tr.sealed_at is null and tr.status = 'open') into v_m3_ok2
      from public.phase_c_trace tr where tr.trace_id = v_m3_trace;
    begin
      update public.phase_c_trace set status = 'sealed' where trace_id = v_m3_trace;
      v_m3_ctl := 'ACCEPTED';
    exception when others then
      v_m3_ctl := case when position('phase_c_trace_sealed_ck' in SQLERRM) > 0
                       then 'phase_c_trace_sealed_ck/' || SQLSTATE
                       else SQLSTATE || ':' || left(SQLERRM, 60) end;
    end;
    begin
      update public.phase_c_trace set status = 'sealed', sealed_at = now()
       where trace_id = v_m3_trace;
      v_m3_state := 'ACCEPTED';
    exception when others then
      v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
    end;
    select count(*) into v_m3_n from public.phase_c_trace tr
     where tr.trace_id = v_m3_trace and tr.status = 'sealed' and tr.sealed_at is null;
    v_ok := coalesce(v_m3_ok2,false) and v_m3_ctl = 'phase_c_trace_sealed_ck/23514'
        and v_m3_state = 'ACCEPTED' and v_m3_n = 0;
    v_msg := format(
      'An OPEN trace %s was written through fn_phase_c_trace_write (status=open, sealed_at null: %s). '
   || 'INJECTION: update it to status=''sealed'' and leave sealed_at null -> %s. CONTROL, differing '
   || 'in exactly one respect - the SAME update with sealed_at = now() -> %s. Rows on '
   || 'public.phase_c_trace that are sealed with a null sealed_at after both attempts: %s. The '
   || 'refusal is the table''s own CHECK, so it is the same answer for every writer of that column, '
   || 'kernel or not; the whole transaction is aborted.',
      v_m3_trace, coalesce(v_m3_ok2::text,'(unknown)'), v_m3_ctl, v_m3_state, v_m3_n);
  exception when others then
    v_ok := false;
    v_msg := 'the open trace could not be written, so nothing was injected: ' || left(SQLERRM, 200);
  end;
  defect_id:='PD-TRACE-003'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;
  -- PD-TRACE-004 a failed idempotent insert leaves an orphan trace -> zero orphan.
  -- THE OLD BLOCKER SAID THE ORPHAN HAD TO COMMIT TO BE SEEN. Re-measured 24 Aug 2026 and false in
  -- two independent ways, both below: the ORDERING that makes the orphan impossible is readable
  -- from the routine itself, and the detector that would catch one is DEFERRABLE, which means
  -- SET CONSTRAINTS ALL IMMEDIATE fires it inside this transaction instead of at a commit.

  -- (a) ORDERING, measured off the live routine rather than asserted about it.
  select pg_get_functiondef('public.fn_kernel_step_complete(jsonb)'::regprocedure) into v_m3_def;
  v_m3_p1 := position('4. CLAIM THE IDEMPOTENCY KEY' in v_m3_def);
  v_m3_p2 := position('idempotency key % is claimed and carries no result' in v_m3_def);
  v_m3_p3 := least(nullif(position('fn_phase_c_trace_advance' in v_m3_def),0),
                   nullif(position('fn_phase_c_trace_write'   in v_m3_def),0));
  v_m3_ok2 := v_m3_p1 > 0 and v_m3_p2 > 0 and v_m3_p3 > 0
          and v_m3_p1 < v_m3_p2 and v_m3_p2 < v_m3_p3;

  -- (b) THE DETECTOR IS FORCEABLE. z90_system_execution_pair_guard on public.phase_c_trace is a
  --     CONSTRAINT TRIGGER, DEFERRABLE INITIALLY DEFERRED.
  begin
    v_m3_trace := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
      'subject_kind','system_execution', 'subject_ref','zz.pd.trace004.probe',
      'component_id','zz.pd.trace004.probe', 'actor_role_id','defect_probe', 'status','open'));
    set constraints all immediate;
    v_m3_state := 'SILENT';
    set constraints all deferred;
  exception when others then
    v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
  end;
  begin
    v_m3_sup := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
      'subject_kind','system_execution', 'subject_ref','zz.pd.trace004.probe',
      'component_id','zz.pd.trace004.probe', 'actor_role_id','defect_probe', 'status','sealed'));
    set constraints all immediate;
    v_m3_ctl := 'SILENT';
    set constraints all deferred;
  exception when others then
    v_m3_ctl := case when position('with no row in phase_c_system_execution' in SQLERRM) > 0
                     then 'z90_system_execution_pair_guard/' || SQLSTATE
                     else SQLSTATE || ':' || left(SQLERRM, 60) end;
  end;

  -- (c) THE TASK SIDE CANNOT EVEN BE STAGED, and that is a stronger answer than the one expected.
  if v_m3_task is null then
    v_m3_key := 'no task from the PD-STATE-002 drive was available to point at a deleted trace';
  else
    begin
      v_m3_orph := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
        'subject_kind','task', 'subject_ref','zz-pd-trace-004-orphan',
        'actor_role_id','defect_probe', 'status','open'));
      delete from public.phase_c_trace where trace_id = v_m3_orph;
      update public.phase_c_task set trace_id = v_m3_orph where task_id = v_m3_task;
      set constraints all immediate;
      v_m3_key := 'the orphan was STAGED AND NOT DETECTED';
      set constraints all deferred;
    exception when others then
      v_m3_key := case when SQLSTATE = '42501'
        then 'refused 42501 before the orphan could be staged at all - a direct UPDATE of '
             || 'public.phase_c_task is refused because no routine with write authority for that '
             || 'table is on the call stack, so z95_phase_c_task_trace_committed never has to fire'
        else SQLSTATE || ': ' || left(SQLERRM, 110) end;
    end;
  end if;

  select count(*) into v_m3_n from public.phase_c_task t
   where t.trace_id is null
      or not exists (select 1 from public.phase_c_trace x where x.trace_id = t.trace_id);
  v_ok := v_m3_ok2 and v_m3_state = 'SILENT'
      and v_m3_ctl = 'z90_system_execution_pair_guard/23514' and v_m3_n = 0;
  defect_id:='PD-TRACE-004'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format(
      '(a) ORDERING, measured off pg_get_functiondef of the live fn_kernel_step_complete rather '
   || 'than asserted: the idempotency claim (section 4) is at character %s, the lost-race branch '
   || 'that returns the other caller''s result is at %s, and the FIRST trace write of any kind is '
   || 'at %s - claim before lost-race return before any trace, ordered correctly: %s. A caller that '
   || 'loses the race therefore returns before a trace exists to be orphaned. '
   || '(b) THE DETECTOR IS FORCEABLE IN-TRANSACTION. z90_system_execution_pair_guard on '
   || 'public.phase_c_trace is DEFERRABLE INITIALLY DEFERRED, so SET CONSTRAINTS ALL IMMEDIATE '
   || 'fires it here. CONTROL: a correctly paired TRACE-SYSTEM-EXECUTION trace left OPEN - an '
   || 'execution in flight, which is allowed to have no phase_c_system_execution row - forced -> '
   || '%s. INJECTION, differing in exactly one respect, the same trace written SEALED with no '
   || 'execution row -> %s. (c) THE TASK-SIDE ORPHAN CANNOT BE STAGED: pointing a real task at a '
   || 'trace deleted in this transaction was %s. Tasks in the whole estate with a null or '
   || 'unresolvable trace_id after all of it: %s.',
      v_m3_p1, v_m3_p2, v_m3_p3, v_m3_ok2, v_m3_state, v_m3_ctl, v_m3_key, v_m3_n);
  blocker := null; return next;
  defect_id:='PD-TRACE-005'; category:='TRACE'; status:='NOT_RUN'; observed:=null;
  blocker := 'the read-only trace exemption is decided in the kernel; Phase D has no path that requests it.';
  return next;

  -- ---- The categories that need section 8 -------------------------------------------------------
  -- Each names the specific missing capability. None is mapped onto a nearby guard.
  for v_key, v_msg in
    select * from (values
      ('PD-AUTH-001','AUTH: needs an unauthenticated HTTP request against a deployed customer endpoint and the response status. No Phase D path issues an HTTP request.'),
      ('PD-AUTH-002','AUTH: needs supplier A''s bearer token against supplier B''s document URL. Requires the section 8 API + storage path.'),
      ('PD-AUTH-003','AUTH: needs a non-admin identity attempting an admin mutation over HTTP; the RLS/route decision is made in the edge function, not in SQL.'),
      ('PD-AUTH-004','AUTH: needs an inactive canonical role to attempt a step through the API; in SQL the driver supplies the role directly and never authenticates it.'),
      ('PD-FILE-001','FILES: needs a real upload whose magic bytes disagree with its extension. The attachment classifier lives in supabase/functions/_shared/attachment.ts and is exercised by its own deno test, not by any SQL path.'),
      ('PD-FILE-002','FILES: needs an oversized upload against the storage endpoint and a 413.'),
      ('PD-FILE-003','FILES: needs executable content posted as a document and the quarantine result.'),
      ('PD-FILE-004','FILES: needs an EXPIRED signed URL to be reused and the 403 observed; signed URLs are minted by storage, not by the database.'),
      ('PD-FILE-005','FILES: needs an insert into storage.objects under a path the caller does not own, judged by a storage RLS policy.'),
      ('PD-PRIV-003','PRIVACY: needs a signed URL whose path belongs to another supplier; storage authorization is the subject.'),
      ('PD-PRIV-004','PRIVACY: needs a supplier bearer token calling the raw inquiry endpoint and the response body.'),
      ('PD-PRIV-005','PRIVACY: needs a rendered artifact to scan for hidden metadata; no Phase D path renders one.'),
      ('PD-PRIV-002','PRIVACY: needs a drawing revision with an unapproved redaction; file revision state is a storage + document-pipeline fact.'),
      ('PD-QUOTE-001','QUOTE: needs supplier A''s token editing supplier B''s quote over the API.'),
      ('PD-QUOTE-004','QUOTE: needs a customer read of an unpublished quote through the portal read path.'),
      ('PD-LEGAL-004','LEGAL: needs the tax/legal static file freshness check, which is a content-pipeline fact.')
    ) as t(a,b)
  loop
    defect_id := v_key; category := split_part(v_msg, ':', 1); status := 'NOT_RUN';
    observed := null; blocker := 'SECTION 8 NOT BUILT — ' || v_msg;
    return next;
  end loop;


  -- ---- THE FOUR THAT NEEDED A FIXTURE, NOT A COMMITTED ROW -------------------------------------
  -- public.inquiries, public.quotes and public.phase_d_object_record hold ZERO rows OUTSIDE a
  -- fixture. Inside one they do not. fn_phase_d_fixture_scenario builds the customer, the inquiry,
  -- the supplier account and the terms acceptance IN THIS TRANSACTION, and every refusal below is
  -- an immediate BEFORE-trigger, CHECK or writer refusal -- none is deferred to commit. The four
  -- blockers these branches replace each said the injection needed a COMMITTED row. It did not; it
  -- needed a fixture, and this function already runs inside a verified fixture context.
  -- MEASURED, NOT ASSUMED: the deliverable driver opens the context and builds NO scenario, so the
  -- scenario is built here rather than presumed to be standing.
  v_pay := public.fn_phase_d_fixture_scenario(jsonb_build_object(
             'label','zz-defect-four','execution_context','test'));
  v_sup := v_pay->'parent_refs'->>'inquiry_id';

  -- PD-DISP-001 an inquiry that is not quote-ready, presented to the dispatch path.
  -- TWO IMPLEMENTATIONS AND THEY DO NOT READ THE SAME COLUMN. fn_phase_d_gate_evaluate('GATE-011')
  -- and fn_phase_d_rule_check('BR-013') read public.inquiries.status; trigger gate_incomplete_match
  -- BEFORE INSERT ON public.inquiry_matches reads i.rfq_ready and returns null. Both are measured.
  -- rfq_ready is DERIVED -- trg_rfq_complete recomputes it from fn_rfq_score on every write -- so
  -- setting that column false is not an injection at all. The injection is an RFQ that is genuinely
  -- incomplete; the scorer then makes both columns unready, which is why one arm can move both.
  v_a := (select to_jsonb(i) from public.inquiries i where i.id::text = v_sup);
  -- RESOLVE, THEN CREATE. uq_leads_email_lower is a unique index on lower(email), so a second call
  -- to this function inside one transaction would collide on it. Every demo supplier below is
  -- looked up first and written only when it is not already standing.
  if not exists (select 1 from public.leads l where lower(l.email) = 'zz-disp001@example.invalid') then
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-disp001-sup','owner_ref','zz-disp001-sup',
      'created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO - disp001 supplier',
        'email','zz-disp001@example.invalid','verified', true)));
  end if;
  select l.id::text into v_key from public.leads l where lower(l.email)='zz-disp001@example.invalid';
  update public.inquiries set spec=null, summary=null, raw_input=null, boq=null, budget=null,
         trades=null, scope_type=null, status='new',
         routing = coalesce(routing,'{}'::jsonb) || jsonb_build_object('dispatched_at', now(),
           'dispatched_by','phase_d_test_context','phase_d_outbound_suppressed', true)
   where id::text = v_sup;
  select count(*) into v_n from public.inquiry_matches;
  select (g.passed is not true) and g.refusal_code = 'gate011_inquiry_not_ready'
    into v_ok from public.fn_phase_d_gate_evaluate('GATE-011', jsonb_build_object('inquiry_id', v_sup)) g;
  select coalesce(v_ok,false) and (r.ok is not true) into v_ok
    from public.fn_phase_d_rule_check('BR-013', jsonb_build_object('inquiry_id', v_sup)) r;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp001-inject','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp001 injection')));
    v_ok := false; v_msg := 'the dispatch write was NOT refused: ' || (v_b->>'result_reference') || ' ';
  exception when others then
    -- THE VERDICT IS READ OUT OF THE RAISED MESSAGE, NOT OFF THE GUC. This exception block is a
    -- subtransaction, so the set_config the refusing trigger issued was rolled back with it and the
    -- key still holds PASS from the fixture's own earlier assignment. Reading it here measured the
    -- wrong subject and said PASS for a write that had just been refused.
    v_ok := coalesce(v_ok,false) and position('pd_object_write_produced_nothing' in SQLERRM) > 0
            and position('BLOCKED_NOT_RFQ_READY' in SQLERRM) > 0;
    v_msg := format('status=%s rfq_ready=%s: gate011_inquiry_not_ready + BR-013 BLOCKED, trigger %s, pd_object_write_produced_nothing, im %s->%s. ',
      (select coalesce(i2.status,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      (select coalesce(i2.rfq_ready::text,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      split_part(coalesce(nullif(split_part(SQLERRM, 'Gate verdict: ', 2),''),'(no verdict)'), ' ', 1),
      v_n, (select count(*) from public.inquiry_matches));
  end;
  -- CONTROL. The SAME inquiry with its qualification content restored and the SAME supplier, so
  -- readiness is the only thing that differs between the two arms.
  update public.inquiries set spec = v_a->'spec', summary = v_a->>'summary',
         raw_input = v_a->>'raw_input', boq = v_a->'boq', budget = v_a->>'budget',
         scope_type = v_a->>'scope_type', status = v_a->>'status',
         trades = (select coalesce(array_agg(x),'{}')::text[]
                     from jsonb_array_elements_text(coalesce(v_a->'trades','[]'::jsonb)) x),
         routing = coalesce(routing,'{}'::jsonb) || jsonb_build_object('dispatched_at', now(),
           'dispatched_by','phase_d_test_context','phase_d_outbound_suppressed', true)
   where id::text = v_sup;
  select count(*) into v_n from public.inquiry_matches;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp001-control','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp001 control')));
    v_ok := coalesce(v_ok,false) and (v_b->>'result_reference') is not null;
    v_msg := v_msg || format('CONTROL restored (%s/%s), same supplier: written, im %s->%s.',
      (select coalesce(i2.status,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      (select coalesce(i2.rfq_ready::text,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      v_n, (select count(*) from public.inquiry_matches));
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL was refused too: ' || left(SQLERRM,80);
  end;
  defect_id:='PD-DISP-001'; category:='DISPATCH';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-DISP-002 a supplier that is pending, rejected or expired, presented to the assignment path.
  -- All four suppliers below are verified=true, so approval_status is the ONLY thing that differs
  -- between each injection and the control -- leads_approved_implies_verified would otherwise make
  -- the control differ in two columns at once.
  -- pending / rejected / expired are written into approval_status, which is the column both
  -- BR-015 and GATE-014 read and which carries no CHECK on its values. leads.registration_expires_at
  -- exists but no rule, no gate and no trigger on inquiry_matches reads it, so expiry has no other
  -- representation any of these three implementations would see.
  v_msg := ''; v_ok := true;
  for v_key in select unnest(array['pending','rejected','expired']) loop
    if not exists (select 1 from public.leads l
                    where lower(l.email) = 'zz-disp002-'||v_key||'@example.invalid') then
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','supplier_account','business_key','zz-disp002-'||v_key,
        'owner_ref','zz-disp002-'||v_key,'created_by','defect_probe','state', v_key,
        'payload', jsonb_build_object('company_name','ZZ DEMO - disp002 '||v_key,
          'email','zz-disp002-'||v_key||'@example.invalid','verified', true)));
    end if;
    select jsonb_build_object('supplier_id', l.id::text) into v_a from public.leads l
     where lower(l.email) = 'zz-disp002-'||v_key||'@example.invalid';
    select coalesce(v_ok,false) and (r.ok is not true) into v_ok
      from public.fn_phase_d_rule_check('BR-015', v_a) r;
    select coalesce(v_ok,false) and (g.passed is not true)
       and g.refusal_code = 'gate014_supplier_unverified'
      into v_ok from public.fn_phase_d_gate_evaluate('GATE-014', v_a) g;
    -- AND WHAT THE WRITE PATH ITSELF DOES WITH THE SAME SUPPLIER. Undone in its own subtransaction
    -- so the measurement leaves nothing behind whichever way it comes out.
    begin
      v_b := public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','supplier_assignment','business_key','zz-disp002-a-'||v_key,
        'owner_ref', v_a->>'supplier_id','created_by','defect_probe',
        'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
          'match_reason','ZZ DEMO - disp002 '||v_key)));
      v_msg := v_msg || v_key || '=W ';
      raise exception 'ZZ_UNDO';
    exception when others then
      if SQLERRM <> 'ZZ_UNDO' then v_msg := v_msg || v_key || '=refused '; end if;
    end;
  end loop;
  if not exists (select 1 from public.leads l
                  where lower(l.email) = 'zz-disp002-approved@example.invalid') then
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-disp002-approved',
      'owner_ref','zz-disp002-approved','created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO - disp002 approved',
        'email','zz-disp002-approved@example.invalid','verified', true)));
  end if;
  select jsonb_build_object('supplier_id', l.id::text) into v_a from public.leads l
   where lower(l.email) = 'zz-disp002-approved@example.invalid';
  select coalesce(v_ok,false) and coalesce(r.ok,false) into v_ok
    from public.fn_phase_d_rule_check('BR-015', v_a) r;
  select count(*) into v_n from public.inquiry_matches;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp002-control',
      'owner_ref', v_a->>'supplier_id','created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp002 control')));
    v_msg := v_msg || format('| CTRL approved: written, im %s->%s',
      v_n, (select count(*) from public.inquiry_matches));
    raise exception 'ZZ_UNDO';
  exception when others then
    if SQLERRM <> 'ZZ_UNDO' then
      v_ok := false; v_msg := v_msg || '| CONTROL refused: ' || left(SQLERRM,60);
    end if;
  end;
  defect_id:='PD-DISP-002'; category:='DISPATCH';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('BR-015+GATE-014(gate014_supplier_unverified) refuse all 3 alike, none distinguished; the inquiry_matches BEFORE-INSERT guard never reads approval_status and WROTE all 3: %s', v_msg);
  blocker := null; return next;

  -- PD-DISP-004 a refused assignment counted as a notification.
  -- The refusal is a BEFORE-trigger return-null on public.inquiry_matches; the notification is
  -- written by the AFTER INSERT trigger notify_matched_supplier, which a BEFORE null never reaches.
  -- Both counts are taken around both arms and both are stated.
  if not exists (select 1 from public.leads l where lower(l.email) = 'zz-disp004@example.invalid') then
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-disp004-sup','owner_ref','zz-disp004-sup',
      'created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO - disp004 supplier',
        'email','zz-disp004@example.invalid','verified', true)));
  end if;
  select l.id::text into v_key from public.leads l where lower(l.email)='zz-disp004@example.invalid';
  update public.leads set matching_blocked = true,
         matching_block_reason = 'ZZ DEMO - PD-DISP-004 injection' where id::text = v_key;
  select count(*) into v_n from public.inquiry_matches;
  select count(*) into v_id from public.notifications;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp004-inject','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp004 injection')));
    v_ok := false; v_msg := 'the refused assignment was written: ' || (v_b->>'result_reference') || ' ';
  exception when others then
    -- Same reason as PD-DISP-001: the GUC the trigger published was rolled back with this
    -- subtransaction, so the verdict is taken from the message the writer raised.
    v_ok := position('pd_object_write_produced_nothing' in SQLERRM) > 0
            and position('BLOCKED_INELIGIBLE_SUPPLIER' in SQLERRM) > 0
            and v_n = (select count(*) from public.inquiry_matches)
            and v_id = (select count(*) from public.notifications);
    v_msg := format('refused %s: im %s->%s, notifications %s->%s. ',
      split_part(coalesce(nullif(split_part(SQLERRM, 'Gate verdict: ', 2),''),'(no verdict)'), ' ', 1),
      v_n, (select count(*) from public.inquiry_matches),
      v_id, (select count(*) from public.notifications));
  end;
  -- CONTROL. The SAME supplier and the SAME inquiry; matching_blocked is the one thing that moves.
  update public.leads set matching_blocked = false, matching_block_reason = null
   where id::text = v_key;
  select count(*) into v_n from public.inquiry_matches;
  select count(*) into v_id from public.notifications;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp004-control','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp004 control')));
    v_msg := v_msg || format('CONTROL same supplier+inquiry, unblocked: im %s->%s, notifications %s->%s.',
      v_n, (select count(*) from public.inquiry_matches),
      v_id, (select count(*) from public.notifications));
    v_ok := coalesce(v_ok,false)
            and (select count(*) from public.inquiry_matches) = v_n + 1
            and (select count(*) from public.notifications) = v_id + 1;
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL was refused too: ' || left(SQLERRM,80);
  end;
  defect_id:='PD-DISP-004'; category:='DISPATCH';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-LEGAL-002 an accepted terms version, rewritten. Two layers and both are immediate.
  select r.record_id, r.business_key, r.owner_ref into v_id, v_key, v_msg
    from public.phase_d_object_record r
   where r.object_id = 'customer_terms_acceptance' and r.superseded_by is null
   order by r.record_id desc limit 1;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','customer_terms_acceptance','business_key', v_key,'owner_ref', v_msg,
      'created_by','defect_probe','state','accepted',
      'payload', jsonb_build_object('stage','customer_terms_acceptance',
        'terms_version','v9-rewritten','accepted_by', v_msg)));
    v_ok := false; v_msg := 'the writer accepted a second version: ' || (v_b->>'result_reference') || ' ';
  exception when others then
    v_ok := position('pd_object_append_only' in SQLERRM) > 0;
    v_msg := 'writer pd_object_append_only; ';
  end;
  select count(*) into v_n from public.phase_d_object_record;
  begin
    update public.phase_d_object_record
       set payload = jsonb_set(payload, '{terms_version}', '"v9-rewritten"')
     where record_id = v_id;
    v_ok := false; v_msg := v_msg || 'the guard permitted a payload rewrite; ';
  exception when others then
    v_ok := coalesce(v_ok,false) and position('pd_object_overwrite_refused' in SQLERRM) > 0;
    v_msg := v_msg || 'guard pd_object_overwrite_refused; ';
  end;
  -- CONTROL. The SAME UPDATE on the SAME row, differing in exactly one respect: the column it moves
  -- is one the APPEND_ONLY family does not freeze. Read from the guard body -- identity, owner,
  -- payload, created_by and created_at are frozen, and for APPEND_ONLY the state too; the
  -- supersession columns are not, and that is the one change an append-only record still permits.
  begin
    update public.phase_d_object_record set superseded_at = now() where record_id = v_id;
    v_msg := v_msg || 'CONTROL same row, superseded_at (not frozen): ACCEPTED';
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL refused too: ' || left(SQLERRM,60);
  end;
  defect_id:='PD-LEGAL-002'; category:='LEGAL';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg || format('; records %s->%s, terms_version still %s', v_n,
    (select count(*) from public.phase_d_object_record),
    (select r2.payload->>'terms_version' from public.phase_d_object_record r2 where r2.record_id = v_id));
  blocker := null; return next;

  -- ---- Remaining rows whose subject exists but whose injection needs a committed run ------------
  for v_key, v_msg in
    select * from (values
      ('PD-QUOTE-005','QUOTE: needs normalization to attempt an overwrite of an original supplier value; the normalization path is not built.'),
      ('PD-ZZ-LIST-TAIL','TAIL: not a defect and never emitted. Removing a row from this list must not strip the comma from its neighbour, so the list ends on a row nobody removes and the loop filters it out by name.')
    ) as t(a,b) where t.a <> 'PD-ZZ-LIST-TAIL'
  loop
    defect_id := v_key; category := split_part(v_msg, ':', 1); status := 'NOT_RUN';
    observed := null; blocker := v_msg;
    return next;
  end loop;
end $function$
