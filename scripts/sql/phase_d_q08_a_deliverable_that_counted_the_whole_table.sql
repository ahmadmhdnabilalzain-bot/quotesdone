-- Q08. A DELIVERABLE THAT COULD NOT REPRODUCE BECAUSE ITS EVIDENCE COUNTED THE WHOLE TABLE.
--
-- NO TRANSACTION CONTROL. One implicit transaction under a simple-query batch; rehearsable.
--
-- PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1 Gate 2 requires every built deliverable to reproduce
-- BYTE-IDENTICALLY from production. PHASE_D_INJECTED_DEFECT_RESULT.csv could not, and the reason
-- had nothing to do with the estate changing.
--
-- Measured 25 Aug 2026, two runs seven hours apart, one line of difference in 75 rows:
--
--   -PD-DISP-004,...,"refused BLOCKED_INELIGIBLE_SUPPLIER: im 6->6, notifications 676->676. ..."
--   +PD-DISP-004,...,"refused BLOCKED_INELIGIBLE_SUPPLIER: im 6->6, notifications 678->678. ..."
--
-- public.notifications grows on its own — the 15-minute health cron writes a digest row into it —
-- so an absolute count of that table is different every time it is read. The control's VERDICT was
-- never wrong: v_ok compares the count before against the count after and requires them equal
-- (refusal) or +1 (control). That logic is untouched. It was the EVIDENCE STRING that printed the
-- two absolute values instead of the difference between them, and the difference is the whole fact
-- the control is about.
--
-- SO THE DELIVERABLE HAD A BUILT-IN EXPIRY. It reproduced for as long as no cron ran — minutes —
-- and any audit re-running Gate 2 later than that would have read a byte difference and had to
-- decide whether the estate had moved. It had not. This is the same shape as a committed constant
-- describing a record that moves underneath it, and the fix is the same: record the fact, not the
-- reading that happened to carry it.
--
-- WHAT CHANGES: two format() calls in the PD-DISP-004 arm of fn_phase_d_run_injected_defects, from
-- `im <before>-><after>, notifications <before>-><after>` to a SIGNED DELTA rendered with
-- `to_char(after - before, 'SFM999999')`. Nothing else in the routine moves — not a predicate, not
-- a verdict, not another defect's arm.
--
-- NOT `format('%+s', …)`: Postgres has no `+` flag and the first apply of this file raised
-- `22023: unrecognized format() type specifier "+"` on the next build. Caught by rebuilding the
-- deliverable immediately after applying, which is the only reason it was caught at all — the
-- routine had already been written to production in that state.
--
-- WHAT IT DOES NOT FIX: this file corrects the one arm that was measured to drift. The other 74
-- arms were not audited for the same shape; if another prints an absolute count of a table a cron
-- writes to, it will surface the same way and is not claimed to be absent here.
--
-- ROLLBACK: scripts/sql/down/phase_d_q08_a_deliverable_that_counted_the_whole_table_down.sql
-- re-applies the body read out of production before this file ran. Applying it restores an evidence
-- string that goes stale within fifteen minutes.

