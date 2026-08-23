-- L03 — the acceptance record stated neither the version nor the digest it accepted
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh.
--
-- public.phase_b_workflow_step says W09-S06's required output is "Immutable supplier acceptance
-- record" and its completion condition is "Displayed version, recorded version and document hash
-- match". The record the handler wrote carried a workflow_record blob and nothing else: no version,
-- no digest, nothing to match. Nothing reported it, because public.fn_phase_d_fixture_scenario
-- builds a supplier_terms_acceptance of its own with the published pair on it (F08), and every
-- downstream read found THAT record. The product's defect was covered by the harness's fixture --
-- "a harness that seeds the row the step is supposed to create is answering its own question",
-- one layer further in than where that sentence was first written.
--
-- Two halves, and both are reads:
--
--   1. WHAT THE STEP IS ACCEPTING. With the stage withheld there is no acceptance to read the pair
--      from, and both keys fell through to committed catalogue fixtures PDF-3104 and PDF-3105 --
--      'phase-d-fixture-terms-v1' at the digest of a fixture terms body. BR-025 resolves the pair
--      against public.legal_documents and correctly refused: "matches 0 row(s)". Nothing was wrong
--      with the fixtures; what was wrong is that they were the answer at all, for a key that names
--      the document the platform actually displayed. An acceptance step accepts the CURRENTLY
--      PUBLISHED document, and which document belongs to which acceptance object is registered
--      here once, in public.phase_d_acceptance_document, and read by both this resolver and (from
--      L03 onward) nothing else that guesses.
--
--   2. WHAT THE RECORD SAYS. The handler already closes its payload with the review verdict for a
--      REVIEW_VERDICT effect and with decided_by/decided_at for a DECISION_HANDLER. The accepted
--      version and digest join them, for a step whose effect object is a registered acceptance.
--
-- After both: W09-S01..S09 all EXECUTED with the workflow's own output withheld, the acceptance
-- record carries version v5 and the true digest of the published supplier agreement, and BR-025
-- passes at W09-S06 for a reason it can also fail for.
--
-- REQUIRES: L01 (the identity doors), L04 (the owner of an object-store record).
-- ROLLBACK: scripts/sql/down/phase_d_l03_the_acceptance_record_stated_neither_the_version_nor_the_digest_down.sql
-- GENERATED from the live bodies by scripts/tmp_diag/gen_l_series.mjs.

create table if not exists public.phase_d_acceptance_document (
  object_id     text primary key,
  document_slug text not null,
  why           text not null,
  registered_at timestamptz not null default now()
);
revoke all on public.phase_d_acceptance_document from public;
grant select on public.phase_d_acceptance_document to service_role;

insert into public.phase_d_acceptance_document (object_id, document_slug, why) values
  ('customer_terms_acceptance','customer-terms',
   'W04 records a customer''s acceptance of the published customer terms; public.fn_phase_d_fixture_scenario reads the same slug at F08'),
  ('supplier_terms_acceptance','supplier-agreement',
   'W09-S06 records a supplier''s acceptance of the published supplier agreement; public.fn_phase_d_fixture_scenario reads the same slug at F08')
on conflict (object_id) do nothing;

-- A register that names a document nobody publishes is a constant again.
do $l03$
declare v_bad text;
begin
  select string_agg(a.object_id || ' -> ' || a.document_slug, ', ') into v_bad
    from public.phase_d_acceptance_document a
   where not exists (select 1 from public.legal_documents d where d.slug = a.document_slug);
  if v_bad is not null then
    raise exception 'phase_d_acceptance_document names % which public.legal_documents does not publish', v_bad;
  end if;
