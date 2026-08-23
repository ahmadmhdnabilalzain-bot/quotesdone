-- K01 — the founder boundary gate asked for half of the evidence its own frozen text names
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh.  W05-S07 "Decide qualification status" was the one
-- founder-gated step of the 257 that produced no declared effect:
--
--   gate005_founder_boundary :: GATE-005 (Founder boundary) requires [founder_authority_ref] and
--   the call names none of it.
--
-- GATE-005's frozen required_evidence, in public.phase_b_gate, is TWO alternatives:
--
--   "Decision is within delegated authority OR founder approval exists."
--
-- public.phase_d_gate_contract implements only the second.  Its evidence_keys are
-- ["step_id","founder_authority_ref"], and public.fn_phase_d_step_context answered that key from a
-- founder command and from nothing else.  A step whose run no founder instructed could therefore
-- never satisfy the gate, however plainly the decision was delegated.
--
-- WHICH STEPS THIS IS ABOUT, measured rather than assumed.  GATE-005 applies where the frozen step
-- declares a founder_gate other than 'none' -- 18 of the 257 steps, in 14 workflows.  Cross those
-- 14 workflows against the founder's own frozen boundary register, public.phase_b_founder_boundary:
--
--   16 of the 18 sit in a workflow at least one boundary scopes.  W17-S07 is FDR-002 and FDR-010,
--      W01-S04 is FDR-001/003/004/005/006, and so on.  For those the founder HAS reserved the
--      decision and only a founder command can answer.  Nothing below changes them.
--   W05-S07 and W18-S05 sit in workflows NO boundary scopes.  FDR-001..FDR-010 name
--      W01;W02;W03;W04;W09;W15;W16;W17;W20;W21;W23;W24;W25;W27;W28;W29;W30 between them, and
--      neither W05 nor W18 is among them.
--
-- W05 is the inquiry qualification workflow.  Its run is started in production by
-- trg_inquiry_received_a when a customer's inquiry arrives -- source_kind 'trigger', command_id
-- null -- so if GATE-005 could only be answered by a founder command, every customer inquiry in
-- production would block at qualification waiting for an approval the founder does not give.  His
-- ruling of 17 Aug 2026 is that he approves refunds.  A founder command attached to a run a
-- customer's inquiry started would be a forgery, and this file does not create one.
--
-- WHAT THE DELEGATION REFERENCE IS.  public.phase_b_founder_boundary is the founder-approved,
-- Phase-B-frozen, digest-guarded statement of what he reserves.  A decision in a workflow that
-- register does not name is delegated BY THAT REGISTER -- a positive fact read off an approved
-- artefact, not an absence.  fn_phase_d_founder_authority returns it as one immutable canonical
-- reference naming the artefact and its digest:
--
--   founder_policy:phase_b_founder_boundary@<digest>
--
-- and the digest is public.fn_phase_b_structure_digest()'s own 'founder_boundaries' row, the same
-- value public.org_phase_baseline holds for phase B and the same one fn_phase_b_baseline_drift
-- compares.  If the register changes, the reference changes and stops matching the approved
-- baseline, and the authority is refused until the founder approves the new register.  That is what
-- "exists, is current, and covers the action" means here, and each of the three is a separate
-- column of the answer.
--
-- AND GATE-005 NOW CHECKS IT.  The evaluator's body for GATE-005 was `v_ok := true` -- presence of
-- a string, never its validity, so any caller could have handed it any text.  It now resolves the
-- authority itself and requires the presented reference to be the one that resolves.
--
-- THE DEAD LOOKUP.  fn_phase_d_step_context read
-- `founder_command_workflow_link.command_id where run_id = sr.run_id` first, and
-- fn_phase_d_drive_workflow inserted that link with (command_id, workflow_id) and no run_id: 15 of
-- 15 rows in the table carry run_id null, so that branch had never matched anything and every
-- resolution that ever succeeded came from the fallback.  The run_id is now stamped, and ONLY where
-- the kernel's own row says the command started the run -- never onto a run some other arrival
-- started, which is the forgery above.
--
-- ROLLBACK: scripts/sql/down/phase_d_k01_the_gate_asked_for_half_the_evidence_its_text_names_down.sql
-- re-applies the previous bodies of fn_phase_d_step_context, fn_phase_d_gate_evaluate and
-- fn_phase_d_drive_workflow and drops fn_phase_d_founder_authority.
--
-- GENERATED from the live bodies by scripts/tmp_diag/gen_k01.mjs.

