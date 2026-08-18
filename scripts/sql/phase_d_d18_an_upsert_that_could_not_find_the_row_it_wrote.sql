-- =================================================================================================
-- Phase D — D18. An upsert that could not find the row it had just written.
--
-- THE BRIEF CALLED THIS "the harness seeds the row the step creates". IT IS NOT.
--
-- Four workflows stopped on a unique constraint or a duplicate gate, and the session brief's
-- diagnosis was that the scenario factory pre-creates the object the workflow produces. That was
-- re-measured before anything was built, exactly as the brief asks. It is wrong for three of the
-- four, and `for_workflow` — the fix the brief proposed re-testing — does not close them:
--
--   W09  for_workflow ON -> 3 stages skipped, 13 more blocked by the cascade, and W09-S03 STILL
--        died on supplier_capabilities_pkey. Removing the fixture row did not remove the collision,
--        which is the tell that the fixture was never the mechanism.
--
-- The mechanism, proved in isolation on production with no workflow involved at all:
--
--     write 1  business_key=KEYPROBE-A  owner_ref=30723 -> supplier_capabilities:supplier_id=30723
--     write 2  business_key=KEYPROBE-B  owner_ref=30723 -> REFUSED duplicate key ... _pkey
--
-- Two writes of the same object, same owner, through the canonical service, and the second one
-- cannot see the first. `fn_phase_d_object_write`'s UPSERT_STATE branch probed
--
--     where key_column::text = business_key
--
-- unconditionally. That is only correct when the write map points key_column at business_key, and
-- two shapes in the estate do not:
--
--   supplier_capability   key_column = supplier_id, column_map.supplier_id = 'owner_ref'
--                         It PROBED supplier_id = <business key> and INSERTED supplier_id =
--                         <owner ref>. A key written in two shapes: it read one value and wrote
--                         another, so it could never match its own row.
--
--   quotation             key_column = id, a generated bigint, probed against a uuid business key.
--   payment_transaction   Never matches, so UPSERT_STATE could only ever INSERT — and the second
--                         insert died on the relation's NATURAL key:
--                             quotes(inquiry_id, supplier_id)
--                             transactions(quote_id) WHERE quote_id IS NOT NULL
--
-- Measured the same way: two supplier_account writes with different business keys produced TWO
-- lead rows. An operation declared UPSERT_STATE that has never once updated.
--
-- IDENTITY IS NOW RESOLVED IN TWO DERIVED PASSES, nothing hand-listed:
--
--   1. key_column, using THE VALUE THAT WILL BE WRITTEN INTO IT (column_map->>key_column resolved
--      against the supplied payload), not the business key.
--   2. failing that, any other unique index on the relation whose columns are ALL declared in the
--      map and ALL supplied by this call — the row's natural key. The index's own predicate is
--      carried through verbatim from pg_get_expr, so the PARTIAL index
--      transactions(quote_id) WHERE quote_id IS NOT NULL matches exactly the rows it constrains
--      instead of a guess about what the predicate means.
--
-- The UPDATE then targets the row the probe FOUND. Re-deriving it from business_key one statement
-- later would reintroduce the same mismatch, because a natural-key probe can resolve a row whose
-- key_column equals neither the business key nor anything in the payload.
--
-- WHAT THIS DOES NOT DO. Where neither pass resolves an identity the write stays an INSERT and a
-- unique violation remains a real business duplicate. supplier_account is such a case: key_column
-- `id` is generated and unmapped, and leads' other unique indexes (claim_token, place_id) are not
-- in the map, so W09 still writes four lead rows for one supplier. That is NOT fixed here and it is
-- NOT hidden: fn_phase_d_object_identity_state() lists every UPSERT_STATE map with no resolvable
-- identity, and it is RED with an owner. Inventing an identity for leads would be the harness
-- deciding what a supplier account is.
--
-- NOTHING IS WEAKENED. No constraint is dropped, no gate is relaxed, no fixture stage is skipped.
-- The collisions stop because the canonical writer now does what UPSERT_STATE says it does. The
-- policy family it enforces already said so in its own refusal text: "One record per identity;
-- move its state, do not write a second."
-- =================================================================================================

begin;

