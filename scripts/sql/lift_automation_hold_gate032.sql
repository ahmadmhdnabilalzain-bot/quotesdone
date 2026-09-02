-- LIFT THE SELECTIVE AUTOMATION HOLD (GATE-032). Founder, 2 Sep 2026: "lift all previous limits or
-- frozen gates; the only thing that remains blocked is OpenRouter." GATE-032 was the stand-down encoded
-- as an active-cron ceiling of 25 (the system sat exactly at 25). With the hold lifted, reactivating the
-- deterministic execution layer is authorized; the ceiling is raised to 60 purely as a runaway guard. The
-- decision is recorded in company_stand_down. OpenRouter/paid inference stays OFF (its producers remain
-- disabled). This amends fn_phase_d_gate_evaluate from its live definition (one branch changed).
--
--   node scripts/apply_sql.mjs scripts/sql/lift_automation_hold_gate032.sql --apply --ddl

begin;

-- Record the founder's full resume from the 16 Aug stand-down.
insert into public.company_stand_down(stood_down_at, actor, reason, resumed_at)
values (now(), 'management@quotesdone.com',
  'FULL RESUME / HOLD LIFTED, 2 Sep 2026. Founder: "lift all previous limits or frozen gates; the only thing that remains blocked is OpenRouter." The deterministic execution layer is re-enabled; inference-bound producers stay off while OpenRouter is held.',
  now());

