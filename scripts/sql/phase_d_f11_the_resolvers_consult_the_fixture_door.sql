-- F11 - the two resolvers consult the fixture door for a key no real row answers
--
-- fn_phase_d_step_context ends its key chain with a comment that has been correct all along:
--
--     40 of the 71 declared context keys still land here, and that is correct: artifact_sha256,
--     terms_hash, legal_review_ref, denominator, formula, outcome_metric and the rest are facts a
--     CALLER produces at runtime, not facts this estate holds.
--
-- The founder's ruling of 21 Aug 2026 supplies the caller. Section B: the scenario catalogue
-- supplies explicit test values, the handler receives the fixture as input, and the handler must
-- not generate the fixture itself. This file is the mechanical form of that sentence.
--
-- WHERE THE DOOR IS, AND WHY THERE.
--
--   fn_phase_d_dispatch_step  ->  fn_phase_d_step_inputs   (resolver)   <- the door is here
--                             ->  fn_phase_d_step_context  (resolver)   <- and here
--                             ->  fn_phase_d_handler_execute (handler)  <- and NOT here
--
-- The handler is handed a payload. It has no call to fn_phase_d_fixture_input and no way to reach
-- the catalogue, so "the handler must not generate the fixture itself" is a property of the call
-- graph rather than a rule someone has to remember.
--
-- WHERE THE DOOR IS IN THE ORDER, AND WHY LAST. Every real source is tried first. A key an actual
-- row can answer is answered by that row and the fixture never shadows a fact; the fixture only
-- reaches a key that would otherwise have been unresolved, which is precisely the population the
-- comment above describes.
--
-- WHY PRODUCTION DOES NOT MOVE. fn_phase_d_fixture_input returns no row unless
-- fn_phase_d_fixture_context() verifies an hmac over the current txid, keyed by a secret no role
-- can SELECT (F01). In production there is no such context. Every key that is unresolved today is
-- unresolved after this file, and every rule and gate that refuses today refuses after it.

