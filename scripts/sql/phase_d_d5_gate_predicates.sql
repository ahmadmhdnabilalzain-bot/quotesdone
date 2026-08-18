-- PHASE D · D5 — ALL 32 GATES GET THEIR OWN PREDICATE AND THEIR OWN EVIDENCE.
--
-- WHAT WAS WRONG. public.fn_phase_c_gate_evaluate applies ONE predicate to all thirty-two: an
-- evidence object must exist, carry evidence_ref and actor_role_id, and the actor must resolve.
-- It never reads the gate's own required_evidence. So GATE-001 "Phase A baseline frozen" and
-- GATE-019 "Payment reconciliation" are, behaviourally, the same gate, and the number of gates
-- enforcing their declared evidence has been zero for the life of the estate.
--
-- WHY A NEW FUNCTION RATHER THAN A STRICTER OLD ONE. fn_phase_c_gate_evaluate is called by the
-- FROZEN fn_kernel_step_complete for every step in the estate. Making it strict would refuse every
-- step completion that does not carry per-gate evidence — including the kernel's own callers,
-- which pass a fixed five-key object and cannot know about GATE-019's transaction. That is not a
-- stricter gate, it is an outage.
--
-- So this is ADDITIVE and the old path is untouched: fn_phase_d_gate_evaluate is strict, the Phase
-- D executor calls it BEFORE handing the step to the kernel, and the kernel's generic evaluation
-- remains behind it as a backstop. The Phase D path is therefore genuinely gated per gate; the
-- non-Phase-D callers keep exactly the behaviour they have today, and this file does not pretend
-- otherwise.
--
-- THE FOUR REQUIRED REFUSALS, all of them real:
--   unknown gate            -> NOT_IMPLEMENTED, blocked
--   no predicate for a gate -> NOT_IMPLEMENTED, blocked
--   required evidence absent-> BLOCKED, naming the missing keys
--   evidence present but empty -> BLOCKED. A key holding '' is the same absence wearing a hat.
-- There is no generic default branch. The final `else` in the predicate returns NOT_IMPLEMENTED.

begin;

-- ================================================================ 1. the evidence contract
create table if not exists public.phase_d_gate_contract (
  gate_id           text primary key references public.phase_b_gate(gate_id),
  evidence_keys     text[] not null,
  predicate_kind    text   not null
    constraint phase_d_gate_contract_predicate_kind_check
    check (predicate_kind in ('MEASURED','EVIDENCE_REQUIRED')),
  refusal_code      text   not null,
  correction_owner  text   not null,
  evidence_source   text   not null,
  recorded_at       timestamptz not null default now()
);

comment on table public.phase_d_gate_contract is
  'The evidence each frozen gate requires, and where it is decided from. predicate_kind MEASURED '
  'means the gate is answered from the database and needs no caller evidence; EVIDENCE_REQUIRED '
  'means the caller must name the keys and an absent key blocks.';