-- -------------------------------------------------------------------------------------------------
-- 1. The canonical writer resolves identity before deciding insert-or-update.
--
-- The body below is the LIVE definition with three edits and nothing else, generated from
-- pg_get_functiondef rather than retyped, so the D17 outbound guard applied minutes ago is carried
-- forward rather than reverted. Re-applying an earlier file in a chain silently reverting a later
-- one is recorded in the D9 closure section 5 and is not repeated here.
-- -------------------------------------------------------------------------------------------------
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
        if not (v_supplied ? v_door.guard_column) then
          execute format('select %s', v_door.suppression_sql) into v_door_val;
          v_supplied := v_supplied || jsonb_build_object(v_door.guard_column, v_door_val);
        end if;
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
-- 2. The board. It reports the identity every UPSERT_STATE map can actually resolve, and it is
--    ALLOWED TO BE RED — an object whose identity cannot be resolved is a fact about the estate,
--    not a number to be narrowed until it reads zero.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_phase_d_object_identity_state()
returns table(check_name text, expected text, actual text, state text, detail text)
language sql stable
set search_path to 'public', 'pg_temp'
as $board$
with wm as (select * from public.phase_d_object_write_map where operation = 'UPSERT_STATE'),
uq as (
  select 'public.' || t.relname as rel, ic.relname as idx_name,
         array_agg(a.attname::text order by a.attnum) as cols
    from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    join pg_class t  on t.oid  = i.indrelid
    join pg_namespace n on n.oid = t.relnamespace and n.nspname = 'public'
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
   where i.indisunique
   group by 1, 2
),
resolvable as (
  select wm.object_id,
         -- pass 1: the key column is mapped, so the writer can probe the value it will write
         (wm.column_map ? wm.key_column) as by_key_column,
         -- pass 2: some other unique index is entirely covered by the map
         exists (select 1 from uq
                  where uq.rel = wm.target_relation
                    and uq.cols <> array[wm.key_column]
                    and (select bool_and(wm.column_map ? c) from unnest(uq.cols) c)) as by_natural_key
    from wm
)
select 'every_upsert_state_map_can_resolve_an_identity',
       (select count(*)::text from resolvable),
       (select count(*)::text from resolvable where by_key_column or by_natural_key),
       case when exists (select 1 from resolvable where not (by_key_column or by_natural_key))
            then 'RED' else 'GREEN' end,
       coalesce((select string_agg(object_id, ', ' order by object_id) from resolvable
                  where not (by_key_column or by_natural_key)),
                'every UPSERT_STATE map resolves an identity')
       || ' — an UPSERT_STATE that resolves no identity can only ever INSERT, so its second write is'
       || ' a duplicate row rather than a state move. Owner: Phase D. Closing it needs an identity'
       || ' the business declares, not one a harness invents.'

union all
-- THE REGRESSION GUARD. This is the check that would have caught the original defect, and it is
-- written against the mechanism rather than against a count of failures.
select 'no_upsert_state_map_probes_a_column_it_does_not_write',
       '0',
       (select count(*)::text from wm
         where (wm.column_map ? wm.key_column)
           and (wm.column_map->>wm.key_column) <> 'business_key'
           and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = 'fn_phase_d_object_write'
                              and p.prosrc like '%v_supplied->>(wm.column_map->>wm.key_column)%')),
       case when exists (
              select 1 from wm
               where (wm.column_map ? wm.key_column)
                 and (wm.column_map->>wm.key_column) <> 'business_key'
                 and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                  where n.nspname = 'public' and p.proname = 'fn_phase_d_object_write'
                                    and p.prosrc like '%v_supplied->>(wm.column_map->>wm.key_column)%'))
            then 'RED' else 'GREEN' end,
       'supplier_capability points key_column supplier_id at owner_ref; if the writer ever goes back '
       || 'to probing business_key it reads one value and writes another, and the second write dies '
       || 'on the primary key'

union all
select 'the_writer_carries_the_natural_key_pass',
       '1',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'fn_phase_d_object_write'
           and p.prosrc like '%indisunique%' and p.prosrc like '%pg_get_expr(i.indpred%'),
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname = 'fn_phase_d_object_write'
                            and p.prosrc like '%indisunique%' and p.prosrc like '%pg_get_expr(i.indpred%')
            then 'GREEN' else 'RED' end,
       'quotes(inquiry_id,supplier_id) and the PARTIAL transactions(quote_id) are only reachable '
       || 'through the natural-key pass, and the partial predicate has to travel with it'

union all
select 'the_update_targets_the_row_the_probe_found',
       '1',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'fn_phase_d_object_write'
           and p.prosrc like '%using v_supplied, v_existing%'),
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname = 'fn_phase_d_object_write'
                            and p.prosrc like '%using v_supplied, v_existing%')
            then 'GREEN' else 'RED' end,
       'updating by business_key after a natural-key probe reintroduces the same mismatch one '
       || 'statement later'
$board$;

revoke all on function public.fn_phase_d_object_identity_state() from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- 3. DEPLOY-TIME CONTROLS. Every one of these runs the writer for real and aborts its own
--    subtransaction, so this deploy leaves no row behind. PL/pgSQL variables are not transactional,
--    which is why the counts survive the rollback.
-- -------------------------------------------------------------------------------------------------
do $ctl$
declare
  v_sup text; v_a jsonb; v_b jsonb;
  v_ref1 text; v_ref2 text; v_leads int; v_red int;
  v_q1 text; v_q2 text; v_quotes int;