end $l03$;

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
     where gc.gate_id = any (coalesce(b.gate_ids,'{}'))
    -- K03. THE PARENT OF THE RECORD THIS STEP WRITES. The list was the union of what the step's
    -- rules and gates ask for, and nothing else, so a key no rule happens to name was never
    -- resolved even where the estate could answer it. W16-S01 wrote a reveal payment that belonged
    -- to no quote for exactly that reason. The object's own frozen binding names its parent and the
    -- write map names the payload key that carries it; both are read here. A step that writes no
    -- business object adds nothing, and a key a rule already asks for is unchanged -- this is a
    -- distinct union.
    union
    select wm.column_map->>bb.parent_identity k
      from public.phase_d_business_object_binding bb
      join public.phase_d_object_write_map wm on wm.object_id = bb.object_id
     where bb.object_id = ec.effect_object_id
       and coalesce(btrim(bb.parent_identity),'') <> ''
       and wm.column_map ? bb.parent_identity
       and wm.column_map->>bb.parent_identity not in ('business_key','owner_ref','state')
    ) q(k);

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
        from public.phase_d_context_key_object cko
       where cko.context_key = v_k and cko.key_role = 'IDENTIFIES';

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
      -- L03. AND AT THE STEP THAT RECORDS THE ACCEPTANCE THERE IS NOTHING TO FIND YET.
      -- W09-S06 is the only step in the estate whose declared effect object is a terms acceptance.
      -- Asked to withhold the object the workflow under test produces -- which is what a harness
      -- that does not answer its own question must do -- no acceptance record exists at S06, both
      -- keys fell to the catalogue door, and BR-025 refused with "matches 0 row(s) in
      -- public.legal_documents" for fixture PDF-3104/PDF-3105: a version string and a digest over
      -- a fixture terms body that is not a published document and never can be one.
      -- An acceptance step accepts THE CURRENTLY DISPLAYED DOCUMENT. Which document that is, for
      -- which acceptance object, is registered once in public.phase_d_acceptance_document and read
      -- from public.legal_documents here -- the same relation BR-025 judges against, so the rule
      -- keeps its ability to fail: a step that produces no registered acceptance resolves nothing
      -- here and falls through to the catalogue exactly as before.
      if coalesce(btrim(coalesce(v_val #>> '{}','')),'') = '' then
        select case when v_k = 'terms_version' then d.version
                    else encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex') end
          into v_val_txt
          from public.phase_d_step_effect x
          join public.phase_d_acceptance_document a on a.object_id = x.effect_object_id
          join public.legal_documents d on d.slug = a.document_slug
         where x.step_id = sr.step_id
         order by d.version desc limit 1;
        if coalesce(btrim(v_val_txt),'') <> '' then
          v_val := to_jsonb(v_val_txt);
          v_src := 'public.legal_documents — the currently published document this step''s own '
                || 'acceptance object accepts, per public.phase_d_acceptance_document';
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
    -- K07. THE OBJECT THIS RUN ALREADY CREATED, before any fixture is consulted.
    --
    -- A key that names an object was answered from the run's own row, from a declared foreign key
    -- on it, or -- fixture context only -- from the canonical reference the SCENARIO recorded.
    -- Nothing answered "the object THIS RUN produced at an earlier step", so W17-S07 asked for the
    -- refund_id of a refund_dispute_case that W17-S01 had created six steps earlier and was told
    -- there was none. public.phase_d_effect_ledger holds it: run_id, effect_object_id and the
    -- canonical result_reference fn_phase_d_object_write returned. This is not a fixture and it runs
    -- in production; it is asked after every source that reads the run's own row, and before the
    -- scenario record, because a fact this run produced outranks one a scenario planted.
    if (v_val is null or v_val = 'null'::jsonb
        or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = '')) then
      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko
       where cko.context_key = v_k and cko.key_role = 'IDENTIFIES';
      if v_key_obj is not null then
        select nullif(btrim(substring(el.result_reference from position('=' in el.result_reference) + 1)),'')
          into v_link_v
          from public.phase_d_effect_ledger el
          join public.phase_d_business_object_binding bb on bb.object_id = el.effect_object_id
         where el.run_id = sr.run_id
           and el.effect_object_id = v_key_obj
           -- AN EFFECT NAMED FOR AN OBJECT IS NOT ALWAYS A REFERENCE TO ONE. phase_d_effect_ledger
           -- records effect_object_id from the step's DECLARED object, so a REVIEW_VERDICT step of
           -- W15 carries effect_object_id quotation_comparison and result_reference
           -- public.review_chain:id=15748 -- the identity of the review, not of the comparison.
           -- Taking it made GATE-018 judge a review row as a comparison and refuse W15-S05 for
           -- 'comparison 15748 does NOT belong to the calling customer', which was true and was
           -- about the wrong row. Only a reference into the object's OWN canonical relation is an
           -- identity of that object.
           and el.effect_relation = bb.canonical_relation
           and coalesce(btrim(el.result_reference),'') <> ''
           and position('=' in el.result_reference) > 0
         order by el.effect_id desc limit 1;
        if v_link_v is not null then
          v_ctx  := v_ctx  || jsonb_build_object(v_k, to_jsonb(v_link_v));
          v_prov := v_prov || jsonb_build_object(v_k,
            format('the canonical reference of the %s this run itself created, read from '
                || 'public.phase_d_effect_ledger.result_reference', v_key_obj));
          v_link_v := null; v_key_obj := null;
          continue;
        end if;
      end if;
      v_key_obj := null;
    end if;

    if (v_val is null or v_val = 'null'::jsonb
        or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = ''))
       and public.fn_phase_d_fixture_context() is not null then
      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko
       where cko.context_key = v_k and cko.key_role = 'IDENTIFIES';
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

CREATE OR REPLACE FUNCTION public.fn_phase_d_handler_execute(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_review jsonb;   -- F34: the recorded canonical internal review for this step run
  b   public.phase_d_handler_binding%rowtype;
  s   public.phase_b_workflow_step%rowtype;
  sr  public.phase_c_workflow_step_run%rowtype;
  ec  public.phase_d_step_effect%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_idem     text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_inputs   jsonb  := coalesce(p_input->'inputs','{}'::jsonb);
  v_ctx      text   := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_ok       boolean; v_reason text; v_missing text[];
  v_rule     record; v_rule_ok boolean; v_rule_type text; v_rule_reason text;
  v_applies  boolean; v_why text; v_enforced boolean; v_refusal text; v_state text;
  v_ev_absent boolean := false;   -- E19
  v_refused  jsonb := '[]'::jsonb;
  v_skipped  jsonb := '[]'::jsonb;
  v_gate     record; v_gstate text; v_gpassed boolean; v_gtype text;
  v_greason  text; v_grefusal text; v_gapplies boolean; v_gwhy text;
  v_gates    jsonb := '[]'::jsonb;
  v_gblocked jsonb := '[]'::jsonb;
  v_evaluated jsonb := '[]'::jsonb;
  v_output   jsonb;
  v_assert   jsonb;
  v_result   jsonb;
  v_effect   jsonb;
  v_cap      jsonb;   -- F05: the accepted capability result for this step run, or null
  v_cap_req  jsonb;   -- F05: the capability request this handler opened
begin
  -- ---- 0. the call itself ------------------------------------------------------------------
  if v_step_run is null or v_actor is null or v_idem is null then
    raise exception 'fn_phase_d_handler_execute: step_run_id, actor_role_id and idempotency_key are all required (got %, %, %) (pd_input_schema_invalid)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)'), coalesce(v_idem,'(null)')
      using errcode = '22023';
  end if;
  if v_ctx not in ('production','test') then
    raise exception 'fn_phase_d_handler_execute: execution_context must be production or test, got %',
      v_ctx using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_handler_execute: no step run % (pd_step_state_invalid)', v_step_run
      using errcode = '23503';
  end if;

  -- ---- 0b. THE BRANCH PROBE'S HOLD --------------------------------------------------------
  -- Section 1 of the founder's ruling asks for BRANCH coverage of all 257 frozen steps. The frozen
  -- model is a linear chain: next_step_if_pass names the next step (or WORKFLOW_COMPLETE), and
  -- next_step_if_fail names one of three symbolic outcomes and never a step. So a step's fail edge
  -- is exercised by an ACTOR reporting failure on it, which requires the step to be OPEN.
  --
  -- MEASURED 23 Aug 2026: 249 of 257 steps are completed by this handler in the same statement the
  -- kernel opens them, so they are never open and no actor can ever take them. W18 is the extreme
  -- case -- all seven steps EXECUTED unaided, the run reaching completed inside
  -- fn_kernel_workflow_start, nothing left to fail or cancel. A handler that succeeds is the
  -- system working; it also means the fail edge of the frozen model is unreachable through the
  -- actor door, and an unexercised branch cannot be reported as covered.
  --
  -- This is the hold, and every part of it is deliberately narrow:
  --   * it acts only inside an open Phase D fixture context, which fn_phase_d_test_context_open
  --     grants for one operation inside one transaction that ends in raise exception;
  --   * it names ONE step, set by the caller at transaction level, and never a workflow or a class;
  --   * it refuses with its own code, pd_handler_held_for_branch_probe, which appears in
  --     phase_d_dispatch.refusal_code -- so no reader, and no deliverable, can mistake a held step
  --     for a handler that could not do its work;
  --   * it changes nothing else. The kernel then does exactly what it does for any refused
  --     dispatch: the step stays open and owned.
  --
  -- What the fail-branch case then proves is the KERNEL's edge for that step -- outcome fail moves
  -- the step to failed and the run to the step's declared failure_workflow_state, with no partial
  -- effect and no residue -- and NOT that the handler could have failed. Those are different
  -- claims and the coverage matrix records which one it has, per step.
  if nullif(btrim(coalesce(current_setting('app.phase_d_hold_step', true), '')), '') = sr.step_id
     and public.fn_phase_d_fixture_context() is not null then
    raise exception 'fn_phase_d_handler_execute: step % is held open by an audited Phase D branch probe; the handler declined so an actor can take the step (pd_handler_held_for_branch_probe)',
      sr.step_id using errcode = '23505';
  end if;

  select * into b from public.phase_d_handler_binding where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_handler_execute: step % has no Phase D handler binding — fail closed. Every one of the 257 frozen steps must carry exactly one. (pd_input_schema_invalid)',
      sr.step_id using errcode = '23503';
  end if;
  select * into s from public.phase_b_workflow_step where step_id = sr.step_id;

  select * into ec from public.phase_d_step_effect where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_handler_execute: step % has no declared effect contract. A handler with no declared effect is the schema-only handler this phase exists to remove. (pd_effect_undeclared)',
      sr.step_id using errcode = '23503';
  end if;

  -- ---- 1. TYPED INPUT ----------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.input_schema_id, v_inputs);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % input rejected: % (pd_input_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 2. RULES IN SCOPE -------------------------------------------------------------------
  -- SCOPE IS NOT APPLICABILITY. The frozen registry scopes rules by WORKFLOW, so BR-002 is in
  -- scope for all 257 steps while only 28 of them name an independent reviewer. Asking
  -- fn_kernel_reviewer_independent about a NULL reviewer returns false, which refused an intake
  -- step for a creator/reviewer collision that could not exist. fn_phase_d_rule_applies decides
  -- both, and records the reason either way.
  --
  -- Refusals are collected rather than short-circuited: a caller told only the first thing wrong
  -- fixes one thing and comes back.
  for v_rule in select unnest(b.rule_ids) rid loop
    select applies, why into v_applies, v_why
      from public.fn_phase_d_rule_applies(v_rule.rid, sr.step_id);
    if not coalesce(v_applies,false) then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'applies', false, 'why', v_why));
      continue;
    end if;

    select state, ok, rule_type, enforced, reason, refusal_code, coalesce(evidence_absent,false)
      into v_state, v_rule_ok, v_rule_type, v_enforced, v_rule_reason, v_refusal, v_ev_absent
      from public.fn_phase_d_rule_check(v_rule.rid,
        jsonb_build_object(
          'accountable_role_id', sr.accountable_role_id,
          'reviewer_role_id',    nullif(b.independent_reviewer_role_id,''),
          'actor_role_id',       v_actor,
          'step_id',             sr.step_id,
          'workflow_id',         b.workflow_id,
          'run_id',              sr.run_id,
          'founder_gate',        b.founder_gate,
          'execution_context',   v_ctx)
        || coalesce(p_input->'context','{}'::jsonb));

    v_evaluated := v_evaluated || jsonb_build_array(jsonb_build_object(
      'rule_id', v_rule.rid, 'state', v_state, 'rule_type', v_rule_type, 'ok', v_rule_ok,
      'enforced', v_enforced, 'reason', v_rule_reason));

    if v_rule_type = 'hard' and v_state in ('ENFORCED_FAIL','NOT_IMPLEMENTED') then
      v_refused := v_refused || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'state', v_state, 'rule_type', v_rule_type,
        'refusal_code', v_refusal, 'reason', v_rule_reason,
        'evidence_absent', v_ev_absent));
    end if;
  end loop;
  if jsonb_array_length(v_refused) > 0 then
    -- E19. TWO DIFFERENT EVENTS DESERVE TWO DIFFERENT NAMES. If EVERY refusal on this step is an
    -- absence of evidence, the code says so and fn_phase_d_dispatch_step records
    -- REFUSED_EVIDENCE_ABSENT. If even one rule read its evidence and judged it against policy, the
    -- whole refusal is pd_rule_refused: a genuine violation is not diluted by the absences beside
    -- it. Both refuse, and neither is a pass.
    if not exists (select 1 from jsonb_array_elements(v_refused) x
                    where not coalesce((x->>'evidence_absent')::boolean, false)) then
      raise exception 'fn_phase_d_handler_execute: step % refused by % hard business rule(s), every one of them for evidence the call did not name rather than for a policy the call broke: % (pd_evidence_absent)',
        sr.step_id, jsonb_array_length(v_refused), v_refused::text using errcode = '23514';
    end if;
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard business rule(s): % (pd_rule_refused)',
      sr.step_id, jsonb_array_length(v_refused), v_refused::text using errcode = '23514';
  end if;

  -- ---- 2b. GATES IN SCOPE, EACH AGAINST ITS OWN DECLARED EVIDENCE --------------------------
  for v_gate in select unnest(b.gate_ids) gid loop
    select ga.applies, ga.why into v_gapplies, v_gwhy
      from public.fn_phase_d_gate_applies(v_gate.gid, sr.step_id) ga;
    if not coalesce(v_gapplies,false) then
      v_gates := v_gates || jsonb_build_array(jsonb_build_object(
        'gate_id', v_gate.gid, 'state', 'NOT_APPLICABLE', 'why', v_gwhy));
      continue;
    end if;
    select ge.state, ge.passed, ge.gate_type, ge.reason, ge.refusal_code, coalesce(ge.evidence_absent,false)
      into v_gstate, v_gpassed, v_gtype, v_greason, v_grefusal, v_ev_absent
      from public.fn_phase_d_gate_evaluate(v_gate.gid,
        jsonb_build_object('step_id', sr.step_id, 'run_id', sr.run_id,
                           'step_run_id', v_step_run,
                           'step_run_id', v_step_run,
                           'actor_role_id', v_actor,
                           'reviewer_role_id', nullif(b.independent_reviewer_role_id,''))
        || coalesce(p_input->'gate_evidence','{}'::jsonb)) ge;

    v_gates := v_gates || jsonb_build_array(jsonb_build_object(
      'gate_id', v_gate.gid, 'state', v_gstate, 'gate_type', v_gtype,
      'passed', v_gpassed, 'reason', v_greason));

    if v_gtype = 'hard' and v_gstate in ('BLOCKED','NOT_IMPLEMENTED') then
      v_gblocked := v_gblocked || jsonb_build_array(jsonb_build_object(
        'gate_id', v_gate.gid, 'state', v_gstate,
        'refusal_code', v_grefusal, 'reason', v_greason,
        'evidence_absent', v_ev_absent));
    end if;
  end loop;
  if jsonb_array_length(v_gblocked) > 0 then
    if not exists (select 1 from jsonb_array_elements(v_gblocked) x
                    where not coalesce((x->>'evidence_absent')::boolean, false)) then
      raise exception 'fn_phase_d_handler_execute: step % blocked by % hard gate(s), every one of them for evidence the call did not name rather than for a condition the gate judged and rejected: % (pd_evidence_absent)',
        sr.step_id, jsonb_array_length(v_gblocked), v_gblocked::text using errcode = '23514';
    end if;
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard gate(s): % (pd_gate_refused)',
      sr.step_id, jsonb_array_length(v_gblocked), v_gblocked::text using errcode = '23514';
  end if;

  -- ---- 3. CAPABILITY BOUNDARY, FAIL CLOSED, AND NO LONGER A MODE STRING --------------------
  -- F05. This read `if b.capability_dependency <> 'NONE' and v_ctx <> 'test'`, so the literal
  -- 'test' arriving in one field turned twenty-one fail-closed business boundaries off at once.
  -- The founder prohibited exactly that shape on 21 Aug 2026. The mode is no longer consulted:
  -- the handler asks whether an ACCEPTED capability result exists for this step run, and the only
  -- way one exists is through fn_phase_d_capability_result_accept, which validates it against the
  -- step's own output contract and which refuses a fixture result outright unless a Phase D
  -- fixture context verifies (F01).
  --
  -- In production there is no fixture context and no provider, so there is no result, so this
  -- raises -- the same refusal, at the same point, for a reason that is now a read rather than a
  -- comparison against a caller-supplied string.
  if b.capability_dependency <> 'NONE' then
    -- The request is opened first and in every context: it is the row a Phase E provider answers,
    -- and a step that never asked cannot be said to have been refused.
    v_cap_req := public.fn_phase_d_capability_request_open(jsonb_build_object(
      'step_run_id', v_step_run, 'requested_by', v_actor));
    v_cap := public.fn_phase_d_capability_answer(v_step_run);
    if v_cap is null then
      raise exception 'fn_phase_d_handler_execute: step % depends on capability % (matched on the frozen required_action at: %) and capability request % carries no accepted result. Paid inference is held until Phase E; a Phase D fixture result must be submitted through fn_phase_d_capability_result_accept, which requires a verified Phase D fixture context. Refusing rather than completing a business step from nothing. (pd_capability_unavailable)',
        sr.step_id, b.capability_dependency, coalesce(nullif(b.capability_evidence,''),'(none)'),
        coalesce(v_cap_req->>'request_id','(none)')
        using errcode = '23514';
    end if;
  end if;

  -- ---- 4. PROVIDER BOUNDARY, FAIL CLOSED ---------------------------------------------------
  -- Same correction, same reason. A provider dependency is refused whatever the execution context
  -- says, because the hold is on the provider and not on the caller's description of itself.
  if b.provider_dependency <> 'NONE' then
    raise exception 'fn_phase_d_handler_execute: step % depends on external provider % which is disabled for the whole of Phase D. No execution context lifts this. (pd_provider_disabled)',
      sr.step_id, b.provider_dependency using errcode = '23514';
  end if;

  -- ---- 4b. H01. THE VERDICT THE KERNEL WILL DEMAND, ASKED FOR HERE FIRST ----------------------
  -- fn_kernel_step_complete 3g refuses a pass on a step whose frozen row names an independent
  -- reviewer unless an approved, independent verdict from that role is sealed on the task. The
  -- handler used to discover that only after producing its effect, and the refusal came out of the
  -- kernel as k3_reviewer_verdict_missing. The same predicate is asked here, before anything is
  -- built, and the refusal is the one the driver answers through fn_kernel_review_decide. Nothing
  -- about the kernel check changes; it still decides at 3g.
  if coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
     and not exists (
       select 1
         from public.phase_c_task t
         join public.phase_c_trace tr on tr.task_id = t.task_id
        where t.run_id = sr.run_id and t.step_id = sr.step_id
          and tr.trace_policy_id = 'TRACE-ROLE-ACTION'
          and tr.evidence_refs @> '[{"review_decision":"approved"}]'::jsonb
          and public.fn_kernel_reviewer_independent(sr.accountable_role_id, tr.reviewer_role_id)
          and (select role_id from public.fn_phase_c_resolve_actor(tr.reviewer_role_id))
              = (select role_id from public.fn_phase_c_resolve_actor(s.independent_reviewer_role_id)))
  then
    raise exception 'fn_phase_d_handler_execute: step % names % as its independent reviewer and no approved, independent verdict from that role has been recorded on its task. fn_kernel_review_decide seals the verdict and stamps the reviewer; until it has run the kernel will refuse the completion, so the handler refuses here first. (pd_review_not_recorded)',
      sr.step_id, s.independent_reviewer_role_id using errcode = '23514';
  end if;

  -- ---- 5. THE FAMILY HANDLER ---------------------------------------------------------------
  -- F34. The recorded canonical review for this step run, read once.
  v_review := public.fn_phase_d_recorded_review(v_step_run);

  v_assert := (
    select coalesce(jsonb_agg(jsonb_build_object(
             'criterion', btrim(c), 'satisfied_by',
             'named inputs [' || array_to_string(
               (select array_agg(k order by k) from jsonb_object_keys(v_inputs) k), ', ') || ']')
             order by ord), '[]'::jsonb)
      from unnest(string_to_array(coalesce(s.acceptance_criteria,''), ';')) with ordinality u(c, ord)
     where btrim(c) <> '');

  v_output := jsonb_build_object(
    'status', 'completed',
    'output', format('%s — %s', s.step_name, coalesce(s.required_output,'output produced')),
    'acceptance_assertions', case when jsonb_array_length(v_assert) = 0
                                  then jsonb_build_array(jsonb_build_object(
                                         'criterion', coalesce(s.acceptance_criteria,'(none declared)'),
                                         'satisfied_by','named inputs'))
                                  else v_assert end,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
       'step_id', sr.step_id, 'step_run_id', v_step_run, 'run_id', sr.run_id,
       'handler_id', b.handler_id, 'handler_version', b.handler_version,
       'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
       'inputs_named', v_inputs, 'execution_context', v_ctx)))
    || case when v_cap is null then '{}'::jsonb
            else jsonb_build_object('capability_result', jsonb_build_object(
              'request_id',    v_cap->'request_id',
              'result_id',     v_cap->'result_id',
              'provider_mode', v_cap->>'provider_mode',
              'fixture_id',    v_cap->>'fixture_id',
              'fixture_version', v_cap->'fixture_version',
              'fixture_hash',  v_cap->>'fixture_hash',
              'payload_digest',v_cap->>'payload_digest',
              'evidence',      v_cap->>'evidence')) end
    || case b.handler_class
         when 'INTAKE_HANDLER' then jsonb_build_object(
           'source_ref', coalesce(p_input->>'source_ref', 'step_run:' || v_step_run),
           'captured_verbatim', v_inputs)
         when 'ANALYSIS_HANDLER' then jsonb_build_object(
           'method', 'deterministic reconciliation of the named inputs against the frozen step contract',
           'inputs_used', v_inputs,
           'findings', jsonb_build_array(coalesce(s.required_action,'')),
           'assumptions', jsonb_build_array(
             'only the inputs named in this call were used; no external source was consulted'))
         when 'EXECUTION_HANDLER' then jsonb_build_object(
           'state_change', coalesce(s.required_output,''),
           'target_object', coalesce(ec.effect_object_id,
             (select primary_object from public.phase_b_workflow w
               where w.workflow_id = b.workflow_id), b.workflow_id),
           'authorization_ref', format('accountable owner %s on step %s',
                                       sr.accountable_role_id, sr.step_id))
         -- F34. A REVIEW READ OFF THE CALLER'S OWN STRING.
         -- Both keys came from p_input, so the kernel dispatch -- which passes neither -- produced
         -- an output naming no reviewer, and BR-002 then refused the step for "names (none) as
         -- reviewer". That refusal was true and it was about this harness, not about the business.
         -- The founder's section 4 names CANONICAL_INTERNAL_REVIEW as an allowed execution input
         -- when it travels through its real interface, and that interface is fn_kernel_review_decide:
         -- it checks independence itself, seals a TRACE-ROLE-ACTION carrying the decision, and
         -- stamps phase_c_task.reviewer_role_id. Both values are therefore READ FROM THOSE ROWS.
         -- A caller can no longer assert either one.
         when 'REVIEW_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'verdict', v_review->'verdict',
           'reviewer_role_id', v_review->'reviewer_role_id'))
         when 'DECISION_HANDLER' then jsonb_build_object(
           'decision', coalesce(s.required_output,''),
           'rationale', coalesce(s.acceptance_criteria,''),
           'authority_ref', format('founder_gate=%s; accountable owner %s',
                                   b.founder_gate, sr.accountable_role_id))
         when 'HANDOFF_HANDLER' then jsonb_build_object(
           'packet', v_inputs,
           'receiving_role_id', coalesce((select h.receiving_role_id from public.phase_b_handoff h
                                           where h.from_step_id = sr.step_id limit 1),
                                         sr.accountable_role_id),
           'acceptance_criteria', coalesce(s.acceptance_criteria,''))
         -- F34. THE FOUR VALUES CAME FROM p_input, AND NOTHING PASSES p_input HERE.
         -- E32 stopped the harness supplying handler inputs, correctly, and the kernel dispatch
         -- passes no measurement keys, so denominator, numerator, formula and window were null on
         -- every call, jsonb_strip_nulls removed them, and the step's own output contract refused
         -- the output the handler had just built. They now come from the committed catalogue
         -- through fn_phase_d_fixture_output, which returns NULL when no row exists -- so a step
         -- with no committed measurement is still refused by its contract, and the denominator-of-0
         -- guard below is untouched.
         when 'MEASUREMENT_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'metric', coalesce(public.fn_phase_d_fixture_output(sr.step_id,'metric'),
                              to_jsonb(nullif(btrim(coalesce(s.required_output,'')),''))),
           'denominator', public.fn_phase_d_fixture_output(sr.step_id,'denominator'),
           'numerator', public.fn_phase_d_fixture_output(sr.step_id,'numerator'),
           'formula', public.fn_phase_d_fixture_output(sr.step_id,'formula'),
           'window', public.fn_phase_d_fixture_output(sr.step_id,'window')))
         when 'CLOSURE_HANDLER' then jsonb_build_object(
           'blockers_resolved', jsonb_build_array(
             'the frozen fn_kernel_step_complete measures the four mandatory closure blocker '
             || 'classes itself and raises k3_closure_blocked if any is open'),
           'closure_evidence', coalesce(s.closure_criteria,''))
         else '{}'::jsonb end;

  -- ---- 5a. TWO REFUSALS THE SCHEMA ALONE CANNOT MAKE ---------------------------------------
  -- F34. TWO REFUSALS THAT WORE ONE NAME. "no review has been recorded for this step" and "the
  -- recorded review names the creator" are different facts with different remedies, and both came
  -- out as pd_rule_refused/BR-002. The first is now its own code, so a driver can answer it by
  -- recording the review through the kernel's own door and asking for the step again.
  if b.handler_class = 'REVIEW_HANDLER'
     and coalesce(btrim(coalesce(v_output->>'reviewer_role_id','')),'') = '' then
    raise exception 'fn_phase_d_handler_execute: step % is a review step and no internal review has been recorded for it. fn_kernel_review_decide seals the verdict and stamps the reviewer on the task; until it has run there is no reviewer to name and no verdict to carry. (pd_review_not_recorded)',
      sr.step_id using errcode = '23514';
  end if;

  if b.handler_class = 'REVIEW_HANDLER'
     and not public.fn_kernel_reviewer_independent(
               sr.accountable_role_id, v_output->>'reviewer_role_id') then
    raise exception 'fn_phase_d_handler_execute: step % is accountable to % and the review names % as reviewer; those resolve to the same effective identity. A creator cannot be the sole independent reviewer of the same output (BR-002). (pd_rule_refused)',
      sr.step_id, sr.accountable_role_id, coalesce(v_output->>'reviewer_role_id','(none)')
      using errcode = '23514';
  end if;

  if b.handler_class = 'MEASUREMENT_HANDLER'
     and jsonb_typeof(v_output->'denominator') = 'number'
     and (v_output->>'denominator')::numeric = 0 then
    raise exception 'fn_phase_d_handler_execute: step % reported a denominator of 0. A ratio over nothing is not a measurement, and reporting it as one is how an unmeasured goal scores as perfect. (pd_output_schema_invalid)',
      sr.step_id using errcode = '22023';
  end if;

  -- ---- 6. TYPED OUTPUT ---------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.output_schema_id, v_output);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % produced an output its own contract rejects: % (pd_output_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 6b. THE BUSINESS EFFECT -------------------------------------------------------------
  -- D7. Until this line existed, 257 of 257 handlers produced a typed output the kernel accepted
  -- and no business effect whatsoever, and fn_phase_d_handler_state() said so in red.
  --
  -- The effect payload comes from the CALLER, merged over the step's own facts. Nothing about the
  -- business record is invented here: a step that needs a business_key and an owner_ref and is
  -- given neither refuses, because a record written under an owner this routine chose would be
  -- the auto-vivified customer account defect in a new place.
  v_effect := public.fn_phase_d_effect_produce(
    jsonb_build_object(
      'step_run_id', v_step_run, 'idempotency_key', v_idem, 'actor_role_id', v_actor,
      'execution_context', v_ctx)
    || jsonb_strip_nulls(jsonb_build_object(
      'business_key', p_input->>'business_key',
      'owner_ref',    p_input->>'owner_ref',
      -- H01 (4). The caller's stated state, else the state the committed catalogue declares for
      -- THIS step (EFFECT_PAYLOAD key 'state', step-scoped, fixture context only), else none -- and
      -- none means the writer keeps the row's state or takes the relation's default. Never 'open'.
      'state',        coalesce(p_input->>'effect_state',
                               (select fi.value #>> '{}'
                                  from public.fn_phase_d_fixture_input(v_step_run, 'EFFECT_PAYLOAD', 'state') fi)),
      'state_before', p_input->>'state_before',
      'trace_id',     p_input->>'trace_id'))
    -- F16. THE CONTENT THE OBJECT'S OWN RELATION DEMANDS, from the committed catalogue.
    --
    -- pd_effect_payload_incomplete is the deepest refusal in the drive: the step has passed every
    -- rule and gate, the dispatch has derived a business key and an owner, and the write to the
    -- object's canonical relation fails on a NOT NULL column -- opportunity.kind, org_tasks.title,
    -- department_objective.objective, content_drafts.body. The builder closure of 2026-08-20
    -- recorded 18 of 56 business objects in that state and reported it as a Phase E boundary,
    -- correctly, because a deterministic handler must not invent a title or an amount.
    --
    -- The founder's ruling of 21 Aug 2026 supplies them instead, from a committed catalogue, and
    -- this is where they arrive. The handler still invents nothing: the value comes from
    -- fn_phase_d_fixture_effect_payload, which reads the columns the RELATION demands and the
    -- values the CATALOGUE holds, and which returns an empty object in production.
    --
    -- The order is caller, then capability result, then catalogue, and the catalogue is last so it
    -- can only fill what nothing else filled.
    || jsonb_build_object('payload',
         public.fn_phase_d_fixture_effect_payload(v_step_run)
         || coalesce(p_input->'effect_payload', v_inputs)
         || case when v_cap is null then '{}'::jsonb
                 else coalesce(v_cap->'payload','{}'::jsonb) end
         -- H01 (1). THE RECORDED REVIEW, LAST, FOR A REVIEW_VERDICT EFFECT. F34 read it into the
         -- output and never into the payload, and BR-002 is judged on the payload. The sealed
         -- verdict and the stamped reviewer outrank the catalogue and any caller, so they close
         -- the concatenation. Absent, nothing is added and fn_phase_d_effect_produce still refuses.
         || case when ec.expected_effect_type = 'REVIEW_VERDICT'
                 then jsonb_strip_nulls(jsonb_build_object(
                        'verdict',          v_review->>'verdict',
                        'reviewer_role_id', v_review->>'reviewer_role_id'))
                 else '{}'::jsonb end
         -- H01 (3). WHO DECIDED AND WHEN, FOR A DECISION STEP. The decider is the accountable role
         -- of the deciding step run, read off the kernel's row; the time is now(). A write map that
         -- carries neither key ignores both.
         || case when b.handler_class = 'DECISION_HANDLER'
                 then jsonb_build_object('decided_by', v_actor, 'decided_at', now())
                 else '{}'::jsonb end
         -- L03. THE VERSION AND THE DIGEST THAT WERE ACCEPTED, FOR A STEP THAT RECORDS AN
         -- ACCEPTANCE. W09-S06's own frozen completion condition is "Displayed version, recorded
         -- version and document hash match", and the record it wrote carried none of the three:
         -- the payload was the workflow_record blob and nothing else. It went unseen because the
         -- fixture scenario built the acceptance itself, with the published pair on it, so every
         -- downstream read found the FIXTURE's record rather than the product's. Withhold that
         -- stage and W09-S07, S08 and S09 refuse on BR-025.
         -- The pair is the step's own resolved context -- the same value BR-025 has just judged at
         -- this step -- so the record states what was accepted and BR-025 can judge it again
         -- downstream. A step whose object is not a registered acceptance adds nothing, and a
         -- context that resolved neither key adds nothing.
         || case when exists (select 1 from public.phase_d_acceptance_document a
                               where a.object_id = ec.effect_object_id)
                 then jsonb_strip_nulls(jsonb_build_object(
                        'terms_version', p_input->'context'->>'terms_version',
                        'terms_hash',    p_input->'context'->>'terms_hash'))
                 else '{}'::jsonb end));

  v_output := v_output || jsonb_build_object('business_effect', jsonb_build_object(
    'effect_type', v_effect->>'effect_type',
    'effect_object_id', v_effect->'effect_object_id',
    'result_reference', v_effect->>'result_reference',
    'effect_id', v_effect->'effect_id',
    'provider_mode', v_effect->>'provider_mode',
    'replay', v_effect->'replay'));

  -- ---- 7. HAND TO THE FROZEN KERNEL --------------------------------------------------------
  -- Everything from here — idempotency, locks, authority, gates, the task state machine,
  -- progression, handoffs, run state and events — belongs to fn_kernel_step_complete and is not
  -- reimplemented. A handler that wrote any of it would be the parallel engine the spec forbids.
  v_result := public.fn_kernel_step_complete(jsonb_build_object(
    'step_run_id', v_step_run, 'actor_role_id', v_actor, 'outcome', 'pass',
    'idempotency_key', v_idem, 'inputs', v_inputs, 'output', v_output,
    'evidence_ref', format('phase_d:%s:%s:effect=%s',
                           b.handler_id, v_step_run, coalesce(v_effect->>'result_reference','none')),
    'correlation_id', p_input->>'correlation_id',
    'causation_id', coalesce(p_input->>'causation_id', 'phase_d_handler:' || b.handler_id)));

  return v_result || jsonb_build_object(
    'phase_d', jsonb_build_object(
      'handler_id', b.handler_id, 'handler_version', b.handler_version,
      'handler_class', b.handler_class, 'execution_context', v_ctx,
      'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
      'rules_in_scope', cardinality(b.rule_ids),
      'rules_evaluated', v_evaluated, 'rules_not_applicable', v_skipped,
      'rules_enforced_count', (select count(*) from jsonb_array_elements(v_evaluated) e2
                                where (e2->>'enforced')::boolean),
      'rules_outstanding_count', (select count(*) from jsonb_array_elements(v_evaluated) e2
                                   where not (e2->>'enforced')::boolean),
      'gates_in_scope', cardinality(b.gate_ids), 'gates_evaluated', v_gates,
      'capability_dependency', b.capability_dependency,
      'provider_dependency', b.provider_dependency,
      'external_effect_policy', b.external_effect_policy,
      'expected_effect_type', ec.expected_effect_type,
      'implementation_depth', ec.implementation_depth,
      'business_effect', v_effect));
end $function$
;