CREATE OR REPLACE FUNCTION public.fn_phase_d_step_context(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  r  public.phase_c_workflow_run%rowtype;
  s  public.phase_b_workflow_step%rowtype;
  b  public.phase_d_handler_binding%rowtype;
  ec public.phase_d_step_effect%rowtype;
  v_keys   text[];
  v_k      text;
  v_val    jsonb;
  v_src    text;
  v_ctx    jsonb := '{}'::jsonb;
  v_prov   jsonb := '{}'::jsonb;
  v_unres  text[] := '{}';
  v_obj    text;
  v_boid   text;
  v_rel    text;
  v_keycol text;
  v_owncol text;
  v_row_id text;
  v_row_own text;
  v_found  boolean := false;
  v_key_prefixed boolean := false;   -- E25
  v_sql    text;
  v_from   text;
  v_to     text;
  v_route  text;
  v_cmd    bigint;
  v_src_ref   text;
  v_src_kind  text;
  v_src_class text;
  v_src_actor text;
  v_src_act   text;
  v_email     text;
  v_fx_val    jsonb;   -- F11
  v_fx_src    text;    -- F11
begin
  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then
    raise exception 'fn_phase_d_step_context: no step run %', p_step_run_id using errcode = '23503';
  end if;
  select * into r  from public.phase_c_workflow_run    where run_id  = sr.run_id;
  select * into s  from public.phase_b_workflow_step   where step_id = sr.step_id;
  select * into b  from public.phase_d_handler_binding where step_id = sr.step_id;
  select * into ec from public.phase_d_step_effect     where step_id = sr.step_id;

  select coalesce(array_agg(distinct k), '{}') into v_keys from (
    select unnest(re.required_context) k from public.phase_d_rule_enforcement re
     where re.rule_id = any (coalesce(b.rule_ids,'{}'))
    union
    select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
     where gc.gate_id = any (coalesce(b.gate_ids,'{}'))) q(k);

  -- ---- the frozen state model ------------------------------------------------------------------
  v_from  := r.state;
  -- E12. THE RESOLVER NULLED A FACT THE GATE EXISTS TO JUDGE.
  --
  -- to_state is the step's own frozen declaration: phase_b_workflow_step.success_workflow_state.
  -- Until now this line also re-ran GATE-006's test on it, and blanked the value when the test
  -- failed. That is a different act from resolving, and it had two consequences.
  --
  -- First, it made the answer depend on WHEN the resolver was called rather than on what the
  -- registry says. fn_phase_d_dispatch_step runs inside fn_kernel_open_step, and a step opened out
  -- of a handoff is dispatched while its run is still in waiting_handoff -- the state it is
  -- leaving. The old guard therefore asked whether the run could go waiting_handoff ->
  -- waiting_handoff, which the frozen model rightly says it cannot, and nulled the key. Called a
  -- moment later, against the same step run, the same function resolved it. Measured 2026-08-20:
  -- W01-S04/S05/S06 record to_state in phase_d_dispatch.unresolved_keys, and a direct call for the
  -- same step runs resolves it to waiting_handoff.
  --
  -- Second, and worse, it turned a judgeable fact into an absent one. GATE-006 already tests the
  -- transition against public.phase_b_workflow_transition, and already holds the reasoned branch
  -- for the case where a step declares the state it is already in (55 of 257 steps do). With the
  -- key blanked, the gate could not reach either branch and reported "requires [to_state] and the
  -- call names none of it" -- an evidence-absence message standing in for a judgement the
  -- instrument was built to make.
  --
  -- The resolution is therefore the declaration, and the judgement stays with the gate. This is a
  -- REMOVAL: nothing new is asserted, and a transition the frozen model does not declare is still
  -- refused -- by GATE-006, which is the check that owns it.
  v_to    := nullif(btrim(coalesce(s.success_workflow_state,'')),'');
  -- D42. route_state IS NOT "the first declared transition, alphabetically". That is what this
  -- resolver did, and GATE-010 duly reported "route state approved; only a confirmed route carries
  -- dispatch authority" for an inquiry that had never been routed. Picking a plausible value out of
  -- the declared set is the placeholder defect wearing a schema. A route state exists when a route
  -- has been confirmed; until then the key is unresolved and GATE-010 refuses, which is the gate
  -- doing its job.
  v_route := null;

  -- ---- the arrival that caused this run, and how the register classifies it ---------------------
  select ti.source_system, 'trigger' into v_src_ref, v_src_kind
    from public.kernel_trigger_inbox ti where ti.run_id = sr.run_id order by ti.inbox_id desc limit 1;
  if v_src_ref is null and coalesce(btrim(coalesce(r.business_object_id,'')),'') <> '' then
    -- D39(2). The first step of a run dispatches INSIDE fn_kernel_workflow_start, before the inbox
    -- row is stamped with run_id. business_object_id is on both sides already, derived from the same
    -- object rule, so it is what links them at the only moment that matters.
    select ti.source_system, 'trigger' into v_src_ref, v_src_kind
      from public.kernel_trigger_inbox ti
     where ti.business_object_id = r.business_object_id
     order by ti.inbox_id desc limit 1;
  end if;
  if v_src_ref is null then
    select si.source_type, 'signal' into v_src_ref, v_src_kind
      from public.kernel_signal_inbox si
     where si.workflow_run_id = sr.run_id order by si.signal_id desc limit 1;
  end if;
  if v_src_ref is null then
    select tk.source_ref, tk.source_kind into v_src_ref, v_src_kind
      from public.phase_c_task tk where tk.run_id = sr.run_id order by tk.task_id limit 1;
  end if;
  -- D40. THE INBOX ROW IS NOT READABLE BY run_id OR business_object_id AT FIRST-STEP DISPATCH TIME.
  -- fn_kernel_trigger_submit inserts the inbox row, then calls fn_kernel_workflow_start passing
  -- source_ref = 'trigger_inbox:<inbox_id>', and stamps run_id and business_object_id onto that row
  -- only AFTER the call returns. The dispatch happens inside it, so both earlier matches were looking
  -- for columns the row does not carry yet. The inbox id IS in the source_ref the kernel already
  -- passes, and fn_kernel_workflow_start writes it onto the task before it opens the step — the one
  -- identifier available at the only moment that matters.
  if v_src_ref like 'trigger_inbox:%' then
    select ti.source_system, 'trigger' into v_src_ref, v_src_kind
      from public.kernel_trigger_inbox ti
     where ti.inbox_id = nullif(substr(v_src_ref, 15), '')::bigint;
  end if;
  if coalesce(btrim(coalesce(v_src_ref,'')),'') <> '' then
    select c.source_class, c.system_actor, c.current_activation
      into v_src_class, v_src_actor, v_src_act
      from public.phase_c_source_cutover c
     where c.source_component_id = v_src_ref limit 1;
  end if;

  -- ---- the run's own business object -----------------------------------------------------------
  v_obj := coalesce(nullif(btrim(coalesce(ec.effect_object_id,'')),''),
                    (select bo.object_id from public.phase_d_business_object_binding bo
                      where bo.governing_workflow_id = r.workflow_id limit 1));
  v_boid := nullif(btrim(coalesce(r.business_object_id,'')),'');
  -- D39(1). The kernel writes the object rule out in full: 'inquiry:<uuid>'. Strip ONLY that
  -- object's own prefix; a blind split on ':' would corrupt an identifier that contains one.
  -- E25. WHETHER THE PREFIX MATCHED IS ITSELF A FACT, and the caller needs it. A run whose
  -- business_object_id is 'inquiry:<uuid>' names the object this step writes; one that reads
  -- 'outbox:195' or a probe label does not, and using the raw string as a business key would invent
  -- an identity for a record. Only a stripped key is a key.
  v_key_prefixed := (v_obj is not null and v_boid is not null and v_boid like (v_obj || ':%'));
  if v_key_prefixed then
    v_boid := substr(v_boid, length(v_obj) + 2);
  end if;
  if v_obj is not null and coalesce(v_boid,'') <> '' then
    select wm.target_relation, wm.key_column, wm.owner_column
      into v_rel, v_keycol, v_owncol
      from public.phase_d_object_write_map wm where wm.object_id = v_obj limit 1;
    if v_rel is not null and coalesce(btrim(v_keycol),'') <> ''
       and to_regclass(v_rel) is not null then
      begin
        v_sql := format('select %I::text, %s from %s where %I::text = $1 limit 1',
                        v_keycol,
                        case when coalesce(btrim(v_owncol),'') = '' then 'null::text'
                             else quote_ident(v_owncol) || '::text' end,
                        to_regclass(v_rel)::text, v_keycol);
        execute v_sql into v_row_id, v_row_own using v_boid;
        v_found := v_row_id is not null;
      exception when others then
        v_found := false;
      end;
    end if;
  end if;

  foreach v_k in array v_keys loop
    v_val := null; v_src := null;

    if v_k = 'from_state' then
      v_val := to_jsonb(v_from); v_src := 'phase_c_workflow_run.state';
    elsif v_k = 'to_state' then
      if v_to is not null then
        v_val := to_jsonb(v_to);
        v_src := 'phase_b_workflow_step.success_workflow_state, confirmed against phase_b_workflow_transition';
      end if;
    elsif v_k = 'route_state' then
      -- Resolved only from a route that actually exists. See the note above v_route.
      if v_route is not null then
        v_val := to_jsonb(v_route); v_src := 'the confirmed route for this inquiry';
      end if;

    elsif v_k in ('inquiry_id','supplier_id','quote_id','transaction_id','document_id',
                  'comparison_id','refund_id') then
      if v_found then
        v_val := to_jsonb(v_row_id);
        v_src := format('%s.%s, looked up by the run''s business_object_id', v_rel, v_keycol);
      end if;
    elsif v_k = 'caller_customer_id' then
      if v_found and v_row_own is not null then
        v_val := to_jsonb(v_row_own);
        v_src := format('%s.%s of the run''s own object', v_rel, coalesce(v_owncol,'(none)'));
      end if;

    elsif v_k = 'inquiry_owner' then
      -- D41. inquiry_owner IS A ROLE, NOT A CUSTOMER. BR-049 is the only consumer of this key —
      -- no gate declares it — and its predicate compares it to the literal role
      -- 'rfq_qualification_manager'. Resolving it from inquiries.customer_id handed a rule about
      -- ACCOUNTABILITY a customer UUID, so it refused every inquiry the moment the owner started
      -- resolving at all. The frozen rule text is unambiguous: "Specialist and document handoffs do
      -- not transfer overall inquiry accountability away from RFQ Qualification Manager unless an
      -- explicit approved workflow says so."
      --
      -- The subject is therefore the role accountable for the INQUIRY, which is
      -- phase_c_workflow_run.accountable_role_id of the run that owns it. For a W05 run that is this
      -- run; for W06 and W07, which are the specialist workflows the rule is about, it is the W05
      -- run for the same inquiry, and where no such run exists the key stays unresolved rather than
      -- being answered with this run''s own role.
      --
      -- This is what makes the rule able to FAIL: it fails exactly when a run''s accountable role
      -- has drifted from the frozen registry''s, which is the drift BR-049 exists to catch.
      if r.workflow_id = 'W05' then
        v_val := to_jsonb(r.accountable_role_id);
        v_src := 'phase_c_workflow_run.accountable_role_id of this inquiry''s own run';
      elsif v_found then
        select to_jsonb(r2.accountable_role_id) into v_val
          from public.phase_c_workflow_run r2
         where r2.workflow_id = 'W05'
           and r2.business_object_id = ('inquiry:' || v_row_id)
         order by r2.run_id desc limit 1;
        v_src := 'phase_c_workflow_run.accountable_role_id of the W05 run that owns this inquiry';
      end if;
    elsif v_k = 'monetary_state' then
      if v_found and v_rel like '%transactions' then
        select to_jsonb(t.fee_status) into v_val from public.transactions t
          where t.id::text = v_row_id limit 1;
        v_src := 'public.transactions.fee_status of the run''s own transaction';
      end if;

    elsif v_k = 'evidence_authority' then
      if v_src_class is not null then
        v_val := to_jsonb(format('%s (%s) via %s, activation %s',
                   v_src_class, coalesce(v_src_actor,'(no system actor)'),
                   v_src_ref, coalesce(v_src_act,'(unstated)')));
        v_src := 'phase_c_source_cutover classification of the arrival that caused this run';
      end if;

    elsif v_k = 'notify_email' then
      if v_found and v_row_own is not null then
        v_email := null;
        if v_owncol = 'customer_id' then
          select c.email into v_email from public.customers c where c.id::text = v_row_own limit 1;
        elsif v_owncol in ('supplier_id','lead_id') then
          select l.email into v_email from public.leads l where l.id::text = v_row_own limit 1;
        end if;
        if coalesce(btrim(coalesce(v_email,'')),'') <> '' then
          v_val := to_jsonb(v_email);
          v_src := format('the email of %s.%s, the owner of the run''s own object', v_rel, v_owncol);
        end if;
      end if;

    elsif v_k = 'evidence_refs' then
      -- E22. A CONDITION THE FIRST STEP OF A RUN COULD NEVER MEET.
      --
      -- This resolved evidence_refs from public.phase_d_effect_ledger for the run and nothing else.
      -- The FIRST step of a run has no predecessor, so it has no prior effect, so the key was
      -- unresolvable for it by construction — not sometimes, ever. BR-027 is bound to 59 steps and
      -- applies to 7 of the estate's first steps; six of those seven (the seventh is held by the
      -- capability boundary) were refused by a rule they had no way to satisfy. Measured 2026-08-20.
      --
      -- The fix is not to hand the key a placeholder. It is to notice that a first step DOES have
      -- evidence, and that the resolver was reading the wrong subject for it: what a first step
      -- rests on is THE ARRIVAL THAT OPENED THE RUN. That is a row — phase_c_workflow_run carries
      -- start_event, command_id and opened_at, and phase_c_source_cutover classifies the source
      -- component — so naming it is a read, not an invention.
      --
      -- THE ARRIVAL COUNTS ONLY FOR A STEP WITH NO PREDECESSOR, and that restriction is what keeps
      -- BR-027 able to fail. A later step must still show what the run has PRODUCED; if its
      -- predecessors produced nothing, it still gets nothing and BR-027 still refuses. Handing every
      -- call an automatic arrival reference would have turned a rule that refuses into a rule that
      -- cannot, which is the defect this file is fixing, in the other direction.
      select case when count(*) = 0 then null
                  else jsonb_agg(jsonb_build_object(
                         'effect_id', el.effect_id, 'step_id', el.step_id,
                         'effect_type', el.effect_type,
                         'result_reference', el.result_reference) order by el.effect_id) end
        into v_val
        from public.phase_d_effect_ledger el where el.run_id = sr.run_id;
      v_src := 'phase_d_effect_ledger for this run';

      if v_val is null
         and not exists (select 1 from public.phase_c_workflow_step_run pr
                          where pr.run_id = sr.run_id and pr.step_run_id < sr.step_run_id) then
        v_val := jsonb_build_array(jsonb_build_object(
          'kind',          'arrival',
          'run_id',        sr.run_id,
          'workflow_id',   r.workflow_id,
          'start_event',   nullif(btrim(coalesce(r.start_event,'')),''),
          'command_id',    r.command_id,
          'source_ref',    nullif(btrim(coalesce(v_src_ref,'')),''),
          'source_class',  v_src_class,
          'system_actor',  v_src_actor,
          'opened_at',     r.opened_at));
        v_src := 'the arrival that opened this run (phase_c_workflow_run.start_event/command_id '
              || 'plus its phase_c_source_cutover classification) — this step has no predecessor, '
              || 'so the arrival is the evidence it rests on';
      end if;

    elsif v_k = 'handoff_id' then
      -- D50. The handoff this step opens is a row of the frozen registry, not something a caller has
      -- to remember to pass. BR-008 was refusing for want of an identifier sitting in a table.
      select to_jsonb(hc.handoff_id) into v_val
        from public.phase_d_handoff_contract hc where hc.from_step_id = sr.step_id
       order by hc.handoff_id limit 1;
      v_src := 'phase_d_handoff_contract.handoff_id for the handoff this step opens';

    elsif v_k = 'sla_policy_id' then
      -- Likewise: the SLA policy of that handoff is recorded against it in the frozen registry.
      select to_jsonb(nullif(btrim(coalesce(h.sla_policy_id,'')),'')) into v_val
        from public.phase_b_handoff h where h.from_step_id = sr.step_id
       order by h.handoff_id limit 1;
      v_src := 'phase_b_handoff.sla_policy_id of the handoff this step opens';

    elsif v_k in ('packet','requested_action','source_version') then
      select case v_k
               when 'packet' then case when hc.packet_keys is null or cardinality(hc.packet_keys) = 0
                                       then null else to_jsonb(hc.packet_keys) end
               when 'requested_action' then to_jsonb(nullif(btrim(coalesce(hc.acceptance_criteria,'')),''))
               else to_jsonb(nullif(btrim(coalesce(hc.source_object_version_key,'')),'')) end
        into v_val
        from public.phase_d_handoff_contract hc where hc.from_step_id = sr.step_id limit 1;
      v_src := 'phase_d_handoff_contract for this step';

    elsif v_k = 'founder_authority_ref' then
      select l.command_id into v_cmd from public.founder_command_workflow_link l
        where l.run_id = sr.run_id limit 1;
      if v_cmd is null then v_cmd := r.command_id; end if;
      if v_cmd is not null then
        v_val := to_jsonb('founder_command:' || v_cmd::text);
        v_src := 'founder_command that started this run';
      end if;

    elsif v_k = 'run_id' then
      -- E11. This function loads sr and r in its first ten lines and then declared run_id
      -- unresolved, which refused GATE-008 on every step in the estate for want of a number the
      -- same function was already holding.
      v_val := to_jsonb(sr.run_id);
      v_src := 'phase_c_workflow_step_run.run_id of this step run';

    elsif v_k = 'actor_role_id' then
      -- The role ACCOUNTABLE for this step run, read from the kernel's own row. Not the caller's
      -- claim about who they are: this function is given a step_run_id and nothing else, and a
      -- context resolver that took an identity from its caller would be answering the question it
      -- was asked to check.
      v_val := to_jsonb(nullif(btrim(coalesce(sr.accountable_role_id,'')),''));
      v_src := 'phase_c_workflow_step_run.accountable_role_id';

    elsif v_k = 'reviewer_role_id' then
      -- The INDEPENDENT reviewer the frozen binding declares, and only that. 45 of the 47 review
      -- steps name none, and for those this stays unresolved so GATE-004 and GATE-021 refuse —
      -- which is the gate working. Choosing a reviewer here would be fn_pick_reviewer returning the
      -- department head 182 times, one layer up.
      v_val := to_jsonb(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''));
      v_src := 'phase_d_handler_binding.independent_reviewer_role_id, declared not chosen';

    elsif v_k = 'step_id' then
      -- MENTIONED IN THIS FUNCTION AND NOT BRANCHED, which is why the first measurement of this
      -- defect missed it. sr.step_id appears in the return object at the bottom, so a grep for
      -- 'step_id' finds it and a reader concludes the key resolves. It did not. A mention is not a
      -- branch — the same lens that cost the 19 Aug audit its central premise, applied here to the
      -- very file that was measuring it.
      v_val := to_jsonb(sr.step_id);
      v_src := 'phase_c_workflow_step_run.step_id';

    elsif v_k = 'step_run_id' then
      v_val := to_jsonb(p_step_run_id);
      v_src := 'the step_run_id this function was called with';

    elsif v_k = 'source_ref' then
      -- The arrival that caused this run, already computed into v_src_ref from kernel_trigger_inbox
      -- at the top of this function. Unresolved when no arrival is recorded, which is a fact about
      -- the run rather than a gap in this resolver.
      v_val := to_jsonb(nullif(btrim(coalesce(v_src_ref,'')),''));
      v_src := 'kernel_trigger_inbox.source_system for this run';

    else
      -- 40 of the 71 declared context keys still land here, and that is correct: artifact_sha256,
      -- terms_hash, legal_review_ref, denominator, formula, outcome_metric and the rest are facts a
      -- CALLER produces at runtime, not facts this estate holds. They stay unresolved and their
      -- rules and gates refuse, which is the contract working.
      -- exception_authority_ref is here on purpose too: BR-043 applies only when the call names a
      -- policy exception, and inventing an authority reference would be the placeholder defect the
      -- D42 comment above already refused once for route_state.
      v_val := null; v_src := null;
    end if;


    -- F11. THE FIXTURE DOOR, AND ONLY AFTER EVERY REAL SOURCE HAS BEEN TRIED.
    --
    -- The founder's section B: "A deterministic handler must not invent business content. The
    -- scenario catalogue supplies explicit test values... The handler receives the fixture as
    -- input. The handler must not generate the fixture itself."
    --
    -- This is where the fixture becomes an input. It runs in the RESOLVER, which is called by
    -- fn_phase_d_dispatch_step before fn_phase_d_handler_execute is entered, so the handler is
    -- handed a value and never reaches for one. And it runs LAST: a key a real row can answer is
    -- answered by that row, and the fixture never shadows a fact.
    --
    -- fn_phase_d_fixture_input returns NO ROW unless fn_phase_d_fixture_context() verifies an hmac
    -- over the current txid keyed by a secret no role can read. In production there is no such
    -- context, so this block resolves nothing, the key stays unresolved, and its rule or gate
    -- refuses exactly as it did before this file existed.
    if v_val is null or v_val = 'null'::jsonb
       or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = '') then
      select fi.value, fi.provenance || format(' [fixture %s v%s %s]', fi.fixture_id,
                                               fi.fixture_version, left(fi.checksum, 12))
        into v_fx_val, v_fx_src
        from public.fn_phase_d_fixture_input(p_step_run_id, 'CONTEXT_KEY', v_k) fi;
      if v_fx_val is not null then
        v_ctx := v_ctx || jsonb_build_object(v_k, v_fx_val);
        v_prov := v_prov || jsonb_build_object(v_k, v_fx_src);
        v_fx_val := null; v_fx_src := null;
        continue;
      end if;
    end if;
    if v_val is null or v_val = 'null'::jsonb
       or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = '') then
      v_unres := v_unres || v_k;
    else
      v_ctx  := v_ctx  || jsonb_build_object(v_k, v_val);
      v_prov := v_prov || jsonb_build_object(v_k, v_src);
    end if;
  end loop;

  return jsonb_build_object(
    'step_run_id', p_step_run_id, 'step_id', sr.step_id,
    'declared_keys', to_jsonb(v_keys),
    'context', v_ctx, 'provenance', v_prov, 'unresolved', to_jsonb(v_unres),
    'arrival', jsonb_build_object('source_ref', v_src_ref, 'source_kind', v_src_kind,
                                  'source_class', v_src_class, 'activation', v_src_act),
    'business_object', jsonb_build_object(
      'object_id', v_obj, 'object_key', v_boid, 'relation', v_rel, 'key_column', v_keycol,
      'owner_column', v_owncol, 'row_found', v_found,
      -- E25. The two facts fn_phase_d_effect_produce demands of its caller, reported here because
      -- this is the routine that already resolved them and the dispatch had no way to know them.
      'key_is_prefixed', v_key_prefixed,
      'row_owner_ref', v_row_own,
      'ownership_scope', (select ob.ownership_scope
                            from public.phase_d_business_object_binding ob
                           where ob.object_id = v_obj)));
