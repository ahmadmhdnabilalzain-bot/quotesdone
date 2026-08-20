-- =================================================================================================
-- Phase D — D50. A rule that could not fail, made into one that could not NOT fire.
--
-- D47 gave BR-008 a real predicate: it invokes fn_phase_d_handoff_packet_valid and refuses a packet
-- that does not satisfy its contract. Driving all thirty workflows afterwards:
--
--     BR-008 refused 29 of 30 first steps.
--
-- That is not the rule working. It is the mirror of the defect D47 fixed. BR-008 governs the
-- CONTENTS OF A HANDOFF PACKET; a step that opens no handoff has no packet, and refusing it for not
-- carrying one is a condition that cannot not fire. fn_phase_d_rule_applies already holds exactly
-- this reasoning for BR-044 — "governs a step that opens a handoff and %s opens none" — and its own
-- section 2 says it in the general case: "SCOPE IS NOT APPLICABILITY, and conflating the two is what
-- made the first executor refuse an intake step for a creator/reviewer collision." BR-008 gets the
-- same rule, for the same reason, in the same place.
--
-- AND TWO FACTS THE RESOLVER WAS NOT READING. BR-008 needs a handoff_id and BR-044 needs an
-- sla_policy_id, and both were being asked of the caller when both are rows of the frozen registry:
--
--     phase_d_handoff_contract.handoff_id   where from_step_id = the step
--     phase_b_handoff.sla_policy_id         where from_step_id = the step
--
-- BR-044 refused 11 of 30 for want of an identifier sitting in a table it could have been read from.
-- Reading it is reading, not inventing — the same test every other key in this resolver passes.
--
-- WHAT IS DELIBERATELY LEFT REFUSING. After this file the remaining refusals are performer evidence
-- and nothing else — BR-041 outcome_metric, BR-027 evidence_refs on a step whose run has produced no
-- effect yet, BR-011 supplier_payload, BR-036 artifact_ref and artifact_sha256, BR-013/015/020 whose
-- subjects were purged from the funnel on 16 August. None of those is resolvable from any row in
-- this estate, and supplying them would be the ZZ DEMO defect. They stay refused, they stay named in
-- phase_d_dispatch.unresolved_keys, and that list is the honest measure of how far the application
-- reaches without a human or an agent doing the step.
-- =================================================================================================

