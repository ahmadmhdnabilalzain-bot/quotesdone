-- PHASE D · D8d — "NO TRANSITION" IS NOT "AN UNDECLARED TRANSITION", AND THE DIFFERENCE WAS 55 STEPS.
--
-- Driving W04 through the real path reached step 2 and stopped:
--
--   W04-S02  pd_gate_refused
--     GATE-006  "transition active -> active is NOT declared in the frozen model"
--
-- MEASURED, before deciding anything:
--
--   phase_b_workflow_transition rows where from_state = to_state          0 of 35
--   frozen steps declaring success_workflow_state = 'active'             55 of 257
--
-- So a run sitting in 'active' that completes any one of 55 steps stays in 'active', GATE-006 looks
-- for an active -> active row, finds none, and blocks. Those 55 steps could never pass this gate,
-- under any evidence, in any workflow. It is the condition that cannot NOT fire — the same shape as
-- the rule that held 32 handoffs because a report always shares vocabulary with the failure it
-- reports, and as BR-043 demanding an authority reference for an exception nobody proposed.
--
-- THIS IS NOT A WEAKENING, AND THE DISTINCTION IS THE WHOLE POINT. GATE-006 is
-- "only declared state transitions may be applied". When from_state = to_state, NO transition is
-- applied: the run does not move. There is nothing for the gate to refuse, and refusing anyway is
-- the gate answering a question it was not asked. Every genuinely undeclared PAIR is still refused,
-- and a positive control below proves it on this same deployment rather than asserting it.
--
-- What would have been a weakening, and is not done here: making the gate pass when the pair is
-- absent, or when either side is empty. Both still block — the evidence check above the predicate is
-- untouched.

begin;

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
    v_ok := true;
    reason := format('GATE-005: step declares founder_gate %s and the call names authority %s',
                     left(coalesce(s.founder_gate,'none'),60), p_evidence->>'founder_authority_ref');

  elsif p_gate_id = 'GATE-006' then
    -- A STEP THAT DOES NOT MOVE THE RUN APPLIES NO TRANSITION. 55 of the 257 frozen steps declare
    -- success_workflow_state = 'active', the frozen model holds 0 self-transitions, and the previous
    -- body therefore refused all 55 whatever evidence they carried. Same state on both sides is the
    -- absence of a transition, not an undeclared one.
    if p_evidence->>'from_state' = p_evidence->>'to_state' then
      v_ok := true;
      reason := format('GATE-006: the run stays in %s — this step applies no workflow-state '
                    || 'transition, so there is none to declare. The frozen model holds no '
                    || 'self-transition and 55 of 257 steps declare the state they are already in.',
                       p_evidence->>'from_state');
    else
      select count(*) into v_n from public.phase_b_workflow_transition t
       where t.from_state = p_evidence->>'from_state' and t.to_state = p_evidence->>'to_state';
      v_ok := (v_n > 0);
      reason := format('GATE-006: transition %s -> %s is %s in the frozen model',
                       p_evidence->>'from_state', p_evidence->>'to_state',
                       case when v_ok then 'declared' else 'NOT declared' end);
    end if;

  elsif p_gate_id = 'GATE-007' then
    v_ok := true;
    reason := 'GATE-007: packet, source version and requested action are all present and non-empty';

  elsif p_gate_id = 'GATE-008' then
    select count(*) into v_n from public.phase_c_workflow_step_run x
     where x.run_id = (p_evidence->>'run_id')::bigint
       and x.state not in ('completed','cancelled','failed','superseded','skipped');
    v_ok := (v_n = 0);
    reason := format('GATE-008: %s step run(s) still open on run %s', v_n, p_evidence->>'run_id');

  elsif p_gate_id = 'GATE-009' then
    v_ok := true;
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
    v_ok := (v_n <= 25);
    reason := format('GATE-032: %s active cron job(s) against the selective automation hold ceiling of 25', v_n);

  elsif p_gate_id in ('GATE-022','GATE-023','GATE-024','GATE-025','GATE-026','GATE-027',
                      'GATE-028','GATE-029','GATE-030') then
    v_ok := true;
    reason := format('%s (%s): all declared evidence is present and non-empty [%s]. '
                  || 'The keys are checked; the CONTENT behind them is not yet verifiable from '
                  || 'this database, which is stated rather than implied.',
                     g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '));

  else
    state := 'NOT_IMPLEMENTED'; passed := false;
    reason := format('gate %s has no predicate in fn_phase_d_gate_evaluate — blocked', p_gate_id);
    return next; return;
  end if;

  state := case when v_ok then 'PASSED' else 'BLOCKED' end;
  passed := coalesce(v_ok, false);
  return next;
end $fn$;

-- ---- POSITIVE CONTROL, ON THIS DEPLOYMENT, NOT AS A CLAIM --------------------------------------
-- A gate that was just taught a new pass case has to be shown still refusing. Zero cannot tell a
-- dead guard from an idle system, so the guard is made to fire.
do $$
declare v_state text; v_passed boolean;
begin
  -- GENUINELY UNDECLARED PAIR: must still BLOCK. The first attempt used active -> completed,
  -- which the control caught as a PASS because that transition IS declared — the control doing its
  -- job on the file that introduced it. completed -> active is the reverse of the only edge leaving
  -- 'completed' (completed -> superseded) and appears nowhere in the 35.
  select ge.state, ge.passed into v_state, v_passed
    from public.fn_phase_d_gate_evaluate('GATE-006',
      jsonb_build_object('step_id','W04-S02','from_state','completed','to_state','active')) ge;
  if v_passed or v_state <> 'BLOCKED' then
    raise exception 'GATE-006 positive control FAILED: completed -> active returned %/% and must block',
      v_state, v_passed;
  end if;

  -- the no-transition case: must now PASS
  select ge.state, ge.passed into v_state, v_passed
    from public.fn_phase_d_gate_evaluate('GATE-006',
      jsonb_build_object('step_id','W04-S02','from_state','active','to_state','active')) ge;
  if not v_passed then
    raise exception 'GATE-006: active -> active still blocks after the fix (% / %)', v_state, v_passed;
  end if;

  -- a declared pair: must PASS
  select ge.state, ge.passed into v_state, v_passed
    from public.fn_phase_d_gate_evaluate('GATE-006',
      jsonb_build_object('step_id','W04-S02','from_state','active','to_state','waiting_handoff')) ge;
  if not v_passed then
    raise exception 'GATE-006: a declared transition active -> waiting_handoff blocks (% / %)',
      v_state, v_passed;
  end if;

  -- missing evidence: must still BLOCK
  select ge.state, ge.passed into v_state, v_passed
    from public.fn_phase_d_gate_evaluate('GATE-006', jsonb_build_object('step_id','W04-S02')) ge;
  if v_passed then
    raise exception 'GATE-006 now passes with NO evidence — that is the weakening this file avoids';
  end if;
end $$;

commit;