end
$function$
;

CREATE OR REPLACE FUNCTION public.fn_phase_d_step_inputs(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  r  public.phase_c_workflow_run%rowtype;
  w  public.phase_b_workflow%rowtype;
  s  public.phase_b_workflow_step%rowtype;
  b  public.phase_d_handler_binding%rowtype;
  v_keys   text[];
  v_k      text;
  v_val    jsonb;
  v_src    text;
  v_in     jsonb := '{}'::jsonb;
  v_prov   jsonb := '{}'::jsonb;
  v_res    text[] := '{}';
  v_unres  text[] := '{}';
  v_fx_val jsonb;   -- F11
  v_fx_src text;    -- F11
  v_cmd    bigint;
begin
  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then
    raise exception 'fn_phase_d_step_inputs: no step run %', p_step_run_id using errcode = '23503';
  end if;
  select * into r  from public.phase_c_workflow_run    where run_id  = sr.run_id;
  select * into s  from public.phase_b_workflow_step   where step_id = sr.step_id;
  select * into w  from public.phase_b_workflow        where workflow_id = r.workflow_id;
  select * into b  from public.phase_d_handler_binding where step_id = sr.step_id;

  select coalesce(sc.required_keys, '{}') into v_keys
    from public.phase_d_handler_schema sc
   where sc.step_id = sr.step_id and sc.schema_kind = 'input';
  if v_keys is null then v_keys := '{}'; end if;

  -- The founder command that caused this run, if one did. W01 is started by
  -- fn_founder_command_submit through os_api, so for that workflow this is the real instruction.
  select l.command_id into v_cmd
    from public.founder_command_workflow_link l where l.run_id = sr.run_id limit 1;
  if v_cmd is null then v_cmd := r.command_id; end if;

  foreach v_k in array v_keys loop
    v_val := null; v_src := null;

    if v_k = 'workflow_record' then
      v_src := 'phase_c_workflow_run + phase_b_workflow + phase_b_workflow_step';
      v_val := jsonb_build_object(
        'run_id', r.run_id, 'workflow_id', r.workflow_id, 'workflow_name', w.workflow_name,
        'domain', w.domain, 'criticality', w.criticality, 'primary_object', w.primary_object,
        'business_object_id', nullif(btrim(coalesce(r.business_object_id,'')),''),
        'object_version', r.object_version, 'run_state', r.state, 'start_event', r.start_event,
        'run_accountable_role_id', r.accountable_role_id, 'opened_at', r.opened_at,
        'step_id', sr.step_id, 'step_name', s.step_name,
        'step_accountable_role_id', sr.accountable_role_id,
        'required_inputs', s.required_inputs, 'required_output', s.required_output,
        'acceptance_criteria', s.acceptance_criteria, 'closure_criteria', s.closure_criteria);

    elsif v_k = 'prior_accepted_outputs' then
      -- THE RECORD of what this run has already accepted. The kernel stores the accepted output's
      -- sha256, never the payload, so the hash IS the identity of the accepted output and the
      -- effect ledger row IS what it produced. Nothing here is reconstructed from prose.
      -- A count of 0 is a fact about a first step, not an absence: the object is returned with
      -- count 0 rather than an empty array, because fn_phase_d_schema_validate reads [] as missing.
      v_src := 'phase_c_workflow_step_run(completed) + phase_d_effect_ledger, this run only';
      select jsonb_build_object(
               'count', count(*),
               'run_id', sr.run_id,
               'outputs', coalesce(jsonb_agg(jsonb_build_object(
                   'step_id', pr.step_id, 'step_run_id', pr.step_run_id,
                   'output_hash', pr.output_hash, 'authority_result', pr.authority_result,
                   'gates_evaluated', pr.gates_evaluated, 'finished_at', pr.finished_at,
                   'effects', coalesce((select jsonb_agg(jsonb_build_object(
                                  'effect_id', el.effect_id, 'effect_type', el.effect_type,
                                  'effect_object_id', el.effect_object_id,
                                  'result_reference', el.result_reference,
                                  'state_after', el.state_after) order by el.effect_id)
                                from public.phase_d_effect_ledger el
                               where el.step_run_id = pr.step_run_id), '[]'::jsonb))
                 order by pr.step_run_id), '[]'::jsonb))
        into v_val
        from public.phase_c_workflow_step_run pr
       where pr.run_id = sr.run_id
         and pr.state = 'completed'
         and pr.step_run_id < sr.step_run_id;

    elsif v_k = 'applicable_policy' then
      v_src := 'phase_d_rule_enforcement + phase_d_gate_contract, in scope for this step';
      v_val := jsonb_build_object(
        'step_id', sr.step_id, 'founder_gate', b.founder_gate,
        'rule_count', coalesce(cardinality(b.rule_ids), 0),
        'gate_count', coalesce(cardinality(b.gate_ids), 0),
        'rules', coalesce((select jsonb_agg(jsonb_build_object(
                    'rule_id', re.rule_id, 'rule_type', re.rule_type,
                    'enforcement_kind', re.enforcement_kind, 'enforcement_point', re.enforcement_point,
                    'refusal_code', re.refusal_code, 'applies_when', re.applies_when,
                    'status', re.status) order by re.rule_id)
                  from public.phase_d_rule_enforcement re
                 where re.rule_id = any (coalesce(b.rule_ids,'{}'))), '[]'::jsonb),
        'gates', coalesce((select jsonb_agg(jsonb_build_object(
                    'gate_id', gc.gate_id, 'predicate_kind', gc.predicate_kind,
                    'refusal_code', gc.refusal_code, 'evidence_keys', to_jsonb(gc.evidence_keys),
                    'correction_owner', gc.correction_owner) order by gc.gate_id)
                  from public.phase_d_gate_contract gc
                 where gc.gate_id = any (coalesce(b.gate_ids,'{}'))), '[]'::jsonb));

    elsif v_k in ('founder_instruction','founder_mandate') then
      v_src := 'founder_command via founder_command_workflow_link / phase_c_workflow_run.command_id';
      select jsonb_build_object(
               'command_id', fc.command_id, 'outcome', fc.outcome, 'state', fc.state,
               'priority', fc.priority, 'command_owner_role_id', fc.command_owner_role_id,
               'primary_role_id', fc.primary_role_id,
               'founder_initiated_only', fc.founder_initiated_only,
               'refund_semantics', fc.refund_semantics, 'created_at', fc.created_at)
        into v_val
        from public.founder_command fc where fc.command_id = v_cmd;

    elsif v_k = 'current_approved_founder_policies' then
      v_src := 'governance_policy + policy_rules(active)';
      select jsonb_build_object(
               'governance_policy_count', (select count(*) from public.governance_policy),
               'governance_policy', coalesce((select jsonb_agg(jsonb_build_object(
                   'id', gp.id, 'domain', gp.domain, 'policy', gp.policy, 'rule', gp.rule,
                   'enforced_by', gp.enforced_by, 'enforcement', gp.enforcement,
                   'owner_dept', gp.owner_dept) order by gp.id)
                   from public.governance_policy gp), '[]'::jsonb),
               'policy_rules', coalesce((select jsonb_agg(jsonb_build_object(
                   'id', pr2.id, 'name', pr2.name, 'severity', pr2.severity, 'scope', pr2.scope)
                   order by pr2.id) from public.policy_rules pr2 where pr2.active), '[]'::jsonb))
        into v_val;

    elsif v_k in ('current_company_objective','approved_company_objectives_and_department_mandates') then
      v_src := 'company_goals(active) + org_departments(active)';
      select jsonb_build_object(
               'goal_count', (select count(*) from public.company_goals where active),
               'goals', coalesce((select jsonb_agg(jsonb_build_object(
                   'key', cg.key, 'goal', cg.goal, 'metric', cg.metric,
                   'target_value', cg.target_value, 'unit', cg.unit, 'period', cg.period,
                   'owner_dept', cg.owner_dept, 'horizon', cg.horizon, 'deadline', cg.deadline)
                   order by cg.sort, cg.key) from public.company_goals cg where cg.active), '[]'::jsonb),
               'departments', coalesce((select jsonb_agg(jsonb_build_object(
                   'dept_key', od.dept_key, 'name', od.name) order by od.dept_key)
                   from public.org_departments od where od.active), '[]'::jsonb))
        into v_val;

    elsif v_k = 'department_mandates' then
      v_src := 'org_departments(active)';
      select jsonb_build_object(
               'count', count(*),
               'departments', coalesce(jsonb_agg(jsonb_build_object(
                   'dept_key', od.dept_key, 'name', od.name, 'charter', od.charter,
                   'north_star', od.north_star) order by od.dept_key), '[]'::jsonb))
        into v_val
        from public.org_departments od where od.active;

    elsif v_k = 'kpi_tree' then
      v_src := 'company_goals(active) grouped by owner_dept';
      select jsonb_build_object(
               'metric_count', (select count(*) from public.company_goals where active),
               'by_department', coalesce(jsonb_object_agg(q.dept, q.metrics), '{}'::jsonb))
        into v_val
        from (select coalesce(nullif(btrim(cg.owner_dept),''),'(unassigned)') as dept,
                     jsonb_agg(jsonb_build_object('key', cg.key, 'metric', cg.metric,
                       'target_value', cg.target_value, 'unit', cg.unit) order by cg.key) as metrics
                from public.company_goals cg where cg.active group by 1) q;

    elsif v_k = 'current_company_state' then
      v_src := 'measured counts: active goals, active departments, open runs, open tasks';
      select jsonb_build_object(
               'measured_at', now(),
               'active_goals', (select count(*) from public.company_goals where active),
               'active_departments', (select count(*) from public.org_departments where active),
               'open_workflow_runs', (select count(*) from public.phase_c_workflow_run
                                       where closed_at is null),
               'open_tasks', (select count(*) from public.phase_c_task where closed_at is null))
        into v_val;

    elsif v_k in ('strategy_options','strategy_option','current_baseline','issued_initiatives',
                  'complete_ownership_and_measurement_setup') then
      -- These are produced by an EARLIER step of the same run. They resolve only once that step has
      -- completed; before that they are genuinely absent and the step must wait, not guess.
      v_src := 'prior completed step runs of this run';
      select jsonb_build_object(
               'produced_by_count', count(*),
               'produced_by', coalesce(jsonb_agg(jsonb_build_object(
                 'step_id', pr.step_id, 'output_hash', pr.output_hash,
                 'finished_at', pr.finished_at) order by pr.step_run_id), '[]'::jsonb))
        into v_val
        from public.phase_c_workflow_step_run pr
       where pr.run_id = sr.run_id and pr.state = 'completed' and pr.step_run_id < sr.step_run_id;
      if coalesce((v_val->>'produced_by_count')::int, 0) = 0 then
        v_val := null;   -- nothing has produced it yet: unresolved, not an empty pass
      end if;

    elsif v_k = 'budget_envelope' then
      -- E9. The prior body said "NO TABLE IN THIS ESTATE HOLDS THESE" and named this key.
      -- public.department_budget holds monthly_aed, spent_aed and the two degrade/halt thresholds
      -- for every active department. That IS a budget envelope. It is read here, not invented.
      v_src := 'department_budget joined to org_departments(active)';
      select jsonb_build_object(
               'measured_at', now(),
               'department_count', count(*),
               'monthly_aed_total', coalesce(sum(db.monthly_aed), 0),
               'spent_aed_total',   coalesce(sum(db.spent_aed), 0),
               'departments', coalesce(jsonb_agg(jsonb_build_object(
                   'dept_key', db.dept_key, 'monthly_aed', db.monthly_aed,
                   'spent_aed', db.spent_aed, 'period_label', db.period_label,
                   'degrade_at_pct', db.degrade_at_pct, 'halt_at_pct', db.halt_at_pct,
                   'updated_at', db.updated_at) order by db.dept_key), '[]'::jsonb))
        into v_val
        from public.department_budget db
        join public.org_departments od on od.dept_key = db.dept_key and od.active;
      -- No budget row is not an empty envelope; it is an unanswered question.
      if coalesce((v_val->>'department_count')::int, 0) = 0 then v_val := null; end if;

    elsif v_k = 'resource_envelope' then
      -- Money AND people, because a resource envelope that names only money cannot bound a plan
      -- this company executes with 90 active agents across 10 departments.
      v_src := 'department_budget + org_departments(active) + org_agents(active)';
      select jsonb_build_object(
               'measured_at', now(),
               'active_departments', (select count(*) from public.org_departments where active),
               'active_agents',      (select count(*) from public.org_agents where active),
               'monthly_aed_total',  coalesce((select sum(monthly_aed) from public.department_budget), 0),
               'spent_aed_total',    coalesce((select sum(spent_aed)   from public.department_budget), 0),
               'by_department', coalesce((select jsonb_agg(jsonb_build_object(
                   'dept_key', od.dept_key, 'name', od.name,
                   'monthly_aed', db.monthly_aed, 'spent_aed', db.spent_aed,
                   'agents', (select count(*) from public.org_agents a
                               where a.active and a.department = od.dept_key))
                   order by od.dept_key)
                 from public.org_departments od
                 left join public.department_budget db on db.dept_key = od.dept_key
                where od.active), '[]'::jsonb))
        into v_val;
      if coalesce((v_val->>'active_departments')::int, 0) = 0 then v_val := null; end if;

    elsif v_k = 'current_cash_budget_and_commitments' then
      -- Budget is what may be spent; commitments are what already has been. Both come from rows:
      -- department_budget for the envelope and the posted general journal for the commitments.
      -- A cash POSITION is not claimed — no table in this estate holds a bank balance, and saying
      -- so is better than deriving one.
      v_src := 'department_budget + gl_journal(posted) — budget and commitments; NO cash position, '
            || 'because no relation in this estate holds one';
      select jsonb_build_object(
               'measured_at', now(),
               'cash_position_available', false,
               'cash_position_note', 'no relation in this estate holds a bank balance',
               'budget_monthly_aed', coalesce((select sum(monthly_aed) from public.department_budget), 0),
               'budget_spent_aed',   coalesce((select sum(spent_aed)   from public.department_budget), 0),
               'budget_by_department', coalesce((select jsonb_agg(jsonb_build_object(
                   'dept_key', db.dept_key, 'monthly_aed', db.monthly_aed, 'spent_aed', db.spent_aed,
                   'halt_at_pct', db.halt_at_pct) order by db.dept_key)
                 from public.department_budget db), '[]'::jsonb),
               'posted_journal_entries', (select count(*) from public.gl_journal where status = 'posted'),
               'commitments', coalesce((select jsonb_agg(jsonb_build_object(
                   'entry_no', j.entry_no, 'entry_date', j.entry_date, 'memo', j.memo,
                   'source', j.source, 'currency', j.currency) order by j.entry_date desc, j.entry_no desc)
                 from (select * from public.gl_journal
                        where status = 'posted' order by entry_date desc, entry_no desc limit 50) j),
                 '[]'::jsonb))
        into v_val;
      if coalesce((v_val->>'budget_monthly_aed')::numeric, 0) = 0
         and coalesce((v_val->>'posted_journal_entries')::int, 0) = 0 then
        v_val := null;   -- neither a budget nor a commitment on file: genuinely unanswered
      end if;

    elsif v_k = 'external_and_internal_evidence' then
      -- INTERNAL evidence is what the company recorded about itself; EXTERNAL is what it recorded
      -- about the world. Both halves are named separately so a reader can see which one is thin,
      -- and external_available is a measured boolean rather than an implied one.
      v_src := 'company_event(30d) + company_index(90d) + decision_trace(30d)';
      select jsonb_build_object(
               'measured_at', now(),
               'window', '30 days for events and decisions, 90 days for measured indices',
               'internal_event_count',    (select count(*) from public.company_event
                                            where occurred_at > now() - interval '30 days'),
               'internal_decision_count', (select count(*) from public.decision_trace
                                            where created_at > now() - interval '30 days'),
               'measured_index_count',    (select count(*) from public.company_index
                                            where measured_on > current_date - 90),
               'measured_indices', coalesce((select jsonb_agg(jsonb_build_object(
                   'index_name', ci.index_name, 'score', ci.score, 'band', ci.band,
                   'measured_on', ci.measured_on) order by ci.measured_on desc, ci.index_name)
                 from (select distinct on (index_name) index_name, score, band, measured_on
                         from public.company_index where measured_on > current_date - 90
                        order by index_name, measured_on desc) ci), '[]'::jsonb),
               'event_types', coalesce((select jsonb_object_agg(t.event_type, t.n)
                 from (select event_type, count(*) n from public.company_event
                        where occurred_at > now() - interval '30 days'
                        group by 1 order by 2 desc limit 25) t), '{}'::jsonb),
               'external_available', false,
               'external_note', 'no external-signal relation is on file; supplier discovery has been '
                             || 'paused since 2026-08-10 and nothing else in this estate records an '
                             || 'outside source')
        into v_val;
      if coalesce((v_val->>'internal_event_count')::int, 0) = 0
         and coalesce((v_val->>'measured_index_count')::int, 0) = 0
         and coalesce((v_val->>'internal_decision_count')::int, 0) = 0 then
        v_val := null;
      end if;

    else
      -- Every key the frozen registry declares is now named above. This branch is the fail-closed
      -- default for a key added later: unresolved, never a placeholder, because a placeholder makes
      -- the step complete on a fact it never had.
      v_val := null;
      v_src := null;
    end if;


    -- F11. THE FIXTURE DOOR, AND ONLY AFTER EVERY REAL SOURCE HAS BEEN TRIED.
    --
    -- The founder's section B: "A deterministic handler must not invent business content. The
    -- scenario catalogue supplies explicit test values... The handler receives the fixture as
    -- input. The handler must not generate the fixture itself."
    --
    -- This is where the fixture becomes an input. It runs in the RESOLVER, which is called by
    -- fn_phase_d_dispatch_step before fn_phase_d_handler_execute is entered, so the handler is
    -- handed a value and never reaches for one. And it runs LAST: a key a real row can answer is
    -- answered by that row, and the fixture never shadows a fact.
    --
    -- fn_phase_d_fixture_input returns NO ROW unless fn_phase_d_fixture_context() verifies an hmac
    -- over the current txid keyed by a secret no role can read. In production there is no such
    -- context, so this block resolves nothing, the key stays unresolved, and its rule or gate
    -- refuses exactly as it did before this file existed.
    if v_val is null or v_val = 'null'::jsonb then
      select fi.value, fi.provenance || format(' [fixture %s v%s %s]', fi.fixture_id,
                                               fi.fixture_version, left(fi.checksum, 12))
        into v_fx_val, v_fx_src
        from public.fn_phase_d_fixture_input(p_step_run_id, 'CONTEXT_KEY', v_k) fi;
      if v_fx_val is not null then
        v_in := v_in || jsonb_build_object(v_k, v_fx_val);
        v_prov := v_prov || jsonb_build_object(v_k, v_fx_src);
        v_res := v_res || v_k;
        v_fx_val := null; v_fx_src := null;
        continue;
      end if;
    end if;
    if v_val is null or v_val = 'null'::jsonb then
      v_unres := v_unres || v_k;
    else
      v_in   := v_in   || jsonb_build_object(v_k, v_val);
      v_prov := v_prov || jsonb_build_object(v_k, v_src);
      v_res  := v_res  || v_k;
    end if;
  end loop;

  return jsonb_build_object(
    'step_run_id', p_step_run_id, 'step_id', sr.step_id, 'run_id', sr.run_id,
    'declared_keys', to_jsonb(v_keys),
    'inputs', v_in, 'provenance', v_prov,
    'resolved', to_jsonb(v_res), 'unresolved', to_jsonb(v_unres));
end
$function$
;
