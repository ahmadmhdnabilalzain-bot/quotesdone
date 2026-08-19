-- =================================================================================================
-- Phase D — D27. "Move its state", said the refusal that offered no way to move it.
--
-- The last workflow. W12 stopped at S02 with pd_object_duplicate_identity, whose text reads
-- "One record per identity; move its state, do not write a second" — and the branch it lives in
-- returned before anything could move.
--
-- MEASURED, not reasoned about: in the Phase D store branch that refusal governs exactly ONE object.
--
--   object              relation_kind          steps writing it   max in one workflow
--   dispatch_batch      PHASE_D_OBJECT_VIEW    5                  5
--   payment_transaction EXISTING_TABLE         3                  3
--   supplier_assignment EXISTING_TABLE         2                  2
--   reveal_transaction  EXISTING_TABLE         0                  -
--
-- The other three are EXISTING_TABLE and never reach it; their second write is an UPSERT_STATE that
-- moves the row, which is exactly what the refusal asks for. So the rule applied to dispatch_batch
-- alone, and the FROZEN registry writes dispatch_batch at five successive steps of W12: accept the
-- package, build the pool, apply fairness policy, review the exception, record selection evidence.
--
-- Five writes to one identity is the design. A rule refusing the second could never be satisfied by
-- the workflow that owns the object.
--
-- WHAT IS NOT CHANGED. record_policy is frozen Phase B (idempotent_case) and is untouched.
-- policy_family is Phase Ds own fold and is also untouched — reclassifying an object to make a
-- test pass is the move this session has refused all the way through. Only the WRITER changes.
--
-- WHAT IS PRESERVED. One record per identity, literally: the move is a superseding version, the
-- same mechanism the four movable families already use. After five writes there is exactly ONE
-- current record and four retained, superseded predecessors. Nothing is overwritten in place, which
-- matters because Phase Bs frozen mutation_rule here is "immutable selection evidence" — history
-- IS the evidence.
--
-- WHAT IS KEPT. The refusal, narrowed to the only thing it can honestly mean: a repeat that moves
-- nothing. The EXISTING_TABLE branch already refuses on exactly that ground — "a write that changes
-- nothing is not a state transition" — so the two branches now give one family the same answer
-- instead of opposite ones. A control below proves the narrowed refusal still fires.
-- =================================================================================================

begin;

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
  v_testctx    boolean := coalesce(nullif(btrim(current_setting('app.phase_d_test_context', true)),''),'') = 'on';
  v_door       record;
  v_door_val   jsonb;
  v_net_max    bigint;
  v_net_new    bigint;
  v_net_urls   text;
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
    v_supplied := v_payload
                  || jsonb_build_object('state', v_state, 'owner_ref', v_owner_ref,
                                        'business_key', v_key);

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
          raise exception 'fn_phase_d_object_write: % exists as % and the payload moves no column. A write that changes nothing is not a state transition. (pd_object_no_state_change)',
            v_object, v_existing using errcode = '22023';
        end if;
        -- D18. Update the row the probe actually FOUND. Re-deriving the target from business_key
        -- here would reintroduce the same mismatch one statement later: the natural-key probe can
        -- resolve a row whose key_column value equals neither the business key nor anything in the
        -- payload.
        v_sql := format('update %s set %s where %I::text = $2 returning %I::text',
                        wm.target_relation, array_to_string(v_sets, ', '),
                        wm.key_column, wm.key_column);
        execute v_sql into v_result_ref using v_supplied, v_existing;
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
      select count(*), string_agg(distinct q.method || ' ' || q.url, ', ')
        into v_net_new, v_net_urls
        from net.http_request_queue q
       where q.id > v_net_max;
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
      'business_key', v_key, 'state', v_state,
      'policy_family', b.policy_family, 'record_policy', b.record_policy,
      'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
      'columns_written', to_jsonb(v_cols),
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
    'version', v_version, 'state', v_readback.state,
    'policy_family', b.policy_family, 'record_policy', b.record_policy,
    'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
    'canonical_relation', b.canonical_relation,
    'superseded_record_id', v_prior.record_id,
    'payload_digest', encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'));
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_phase_d_drive_workflow(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  w        public.phase_b_workflow%rowtype;
  sr       public.phase_c_workflow_step_run%rowtype;
  e        public.phase_d_step_effect%rowtype;
  b        public.phase_d_handler_binding%rowtype;
  wm       public.phase_d_object_write_map%rowtype;
  v_wf     text := nullif(btrim(coalesce(p_input->>'workflow_id','')),'');
  v_ctx    text := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'test'));
  v_max    int  := coalesce(nullif(p_input->>'max_steps','')::int, 40);
  v_label  text := coalesce(nullif(btrim(p_input->>'label'),''), 'phase-d-drive');
  v_owner  text := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
  v_verdict text := nullif(btrim(coalesce(p_input->>'verdict','')),'');
  -- THE REVIEWER IS A RUNTIME FACT FOR 45 OF THE 47 REVIEW STEPS. Measured on the frozen registry:
  -- 47 steps are step_type='review' and 45 of them name no independent_reviewer_role_id, so there is
  -- no reviewer to read for all but two. The executor is right to refuse — fn_kernel_reviewer_
  -- independent(owner, NULL) is false and BR-002 blocks — and the identity has to come from whoever
  -- is driving. It is taken from the CALLER and never chosen here: a driver that picked a reviewer
  -- would be fn_pick_reviewer returning the department head 182 times, one layer up. Independence is
  -- still decided by the kernel, not by this parameter.
  v_caller_reviewer text := nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'');
  v_parents jsonb := coalesce(p_input->'parent_refs','{}'::jsonb);
  v_extra   jsonb := coalesce(p_input->'context','{}'::jsonb);
  v_run    bigint;
  v_start  jsonb;
  v_steps  jsonb := '[]'::jsonb;
  v_i      int := 0;
  v_res    jsonb;
  v_inputs jsonb;
  v_eff    jsonb;
  v_fix    jsonb;
  v_key    text;
  v_keys   jsonb := '{}'::jsonb;
  v_col    record;
  v_err    text; v_sqlstate text; v_code text;
  v_run_state text;
  v_scope_owner text;
  v_contrib text;
  v_contrib_kind text;    -- D20
  v_produced_rel text;    -- D21
  v_object_rel   text;    -- D21
  v_fk_rel       text;    -- D22
  v_fk_col       text;    -- D22
  v_fk_owner     text;    -- D22
  v_decl_state text;
  v_working_state text;   -- D20
  v_working_payload jsonb; -- D23
  v_decision_payload jsonb; -- D26
  v_prov_payload jsonb;     -- D27
  v_dec_role text;          -- D26
  v_cands text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(p_input->'reviewer_candidates') x), '{}'::text[]);
  hr       public.phase_c_handoff_run%rowtype;
  hc       public.phase_d_handoff_contract%rowtype;
  v_hoff   jsonb;
  v_hpk    jsonb;
  v_haccept int := 0;
  v_handoffs jsonb := '[]'::jsonb;
  v_prev   public.phase_c_workflow_step_run%rowtype;
  v_ledger int; v_before int; v_after int;
  v_reviewer text;
  v_task    bigint;
  v_decide  jsonb;
  v_declared_reviewer text;
