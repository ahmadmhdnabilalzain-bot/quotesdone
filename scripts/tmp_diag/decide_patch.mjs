// PATCHES for public.fn_phase_d_run_injected_defects() — the ten cases of the thirteen that turned
// out to have a live refusal mechanism and a control that differs in exactly one respect.
//
// Every `find` is an exact substring of the CURRENT live body (dumped 24 Aug 2026) and none of them
// touches PD-IDEM-002, PD-REV-002/004/005, PD-STATE-002/003, PD-TRACE-003/004, PD-DISP-001/002/004
// or PD-LEGAL-002, which are owned elsewhere.
//
// Every verdict below was produced by execution against production inside a transaction that ends
// in `raise exception`; see scripts/tmp_diag/decide_probeB.mjs / decide_probeD.mjs for the runs.
//
// ORDERING NOTE. `list-tail-guard` must be applied before (or independently of) the row removals in
// the second values list: it makes the list end on a row nobody removes, so deleting any real row
// above it cannot strip the comma off its neighbour. The loop is given `where t.a <> ...` so the
// tail row is never emitted and the population stays at 75.

const NEW_BRANCHES = `  -- ---- Ten injections that DO have a live refusal, each with a control -------------------------
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

    -- PD-AUTH-005 category overlay presented as the accountable task owner.
    begin
      v_task := public.fn_phase_c_task_create(jsonb_build_object(
        'source_kind','defect_probe','source_ref','zz-auth-005','accountable_role_id', v_ovl,
        'objective','zz','idempotency_key','zz-pd-auth-005-inj'));
      v_state := 'ACCEPTED';
    exception when others then v_state := 'REFUSED'; v_code := left(SQLERRM, 90); end;
    begin
      v_task := public.fn_phase_c_task_create(jsonb_build_object(
        'source_kind','defect_probe','source_ref','zz-auth-005c','accountable_role_id','compliance_and_privacy_officer',
        'objective','zz','idempotency_key','zz-pd-auth-005-ctl'));
      v_ctl := 'ACCEPTED';
    exception when others then v_ctl := 'REFUSED: ' || left(SQLERRM, 60); end;
    v_ok := v_state = 'REFUSED' and v_ctl = 'ACCEPTED';
    defect_id:='PD-AUTH-005'; category:='AUTH';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('fn_phase_c_task_create, the only routine in kernel_write_authority permitted to open a task: overlay %s as accountable owner -> %s (%s); the same call naming an active canonical role -> %s. z10_phase_c_overlay_not_accountable stands behind it.',
                       v_ovl, v_state, v_code, v_ctl);
    blocker := null; return next;

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

    -- PD-LEGAL-005 the creator performs its own final COMPLIANCE review.
    begin
      v_task := public.fn_phase_c_task_create(jsonb_build_object(
        'source_kind','defect_probe','source_ref','zz-legal-005','workflow_id','W28','step_id','W28-S04',
        'accountable_role_id','compliance_and_privacy_officer','reviewer_required', true,
        'reviewer_role_id','compliance_and_privacy_officer','objective','zz','idempotency_key','zz-pd-legal-005-inj'));
      v_state := 'ACCEPTED';
    exception when others then v_state := 'REFUSED'; v_code := left(SQLERRM, 80); end;
    begin
      v_task := public.fn_phase_c_task_create(jsonb_build_object(
        'source_kind','defect_probe','source_ref','zz-legal-005c','workflow_id','W28','step_id','W28-S04',
        'accountable_role_id','compliance_and_privacy_officer','reviewer_required', true,
        'reviewer_role_id','general_counsel','objective','zz','idempotency_key','zz-pd-legal-005-ctl'));
      v_ctl := 'ACCEPTED';
    exception when others then v_ctl := 'REFUSED: ' || left(SQLERRM, 60); end;
    v_ok := v_state = 'REFUSED' and v_ctl = 'ACCEPTED';
    defect_id:='PD-LEGAL-005'; category:='LEGAL';
    status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('W28-S04 "Assess compliance and privacy" is the compliance review step of the frozen registry. Its owner as its own reviewer -> %s (%s); the same task with general_counsel reviewing -> %s. z20_phase_c_task_state_guard decides.',
                       v_state, v_code, v_ctl);
    blocker := null; return next;

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

`;