CREATE OR REPLACE FUNCTION public.fn_phase_d_founder_authority(p_run_id bigint, p_step_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_wf       text;
  v_cmd      bigint;
  v_state    text;
  v_reserved text;
  v_digest   text;
  v_baseline text;
  v_covers   boolean;
  v_exists   boolean;
  v_current  boolean;
begin
  select s.workflow_id into v_wf from public.phase_b_workflow_step s where s.step_id = p_step_id;
  if v_wf is null then
    return jsonb_build_object('ref', null, 'kind', 'UNKNOWN_STEP',
      'exists', false, 'current', false, 'covers', false, 'valid', false,
      'why', format('%s is not a step of the frozen registry', coalesce(p_step_id, '(null)')));
  end if;

  -- WHAT THE FOUNDER RESERVED, read from the register he approved. Never a list in this body.
  select string_agg(b.boundary_id, ';' order by b.boundary_id) into v_reserved
    from public.phase_b_founder_boundary b
   where v_wf = any (string_to_array(replace(b.workflow_scope, ' ', ''), ';'));

  -- 1. A FOUNDER COMMAND, where one instructed this run.
  select l.command_id into v_cmd from public.founder_command_workflow_link l
   where l.run_id = p_run_id limit 1;
  if v_cmd is null then
    select r.command_id into v_cmd from public.phase_c_workflow_run r where r.run_id = p_run_id;
  end if;

  if v_cmd is not null then
    select fc.state into v_state from public.founder_command fc where fc.command_id = v_cmd;
    v_exists  := v_state is not null;
    v_current := v_exists and v_state <> 'cancelled';
    v_covers  := exists (select 1 from public.founder_command_workflow_link l2
                          where l2.command_id = v_cmd and l2.workflow_id = v_wf)
              or exists (select 1 from public.phase_c_workflow_run r2
                          where r2.run_id = p_run_id and r2.command_id = v_cmd);
    return jsonb_build_object(
      'ref',     'founder_command:' || v_cmd::text,
      'kind',    'FOUNDER_COMMAND',
      'source',  'founder_command that started this run',
      'artefact','public.founder_command',
      'reserved_by', v_reserved,
      'exists',  v_exists, 'current', v_current, 'covers', v_covers,
      'valid',   v_exists and v_current and v_covers,
      'why', format('founder command %s is %s and %s workflow %s', v_cmd,
                    case when not v_exists then 'not on record'
                         when v_current then 'live (state ' || v_state || ')'
                         else 'cancelled' end,
                    case when v_covers then 'selected' else 'DID NOT select' end, v_wf));
  end if;

  -- 2. DELEGATED AUTHORITY, read off the founder-approved frozen boundary register.
  select d.sha256 into v_digest
    from public.fn_phase_b_structure_digest() d where d.subject = 'founder_boundaries';
  select bl.registry_sha256->'structure'->'founder_boundaries'->>'database' into v_baseline
    from public.org_phase_baseline bl where bl.phase = 'B';

  v_exists  := v_digest is not null
               and exists (select 1 from public.phase_b_founder_boundary)
               and v_baseline is not null;
  v_current := v_exists and v_digest = v_baseline;
  v_covers  := v_reserved is null;

  if not v_covers then
    return jsonb_build_object(
      'ref', null, 'kind', 'FOUNDER_RESERVED',
      'source', 'public.phase_b_founder_boundary',
      'artefact', 'public.phase_b_founder_boundary@' || coalesce(left(v_digest, 16), '(none)'),
      'reserved_by', v_reserved,
      'exists', v_exists, 'current', v_current, 'covers', false, 'valid', false,
      'why', format('%s is reserved to the founder by %s and no founder command instructed this run',
                    v_wf, v_reserved));
  end if;

  return jsonb_build_object(
    'ref',     'founder_policy:phase_b_founder_boundary@' || coalesce(left(v_digest, 16), 'unknown'),
    'kind',    'DELEGATED_AUTHORITY',
    'source',  'public.phase_b_founder_boundary, the founder-approved frozen register of what he '
            || 'reserves: it names no boundary over ' || v_wf || ', so the decision is delegated '
            || 'to the step''s accountable role',
    'artefact','public.phase_b_founder_boundary@' || coalesce(left(v_digest, 16), 'unknown'),
    'reserved_by', null,
    'exists',  v_exists, 'current', v_current, 'covers', true,
    'valid',   v_exists and v_current,
    'why', format('the founder-approved boundary register (%s rows, digest %s) %s the Phase B '
               || 'baseline and reserves no decision in %s',
                  (select count(*) from public.phase_b_founder_boundary),
                  coalesce(left(v_digest, 16), '(none)'),
                  case when v_current then 'matches' else 'DOES NOT match' end, v_wf));
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_founder_authority(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_founder_authority(bigint, text) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_phase_d_step_context(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  v_val_txt text;  -- G02: the acceptance value read back before it becomes jsonb
  v_key_obj text;  -- G08: the object a context key names, from phase_d_context_key_object
  v_link    text;  -- G08: the column on this run's relation that reaches that object
  v_link_v  text;  -- G08: what that column holds
  v_scn_ref jsonb; -- G08: the canonical reference the scenario recorded for that object
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
  v_run_key text;
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
  v_auth   jsonb;   -- K01
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
  -- THE RUN'S OWN PARTY, KEPT SEPARATELY. v_boid below is consumed by the STEP's object: where the
  -- step writes something other than what the run is about, the prefix does not match, the lookup
  -- fails and v_found is false. That is correct for the step's own subject and wrong for anything
  -- that belongs to the run as a whole. Measured 23 Aug 2026 on W09-S03: the run's
  -- business_object_id is 'supplier_account:37085' and the step's business object is
  -- supplier_capability on public.supplier_capabilities with row_found false, so the terms branch
  -- below had no anchor and fell through to the catalogue.
  v_run_key := case when v_boid like '%:%' then substr(v_boid, position(':' in v_boid) + 1) else null end;
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
      -- G08. THIS ANSWERED ALL SEVEN WITH THE RUN'S OWN ROW ID. See the file header: BR-015 was told
      -- a quote was a supplier, BR-020 that a comparison was a transaction, BR-013 that a document
      -- was an inquiry. Each key names an object, that object is recorded, and the answer must come
      -- from the object it names or not at all.
      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko where cko.context_key = v_k;

      if v_found and v_key_obj is not null and v_key_obj = v_obj then
        -- The key names the object this run is about. The row id is the answer.
        v_val := to_jsonb(v_row_id);
        v_src := format('%s.%s, looked up by the run''s business_object_id', v_rel, v_keycol);

      elsif v_found and v_key_obj is not null then
        -- The key names a DIFFERENT object. Reach it from this run's own row, through a declared
        -- foreign key to that object's canonical relation where one exists, and otherwise through a
        -- column named exactly like the key. Both are read from the catalog; neither is listed here.
        select a.attname into v_link
          from pg_constraint con
          join lateral unnest(con.conkey) k(attnum) on true
          join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
         where con.contype = 'f'
           and con.conrelid = to_regclass(v_rel)
           and con.confrelid = (select to_regclass(bb.canonical_relation)
                                  from public.phase_d_business_object_binding bb
                                 where bb.object_id = v_key_obj)
         order by a.attname limit 1;
        if v_link is null then
          select a.attname into v_link from pg_attribute a
           where a.attrelid = to_regclass(v_rel) and a.attnum > 0 and not a.attisdropped
             and a.attname = v_k;
        end if;
        if v_link is not null then
          begin
            execute format('select %I::text from %s where %I::text = $1',
                           v_link, to_regclass(v_rel)::text, v_keycol)
              into v_link_v using v_row_id;
          exception when others then v_link_v := null; end;
          if coalesce(btrim(v_link_v),'') <> '' then
            v_val := to_jsonb(v_link_v);
            v_src := format('%s.%s of the run''s own row, which reaches %s', v_rel, v_link, v_key_obj);
          end if;
          v_link := null; v_link_v := null;
        end if;
      end if;
    elsif v_k = 'caller_customer_id' then
      -- G18. THE OWNER IS THE ANSWER ONLY WHEN THE OWNER IS A CUSTOMER.
      -- On a W14 run the business object is a quotation and its owner column is
      -- public.quotes.supplier_id, so this branch handed BR-019 a supplier and BR-019 refused,
      -- correctly, about the wrong party. Whether the owner column reaches the customer relation is
      -- read from the catalog, not assumed from the column's name.
      if v_found and v_row_own is not null and v_owncol is not null
         and exists (select 1
                       from pg_constraint con
                       join lateral unnest(con.conkey) k(attnum) on true
                       join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
                      where con.contype = 'f'
                        and con.conrelid = to_regclass(v_rel)
                        and a.attname = v_owncol
                        and con.confrelid = (select to_regclass(bb.canonical_relation)
                                               from public.phase_d_business_object_binding bb
                                              where bb.object_id = 'customer_account')) then
        v_val := to_jsonb(v_row_own);
        v_src := format('%s.%s of the run''s own object, which is a declared foreign key into the customer relation', v_rel, v_owncol);
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
        -- G09. AN INQUIRY NO RUN HAS CLAIMED HAS NOT DRIFTED FROM ANYTHING.
        -- Measured: W06-S01 and W07-S01 refused with "inquiry owner is (unstated)" because the
        -- inquiry exists and no W05 run does. The branch above still comes first, so an inquiry a
        -- run HAS claimed is answered by that run's actual role and BR-049 still refuses when it
        -- has drifted. Only the unclaimed case changes, and there the frozen registry's own
        -- accountable role for the workflow that owns the inquiry object is the answer -- read from
        -- public.phase_b_workflow, never named here.
      end if;
      -- G14. THE FALLBACK WAS INSIDE THE BRANCH THAT NEEDS THE RUN'S OWN ROW, AND W06 HAS NONE.
      -- W06's primary object is inquiry_route_set, whose fixture stage contributes a STATE rather
      -- than a key, so the run's business object never resolves and the branch above never ran.
      -- W06-S01 kept refusing with "inquiry owner is (unstated)" after G09 had supposedly answered
      -- it. The fallback belongs wherever nothing else has answered, which is here.
      if v_val is null then
        select to_jsonb(w2.accountable_role_id) into v_val
          from public.phase_b_workflow w2
         where w2.primary_object = 'inquiry' order by w2.workflow_id limit 1;
        v_src := 'phase_b_workflow.accountable_role_id of the workflow whose primary object is '
              || 'the inquiry -- no workflow run has claimed this inquiry, so accountability is '
              || 'where the frozen registry puts it and has not moved';
      end if;
    elsif v_k = 'monetary_state' then
      if v_found and v_rel like '%transactions' then
        select to_jsonb(t.fee_status) into v_val from public.transactions t
          where t.id::text = v_row_id limit 1;
        v_src := 'public.transactions.fee_status of the run''s own transaction';
      end if;

    elsif v_k = 'evidence_authority' then
      -- F13. THIS RESOLVED, AND RESOLVED TO SOMETHING THE RULE CANNOT RANK.
      --
      -- BR-029 is about RANK: lower-authority evidence may not silently overwrite higher, and the
      -- estate's ranking is public.mep_evidence_weight (alias, customer_text, document_extraction,
      -- scope_rule, structured_answer). This branch answered with the arrival CLASSIFICATION --
      -- "A NEW_WORK_REQUEST (system.task_engine) via dbtrigger:public.inquiries:trg_inquiry_received_a,
      -- activation ACTIVE" -- which is a true fact about how the run started and is not an evidence
      -- authority at all. Measured on every drive: 0 rows matched, so BR-029 refused for the whole
      -- estate, and it refused with a reason that read as though the authority were unranked rather
      -- than as though the resolver had answered a different question.
      --
      -- The correction is a REMOVAL plus a test: the classification is offered only if it actually
      -- appears in the ranking. When it does not, the key is UNRESOLVED, which is the honest state
      -- -- and which is what lets the Phase D fixture door supply a ranked authority, and what
      -- keeps BR-029 refusing in production where no such authority is named.
      if v_src_class is not null
         and exists (select 1 from public.mep_evidence_weight w
                      where w.weight_key = v_src_class or w.evidence_source = v_src_class
                         or w.source_authority = v_src_class) then
        v_val := to_jsonb(v_src_class);
        v_src := 'phase_c_source_cutover classification of the arrival that caused this run, confirmed present in the public.mep_evidence_weight ranking';
      elsif exists (select 1 from public.phase_d_object_record o
                     where o.object_id = 'document_extraction'
                       and o.payload->>'document_id' = coalesce(v_row_id,'')) then
        -- The run's own object carries a document extraction, and document_extraction IS a ranked
        -- evidence source. This is a read of what the run rests on, not a choice.
        v_val := to_jsonb('document_extraction'::text);
        v_src := 'public.mep_evidence_weight: the run''s own object carries a document extraction, which is a ranked evidence source';
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
      -- K01. GATE-005's frozen evidence is "Decision is within delegated authority OR founder
      -- approval exists", and this resolved only the second half, so a step whose run no founder
      -- instructed could never answer it. One resolver now answers both, from the founder's own
      -- frozen boundary register where no command instructed the run, and it reports the reference
      -- only when that reference is valid -- exists, current, and covering this workflow.
      v_auth := public.fn_phase_d_founder_authority(sr.run_id, sr.step_id);
      if coalesce((v_auth->>'valid')::boolean, false) then
        v_val := to_jsonb(v_auth->>'ref');
        v_src := v_auth->>'source';
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
      -- G02. THE REVIEWER WHO ACTUALLY REVIEWED, BEFORE THE ONE THE REGISTRY DECLARES.
      --
      -- This read only phase_d_handler_binding.independent_reviewer_role_id, which 229 of the 257
      -- steps leave blank, so every gate asking who reviewed something was answered "nobody" even
      -- after fn_kernel_review_decide had sealed a verdict and STAMPED THE REVIEWER on the task.
      -- fn_phase_d_recorded_review already reads that stamp and nothing consulted it here.
      --
      -- Order matters and this order is deliberate: the reviewer who actually reviewed outranks the
      -- reviewer a registry column names, because the gate's question is about the review that
      -- happened. Where no review has been recorded the declared reviewer still answers, and where
      -- neither exists the key stays unresolved and the gate refuses -- which is the gate working,
      -- and is what the previous comment here was protecting. Nothing chooses a reviewer: this
      -- resolver reports one or reports none, exactly as fn_pick_reviewer should have.
      v_val := to_jsonb(nullif(btrim(coalesce(
                 (public.fn_phase_d_recorded_review(p_step_run_id))->>'reviewer_role_id','')),''));
      if v_val is not null then
        v_src := 'phase_c_task.reviewer_role_id, stamped by fn_kernel_review_decide on the review '
              || 'actually recorded for this step run';
      else
        v_val := to_jsonb(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''));
        v_src := 'phase_d_handler_binding.independent_reviewer_role_id, declared not chosen';
      end if;
      -- H03. A STEP THAT IS NOT A REVIEW IS ASKED ABOUT THE REVIEW THE RUN RECORDED. GATE-021 and
      -- GATE-026 apply from the first review step to the last step; at a publish step the reviewer
      -- is whoever reviewed earlier in this run. Read from the same task stamp, on an earlier step
      -- run of the same run, only where this step reviews nothing itself.
      if (v_val is null or v_val = 'null'::jsonb)
         and b.handler_class is distinct from 'REVIEW_HANDLER'
         and coalesce(btrim((select s3.independent_reviewer_role_id
                              from public.phase_b_workflow_step s3 where s3.step_id = sr.step_id)),'') = '' then
        select to_jsonb(nullif(btrim(coalesce(t2.reviewer_role_id,'')),'')) into v_val
          from public.phase_c_task t2
          join public.phase_c_workflow_step_run sr2
            on sr2.run_id = t2.run_id and sr2.step_id = t2.step_id
         where t2.run_id = sr.run_id
           and sr2.step_run_id < p_step_run_id
           and coalesce(btrim(t2.reviewer_role_id),'') <> ''
         order by sr2.step_run_id desc, t2.task_id desc
         limit 1;
        if v_val is not null then
          v_src := 'phase_c_task.reviewer_role_id of the most recent review fn_kernel_review_decide '
                || 'recorded on an earlier step run of this same run -- this step reviews nothing '
                || 'itself, and the gate asks about the review that happened';
        end if;
      end if;

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

    elsif v_k in ('terms_version','terms_hash') then
      -- G02. A KEY THAT NAMES A RECORD WAS ANSWERED FROM A CONSTANT, AND THE CONSTANT WON.
      --
      -- BR-025 asks whether an acceptance references the exact displayed version AND hash, and it
      -- resolves the pair against public.legal_documents. Measured on W04 and W09: it refused with
      --
      --   "acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f, which matches
      --    0 row(s) in public.legal_documents whose displayed body hashes to exactly that digest"
      --
      -- Those two values are the COMMITTED CATALOGUE FIXTURES PDF-3104 and PDF-3105. Nothing was
      -- wrong with them; they are a real pair over a real fixture body. What was wrong is that they
      -- were the answer at all. The scenario factory reads the version and digest of the ACTUALLY
      -- PUBLISHED documents -- public.legal_documents customer-terms v3 and supplier-agreement v5 --
      -- and writes them onto the acceptance record it creates. Both keys then fell through every
      -- branch of this resolver to the fixture door, which answered from the catalogue, and the
      -- catalogue value shadowed the record the scenario had just written. That is D9g's "a
      -- generated fixture beat the real reference", one layer up, and F47's "a key that names an
      -- object is answered from that object's reference" stated for a third time.
      --
      -- THE ACCEPTANCE RECORD IS FOUND BY WHAT IT CARRIES, NOT BY WHAT IT IS CALLED. The record
      -- sought is the live object record owned by this run's own business object that carries both
      -- terms keys -- no object name, no naming convention, no workflow list. A run whose object
      -- row was not found, or that owns no acceptance, resolves nothing here and falls through to
      -- the catalogue exactly as before, where BR-025 still matches 0 rows and still refuses. The
      -- rule keeps its ability to fail, and it now also has a way to pass for a true reason.
      -- J05. AND THE ACCEPTANCE BELONGS TO THE RUN'S PARTY, NOT TO THE STEP'S SUBJECT. The block
      -- above anchored on v_row_id, which is the row the STEP is about. Measured on W09-S03, S05
      -- and S06: the run is about supplier_account 37085 and the step is about a
      -- supplier_capability that does not exist yet, so v_found was false, this branch never ran,
      -- and BR-025 was answered from catalogue fixtures PDF-3104/PDF-3105 --
      -- "acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f, which matches 0
      -- row(s) in public.legal_documents". The acceptance the scenario actually wrote names
      -- supplier-agreement v5, owned by 37085, and it was one join away the whole time.
      --
      -- A terms acceptance is a fact about the PARTY the run concerns; no step in a workflow makes
      -- it a fact about that step's own subject. So the step's subject is tried first, and the
      -- run's own party second. A run whose party owns no acceptance still resolves nothing and
      -- BR-025 still matches 0 rows and still refuses: the rule keeps its ability to fail.
      if coalesce(v_row_id, v_run_key) is not null then
        select o.payload ->> v_k into v_val_txt
          from public.phase_d_object_record o
         where o.superseded_by is null
           and o.payload ? 'terms_version' and o.payload ? 'terms_hash'
           and o.owner_ref in (v_row_id, v_run_key)
         order by (o.owner_ref = v_row_id) desc, o.record_id desc limit 1;
        if coalesce(btrim(v_val_txt),'') <> '' then
          v_val := to_jsonb(v_val_txt);
          v_src := 'the terms-acceptance record this run''s own business object owns, in '
                || 'public.phase_d_object_record -- the pair the acceptance actually names';
        end if;
        v_val_txt := null;
      end if;

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


    -- G08. THE SCENARIO-REFERENCE DOOR, in front of the catalogue and behind every real source.
    --
    -- public.quote_comparisons carries no transaction column and public.documents relates to its
    -- inquiry through a polymorphic (ref_table, ref_id) pair, so no derivation from the schema can
    -- reach W15's transaction_id or W07's inquiry_id from the run's own row. The scenario created
    -- both objects and recorded the canonical reference of each. This answers from THAT -- a row the
    -- scenario actually wrote through fn_phase_d_object_write -- rather than from the committed
    -- constant the fixture door below would otherwise supply.
    --
    -- It returns nothing unless fn_phase_d_fixture_context() verifies an hmac over the current txid
    -- keyed by a secret no role can SELECT. In production this block resolves nothing at all.
    if (v_val is null or v_val = 'null'::jsonb
        or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = ''))
       and public.fn_phase_d_fixture_context() is not null then
      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko where cko.context_key = v_k;
      if v_key_obj is not null then
        select sc.canonical_ref into v_scn_ref
          from public.phase_d_scenario_record sc
         where sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and sc.object_id = v_key_obj
         order by sc.scenario_record_id desc limit 1;
        if v_scn_ref is not null
           and coalesce(btrim(v_scn_ref->>'canonical_identity'),'') <> '' then
          v_ctx  := v_ctx  || jsonb_build_object(v_k, to_jsonb(v_scn_ref->>'canonical_identity'));
          v_prov := v_prov || jsonb_build_object(v_k,
            format('the canonical reference the scenario recorded for %s in '
                || 'public.phase_d_scenario_record -- a row this scenario created through '
                || 'fn_phase_d_object_write, not a committed constant', v_key_obj));
          v_scn_ref := null; v_key_obj := null;
          continue;
        end if;
        v_scn_ref := null;
      end if;
      v_key_obj := null;
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