CREATE OR REPLACE FUNCTION public.fn_phase_d_run_injected_defects()
 RETURNS TABLE(defect_id text, category text, status text, observed text, blocker text)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_s4_step text; v_s4_bare text; v_s4_reason text; v_s3_step text; v_s3_flip text;
  v_p2_state text; v_p2_code text; v_p2_fstate text; v_p2_fpassed boolean;
  v_p2_fcode text; v_p2_fabsent boolean; v_p2_other text;
  -- N04 locals. Named for the case that uses them so a later reader can delete them with it.
  v_c4_ob0 bigint; v_c4_row bigint; v_c4_n0 bigint; v_c4_n1 bigint; v_c4_n2 bigint; v_c4_emit jsonb;
  v_t5_board text; v_c1_verdict text; v_c1_observed text;
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

  -- PD-CONC-001 two workers claim the same task.
  -- The race is driven by scripts/phase_d/run_concurrency_probes.mjs, which issues two overlapping
  -- statements on two distinct backends against a temporary committed canary and then removes it.
  -- This branch reads what that harness recorded and refuses to invent a verdict when it has not run.
  select r.verdict, r.observed into v_c1_verdict, v_c1_observed
    from public.phase_d_concurrency_probe_result r
   where r.probe_id = 'C1-skip-locked-single-claimant'
   order by r.ran_at desc limit 1;
  defect_id:='PD-CONC-001'; category:='CONCURRENCY';
  if v_c1_verdict is null then
    status := 'NOT_RUN'; observed := null;
    blocker := 'the two-session harness has not run. node scripts/phase_d/run_concurrency_probes.mjs '
            || 'records C1-skip-locked-single-claimant; until it does there is no result to read, and '
            || 'a verdict invented here would be the fabrication this register exists to prevent.';
  else
    status := v_c1_verdict; observed := v_c1_observed; blocker := null;
  end if;
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
  -- PD-AUTH-005. THE RECORDED BLOCKER WAS WRONG ABOUT A ROUTINE THAT WAS ALWAYS HERE.
  -- It said closing this needs fn_phase_c_task_create, a KERNEL_INTERNAL_PRIMITIVE, and that a
  -- probe calling it is the bypass fn_kernel_retired_path_state exists to catch. public.
  -- fn_kernel_open_step IS "a kernel entry point that accepts an owner and routes to the primitive"
  -- -- the exact thing the blocker said had to be built. It takes owner_role_id FROM THE CALLER.
  declare
    v_a5_ovl text; v_a5_alias text; v_a5_fx jsonb; v_a5_dr jsonb; v_a5_run bigint;
    v_a5_step text; v_a5_owner text; v_a5_msg text := ''; v_a5_ok boolean := false;
    v_a5_t1 bigint; v_a5_t2 bigint; v_a5_r1 bigint; v_a5_r2 bigint; v_a5_c1 bigint; v_a5_c2 bigint;
    v_a5_A text; v_a5_B text; v_a5_C text; v_a5_G text;
  begin
    -- WRITES INSIDE A BLOCK THAT ALWAYS RAISES. fn_phase_d_injected_defect_report has callers other
    -- than the deliverable builder, and not all of them abort. A plpgsql exception block is a
    -- subtransaction: raising at the end of it discards every row this branch wrote, in every
    -- caller, without depending on anyone else's discipline. The findings come back in the message.
    begin
      select b.live_role_id into v_a5_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;
      select a.alias into v_a5_alias from public.org_role_alias a where a.role_id = v_a5_ovl limit 1;
      v_a5_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
        'label','pd-auth-005','execution_context','test','for_workflow','W04'));
      v_a5_dr := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id','W04','scenario', v_a5_fx, 'mode','happy','hold_at_first_open_step', true));
      v_a5_run := (v_a5_dr->>'run_id')::bigint;
      select s.step_id, s.accountable_role_id into v_a5_step, v_a5_owner
        from public.phase_b_workflow_step s
       where s.workflow_id='W04'
         and not exists (select 1 from public.phase_c_workflow_step_run r
                          where r.run_id=v_a5_run and r.step_id=s.step_id)
       order by s.step_no limit 1;

      select count(*) into v_a5_t1 from public.phase_c_task;
      select count(*) into v_a5_r1 from public.phase_c_workflow_step_run;
      select count(*) into v_a5_c1 from public.phase_c_trace;

      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_a5_run,'step_id',v_a5_step,
          'owner_role_id', v_a5_ovl, 'opened_because','PD-AUTH-005 overlay as accountable owner'));
        v_a5_A := 'ACCEPTED';
      exception when others then v_a5_A := 'REFUSED ' || SQLSTATE; end;
      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_a5_run,'step_id',v_a5_step,
          'owner_role_id', v_a5_alias, 'opened_because','PD-AUTH-005 overlay behind its alias'));
        v_a5_B := 'ACCEPTED';
      exception when others then v_a5_B := 'REFUSED ' || SQLSTATE; end;

      select count(*) into v_a5_t2 from public.phase_c_task;
      select count(*) into v_a5_r2 from public.phase_c_workflow_step_run;
      select count(*) into v_a5_c2 from public.phase_c_trace;

      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_a5_run,'step_id',v_a5_step,
          'owner_role_id', v_a5_owner, 'opened_because','PD-AUTH-005 control: the standing role'));
        v_a5_C := 'ACCEPTED';
      exception when others then v_a5_C := 'REFUSED ' || SQLSTATE; end;

      -- THE TABLE BOUNDARY IS ASSERTED SOMEWHERE ELSE, AND THIS IS WHY.
      -- a02_phase_c_step_run_owner_admissible can only be reached with an overlay through
      -- fn_kernel_write_guard's audited maintenance door, and a literal
      -- `update public.phase_c_workflow_step_run` inside THIS routine is precisely what
      -- fn_kernel_write_guard_state's routines_that_write_a_protected_table_with_no_authority
      -- exists to surface -- it took that board from 1 of 37 to 3 of 39. Registering this routine
      -- to quieten it would GRANT it authority over the table, which is the opposite of the point.
      -- The forced firing lives in scripts/checks/protected_table_guards_actually_fire.test.mjs,
      -- which is a check rather than a routine and so is not a writer any board can count.
      -- What this branch asserts is the LIVE path: fn_kernel_open_step refuses the overlay before
      -- a row exists, and the stable identity comes from the predicate both guards raise from.
      v_a5_G := coalesce((select refusal_code
                            from public.fn_phase_d_owner_admissibility(v_a5_ovl)), 'ADMISSIBLE');

      raise exception '%', 'PDA5' || chr(31) || v_a5_A || '|' || v_a5_B || '|' || v_a5_C || '|' || v_a5_G || '|' || (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_ovl)) || '|' || (select refusal_code from public.fn_phase_d_owner_admissibility(v_a5_alias)) || '|' || case when v_a5_t1 = v_a5_t2 and v_a5_r1 = v_a5_r2 and v_a5_c1 = v_a5_c2 then 'unchanged' else 'MOVED tasks '||(v_a5_t2-v_a5_t1)||' step runs '||(v_a5_r2-v_a5_r1)||' traces '||(v_a5_c2-v_a5_c1) end;
    exception when others then
      if position('PDA5' in SQLERRM) = 1 then v_a5_msg := split_part(SQLERRM, chr(31), 2);
      else v_a5_msg := 'BRANCH_ERROR ' || left(SQLERRM, 120); end if;
    end;

    v_a5_ok := split_part(v_a5_msg,'|',1) like 'REFUSED%'
           and split_part(v_a5_msg,'|',2) like 'REFUSED%'
           and split_part(v_a5_msg,'|',3) = 'ACCEPTED'
           and split_part(v_a5_msg,'|',4) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',5) = 'pd_overlay_cannot_own_task'
           and split_part(v_a5_msg,'|',6) = 'pd_overlay_cannot_own_task'
           -- and the standing role must still be ADMISSIBLE, or the predicate refuses everything
           and (select admissible from public.fn_phase_d_owner_admissibility(
                  (select accountable_role_id from public.phase_b_workflow_step
                    where step_id = 'W04-S02')))
           and split_part(split_part(v_a5_msg,'|',7),' ',1) like '%'
           and split_part(v_a5_msg,'|',7) = 'unchanged';
    defect_id:='PD-AUTH-005'; category:='AUTH';
    status := case when v_a5_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('overlay owner->%s alias->%s standing role->%s; owner-admissibility predicate %s; tasks, step runs and traces across both refusals: %s',
                       split_part(v_a5_msg,'|',1), split_part(v_a5_msg,'|',2),
                       split_part(v_a5_msg,'|',3), split_part(v_a5_msg,'|',4),
                       split_part(v_a5_msg,'|',7));
    blocker := null; return next;
  end;

  -- (the withdrawn note below is kept as the record of why this case was NOT_RUN until O01)
  -- PD-AUTH-005 — the earlier withdrawal, and this is why rather than a silent revert.
  -- The branch that closed it called public.fn_phase_c_task_create. public.kernel_write_authority
  -- says that routine may write public.phase_c_task; public.kernel_retired_path says it is a
  -- KERNEL_INTERNAL_PRIMITIVE, reachable only from fn_kernel_*. Both are true together — it is the
  -- authorised writer, called by the kernel — so a PROBE calling it is exactly the bypass
  -- fn_kernel_retired_path_state counts, and it took that board from 0 of 9 to 1 of 9.
  -- Making the board's exclusion list longer to admit this estate's own probe would be editing a
  -- kernel board to suit the code it audits. The refusal was real and was observed; the route to it
  -- was not one a probe may take.

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
  -- PD-LEGAL-005. THE CANONICAL REVIEW SERVICE ALREADY REFUSES A SELF-REVIEW, AND THE TASK
  -- BOUNDARY REFUSES THE COLLISION BEFORE A TASK EXISTS. Both are driven here on a REAL
  -- review-required privacy artifact -- W08-S06, "Approve immutable supplier-safe package",
  -- frozen owner marketplace_content_privacy_reviewer, frozen reviewer
  -- compliance_and_privacy_officer -- and the alias arm uses privacy_officer, a registered
  -- legacy_role_id of the reviewer.
  declare
    v_l5_fx jsonb; v_l5_dr jsonb; v_l5_run bigint; v_l5_task bigint; v_l5_msg text := '';
    v_l5_ok boolean := false; v_l5_A text; v_l5_B text; v_l5_C text; v_l5_T text; v_l5_S text;
    v_l5_t1 bigint; v_l5_t2 bigint;
  begin
    -- WRITES INSIDE A BLOCK THAT ALWAYS RAISES. fn_phase_d_injected_defect_report has callers other
    -- than the deliverable builder, and not all of them abort. A plpgsql exception block is a
    -- subtransaction: raising at the end of it discards every row this branch wrote, in every
    -- caller, without depending on anyone else's discipline. The findings come back in the message.
    begin
      v_l5_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
        'label','pd-legal-005','execution_context','test','for_workflow','W08'));
      v_l5_dr := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id','W08','scenario', v_l5_fx, 'mode','happy','hold_at_first_open_step', true));
      v_l5_run := (v_l5_dr->>'run_id')::bigint;

      select count(*) into v_l5_t1 from public.phase_c_task;
      -- the task boundary: the declared reviewer presented as the step's own owner
      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_l5_run,'step_id','W08-S06',
          'owner_role_id','compliance_and_privacy_officer',
          'opened_because','PD-LEGAL-005 creator is the declared reviewer'));
        v_l5_T := 'ACCEPTED';
      exception when others then
        v_l5_T := case when position('pd_creator_reviewer_collision' in SQLERRM) > 0
                       then 'pd_creator_reviewer_collision' else 'other:' || SQLSTATE end;
      end;
      -- the same collision reached through a legacy alias of the reviewer
      begin
        perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_l5_run,'step_id','W08-S06',
          'owner_role_id','privacy_officer',
          'opened_because','PD-LEGAL-005 alias of the declared reviewer'));
        v_l5_S := 'ACCEPTED';
      exception when others then
        v_l5_S := case when position('pd_creator_reviewer_collision' in SQLERRM) > 0
                       then 'pd_creator_reviewer_collision' else 'other:' || SQLSTATE end;
      end;
      select count(*) into v_l5_t2 from public.phase_c_task;

      -- the canonical owner, so a task exists for the review service to be asked about
      perform public.fn_kernel_open_step(jsonb_build_object('run_id',v_l5_run,'step_id','W08-S06',
        'owner_role_id','marketplace_content_privacy_reviewer',
        'opened_because','PD-LEGAL-005 control: the frozen canonical owner'));
      select t.task_id into v_l5_task from public.phase_c_task t
       where t.run_id = v_l5_run and t.step_id = 'W08-S06' order by t.task_id desc limit 1;

      -- A: the reviewer resolves to the creator
      v_l5_A := coalesce((public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_l5_task, 'reviewer_role_id','marketplace_content_privacy_reviewer',
        'decision','approved','reason','PD-LEGAL-005 arm A')))->>'error', 'ACCEPTED');
      -- B: a legacy alias of the creator
      v_l5_B := coalesce((public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_l5_task, 'reviewer_role_id','moderation_specialist',
        'decision','approved','reason','PD-LEGAL-005 arm B')))->>'error', 'ACCEPTED');
      -- C: the genuinely independent authorised reviewer the frozen registry declares
      v_l5_C := coalesce((public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_l5_task, 'reviewer_role_id','compliance_and_privacy_officer',
        'decision','approved','reason','PD-LEGAL-005 arm C')))->>'error', 'ACCEPTED');

      raise exception '%', 'PDL5' || chr(31) || v_l5_A || '|' || v_l5_B || '|' || v_l5_C || '|' || v_l5_T || '|' || v_l5_S || '|' || case when v_l5_t1 = v_l5_t2 then 'unchanged' else 'MOVED '||(v_l5_t2-v_l5_t1) end;
    exception when others then
      if position('PDL5' in SQLERRM) = 1 then v_l5_msg := split_part(SQLERRM, chr(31), 2);
      else v_l5_msg := 'BRANCH_ERROR ' || left(SQLERRM, 120); end if;
    end;

    -- BOTH refusal codes are accepted, and this is why rather than left as a loose predicate.
    -- fn_kernel_review_decide checks the DECLARED reviewer (frozen Phase B) before it checks
    -- independence, so a creator offering itself is refused as not_the_declared_reviewer -- the
    -- stronger of the two answers, because the registry names who reviews and the creator is not
    -- that role. reviewer_not_independent is what fires where no reviewer is declared. Either is a
    -- refusal of the same act; a case that demanded exactly one of them would be asserting the
    -- ORDER of two guards rather than the behaviour of the control.
    v_l5_ok := split_part(v_l5_msg,'|',1) in ('reviewer_not_independent','not_the_declared_reviewer')
           and split_part(v_l5_msg,'|',2) in ('reviewer_not_independent','not_the_declared_reviewer')
           and split_part(v_l5_msg,'|',3) = 'ACCEPTED'
           and split_part(v_l5_msg,'|',4) = 'pd_creator_reviewer_collision'
           and split_part(v_l5_msg,'|',5) = 'pd_creator_reviewer_collision'
           and split_part(v_l5_msg,'|',6) = 'unchanged'
           -- AND THE INDEPENDENCE DECISION ITSELF, ACROSS BOTH IDENTITY VOCABULARIES, so the case
           -- does not rest on a refusal that fired for the declared-reviewer reason.
           and not public.fn_kernel_reviewer_independent(
                     'marketplace_content_privacy_reviewer','marketplace_content_privacy_reviewer')
           and not public.fn_kernel_reviewer_independent(
                     'marketplace_content_privacy_reviewer','moderation_specialist')
           and not public.fn_kernel_reviewer_independent(
                     'compliance_and_privacy_officer','privacy_officer')
           and public.fn_kernel_reviewer_independent(
                     'marketplace_content_privacy_reviewer','compliance_and_privacy_officer');
    defect_id:='PD-LEGAL-005'; category:='LEGAL';
    status := case when v_l5_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('W08-S06 review service: creator->%s alias-of-creator->%s independent->%s; task boundary %s / alias %s; tasks across both refusals: %s; fn_kernel_reviewer_independent self=f alias=f cross-vocab=f independent=t',
                       split_part(v_l5_msg,'|',1), split_part(v_l5_msg,'|',2), split_part(v_l5_msg,'|',3),
                       split_part(v_l5_msg,'|',4), split_part(v_l5_msg,'|',5), split_part(v_l5_msg,'|',6));
    blocker := null; return next;
  end;

  -- (the withdrawn note below is kept as the record of why this case was NOT_RUN until O01)
  -- PD-LEGAL-005 — the earlier withdrawal, and this is why rather than a silent revert.
  -- The branch that closed it called public.fn_phase_c_task_create. public.kernel_write_authority
  -- says that routine may write public.phase_c_task; public.kernel_retired_path says it is a
  -- KERNEL_INTERNAL_PRIMITIVE, reachable only from fn_kernel_*. Both are true together — it is the
  -- authorised writer, called by the kernel — so a PROBE calling it is exactly the bypass
  -- fn_kernel_retired_path_state counts, and it took that board from 0 of 9 to 1 of 9.
  -- Making the board's exclusion list longer to admit this estate's own probe would be editing a
  -- kernel board to suit the code it audits. The refusal was real and was observed; the route to it
  -- was not one a probe may take.

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


  -- PD-FIN-004. THE APPEND-ONLY CONTROL WAS ALWAYS REAL; WHAT WAS MISSING WAS A PRODUCER.
  -- public.kernel_write_authority held ZERO rows for phase_c_refund_decision, so no routine could
  -- ever create the row the immutability trigger exists to protect, and the table stayed at 0.
  -- O02 registered public.fn_kernel_refund_decision_record -- the canonical founder decision
  -- service, which resolves the founder through fn_phase_c_require_founder and writes decided_by
  -- from the VERIFIED identity, never from the call. Nothing here forges a founder: the subject is
  -- bound through the estate's own server door, in a subtransaction that always rolls back, on the
  -- founder's own written instruction for this session.
  declare
    v_f4_sub uuid; v_f4_req bigint; v_f4_d1 bigint; v_f4_res jsonb; v_f4_msg text := '';
    v_f4_ok boolean := false; v_f4_before jsonb; v_f4_row public.phase_c_refund_decision%rowtype;
    v_f4_N text; v_f4_U text; v_f4_D text; v_f4_S text; v_f4_E text; v_f4_R text; v_f4_W text;
  begin
    -- WRITES INSIDE A BLOCK THAT ALWAYS RAISES. fn_phase_d_injected_defect_report has callers other
    -- than the deliverable builder, and not all of them abort. A plpgsql exception block is a
    -- subtransaction: raising at the end of it discards every row this branch wrote, in every
    -- caller, without depending on anyone else's discipline. The findings come back in the message.
    begin
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','request_id',1,'decision','approved','reason','no founder on this call'));
        v_f4_N := 'ACCEPTED';
      exception when others then v_f4_N := 'REFUSED ' || SQLSTATE; end;

      select f.auth_user_id into v_f4_sub from public.phase_c_founder_identity f
       where f.active and f.kind='email' and f.auth_user_id is not null order by f.identity limit 1;
      perform public.fn_phase_c_founder_subject_bind(v_f4_sub);
      insert into public.founder_approval_request(action_class, subject_ref, prepared_by_role_id)
      values ('refund_decision','pd-fin-004','payments_and_billing_manager') returning request_id into v_f4_req;
      v_f4_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
        'op','record','request_id',v_f4_req,'decision','approved','reason','PD-FIN-004'));
      v_f4_d1 := (v_f4_res->>'decision_id')::bigint;
      select * into v_f4_row from public.phase_c_refund_decision where decision_id = v_f4_d1;
      v_f4_before := to_jsonb(v_f4_row);

      -- THE EDIT AND THE DELETE ARE ASKED OF THE SERVICE, NOT WRITTEN BY HAND, and this is why.
      -- The raw UPDATE and DELETE reach a00_phase_c_refund_decision_immutable only through
      -- fn_kernel_write_guard's maintenance door, and a literal
      -- `update public.phase_c_refund_decision` inside this routine is exactly what
      -- fn_kernel_write_guard_state counts as an unauthorised writer. Those two arms are driven in
      -- scripts/checks/protected_table_guards_actually_fire.test.mjs, which asserts the frozen
      -- trigger's own 23514 refusals and that the original row did not move.
      -- Here the same two acts are asked of the canonical service, which is the door a caller
      -- actually has, and it refuses both with pd_refund_decision_append_only rather than teaching
      -- its callers that a raw edit is worth attempting.
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','decision_id',v_f4_d1,'edit',true,'request_id',v_f4_req,
          'decision','rejected','reason','PD-FIN-004 edit attempt'));
        v_f4_U := 'ACCEPTED';
      exception when others then
        v_f4_U := case when position('pd_refund_decision_append_only' in SQLERRM) > 0
                       then 'REFUSED pd_refund_decision_append_only' else 'other:' || SQLSTATE end;
      end;
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','decision_id',v_f4_d1,'delete',true,'request_id',v_f4_req,
          'decision','rejected','reason','PD-FIN-004 delete attempt'));
        v_f4_D := 'ACCEPTED';
      exception when others then
        v_f4_D := case when position('pd_refund_decision_append_only' in SQLERRM) > 0
                       then 'REFUSED pd_refund_decision_append_only' else 'other:' || SQLSTATE end;
      end;
      select * into v_f4_row from public.phase_c_refund_decision where decision_id = v_f4_d1;
      v_f4_R := case when to_jsonb(v_f4_row) = v_f4_before then 'UNCHANGED' else 'CHANGED' end;

      begin
        v_f4_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
          'op','record','request_id',v_f4_req,'decision','rejected','reason','superseding',
          'supersedes_decision_id', v_f4_d1, 'supersession_reason','PD-FIN-004 supersession'));
        v_f4_S := 'ACCEPTED';
      exception when others then v_f4_S := 'REFUSED ' || SQLSTATE; end;
      begin
        perform public.fn_kernel_refund_decision_record(jsonb_build_object('op','execute','decision_id',v_f4_d1));
        v_f4_E := 'ACCEPTED';
      exception when others then
        v_f4_E := case when position('pd_refund_execution_without_founder_decision' in SQLERRM) > 0
                       then 'pd_refund_execution_without_founder_decision' else 'other:'||SQLSTATE end;
      end;
      begin
        insert into public.refunds(amount_fils, currency, status, requested_by, reason_code)
        values (1000,'AED','succeeded','customer_success_director','goodwill');
        v_f4_W := 'ACCEPTED';
      exception when others then
        v_f4_W := case when position('pd_refund_execution_without_founder_decision' in SQLERRM) > 0
                       then 'pd_refund_execution_without_founder_decision' else 'other:'||SQLSTATE end;
      end;

      raise exception '%', 'PDF4' || chr(31) || v_f4_N || '|' || v_f4_U || '|' || v_f4_D || '|' || v_f4_R || '|' || v_f4_S || '|' || v_f4_E || '|' || v_f4_W;
    exception when others then
      if position('PDF4' in SQLERRM) = 1 then v_f4_msg := split_part(SQLERRM, chr(31), 2);
      else v_f4_msg := 'BRANCH_ERROR ' || left(SQLERRM, 120); end if;
    end;

    v_f4_ok := split_part(v_f4_msg,'|',1) like 'REFUSED%'
           and split_part(v_f4_msg,'|',2) like 'REFUSED%'
           and split_part(v_f4_msg,'|',3) like 'REFUSED%'
           and split_part(v_f4_msg,'|',4) = 'UNCHANGED'
           and split_part(v_f4_msg,'|',5) = 'ACCEPTED'
           and split_part(v_f4_msg,'|',6) = 'pd_refund_execution_without_founder_decision'
           and split_part(v_f4_msg,'|',7) = 'pd_refund_execution_without_founder_decision';
    defect_id:='PD-FIN-004'; category:='FINANCE';
    status := case when v_f4_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('no-founder->%s; UPDATE->%s DELETE->%s original %s; supersede->%s; execute superseded->%s; refund without decision->%s',
                       split_part(v_f4_msg,'|',1), split_part(v_f4_msg,'|',2), split_part(v_f4_msg,'|',3),
                       split_part(v_f4_msg,'|',4), split_part(v_f4_msg,'|',5), split_part(v_f4_msg,'|',6),
                       split_part(v_f4_msg,'|',7));
    blocker := null; return next;
  end;

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
  -- THE OLD BLOCKER SAID NO CONSUMER RUNS UNDER THE HOLD. Re-measured 24 Aug 2026: the canonical
  -- consumer public.fn_kernel_event_consume(outbox_id) runs inside the CALLER'S transaction and
  -- projects only -- fn_kernel_step_complete is the single authoritative progression path, so a
  -- consumer that created work would be a second creator racing the first. The live cron
  -- phase_c_outbox_deliver_1min, which does deliver externally, never sees a row in a transaction
  -- that is aborted. So the consumption CAN be driven here, and the self-loop is measured rather
  -- than inferred from two registry columns being equal.
  --
  -- THE INJECTION IS A SECOND CONSUMPTION OF THE SAME ROW. If consuming re-emits, the second call
  -- adds outbox rows; if the projection holds, both calls add none. Consuming twice also answers
  -- the idempotency half: a replayed delivery must not produce a second effect.
  begin
    select coalesce(max(outbox_id),0) into v_c4_ob0 from public.phase_c_event_outbox;
    v_c4_emit := public.fn_kernel_outbox_emit(jsonb_build_object(
      'event_id', 'EV-W01-STARTED', 'workflow_id','W01',
      'producer','system.workflow_engine',
      'accountable_role_id','chief_of_staff',
      'correlation_id', gen_random_uuid(), 'causation_id', gen_random_uuid(),
      'source_id','pd-outbox-004-probe',
      'dedupe_value','zz-pd-outbox-004-' || gen_random_uuid()::text,
      'payload', jsonb_build_object('fact','PHASE_D_FIXTURE_DO_NOT_PUBLISH outbox-004 probe')));
    select o.outbox_id into v_c4_row from public.phase_c_event_outbox o
     where o.outbox_id > v_c4_ob0 order by o.outbox_id limit 1;
    if v_c4_row is null then
      status := 'NOT_DISCRIMINATED';
      observed := 'fn_kernel_outbox_emit wrote no row, so there was nothing to consume twice';
    else
      select count(*) into v_c4_n0 from public.phase_c_event_outbox;
      perform 1 from public.fn_kernel_event_consume(v_c4_row);
      select count(*) into v_c4_n1 from public.phase_c_event_outbox;
      perform 1 from public.fn_kernel_event_consume(v_c4_row);
      select count(*) into v_c4_n2 from public.phase_c_event_outbox;
      v_ok := (v_c4_n1 - v_c4_n0) = 0 and (v_c4_n2 - v_c4_n1) = 0;
      status := case when v_ok then 'IDEMPOTENT_NO_DUPLICATE' else 'NOT_REFUSED' end;
      observed := format('outbox row %s consumed twice by the canonical consumer inside this '
                      || 'transaction: first consumption added %s outbox row(s), second added %s. '
                      || 'A consumer that re-emitted would have added one each time.',
                      v_c4_row, v_c4_n1 - v_c4_n0, v_c4_n2 - v_c4_n1);
    end if;
  exception when others then
    status := 'NOT_DISCRIMINATED';
    observed := 'the consume probe raised ' || SQLSTATE || ': ' || left(SQLERRM, 200);
  end;
  defect_id:='PD-OUTBOX-004'; category:='OUTBOX'; blocker := null;
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

  -- PD-PROV-002 a gate READ failure must not look like a gate refusal.
  -- THE OLD BLOCKER SAID THE DISTINCTION "IS NOT REPRESENTABLE". It was not representable because
  -- it had not been built: fn_phase_d_gate_evaluate carried zero exception handlers, so a read
  -- error propagated and aborted the caller instead of becoming a verdict. N06 built it. A defect
  -- catalogue entry saying a control cannot be tested because the control does not exist is a
  -- product gap wearing an exemption, and this one was.
  --
  -- THREE ARMS ON ONE GATE, so the refusal is about the fault and not about the gate refusing
  -- everything: the gate reads and passes; the gate's read is made to fail; and a DIFFERENT gate
  -- evaluated with the fault still armed still answers normally, which is what proves the fault is
  -- scoped rather than global.
  begin
    perform set_config('app.phase_d_gate_read_fault', '', true);
    select g.state, g.refusal_code into v_p2_state, v_p2_code
      from public.fn_phase_d_gate_evaluate('GATE-001', jsonb_build_object('step_id','W01-S01')) g;

    perform set_config('app.phase_d_gate_read_fault', 'GATE-001', true);
    select g.state, g.passed, g.refusal_code, g.evidence_absent
      into v_p2_fstate, v_p2_fpassed, v_p2_fcode, v_p2_fabsent
      from public.fn_phase_d_gate_evaluate('GATE-001', jsonb_build_object('step_id','W01-S01')) g;

    select g.state into v_p2_other
      from public.fn_phase_d_gate_evaluate('GATE-002',
             jsonb_build_object('actor_role_id','chief_of_staff')) g;
    perform set_config('app.phase_d_gate_read_fault', '', true);

    v_ok := v_p2_state = 'PASSED'
        and v_p2_fstate = 'BLOCKED' and v_p2_fpassed is not true
        and v_p2_fcode = 'gate_read_failed' and v_p2_fabsent is true
        and v_p2_other = 'PASSED';
    v_msg := format('read-and-passed: %s/%s | read FAILED: %s passed=%s code=%s evidence_absent=%s '
                 || '| a different gate with the fault still armed: %s. A gate that could not read '
                 || 'now fails closed under its own refusal code instead of answering like one that '
                 || 'read and refused.',
                 v_p2_state, coalesce(v_p2_code,'-'),
                 v_p2_fstate, coalesce(v_p2_fpassed::text,'-'), coalesce(v_p2_fcode,'-'),
                 coalesce(v_p2_fabsent::text,'-'), coalesce(v_p2_other,'-'));
  exception when others then
    perform set_config('app.phase_d_gate_read_fault', '', true);
    v_ok := false;
    v_msg := 'the gate read-fault probe raised instead of returning a verdict: '
          || SQLSTATE || ' ' || left(SQLERRM, 160)
          || ' — a read error that still propagates is the defect itself.';
  end;
  defect_id:='PD-PROV-002'; category:='PROVIDER';
  status := case when v_ok then 'FAIL_CLOSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

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
  -- PD-STATE-003 a nonterminal step presented to the kernel as a closure step.
  -- THE POPULATION IS EMPTY — 0 of 257 frozen steps state their terminality inconsistently — and
  -- the old row stopped there, at NOT_DISCRIMINATED. But "why is it empty" is the measurable part:
  -- creating an inconsistent step is refused by z90_phase_b_freeze, which compares a DIGEST rather
  -- than a count, so flipping one boolean is refused even though no row count moves.
  --
  -- THE CONTROL IS THE OTHER REFUSAL. PD-STATE-004 above is refused by a10_phase_b_owner_guard with
  -- a different message. Two different guards answering two different injections is what shows the
  -- registry is judging the change rather than refusing every statement identically.
  begin
    select count(*) into v_n from public.phase_b_workflow_step
     where (next_step_if_pass = 'WORKFLOW_COMPLETE') <> is_closure_step;
    select step_id into v_s3_step from public.phase_b_workflow_step
     where workflow_id='W04' order by step_no limit 1;
    begin
      update public.phase_b_workflow_step set is_closure_step = not is_closure_step
       where step_id = v_s3_step;
      v_s3_flip := 'ACCEPTED — an inconsistent step was written';
    exception when others then v_s3_flip := left(SQLERRM, 130);
    end;
    v_ok := v_n = 0 and v_s3_flip not like 'ACCEPTED%';
    v_msg := format('%s of 257 frozen steps state their terminality inconsistently, and creating one '
                 || 'was refused: [%s]. The population is empty because the registry refuses to make '
                 || 'it non-empty, which is the fact this case is about; the refusal differs from the '
                 || 'one PD-STATE-004 receives, so the registry is judging the change rather than '
                 || 'refusing every statement alike.', v_n, v_s3_flip);
  exception when others then
    v_ok := false; v_msg := 'the probe raised outside its own handlers: ' || left(SQLERRM, 160);
  end;
  defect_id:='PD-STATE-003'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;
  -- PD-STATE-004 a successor step with no accountable owner.
  -- THE OLD BLOCKER SAID THE SUBJECT IS A FROZEN PHASE B PROPERTY AND SO CANNOT BE INJECTED. The
  -- frozen registry REFUSING the injection is itself a discriminating result — it is what makes the
  -- state unreachable — and refusing to execute it left that refusal unmeasured.
  --
  -- TWO ARMS, and the second is the one that matters. Blanking the owner is refused by
  -- a10_phase_b_owner_guard; blanking it again with app.phase_b_change_reason SET is refused by the
  -- SAME guard, so an unowned successor cannot be created even by a caller holding change-request
  -- authority. That is stronger than "it is frozen": freezing can be amended, and this cannot.
  begin
    select step_id into v_s4_step from public.phase_b_workflow_step
     where workflow_id='W04' order by step_no limit 1;
    begin
      update public.phase_b_workflow_step set accountable_role_id = '' where step_id = v_s4_step;
      v_s4_bare := 'ACCEPTED — an unowned successor was written';
    exception when others then v_s4_bare := left(SQLERRM, 120);
    end;
    begin
      perform set_config('app.phase_b_change_reason',
        'PBCR-probe: a probe is not a change request; this exists to show the guard does not care', true);
      update public.phase_b_workflow_step set accountable_role_id = '' where step_id = v_s4_step;
      v_s4_reason := 'ACCEPTED with a change reason set';
    exception when others then v_s4_reason := left(SQLERRM, 120);
    end;
    perform set_config('app.phase_b_change_reason', '', true);
    v_ok := v_s4_bare not like 'ACCEPTED%' and v_s4_reason not like 'ACCEPTED%';
    v_msg := format('blanking the accountable owner of %s was refused [%s]; and refused again with '
                 || 'app.phase_b_change_reason set [%s]. A successor with no accountable owner cannot '
                 || 'be created in this estate even by a caller holding change-request authority, so '
                 || 'the state the defect names is unreachable by construction rather than by policy.',
                    v_s4_step, v_s4_bare, v_s4_reason);
  exception when others then
    v_ok := false; v_msg := 'the probe raised outside its own handlers: ' || left(SQLERRM, 160);
  end;
  defect_id:='PD-STATE-004'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- ---- TRACE ----------------------------------------------------------------------------------
  -- PD-TRACE-001 / PD-TRACE-002.
  -- THE OLD BLOCKER TREATED THE REFUSAL AS THE OBSTACLE. It is the control. Phase D's whole
  -- contract for a kernel-owned object is that it refuses to write it, and fn_phase_d_object_write
  -- says so by name. Calling it and reading the refusal is a discriminating result: a Phase D path
  -- that DID stage an untraced step run is exactly the defect, and this proves it cannot.
  -- The positive half is that the same routine accepts a Phase D-owned object in the same shape,
  -- so the refusal is about the subject and not about the routine refusing everything.
  begin
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','workflow_step_run',
      'business_key','zz-pd-trace-001',
      'owner_ref','system.workflow_engine', 'created_by','system.workflow_engine',
      'target_state','active',
      'payload', jsonb_build_object('note','PHASE_D_FIXTURE_DO_NOT_PUBLISH — untraced step run')));
    v_ok := false;
    v_msg := 'a Phase D handler WROTE a kernel-owned step run';
  exception when others then
    v_ok := position('pd_object_kernel_owned' in SQLERRM) > 0;
    v_msg := case when v_ok
      then 'fn_phase_d_object_write refused the kernel-owned relation by name (pd_object_kernel_owned): '
        || 'a Phase D handler that wrote it would be a second creator for one object. An active step '
        || 'run with no trace therefore cannot be staged through any Phase D door.'
      else 'refused, but not as a kernel-owned object: ' || left(SQLERRM, 160) end;
  end;
  defect_id:='PD-TRACE-001'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  defect_id:='PD-TRACE-002'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'the closing half has the same single door and the same refusal: ' || v_msg;
  blocker := null; return next;
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
  -- PD-TRACE-005. THE ABSENCE OF A PHASE D PATH IS THE CONTROL, not the blocker: a Phase D route
  -- that could put a state-changing component on a read-only trace policy is precisely the defect.
  -- Both halves are executed -- the Phase D door refuses the write, and the kernel's own board
  -- reports the standing population -- so the row rests on two measurements rather than on prose.
  begin
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','trace_policy',
      'business_key','TRACE-MONITORING',
      'owner_ref','system.workflow_engine', 'created_by','system.workflow_engine',
      'target_state','exempt',
      'payload', jsonb_build_object('note','PHASE_D_FIXTURE_DO_NOT_PUBLISH — exemption request')));
    v_ok := false;
    v_msg := 'a Phase D handler granted itself a trace exemption';
  exception when others then
    -- The specific code, not any error: a probe that accepts every failure would score a typo as a
    -- pass. trace_policy is not a bound Phase D object, so the door fails closed rather than storing
    -- a record under a policy nobody declared -- which is the refusal this case needs.
    v_ok := position('pd_object_unbound' in SQLERRM) > 0;
    v_msg := 'the Phase D write door refused the trace policy (' ||
             coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1], SQLSTATE) || ')';
  end;
  select coalesce(string_agg(b.check_name || ' ' || b.actual, '; '), '(no rows)')
    into v_t5_board
    from public.fn_kernel_system_trace_state() b
   where b.check_name in ('state_changing_components_on_a_read_only_policy',
                          'read_only_components_without_a_recorded_exemption');
  defect_id:='PD-TRACE-005'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg || '; and the kernel board reports ' || v_t5_board;
  blocker := null; return next;

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
      ('PD-PRIV-004','PRIVACY: needs a supplier bearer token calling the raw inquiry endpoint and the response body.')
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
    -- Q08. THE VERDICT WAS ALWAYS A DELTA; THE EVIDENCE WAS AN ABSOLUTE COUNT.
    -- v_ok above compares counts BEFORE and AFTER, which is right. This string printed the two
    -- absolute values -- 'notifications 676->676' -- and public.notifications grows on its own:
    -- the 15-minute health cron writes to it. So the deliverable this string lands in could not
    -- reproduce byte-for-byte more than a few minutes after it was built, and Gate 2 requires
    -- exactly that. Measured 25 Aug 2026: the only diff between two runs seven hours apart was
    -- 676->676 becoming 678->678. The delta is the fact the control is about and it is stable.
    v_msg := format('refused %s: im %s, notifications %s. ',
      split_part(coalesce(nullif(split_part(SQLERRM, 'Gate verdict: ', 2),''),'(no verdict)'), ' ', 1),
      to_char((select count(*) from public.inquiry_matches) - v_n, 'SFM999999'),
      to_char((select count(*) from public.notifications) - v_id, 'SFM999999'));
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
    v_msg := v_msg || format('CONTROL same supplier+inquiry, unblocked: im %s, notifications %s.',
      to_char((select count(*) from public.inquiry_matches) - v_n, 'SFM999999'),
      to_char((select count(*) from public.notifications) - v_id, 'SFM999999'));
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

  -- ---- THE FIVE THAT NEEDED A CONTRACT, AND NOW HAVE ONE ---------------------------------------
  -- Each of these was NOT_RUN because the control it names did not exist in this estate. O03-O07
  -- built them. Every branch below drives an injection AND its control, and the control is the half
  -- that makes the refusal mean something: a predicate that refuses both arms is indistinguishable
  -- from a dead path.

  -- PD-LEGAL-004. Four ways a source fails and one way it does not, over committed reference rows
  -- in public.phase_d_legal_source that this branch does not create -- a probe that writes its own
  -- stale source and then asks whether a stale source is refused has answered its own question.
  declare v_g4 text[]; v_g4_ok boolean;
  begin
    select array[
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-fta-corporate-tax-expired')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-undated-circular')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-blog-vat-opinion')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-fta-corporate-tax-2024')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-fta-corporate-tax-current')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_gate_evaluate('GATE-027', jsonb_build_object(
        'reconciliation_ref','zz','control_exception_ref','zz','tax_source_ref','zz-demo-fta-corporate-tax-expired'))),'PASSED')
    ] into v_g4;
    v_g4_ok := v_g4[1]='pd_legal_source_stale' and v_g4[2]='pd_legal_source_missing'
           and v_g4[3]='pd_legal_source_not_authoritative' and v_g4[4]='pd_legal_source_superseded'
           and v_g4[5]='USABLE' and v_g4[6]='pd_legal_source_stale';
    -- and the HARD boundary: an assertion citing the stale source is refused outright
    begin
      insert into public.phase_d_legal_assertion
        (subject, jurisdiction, position_summary, source_id, asserted_by_role_id)
      values ('pd-legal-004','AE','probe','zz-demo-fta-corporate-tax-expired','general_counsel');
      v_g4 := v_g4 || 'ASSERTION_ACCEPTED';
    exception when others then
      v_g4 := v_g4 || case when position('pd_legal_source_stale' in SQLERRM) > 0
                           then 'pd_legal_source_stale' else 'other:'||SQLSTATE end;
    end;
    v_g4_ok := v_g4_ok and v_g4[7] = 'pd_legal_source_stale';
    defect_id:='PD-LEGAL-004'; category:='LEGAL';
    status := case when v_g4_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('freshness predicate stale/undated/non-authoritative/superseded/current -> %s; GATE-027 on the stale source -> %s; assertion citing it -> %s',
                       array_to_string(v_g4[1:5],','), v_g4[6], v_g4[7]);
    blocker := null; return next;
  end;

  -- PD-PRIV-002. A revision whose redaction is unapproved, one rejected, one superseded, and the
  -- approved clean one, all through BR-012 and GATE-013 -- the two predicates that returned the
  -- IDENTICAL ENFORCED_PASS to the injection and the control before O07.
  declare v_p2 text[]; v_p2_ok boolean;
  begin
    select array[
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-unredacted')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-rejected')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-superseded')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-safe')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-safe', repeat('f',64))),'DISPATCHABLE'),
      (select state from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
        'safe_package_ref','zz-demo-pkg-priv-002','safe_package_approved_by','compliance_and_privacy_officer',
        'actor_role_id','marketplace_content_privacy_reviewer'))),
      (select state from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
        'safe_package_ref','zz-demo-pkg-priv-002-clean','safe_package_approved_by','compliance_and_privacy_officer',
        'actor_role_id','marketplace_content_privacy_reviewer')))
    ] into v_p2;
    v_p2_ok := v_p2[1]='pd_revision_redaction_unapproved' and v_p2[2]='pd_revision_redaction_rejected'
           and v_p2[3]='pd_revision_superseded' and v_p2[4]='DISPATCHABLE'
           and v_p2[5]='pd_revision_digest_mismatch' and v_p2[6]='BLOCKED' and v_p2[7]='PASSED';
    defect_id:='PD-PRIV-002'; category:='PRIVACY';
    status := case when v_p2_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('revision pending/rejected/superseded/approved/wrong-digest -> %s; GATE-013 on the unapproved package -> %s, on the approved one -> %s',
                       array_to_string(v_p2[1:5],','), v_p2[6], v_p2[7]);
    blocker := null; return next;
  end;

  -- PD-PRIV-005. The hidden-metadata verdict recorded by scripts/phase_d/run_metadata_scan_probe.mjs
  -- over the committed fixture bytes, and the two fail-closed arms. The scan is a MEASUREMENT taken
  -- outside the database because Postgres never receives file bytes; this branch reads what it
  -- recorded and refuses to score a revision whose scan is absent.
  declare v_p5 text[]; v_p5_ok boolean; v_p5_n bigint;
  begin
    select count(*) into v_p5_n from public.phase_d_metadata_scan;
    select array[
      coalesce((select outcome from public.phase_d_metadata_scan
                 where revision_ref='zz-demo-rev-photo-unredacted' order by scan_id desc limit 1),'NO_SCAN'),
      coalesce((select outcome from public.phase_d_metadata_scan
                 where revision_ref='zz-demo-rev-photo-safe' order by scan_id desc limit 1),'NO_SCAN'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-photo-unredacted')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-photo-safe')),'DISPATCHABLE'),
      (select state from public.fn_phase_d_rule_check('BR-011', jsonb_build_object(
        'supplier_payload','scope only','file_revision_ref','zz-demo-rev-photo-unredacted'))),
      (select state from public.fn_phase_d_rule_check('BR-011', jsonb_build_object(
        'supplier_payload','scope only','file_revision_ref','zz-demo-rev-photo-safe'))),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-unredacted')),'DISPATCHABLE')
    ] into v_p5;
    v_p5_ok := v_p5[1]='IDENTIFIERS_FOUND' and v_p5[2]='CLEAN'
           and v_p5[3]='pd_hidden_metadata_identifier_found' and v_p5[4]='DISPATCHABLE'
           and v_p5[5]='ENFORCED_FAIL' and v_p5[6]='ENFORCED_PASS' and v_p5_n >= 4;
    defect_id:='PD-PRIV-005'; category:='PRIVACY';
    status := case when v_p5_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    -- v_p5_n is asserted (>= 4 recorded scans, or the verdicts below are about nothing) and NOT
    -- printed: it is an estate total that grows whenever another artefact is scanned, and a
    -- deliverable row that moves for a reason the case is not about does not reproduce.
    observed := format('dirty bytes -> %s, cleared bytes -> %s; dispatch %s / %s; BR-011 %s / %s',
                       v_p5[1], v_p5[2], v_p5[3], v_p5[4], v_p5[5], v_p5[6]);
    blocker := null; return next;
  end;

  -- PD-QUOTE-001. Supplier B naming supplier A's key, through the canonical write service, and
  -- supplier A rewriting their own key in the same shape. The object is SUPPLIER-scoped and goes
  -- through the same routine and the same owner_ref handling as a quotation; nothing here writes
  -- public.quotes, so no marketplace trigger fires.
  declare v_q1_a text; v_q1_b text; v_q1_msg text := ''; v_q1_ok boolean := false;
         v_q1_I text; v_q1_C text; v_q1_n bigint;
  begin
    begin
      select id::text into v_q1_a from public.leads order by id limit 1;
      select id::text into v_q1_b from public.leads order by id offset 1 limit 1;
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','supplier_correction_case','business_key','pd-quote-001','owner_ref',v_q1_a,
        'created_by','pd_quote_001','state','open','payload',jsonb_build_object('n',1)));
      begin
        perform public.fn_phase_d_object_write(jsonb_build_object(
          'object_id','supplier_correction_case','business_key','pd-quote-001','owner_ref',v_q1_b,
          'created_by','pd_quote_001','state','in_progress','payload',jsonb_build_object('n',2)));
        v_q1_I := 'ACCEPTED';
      exception when others then
        v_q1_I := case when position('pd_object_cross_owner_write' in SQLERRM) > 0
                       then 'pd_object_cross_owner_write' else 'other:'||SQLSTATE end;
      end;
      begin
        perform public.fn_phase_d_object_write(jsonb_build_object(
          'object_id','supplier_correction_case','business_key','pd-quote-001','owner_ref',v_q1_a,
          'created_by','pd_quote_001','state','in_progress','payload',jsonb_build_object('n',3)));
        v_q1_C := 'ACCEPTED';
      exception when others then v_q1_C := 'REFUSED '||SQLSTATE; end;
      select count(*) into v_q1_n from public.phase_d_object_record
       where object_id='supplier_correction_case' and business_key='pd-quote-001'
         and owner_ref = v_q1_b;
      raise exception '%', 'PDQ1' || chr(31) || v_q1_I || '|' || v_q1_C || '|' || v_q1_n;
    exception when others then
      if position('PDQ1' in SQLERRM) = 1 then v_q1_msg := split_part(SQLERRM, chr(31), 2);
      else v_q1_msg := 'BRANCH_ERROR '||left(SQLERRM,110); end if;
    end;
    v_q1_ok := split_part(v_q1_msg,'|',1)='pd_object_cross_owner_write'
           and split_part(v_q1_msg,'|',2)='ACCEPTED'
           and split_part(v_q1_msg,'|',3)='0';
    defect_id:='PD-QUOTE-001'; category:='QUOTE';
    status := case when v_q1_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('supplier B writing supplier A''''s key -> %s; supplier A rewriting their own -> %s; rows left owned by B: %s',
                       split_part(v_q1_msg,'|',1), split_part(v_q1_msg,'|',2), split_part(v_q1_msg,'|',3));
    blocker := null; return next;
  end;

  -- PD-QUOTE-004. One customer, two comparisons differing in EXACTLY ONE respect -- the publication
  -- state -- read as the owner, as an unrelated customer, and as admin.
  declare v_q4_msg text := ''; v_q4_ok boolean := false; v_q4_cust uuid; v_q4_d bigint; v_q4_p bigint;
         v_q4_a1 text; v_q4_a2 text; v_q4_a3 text; v_q4_a4 text; v_q4_n bigint;
  begin
    begin
      v_q4_cust := '00000000-0000-4000-8000-0000000c0004'::uuid;
      insert into public.quote_comparisons(inquiry_id, customer_id, lang, quote_count, signature, analysis, publication_state)
      values (gen_random_uuid(), v_q4_cust, 'en', 2, 'PD-QUOTE-004-draft', '{}'::jsonb, 'DRAFT')
      returning id into v_q4_d;
      insert into public.quote_comparisons(inquiry_id, customer_id, lang, quote_count, signature, analysis, publication_state, published_at)
      values (gen_random_uuid(), v_q4_cust, 'en', 2, 'PD-QUOTE-004-published', '{}'::jsonb, 'PUBLISHED', now())
      returning id into v_q4_p;
      select coalesce(refusal_code,'VISIBLE') into v_q4_a1 from public.fn_phase_d_comparison_visible(v_q4_d::text, v_q4_cust::text, 'customer');
      select coalesce(refusal_code,'VISIBLE') into v_q4_a2 from public.fn_phase_d_comparison_visible(v_q4_p::text, v_q4_cust::text, 'customer');
      select coalesce(refusal_code,'VISIBLE') into v_q4_a3 from public.fn_phase_d_comparison_visible(v_q4_p::text, gen_random_uuid()::text, 'customer');
      select coalesce(refusal_code,'VISIBLE') into v_q4_a4 from public.fn_phase_d_comparison_visible(v_q4_d::text, v_q4_cust::text, 'admin');
      select count(*) into v_q4_n from public.fn_phase_d_rule_check('BR-019', jsonb_build_object(
        'comparison_id', v_q4_d::text, 'caller_customer_id', v_q4_cust::text)) rc where rc.ok;
      raise exception '%', 'PDQ4' || chr(31) || v_q4_a1 || '|' || v_q4_a2 || '|' || v_q4_a3 || '|' || v_q4_a4 || '|' || v_q4_n;
    exception when others then
      if position('PDQ4' in SQLERRM) = 1 then v_q4_msg := split_part(SQLERRM, chr(31), 2);
      else v_q4_msg := 'BRANCH_ERROR '||left(SQLERRM,110); end if;
    end;
    v_q4_ok := split_part(v_q4_msg,'|',1)='pd_comparison_unpublished'
           and split_part(v_q4_msg,'|',2)='VISIBLE'
           and split_part(v_q4_msg,'|',3)='pd_comparison_not_the_owner'
           and split_part(v_q4_msg,'|',4)='VISIBLE'
           and split_part(v_q4_msg,'|',5)='0';
    defect_id:='PD-QUOTE-004'; category:='QUOTE';
    status := case when v_q4_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('owner reading their own unpublished -> %s, published -> %s; unrelated customer on the published one -> %s; admin on the draft -> %s; BR-019 passes on the draft: %s',
                       split_part(v_q4_msg,'|',1), split_part(v_q4_msg,'|',2), split_part(v_q4_msg,'|',3),
                       split_part(v_q4_msg,'|',4), split_part(v_q4_msg,'|',5));
    blocker := null; return next;
  end;

  -- PD-QUOTE-005. A supplier revision, a normalisation beside it, a replay, and an attempt to
  -- overwrite the original -- all through the object store, none of it touching public.quotes.
  declare v_q5_msg text := ''; v_q5_ok boolean := false; v_q5_rec bigint; v_q5_sha text;
         v_q5_N text; v_q5_R text; v_q5_O text; v_q5_I text; v_q5_B text; v_q5_n1 bigint; v_q5_n2 bigint;
  begin
    begin
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','quotation_revision','business_key','pd-quote-005','owner_ref','ZZ DEMO SUPPLIER',
        'created_by','pd_quote_005','state','submitted',
        'payload', jsonb_build_object('lead_time','30 days','payment_terms','50/50','scope','as tendered')));
      select o.record_id, encode(extensions.digest(convert_to(o.payload::text,'UTF8'),'sha256'),'hex')
        into v_q5_rec, v_q5_sha
        from public.phase_d_object_record o
       where o.object_id='quotation_revision' and o.business_key='pd-quote-005' and o.superseded_by is null
       order by o.record_id desc limit 1;

      -- the derived projection, referencing the original and restating none of it
      insert into public.phase_d_quote_normalisation
        (source_quote_ref, source_revision_ref, source_payload_sha256, schema_version, normalised,
         transformation, actor_role_id)
      values ('pd-quote-005','pd-quote-005', v_q5_sha, 'v1',
              jsonb_build_object('normalised_lead_time_days', 30),
              jsonb_build_object('source_fields', jsonb_build_array('lead_time'),
                                 'rule','"30 days" -> 30'), 'quote_evaluation');
      v_q5_N := 'ACCEPTED';
      select count(*) into v_q5_n1 from public.phase_d_quote_normalisation where source_revision_ref='pd-quote-005';

      -- replay: identical source, identical schema version -> no second row
      begin
        insert into public.phase_d_quote_normalisation
          (source_quote_ref, source_revision_ref, source_payload_sha256, schema_version, normalised,
           transformation, actor_role_id)
        values ('pd-quote-005','pd-quote-005', v_q5_sha, 'v1',
                jsonb_build_object('normalised_lead_time_days', 30),
                jsonb_build_object('source_fields', jsonb_build_array('lead_time')), 'quote_evaluation');
        v_q5_R := 'DUPLICATED';
      exception when unique_violation then v_q5_R := 'IDEMPOTENT_NO_DUPLICATE';
                when others then v_q5_R := 'other:'||SQLSTATE; end;
      select count(*) into v_q5_n2 from public.phase_d_quote_normalisation where source_revision_ref='pd-quote-005';

      -- a projection that restates a supplier-authored field is not a projection
      begin
        insert into public.phase_d_quote_normalisation
          (source_quote_ref, source_revision_ref, source_payload_sha256, schema_version, normalised,
           transformation, actor_role_id)
        values ('pd-quote-005','pd-quote-005', v_q5_sha, 'v2',
                jsonb_build_object('lead_time','7 days'),
                jsonb_build_object('source_fields', jsonb_build_array('lead_time')), 'quote_evaluation');
        v_q5_B := 'ACCEPTED';
      exception when others then
        v_q5_B := case when position('pd_normalisation_restates_original' in SQLERRM) > 0
                       then 'pd_normalisation_restates_original' else 'other:'||SQLSTATE end;
      end;

      -- the direct overwrite of the original
      perform set_config('kernel.maintenance_reason','PD-QUOTE-005: attempt the original overwrite', true);
      begin
        update public.phase_d_object_record set payload = jsonb_build_object('lead_time','7 days')
         where record_id = v_q5_rec;
        v_q5_O := 'ACCEPTED';
      exception when others then
        v_q5_O := case when position('pd_object_overwrite_refused' in SQLERRM) > 0
                       then 'pd_object_overwrite_refused' else 'other:'||SQLSTATE end;
      end;
      perform set_config('kernel.maintenance_reason','', true);

      select case when qi.intact then 'INTACT' else coalesce(qi.refusal_code,'NOT_INTACT') end into v_q5_I
        from public.fn_phase_d_quote_original_intact('pd-quote-005') qi;
      raise exception '%', 'PDQ5' || chr(31) || v_q5_N || '|' || v_q5_R || '|' || v_q5_B || '|' || v_q5_O || '|' || v_q5_I || '|' || v_q5_n1||'/'||v_q5_n2;
    exception when others then
      if position('PDQ5' in SQLERRM) = 1 then v_q5_msg := split_part(SQLERRM, chr(31), 2);
      else v_q5_msg := 'BRANCH_ERROR '||left(SQLERRM,110); end if;
    end;
    v_q5_ok := split_part(v_q5_msg,'|',1)='ACCEPTED'
           and split_part(v_q5_msg,'|',2)='IDEMPOTENT_NO_DUPLICATE'
           and split_part(v_q5_msg,'|',3)='pd_normalisation_restates_original'
           and split_part(v_q5_msg,'|',4)='pd_object_overwrite_refused'
           and split_part(v_q5_msg,'|',5)='INTACT'
           and split_part(split_part(v_q5_msg,'|',6),'/',1)=split_part(split_part(v_q5_msg,'|',6),'/',2);
    defect_id:='PD-QUOTE-005'; category:='QUOTE';
    status := case when v_q5_ok then 'IDEMPOTENT_NO_DUPLICATE' else 'NOT_REFUSED' end;
    observed := format('normalisation -> %s; replay -> %s (rows %s); restating an original field -> %s; direct overwrite -> %s; original %s',
                       split_part(v_q5_msg,'|',1), split_part(v_q5_msg,'|',2), split_part(v_q5_msg,'|',6),
                       split_part(v_q5_msg,'|',3), split_part(v_q5_msg,'|',4), split_part(v_q5_msg,'|',5));
    blocker := null; return next;
  end;

  -- ---- Remaining rows whose subject exists but whose injection needs a committed run ------------
  for v_key, v_msg in
    select * from (values
      ('PD-ZZ-LIST-TAIL','TAIL: not a defect and never emitted. Removing a row from this list must not strip the comma from its neighbour, so the list ends on a row nobody removes and the loop filters it out by name.')
    ) as t(a,b) where t.a <> 'PD-ZZ-LIST-TAIL'
  loop
    defect_id := v_key; category := split_part(v_msg, ':', 1); status := 'NOT_RUN';
    observed := null; blocker := v_msg;
    return next;
  end loop;
end $function$;