export const PATCHES = [
  // ---------------------------------------------------------------------------------------------
  // 1. Make the second values list end on a row nothing removes, so any real row above it can be
  //    deleted without stripping the comma from its neighbour. The loop skips the tail by name, so
  //    the population stays at exactly 75.
  {
    name: 'list-tail-guard',
    find: `      ('PD-LEGAL-005','LEGAL: the independence refusal is proved for reviewers (PD-REV-001); injecting it for a COMPLIANCE review needs the compliance review path, which is not a Phase D step.')
    ) as t(a,b)
  loop
    defect_id := v_key; category := split_part(v_msg, ':', 1); status := 'NOT_RUN';
    observed := null; blocker := v_msg;`,
    replace: `      ('PD-LEGAL-005','LEGAL: the independence refusal is proved for reviewers (PD-REV-001); injecting it for a COMPLIANCE review needs the compliance review path, which is not a Phase D step.'),
      ('PD-ZZ-LIST-TAIL','TAIL: not a defect and never emitted. Removing a row from this list must not strip the comma from its neighbour, so the list ends on a row nobody removes and the loop filters it out by name.')
    ) as t(a,b) where t.a <> 'PD-ZZ-LIST-TAIL'
  loop
    defect_id := v_key; category := split_part(v_msg, ':', 1); status := 'NOT_RUN';
    observed := null; blocker := v_msg;`,
  },

  // ---------------------------------------------------------------------------------------------
  // 2. Remove the nine catalogue rows whose recorded blocker is now measured to be wrong. (The
  //    tenth, PD-FIN-001, has its own explicit block and is replaced in patch 12.)
  {
    name: 'drop-row-PD-AUTH-005',
    find: `      ('PD-AUTH-005','AUTH: needs a category overlay presented as a task owner through the API path; the SQL path resolves the actor before any authority check.'),\n`,
    replace: '',
  },
  {
    name: 'drop-row-PD-PRIV-001',
    find: `      ('PD-PRIV-001','PRIVACY: needs the supplier-safe approval path to receive a payload containing a customer email and refuse it. The safe package is recorded as an object but its CONTENTS are not rendered or scanned in Phase D.'),\n`,
    replace: '',
  },
  {
    name: 'drop-row-PD-DISP-005',
    find: `      ('PD-DISP-005','DISPATCH: needs a category overlay to attempt a dispatch through an authenticated path.'),\n`,
    replace: '',
  },
  {
    name: 'drop-row-PD-LEGAL-001',
    find: `      ('PD-LEGAL-001','LEGAL: needs the certificate rendering path, which is outside Phase D.'),\n`,
    replace: '',
  },
  {
    name: 'drop-row-PD-DISP-003',
    find: `      ('PD-DISP-003','DISPATCH: GATE-013 tests who approved the safe package; injecting an UNAPPROVED one needs the approval column to be writable to a non-approver, which the write map does not permit.'),\n`,
    replace: '',
  },
  {
    name: 'drop-row-PD-QUOTE-002',
    find: `      ('PD-QUOTE-002','QUOTE: GATE-017 refuses a quote with no amount and is exercised by the W14 drive; as an INJECTION it needs a publish attempted on the incomplete quote.'),\n`,
    replace: '',
  },
  {
    name: 'drop-row-PD-QUOTE-003',
    find: `      ('PD-QUOTE-003','QUOTE: needs a technical claim with no evidence presented to the evaluation path; quotation_evaluation is bound but no Phase D step writes an evidence-bearing claim.'),\n`,
    replace: '',
  },
  {
    name: 'drop-row-PD-LEGAL-003',
    find: `      ('PD-LEGAL-003','LEGAL: needs a non-refund subject submitted to the founder approval path; that path is phase_c_refund_decision and no Phase D route writes it.'),\n`,
    replace: '',
  },
  {
    name: 'drop-row-PD-LEGAL-005',
    find: `      ('PD-LEGAL-005','LEGAL: the independence refusal is proved for reviewers (PD-REV-001); injecting it for a COMPLIANCE review needs the compliance review path, which is not a Phase D step.'),\n`,
    replace: '',
  },

  // ---------------------------------------------------------------------------------------------
  // 3. Replace the PD-FIN-001 NOT_RUN block with the ten executed branches.
  {
    name: 'executed-branches-for-the-ten',
    find: `  -- PD-FIN-001 executor also reconciles -> separation of duties.
  defect_id:='PD-FIN-001'; category:='FINANCE'; status:='NOT_RUN'; observed:=null;
  blocker := 'phase_c_refund_decision carries executor_role_id and reconciler_role_id, but no Phase D '
          || 'path writes that table — GATE-020 reads public.refunds instead. Injecting one identity into '
          || 'both columns needs the refund execution path of section 9 wired to phase_c_refund_decision, '
          || 'which is not built.';
  return next;
`,
    replace: NEW_BRANCHES,
  },
];