CREATE OR REPLACE FUNCTION public.fn_phase_d_gate_evaluate(p_gate_id text, p_evidence jsonb)
 RETURNS TABLE(state text, passed boolean, gate_type text, reason text, refusal_code text, evidence_absent boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
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
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_phase_d_drive_workflow(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  w         public.phase_b_workflow%rowtype;
  sr        public.phase_c_workflow_step_run%rowtype;
  hr        public.phase_c_handoff_run%rowtype;
  hc        public.phase_d_handoff_contract%rowtype;
  d         public.phase_d_dispatch%rowtype;
  v_prev    public.phase_c_workflow_step_run%rowtype;
  v_wf      text := nullif(btrim(coalesce(p_input->>'workflow_id','')),'');
  v_label   text := coalesce(nullif(btrim(p_input->>'label'),''), 'phase-d-drive');
  v_ctx     text := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_max     int  := coalesce(nullif(p_input->>'max_steps','')::int, 40);
  -- HOLD AT AN OPEN STEP. A caller that means to drive a step's FAILURE branch needs that step
  -- open and owned, and cannot get there by asking the kernel to stop: since PCCR-001 the dispatch
  -- fires when the step OPENS, so a handler that can execute closes its step and the kernel opens
  -- the next one before any caller is consulted. max_steps 0 therefore does not leave a step open
  -- -- measured 23 Aug 2026 on all 30 workflows, 19 of them came back with the run in
  -- waiting_handoff or waiting_review and NO open step run at all, because the successor is not
  -- opened until the receiving owner accepts the handoff. The failure and cancellation probes then
  -- had nothing to act on and were refused 22023 for a null step_run_id, which is a fact about the
  -- probe and not about the estate.
  --
  -- These two inputs let the caller drive the canonical path -- the same handoff acceptances, the
  -- same capability results, the same recorded reviews, the same fn_kernel_step_complete for every
  -- earlier step -- and STOP with one named step open, having completed nothing on it. Nothing is
  -- skipped and no state is written by hand: the run is exactly where a real actor would find it.
  v_hold_step text := nullif(btrim(coalesce(p_input->>'hold_at_step_id','')),'');
  v_hold_any  boolean := coalesce((p_input->>'hold_at_first_open_step')::boolean, false);
  v_held_srid bigint := null;
  v_held_step text := null;
  v_boid    text := nullif(btrim(coalesce(p_input->>'business_object_id','')),'');
  v_caller_reviewer text := nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'');
  v_cands   text[] := coalesce((select array_agg(x)
                                  from jsonb_array_elements_text(p_input->'reviewer_candidates') x),
                               '{}'::text[]);
  v_run     bigint;
  v_start   jsonb;
  v_steps   jsonb := '[]'::jsonb;
  v_handoffs jsonb := '[]'::jsonb;
  v_i       int := 0;
  v_driven  int := 0;
  v_haccept int := 0;
  v_dispatched int := 0;
  v_executed   int := 0;
  v_before  bigint;
  v_declared text;
  v_rev     text;
  v_task    bigint;
  v_decide  jsonb;
  v_hoff    jsonb;
  v_hpk     jsonb;
  v_err     text; v_sqlstate text; v_code text;
  v_run_state text;
  v_cap_fixture text;      -- F17: the committed CAPABILITY_RESULT row for this step
  v_cap_req   jsonb;       -- F17
  v_cap_res   jsonb;       -- F17
  v_caps      jsonb := '[]'::jsonb;   -- F17: what the capability path did, per step
  v_capn      int := 0;    -- F17: capability results accepted
  v_redisp    jsonb;
  sr2         public.phase_c_workflow_step_run%rowtype;  -- F38: the step run, re-read after dispatch
  v_handler_closed int := 0;          -- F38: steps the handler closed through the kernel itself
  v_seen           bigint[] := '{}';  -- G07: every step run this loop actually observed
  v_unseen         int := 0;          -- G07: handler closures that happened before the loop began
  v_rtask     bigint;                 -- F35: the task the internal review decides
  v_rrev      text;                   -- F35: the reviewer, frozen-declared or independence-tested
  v_rdec      jsonb;                  -- F35: what fn_kernel_review_decide returned
  v_revs      jsonb := '[]'::jsonb;   -- F35: what the review path did, per step
  v_revn      int := 0;               -- F35: internal reviews recorded
  v_stopped jsonb := null;        -- where the DRIVE could go no further, and why
  v_first_refusal jsonb := null;  -- where the deterministic HANDLER first declined, and why
  v_founder_cmd   bigint := null; -- G05: the fixture founder command this run arises from, where one applies
  v_premature     boolean := false;   -- H06: the kernel reported the run already existed
  v_redispatched  int := 0;           -- H06: open steps dispatched again once the scenario was complete
begin
  if v_wf is null then
    raise exception 'fn_phase_d_drive_workflow: workflow_id is required' using errcode = '22023';
  end if;
  -- The kernel dispatch hard-codes 'execution_context','production'. Accepting any other value
  -- here would be this routine promising a mode it has no way to pass on.
  if v_ctx <> 'production' then
    raise exception 'fn_phase_d_drive_workflow: execution_context % is not available. This driver goes through fn_kernel_step_complete, and fn_phase_d_dispatch_step executes the handler in production context with no other mode. (pd_drive_context_unavailable)',
      v_ctx using errcode = '22023';
  end if;

  select * into w from public.phase_b_workflow where workflow_id = v_wf;
  if not found then
    raise exception 'fn_phase_d_drive_workflow: % is not a frozen workflow', v_wf using errcode = '23503';
  end if;

  select count(*) into v_before from public.phase_d_effect_ledger;

  -- THE ARRIVAL NAMES THE OBJECT IT IS ABOUT. E25 derives business_key from the run's
  -- business_object_id and only when it carries the '<object>:' prefix of the object the step
  -- writes - 'inquiry:<uuid>' is an identity, a bare object name is not. The previous driver
  -- passed w.primary_object, which is the object's NAME, so the prefix test was false on every
  -- run it started and the derivation E25 built could never fire through this path.
  v_boid := coalesce(v_boid, w.primary_object || ':' || v_label);

  -- G05. EVERY RUN AROSE BY ITSELF, SO NO RUN COULD REST ON FOUNDER AUTHORITY.
  --
  -- This started every one of the 30 workflows with source_kind 'autonomous' and no command_id.
  -- fn_phase_d_step_context resolves founder_authority_ref from founder_command_workflow_link for
  -- the run, or failing that from phase_c_workflow_run.command_id -- and an autonomous start
  -- leaves both empty by construction. So the key was unresolvable on every run of every workflow,
  -- and the six rules that read it refused every founder-gated step in the estate. Measured:
  -- W03-S01 and W18-S05 refused with "BR-003 requires [founder_authority_ref] and the call names
  -- none of it", and the scenario factory had created a founder command four statements earlier
  -- and handed back founder_authority_ref in its parent_refs, where nothing read it.
  --
  -- The correction is an ARRIVAL, not an injection. fn_kernel_workflow_start already accepts
  -- source_kind 'founder_command' with a command_id, and that is how a founder-instructed run is
  -- really started in production; F12's fixture command is a real row in public.founder_command
  -- created through its own canonical service inside this aborted transaction. Starting the run
  -- from it makes the run's origin TRUE rather than absent. Handing the rule a reference for a run
  -- that arose autonomously would have been the forgery; a run that has no origin at all is simply
  -- a run nothing instructed.
  --
  -- THE FOUNDER COMMAND IS ONLY USED WHERE THE FROZEN REGISTRY SAYS THE WORKFLOW IS FOUNDER-GATED,
  -- and which workflows those are is read from phase_b_business_rule.workflow_scope and
  -- phase_b_workflow_step.founder_gate, never listed here. A workflow with no founder-reserved
  -- step still starts autonomously, and BR-003 stays unresolvable there -- as it should, since
  -- BR-003 does not govern it.
  --
  -- IT AUTHORISES NOTHING BEYOND ITS OWN SENTENCE. The fixture command carries
  -- founder_initiated_only false and refund_semantics false, its founder_identity resolves to
  -- nobody, and founder AUTHENTICATION is fn_phase_c_require_founder, which reads a verified auth
  -- subject and never this table. z00_refund_founder_decision_only on public.refunds is untouched
  -- and still refuses a refund without a founder decision -- measured after this change, not
  -- assumed.
  if exists (select 1 from public.phase_b_workflow_step fs
              where fs.workflow_id = v_wf
                and lower(coalesce(btrim(fs.founder_gate),'none')) <> 'none')
     or exists (select 1 from public.phase_b_business_rule br
                 where br.rule_id in (select re.rule_id from public.phase_d_rule_enforcement re
                                       where 'founder_authority_ref' = any(re.required_context))
                   and (upper(br.workflow_scope) = 'ALL'
                        or v_wf = any(string_to_array(replace(br.workflow_scope,' ',''),';'))))
  then
    -- The command the factory recorded, read from the evidence manifest it wrote — the same row
    -- fn_phase_d_founder_authority_fixture returned, not a second lookup that might find another.
    select nullif(split_part(l.contributed_value, ':', 2),'')::bigint into v_founder_cmd
      from public.phase_d_scenario_record l
     where l.fixture_run_id = public.fn_phase_d_fixture_context()
       and l.contributes_ref = 'founder_authority_ref'
     order by l.scenario_record_id desc limit 1;
  end if;

  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id',        v_wf,
    'business_object_id', v_boid,
    'source_kind',        case when v_founder_cmd is null then 'autonomous' else 'founder_command' end,
    'source_ref',         format('zz-phase-d-%s-%s', v_label, v_wf),
    'requested_by',       w.accountable_role_id,
    'trigger_ctx',        jsonb_build_object('driver','fn_phase_d_drive_workflow',
                                             'path','kernel doors only'))
    || case when v_founder_cmd is null then '{}'::jsonb
            else jsonb_build_object('command_id', v_founder_cmd) end);
  if v_founder_cmd is not null then
    -- fn_kernel_event_consume refuses an event naming a workflow the command did not select, so the
    -- selection is recorded here rather than left implied by the run alone.
    -- K01. THE run_id WAS NEVER WRITTEN. fn_phase_d_step_context reads this table by run_id
    -- first, and all 15 rows carried run_id null, so that read had never matched a row in the
    -- estate's history. It is stamped here -- and ONLY where the kernel's own row says this command
    -- started this run. Where the arrival started the run first (H06) the command did not instruct
    -- it, and claiming otherwise would put founder authority under a customer's inquiry.
    insert into public.founder_command_workflow_link (command_id, workflow_id, run_id)
    values (v_founder_cmd, v_wf,
            (select r2.run_id from public.phase_c_workflow_run r2
              where r2.run_id = v_run and r2.command_id = v_founder_cmd))
    on conflict (command_id, workflow_id) do update
      set run_id = excluded.run_id
      where public.founder_command_workflow_link.run_id is null
        and excluded.run_id is not null;
  end if;
  v_run := (v_start->>'run_id')::bigint;
  if v_run is null then
    return jsonb_build_object('ok', false, 'workflow_id', v_wf,
      'stopped_because', 'the kernel returned no run_id', 'kernel_result', v_start);
  end if;

  -- H06. THE RUN ALREADY EXISTED: the scenario's own arrival started it before the scenario was
  -- complete, and its first dispatch judged half a world. Each open step run whose latest dispatch
  -- was a refusal is dispatched once more, through the same door, under the kernel's own key.
  if coalesce((v_start->>'duplicate')::boolean, false) then
    v_premature := true;
    for sr in select * from public.phase_c_workflow_step_run
               where run_id = v_run
                 and state in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
               order by step_run_id
    loop
      select * into d from public.phase_d_dispatch
       where step_run_id = sr.step_run_id order by dispatch_id desc limit 1;
      if found and d.outcome <> 'EXECUTED' then
        begin
          perform public.fn_phase_d_dispatch_step(jsonb_build_object(
            'step_run_id',     sr.step_run_id,
            'actor_role_id',   sr.accountable_role_id,
            'opened_by_kind',  'scenario_complete',
            'opened_by_ref',   format('the scenario finished after the arrival opened %s', sr.step_id),
            'idempotency_key', (select ws.idempotency_scope from public.phase_b_workflow_step ws
                                 where ws.step_id = sr.step_id) || '|' || v_run || '|' || sr.step_id || '|kernel'));
          v_redispatched := v_redispatched + 1;
        exception when others then null;
        end;
      end if;
    end loop;
  end if;

  loop
    v_i := v_i + 1;
    exit when v_i > v_max;

    select * into sr from public.phase_c_workflow_step_run
     where run_id = v_run
       and state in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
     order by step_run_id
     limit 1;

    -- ---- NO OPEN STEP RUN IS NOT NECESSARILY A STOPPED RUN -----------------------------------
    -- The kernel opens no successor until the receiving owner accepts the handoff.
    if not found then
      select * into hr from public.phase_c_handoff_run
       where run_id = v_run and status = 'open'
       order by handoff_run_id limit 1;
      -- A DRIVER THAT STOPS WITHOUT SAYING WHY IS THE INSTRUMENT GAP THIS ESTATE KEEPS FINDING.
      -- Both of these were a bare `exit when not found` in my first draft, so a run that ended in
      -- waiting_handoff with no D9 contract reported a stop with an empty reason, and a reader
      -- would have taken the blank for "nothing went wrong".
      if not found then
        if v_stopped is null then
          v_stopped := jsonb_build_object(
            'at', (select state from public.phase_c_workflow_run where run_id = v_run),
            'refused_with','pd_drive_no_open_work',
            -- NO run_id IN A REPRODUCIBLE DELIVERABLE. This read "...on run 25384", and a run_id is
            -- different every drive, so the committed CSV could never reproduce byte-for-byte and
            -- phase_d_deliverables_match_production.test.mjs failed on thirty lines that differed
            -- only in that number. The run_id is on the row already, as run_id; a reason is a
            -- reason.
            'reason', 'no step run is open and no handoff run is open; the run is as far as the kernel will take it');
        end if;
        exit;
      end if;

      select * into hc from public.phase_d_handoff_contract where handoff_id = hr.handoff_id;
      if not found then
        if v_stopped is null then
          v_stopped := jsonb_build_object('at', hr.handoff_id, 'refused_with','pd_handoff_contract_absent',
            'reason', format('handoff %s is open and public.phase_d_handoff_contract holds no row for it, so this driver has no packet contract to satisfy', hr.handoff_id));
        end if;
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', false, 'refused_with', 'pd_handoff_contract_absent'));
        exit;
      end if;

      select * into v_prev from public.phase_c_workflow_step_run
       where step_run_id = hr.from_step_run_id;

      -- Derived where the estate can derive it; a labelled caller assertion for the work-product
      -- keys, which are what the sending PERSON hands over and no business rule ever reads.
      v_hpk := coalesce((select jsonb_object_agg(k, format('ZZ DEMO - %s declared by the driver standing in for %s', k, hc.sending_role_id))
                           from unnest(hc.packet_keys) k), '{}'::jsonb)
             || jsonb_build_object(
                  'business_object_id',
                    coalesce((select business_object_id from public.phase_c_workflow_run
                               where run_id = v_run), v_boid),
                  'object_version', coalesce(hr.object_version, 1),
                  'output', coalesce(v_prev.output_hash,
                                     'no output hash recorded on the sending step run'),
                  'evidence_refs',
                    coalesce((select string_agg(result_reference, '; ' order by effect_id)
                                from public.phase_d_effect_ledger
                               where step_run_id = hr.from_step_run_id),
                             'no Phase D effect recorded for the sending step run'),
                  'requested_action',
                    coalesce((select required_action from public.phase_b_workflow_step
                               where step_id = hc.to_step_id),
                             'the frozen receiving step names no required action'));

      begin
        v_hoff := public.fn_phase_d_handoff_accept(jsonb_build_object(
          'handoff_run_id',  hr.handoff_run_id,
          'actor_role_id',   hc.receiving_role_id,
          'packet',          v_hpk,
          'idempotency_key', format('%s:%s:%s', v_label, hr.handoff_id, hr.handoff_run_id)));
        v_haccept := v_haccept + 1;
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', v_hoff->'ok', 'to_step_id', v_hoff->>'to_step_id',
          'accountable_after', v_hoff->>'accountable_after'));
        continue;
      exception when others then
        v_sqlstate := SQLSTATE; v_err := SQLERRM;
        v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', false, 'refused_with', v_code, 'sqlstate', v_sqlstate,
          'reason', left(v_err, 400)));
        if v_stopped is null then
          v_stopped := jsonb_build_object('at', hr.handoff_id, 'refused_with', v_code,
                                          'reason', left(v_err, 400));
        end if;
        -- A driver that skipped a refused handoff would report a closure the workflow never reached.
        exit;
      end;
    end if;

    -- ---- THE HOLD ----------------------------------------------------------------------------
    -- Reached only through the doors above: every earlier step was completed through
    -- fn_kernel_step_complete and every earlier handoff through fn_phase_d_handoff_accept. This
    -- step run is open because the kernel opened it and nothing has closed it.
    if v_hold_any or (v_hold_step is not null and sr.step_id = v_hold_step) then
      v_held_srid := sr.step_run_id;
      v_held_step := sr.step_id;
      v_seen := v_seen || sr.step_run_id;
      if v_stopped is null then
        v_stopped := jsonb_build_object('at', sr.step_id, 'refused_with', 'pd_drive_held_open',
          'reason', 'the caller asked this drive to stop with this step open; nothing was completed on it');
      end if;
      exit;
    end if;

    -- ---- WHAT THE DETERMINISTIC HANDLER DID WITH THIS STEP ------------------------------------
    -- It has already happened. The dispatch fires when the kernel OPENS the step, so by the time
    -- this loop sees an open step run the row is on the table. Reading it is the whole of what this
    -- driver has to do to measure Phase D; it never calls the handler itself.
    select * into d from public.phase_d_dispatch
     where step_run_id = sr.step_run_id order by dispatch_id desc limit 1;

    -- ---- F17. THE CAPABILITY RESULT ARRIVES, AND THE STEP IS DISPATCHED AGAIN ------------------
    -- The founder's section C sequence is: capability request -> capability result -> output
    -- validation -> evidence/provenance -> handler continuation. F05 built the first four and left
    -- the fifth to the caller, because the request is opened INSIDE fn_kernel_open_step and there is
    -- no moment between the open and the refusal for anyone to answer it. This is that moment: the
    -- kernel opened the step, the handler asked and was refused for want of an answer, and the
    -- driver -- standing in for whoever supplies the capability -- submits the pre-authored fixture
    -- result through the canonical acceptance service and asks the estate to dispatch the step
    -- again.
    --
    -- Nothing here bypasses anything. fn_phase_d_capability_result_accept still requires a verified
    -- Phase D fixture context, still validates the payload against the step's own output contract,
    -- still records the fixture id, version and hash, and still refuses provider_mode = provider
    -- while the hold stands. If any of that refuses, the step stays refused and the refusal is
    -- recorded below rather than swallowed.
    if found and d.refusal_code = 'pd_capability_unavailable'
       and public.fn_phase_d_fixture_context() is not null then
      select c.fixture_id into v_cap_fixture
        from public.phase_d_fixture_catalogue c
       where c.scope = 'CAPABILITY_RESULT' and c.step_id = sr.step_id
       order by c.fixture_id limit 1;
      begin
        if v_cap_fixture is null then
          raise exception 'no committed CAPABILITY_RESULT fixture for step % (pd_capability_fixture_unknown)', sr.step_id
            using errcode = '23503';
        end if;
        v_cap_req := public.fn_phase_d_capability_request_open(jsonb_build_object(
          'step_run_id', sr.step_run_id, 'requested_by', sr.accountable_role_id));
        v_cap_res := public.fn_phase_d_capability_result_accept(jsonb_build_object(
          'request_id',    v_cap_req->'request_id',
          'provider_mode', 'fixture',
          'fixture_id',    v_cap_fixture,
          'accepted_by',   sr.accountable_role_id));
        v_capn := v_capn + 1;
        -- HANDLER CONTINUATION: the same door the kernel used, on the same step run.
        v_redisp := public.fn_phase_d_dispatch_step(jsonb_build_object(
          'step_run_id',     sr.step_run_id,
          'actor_role_id',   sr.accountable_role_id,
          'opened_by_kind',  'capability_result',
          'opened_by_ref',   format('%s:result=%s', v_cap_fixture, v_cap_res->>'result_id'),
          'idempotency_key', format('%s:%s:%s:cap', v_label, sr.step_id, sr.step_run_id)));
        v_caps := v_caps || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'request_id', v_cap_req->'request_id',
          'result_id', v_cap_res->'result_id', 'provider_mode', v_cap_res->>'provider_mode',
          'fixture_id', v_cap_res->>'fixture_id', 'fixture_version', v_cap_res->'fixture_version',
          'fixture_hash', v_cap_res->>'fixture_hash',
          'redispatch_outcome', v_redisp->>'outcome',
          'redispatch_refusal', v_redisp->>'refusal_code'));
        select * into d from public.phase_d_dispatch
         where step_run_id = sr.step_run_id order by dispatch_id desc limit 1;
      exception when others then
        v_caps := v_caps || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'fixture_id', v_cap_fixture, 'ok', false,
          'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
          'reason', left(SQLERRM, 300)));
      end;
      v_cap_fixture := null;
    end if;

    -- ---- THE INTERNAL REVIEW, THROUGH THE KERNEL'S OWN DOOR, THEN ASK AGAIN (F35) -----------
    -- The mirror of the capability block above, for the other input class the handler cannot
    -- invent. F34 made fn_phase_d_handler_execute read the verdict and the reviewer from the review
    -- the estate RECORDED -- phase_c_task.reviewer_role_id and the sealed TRACE-ROLE-ACTION -- and
    -- refuse with pd_review_not_recorded when there is none. There is none at step-open time,
    -- because the kernel dispatches the handler the instant the step opens and no review has
    -- happened yet. This is the moment one can: the step is open and owned, the handler has said
    -- what it is missing, and the driver -- standing in for the reviewer -- records the decision
    -- through fn_kernel_review_decide and asks the estate to dispatch the step again.
    --
    -- NOTHING IS BYPASSED. fn_kernel_review_decide refuses a reviewer the frozen registry did not
    -- name where it names one, refuses a reviewer who resolves to the creator, refuses a review
    -- with no stated reason, and seals its own trace. The reviewer is never chosen by preference
    -- here: it is the frozen independent_reviewer_role_id, or a candidate the kernel's own
    -- independence test allows. If it refuses, the step stays refused and the refusal is recorded.
    -- H11. Also record a review when a gate refused for want of the reviewer, not only when the
    -- REVIEW_HANDLER raised pd_review_not_recorded. Same review, same door, same independence check.
    if found and (d.refusal_code = 'pd_review_not_recorded'
                  or (d.refusal_code in ('pd_evidence_absent','pd_gate_refused')
                      and coalesce(d.reason,'') ilike '%reviewer_role_id%')) then
      begin
        select t.task_id into v_rtask from public.phase_c_task t
         where t.run_id = sr.run_id and t.step_id = sr.step_id
         order by t.task_id desc limit 1;

        select s2.independent_reviewer_role_id into v_rrev
          from public.phase_b_workflow_step s2 where s2.step_id = sr.step_id;
        v_rrev := nullif(btrim(coalesce(v_rrev,'')),'');
        if v_rrev is null then
          v_rrev := (select c from unnest(v_cands) c
                      where public.fn_kernel_reviewer_independent(sr.accountable_role_id, c)
                      limit 1);
        end if;
        if v_rrev is null and v_caller_reviewer is not null
           and public.fn_kernel_reviewer_independent(sr.accountable_role_id, v_caller_reviewer) then
          v_rrev := v_caller_reviewer;
        end if;

        if v_rtask is null then
          raise exception 'step % has no task to review (pd_review_no_task)', sr.step_id
            using errcode = '23503';
        end if;
        if v_rrev is null then
          raise exception 'step % is owned by % and no candidate role passes the kernel independence test against it (pd_review_no_independent_reviewer)',
            sr.step_id, sr.accountable_role_id using errcode = '23503';
        end if;

        -- The stated reason is the committed rationale fixture, not a sentence written here.
        v_rdec := public.fn_kernel_review_decide(jsonb_build_object(
          'task_id',          v_rtask,
          'reviewer_role_id', v_rrev,
          'decision',         'approved',
          'reason',           coalesce(
                                public.fn_phase_d_fixture_output(sr.step_id,'rationale') #>> '{}',
                                'PHASE_D_FIXTURE_DO_NOT_PUBLISH - no committed rationale fixture')));

        if coalesce((v_rdec->>'ok')::boolean, false) then
          v_redisp := public.fn_phase_d_dispatch_step(jsonb_build_object(
            'step_run_id',     sr.step_run_id,
            'actor_role_id',   sr.accountable_role_id,
            'opened_by_kind',  'internal_review',
            'opened_by_ref',   format('task=%s;reviewer=%s', v_rtask, v_rrev),
            'idempotency_key', format('%s:%s:%s:rev', v_label, sr.step_id, sr.step_run_id)));
          select * into d from public.phase_d_dispatch
           where step_run_id = sr.step_run_id order by dispatch_id desc limit 1;
        end if;

        v_revn := v_revn + 1;
        v_revs := v_revs || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'task_id', v_rtask, 'reviewer_role_id', v_rrev,
          'review_ok', v_rdec->'ok', 'review_error', v_rdec->>'error',
          'redispatch_outcome', v_redisp->>'outcome',
          'redispatch_refusal', v_redisp->>'refusal_code'));
      exception when others then
        v_revs := v_revs || jsonb_build_array(jsonb_build_object(
          'step_id', sr.step_id, 'ok', false,
          'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
          'reason', left(SQLERRM, 300)));
      end;
    end if;

    if found then
      v_dispatched := v_dispatched + 1;
      if d.outcome = 'EXECUTED' then v_executed := v_executed + 1; end if;
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'ok', (d.outcome = 'EXECUTED'), 'dispatch_outcome', d.outcome,
        'refused_with', nullif(d.refusal_code,''), 'reason', left(coalesce(d.reason,''), 400),
        'unresolved_keys', to_jsonb(coalesce(d.unresolved_keys,'{}'::text[])),
        'effect_id', d.effect_id));
      -- TWO SUBJECTS, TWO FIELDS. My first draft folded both into one 'stopped' object, and the
      -- deliverable then reported W21 as stopping at W21-S01 when the drive had in fact reached
      -- W21-S07 -- because step 1's dispatch refused, as nearly every dispatch does, and that was
      -- the first thing to claim the field. Where the HANDLER first declined is a Phase D fact;
      -- where the DRIVE could go no further is a fact about this harness and the kernel.
      if d.outcome <> 'EXECUTED' and v_first_refusal is null then
        v_first_refusal := jsonb_build_object('at', sr.step_id,
                                              'refused_with', nullif(d.refusal_code,''),
                                              'reason', left(coalesce(d.reason,''), 400));
      end if;
    else
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'ok', false, 'dispatch_outcome', 'NOT_DISPATCHED',
        'refused_with', 'pd_no_dispatch_row',
        'reason', 'the kernel opened this step and no phase_d_dispatch row exists for it'));
      if v_first_refusal is null then
        v_first_refusal := jsonb_build_object('at', sr.step_id, 'refused_with','pd_no_dispatch_row',
          'reason','the kernel opened this step and no phase_d_dispatch row exists for it');
      end if;
    end if;

    -- ---- F38. THE HANDLER MAY HAVE ALREADY COMPLETED THIS STEP -----------------------------
    -- fn_phase_d_handler_execute section 7 hands the completed step to the FROZEN KERNEL itself.
    -- When it succeeds, the kernel closes the step run, opens the successor, and -- where the step
    -- ends in a handoff -- moves the whole run to waiting_handoff. The driver then arrived at its
    -- own fn_kernel_step_complete for a step that was already closed, against a run that was no
    -- longer active, and was refused:
    --
    --   k3_run_not_active: workflow run N is in state waiting_handoff, not active
    --
    -- and the drive stopped there. MEASURED, and it is the reason a fix made the headline fall:
    -- after F36 let the five capability steps execute, total EXECUTED across the estate went from
    -- 45 to 36, because every workflow whose handler succeeded early now died at the next
    -- iteration. Success in one place was being converted into an earlier stop.
    --
    -- The kernel is right on both counts and neither is touched. What was wrong is that this
    -- driver assumed every step needs an actor to close it. A step the HANDLER closed is closed;
    -- the driver re-reads the step run and, if the kernel has moved it out of every open state,
    -- takes the next piece of work instead of trying to close it twice.
    --
    -- This is also the §4 distinction the founder asked for: a step closed here is
    -- CANONICAL_HANDLER_EFFECT, and a step closed below is CANONICAL_ACTOR_INPUT. They are counted
    -- apart because they are different claims.
    v_seen := v_seen || sr.step_run_id;   -- G07: what this loop saw, so what it did not see is derivable
    select * into sr2 from public.phase_c_workflow_step_run where step_run_id = sr.step_run_id;
    if found and sr2.state not in
       ('ready','active','not_ready','waiting_input','waiting_review','blocked') then
      v_handler_closed := v_handler_closed + 1;
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'closed_by', 'CANONICAL_HANDLER_EFFECT', 'step_run_state', sr2.state));
      continue;
    end if;

    -- ---- A STEP THAT NEEDS AN INDEPENDENT VERDICT GETS ONE, THROUGH THE KERNEL'S OWN DOOR ------
    -- The reviewer is never chosen here: it is the one the frozen registry declares, or one the
    -- CALLER offered, and fn_kernel_review_decide decides independence either way. A driver that
    -- picked a reviewer would be fn_pick_reviewer returning the department head, one layer up.
    select s.independent_reviewer_role_id into v_declared
      from public.phase_b_workflow_step s where s.step_id = sr.step_id;
    v_rev := nullif(btrim(coalesce(v_declared,'')),'');
    if v_rev is null then
      v_rev := (select c from unnest(v_cands) c
                 where public.fn_kernel_reviewer_independent(sr.accountable_role_id, c) limit 1);
    end if;
    if v_rev is null and v_caller_reviewer is not null
       and public.fn_kernel_reviewer_independent(sr.accountable_role_id, v_caller_reviewer) then
      v_rev := v_caller_reviewer;
    end if;
    if v_rev is not null then
      select t.task_id into v_task from public.phase_c_task t
       where t.run_id = v_run and t.step_id = sr.step_id order by t.task_id desc limit 1;
      if v_task is not null then
        begin
          v_decide := public.fn_kernel_review_decide(jsonb_build_object(
            'task_id', v_task, 'reviewer_role_id', v_rev, 'decision', 'approved',
            'reason', format('%s: an independent reviewer approves %s', v_label, sr.step_id)));
        exception when others then
          -- Recorded, never swallowed: a verdict that could not be written is why the step may
          -- refuse a moment later, and a driver that hid it would make that refusal unexplainable.
          v_decide := jsonb_build_object('ok', false, 'error', left(SQLERRM, 240));
        end;
      end if;
    end if;

    -- ---- THE DOOR PRODUCTION USES ------------------------------------------------------------
    -- fn_kernel_step_complete, with what an ACTOR supplies and nothing else. No context, no gate
    -- evidence, no business_key, no owner_ref, no effect payload: the kernel dispatch resolves all
    -- of those from fn_phase_d_step_inputs and fn_phase_d_step_context, and will not accept them
    -- from a caller. That is the property this file exists to restore.
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id',      sr.step_run_id,
        'actor_role_id',    sr.accountable_role_id,
        'outcome',          'pass',
        'idempotency_key',  format('%s:%s:%s', v_label, sr.step_id, sr.step_run_id),
        'inputs',           jsonb_build_object('driver','fn_phase_d_drive_workflow',
                                               'note','no business content is supplied by this driver'),
        'output',           jsonb_build_object('status','completed',
                                               'output', format('%s completed %s', v_label, sr.step_id)),
        'evidence_refs',    jsonb_build_array(jsonb_build_object('driver_run', v_label)),
        'requested_action', 'proceed',
        'acceptance_criteria', format('%s drove %s through the kernel', v_label, sr.step_id),
        'object_version',   1));
      v_driven := v_driven + 1;
    exception when others then
      v_sqlstate := SQLSTATE; v_err := SQLERRM;
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'ok', false, 'kernel_refused', true, 'refused_with', v_code,
        'sqlstate', v_sqlstate, 'reason', left(v_err, 400)));
      v_stopped := jsonb_build_object('at', sr.step_id, 'refused_with', v_code,
                                      'reason', left(v_err, 400),
                                      'refused_by', 'fn_kernel_step_complete');
      exit;
    end;
  end loop;

  select state into v_run_state from public.phase_c_workflow_run where run_id = v_run;

  -- G07. THE CLOSURES THIS LOOP NEVER SAW, read from the ledger that already recorded them.
  -- A step run carrying an EXECUTED dispatch and sitting in no open state was closed by the
  -- handler's own call into fn_kernel_step_complete. Excluding the step runs the loop handled makes
  -- the two counts disjoint by construction rather than by argument.
  -- ALIASED disp, NOT d: this routine declares a RECORD named d, and a plpgsql variable shadows a
  -- table alias of the same name rather than losing to it.
  select count(distinct disp.step_run_id) into v_unseen
    from public.phase_d_dispatch disp
    join public.phase_c_workflow_step_run x on x.step_run_id = disp.step_run_id
   where disp.run_id = v_run
     and disp.outcome = 'EXECUTED'
     and x.state not in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
     and not (disp.step_run_id = any(v_seen));

  return jsonb_build_object(
    'ok', true,
    'workflow_id', v_wf,
    'run_id', v_run,
    'label', v_label,
    -- Named for what it measures, not for what a reader might hope it measures.
    'path', 'fn_kernel_workflow_start -> fn_kernel_review_decide -> fn_kernel_step_complete -> fn_phase_d_handoff_accept',
    'steps_in_workflow', (select count(*) from public.phase_b_workflow_step where workflow_id = v_wf),
    'held_step_id', v_held_step,
    'held_step_run_id', v_held_srid,
    'steps_driven', v_driven,
    'handoffs_accepted', v_haccept,
    'open_handoffs_left', (select count(*) from public.phase_c_handoff_run
                            where run_id = v_run and status = 'open'),
    -- What Phase D actually did: how many step-openings the kernel dispatched to the
    -- deterministic handler, and how many of those the handler completed unaided.
    -- COUNTED FROM THE TABLE, NOT FROM THIS LOOP. The first version incremented these as the loop
    -- walked the open steps, and it reported dispatches_executed = 0 on a run that had produced
    -- three effect-ledger rows. The reason is the whole of E33: a step whose handler EXECUTES has
    -- its task closed in the same statement that opened it, so it is never an open step and this
    -- loop never sees it. An instrument that counts only what it walks past cannot count the thing
    -- that finishes before the walk reaches it. The population is every dispatch the kernel
    -- produced for this run.
    'dispatches_seen', (select count(*) from public.phase_d_dispatch where run_id = v_run),
    'dispatches_executed', (select count(*) from public.phase_d_dispatch
                             where run_id = v_run and outcome = 'EXECUTED'),
    'dispatch_outcomes', (select coalesce(jsonb_object_agg(o, n), '{}'::jsonb) from (
        select coalesce(nullif(refusal_code,''), outcome) o, count(*) n
          from public.phase_d_dispatch where run_id = v_run group by 1) z),
    'steps_loop_walked', v_dispatched,
    'effects_for_this_run', (select count(*) from public.phase_d_effect_ledger where run_id = v_run),
    'effects_total_delta', (select count(*) from public.phase_d_effect_ledger) - v_before,
    'run_state', v_run_state,
    -- phase_b_workflow.allowed_terminal_states is TEXT, not an array: 'completed; cancelled;
    -- superseded'. My first draft wrote `v_run_state = any((select allowed_terminal_states ...))`,
    -- which Postgres parses as the SUBQUERY form of ANY — so it compared the run state against the
    -- whole semicolon-separated string as one value and was false for every run ever driven.
    -- closure_verdict could therefore only ever read STOPPED, and this deliverable reported 0 of 30
    -- closing while runs were reaching 'completed'. Caught by the deliverable's own reproduction
    -- test, not by reading the code.
    'terminal', exists (
       select 1 from public.phase_b_workflow w2,
            lateral unnest(string_to_array(coalesce(w2.allowed_terminal_states,''), ';')) s
        where w2.workflow_id = v_wf and btrim(s) = v_run_state),
    -- Where the DRIVE could go no further. Null only when the run reached a terminal state with
    -- nothing open, which is the one case where "it stopped" needs no explanation.
    'stopped', coalesce(v_stopped, case when v_i > v_max
      then jsonb_build_object('at','(step budget)','refused_with','pd_drive_max_steps',
             'reason', format('the drive ran %s steps and max_steps is %s', v_i - 1, v_max))
      else null end),
    -- Where the deterministic HANDLER first declined. This is the Phase D subject, and it is a
    -- different question from the one above. Read from the dispatch table in dispatch order for
    -- the same reason the counts are: the loop does not see every dispatched step.
    'first_handler_refusal', coalesce(
      (select jsonb_build_object('at', step_id, 'refused_with', nullif(refusal_code,''),
                                 'reason', left(coalesce(reason,''), 400))
         from public.phase_d_dispatch
        where run_id = v_run and outcome <> 'EXECUTED'
        order by dispatch_id limit 1), v_first_refusal),
    'capability_results_accepted', v_capn,
    'premature_arrival_run', v_premature,
    'steps_redispatched_after_scenario', v_redispatched,
    'capability_path', v_caps,
    'steps_closed_by_the_handler', v_handler_closed + v_unseen,
    'steps_closed_by_the_handler_before_the_loop_began', v_unseen,
    'internal_reviews_recorded', v_revn,
    'review_path', v_revs,
    'steps', v_steps,
    'handoffs', v_handoffs);
end $function$
;