begin
  if v_wf is null then
    raise exception 'fn_phase_d_drive_workflow: workflow_id is required' using errcode = '22023';
  end if;
  select * into w from public.phase_b_workflow where workflow_id = v_wf;
  if not found then
    raise exception 'fn_phase_d_drive_workflow: % is not a frozen workflow', v_wf using errcode = '23503';
  end if;

  select count(*) into v_before from public.phase_d_effect_ledger;

  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id', v_wf,
    'business_object_id', w.primary_object,
    'source_kind', 'autonomous',
    'source_ref', format('zz-phase-d-%s-%s', v_label, v_wf),
    'requested_by', w.accountable_role_id,
    'trigger_ctx', jsonb_build_object('driver','fn_phase_d_drive_workflow','fixture',true)));
  v_run := (v_start->>'run_id')::bigint;
  if v_run is null then
    return jsonb_build_object('ok', false, 'workflow_id', v_wf,
      'stopped_because', 'the kernel returned no run_id', 'kernel_result', v_start);
  end if;

  loop
    v_i := v_i + 1;
    exit when v_i > v_max;

    select * into sr from public.phase_c_workflow_step_run
     where run_id = v_run
       and state in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
     order by step_run_id
     limit 1;

    -- ---- NO OPEN STEP RUN IS NOT NECESSARILY A STOPPED RUN ---------------------------------------
    -- The kernel opens no successor until the receiving owner accepts the handoff. A run sitting in
    -- waiting_handoff has work to do and nobody has done it. Accept through the D9 contract path,
    -- which checks THIS handoff's own frozen packet and then lets the kernel move the state.
    if not found then
      select * into hr from public.phase_c_handoff_run
       where run_id = v_run and status = 'open'
       order by handoff_run_id limit 1;
      exit when not found;

      select * into hc from public.phase_d_handoff_contract where handoff_id = hr.handoff_id;
      exit when not found;

      select * into v_prev from public.phase_c_workflow_step_run
       where step_run_id = hr.from_step_run_id;

      -- Real facts where real facts exist; a fixture only for the clauses the frozen registry
      -- declares and nothing in this estate can supply.
      v_hpk := coalesce((select jsonb_object_agg(k, format('ZZ DEMO — %s for %s', k, hr.handoff_id))
                           from unnest(hc.packet_keys) k), '{}'::jsonb)
             || jsonb_build_object(
                  'business_object_id',
                    coalesce((select business_object_id from public.phase_c_workflow_run
                               where run_id = v_run), w.primary_object),
                  'object_version', coalesce(hr.object_version, 1),
                  'output', coalesce(v_prev.output_hash, 'no output hash recorded on the sending step run'),
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
          'handoff_run_id', hr.handoff_run_id,
          'actor_role_id',  hc.receiving_role_id,
          'packet',         v_hpk,
          'idempotency_key', format('%s:%s:%s', v_label, hr.handoff_id, hr.handoff_run_id)));
        v_haccept := v_haccept + 1;
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', v_hoff->'ok', 'replay', v_hoff->'replay',
          'to_step_id', v_hoff->>'to_step_id',
          'accountable_before', v_hoff->>'accountable_before',
          'accountable_after',  v_hoff->>'accountable_after',
          'sla_policy_id', v_hoff->>'sla_policy_id',
          'sla_breached', v_hoff->'sla_breached'));
        continue;
      exception when others then
        v_sqlstate := SQLSTATE; v_err := SQLERRM;
        v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
        v_handoffs := v_handoffs || jsonb_build_array(jsonb_build_object(
          'handoff_id', hr.handoff_id, 'handoff_run_id', hr.handoff_run_id,
          'ok', false, 'refused_with', v_code, 'sqlstate', v_sqlstate,
          'reason', left(v_err, 400)));
        -- STOP. A driver that skipped a refused handoff and carried on would report a closure the
        -- workflow never reached, exactly as it would for a refused step.
        exit;
      end;
    end if;

    select * into e from public.phase_d_step_effect where step_id = sr.step_id;
    select * into b from public.phase_d_handler_binding where step_id = sr.step_id;

    select coalesce(jsonb_object_agg(k, 'ZZ DEMO — ' || k || ' for ' || sr.step_id), '{}'::jsonb)
      into v_inputs
      from public.phase_d_handler_schema sc, unnest(sc.required_keys) k
     where sc.step_id = sr.step_id and sc.schema_kind = 'input';

    -- One source for every rule fact and gate fact the step declares it needs, typed per key.
    v_fix := public.fn_phase_d_fixture_context(sr.step_run_id, v_label);

    -- THE OWNER OF A CUSTOMER-SCOPED OBJECT IS A CUSTOMER, NOT A FRESH UUID. The write map points
    -- public.inquiries.customer_id at owner_ref, so a generated key reached a foreign key and W05
    -- died on inquiries_customer_id_fkey. The scope is read from the object's own binding — CUSTOMER
    -- takes customer_id, SUPPLIER takes supplier_id, COMPANY has no parent row and keeps the key.
    -- Nothing is defaulted: if the caller supplied no parent of that scope, this stays null and the
    -- previous behaviour and its refusal are unchanged.
    -- The first value the target's state CHECK admits, read from pg_constraint rather than
    -- assumed. Nothing is invented: a target with no CHECK yields null and the old default stands.
    -- D20. THE STATE AN OBJECT IS IN WHEN THE BUSINESS IS WORKING, read from the registry that
    -- the scenario factory builds its lineage from. Four of the five relations these workflows
    -- write carry NO state CHECK constraint — inquiries.status, documents.status, quotes.status
    -- and transactions.fee_status are all unconstrained text — so the CHECK-first heuristic below
    -- resolved null and every driven object was written 'open'. Five MEASURED gates then read the
    -- row back and correctly refused it:
    --     GATE-011 inquiries.status in (quote_ready, dispatched, quoted, completed)
    --     GATE-012 documents.status not in (error, quarantined, rejected)
    --     GATE-017 quotes.quote_amount is not null and status <> ''
    --     GATE-018 quote_comparisons ownership
    --     BR-020   transactions.fee_status must be a declared payment state
    -- Those gates were right every time. What was missing is that the driver never advanced the
    -- object; it created it open and asked a gate whether open was good enough.
    --
    -- working_state is taken in preference to the CHECK-first value because "the first literal in
    -- the constraint array" is an ordering accident, not a business state. Where a CHECK exists,
    -- a deploy control proves working_state is inside it, so this is narrower than what it
    -- replaces rather than looser.
    -- D23. A STATE CAN REQUIRE A COMPANION COLUMN, AND D20 SUPPLIED THE STATE WITHOUT IT.
    --
    -- D20 gave the driver working_state and W09 went 9/9 -> 1/9 on
    --     new row for relation "leads" violates check constraint "leads_approved_implies_verified"
    -- because public.leads carries CHECK (approval_status <> 'approved' OR verified = true). The
    -- driver had been writing 'open', which the constraint does not care about; the moment it
    -- started writing the real state it also owed the column that state implies. The scenario
    -- factory had always supplied verified=true — that is one of the four defects D9 recorded — so
    -- the fixture built a lineage the driver could not reproduce.
    --
    -- Caught by re-driving all 30 rather than the 9 this session had been iterating on. An
    -- increment measured only against the workflows it was aimed at will keep doing this.
    --
    -- working_payload is the minimum a stage needs alongside its state, declared as data next to
    -- working_state so the two cannot be moved apart, and merged UNDER the effect payload so a step
    -- that supplies its own value still wins.
    -- D26. A STEP WHOSE DECLARED JOB IS TO DECIDE MUST BE ABLE TO RECORD THAT IT DECIDED.
    --
    -- W17-S06 is "Decide case outcome", handler_class DECISION_HANDLER, effect object
    -- refund_dispute_case, accountable to trust_and_safety_manager, required_action "Approve,
    -- reject, escalate, partially resolve or request further evidence within authority." It runs and
    -- it PASSES. Then W17-S07 is refused by GATE-020, which reads
    --
    --     public.refunds.decided_by <> '' AND public.refunds.decided_at IS NOT NULL
    --
    -- and finds neither, because the refund_dispute_case write map declares no decision columns. The
    -- step that decides had nowhere to write its decision. That is the same shape D9 recorded as
    -- "an object that could not reach its own state" and D20 as the driver never advancing the
    -- object — not a founder-authorisation problem, which is what it had been read as.
    --
    -- THE FOUNDER GUARD IS NOT TOUCHED AND IS NOT CIRCUMVENTED. z00_refund_founder_decision_only
    -- fires only when status = 'approved' and then demands an active row in
    -- phase_c_founder_identity. Phase D writes the refund at its declared working_state,
    -- 'requested', and never at 'approved'. So the guard is never engaged, no founder identity is
    -- forged, and a deploy control below PROVES the guard still refuses a non-founder approval.
    --
    -- DERIVED, NOT LISTED. The rule is: a DECISION_HANDLER step whose target relation carries
    -- decided_by and decided_at records them, and the decider is that step's OWN frozen
    -- accountable_role_id — read from phase_b_workflow_step, never chosen here. 35 steps are
    -- DECISION_HANDLER and 32 name an object; only the relations that actually have the columns are
    -- written, which today is public.refunds alone.
    -- D27. EVERY EFFECT RECORDS WHICH STEP PRODUCED IT.
    --
    -- W12 writes dispatch_batch at five steps and the driver handed all five the same generic
    -- payload, so the narrowed pd_object_duplicate_identity refusal fired on the second: same
    -- state, same payload, nothing moved. It was right to fire. In reality S01 accepts a package
    -- and S02 builds a supplier pool -- they write different things -- and it is the HARNESS that
    -- had no way to tell them apart.
    --
    -- produced_by_step is provenance, not invented business data: it is the step id from the frozen
    -- registry, recording which step wrote which version. For an object whose frozen mutation_rule
    -- is "immutable selection evidence" that is precisely the evidence a reader needs.
    --
    -- It also keeps the refusal sharp where it matters. A genuine REPLAY -- the same step writing
    -- the same content twice -- still carries the same step id, so it is still refused. Only two
    -- DIFFERENT steps of a workflow can now both write one identity.
    v_prov_payload := jsonb_build_object('produced_by_step', sr.step_id);

    v_decision_payload := '{}'::jsonb;
    if e.effect_object_id is not null
       and exists (select 1 from public.phase_d_handler_binding hb
                    where hb.step_id = sr.step_id and hb.handler_class = 'DECISION_HANDLER')
       and exists (select 1 from public.phase_d_object_write_map wm4
                    join pg_attribute a1 on a1.attrelid = wm4.target_relation::regclass
                                        and a1.attname = 'decided_by' and a1.attnum > 0 and not a1.attisdropped
                    join pg_attribute a2 on a2.attrelid = wm4.target_relation::regclass
                                        and a2.attname = 'decided_at' and a2.attnum > 0 and not a2.attisdropped
                   where wm4.object_id = e.effect_object_id)
    then
      select x.accountable_role_id into v_dec_role
        from public.phase_b_workflow_step x where x.step_id = sr.step_id;
      if coalesce(btrim(v_dec_role),'') <> '' then
        v_decision_payload := jsonb_build_object(
          'decided_by', v_dec_role,
          'decided_at', to_jsonb(now()));
      end if;
    end if;

    v_working_state := null;
    v_working_payload := '{}'::jsonb;
    if e.effect_object_id is not null then
      select st3.working_state, coalesce(st3.working_payload, '{}'::jsonb)
        into v_working_state, v_working_payload
        from public.phase_d_fixture_stage st3
       where st3.object_id = e.effect_object_id;
    end if;

    v_decl_state := null;
    if e.effect_object_id is not null then
      select (regexp_match(pg_get_constraintdef(c.oid), '= ANY \(ARRAY\[''([^'']+)'''))[1]
        into v_decl_state
        from public.phase_d_object_write_map m
        join pg_constraint c on c.conrelid = m.target_relation::regclass and c.contype = 'c'
       where m.object_id = e.effect_object_id
         -- column_map is target_column -> payload_key, so the state column is the KEY whose VALUE
         -- is 'state'. Reading it the other way round finds nothing and silently defaults.
         and exists (select 1 from jsonb_each_text(m.column_map) kv
                      where kv.value = 'state'
                        and pg_get_constraintdef(c.oid) like '%(' || kv.key || ' =%')
         and pg_get_constraintdef(c.oid) like '%= ANY (ARRAY[%'
       limit 1;
    end if;

    v_scope_owner := null;
    if e.effect_object_id is not null then
      select case ob.ownership_scope
               when 'CUSTOMER' then nullif(btrim(coalesce(v_parents->>'customer_id','')),'')
               when 'SUPPLIER' then nullif(btrim(coalesce(v_parents->>'supplier_id','')),'')
               else null end
        into v_scope_owner
        from public.phase_d_business_object_binding ob
       where ob.object_id = e.effect_object_id;
    end if;

    -- D22. A COMPANY-SCOPED OWNER CAN STILL BE A FOREIGN KEY.
    --
    -- The scope resolution above covers CUSTOMER and SUPPLIER and returns null for COMPANY, on the
    -- reasoning that a company-scoped object "has no parent row and keeps the key". W01-S07 is the
    -- counter-example: initiative is COMPANY-scoped, its write map points org_tasks.dept_key at
    -- owner_ref, and dept_key is
    --     FOREIGN KEY (dept_key) REFERENCES org_departments(dept_key)
    -- so the generated key reached a foreign key and the step died on org_tasks_dept_key_fkey.
    -- Scope is about WHOSE the object is; a foreign key is about whether the value exists. They are
    -- different questions and only the first was being asked.
    --
    -- The owner is RESOLVED, never created. Phase A is frozen and holds 10 active departments; a
    -- fixture that created an eleventh to satisfy a foreign key would be inventing an organisation
    -- to pass a test. Where the referenced table carries an active flag the resolution prefers an
    -- active row, ordered by its key so the same run always resolves the same one. Where nothing
    -- resolves, this stays null and the previous behaviour and its refusal are unchanged.
    v_fk_owner := null;
    if e.effect_object_id is not null and v_scope_owner is null then
      v_fk_rel := null; v_fk_col := null;
      select kcu.column_name,
             'public.' || ccu.table_name || '.' || ccu.column_name
        into v_fk_col, v_fk_rel
        from public.phase_d_object_write_map wm2
        join jsonb_each_text(wm2.column_map) cm on cm.value = 'owner_ref'
        join information_schema.table_constraints tc
          on tc.table_schema = 'public'
         and tc.table_name = split_part(wm2.target_relation, '.', 2)
         and tc.constraint_type = 'FOREIGN KEY'
        join information_schema.key_column_usage kcu
          on kcu.constraint_name = tc.constraint_name and kcu.table_schema = 'public'
         and kcu.column_name = cm.key
        join information_schema.constraint_column_usage ccu
          on ccu.constraint_name = tc.constraint_name and ccu.table_schema = 'public'
       where wm2.object_id = e.effect_object_id
       limit 1;

      if v_fk_rel is not null then
        execute format(
          'select %I::text from %I.%I %s order by %I limit 1',
          split_part(v_fk_rel, '.', 3), 'public', split_part(v_fk_rel, '.', 2),
          case when exists (select 1 from pg_attribute a
                             where a.attrelid = ('public.' || split_part(v_fk_rel,'.',2))::regclass
                               and a.attname = 'active' and a.attnum > 0 and not a.attisdropped)
               then 'where active' else '' end,
          split_part(v_fk_rel, '.', 3))
          into v_fk_owner;
      end if;
    end if;

    -- THE BUSINESS KEY MUST BE THE TARGET'S KEY TYPE. public.customers.id is a uuid, and a label
    -- string reached it as one: "invalid input syntax for type uuid". A driver that hands a business
    -- key of the wrong type produces a type error where a business refusal belongs, and the two read
    -- nothing alike in a result table.
    select * into wm from public.phase_d_object_write_map where object_id = e.effect_object_id;
    if found and exists (
         select 1 from pg_attribute a
          where a.attrelid = wm.target_relation::regclass and a.attname = wm.key_column
            and format_type(a.atttypid, a.atttypmod) = 'uuid') then
      v_key := gen_random_uuid()::text;
    else
      -- D22. ONE KEY PER (RUN, OBJECT) IS RIGHT FOR EVERY FAMILY EXCEPT APPEND_ONLY.
      -- The comment below is correct and stays: W04 wrote two customer rows because the key
      -- carried the step id. But provider_event is APPEND_ONLY — its whole contract is that a
      -- correction is a NEW key, never a second version of this one — and W16-S03 and W16-S04
      -- both write it. Sharing one key made the second an INSERT onto an existing primary key
      -- and W16 died on stripe_events_pkey. The family decides, and it is read rather than
      -- assumed: the writer already refuses a second version of an APPEND_ONLY key by name.
      if exists (select 1 from public.phase_d_business_object_binding ob2
                  where ob2.object_id = e.effect_object_id
                    and ob2.policy_family = 'APPEND_ONLY') then
        v_key := format('zz-phase-d-%s-%s-%s-%s', v_label, e.effect_object_id, v_run, sr.step_id);
      else
        v_key := format('zz-phase-d-%s-%s-%s', v_label, e.effect_object_id, v_run);
      end if;
    end if;
    -- ONE BUSINESS KEY PER (RUN, OBJECT), NOT PER STEP. The first drive of W04 wrote TWO customer
    -- rows — one at S01 (create) and another at S03 (verify) — because the key carried the step id,
    -- so the second write found no existing row and inserted instead of moving the first one's
    -- state. A workflow that creates a fresh account at every step it touches is not onboarding a
    -- customer, and the ledger would have counted both as successful effects. Keys are remembered
    -- per object for the life of the run.
    -- D25. THE CACHE MUST NOT APPLY TO THE ONE FAMILY THAT MAY NOT BE MOVED.
    --
    -- D22 gave APPEND_ONLY objects a per-step business key and W16 still died on
    -- stripe_events_pkey. The key was computed correctly and THIS BLOCK threw it away one
    -- statement later: the cache remembers a key per object for the life of the run, so W16-S04
    -- was handed W16-S03's key and INSERTed onto it.
    --
    -- The cache is right and the comment above it is right — W04 wrote two customer rows without
    -- it. But its whole purpose is to make a second write MOVE THE FIRST ROW'S STATE, and an
    -- APPEND_ONLY object is defined by not doing that. fn_phase_d_object_write says so in its own
    -- refusal: "a correction is a NEW key, never a second version of this one". So the family that
    -- the cache exists to serve is precisely the family it must skip.
    --
    -- A fix that is computed and then discarded by code a few lines away is worth naming: D22's
    -- control asserted no regression on W16 rather than a number, which is the only reason this
    -- was not recorded as fixed.
    if exists (select 1 from public.phase_d_business_object_binding ob3
                where ob3.object_id = e.effect_object_id
                  and ob3.policy_family = 'APPEND_ONLY') then
      null;  -- each step appends its own row; nothing is remembered and nothing is moved
    elsif v_keys ? e.effect_object_id then
      v_key := v_keys->>e.effect_object_id;
    elsif e.effect_object_id is not null then
      v_keys := v_keys || jsonb_build_object(e.effect_object_id, v_key);
    end if;
    v_eff := '{}'::jsonb;

    -- THE REVIEWER IS RESOLVED FOR EVERY STEP, NOT ONLY FOR A REVIEW_VERDICT EFFECT.
    -- BR-002 is enforced on the STEP, and W17-S04 and W17-S05 are step_type='review' whose declared
    -- EFFECT is CAPABILITY_REQUEST. Resolving the reviewer inside the REVIEW_VERDICT branch meant
    -- those steps were asked for an independent reviewer and never given the chance to name one, so
    -- BR-002 refused them with 'the review names (none) as reviewer'. Same disagreement as W11-S01,
    -- one layer along: a fact keyed on the effect type while the rule is keyed on the step.
    v_reviewer := nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),'');
    if v_reviewer is null then
      v_reviewer := v_caller_reviewer;
      if v_reviewer is null
         or not public.fn_kernel_reviewer_independent(sr.accountable_role_id, v_reviewer) then
        select c into v_reviewer from unnest(v_cands) c
         where public.fn_kernel_reviewer_independent(sr.accountable_role_id, c) limit 1;
      end if;
    end if;
    v_task := null;
    v_decide := null;

    if e.expected_effect_type = 'MEASUREMENT_RECORD' then
      v_eff := jsonb_build_object('numerator', 1, 'denominator', 1,
                                  'formula', 'fixture', 'window', 'fixture');
    elsif e.expected_effect_type = 'EXTERNAL_EFFECT_INTENT' then
      v_eff := jsonb_build_object(
        'recipient', 'zz-phase-d-' || v_label || '@example.invalid',
        'consent_basis', 'fixture: no consent record is asserted and nothing is sent',
        'suppressed', false);
    elsif e.expected_effect_type = 'REVIEW_VERDICT' then
      -- WHERE THE FROZEN REGISTRY NAMES A REVIEWER, THAT ONE IS USED AND NOTHING IS CHOSEN.
      -- Where it does not — 45 of the 47 review steps — the CALLER's reviewer is offered, and if
      -- that one is not independent of this step's owner the caller's own candidate list is tried
      -- in order using the FROZEN kernel's independence test. The driver never invents an identity,
      -- never reads a department head, and the verdict is still the caller's; fn_kernel_review_decide
      -- and fn_phase_d_effect_produce both re-check independence afterwards.
      -- already resolved above, for every step
      v_eff := jsonb_strip_nulls(jsonb_build_object(
        'verdict', v_verdict, 'reviewer_role_id', v_reviewer,
        'subject_type', 'phase_d_step', 'subject_id', sr.step_id,
        'author_agent', sr.accountable_role_id, 'stage', sr.step_id,
        'notes', 'fixture review through fn_phase_d_drive_workflow'));
    elsif e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT') then
      if wm.object_id is not null then
        for v_col in
          select k.key as col, wm.column_map->>k.key as src,
                 format_type(a.atttypid, a.atttypmod) as ftype,
                 (select typcategory from pg_type ty where ty.oid = a.atttypid) as tcat
            from jsonb_each(wm.column_map) k
            join pg_attribute a
              on a.attrelid = wm.target_relation::regclass and a.attname = k.key and a.attnum > 0
           -- EVERY MAPPED COLUMN, not only the ones the table REQUIRES. public.customers has no
           -- NOT-NULL-without-default column at all, so the required-only filter produced an
           -- empty payload: the first write inserted on defaults and the second found the row,
           -- moved nothing, and hit pd_object_no_state_change. A step writes the fields it has,
           -- not only the fields it must. Identity and generated columns stay excluded because
           -- Postgres refuses a value for them.
           -- AND NEVER THE KEY COLUMN. Third instance of one lesson in one session: an identity is
           -- not a fixture. With every mapped column fixtured, the key column's source key —
           -- business_key — was regenerated at each step, so W04 created FOUR customer accounts
           -- for one onboarding and the ledger counted all four as successful effects. The key is
           -- remembered per (run, object) and the generator must not overwrite it.
           where a.attidentity = '' and a.attgenerated = '' and k.key <> wm.key_column
        loop
          if v_parents ? v_col.src then
            v_eff := v_eff || jsonb_build_object(v_col.src, v_parents->v_col.src);
          else
            -- THE LABEL CARRIES THE STEP, SO A LATER STEP GENUINELY MOVES THE RECORD. With one
            -- label for the whole run, every step produced byte-identical values and the second
            -- write hit pd_object_no_state_change — my own guard, firing correctly on a fixture
            -- that changed nothing. A real onboarding does move the record at each step; a fixture
            -- that does not is testing the guard, not the workflow.
            v_eff := v_eff || jsonb_build_object(v_col.src,
              public.fn_phase_d_fixture_for_column(wm.target_relation, v_col.col,
                                                   v_label || '-' || sr.step_id));
          end if;
        end loop;
      end if;
      v_eff := v_eff || v_parents;
      if v_eff = '{}'::jsonb then
        v_eff := jsonb_build_object('fixture', v_label);
      end if;
    end if;

    -- ---- A STEP THAT NAMES A REVIEWER NEEDS A RECORDED VERDICT FIRST -----------------------
    -- The frozen kernel refuses otherwise, and it says so precisely:
    --   "step W04-S04 names compliance_and_privacy_officer as its independent reviewer and no
    --    approved, independent verdict from that role exists on task 8409. Record it with
    --    fn_kernel_review_decide first."  (k3_reviewer_verdict_missing)
    -- So the driver records one, on the OPEN TASK for this step, naming the reviewer the FROZEN
    -- registry declares. fn_kernel_review_decide compares the offered reviewer against that
    -- registry through fn_phase_c_resolve_actor and returns not_the_declared_reviewer if they
    -- differ, so this cannot smuggle a reviewer past the freeze — it can only supply the one
    -- Phase B already named. The verdict itself is still the CALLER's; with none given, nothing is
    -- recorded and the kernel refuses, which is the correct behaviour and stays observable.
    v_declared_reviewer := nullif(btrim(coalesce(
      (select x.independent_reviewer_role_id from public.phase_b_workflow_step x
        where x.step_id = sr.step_id), '')), '');
    if v_declared_reviewer is not null and v_verdict is not null then
      select t.task_id into v_task from public.phase_c_task t
       where t.run_id = v_run and t.step_id = sr.step_id
       order by t.task_id desc limit 1;
      if v_task is not null then
        begin
          v_decide := public.fn_kernel_review_decide(jsonb_build_object(
            'task_id', v_task, 'reviewer_role_id', v_declared_reviewer,
            'decision', v_verdict,
            'reason', format('phase_d driver fixture verdict for %s', sr.step_id)));
        exception when others then
          -- Recorded, never swallowed: a verdict that could not be written is why the step will
          -- refuse a moment later, and a driver that hid it would make that refusal unexplainable.
          v_decide := jsonb_build_object('ok', false, 'error', left(SQLERRM, 240));
        end;
      end if;
    end if;

    begin
      v_res := public.fn_phase_d_handler_execute(
        jsonb_build_object(
          'step_run_id', sr.step_run_id,
          'actor_role_id', sr.accountable_role_id,
          'idempotency_key', format('%s:%s:%s', v_label, sr.step_id, sr.step_run_id),
          'inputs', v_inputs,
          'execution_context', v_ctx,
          -- A CALLER-SUPPLIED REAL REFERENCE WINS OVER A GENERATED FIXTURE. v_fix invents a
          -- typed value for every key the step DECLARES it needs; parent_refs carries the keys a
          -- scenario actually created. BR-013 reads an inquiry back out of public.inquiries, so
          -- 'ZZ DEMO — inquiry_id' is a refusal every time and the refusal says nothing about the
          -- step. Ordering is fixture, then reality, then per-call extras.
          'context', v_fix || v_parents || v_extra,
          -- The resolved reviewer must reach the GATE evidence too. GATE-021 and GATE-026 declare
          -- reviewer_role_id as required evidence and were refusing with 'the call names none of it'
          -- while the driver had one in hand. A gate asking for a fact the caller holds and never
          -- passes is the harness losing it, not the gate being strict.
          'gate_evidence', v_fix || v_parents
                           || jsonb_strip_nulls(jsonb_build_object('reviewer_role_id', v_reviewer))
                           || v_extra,
          'business_key', coalesce(nullif(v_eff->>'business_key',''), v_key),
          'owner_ref', coalesce(v_scope_owner, v_fk_owner, v_owner, nullif(v_eff->>'owner_ref',''), v_key),
          -- THE STATE MUST BE ONE THE TARGET DECLARES. 'open' is not in refunds_status_check,
          -- so W17-S01 wrote a refund the table refused: a fixture that names a state must name a
          -- declared one, the same lesson d8f learned for the column fixtures. The allowed set is
          -- read from the target's own CHECK constraint; where there is none, 'open' still applies.
          'effect_state', coalesce(v_working_state, v_decl_state, 'open'),
          -- D23. THE DECLARED MINIMUM WINS OVER THE GENERATED VALUE, and the first draft of this
          -- file had it the other way round and did not work. verified is declared in the
          -- supplier_account write map, so the driver's payload builder generates a value for it
          -- exactly as D19 found it generating routing — and a generated boolean beat the
          -- requirement the CHECK constraint states. Declaring a column so the writer can control
          -- it is also what makes the harness start inventing it, for the second time in six files.
          'effect_payload', v_eff || coalesce(v_prov_payload,'{}'::jsonb)
                                   || coalesce(v_working_payload,'{}'::jsonb)
                                   || coalesce(v_decision_payload,'{}'::jsonb))
        || jsonb_strip_nulls(jsonb_build_object('reviewer_role_id', v_reviewer))
        || case when e.expected_effect_type = 'REVIEW_VERDICT'
                then jsonb_strip_nulls(jsonb_build_object(
                       'verdict', v_verdict, 'reviewer_role_id', v_reviewer))
                else '{}'::jsonb end
        || case when b.handler_class = 'REVIEW_HANDLER'
                then jsonb_strip_nulls(jsonb_build_object(
                       'verdict', v_verdict,
                       'reviewer_role_id', v_reviewer))
                else '{}'::jsonb end
        -- THE OUTPUT CONTRACT IS THE AUTHORITY ON THE OUTPUT, not the effect type. W11-S01 is the
        -- one step of 257 where the two disagree: step_type='measurement' gives it a contract
        -- requiring numerator, denominator, formula and window, while D7d's lexicon classified its
        -- effect as CAPABILITY_REQUEST from the required_action text. Keyed on the effect type this
        -- step could never satisfy its own contract. Keyed on the contract it can, and no other step
        -- changes behaviour.
        || case when exists (select 1 from public.phase_d_handler_schema sc2
                              where sc2.step_id = sr.step_id and sc2.schema_kind = 'output'
                                and sc2.required_keys && array['numerator','denominator'])
                then jsonb_build_object('numerator', 1, 'denominator', 1,
                                        'formula','fixture','window','fixture')
                else '{}'::jsonb end);

      -- ---- THE RUN ACCUMULATES ITS OWN REFERENCES --------------------------------------------
      -- A workflow that CREATES an object at step 1 and has a rule READ it at step 4 needs the key
      -- step 1 produced. parent_refs is computed once, before the drive, so W16-S04's BR-020 was
      -- asking about a transaction that W16-S01 had just written and nobody had told it about.
      -- The name each object contributes is read from phase_d_fixture_stage.contributes_ref — the
      -- same mapping the scenario factory uses, so the two vocabularies cannot drift apart.
      if coalesce((v_res->'ok')::text,'false') = 'true'
         and e.effect_object_id is not null
         and (v_res->'phase_d'->'business_effect'->>'result_reference') is not null then
        -- D20. WHAT A STAGE CONTRIBUTES IS NOT ALWAYS A KEY. The comment above says this mapping
        -- is "the same mapping the scenario factory uses, so the two vocabularies cannot drift
        -- apart". They had already drifted: the factory carried a hard-coded exception —
        --     case when st.stage_key = 'inquiry_route_set' then 'confirmed' else <result key> end
        -- and this fold did not. So the factory contributed route_state='confirmed' and the driver
        -- overwrote it with a record id the moment W06-S01 produced its effect, and GATE-010 was
        -- handed "route state 2845" and refused a route that was in fact confirmed. An assertion
        -- that two things cannot drift, written next to the copy that had drifted.
        --
        -- The stage now DECLARES which it contributes and both readers obey the same column.
        -- D21. A REVIEW STEP PRODUCES A REVIEW RECORD, WHATEVER OBJECT IT IS ABOUT.
        --
        -- 27 of the 257 frozen steps name a business object in phase_d_step_effect.effect_object_id
        -- and produce a review_record: W05-S06 is effect_object_id='inquiry' and its declared
        -- transition is "review_record appended with the caller's verdict". The effect it produces
        -- lands in public.phase_d_object_record, not in public.inquiries.
        --
        -- This fold keyed on effect_object_id alone and wrote the produced reference under that
        -- object's name. So after W05-S06 the run believed inquiry_id was 3123 — a
        -- phase_d_object_record.record_id — and GATE-011 dutifully reported "inquiry 3123 is not
        -- quote-ready or does not exist". It was right: no such inquiry exists. W05-S01 had
        -- produced public.inquiries:id=578d356c-8b0d-448f-b500-6971d15cf329 six steps earlier and
        -- the run had thrown it away.
        --
        -- Four workflows, one defect, each refused by the gate that sits immediately after a review
        -- step: W05-S07 GATE-011, W07-S04 GATE-012, W14-S05 GATE-017, W15-S02 GATE-018. Every one
        -- of those gates was reading the wrong subject because the harness had renamed it.
        --
        -- A reference is only folded when the thing produced IS the object, proved by comparing the
        -- relation the write actually landed in against the relation that object is bound to.
        -- Nothing is listed by hand and no step is special-cased.
        select st2.contributes_ref, st2.contributes_kind into v_contrib, v_contrib_kind
          from public.phase_d_fixture_stage st2 where st2.object_id = e.effect_object_id;

        v_produced_rel := split_part(v_res->'phase_d'->'business_effect'->>'result_reference', ':', 1);
        select case when bb.relation_kind = 'EXISTING_TABLE'
                    then (select mm.target_relation from public.phase_d_object_write_map mm
                           where mm.object_id = e.effect_object_id)
                    else 'public.phase_d_object_record' end
          into v_object_rel
          from public.phase_d_business_object_binding bb
         where bb.object_id = e.effect_object_id;

        if v_contrib is not null and v_produced_rel is distinct from v_object_rel then
          -- Not dropped in silence: fn_phase_d_reference_fold_state() counts every step whose
          -- declared object and produced relation disagree, so the 27 review steps that do this are
          -- a standing, countable fact about the frozen registry rather than a quiet skip here.
          v_contrib := null;
        end if;

        if v_contrib is not null then
          v_parents := v_parents || jsonb_build_object(v_contrib,
            case when v_contrib_kind = 'STATE'
                 then coalesce(v_res->'phase_d'->'business_effect'->>'state',
                               v_working_state,
                               split_part(v_res->'phase_d'->'business_effect'->>'result_reference', '=', 2))
                 else split_part(v_res->'phase_d'->'business_effect'->>'result_reference', '=', 2)
            end);
          if v_contrib = 'customer_id' then
            v_parents := v_parents || jsonb_build_object('caller_customer_id',
              split_part(v_res->'phase_d'->'business_effect'->>'result_reference', '=', 2));
          end if;
        end if;
      end if;

      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'expected_effect_type', e.expected_effect_type,
        'handler_class', b.handler_class,
        'ok', v_res->'ok', 'outcome', v_res->>'outcome',
        'step_state', v_res->>'step_state', 'run_state', v_res->>'run_state',
        'effect', v_res->'phase_d'->'business_effect'->'result_reference',
        'effect_id', v_res->'phase_d'->'business_effect'->'effect_id',
        'review_recorded', v_decide));
    exception when others then
      v_sqlstate := SQLSTATE; v_err := SQLERRM;
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+|gate[0-9]+_[a-z0-9_]+|br[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'expected_effect_type', e.expected_effect_type,
        'handler_class', b.handler_class,
        'ok', false, 'refused_with', v_code, 'sqlstate', v_sqlstate,
        'reason', left(v_err, 400)));
      exit;
    end;
  end loop;

  select state into v_run_state from public.phase_c_workflow_run where run_id = v_run;
  select count(*) into v_after from public.phase_d_effect_ledger;
  select count(*) into v_ledger from public.phase_d_effect_ledger where run_id = v_run;

  return jsonb_build_object(
    'ok', (v_run_state is not null
           and not exists (select 1 from jsonb_array_elements(v_steps) x
                            where coalesce((x->>'ok')::boolean, false) = false)
           and not exists (select 1 from jsonb_array_elements(v_handoffs) x
                            where coalesce((x->>'ok')::boolean, false) = false)),
    'workflow_id', v_wf, 'run_id', v_run, 'run_state', v_run_state,
    'steps_in_workflow', (select count(*) from public.phase_b_workflow_step
                           where workflow_id = v_wf),
    'steps_driven', jsonb_array_length(v_steps),
    'handoffs_accepted', v_haccept,
    'handoffs', v_handoffs,
    'open_handoffs_left', (select count(*) from public.phase_c_handoff_run
                            where run_id = v_run and status = 'open'),
    'effects_for_this_run', v_ledger,
    'effect_ledger_delta', v_after - v_before,
    'terminal', (select terminal from public.phase_b_workflow_state
                  where state = v_run_state),
    'steps', v_steps);