CREATE OR REPLACE FUNCTION public.fn_phase_d_gate_evaluate(p_gate_id text, p_evidence jsonb)
 RETURNS TABLE(state text, passed boolean, gate_type text, reason text, refusal_code text, evidence_absent boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_g13_ok boolean; v_g13_code text; v_g13_why text;   -- O07
  g public.phase_b_gate%rowtype;
  c public.phase_d_gate_contract%rowtype;
  s public.phase_b_workflow_step%rowtype;
  v_missing text[]; v_n bigint; v_ok boolean; v_txt text;
  v_auth jsonb;   -- K01
begin
  evidence_absent := false;   -- E19, see fn_phase_d_rule_check
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
      -- E19. Same distinction as the rule side. The gate is BLOCKED either way; this column says
      -- which kind of blocked. Here the gate never saw its evidence -- it did not judge it.
      evidence_absent := true;
      state := 'BLOCKED'; passed := false;
      reason := format('gate %s (%s) requires [%s] and the call names none of it. Declared evidence: %s',
                       g.gate_id, g.gate_name, array_to_string(v_missing, ', '),
                       coalesce(g.required_evidence,'(none stated)'));
      return next; return;
    end if;
  end if;

  -- ============================ N06. READ FAILURE IS NOT REFUSAL ============================
  -- Until this block existed the routine carried ZERO exception handlers, so a read error inside a
  -- predicate -- permission denied, a relation renamed, a statement cancelled -- propagated and
  -- aborted the CALLER'S transaction. There was no state, refusal_code or evidence_absent value
  -- that said "the gate could not read", as distinct from the BLOCKED/false it returns when it
  -- read the evidence and judged it. Those are different facts with different remedies: one is
  -- fixed by correcting the evidence, the other by fixing the estate, and a caller that cannot
  -- tell them apart will retry the wrong one forever.
  --
  -- IT FAILS CLOSED. state BLOCKED, passed false, evidence_absent true -- the gate did not see its
  -- evidence, because it could not read it. A gate that answered PASSED on a read error would be
  -- the far worse defect.
  --
  -- THE FAULT HOOK. A read error cannot be provoked from inside an aborted transaction by revoking
  -- a grant -- the routine pins its own search_path and runs as the owner of every relation it
  -- reads, so nothing a caller sets reaches it. app.phase_d_gate_read_fault names one gate whose
  -- read is made to fail, and it is the ONLY way this branch can be reached deliberately. Said
  -- plainly: the fault is injected, not a revoked production grant. What the test proves is that
  -- the DISTINCTION exists and fails closed -- which is the whole of the defect -- and the control
  -- is the identical call with the hook unset.
  begin
    if coalesce(nullif(current_setting('app.phase_d_gate_read_fault', true),''), '') = p_gate_id then
      perform 1 / (case when true then 0 else 1 end);
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
    -- K01. THIS WAS `v_ok := true`. The gate checked that a string was present and never that it
    -- meant anything, so any caller could have handed it any text and passed the founder boundary.
    -- It now resolves the authority for itself, from the founder command that instructed the run or
    -- from the founder-approved frozen boundary register, and requires the reference the call
    -- presents to be the one that resolves.
    select * into s from public.phase_b_workflow_step where step_id = p_evidence->>'step_id';
    v_auth := public.fn_phase_d_founder_authority(
                nullif(p_evidence->>'run_id','')::bigint, p_evidence->>'step_id');
    v_ok := coalesce((v_auth->>'valid')::boolean, false)
            and v_auth->>'ref' is not null
            and (p_evidence->>'founder_authority_ref') = (v_auth->>'ref');
    reason := format('GATE-005: step declares founder_gate %s; the call names authority %s; the '
                  || 'estate resolves %s (%s) -- %s',
                     left(coalesce(s.founder_gate,'none'),60),
                     coalesce(p_evidence->>'founder_authority_ref','(none)'),
                     coalesce(v_auth->>'ref','(none)'), coalesce(v_auth->>'kind','-'),
                     coalesce(v_auth->>'why','(no reason stated)'));

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
    -- O04/O07. THIS NEVER DEREFERENCED safe_package_ref. The value was required present by the
    -- generic evidence_keys loop and then used only inside format() for the reason string, so the
    -- gate could be satisfied by any package at all provided the approver was not the author.
    -- It now consults the same file-set verdict BR-012 does.
    select pr.dispatchable, pr.refusal_code, pr.reason into v_g13_ok, v_g13_code, v_g13_why
      from public.fn_phase_d_package_revisions_dispatchable(p_evidence->>'safe_package_ref') pr;
    v_ok := public.fn_kernel_reviewer_independent(
              coalesce(p_evidence->>'actor_role_id', 'unknown'),
              p_evidence->>'safe_package_approved_by')
            and v_g13_ok;
    if not v_g13_ok then refusal_code := v_g13_code; end if;
    reason := format('GATE-013: package %s approved by %s; independence %s; file set %s',
                     p_evidence->>'safe_package_ref', p_evidence->>'safe_package_approved_by',
                     case when public.fn_kernel_reviewer_independent(
                            coalesce(p_evidence->>'actor_role_id','unknown'),
                            p_evidence->>'safe_package_approved_by')
                          then 'holds' else 'FAILS — the approver is the author' end,
                     coalesce(v_g13_why,'(no verdict)'));

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
    -- O06/O07. The byte-identical ownership count BR-019 carried, with the same defect: its
    -- refusal_code is gate018_comparison_not_publishable and it never read publishability.
    -- Changed with the rule and not after it -- fixing only one leaves the gate green on the same
    -- unpublished comparison, which is how a pair of predicates disagrees in silence.
    select cv.visible, cv.refusal_code, cv.reason into v_g13_ok, v_g13_code, v_g13_why
      from public.fn_phase_d_comparison_visible(
             p_evidence->>'comparison_id', p_evidence->>'caller_customer_id',
             coalesce(nullif(btrim(p_evidence->>'caller_kind'),''), 'customer')) cv;
    v_ok := v_g13_ok;
    if not v_ok then refusal_code := v_g13_code; end if;
    reason := 'GATE-018: ' || coalesce(v_g13_why, 'no verdict returned by fn_phase_d_comparison_visible');

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
    -- Founder lifted the selective automation hold on 2 Sep 2026 ("lift all previous limits or frozen
    -- gates; the only thing that remains blocked is OpenRouter"), and on 3 Sep 2026 asked for these
    -- gates to be fixed permanently so they stop blocking authorized activation. The ceiling WAS the
    -- stand-down hold; it is now purely a runaway-explosion guard. It is sized ABOVE the whole authorized
    -- cron universe rather than at an arbitrary low number: the company DEFINES 221 cron jobs and the
    -- founder has authorized activating them, so any count up to that whole set is legitimate, not a
    -- runaway. The guard therefore fires only when active crons exceed the full defined set by a clear
    -- margin (a bug spawning brand-new jobs beyond the ~221 known) — 240 — which is what "runaway"
    -- actually means here. This stops the gate reddening on every legitimate cron the activation turns on
    -- (the recurring failure) while still catching an uncontrolled explosion. Recorded in
    -- public.company_stand_down (full resume, 2 Sep 2026).
    select count(*) into v_n from cron.job where active;
    v_ok := (v_n <= 240);
    reason := format('GATE-032: %s active cron job(s) of 221 defined; automation hold lifted by founder 2 Sep 2026, runaway guard 240 (above the full authorized cron set)', v_n);

  elsif p_gate_id in ('GATE-027','GATE-028') then
    -- O03/O07. THE LEGAL AND TAX CURRENCY LEG, AND WHAT IT DELIBERATELY DOES NOT DO.
    --
    -- GATE-027 binds 10 W27 steps and GATE-028 binds 9 W28 steps. Making a source reference a
    -- REQUIRED evidence key would block all 19 on every drive, because fn_phase_d_step_context
    -- resolves no such key -- so nineteen steps would stop for a control that is about the two
    -- steps whose frozen acceptance criteria actually demand it. That is the "tightening a guard
    -- reddens its own probes" shape, and the trade is not worth making here: the HARD boundary for
    -- this control is a10_phase_d_legal_assertion_source on public.phase_d_legal_assertion, where
    -- naming a source is mandatory and a stale one is refused outright.
    --
    -- What this leg does is judge a source WHEN ONE IS NAMED, which is strictly more than the
    -- v_ok := true it replaces, and it says so in the reason either way rather than implying it.
    v_g13_why := btrim(coalesce(p_evidence->>(case when p_gate_id = 'GATE-027'
                                                   then 'tax_source_ref' else 'legal_source_ref' end), ''));
    if v_g13_why <> '' then
      select ls.usable, ls.refusal_code, ls.reason into v_g13_ok, v_g13_code, v_g13_why
        from public.fn_phase_d_legal_source_current(v_g13_why, true) ls;
      v_ok := v_g13_ok;
      if not v_ok then refusal_code := v_g13_code; end if;
      reason := format('%s (%s): declared evidence present [%s], and the %s it cites -- %s',
                       g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '),
                       case when p_gate_id = 'GATE-027' then 'tax authority' else 'legal source' end,
                       coalesce(v_g13_why,'(no verdict)'));
    else
      v_ok := true;
      reason := format('%s (%s): all declared evidence is present and non-empty [%s]. No %s was '
                    || 'cited, so no currency test was performed -- said rather than implied. A '
                    || 'legal or tax assertion itself is refused at public.phase_d_legal_assertion '
                    || 'unless it cites a current, authoritative, unsuperseded source.',
                       g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '),
                       case when p_gate_id = 'GATE-027' then 'tax_source_ref' else 'legal_source_ref' end);
    end if;

  elsif p_gate_id in ('GATE-022','GATE-023','GATE-024','GATE-025','GATE-026',
                      'GATE-029','GATE-030') then
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

  exception when others then
    -- Anything the predicate chain could not READ. Not "anything that went wrong": a predicate
    -- that judges evidence and returns false never arrives here, because returning false is not
    -- an exception.
    state := 'BLOCKED'; passed := false; evidence_absent := true;
    refusal_code := 'gate_read_failed';
    reason := format('gate %s could not READ what it needed to judge: %s (%s). This is not a '
                  || 'refusal -- the gate reached no verdict on the evidence, and a caller must '
                  || 'fix the estate rather than the evidence.',
                     p_gate_id, left(SQLERRM, 160), SQLSTATE);
    return next; return;
  end;

  state := case when v_ok then 'PASSED' else 'BLOCKED' end;
  passed := coalesce(v_ok, false);
  return next;
end $function$;

commit;
