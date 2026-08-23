-- K02 — the parent a nullable column did not demand, and the assignment that had no inquiry
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. W12-S06 "Create idempotent supplier assignments"
-- was one of the three steps of the 257 producing no declared effect:
--
--   pd_object_write_produced_nothing :: the write to public.inquiry_matches for supplier_assignment
--   returned no key. Refusing to report a write that produced nothing.
--
-- THE HAND-OVER'S DIAGNOSIS WAS WRONG AND THE MEASUREMENT SAYS SO. It recorded the cause as "the
-- fixture inquiry is not rfq_ready". Driven inside one aborted transaction on 23 Aug 2026, with
-- for_workflow W12, the fixture inquiry scores 100, generic_ready true, category_required_ok true,
-- rfq_ready TRUE, status quote_ready; the supplier is not banned, not matching-blocked, not
-- permanently closed and has no expired licence; public.unsafe_block gained no row; and the same
-- insert issued by hand in the same transaction landed a row and returned its id.
--
-- WHAT ACTUALLY HAPPENED. public.phase_d_object_write builds its statement from the write map and
-- SKIPS any mapped column whose source key the payload does not carry. The map for
-- supplier_assignment is
--
--   {"inquiry_id":"inquiry_id","similarity":"similarity","supplier_id":"owner_ref","match_reason":"match_reason"}
--
-- and the payload carried owner_ref and nothing else, so the statement issued was
-- `insert into public.inquiry_matches (supplier_id) values (...)` -- an assignment with NO INQUIRY.
-- public.inquiry_matches carries BEFORE INSERT trigger gate_incomplete_match, which reads
-- `select rfq_ready from public.inquiries where id = NEW.inquiry_id`; NEW.inquiry_id was null, the
-- read found no row, ready came back null, and the trigger returned null. The gate was right to
-- refuse an orphan and the writer was right to refuse a write that produced nothing. The defect is
-- upstream of both: nothing supplied the parent.
--
-- WHY NOTHING SUPPLIED IT. public.fn_phase_d_fixture_effect_payload fills "the columns the target
-- relation actually DEMANDS" -- NOT NULL, no default, not generated -- plus any column the
-- committed catalogue speaks for. public.inquiry_matches.inquiry_id is NULLABLE, so it demands
-- nothing, so the parent was never in the population. A filter that can never select the thing that
-- matters.
--
-- THE FIX IS THE OBJECT'S OWN DECLARED PARENT, and it is derived, not listed.
-- public.phase_d_business_object_binding.parent_identity already names it for every object that has
-- one -- inquiry_id for supplier_assignment, transaction_id for invoice_receipt, quote_id for
-- payment_transaction. Where the write map maps a column of that name and the payload does not
-- carry its source key, fn_phase_d_effect_produce asks fn_phase_d_step_context for it. The context
-- resolves an identity from the row it names; a parent is never taken from a fixture constant,
-- because an identity is never a fixture. This runs in production exactly as it runs under a
-- fixture context: a parent is structural, not fixture content.
--
-- AND THE WRITER NOW REFUSES AN ORPHAN BY NAME. Where the declared parent is still unresolved the
-- write stops with pd_object_parent_missing instead of issuing a statement whose only possible
-- outcomes are a silent skip or a foreign-key error two layers down. Five objects have a mapped
-- parent identity on a nullable column -- department_mandate, inquiry, payment_transaction,
-- quotation, supplier_assignment -- and this is the guard for all five.
--
-- THE ELIGIBILITY EVIDENCE AND THE INCLUSION REASON are the remaining two mapped columns,
-- similarity and match_reason. A deterministic handler must not invent either, so they arrive the
-- way the founder's ruling of 21 Aug 2026 provides for: two rows of the committed fixture
-- catalogue, scoped to W12-S06, marked PHASE_D_FIXTURE_DO_NOT_PUBLISH, returning {} in production.
--
-- ROLLBACK: scripts/sql/down/phase_d_k02_the_parent_a_nullable_column_did_not_demand_down.sql
-- re-applies the previous bodies of fn_phase_d_effect_produce and fn_phase_d_object_write and
-- deletes the two catalogue rows.
--
-- GENERATED from the live bodies by scripts/tmp_diag/gen_k02.mjs.
CREATE OR REPLACE FUNCTION public.fn_phase_d_effect_produce(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  e            public.phase_d_step_effect%rowtype;
  sr           public.phase_c_workflow_step_run%rowtype;
  prior        public.phase_d_effect_ledger%rowtype;
  v_step_run   bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_idem       text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_actor      text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_payload    jsonb  := coalesce(p_input->'payload','{}'::jsonb);
  v_key        text   := nullif(btrim(coalesce(p_input->>'business_key','')),'');
  v_owner      text   := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
  v_state      text   := nullif(btrim(coalesce(p_input->>'state','')),'');
  v_ctx        text   := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_write      jsonb;
  v_result_ref text;
  v_relation   text;
  v_mode       text := 'none';
  v_eid        bigint;
  v_num        numeric; v_den numeric;
  v_cap        jsonb;   -- F05: the accepted capability result for this step run, or null
  v_parent_col text;    -- K02: the parent identity the object's binding declares
  v_parent_src text;    -- K02: the payload key the write map reads it from
  v_parent_val jsonb;   -- K02: what the step context resolves for it
begin
  if v_step_run is null or v_idem is null or v_actor is null then
    raise exception 'fn_phase_d_effect_produce: step_run_id, idempotency_key and actor_role_id are all required (pd_effect_input_invalid)'
      using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_effect_produce: no step run % (pd_step_state_invalid)', v_step_run
      using errcode = '23503';
  end if;

  select * into e from public.phase_d_step_effect where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_effect_produce: step % has no declared effect contract — fail closed. All 257 frozen steps carry one. (pd_effect_undeclared)',
      sr.step_id using errcode = '23503';
  end if;

  -- ---- IDEMPOTENCY IS A READ, NOT A HOPE -------------------------------------------------
  -- A replayed handler must produce NO second effect. The assertion a duplicate-effect test makes
  -- is the ledger ROW COUNT, not the returned payload, so the check is done here and the prior
  -- row is returned verbatim.
  select * into prior from public.phase_d_effect_ledger
   where step_run_id = v_step_run and effect_type = e.expected_effect_type;
  if found then
    return jsonb_build_object(
      'ok', true, 'replay', true, 'effect_id', prior.effect_id,
      'effect_type', prior.effect_type, 'effect_object_id', prior.effect_object_id,
      'result_reference', prior.result_reference, 'provider_mode', prior.provider_mode,
      'note', 'the effect for this step run already exists; no second effect was produced');
  end if;

  -- ---- K02. THE PARENT THE OBJECT DECLARES -------------------------------------------------
  -- public.phase_d_object_write skips a mapped column whose source key the payload does not carry,
  -- and fn_phase_d_fixture_effect_payload only fills columns the RELATION demands. A parent column
  -- that is nullable demands nothing, so supplier_assignment was written with no inquiry_id and a
  -- BEFORE trigger dropped the row. The object's own binding already names its parent; that is read
  -- here, and the value comes from the step context, which resolves an identity from the row it
  -- names. Nothing is invented and no constant is used: an identity is never a fixture.
  select bb.parent_identity, wm.column_map->>bb.parent_identity
    into v_parent_col, v_parent_src
    from public.phase_d_business_object_binding bb
    join public.phase_d_object_write_map wm on wm.object_id = bb.object_id
   where bb.object_id = e.effect_object_id
     and coalesce(btrim(bb.parent_identity),'') <> ''
     and wm.column_map ? bb.parent_identity;
  if v_parent_src is not null
     and v_parent_src not in ('business_key','owner_ref','state')
     and (not (v_payload ? v_parent_src) or v_payload->v_parent_src = 'null'::jsonb) then
    v_parent_val := (public.fn_phase_d_step_context(v_step_run))->'context'->v_parent_src;
    if v_parent_val is not null and v_parent_val <> 'null'::jsonb then
      v_payload := v_payload || jsonb_build_object(v_parent_src, v_parent_val);
    end if;
  end if;

  -- ---- the seven types -------------------------------------------------------------------
  if e.expected_effect_type = 'KERNEL_ONLY_TRANSITION' then
    -- Nothing is written here beyond the ledger entry. The effect IS the kernel's step run and
    -- run-state move, which is persistent and kernel-verifiable; a domain row invented to make a
    -- count look better would be a fabricated effect.
    v_result_ref := format('public.phase_c_workflow_step_run:step_run_id=%s', v_step_run);
    v_relation   := 'public.phase_c_workflow_step_run';

  elsif e.expected_effect_type = 'CAPABILITY_REQUEST' then
    -- Fail closed in production, and record the refusal as the effect. A capability step whose
    -- effect was a success record would be a mock completing a business step.
    -- F05. This read `if v_ctx <> 'test' then raise`, which is the bypass the founder prohibited
    -- seen from the effect side: the string 'test' turned the refusal into a record. The subject
    -- is now the same one the handler asks about -- is there an ACCEPTED capability result for
    -- this step run? The declared effect of a capability step IS the request; what the result
    -- adds is the answer it can point at, and its provider_mode is recorded rather than assumed.
    v_cap := public.fn_phase_d_capability_answer(v_step_run);
    if v_cap is null then
      raise exception 'fn_phase_d_effect_produce: step % is capability-dependent and its capability request carries no accepted result. The declared effect is a refusal, not a record. No execution context lifts this. (pd_capability_unavailable)',
        sr.step_id using errcode = '23514';
    end if;
    v_result_ref := format('capability_request:%s:result=%s:mode=%s:digest=%s',
                           v_cap->>'request_id', v_cap->>'result_id', v_cap->>'provider_mode',
                           left(coalesce(v_cap->>'payload_digest',''), 12));
    v_relation   := 'public.phase_d_capability_result';
    v_mode       := v_cap->>'provider_mode';

  elsif e.expected_effect_type = 'EXTERNAL_EFFECT_INTENT' then
    -- MOCK, ALWAYS. provider_mode has no 'live' value, so this cannot be turned into a send by
    -- changing a parameter. A recipient and a consent basis are REQUIRED and are not defaulted:
    -- an intent that cannot say who it is for is not an intent.
    if not (v_payload ? 'recipient') or not (v_payload ? 'consent_basis') then
      raise exception 'fn_phase_d_effect_produce: step % declares an external effect and the payload names no %. An intent with no recipient or no consent basis must not be recorded as one. (pd_effect_intent_incomplete)',
        sr.step_id,
        case when not (v_payload ? 'recipient') then 'recipient' else 'consent_basis' end
        using errcode = '22023';
    end if;
    if coalesce(v_payload->>'suppressed','false') = 'true' then
      v_result_ref := format('external_intent:SUPPRESSED:%s', v_payload->>'recipient');
    else
      v_result_ref := format('external_intent:MOCK:%s', v_payload->>'recipient');
    end if;
    v_relation := 'public.phase_d_effect_ledger';
    v_mode     := 'mock';

  elsif e.expected_effect_type = 'MEASUREMENT_RECORD' then
    -- least(100, NULL) returns 100 and put 97.7% attainment in the founder's email on a
    -- zero-revenue day. Nothing is defaulted, and a zero denominator raises.
    if not (v_payload ? 'numerator') or not (v_payload ? 'denominator') then
      raise exception 'fn_phase_d_effect_produce: step % is a measurement step and the payload names no %. An absent input must not score as satisfied. (pd_effect_measurement_incomplete)',
        sr.step_id,
        case when not (v_payload ? 'numerator') then 'numerator' else 'denominator' end
        using errcode = '22023';
    end if;
    v_num := (v_payload->>'numerator')::numeric;
    v_den := (v_payload->>'denominator')::numeric;
    if v_den = 0 then
      raise exception 'fn_phase_d_effect_produce: step % reported a denominator of 0. A ratio over nothing is not a measurement. (pd_effect_zero_denominator)',
        sr.step_id using errcode = '22023';
    end if;
    v_result_ref := format('measurement:%s/%s', v_num, v_den);
    v_relation   := 'public.phase_d_effect_ledger';

  elsif e.expected_effect_type = 'REVIEW_VERDICT' then
    -- The verdict is the caller's. An absent one is a refusal, not an approval: a review handler
    -- that supplied its own verdict would make all 47 review steps a rubber stamp.
    if not (v_payload ? 'verdict') or nullif(btrim(v_payload->>'verdict'),'') is null then
      raise exception 'fn_phase_d_effect_produce: step % is a review step and the payload names no verdict. This routine does not have one to give. (pd_effect_verdict_absent)',
        sr.step_id using errcode = '22023';
    end if;
    if not public.fn_kernel_reviewer_independent(
             sr.accountable_role_id, nullif(btrim(v_payload->>'reviewer_role_id'),'')) then
      raise exception 'fn_phase_d_effect_produce: step % is accountable to % and names % as reviewer; those resolve to one effective identity (BR-002). (pd_rule_refused)',
        sr.step_id, sr.accountable_role_id, coalesce(v_payload->>'reviewer_role_id','(none)')
        using errcode = '23514';
    end if;
    -- H10. review_chain demands subject_type, subject_id, author_agent and stage. The caller's
    -- payload wins where it names them; otherwise each is the fact the run already holds -- what is
    -- under review, its identity, and who reviewed it -- never invented. dept_key comes from the
    -- owner_ref derivation, which resolves a real department for a COMPANY-scoped write.
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','review_record',
      'business_key', coalesce(v_key, format('%s:%s', sr.step_id, v_step_run)),
      'owner_ref', coalesce(v_owner, sr.accountable_role_id),
      'created_by', v_actor,
      'state', coalesce(v_state, v_payload->>'verdict'),
      'payload', jsonb_build_object(
        'subject_type', e.effect_object_id,
        'subject_id',   coalesce(v_key, format('%s:%s', sr.step_id, v_step_run)),
        'author_agent', v_actor,
        'stage',        sr.step_id,
        'notes',        coalesce(v_payload->>'notes', 'phase_d review verdict'))
        || v_payload));
    v_result_ref := v_write->>'result_reference';
    v_relation   := v_write->>'canonical_relation';

  else
    -- DOMAIN_MUTATION and VERSIONED_ARTIFACT: the object's own canonical service.
    if v_key is null or v_owner is null then
      raise exception 'fn_phase_d_effect_produce: step % writes business object % and the call names no %. (pd_effect_owner_or_key_missing)',
        sr.step_id, e.effect_object_id,
        case when v_key is null then 'business_key' else 'owner_ref' end
        using errcode = '22023';
    end if;
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id', e.effect_object_id, 'business_key', v_key, 'owner_ref', v_owner,
      'created_by', v_actor, 'state', v_state, 'payload', v_payload,
      'run_id', sr.run_id, 'step_run_id', v_step_run, 'trace_id', p_input->>'trace_id'));
    v_result_ref := v_write->>'result_reference';
    v_relation   := coalesce(v_write->>'canonical_relation', e.effect_relation);
  end if;

  insert into public.phase_d_effect_ledger
    (step_run_id, step_id, workflow_id, run_id, effect_type, effect_object_id, effect_relation,
     effect_operation, result_reference, state_before, state_after, provider_mode,
     payload_digest, idempotency_key, produced_by, trace_id)
  values (v_step_run, sr.step_id, e.workflow_id, sr.run_id, e.expected_effect_type,
          e.effect_object_id, v_relation, e.effect_operation, v_result_ref,
          nullif(p_input->>'state_before',''), v_state, v_mode,
          encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'), v_idem, v_actor,
          nullif(p_input->>'trace_id','')::bigint)
  returning effect_id into v_eid;

  if v_eid is null then
    raise exception 'fn_phase_d_effect_produce: the ledger insert for step run % returned no effect_id. (pd_effect_produced_nothing)',
      v_step_run using errcode = '23502';
  end if;

  return jsonb_build_object(
    'ok', true, 'replay', false, 'effect_id', v_eid,
    'effect_type', e.expected_effect_type, 'effect_object_id', e.effect_object_id,
    'effect_relation', v_relation, 'effect_operation', e.effect_operation,
    'result_reference', v_result_ref, 'provider_mode', v_mode,
    'completion_condition', e.completion_condition,
    'object_write', v_write);
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_phase_d_object_write(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  b            public.phase_d_business_object_binding%rowtype;
  wm           public.phase_d_object_write_map%rowtype;
  v_object     text  := nullif(btrim(coalesce(p_input->>'object_id','')),'');
  v_key        text  := nullif(btrim(coalesce(p_input->>'business_key','')),'');
  v_owner_ref  text  := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
  v_payload    jsonb := p_input->'payload';
  v_actor      text  := nullif(btrim(coalesce(p_input->>'created_by','')),'');
  v_state      text  := coalesce(nullif(btrim(p_input->>'state'),''), 'open');
  v_state_given text := nullif(btrim(p_input->>'state'),'');   -- H02: what the caller actually said
  v_unchanged  boolean := false;                               -- H02: a confirmation, not a write
  v_prior      public.phase_d_object_record%rowtype;
  v_version    integer := 1;
  v_id         bigint;
  v_readback   public.phase_d_object_record%rowtype;
  v_cols       text[] := '{}';
  v_vals       text[] := '{}';
  v_sets       text[] := '{}';
  v_col        record;
  v_expr       text;
  v_existing   text;
  v_result_ref text;
  v_sql        text;
  v_supplied   jsonb;
  -- D17: the outbound door.
  v_testctx    boolean := public.fn_phase_d_fixture_context() is not null;
  v_door       record;
  v_door_val   jsonb;
  v_net_max    bigint;
  v_net_new    bigint;
  v_net_urls   text;
  -- K02: the parent the object declares.
  v_parent_src text;
  -- D18: identity resolution for UPSERT_STATE.
  v_ident_val  text;
  v_uq         record;
  v_where      text;
begin
  if v_object is null or v_key is null or v_actor is null then
    raise exception 'fn_phase_d_object_write: object_id, business_key and created_by are all required (got %, %, %) (pd_object_input_invalid)',
      coalesce(v_object,'(null)'), coalesce(v_key,'(null)'), coalesce(v_actor,'(null)')
      using errcode = '22023';
  end if;

  select * into b from public.phase_d_business_object_binding where object_id = v_object;
  if not found then
    raise exception 'fn_phase_d_object_write: % is not a bound Phase D business object — fail closed rather than store a record under a policy nobody declared (pd_object_unbound)',
      v_object using errcode = '23503';
  end if;

  if v_payload is null or jsonb_typeof(v_payload) <> 'object' or v_payload = '{}'::jsonb then
    raise exception 'fn_phase_d_object_write: % sent payload of type %. An empty object is not evidence that anything was recorded. (pd_object_payload_empty)',
      v_object, coalesce(jsonb_typeof(v_payload),'null') using errcode = '22023';
  end if;

  if v_owner_ref is null then
    raise exception 'fn_phase_d_object_write: % is %-scoped and the call names no owner_ref. An unowned business record is the accountability gap this map exists to close. (pd_object_owner_missing)',
      v_object, b.ownership_scope using errcode = '22023';
  end if;

  -- ================= EXISTING TABLE: a real write, through the declared map =================
  if b.relation_kind = 'EXISTING_TABLE' then
    -- THE KERNEL'S OWN TABLES ARE NOT WRITABLE FROM HERE, AND THIS IS THE POINT OF THE BRANCH.
    -- workflow_run, workflow_step_run and handoff_record are created and moved by
    -- fn_kernel_step_complete. Two creators for one object is what deadlocked 16 of 30 workflows
    -- when workflow_start and step_complete both made the same handoff run; it is not repeated
    -- here because a handler asked politely.
    if b.governing_workflow_id = 'ALL' and v_object <> 'review_record' then
      raise exception 'fn_phase_d_object_write: % is written by the frozen kernel (%). A Phase D handler that wrote it would be a second creator for one object. Use fn_kernel_step_complete. (pd_object_kernel_owned)',
        v_object, b.canonical_relation using errcode = '23514';
    end if;

    select * into wm from public.phase_d_object_write_map where object_id = v_object;
    if not found then
      raise exception 'fn_phase_d_object_write: % is bound to existing relation % and no write map is declared for it. Refusing to guess a column layout. (pd_object_no_write_map)',
        v_object, b.canonical_relation using errcode = '23503';
    end if;

    -- The payload the caller actually sent, plus the four facts every write carries. state and
    -- owner_ref are named here so a map can point a column at either without the caller repeating
    -- them; nothing else is defaulted.
    -- H02 (1). NO STATE THE CALLER DID NOT STATE. An insert takes the relation's default and an
    -- update leaves the column alone; a stated state for a relation whose map carries no state
    -- column is refused rather than dropped on the floor.
    -- H09. A stated state the map cannot carry is reported on the return, not refused: review_record
    -- carries its verdict as content and has never had a state column.
    v_supplied := v_payload
                  || jsonb_build_object('owner_ref', v_owner_ref, 'business_key', v_key)
                  || case when v_state_given is null then '{}'::jsonb
                          else jsonb_build_object('state', v_state_given) end;

    -- D17. OUTBOUND SUPPRESSION, IN TEST CONTEXT ONLY, THROUGH EACH TRIGGER'S OWN GUARD.
    -- In production this loop does not run: a real Phase D handler dispatching a real inquiry is
    -- the intended behaviour and must not be suppressed. Under the Phase D hold the writer sets
    -- the product's own already-done marker, and a caller that supplied one keeps it.
    if v_testctx then
      for v_door in
        select d.guard_column, d.suppression_sql
          from public.phase_d_outbound_door d
         where d.relation = wm.target_relation
           and d.disposition = 'SUPPRESSED_BY_ITS_OWN_GUARD'
      loop
        -- D19. THE SUPPRESSION IS NOT DEFEASIBLE BY THE CALLER.
        --
        -- This was `if not (v_supplied ? guard_column)` — respect a value the caller supplied.
        -- Adding `routing` to the inquiry write map in D17 made the DRIVER's payload builder start
        -- generating a value for it, because it invents a typed value for every declared column.
        -- The generated jsonb carried no dispatched_at, the injection stood aside for it, and
        -- W05-S01 POSTed dispatch_inquiry again. A harness that generates a value for the key the
        -- guard reads is the same defect D9 recorded as "a generated fixture beat the real
        -- reference", and here it silently re-armed a door the writer had just closed.
        --
        -- Under the Phase D hold a caller does not get to opt out, so the writer overwrites. Both
        -- registered guard columns were measured as read by nothing: 0 rules, 0 gate contracts,
        -- 0 references in fn_rfq_score / fn_rfq_required_check. Overwriting them changes no
        -- decision any workflow makes; leaving them writable changes whether a POST leaves the
        -- database.
        execute format('select %s', v_door.suppression_sql) into v_door_val;
        v_supplied := v_supplied || jsonb_build_object(v_door.guard_column, v_door_val);
      end loop;
    end if;

    -- K02. AN ORPHAN IS REFUSED BY NAME. Where the object's binding declares a parent identity,
    -- the write map maps a column of that name, and this call supplies no value for it, the row
    -- about to be written belongs to nothing. Issuing it can only end in a silent BEFORE-trigger
    -- skip -- which is exactly how W12-S06 lost its effect -- or a foreign-key error two layers
    -- down. A NOT NULL column is left to the relation's own 23502; this covers the nullable ones,
    -- which is where the hole was.
    select wm.column_map->>b.parent_identity into v_parent_src
      from pg_attribute a
     where a.attrelid = wm.target_relation::regclass
       and a.attname = b.parent_identity and a.attnum > 0 and not a.attnotnull
       and coalesce(btrim(b.parent_identity),'') <> ''
       and wm.column_map ? b.parent_identity;
    if v_parent_src is not null
       and v_parent_src not in ('business_key','owner_ref','state')
       and (not (v_supplied ? v_parent_src) or v_supplied->v_parent_src = 'null'::jsonb) then
      raise exception 'fn_phase_d_object_write: % declares parent identity %, the write map reads it from payload key %, and this call supplies none. A % row that belongs to no % is not a business record. (pd_object_parent_missing)',
        v_object, b.parent_identity, v_parent_src, wm.target_relation, b.parent_identity
        using errcode = '23502';
    end if;

    for v_col in
      select k.key as col, wm.column_map->>k.key as src,
             format_type(a.atttypid, a.atttypmod) as ftype,
             (select typcategory from pg_type ty where ty.oid = a.atttypid) as tcat,
             a.attidentity, a.attgenerated
        from jsonb_each(wm.column_map) k
        join pg_attribute a
          on a.attrelid = wm.target_relation::regclass and a.attname = k.key and a.attnum > 0
       order by k.key
    loop
      -- A GENERATED ALWAYS identity or generated column cannot be written. The map validator
      -- excludes them from "required"; this excludes them from the statement.
      if v_col.attidentity = 'a' or v_col.attgenerated <> '' then continue; end if;
      if not (v_supplied ? v_col.src) then continue; end if;

      v_expr := case
        when v_col.ftype = 'jsonb' or v_col.ftype = 'json' then
          format('($1->%L)', v_col.src)
        when v_col.tcat = 'A' then
          format('(select coalesce(array_agg(x::text),''{}'')::%s from jsonb_array_elements_text($1->%L) x)',
                 v_col.ftype, v_col.src)
        else
          format('($1->>%L)::%s', v_col.src, v_col.ftype)
      end;
      v_cols := v_cols || quote_ident(v_col.col);
      v_vals := v_vals || v_expr;
      if v_col.col <> wm.key_column then
        v_sets := v_sets || format('%I = %s', v_col.col, v_expr);
      end if;
    end loop;

    if cardinality(v_cols) = 0 then
      raise exception 'fn_phase_d_object_write: % supplied no column the write map for % can use. Payload keys were %. (pd_object_payload_unmapped)',
        v_object, wm.target_relation,
        coalesce((select string_agg(k,', ' order by k) from jsonb_object_keys(v_supplied) k),'(none)')
        using errcode = '22023';
    end if;

    -- D17. The high-water mark, taken immediately before the write. Counting rows with a HIGHER id
    -- afterwards rather than differencing two counts is deliberate: pg_net's worker DELETES rows it
    -- has processed, so a plain count delta can be masked to zero by a concurrent drain and report
    -- silence over two real POSTs.
    if v_testctx then
      select coalesce(max(id),0) into v_net_max from net.http_request_queue;
    end if;

    if wm.operation = 'UPSERT_STATE' then
      -- D18. AN UPSERT MUST LOOK FOR THE ROW IT WOULD WRITE, NOT FOR A DIFFERENT ONE.
      --
      -- This probe used to be `where key_column::text = business_key` unconditionally, which is
      -- only correct when the map points key_column at business_key. Two shapes broke on it:
      --
      --   supplier_capability  key_column = supplier_id, column_map.supplier_id = 'owner_ref'
      --                        -> probed supplier_id = <business key>, INSERTED supplier_id =
      --                           <owner ref>. It read one value and wrote another, so it could
      --                           never find its own row and the second write died on the pkey.
      --
      --   quotation / payment_transaction   key_column = id, a generated bigint
      --                        -> probed a bigint id against a uuid business key, never matched,
      --                           always inserted, and collided on the relation's NATURAL key
      --                           (quotes(inquiry_id,supplier_id), transactions(quote_id)).
      --
      -- Identity is now resolved in two derived passes and nothing is hand-listed:
      --   1. key_column, using THE VALUE THAT WILL BE WRITTEN INTO IT.
      --   2. failing that, any other unique index on the relation whose columns are ALL declared
      --      in the map and ALL supplied by this call — the row's natural key. The index's own
      --      predicate is carried through verbatim from pg_get_expr, so a PARTIAL unique index
      --      such as transactions(quote_id) WHERE quote_id IS NOT NULL is matched on exactly the
      --      rows it actually constrains rather than on a guess about what the predicate means.
      --
      -- Where neither pass resolves an identity the write stays an INSERT and a unique violation
      -- remains a real business duplicate. That is reported by fn_phase_d_object_identity_state()
      -- rather than papered over.
      v_existing := null;

      if wm.column_map ? wm.key_column then
        v_ident_val := v_supplied->>(wm.column_map->>wm.key_column);
        if v_ident_val is not null then
          v_sql := format('select %I::text from %s where %I::text = $1 limit 1',
                          wm.key_column, wm.target_relation, wm.key_column);
          execute v_sql into v_existing using v_ident_val;
        end if;
      end if;

      -- H02 (2). THE CALLER'S KEY IS THE RELATION'S KEY when the map writes no key column: probe it
      -- as text, which matches nothing when the shapes differ and the row when they do not.
      if v_existing is null and not (wm.column_map ? wm.key_column) then
        begin
          v_sql := format('select %I::text from %s where %I::text = $1 limit 1',
                          wm.key_column, wm.target_relation, wm.key_column);
          execute v_sql into v_existing using v_key;
        exception when others then
          v_existing := null;
        end;
      end if;

      if v_existing is null then
        for v_uq in
          select ic.relname as idx_name,
                 array_agg(a.attname::text order by a.attnum) as cols,
                 min(pg_get_expr(i.indpred, i.indrelid)) as pred
            from pg_index i
            join pg_class ic on ic.oid = i.indexrelid
            join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
           where i.indrelid = wm.target_relation::regclass
             and i.indisunique
           group by ic.relname, i.indexrelid
           order by ic.relname
        loop
          -- an index on exactly the key column is pass 1's job, and it already ran
          continue when v_uq.cols = array[wm.key_column];
          continue when not (select bool_and(wm.column_map ? c) from unnest(v_uq.cols) c);
          continue when not (select bool_and(v_supplied ? (wm.column_map->>c)) from unnest(v_uq.cols) c);
          continue when exists (select 1 from unnest(v_uq.cols) c
                                 where v_supplied->>(wm.column_map->>c) is null);

          select string_agg(format('%I::text = ($1->>%L)', c, wm.column_map->>c), ' and ')
            into v_where from unnest(v_uq.cols) c;
          if v_uq.pred is not null then
            v_where := v_where || ' and (' || v_uq.pred || ')';
          end if;

          v_sql := format('select %I::text from %s where %s limit 1',
                          wm.key_column, wm.target_relation, v_where);
          execute v_sql into v_existing using v_supplied;
          exit when v_existing is not null;
        end loop;
      end if;
      if v_existing is not null then
        if cardinality(v_sets) = 0 then
          -- H02 (3). The row already carries everything this call asked for. That is the declared
          -- completion condition of an OBJECT_STATE_WRITE met, not a transition refused: the
          -- existing reference is returned, nothing is written, and unchanged = true says so.
          v_unchanged := true;
          v_result_ref := v_existing;
        end if;
        -- D18. Update the row the probe actually FOUND. Re-deriving the target from business_key
        -- here would reintroduce the same mismatch one statement later: the natural-key probe can
        -- resolve a row whose key_column value equals neither the business key nor anything in the
        -- payload.
        if not v_unchanged then
          v_sql := format('update %s set %s where %I::text = $2 returning %I::text',
                          wm.target_relation, array_to_string(v_sets, ', '),
                          wm.key_column, wm.key_column);
          execute v_sql into v_result_ref using v_supplied, v_existing;
        end if;
      else
        v_sql := format('insert into %s (%s) values (%s) returning %I::text',
                        wm.target_relation, array_to_string(v_cols, ', '),
                        array_to_string(v_vals, ', '), wm.key_column);
        execute v_sql into v_result_ref using v_supplied;
      end if;
    else
      v_sql := format('insert into %s (%s) values (%s) returning %I::text',
                      wm.target_relation, array_to_string(v_cols, ', '),
                      array_to_string(v_vals, ', '), wm.key_column);
      execute v_sql into v_result_ref using v_supplied;
    end if;

    -- A NULL RETURN IS NOT A WRITE. A BEFORE trigger returning NULL gives a statement that
    -- "succeeded" with no row; the returned key is what separates the two.
    if v_result_ref is null then
      raise exception 'fn_phase_d_object_write: the write to % for % returned no key. Refusing to report a write that produced nothing. (pd_object_write_produced_nothing)',
        wm.target_relation, v_object using errcode = '23502';
    end if;

    -- D17. THE ASSERTION. A Phase D test write may not leave an outbound request behind it.
    if v_testctx then
      -- WHOSE REQUEST IS IT. This counted every row above an id watermark, so a request enqueued
      -- by ANY concurrent transaction was attributed to this write. Measured 23 Aug 2026: the
      -- step-coverage drive failed with "writing inquiry to public.inquiries enqueued 2 outbound
      -- HTTP request(s): POST .../dropbox_backup, POST .../uptime_check" -- and neither came from
      -- the write. cron.job 88 (dropbox_backup_scan) and 35 (uptime_check_15min) both run
      -- */15 * * * *, they commit while a Phase D transaction is open, and READ COMMITTED then
      -- shows their rows to the next statement here. A drive that fails four times an hour, on the
      -- quarter hour, because a scheduled job ran is an instrument reporting on the wrong subject.
      -- The requests are attributed to this transaction now; see the helper for how.
      select r.n, r.urls into v_net_new, v_net_urls
        from public.fn_phase_d_outbound_requests_by_this_transaction(v_net_max) r;
      if coalesce(v_net_new,0) > 0 then
        raise exception 'fn_phase_d_object_write: writing % to % enqueued % outbound HTTP request(s): %. A Phase D test write may not leave an outbound request behind it. (pd_object_outbound_request_produced)',
          v_object, wm.target_relation, v_net_new, v_net_urls using errcode = '23514',
          hint = 'A trigger on this relation calls net.http_post. Register it in public.phase_d_outbound_door with the product''s own already-done guard column, or explain why the request is legitimate under the hold.';
      end if;
    end if;

    return jsonb_build_object(
      'ok', true, 'object_id', v_object, 'relation_kind', 'EXISTING_TABLE',
      'canonical_relation', wm.target_relation, 'operation', wm.operation,
      'result_reference', format('%s:%s=%s', wm.target_relation, wm.key_column, v_result_ref),
      -- F44. THE CANONICAL REFERENCE, RETURNED BY THE WRITER ITSELF.
      -- Which identity is canonical for this object is a property of the object, recorded once in
      -- public.phase_d_object_reference_strategy and derived from the frozen 56-object map. For an
      -- EXISTING_TABLE object it is the relation's own primary key -- the value this write just
      -- produced -- and every caller downstream now takes it from here rather than choosing.
      'canonical_ref', public.fn_phase_d_ref(jsonb_build_object(
                         'object_id', v_object, 'identity', v_result_ref,
                         'owner_ref', v_owner_ref)),
      'business_key', v_key, 'state', v_state_given,
      'policy_family', b.policy_family, 'record_policy', b.record_policy,
      'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
      'columns_written', case when v_unchanged then '[]'::jsonb else to_jsonb(v_cols) end,
      'unchanged', v_unchanged,
      'state_carried_by_relation', (v_state_given is null
         or exists (select 1 from jsonb_each_text(wm.column_map) k where k.value = 'state')),
      'outbound_requests_enqueued', coalesce(v_net_new, 0),
      'quarantine_note', wm.quarantine_note,
      'payload_digest', encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'));
  end if;

  -- ================= PHASE D STORE: unchanged behaviour from D2 =================
  select * into v_prior from public.phase_d_object_record
   where object_id = v_object and business_key = v_key and superseded_by is null
   order by version desc limit 1;

  if found then
    if b.policy_family = 'APPEND_ONLY' then
      raise exception 'fn_phase_d_object_write: % is APPEND_ONLY (%) and business key % already holds record %. A correction is a NEW key, never a second version of this one. (pd_object_append_only)',
        v_object, b.record_policy, v_key, v_prior.record_id using errcode = '23514';
    end if;
    -- D27. "MOVE ITS STATE" — AND THE WRITER OFFERED NO WAY TO MOVE IT.
    --
    -- This refusal told the caller to move the record's state instead of writing a second, and then
    -- returned before anything could. In the store branch it governs exactly ONE object:
    --
    --     dispatch_batch   PHASE_D_OBJECT_VIEW   TRANSACTION_RECORD
    --
    -- payment_transaction, reveal_transaction and supplier_assignment are the other three
    -- TRANSACTION_RECORDs and all three are EXISTING_TABLE, so they never reach this branch — their
    -- second write is an UPSERT_STATE that moves the row, which is exactly what this text asks for.
    --
    -- And the frozen registry writes dispatch_batch at FIVE successive steps of W12:
    --     S01 Accept dispatch-ready package        INTAKE_HANDLER
    --     S02 Build eligible supplier pool         ANALYSIS_HANDLER
    --     S03 Apply fairness and capacity policy   ANALYSIS_HANDLER
    --     S04 Review policy exception if needed    REVIEW_HANDLER
    --     S08 Record selection and exclusion evidence  EXECUTION_HANDLER
    --
    -- A batch that is accepted, then built, then policy-applied, then reviewed, then evidenced. Five
    -- writes to one identity is the DESIGN, so a rule refusing the second could never be satisfied
    -- by the workflow that owns the object. That is a misclassification meeting a missing mechanism,
    -- not a business constraint doing its job.
    --
    -- ONE RECORD PER IDENTITY IS PRESERVED, and that is the part that must not be lost. The move is
    -- a superseding version, the same mechanism VERSIONED, IMMUTABLE_REVISION, CASE_RECORD and
    -- MUTABLE_CONTROLLED already use: the prior row is retained and marked superseded, so after five
    -- writes there is exactly ONE current record and four retained predecessors. Nothing is
    -- overwritten in place, which matters because Phase B's frozen mutation_rule for this object is
    -- "immutable selection evidence" — history is evidence.
    --
    -- THE REFUSAL IS KEPT, NARROWED TO WHAT IT CAN ACTUALLY MEAN: a repeat that moves nothing. The
    -- EXISTING_TABLE branch already refuses on exactly that ground — "a write that changes nothing
    -- is not a state transition" — so the two branches now agree about one family instead of giving
    -- it opposite answers. record_policy is FROZEN Phase B and is untouched; policy_family is Phase
    -- D's own fold and is also untouched. Only the writer's behaviour changes.
    if b.policy_family = 'TRANSACTION_RECORD'
       and v_prior.state is not distinct from v_state
       and v_prior.payload = v_payload then
      raise exception 'fn_phase_d_object_write: % is a %-family record and business key % already exists as record % with the same state and payload. One record per identity; move its state, do not write a second. (pd_object_duplicate_identity)',
        v_object, b.policy_family, v_key, v_prior.record_id using errcode = '23505';
    end if;
    v_version := v_prior.version + 1;
  end if;

  insert into public.phase_d_object_record
    (object_id, business_key, version, state, owner_scope, owner_ref, payload,
     run_id, step_run_id, trace_id, created_by)
  values (v_object, v_key, v_version, v_state, b.ownership_scope, v_owner_ref, v_payload,
          nullif(p_input->>'run_id','')::bigint, nullif(p_input->>'step_run_id','')::bigint,
          nullif(p_input->>'trace_id','')::bigint, v_actor)
  returning record_id into v_id;

  if v_id is null then
    raise exception 'fn_phase_d_object_write: the insert for % / % returned no record_id. Refusing to report a write that produced nothing. (pd_object_write_produced_nothing)',
      v_object, v_key using errcode = '23502';
  end if;
  select * into v_readback from public.phase_d_object_record where record_id = v_id;
  if not found then
    raise exception 'fn_phase_d_object_write: record % is not readable back in the same transaction. (pd_object_write_not_readable)',
      v_id using errcode = '23502';
  end if;

  if v_prior.record_id is not null
     -- D27. TRANSACTION_RECORD joins the supersede list so that "one record per identity" stays
     -- literally true: the prior version is retained and marked superseded, never left as a second
     -- live record alongside the new one.
     and b.policy_family in ('VERSIONED','IMMUTABLE_REVISION','CASE_RECORD','MUTABLE_CONTROLLED','TRANSACTION_RECORD') then
    update public.phase_d_object_record
       set superseded_by = v_id, superseded_at = now()
     where record_id = v_prior.record_id;
  end if;

  return jsonb_build_object(
    'ok', true, 'object_id', v_object, 'relation_kind', 'PHASE_D_OBJECT_VIEW',
    'record_id', v_id, 'business_key', v_key,
    'result_reference', format('public.phase_d_object_record:record_id=%s', v_id),
    -- F44. For a PHASE_D_STORE object the canonical identity is object_id + business_key + version.
    -- record_id stays in the envelope as the physical detail it is, never as the identity.
    'canonical_ref', public.fn_phase_d_ref(jsonb_build_object(
                       'object_id', v_object, 'identity', v_key,
                       'version', v_version::text, 'owner_ref', v_owner_ref)),
    'version', v_version, 'state', v_readback.state,
    'policy_family', b.policy_family, 'record_policy', b.record_policy,
    'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
    'canonical_relation', b.canonical_relation,
    'superseded_record_id', v_prior.record_id,
    'payload_digest', encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'));
end $function$
;

-- The eligibility evidence and the inclusion reason W12-S06's effect must carry. Scoped to the
-- step, so nothing else in the estate can be filled by them. The checksum column is computed by
-- a10_phase_d_fixture_catalogue_checksum and is never supplied here.
insert into public.phase_d_fixture_catalogue
  (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind,
   expected_schema, expected_result, prohibited_external_use, marker_exemption)
values
  ('PDF-5001', 1, 'W12', 'W12-S06', 'EFFECT_PAYLOAD', 'match_reason',
   to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH — included by deterministic capability match on the routed trade; no supplier was contacted'::text),
   'text',
   'free text; public.inquiry_matches.match_reason is the inclusion reason BR-016 and GATE-015 read',
   'the supplier-assignment effect records WHY this supplier was included instead of leaving the column null',
   'Never send to a supplier. The assignment is created inside a transaction that is aborted.',
   null),
  ('PDF-5002', 1, 'W12', 'W12-S06', 'EFFECT_PAYLOAD', 'similarity',
   to_jsonb(0.90::numeric),
   'number',
   'numeric 0..1; public.inquiry_matches.similarity is the eligibility evidence the assignment carries',
   'the supplier-assignment effect records the match strength it was created on',
   'Never quote to a supplier or a customer as a real match score.',
   'similarity is numeric; a text marker cannot be stored in it and the value is scoped to one fixture step.')
on conflict (fixture_id) do update
  set fixture_version = excluded.fixture_version, workflow_id = excluded.workflow_id, step_id = excluded.step_id, scope = excluded.scope,
      field_key = excluded.field_key, value = excluded.value, value_kind = excluded.value_kind,
      expected_schema = excluded.expected_schema, expected_result = excluded.expected_result,
      prohibited_external_use = excluded.prohibited_external_use,
      marker_exemption = excluded.marker_exemption;