end $function$
;

-- -------------------------------------------------------------------------------------------------
-- DEPLOY-TIME CONTROLS.
-- -------------------------------------------------------------------------------------------------
do $ctl$
declare
  v_fx jsonb; v jsonb; wf record; v_cands jsonb;
  v_closed int := 0; v_net int; v_max bigint; v_nb bigint; v_notif int;
  v_w12 int; v_w17 int; v_out text := '';
  v_current int; v_superseded int; v_refused boolean := false;
  v_a jsonb; v_key text;
begin
  perform set_config('app.phase_d_test_context','on', true);

  -- (a) ONE RECORD PER IDENTITY MUST SURVIVE THE CHANGE. Five writes of one dispatch_batch must
  --     leave exactly ONE current record and four retained, superseded predecessors — not five
  --     live rows, which is what this family exists to prevent.
  begin
    v_key := 'd27-ctl-' || md5('batch');
    for i in 1..5 loop
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','dispatch_batch','business_key', v_key, 'owner_ref','d27_control',
        'created_by','d27_control','state','open',
        'payload', jsonb_build_object('step', i, 'note','ZZ DEMO — d27 control write ' || i)));
    end loop;
    select count(*) filter (where superseded_by is null),
           count(*) filter (where superseded_by is not null)
      into v_current, v_superseded
      from public.phase_d_object_record
     where object_id = 'dispatch_batch' and business_key = v_key;
    raise exception 'PHASE_D_D27_CTL_ROLLBACK';
  exception when others then
    if SQLERRM <> 'PHASE_D_D27_CTL_ROLLBACK' then
      raise exception 'D27 control (a): the five-write probe failed with: %', SQLERRM;
    end if;
  end;
  if coalesce(v_current,0) <> 1 then
    raise exception 'D27 control (a): five writes left % CURRENT dispatch_batch record(s); exactly 1 is required. One record per identity has been lost.', coalesce(v_current,-1);
  end if;
  if coalesce(v_superseded,0) <> 4 then
    raise exception 'D27 control (a): five writes retained % superseded predecessor(s); 4 are required. History is evidence and must not be overwritten.', coalesce(v_superseded,-1);
  end if;

  -- (b) THE REFUSAL MUST STILL FIRE for a repeat that moves nothing. Narrowed is not removed.
  begin
    v_key := 'd27-ctl-' || md5('norepeat');
    v_a := jsonb_build_object('note','ZZ DEMO — identical');
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','dispatch_batch','business_key', v_key, 'owner_ref','d27_control',
      'created_by','d27_control','state','open','payload', v_a));
    begin
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','dispatch_batch','business_key', v_key, 'owner_ref','d27_control',
        'created_by','d27_control','state','open','payload', v_a));
    exception when sqlstate '23505' then
      if position('pd_object_duplicate_identity' in SQLERRM) > 0 then v_refused := true; end if;
    end;
    raise exception 'PHASE_D_D27_CTL_ROLLBACK';
  exception when others then
    if SQLERRM <> 'PHASE_D_D27_CTL_ROLLBACK' then
      raise exception 'D27 control (b): the identical-repeat probe failed with: %', SQLERRM;
    end if;
  end;
  if not v_refused then
    raise exception 'D27 control (b): an identical repeat write was ACCEPTED. The refusal was removed rather than narrowed.';
  end if;

  -- (c) THE 30-WORKFLOW DRIVE.
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  begin
    select coalesce(max(id),0) into v_max from net.http_request_queue;
    select count(*) into v_nb from public.notifications;
    for wf in select workflow_id from public.phase_b_workflow order by workflow_id loop
      v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
        'label','d27c-' || lower(wf.workflow_id), 'execution_context','test',
        'for_workflow', case when wf.workflow_id = 'W12' then wf.workflow_id else null end));
      v := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id', wf.workflow_id, 'label','d27c-' || lower(wf.workflow_id),
        'execution_context','test','verdict','approved',
        'reviewer_role_id', coalesce(
          (select s.independent_reviewer_role_id from public.phase_b_workflow_step s
            where s.workflow_id = wf.workflow_id
              and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
            order by s.step_id limit 1), 'risk_and_governance_manager'),
        'reviewer_candidates', v_cands,
        'parent_refs', v_fx->'rule_context'));
      if (v->>'steps_driven') = (v->>'steps_in_workflow') then v_closed := v_closed + 1; end if;
      if wf.workflow_id = 'W12' then v_w12 := (v->>'steps_driven')::int; end if;
      if wf.workflow_id = 'W17' then v_w17 := (v->>'steps_driven')::int; end if;
      if (v->>'steps_driven') <> (v->>'steps_in_workflow') then
        v_out := v_out || format(E'\n  %s %s/%s stop=%s  %s', wf.workflow_id,
          v->>'steps_driven', v->>'steps_in_workflow',
          coalesce((select x->>'step_id' from jsonb_array_elements(v->'steps') x
                     where coalesce((x->>'ok')::boolean,false)=false limit 1),'?'),
          left(coalesce((select x->>'reason' from jsonb_array_elements(v->'steps') x
                     where coalesce((x->>'ok')::boolean,false)=false limit 1),''),150));
      end if;
    end loop;
    select count(*) into v_net from net.http_request_queue where id > v_max;
    select count(*) - v_nb into v_notif from public.notifications;
    raise exception 'PHASE_D_D27_CTL_ROLLBACK';
  exception when others then
    if SQLERRM <> 'PHASE_D_D27_CTL_ROLLBACK' then
      raise exception 'D27 control (c): the 30-workflow drive failed with: %', SQLERRM;
    end if;
  end;

  -- W12 IS NOT CLOSED BY THIS FILE AND THE CONTROL SAYS SO. This file gives the store-backed
  -- TRANSACTION_RECORD a way to move, which takes W12 from 2/9 to 7/9. It then stops at S07 on
  -- GATE-015, refusing the run because W12-S06 created the assignment S07 is about — a separate
  -- defect with a separate fix. Demanding 9 here would be asking this file to claim a fix it did
  -- not make.
  if coalesce(v_w12,0) < 7 then
    raise exception 'D27 control (c): W12 drove % of 9; it reached 2 before this file and must reach at least 7.%', coalesce(v_w12,0), v_out;
  end if;
  if coalesce(v_w17,0) <> 11 then
    raise exception 'D27 control (c): W17 drove % of 11 — D26 must not have regressed.%', coalesce(v_w17,0), v_out;
  end if;
  if v_closed < 29 then
    raise exception 'D27 control (c): % of 30 close; 29 was the count before this file and it must not regress.%', v_closed, v_out;
  end if;
  if coalesce(v_net,0) <> 0 then
    raise exception 'D27 control (c): the drive enqueued % outbound request(s).', v_net;
  end if;
  if coalesce(v_notif,0) <> 0 then
    raise exception 'D27 control (c): the drive wrote % notification row(s).', v_notif;
  end if;

  raise notice 'D27: % of 30 close. W12 %/9, W17 %/11. One current record per identity, 4 superseded retained, identical repeat still refused.',
    v_closed, v_w12, v_w17;
end $ctl$;

commit;