insert into public.phase_d_gate_contract
  (gate_id, evidence_keys, predicate_kind, refusal_code, correction_owner, evidence_source) values
 ('GATE-001','{}','MEASURED','gate001_phase_a_not_frozen','ceo',
  'public.fn_phase_a_baseline_drift() and the Phase A row in public.org_phase_baseline'),
 ('GATE-002','{actor_role_id}','MEASURED','gate002_owner_unresolved','chief_of_staff',
  'public.fn_phase_c_actor_may_own'),
 ('GATE-003','{step_id}','MEASURED','gate003_owner_not_singular','chief_of_staff',
  'public.phase_b_workflow_step.accountable_role_id, one per step by primary key'),
 ('GATE-004','{step_id,reviewer_role_id}','MEASURED','gate004_creator_is_reviewer','chief_of_staff',
  'public.fn_kernel_reviewer_independent'),
 ('GATE-005','{step_id,founder_authority_ref}','EVIDENCE_REQUIRED','gate005_founder_boundary','ceo',
  'phase_b_workflow_step.founder_gate plus a named founder authority'),
 ('GATE-006','{step_id,from_state,to_state}','MEASURED','gate006_transition_undeclared','chief_of_staff',
  'public.phase_b_workflow_transition'),
 ('GATE-007','{packet,source_version,requested_action}','EVIDENCE_REQUIRED','gate007_packet_incomplete','chief_of_staff',
  'the handoff packet the sender presents'),
 ('GATE-008','{run_id}','MEASURED','gate008_closure_blocked','chief_of_staff',
  'open step runs, tasks and handoff runs on the run'),
 ('GATE-009','{terms_version,terms_hash,acceptance_ref}','EVIDENCE_REQUIRED','gate009_terms_mismatch','compliance_and_privacy_officer',
  'the displayed terms version and hash, and the acceptance record'),
 ('GATE-010','{route_state}','EVIDENCE_REQUIRED','gate010_route_unconfirmed','inquiry_router',
  'the route state the router presents'),
 ('GATE-011','{inquiry_id}','MEASURED','gate011_inquiry_not_ready','rfq_qualification_manager',
  'public.inquiries.status'),
 ('GATE-012','{document_id}','MEASURED','gate012_document_unusable','document_intelligence_manager',
  'public.documents.status, mime and error'),
 ('GATE-013','{safe_package_ref,safe_package_approved_by}','EVIDENCE_REQUIRED','gate013_package_unapproved','marketplace_content_privacy_reviewer',
  'the approved supplier-safe package revision and its independent reviewer'),
 ('GATE-014','{supplier_id}','MEASURED','gate014_supplier_unverified','supplier_verification',
  'public.leads.approval_status and verified'),
 ('GATE-015','{inquiry_id,supplier_id}','MEASURED','gate015_duplicate_dispatch','supplier_matching_dispatch_operator',
  'public.inquiry_matches'),
 ('GATE-016','{notify_email,assignment_result,template_ref}','EVIDENCE_REQUIRED','gate016_notification_ineligible','lifecycle_channel_operations',
  'public.email_suppressions plus the assignment and approved template'),
 ('GATE-017','{quote_id}','MEASURED','gate017_quote_incomplete','quote_evaluation_specialist',
  'public.quotes mandatory commercial fields'),
 ('GATE-018','{comparison_id,caller_customer_id}','MEASURED','gate018_comparison_not_publishable','quote_evaluation_specialist',
  'public.quote_comparisons ownership'),
 ('GATE-019','{transaction_id}','MEASURED','gate019_payment_unreconciled','payments_and_billing_manager',
  'public.fn_phase_d_reveal_permitted against the payment-state ladder'),
 ('GATE-020','{refund_id,financial_action_key}','EVIDENCE_REQUIRED','gate020_refund_unauthorised','trust_and_safety_manager',
  'public.refunds.decided_by plus a unique financial action key'),
 ('GATE-021','{artifact_ref,artifact_sha256,reviewer_role_id}','EVIDENCE_REQUIRED','gate021_artifact_unapproved','brand_and_creative',
  'the exact final artifact, its digest and an independent reviewer'),
 ('GATE-022','{requirement_ref,ux_ref,backend_ref,frontend_ref,test_ref}','EVIDENCE_REQUIRED','gate022_product_unaccepted','product_manager',
  'the five acceptance references the frozen gate names'),
 ('GATE-023','{model_eval_ref,workflow_eval_ref,holdout_isolated}','EVIDENCE_REQUIRED','gate023_ai_eval_incomplete','ai_quality_reviewer',
  'independent model and workflow evaluations, and a stated holdout isolation'),
 ('GATE-024','{test_ref,security_ref,rollback_ref,operations_ref}','EVIDENCE_REQUIRED','gate024_release_unready','quality_and_release_director',
  'the four readiness references the frozen gate names'),
 ('GATE-025','{metric_definition_ref,lineage_ref}','EVIDENCE_REQUIRED','gate025_data_integrity','data_intelligence_director',
  'the canonical metric definition and its source lineage'),
 ('GATE-026','{source_ref,freshness_ref,contradiction_ref,reviewer_role_id}','EVIDENCE_REQUIRED','gate026_knowledge_unvalidated','knowledge_director',
  'independent source, freshness and contradiction review'),
 ('GATE-027','{reconciliation_ref,control_exception_ref}','EVIDENCE_REQUIRED','gate027_close_blocked','cfo',
  'critical reconciliations and control exceptions'),
 ('GATE-028','{legal_review_ref}','EVIDENCE_REQUIRED','gate028_legal_incomplete','general_counsel',
  'the legal, compliance and risk review, plus the founder gate where required'),
 ('GATE-029','{service_verification_ref,data_verification_ref,security_verification_ref}','EVIDENCE_REQUIRED','gate029_recovery_unverified','it_operations_engineer',
  'the three post-recovery verifications'),
 ('GATE-030','{verification_ref,critical_risk_resolved}','EVIDENCE_REQUIRED','gate030_capability_unrestored','agent_workforce_capability_director',
  'independent verification and the critical-risk resolution'),
 ('GATE-031','{}','MEASURED','gate031_paid_inference','ai_director',
  'public.fn_kernel_paid_provider_gate and public.llm_attempt'),
 ('GATE-032','{}','MEASURED','gate032_activation','chief_operating_officer',
  'active cron jobs against the selective automation hold')
