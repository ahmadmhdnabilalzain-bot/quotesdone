-- =================================================================================================
-- Phase D — D19. A generated payload re-armed the door the writer had just closed.
--
-- D17 closed two outbound HTTP doors by setting each trigger's own already-done marker on Phase D
-- test writes, and proved it: a full 23-stage scenario build enqueued 0 requests where it had
-- enqueued 2. D18 then made UPSERT_STATE resolve identity properly, and the ten stopped workflows
-- were re-driven. W09 closed 9/9. W14 went 1/9 -> 5/9. W16 went 1/9 -> 2/9.
--
-- AND W05 WENT 2/9 -> 1/9, refused by D17's own guard:
--
--     fn_phase_d_object_write: writing inquiry to public.inquiries enqueued 1 outbound HTTP
--     request(s): POST .../functions/v1/dispatch_inquiry
--
-- The guard did exactly what it was built to do, on the increment that introduced the regression,
-- one file after it was written. That is the whole argument for building it.
--
-- THE MECHANISM. D17 added `routing` to the inquiry write map so the writer could set it. The
-- DRIVER's payload builder generates a typed value for every column the map declares — that is how
-- it drives 257 steps without a hand-written payload each. So from D17 onward the driver supplied
-- its own `routing`, a generated jsonb with no `dispatched_at` in it. The injection read
--
--     if not (v_supplied ? v_door.guard_column) then ... end if;
--
-- saw that `routing` was present, respectfully stood aside, and handed
-- trg_autodispatch_inquiry a value that satisfied its firing condition.
--
-- This is the shape the D9 closure recorded as "a generated fixture beat the real reference": a
-- harness that invents a value for the key the thing under test must read. There it answered a rule
-- in the negative; here it re-opened an outbound door. Declaring a column so the writer can control
-- it is also what makes the harness start generating it, and those two consequences arrived in the
-- same edit.
--
-- THE FIX. Under the Phase D hold the suppression is not defeasible by the caller. The writer
-- overwrites the guard column rather than deferring to a supplied value.
--
-- That is safe to assert rather than assume: both registered guard columns were measured as read by
-- nothing — 0 phase_d_rule_enforcement rows, 0 phase_d_gate_contract rows, and 0 references in
-- fn_rfq_score or fn_rfq_required_check. Overwriting them changes no decision any workflow makes.
-- Leaving them writable changes whether a POST leaves the database.
--
-- The narrower alternative — merge dispatched_at into whatever the caller sent — was rejected. It
-- keeps a caller-shaped hole in a hold, and the next generated key that happens to collide with a
-- trigger guard would walk through it exactly as this one did.
-- =================================================================================================

begin;

-- The body below is the LIVE definition with one edit, generated from pg_get_functiondef rather
-- than retyped, so D17's outbound guard and D18's identity resolution are carried forward.
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
    if b.policy_family = 'TRANSACTION_RECORD' then
      raise exception 'fn_phase_d_object_write: % is a %-family record and business key % already exists as record %. One record per identity; move its state, do not write a second. (pd_object_duplicate_identity)',
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
     and b.policy_family in ('VERSIONED','IMMUTABLE_REVISION','CASE_RECORD','MUTABLE_CONTROLLED') then
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

-- CREATE OR REPLACE preserves the ACL, so the D2 revoke stands and is not repeated here.

-- -------------------------------------------------------------------------------------------------
-- DEPLOY-TIME CONTROLS. Both drive real work and abort their own subtransaction, so this deploy
-- leaves nothing behind; PL/pgSQL variables are not transactional, so the counts survive.
-- -------------------------------------------------------------------------------------------------
do $ctl$
declare
  v_fx jsonb; v jsonb; v_cands jsonb; v_rev text;
  v_max bigint; v_new int; v_urls text;
  v_driven int; v_stop text; v_reason text;
begin
  perform set_config('app.phase_d_test_context','on', true);
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';

  -- (a) THE REGRESSION ITSELF. Drive W05 — the workflow whose first step writes an inquiry — and
  --     require that it gets past S01 with no outbound request. Before this file it refused at
  --     W05-S01 with pd_object_outbound_request_produced.
  begin
    select coalesce(max(id),0) into v_max from net.http_request_queue;
    v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','d19-ctl-w05','execution_context','test'));
    select coalesce(
      (select s.independent_reviewer_role_id from public.phase_b_workflow_step s
        where s.workflow_id = 'W05' and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
        order by s.step_id limit 1), 'risk_and_governance_manager') into v_rev;
    v := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W05','label','d19-ctl-w05','execution_context','test','verdict','approved',
      'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands,
      'parent_refs', v_fx->'rule_context'));
    v_driven := (v->>'steps_driven')::int;
    select x->>'step_id', left(coalesce(x->>'reason',''),200) into v_stop, v_reason
      from jsonb_array_elements(v->'steps') x
     where coalesce((x->>'ok')::boolean,false) = false limit 1;
    select count(*), coalesce(string_agg(distinct url, ', '),'(none)') into v_new, v_urls
      from net.http_request_queue where id > v_max;
    raise exception 'PHASE_D_D19_CTL_ROLLBACK';
  exception
    when others then
      if SQLERRM <> 'PHASE_D_D19_CTL_ROLLBACK' then
        raise exception 'D19 control (a): driving W05 failed with: %', SQLERRM;
      end if;
  end;

  if coalesce(v_new,0) <> 0 then
    raise exception 'D19 control (a): driving W05 enqueued % outbound request(s): %. The suppression is still being stood aside for a generated value.',
      v_new, v_urls;
  end if;
  if coalesce(v_driven,0) < 2 then
    raise exception 'D19 control (a): W05 drove only % step(s), stopping at % — %. It reached 2 before D17 and must not have regressed.',
      coalesce(v_driven,0), coalesce(v_stop,'(none)'), coalesce(v_reason,'(none)');
  end if;

  -- (b) THE OVERWRITE IS REAL. Hand the writer a routing value that WOULD arm the trigger and
  --     require that the row lands with dispatched_at set anyway.
  begin
    v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','d19-ctl-arm','execution_context','test','up_to_stage', 10));
    select coalesce(max(id),0) into v_max from net.http_request_queue;
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','inquiry','business_key', md5('d19-arm')::uuid::text,
      'owner_ref', (v_fx->'parent_refs'->>'customer_id'),
      'created_by','d19_control','state','quote_ready',
      'payload', public.fn_phase_d_fixture_inquiry_payload('d19-arm')
                 || jsonb_build_object('routing', jsonb_build_object('armed_by_the_caller', true))));
    select count(*), coalesce(string_agg(distinct url, ', '),'(none)') into v_new, v_urls
      from net.http_request_queue where id > v_max;
    raise exception 'PHASE_D_D19_CTL_ROLLBACK';
  exception
    when others then
      if SQLERRM <> 'PHASE_D_D19_CTL_ROLLBACK' then
        raise exception 'D19 control (b): the arming probe failed with: %', SQLERRM;
      end if;
  end;
  if coalesce(v_new,0) <> 0 then
    raise exception 'D19 control (b): a caller-supplied routing with no dispatched_at still let % request(s) out: %',
      v_new, v_urls;
  end if;

  -- (c) the D17 board is still green and still watching
  if exists (select 1 from public.fn_phase_d_outbound_state() where state <> 'GREEN') then
    raise exception 'D19 control (c): fn_phase_d_outbound_state() is not green after this change.';
  end if;

  raise notice 'D19: the outbound suppression is no longer defeasible by a caller-supplied value.';
end $ctl$;

commit;
