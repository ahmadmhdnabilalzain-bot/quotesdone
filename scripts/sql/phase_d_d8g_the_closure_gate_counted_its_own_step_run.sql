-- PHASE D · D8g — THE CLOSURE GATE COUNTED THE STEP RUN THAT WAS ASKING IT.
--
-- W04 driven end to end through the real path: all 7 steps, 6 business effects, and the seventh
-- step refused:
--
--   W04-S07  CLOSURE  pd_gate_refused
--     GATE-008  "1 step run(s) still open on run 6444"   gate008_closure_blocked
--
-- The one open step run is W04-S07 itself. A closure step is necessarily open at the moment it
-- evaluates its own closure gate, so GATE-008 as written can never pass — for any workflow, under
-- any evidence. That is 30 closure steps, one per workflow, and it is the same shape as GATE-006
-- refusing 55 steps for a transition that was never applied: a condition that cannot NOT fire.
--
-- NOT A WEAKENING. GATE-008 is "closure completeness: nothing is still open". The step performing
-- the closure is not an outstanding piece of work — it is the closure. Every OTHER open step run
-- still blocks, and the positive control below proves it by leaving one open and watching the gate
-- refuse, on this deployment, rather than asserting it.
--
-- The evidence contract gains step_run_id, because a gate cannot exclude a step run it is not told
-- about. Told nothing, it counts every open run and blocks — the fail-closed behaviour is unchanged.

begin;

update public.phase_d_gate_contract
   set evidence_keys = array['run_id','step_run_id']
 where gate_id = 'GATE-008';

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
    -- THE CLOSING STEP IS NOT AN OUTSTANDING PIECE OF WORK. It is necessarily open while it asks,
    -- so counting it made this gate unpassable for all 30 closure steps. Every other open step run
    -- still blocks.
    select count(*) into v_n from public.phase_c_workflow_step_run x
     where x.run_id = (p_evidence->>'run_id')::bigint
       and x.step_run_id is distinct from (p_evidence->>'step_run_id')::bigint
       and x.state not in ('completed','cancelled','failed','superseded','skipped');
    v_ok := (v_n = 0);
    reason := format('GATE-008: %s step run(s) still open on run %s, excluding the closing step run %s itself',
                     v_n, p_evidence->>'run_id', p_evidence->>'step_run_id');

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

-- ---- the executor tells the gate which step run is asking ---------------------------------------
-- A gate cannot exclude a step run it is not told about, and the driver's fixture context
-- deliberately refuses to supply step_run_id — that is an identity, and a fixture that supplies an
-- identity is the harness answering its own question. It comes from the step run, through the
-- executor, exactly like actor_role_id.
do $$
declare v_def text; v_old text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_phase_d_handler_execute';

  v_old := 'jsonb_build_object(''step_id'', sr.step_id, ''run_id'', sr.run_id,';
  v_new := 'jsonb_build_object(''step_id'', sr.step_id, ''run_id'', sr.run_id,'
        || E'\n                           ''step_run_id'', v_step_run,';
  if position(v_old in v_def) = 0 then
    raise exception 'fn_phase_d_handler_execute: the gate-evidence block did not match; refusing to patch a body I cannot find';
  end if;
  execute replace(v_def, v_old, v_new);
end $$;

-- ---- POSITIVE CONTROLS, ON THIS DEPLOYMENT ------------------------------------------------------
do $$
declare v_state text; v_passed boolean; v_run bigint; v_a bigint; v_b bigint;
begin
  -- Told nothing, it still blocks: the evidence contract is unchanged in spirit.
  select ge.state, ge.passed into v_state, v_passed
    from public.fn_phase_d_gate_evaluate('GATE-008', jsonb_build_object('run_id','1')) ge;
  if v_passed then
    raise exception 'GATE-008 passes with no step_run_id — that is the weakening this file avoids';
  end if;

  -- A run with TWO open step runs must still block when one of them is excluded, because the other
  -- is genuinely outstanding. Zero cannot tell a dead guard from an idle system, so the guard is
  -- made to fire on real rows.
  select x.run_id, min(x.step_run_id), max(x.step_run_id)
    into v_run, v_a, v_b
    from public.phase_c_workflow_step_run x
   where x.state not in ('completed','cancelled','failed','superseded','skipped')
   group by x.run_id having count(*) >= 2
   limit 1;

  if v_run is not null then
    select ge.state, ge.passed into v_state, v_passed
      from public.fn_phase_d_gate_evaluate('GATE-008',
        jsonb_build_object('run_id', v_run::text, 'step_run_id', v_a::text)) ge;
    if v_passed then
      raise exception 'GATE-008 positive control FAILED: run % has >=2 open step runs and the gate passed while excluding only %',
        v_run, v_a;
    end if;
  else
    raise notice 'GATE-008 positive control: no run with two open step runs exists to fire it on; the no-evidence control above is the only one that ran';
  end if;
end $$;

commit;