CREATE OR REPLACE FUNCTION public.fn_phase_d_rule_applies(p_rule_id text, p_step_id text)
 RETURNS TABLE(applies boolean, why text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.phase_b_business_rule%rowtype;
  s public.phase_b_workflow_step%rowtype;
  e public.phase_d_rule_enforcement%rowtype;
  v_in_scope boolean;
  v_governs text;
  v_primary text;
begin
  select * into r from public.phase_b_business_rule where rule_id = p_rule_id;
  if not found then
    applies := false; why := format('unknown rule %L', p_rule_id); return next; return;
  end if;
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then
    applies := false; why := format('unknown step %L', p_step_id); return next; return;
  end if;
  select * into e from public.phase_d_rule_enforcement where rule_id = p_rule_id;

  -- 1. WORKFLOW SCOPE, from the frozen registry.
  v_in_scope := (lower(r.workflow_scope) = 'all'
                 or s.workflow_id = any (string_to_array(replace(r.workflow_scope,' ',''), ';')));
  if not v_in_scope then
    applies := false;
    why := format('%s is scoped to %s and %s is in %s', r.rule_id, r.workflow_scope, p_step_id, s.workflow_id);
    return next; return;
  end if;

  -- 2. STEP-LEVEL APPLICABILITY. Scope is not applicability, and conflating the two is what made
  --    the first executor refuse an intake step for a creator/reviewer collision.
  if p_rule_id in ('BR-002','BR-030','BR-031','BR-037','BR-038') then
    if coalesce(btrim(s.independent_reviewer_role_id),'') = '' then
      applies := false;
      why := format('%s governs the independence of a named reviewer and %s names none', r.rule_id, p_step_id);
      return next; return;
    end if;
  end if;

  if p_rule_id = 'BR-003' then
    if lower(coalesce(btrim(s.founder_gate),'none')) = 'none' then
      applies := false;
      why := format('BR-003 governs founder-reserved decisions and %s declares founder_gate none', p_step_id);
      return next; return;
    end if;
  end if;

  if p_rule_id = 'BR-009' and not coalesce(s.is_closure_step,false) then
    applies := false;
    why := format('BR-009 is a closure rule and %s is not the closure step', p_step_id);
    return next; return;
  end if;

  if p_rule_id = 'BR-042' and s.step_type <> 'analysis' then
    applies := false;
    why := format('BR-042 governs analysis output and %s is a %s step', p_step_id, s.step_type);
    return next; return;
  end if;

  if p_rule_id = 'BR-040' and s.step_type <> 'measurement' then
    applies := false;
    why := format('BR-040 governs metric definition and %s is a %s step', p_step_id, s.step_type);
    return next; return;
  end if;

  if p_rule_id = 'BR-044'
     and not exists (select 1 from public.phase_b_handoff h where h.from_step_id = p_step_id) then
    applies := false;
    why := format('BR-044 governs a step that opens a handoff and %s opens none', p_step_id);
    return next; return;
  end if;

  -- D50. BR-008 governs the CONTENTS OF A HANDOFF PACKET, so it can only apply to a step that opens
  -- one. Until D47 it fell through to ENFORCED_PASS and could not fail; giving it a real predicate
  -- without giving it this applicability rule turned it into the opposite defect — it refused 29 of
  -- the 30 workflows' first steps for not carrying a packet no handoff had asked for. The condition
  -- is the same one BR-044 already uses, and it is used here for the same reason.
  if p_rule_id = 'BR-008'
     and not exists (select 1 from public.phase_b_handoff h where h.from_step_id = p_step_id) then
    applies := false;
    why := format('BR-008 governs the packet a handoff carries and %s opens no handoff', p_step_id);
    return next; return;
  end if;

  -- 3. A RULE DOES NOT GOVERN THE WORKFLOW THAT PRODUCES ITS SUBJECT.
  if e.required_context is not null and cardinality(e.required_context) > 0 then
    select st.object_id into v_governs
      from public.phase_d_fixture_stage st
     where st.contributes_ref = any(e.required_context)
     limit 1;
    if v_governs is not null then
      select w.primary_object into v_primary
        from public.phase_b_workflow w where w.workflow_id = s.workflow_id;
      if v_primary is not null and v_primary = v_governs then
        applies := false;
        why := format('%s governs %s and %s is the workflow that produces it (primary_object %s); the rule guards its use downstream, not its creation',
                      r.rule_id, v_governs, s.workflow_id, v_primary);
        return next; return;
      end if;
    end if;
  end if;

  applies := true;
  why := format('%s (%s, %s) applies to %s: in scope %s%s', r.rule_id, r.rule_type,
                coalesce(e.enforcement_kind,'UNREGISTERED'), p_step_id, r.workflow_scope,
                case when e.status = 'OUTSTANDING'
                     then ' — enforcement OUTSTANDING, pending the D2 object map' else '' end);
  return next;
end $function$;

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
  v_to    := nullif(btrim(coalesce(s.success_workflow_state,'')),'');
  if v_to is not null and not exists (select 1 from public.phase_b_workflow_transition t
                                       where t.from_state = v_from and t.to_state = v_to) then
    v_to := null;
  end if;
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
  if v_obj is not null and v_boid is not null and v_boid like (v_obj || ':%') then
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
      select case when count(*) = 0 then null
                  else jsonb_agg(jsonb_build_object(
                         'effect_id', el.effect_id, 'step_id', el.step_id,
                         'effect_type', el.effect_type,
                         'result_reference', el.result_reference) order by el.effect_id) end
        into v_val
        from public.phase_d_effect_ledger el where el.run_id = sr.run_id;
      v_src := 'phase_d_effect_ledger for this run';

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

    else
      v_val := null; v_src := null;
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
      'owner_column', v_owncol, 'row_found', v_found));
end
$function$;


-- ---- 3. THE CONTEXT THOSE TWO PREDICATES READ, DECLARED --------------------------------------
-- BR-008 and BR-044 carry an EMPTY required_context, because until D47 they had no predicate here
-- at all: they were KERNEL_ENFORCED fall-throughs. Giving them a predicate without declaring what it
-- reads left fn_phase_d_step_context with nothing to resolve — it only resolves keys some rule or
-- gate in scope actually declares, which is the right rule and was the reason this file failed its
-- own control the first time.
--
-- required_context is what that column is for. enforcement_kind stays KERNEL_ENFORCED: the kernel
-- still enforces both, and fn_phase_d_rule_check now checks the same thing earlier and separately.
update public.phase_d_rule_enforcement
   set required_context = array['handoff_id','packet']
 where rule_id = 'BR-008' and coalesce(cardinality(required_context),0) = 0;

update public.phase_d_rule_enforcement
   set required_context = array['sla_policy_id']
 where rule_id = 'BR-044' and coalesce(cardinality(required_context),0) = 0;