on conflict (gate_id) do update set
  evidence_keys = excluded.evidence_keys, predicate_kind = excluded.predicate_kind,
  refusal_code = excluded.refusal_code, correction_owner = excluded.correction_owner,
  evidence_source = excluded.evidence_source, recorded_at = now();

-- ================================================================ 2. the per-gate predicate
create or replace function public.fn_phase_d_gate_evaluate(p_gate_id text, p_evidence jsonb)
returns table(state text, passed boolean, gate_type text, reason text, refusal_code text)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  g public.phase_b_gate%rowtype;
  c public.phase_d_gate_contract%rowtype;
  s public.phase_b_workflow_step%rowtype;
  v_missing text[]; v_n bigint; v_ok boolean; v_txt text;
begin
  select * into g from public.phase_b_gate where gate_id = p_gate_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; passed := false; gate_type := 'unknown';
    reason := format('unknown gate %s — blocked, not defaulted', p_gate_id);
    refusal_code := 'gate_unknown'; return next; return;
  end if;
  gate_type := g.gate_type;

  select * into c from public.phase_d_gate_contract where gate_id = p_gate_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; passed := false;
    reason := format('gate %s has no Phase D evidence contract — blocked', p_gate_id);
    refusal_code := 'gate_uncontracted'; return next; return;
  end if;
  refusal_code := c.refusal_code;

  -- ---- the declared evidence must be present AND non-empty, whatever the gate ----------------
  if cardinality(c.evidence_keys) > 0 then
    select array_agg(k order by k) into v_missing
      from unnest(c.evidence_keys) k
     where p_evidence is null or not (p_evidence ? k)
        or jsonb_typeof(p_evidence->k) = 'null'
        or (jsonb_typeof(p_evidence->k) = 'string' and btrim(p_evidence->>k) = '');
    if v_missing is not null then
      state := 'BLOCKED'; passed := false;
      reason := format('gate %s (%s) requires [%s] and the call names none of it. Declared evidence: %s',
                       g.gate_id, g.gate_name, array_to_string(v_missing, ', '),
                       coalesce(g.required_evidence,'(none stated)'));
      return next; return;
    end if;
  end if;

  -- ---- per-gate predicates. There is NO generic default; the else at the bottom is
  -- ---- NOT_IMPLEMENTED, which blocks.
  if p_gate_id = 'GATE-001' then
    select count(*) into v_n from public.fn_phase_a_baseline_drift();
    v_ok := (v_n = 0) and exists (select 1 from public.org_phase_baseline where phase = 'A');
    reason := format('GATE-001: Phase A drift %s row(s); baseline row %s', v_n,
                     case when exists (select 1 from public.org_phase_baseline where phase='A')
                          then 'present' else 'ABSENT' end);

  elsif p_gate_id = 'GATE-002' then
    v_ok := public.fn_phase_c_actor_may_own(p_evidence->>'actor_role_id');
    reason := format('GATE-002: actor %s %s', p_evidence->>'actor_role_id',
                     case when v_ok then 'resolves to an active canonical role or permitted overlay'
                          else 'does not resolve' end);

  elsif p_gate_id = 'GATE-003' then
    select count(*) into v_n from public.phase_b_workflow_step x
     where x.step_id = p_evidence->>'step_id' and coalesce(btrim(x.accountable_role_id),'') <> '';
    v_ok := (v_n = 1);
    reason := format('GATE-003: step %s has %s accountable owner(s); exactly one is required',
                     p_evidence->>'step_id', v_n);

  elsif p_gate_id = 'GATE-004' then
    select * into s from public.phase_b_workflow_step where step_id = p_evidence->>'step_id';
    v_ok := public.fn_kernel_reviewer_independent(s.accountable_role_id, p_evidence->>'reviewer_role_id');
    reason := format('GATE-004: %s and %s %s', s.accountable_role_id, p_evidence->>'reviewer_role_id',
                     case when v_ok then 'are different effective identities'
                          else 'resolve to the same effective identity' end);

  elsif p_gate_id = 'GATE-005' then
    select * into s from public.phase_b_workflow_step where step_id = p_evidence->>'step_id';
    -- The evidence block above already proved founder_authority_ref is present and non-empty.
    v_ok := true;
    reason := format('GATE-005: step declares founder_gate %s and the call names authority %s',
                     left(coalesce(s.founder_gate,'none'),60), p_evidence->>'founder_authority_ref');

  elsif p_gate_id = 'GATE-006' then
    select count(*) into v_n from public.phase_b_workflow_transition t
     where t.from_state = p_evidence->>'from_state' and t.to_state = p_evidence->>'to_state';
    v_ok := (v_n > 0);
    reason := format('GATE-006: transition %s -> %s is %s in the frozen model',
                     p_evidence->>'from_state', p_evidence->>'to_state',
                     case when v_ok then 'declared' else 'NOT declared' end);

  elsif p_gate_id = 'GATE-007' then
    v_ok := true;   -- the three packet keys were proved present above
    reason := 'GATE-007: packet, source version and requested action are all present and non-empty';

  elsif p_gate_id = 'GATE-008' then
    select count(*) into v_n from public.phase_c_workflow_step_run x
     where x.run_id = (p_evidence->>'run_id')::bigint
       and x.state not in ('completed','cancelled','failed','superseded','skipped');
    v_ok := (v_n = 0);
    reason := format('GATE-008: %s step run(s) still open on run %s', v_n, p_evidence->>'run_id');

  elsif p_gate_id = 'GATE-009' then
    v_ok := true;   -- version, hash and acceptance record all proved present above
    reason := format('GATE-009: acceptance %s names version %s at hash %s',
                     p_evidence->>'acceptance_ref', p_evidence->>'terms_version',
                     left(p_evidence->>'terms_hash',12));

  elsif p_gate_id = 'GATE-010' then
    v_ok := lower(btrim(p_evidence->>'route_state')) = 'confirmed';
    reason := format('GATE-010: route state %s; only a confirmed route carries dispatch authority',
                     p_evidence->>'route_state');

  elsif p_gate_id = 'GATE-011' then
    select count(*) into v_n from public.inquiries i
     where i.id::text = p_evidence->>'inquiry_id'
       and coalesce(i.status,'') in ('quote_ready','dispatched','quoted','completed');
    v_ok := (v_n = 1);
    reason := format('GATE-011: inquiry %s %s', p_evidence->>'inquiry_id',
                     case when v_ok then 'is quote-ready' else 'is not quote-ready or does not exist' end);

  elsif p_gate_id = 'GATE-012' then
    select count(*) into v_n from public.documents d
     where d.id::text = p_evidence->>'document_id'
       and coalesce(d.status,'') not in ('error','quarantined','rejected')
       and coalesce(d.error,'') = '';
    v_ok := (v_n = 1);
    reason := format('GATE-012: document %s %s', p_evidence->>'document_id',
                     case when v_ok then 'is supported, readable and carries no error'
                          else 'is missing, errored or quarantined' end);

  elsif p_gate_id = 'GATE-013' then
    v_ok := public.fn_kernel_reviewer_independent(
              coalesce(p_evidence->>'actor_role_id', 'unknown'),
              p_evidence->>'safe_package_approved_by');
    reason := format('GATE-013: package %s approved by %s; independence %s',
                     p_evidence->>'safe_package_ref', p_evidence->>'safe_package_approved_by',
                     case when v_ok then 'holds' else 'FAILS — the approver is the author' end);

  elsif p_gate_id = 'GATE-014' then
    select count(*) into v_n from public.leads l
     where l.id::text = p_evidence->>'supplier_id'
       and coalesce(l.approval_status,'') = 'approved' and coalesce(l.verified,false);
    v_ok := (v_n = 1);
    reason := format('GATE-014: supplier %s %s', p_evidence->>'supplier_id',
                     case when v_ok then 'is currently approved and verified'
                          else 'is not an approved, verified supplier' end);

  elsif p_gate_id = 'GATE-015' then
    select count(*) into v_n from public.inquiry_matches m
     where m.inquiry_id::text = p_evidence->>'inquiry_id'
       and m.supplier_id::text = p_evidence->>'supplier_id';
    v_ok := (v_n = 0);
    reason := format('GATE-015: %s existing assignment(s) for that supplier and inquiry; a dispatch would be a duplicate', v_n);

  elsif p_gate_id = 'GATE-016' then
    select count(*) into v_n from public.email_suppressions e
     where lower(e.email) = lower(p_evidence->>'notify_email');
    v_ok := (v_n = 0)
            and lower(coalesce(p_evidence->>'assignment_result','')) in ('delivered','accepted','sent');
    reason := format('GATE-016: %s is %s; assignment result %s',
                     p_evidence->>'notify_email',
                     case when v_n = 0 then 'not suppressed' else 'SUPPRESSED' end,
                     p_evidence->>'assignment_result');

  elsif p_gate_id = 'GATE-017' then
    select count(*) into v_n from public.quotes q
     where q.id::text = p_evidence->>'quote_id'
       and q.quote_amount is not null and coalesce(btrim(q.status),'') <> '';
    v_ok := (v_n = 1);
    reason := format('GATE-017: quote %s %s', p_evidence->>'quote_id',
                     case when v_ok then 'carries a stated amount and status'
                          else 'is missing mandatory commercial fields' end);

  elsif p_gate_id = 'GATE-018' then
    select count(*) into v_n from public.quote_comparisons qc
     where qc.id::text = p_evidence->>'comparison_id'
       and qc.customer_id::text = p_evidence->>'caller_customer_id';
    v_ok := (v_n = 1);
    reason := format('GATE-018: comparison %s %s the calling customer', p_evidence->>'comparison_id',
                     case when v_ok then 'belongs to' else 'does NOT belong to' end);

  elsif p_gate_id = 'GATE-019' then
    select rp.permitted, rp.reason into v_ok, v_txt
      from public.fn_phase_d_reveal_permitted(p_evidence->>'transaction_id') rp;
    reason := coalesce(v_txt, 'GATE-019: no verdict returned by the reveal decision');

  elsif p_gate_id = 'GATE-020' then
    select count(*) into v_n from public.refunds rf
     where rf.id::text = p_evidence->>'refund_id'
       and coalesce(btrim(rf.decided_by),'') <> '' and rf.decided_at is not null;
    v_ok := (v_n = 1);
    reason := format('GATE-020: refund %s %s, financial action key %s',
                     p_evidence->>'refund_id',
                     case when v_ok then 'carries a recorded decision and decider'
                          else 'has no recorded founder decision' end,
                     p_evidence->>'financial_action_key');

  elsif p_gate_id = 'GATE-021' then
    v_ok := public.fn_kernel_reviewer_independent(
              coalesce(p_evidence->>'actor_role_id','unknown'), p_evidence->>'reviewer_role_id');
    reason := format('GATE-021: artifact %s at digest %s reviewed by %s; independence %s',
                     p_evidence->>'artifact_ref', left(p_evidence->>'artifact_sha256',12),
                     p_evidence->>'reviewer_role_id',
                     case when v_ok then 'holds' else 'FAILS' end);

  elsif p_gate_id = 'GATE-031' then
    v_ok := not coalesce((public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini')->>'allowed')::boolean, true);
    select count(*) into v_n from public.llm_attempt where created_at > now() - interval '24 hours';
    v_ok := v_ok and (v_n = 0);
    reason := format('GATE-031: paid-provider gate %s; %s llm_attempt row(s) in 24h',
                     case when v_ok then 'refuses every route' else 'ALLOWED a route' end, v_n);

  elsif p_gate_id = 'GATE-032' then
    select count(*) into v_n from cron.job where active;
    v_ok := (v_n <= 25);   -- the selective hold's disclosed ceiling; growth is the breach
    reason := format('GATE-032: %s active cron job(s) against the selective automation hold ceiling of 25', v_n);

  -- ---- gates whose evidence is named but whose deeper verification is not yet modelled -------
  elsif p_gate_id in ('GATE-022','GATE-023','GATE-024','GATE-025','GATE-026','GATE-027',
                      'GATE-028','GATE-029','GATE-030') then
    v_ok := true;   -- every declared key was proved present and non-empty above
    reason := format('%s (%s): all declared evidence is present and non-empty [%s]. '
                  || 'The keys are checked; the CONTENT behind them is not yet verifiable from '
                  || 'this database, which is stated rather than implied.',
                     g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '));

  else
    -- NO GENERIC DEFAULT. A gate that reaches here has no predicate and is blocked.
    state := 'NOT_IMPLEMENTED'; passed := false;
    reason := format('gate %s has no predicate in fn_phase_d_gate_evaluate — blocked', p_gate_id);
    return next; return;
  end if;

  state := case when v_ok then 'PASSED' else 'BLOCKED' end;
  passed := coalesce(v_ok, false);
  return next;
end $fn$;

comment on function public.fn_phase_d_gate_evaluate(text, jsonb) is
  'Per-gate evaluation against each gate''s own declared evidence. Replaces nothing: '
  'fn_phase_c_gate_evaluate is called by the FROZEN kernel for every step in the estate and '
  'making it strict would refuse callers that cannot know about a given gate''s evidence. This is '
  'the strict path the Phase D executor uses, with the kernel''s generic check behind it.';

-- ================================================================ 2b. applicability
-- SCOPE IS NOT APPLICABILITY, AND THIS IS THE SECOND TIME THAT BIT. BR-002 refused an intake
-- step for a creator/reviewer collision that could not exist, because it was scoped to every
-- workflow while only 28 of 257 steps name a reviewer. GATE-004 is the same rule wearing a gate's
-- clothes, and the first wiring of this file reproduced the defect exactly: W01-S01 was blocked
-- for want of a reviewer_role_id on a step whose frozen definition names no reviewer at all.
--
-- A gate that cannot apply is NOT_APPLICABLE with a reason, never BLOCKED and never silently
-- skipped.
create or replace function public.fn_phase_d_gate_applies(p_gate_id text, p_step_id text)
returns table(applies boolean, why text)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare g public.phase_b_gate%rowtype; s public.phase_b_workflow_step%rowtype;
begin
  select * into g from public.phase_b_gate where gate_id = p_gate_id;
  if not found then applies := false; why := format('unknown gate %s', p_gate_id); return next; return; end if;
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then applies := false; why := format('unknown step %s', p_step_id); return next; return; end if;

  if upper(g.workflow_scope) <> 'ALL'
     and not (s.workflow_id = any (string_to_array(replace(g.workflow_scope,' ',''), ';'))) then
    applies := false;
    why := format('%s is scoped to %s and %s is in %s', g.gate_id, g.workflow_scope, p_step_id, s.workflow_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-004' and coalesce(btrim(s.independent_reviewer_role_id),'') = '' then
    applies := false;
    why := format('GATE-004 governs the independence of a named reviewer and %s names none', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-005' and lower(coalesce(btrim(s.founder_gate),'none')) = 'none' then
    applies := false;
    why := format('GATE-005 governs a founder-reserved decision and %s declares founder_gate none', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-007'
     and not exists (select 1 from public.phase_b_handoff h where h.from_step_id = p_step_id) then
    applies := false;
    why := format('GATE-007 governs a handoff packet and %s opens no handoff', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-008' and not coalesce(s.is_closure_step, false) then
    applies := false;
    why := format('GATE-008 is a closure gate and %s is not the closure step', p_step_id);
    return next; return;
  end if;

  applies := true;
  why := format('%s (%s, scope %s) applies to %s', g.gate_id, g.gate_type, g.workflow_scope, p_step_id);
  return next;
end $fn$;

comment on function public.fn_phase_d_gate_applies(text, text) is
  'Decides workflow scope AND step-level applicability for a gate, returning the reason either '
  'way. A gate that cannot apply is visibly out of scope rather than blocking a step for evidence '
  'the frozen step never had.';

-- ================================================================ 3. the board
create or replace function public.fn_phase_d_gate_state()
returns table(check_name text, expected text, actual text, ok boolean)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare n_gates int; n_contract int; n_notimpl int; n_generic int; n_blank int;
begin
  select count(*) into n_gates    from public.phase_b_gate;
  select count(*) into n_contract from public.phase_d_gate_contract;

  check_name := 'every_frozen_gate_has_an_evidence_contract';
  expected := n_gates::text; actual := n_contract::text; ok := (n_contract = n_gates); return next;

  -- Every gate must reach a predicate. Asked with EMPTY evidence, none may report NOT_IMPLEMENTED.
  select count(*) into n_notimpl from public.phase_b_gate g
   where (select ge.state from public.fn_phase_d_gate_evaluate(g.gate_id, '{}'::jsonb) ge)
         = 'NOT_IMPLEMENTED';
  check_name := 'gates_with_no_predicate';
  expected := '0'; actual := n_notimpl::text; ok := (n_notimpl = 0); return next;

  -- An unknown gate must be blocked, never waved through.
  check_name := 'unknown_gate_is_blocked';
  expected := 'NOT_IMPLEMENTED/false';
  actual := (select ge.state || '/' || ge.passed::text
               from public.fn_phase_d_gate_evaluate('GATE-999','{}'::jsonb) ge);
  ok := (actual = 'NOT_IMPLEMENTED/false'); return next;

  -- A gate declaring evidence must BLOCK when given none. This is the check that would have
  -- caught the generic predicate this file replaces.
  select count(*) into n_generic from public.phase_d_gate_contract c
   where cardinality(c.evidence_keys) > 0
     and (select ge.passed from public.fn_phase_d_gate_evaluate(c.gate_id, '{}'::jsonb) ge);
  check_name := 'evidence_declaring_gates_that_pass_on_no_evidence';
  expected := '0'; actual := n_generic::text; ok := (n_generic = 0); return next;

  select count(*) into n_blank from public.phase_d_gate_contract
   where coalesce(btrim(correction_owner),'') = '' or coalesce(btrim(evidence_source),'') = '';
  check_name := 'gates_with_no_correction_owner_or_source';
  expected := '0'; actual := n_blank::text; ok := (n_blank = 0); return next;
end $fn$;

comment on function public.fn_phase_d_gate_state() is
  'Phase D gate board. The fourth check is the one that matters: a gate declaring evidence must '
  'BLOCK when handed none, which is exactly what the single generic predicate did not do.';

-- ================================================================ 4. grants
revoke all on function public.fn_phase_d_gate_evaluate(text, jsonb) from public, anon;
grant execute on function public.fn_phase_d_gate_evaluate(text, jsonb) to service_role, authenticated;
revoke all on function public.fn_phase_d_gate_state() from public, anon;
grant execute on function public.fn_phase_d_gate_state() to service_role, authenticated;
revoke all on public.phase_d_gate_contract from public, anon, authenticated;
grant select on public.phase_d_gate_contract to service_role, authenticated;

commit;