begin
  perform set_config('app.phase_d_test_context','on', true);

  -- (a) THE ORIGINAL DEFECT, RE-RUN. Same owner, different business key, twice. Before this file
  --     the second write raised duplicate key on supplier_capabilities_pkey.
  begin
    v_a := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key', md5('d18-ctl-sup')::uuid::text,
      'owner_ref', md5('d18-ctl-sup')::uuid::text, 'created_by','d18_control','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO — d18 control','verified',true)));
    v_sup := split_part(v_a->>'result_reference','=',2);

    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_capability','business_key','D18-CTL-A','owner_ref', v_sup,
      'created_by','d18_control','state','approved',
      'payload', jsonb_build_object('trades','["general"]'::jsonb)));
    v_ref1 := v_b->>'result_reference';

    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_capability','business_key','D18-CTL-B','owner_ref', v_sup,
      'created_by','d18_control','state','approved',
      'payload', jsonb_build_object('trades','["steel"]'::jsonb)));
    v_ref2 := v_b->>'result_reference';

    raise exception 'PHASE_D_D18_CTL_ROLLBACK';
  exception
    when others then
      if SQLERRM <> 'PHASE_D_D18_CTL_ROLLBACK' then
        raise exception 'D18 control (a): the two-write probe failed with: %', SQLERRM;
      end if;
  end;
  if v_ref1 is null or v_ref2 is null then
    raise exception 'D18 control (a): a supplier_capability write returned no reference (% / %)',
      coalesce(v_ref1,'(null)'), coalesce(v_ref2,'(null)');
  end if;
  if v_ref1 <> v_ref2 then
    raise exception 'D18 control (a): two writes of one supplier''s capability resolved to different rows (% vs %). The upsert is still not finding the row it wrote.',
      v_ref1, v_ref2;
  end if;

  -- (b) THE NATURAL KEY. Two quotations for one (inquiry, supplier) with different business keys
  --     must resolve to ONE row through quotes_inquiry_id_supplier_id_key.
  begin
    perform public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','d18-ctl-nat','execution_context','test','up_to_stage', 140));
    select count(*) into v_quotes from public.quotes;

    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','quotation','business_key', md5('D18-NAT-A')::uuid::text,
      'owner_ref', (select id::text from public.leads order by id desc limit 1),
      'created_by','d18_control','state','submitted',
      'payload', jsonb_build_object(
        'inquiry_id', (select id::text from public.inquiries order by id desc limit 1),
        'quote_amount', 1000)));
    v_q1 := v_b->>'result_reference';

    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','quotation','business_key', md5('D18-NAT-B')::uuid::text,
      'owner_ref', (select id::text from public.leads order by id desc limit 1),
      'created_by','d18_control','state','submitted',
      'payload', jsonb_build_object(
        'inquiry_id', (select id::text from public.inquiries order by id desc limit 1),
        'quote_amount', 2000)));
    v_q2 := v_b->>'result_reference';

    raise exception 'PHASE_D_D18_CTL_ROLLBACK';
  exception
    when others then
      if SQLERRM <> 'PHASE_D_D18_CTL_ROLLBACK' then
        raise exception 'D18 control (b): the natural-key probe failed with: %', SQLERRM;
      end if;
  end;
  if v_q1 is null or v_q2 is null or v_q1 <> v_q2 then
    raise exception 'D18 control (b): two quotations for one (inquiry, supplier) resolved to % and %. The natural-key pass is not matching quotes_inquiry_id_supplier_id_key.',
      coalesce(v_q1,'(null)'), coalesce(v_q2,'(null)');
  end if;

  -- (c) The board must be readable, and its one RED must be the disclosed one rather than a
  --     surprise. supplier_account has no resolvable identity and that is stated, not hidden.
  select count(*) into v_red from public.fn_phase_d_object_identity_state() where state <> 'GREEN';
  if v_red <> 1 then
    raise exception 'D18 control (c): fn_phase_d_object_identity_state() has % red check(s); exactly 1 is expected and disclosed (the unresolvable-identity maps).', v_red;
  end if;
  if not exists (select 1 from public.fn_phase_d_object_identity_state()
                  where state = 'RED' and check_name = 'every_upsert_state_map_can_resolve_an_identity') then
    raise exception 'D18 control (c): the red check is not the disclosed one. A different red means something else broke.';
  end if;

  raise notice 'D18: identity resolution live; two-write probes collapse to one row on both the key column and the natural key.';
end $ctl$;

commit;