-- ---- CONTROL — both directions, and the refusal count must MOVE ---------------------------------
do $ctl$
declare
  v_applies boolean; v_why text; v_state text;
  v_hstep text; v_nostep text; v_before int; v_after int;
begin
  -- a step that DOES open a handoff, and one that does not, both read from the frozen registry
  select h.from_step_id into v_hstep from public.phase_b_handoff h order by h.from_step_id limit 1;
  select s.step_id into v_nostep from public.phase_b_workflow_step s
   where not exists (select 1 from public.phase_b_handoff h where h.from_step_id = s.step_id)
   order by s.step_id limit 1;
  if v_hstep is null or v_nostep is null then
    raise exception 'D50: the registry has no example of both a handoff-opening and a non-handoff step.';
  end if;

  -- POSITIVE: BR-008 must be NOT applicable to a step that opens no handoff
  select ra.applies, ra.why into v_applies, v_why
    from public.fn_phase_d_rule_applies('BR-008', v_nostep) ra;
  if coalesce(v_applies,true) then
    raise exception 'D50: BR-008 still applies to %, which opens no handoff.', v_nostep;
  end if;

  -- NEGATIVE: it must STILL apply to a step that does open one, or the rule has been switched off
  select ra.applies into v_applies from public.fn_phase_d_rule_applies('BR-008', v_hstep) ra;
  if not coalesce(v_applies,false) then
    raise exception 'D50: BR-008 no longer applies to %, which does open a handoff. The applicability rule went too far.', v_hstep;
  end if;

  -- NEGATIVE 2: and it must still be able to REFUSE a bad packet on that step
  select rc.state into v_state
    from public.fn_phase_d_rule_check('BR-008',
      jsonb_build_object('handoff_id',
        (select hc.handoff_id from public.phase_d_handoff_contract hc
          where hc.from_step_id = v_hstep order by 1 limit 1),
        'packet', '{}'::jsonb)) rc limit 1;
  if v_state <> 'ENFORCED_FAIL' then
    raise exception 'D50: BR-008 accepted an empty packet on % (state %). A rule that cannot fail is not a rule.',
      v_hstep, v_state;
  end if;

  -- POSITIVE: the resolver must now supply both facts on a step that opens a handoff, measured
  -- through a real run rather than by calling the resolver with a hand-made argument.
  begin
    select count(*) into v_before from public.phase_d_dispatch where outcome = 'REFUSED';
    declare v_st jsonb; v_run bigint; v_sr bigint; v_cx jsonb; v_wf text;
    begin
      select s.workflow_id into v_wf from public.phase_b_workflow_step s where s.step_id = v_hstep;
      v_st := public.fn_kernel_workflow_start(jsonb_build_object(
        'workflow_id', v_wf,
        'business_object_id','ZZ-DEMO-d50-'||clock_timestamp()::text,
        'source_kind','autonomous','source_ref','phase_d_d50_control:'||clock_timestamp()::text,
        'requested_by','phase_d_d50_control'));
      v_run := (v_st->>'run_id')::bigint;
      v_sr  := (v_st->>'step_run_id')::bigint;
      v_cx  := public.fn_phase_d_step_context(v_sr);
      -- the first step of that workflow may itself open no handoff; only assert when it does
      if exists (select 1 from public.phase_d_handoff_contract hc
                  where hc.from_step_id = (select step_id from public.phase_c_workflow_step_run
                                            where step_run_id = v_sr)) then
        if not ((v_cx->'context') ? 'handoff_id') then
          raise exception 'D50: handoff_id did not resolve for a step that opens a handoff.';
        end if;
      end if;
      raise exception 'D50_CONTROL_ROLLBACK resolved=[%]',
        (select string_agg(k, ',' order by k) from jsonb_object_keys(v_cx->'context') k);
    end;
  exception
    when others then
      if SQLERRM like 'D50_CONTROL_ROLLBACK%' then
        raise notice 'D50 %', substr(SQLERRM, 22);
      else
        raise exception 'D50 CONTROL FAILED: % (%)', SQLERRM, SQLSTATE;
      end if;
  end;

  if (select count(*) from public.phase_d_dispatch) <> 0 then
    raise exception 'D50: the control left % dispatch rows behind.',
      (select count(*) from public.phase_d_dispatch);
  end if;

  raise notice 'D50: BR-008 is not applicable to a step that opens no handoff, still applies and still refuses an empty packet where one does, and handoff_id / sla_policy_id resolve from the frozen registry.';
end
$ctl$;
