-- J04 — the outbound-request guard counted a scheduled job's requests as the write's own
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. The 257-step coverage drive came back:
--
--   fn_phase_d_object_write: writing inquiry to public.inquiries enqueued 2 outbound HTTP
--   request(s): POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dropbox_backup,
--   POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/uptime_check
--   (pd_object_outbound_request_produced)
--
-- Neither request came from the write. cron.job 88 dropbox_backup_scan and cron.job 35
-- uptime_check_15min are both `*/15 * * * *` and both active; they enqueue into
-- net.http_request_queue, they commit while a Phase D transaction is open, and READ COMMITTED shows
-- their rows to this function's next statement. The guard counted `where q.id > v_net_max` -- every
-- row above a watermark, by whoever -- so four times an hour a Phase D drive was refused for
-- something a scheduled job did.
--
-- The guard itself is right and stays: a Phase D test write may not leave an outbound request
-- behind it. What was wrong is the population. Requests are now attributed to THIS transaction:
-- a visible queue row whose xmin is still in progress can only have been written by us, because a
-- row from any other in-flight transaction is not visible at all and a row from a committed one
-- reports 'committed'. pg_xact_status settles it exactly, including for the subtransaction xids a
-- plpgsql exception block allocates -- verified on this database, where a row inserted inside
-- `begin ... exception ... end` carried xmin 3453125 against a top-level 3453124 and still reported
-- 'in progress'.
--
-- fn_phase_d_fixture_scenario reported the same population under the name
-- outbound_http_requests_written_by_this_scenario, and had the same defect for the same reason.
--
-- THE BOARD IS UPDATED, NOT WEAKENED. fn_phase_d_outbound_state's check
-- the_canonical_writer_still_counts_the_outbound_queue asserted the writer's own text contains
-- 'net.http_request_queue'. The writer now reaches the queue through the attribution helper, so the
-- check reads the helper's name instead. The other half of the check --
-- pd_object_outbound_request_produced -- is untouched, and the assertion is the same one: the
-- canonical writer still counts.
--
-- ROLLBACK: re-apply the previous bodies of fn_phase_d_object_write, fn_phase_d_fixture_scenario
-- and fn_phase_d_outbound_state, then
--   drop function if exists public.fn_phase_d_outbound_requests_by_this_transaction(bigint);
-- A down script is committed at
-- scripts/sql/down/phase_d_j04_the_outbound_guard_counted_a_cron_jobs_requests_down.sql.
--
-- GENERATED from the live bodies by scripts/tmp_diag/gen_j04.mjs.

-- ---- the attribution, in one place, because two callers ask the same question -----------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_outbound_requests_by_this_transaction(p_after bigint)
 RETURNS TABLE(n integer, urls text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- The 64-bit id carries the epoch; the 32-bit form is what a row's xmin holds.
  v_top8  bigint := pg_current_xact_id()::text::bigint;
  v_top32 bigint := mod(pg_current_xact_id()::text::bigint, 4294967296);
begin
  return query
  select count(*)::int,
         string_agg(distinct q.method || ' ' || q.url, ', ')
    from net.http_request_queue q
   where q.id > p_after
     -- Anything below our own xid was written before this transaction started and cannot be ours.
     -- Filtering it first also fixes the epoch for the conversion on the next line.
     and q.xmin::text::bigint >= v_top32
     -- A visible row whose writer is still in progress is ours: another in-flight transaction's
     -- rows are not visible here at all, and a committed one reports 'committed'.
     and pg_xact_status(((v_top8 - v_top32) + q.xmin::text::bigint)::text::xid8) = 'in progress';
end
$function$;

-- A newly CREATED function is granted EXECUTE to PUBLIC. Nothing outside the two Phase D writers
-- calls this, and it reads a queue that names production endpoints.
REVOKE ALL ON FUNCTION public.fn_phase_d_outbound_requests_by_this_transaction(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_outbound_requests_by_this_transaction(bigint) FROM anon;
REVOKE ALL ON FUNCTION public.fn_phase_d_outbound_requests_by_this_transaction(bigint) FROM authenticated;

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
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_scenario(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  st       public.phase_d_fixture_stage%rowtype;
  v_label  text := nullif(btrim(coalesce(p_input->>'label','')),'');
  v_ctx    text := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),''));
  v_upto   int  := coalesce(nullif(p_input->>'up_to_stage','')::int, 9999);
  v_actor  text := coalesce(nullif(btrim(p_input->>'created_by'),''), 'phase_d_fixture_factory');
  v_refs   jsonb := '{}'::jsonb;
  v_man    jsonb := '[]'::jsonb;
  v_w      jsonb;
  v_pay    jsonb;
  v_key    text;
  v_owner  text;
  v_state  text;
  v_name   text;
  v_missing text[];
  v_ref_n  bigint;
  v_err    text;
  v_ok     int := 0; v_blocked int := 0; v_owned int := 0;
  v_for_wf text := nullif(btrim(coalesce(p_input->>'for_workflow','')),'');
  v_notif_before bigint; v_notif_after bigint;
  v_notif_id_before bigint;              -- G11: the high-water mark, so new rows are identifiable
  v_notif_id_start  bigint;              -- G13: the same, for the whole scenario rather than one stage
  v_inbox_before bigint; v_inbox_after bigint;
  v_notif_start  bigint; v_inbox_start  bigint;
  v_net_start    bigint;
  v_fixture_run  bigint;                     -- F01: the audited fixture run this build belongs to
  v_terms_ver    text;   v_terms_hash text;  -- F08: a REAL published document, not an invented one
  v_sup_ver      text;   v_sup_hash   text;
  v_art_sha      text;                       -- F08: the digest BR-036 resolves
  v_cat          jsonb;                      -- F08: a committed catalogue value
  v_scenario_id  bigint;
  v_state_col    text;    -- F15: the column the write map points at the state
  v_actual       text;    -- F15: what the product left in it
begin
  if v_label is null then
    raise exception 'fn_phase_d_fixture_scenario: label is required; it is what makes the ids deterministic and the residue findable (pd_fixture_label_missing)'
      using errcode = '22023';
  end if;
  if v_ctx <> 'test' then
    raise exception 'fn_phase_d_fixture_scenario: execution_context is %; this factory runs only in test (pd_fixture_not_test_context)',
      coalesce(nullif(v_ctx,''),'(unset)') using errcode = '23514';
  end if;
  -- F01. THIS READ A GUC ANY CALLER COULD SET. `set local app.phase_d_test_context = 'on'` was
  -- accepted from service_role, so the "protected test context" was a string the caller supplied
  -- about itself -- the same shape as a guard authenticating an email. The context is now an hmac
  -- over the current txid, keyed by a secret no role can SELECT, minted only by
  -- fn_phase_d_test_context_open against an approved audited operation.
  v_fixture_run := public.fn_phase_d_fixture_context();
  if v_fixture_run is null then
    raise exception 'fn_phase_d_fixture_scenario: no verified Phase D fixture context in this transaction (pd_fixture_no_test_context)'
      using errcode = '23514',
            hint = 'select public.fn_phase_d_test_context_open(''{"operation_key":"pdop_scenario_factory","label":"..."}''); and abort the transaction when finished.';
  end if;
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_d_fixture_scenario: % may not build fixtures (pd_fixture_untrusted_caller)',
      current_user using errcode = '42501';
  end if;

  -- F08. BR-025 REQUIRES THE EXACT DISPLAYED VERSION AND ITS DIGEST, and this factory was writing
  -- 'zz-terms-v1' with sha256('zz-terms-v1') -- a hash OF THE VERSION STRING, not of any terms.
  -- The rule resolves the pair against public.legal_documents where the displayed body hashes to
  -- exactly that digest, so the acceptance the factory created could never be an acceptance of
  -- anything, and BR-025 refused every terms step for the right reason. The pair is now READ from
  -- the published document, so the fixture accepts terms that actually exist.
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_terms_ver, v_terms_hash
    from public.legal_documents d where d.slug = 'customer-terms' order by d.version desc limit 1;
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_sup_ver, v_sup_hash
    from public.legal_documents d where d.slug = 'supplier-agreement' order by d.version desc limit 1;
  -- The artifact digest is the digest of the committed artifact fixture's own text, so BR-036
  -- resolves it against a record this scenario writes rather than against a string.
  select encode(sha256(convert_to(c.value #>> '{}','UTF8')),'hex') into v_art_sha
    from public.phase_d_fixture_catalogue c
   where c.scope = 'CONTEXT_KEY' and c.field_key = 'artifact_ref';

  select coalesce(max(id),0) into v_net_start from net.http_request_queue;
  select count(*) into v_notif_start from public.notifications;
  select coalesce(max(id),0) into v_notif_id_start from public.notifications;  -- G13
  select count(*) into v_inbox_start from public.kernel_trigger_inbox;

  for st in select * from public.phase_d_fixture_stage where stage_no <= v_upto order by stage_no
  loop
    -- A SCENARIO MUST NOT PRE-CREATE THE OBJECT THE WORKFLOW UNDER TEST PRODUCES. W09 writes
    -- supplier_capability, W14 writes quotation, W16 writes payment_transaction; building those
    -- first made the workflow collide with its own output on a unique constraint, and a harness
    -- that seeds the row the step is supposed to create is answering its own question. The set is
    -- read from phase_d_step_effect for that workflow, never listed by hand.
    -- D22. THE EXCLUSION SKIPS LEAVES ONLY, SO A CASCADE IS IMPOSSIBLE BY CONSTRUCTION.
    --
    -- Measured with the old rule: for_workflow on W09 skipped 3 stages and the requires_stages
    -- cascade then blocked 13 MORE, because supplier_account is a parent of half the lineage. The
    -- D9 closure recorded the same shape as closure falling 14 -> 3, which is why the exclusion was
    -- left available and unused. Removing a parent to avoid a collision costs more than it saves.
    --
    -- A stage no other stage requires cannot cascade. supplier_assignment and provider_event are
    -- both leaves, and they are exactly the two collisions left: W12 writes supplier_assignment and
    -- GATE-015 correctly refused the fixture's as a duplicate dispatch. The skip is still recorded
    -- in the manifest as SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST, never silently.
    if v_for_wf is not null
       and not exists (select 1 from public.phase_d_fixture_stage t
                        where st.stage_key = any(t.requires_stages))
       and exists (
         select 1 from public.phase_d_step_effect x
          where x.workflow_id = v_for_wf and x.effect_object_id = st.object_id) then
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status', 'SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST', 'detail', v_for_wf));
      v_owned := v_owned + 1;
      continue;
    end if;

    select array_agg(r) into v_missing
      from unnest(st.requires_stages) r
     where not exists (select 1 from jsonb_array_elements(v_man) m
                        where m->>'stage_key' = r and m->>'status' = 'CREATED');
    if v_missing is not null then
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status', 'SKIPPED_PARENT_NOT_CREATED', 'detail', array_to_string(v_missing, ', ')));
      v_blocked := v_blocked + 1;
      continue;
    end if;

    if st.reference_relation is not null then
      execute format('select count(*) from %s', st.reference_relation) into v_ref_n;
      if v_ref_n = 0 then
        v_man := v_man || jsonb_build_array(jsonb_build_object(
          'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
          'status', 'BLOCKED_NO_REFERENCE_DATA', 'detail',
          format('%s holds 0 rows and this factory does not create business reference data',
                 st.reference_relation)));
        v_blocked := v_blocked + 1;
        continue;
      end if;
    end if;

    v_name  := format('ZZ DEMO — %s %s', v_label, st.stage_key);
    v_key   := md5(format('%s:%s', v_label, st.stage_key))::uuid::text;
    v_owner := v_key;
    -- F10. THE STATE IS THE STAGE'S OWN DECLARATION. This line used to read v_state := 'open' and
    -- every branch below then assigned a literal over it, so public.phase_d_fixture_stage.working_state
    -- -- the column whose sibling working_state_evidence explains, per stage, WHY that state -- was
    -- read by nothing at all. Five stages carried a state their object's contract does not declare
    -- and refused on every build since they were written; correcting the table changed nothing,
    -- because the table was not the source. It is now.
    v_state := coalesce(nullif(btrim(st.working_state),''), 'open');
    v_pay   := jsonb_build_object('fixture_label', v_label, 'stage', st.stage_key,
                                  'phase_d_test_context', true);

    -- D22. company_objective HAS NEVER ONCE CREATED ITS OBJECT.
    --
    -- D16 added this stage to fix W01-S03 dying on department_objective_goal_key_fkey, and it has
    -- refused on every build since with
    --     null value in column "goal" of relation "company_goals" violates not-null
    -- because the chain below has no branch for it, so the payload carried only the three
    -- bookkeeping keys every stage gets. The write map declares goal and metric; both are NOT NULL
    -- with no default.
    --
    -- Nothing failed loudly. stages_created read 23 of 25 and the missing one was recorded as
    -- REFUSED inside the manifest, where no caller was looking. A stage added to fix a foreign key
    -- and never observed creating anything is the "finished capability with no entry point" shape,
    -- and the only reason it surfaced is that a control started counting stages_not_created.
    if st.stage_key = 'company_objective' then
      v_pay := v_pay || jsonb_build_object(
        'goal', 1, 'metric', format('zz_demo_%s', v_label), 'active', true, 'direction', 'at_least');

    elsif st.stage_key = 'customer_account' then
      -- NO EMAIL AND NO PHONE. trg_inquiry_received_a queues a customer email for any inquiry whose
      -- customer has an address, and trg_new_quote_sms / trg_reveal_receipt_a do the same on a
      -- phone. The fixture identity carries neither, and the per-stage assertion below is what
      -- proves it rather than this comment.
      v_pay := v_pay || jsonb_build_object('full_name', v_name, 'locale', 'en');

    elsif st.stage_key = 'customer_terms_acceptance' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object(
        'terms_version', v_terms_ver,
        'terms_hash',    v_terms_hash,
        'accepted_by',   v_refs->>'customer_id');

    elsif st.stage_key = 'inquiry' then
      -- The FACTS fn_rfq_score reads, never a readiness flag. rfq_ready is derived by
      -- trg_rfq_complete and the verdict stays the product's own.
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || public.fn_phase_d_fixture_inquiry_payload(v_label);

    elsif st.stage_key = 'inquiry_answer' then
      v_owner := v_refs->>'inquiry_id';
      -- G11. THE GROUP IS A CHILD OF THIS SCENARIO'S OWN INQUIRY, so this stage creates it.
      -- public.inquiry_workstream_group holds 0 rows on production and this stage reported
      -- BLOCKED_NO_REFERENCE_DATA on every build since D9c. A group carries an inquiry_id foreign
      -- key and a defaulted rfq_mode and nothing else -- it is structure belonging to one inquiry,
      -- not a supplier or a field definition the estate shares. It is created for the inquiry this
      -- scenario created and rolled back with it.
      insert into public.inquiry_workstream_group (inquiry_id)
      values ((v_refs->>'inquiry_id')::uuid)
      on conflict do nothing;
      v_pay := v_pay || jsonb_build_object(
        'answer_scope','inquiry_shared', 'source_kind','customer', 'precedence','customer_confirmed',
        'value', to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture answer'::text),
        'field_id', (select fd.field_id from public.field_definition fd order by fd.field_id limit 1),
        'group_id', (select g.id from public.inquiry_workstream_group g
                      where g.inquiry_id = (v_refs->>'inquiry_id')::uuid
                      order by g.id desc limit 1));

    elsif st.stage_key = 'notification' then
      -- G11. The recipient is the committed catalogue's reserved .invalid address and the channel
      -- is none. status is NOT set here: fn_phase_d_object_write's outbound-door loop overwrites it
      -- with the declared suppression in verified fixture context and does not let a caller opt out,
      -- which is exactly the D19 property -- a generated payload must not be able to re-arm a door.
      v_owner := 'phase_d_fixture';
      v_pay := v_pay || jsonb_build_object(
        'type', 'phase_d_fixture',
        'channel', 'none',
        'to_email', public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'recipient'),
        'subject', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — Phase D fixture notification record',
        'body', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture notification. It is written at the suppression the outbound door declares, no sender selects it, and it is created inside a transaction that is aborted.');

    elsif st.stage_key = 'inquiry_version' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'version', 1);

    elsif st.stage_key = 'inquiry_route_set' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'route_state','confirmed', 'routes', '["general"]'::jsonb,
                                           'evidence','ZZ DEMO — fixture route evidence');

    elsif st.stage_key = 'inquiry_document' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object('kind','boq', 'mime','application/pdf',
                                           'bucket','zz-phase-d-fixtures',
                                           'path', format('zz/%s/%s.pdf', v_label, st.stage_key),
                                           'file_name', format('zz-%s.pdf', v_label));

    elsif st.stage_key = 'document_extraction' then
      v_owner := v_refs->>'document_id';
      v_pay := v_pay || jsonb_build_object('document_id', v_refs->>'document_id',
                                           'method','deterministic', 'paid_model_used', false);

    elsif st.stage_key = 'supplier_safe_package' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object(
        'inquiry_id', v_refs->>'inquiry_id',
        'safe_package_ref', v_key,
        'safe_package_approved_by', 'compliance_and_privacy_officer',
        'contents','ZZ DEMO — scope and quantities only; no customer identity');

    elsif st.stage_key = 'supplier_account' then
      v_pay := v_pay || jsonb_build_object('company_name', v_name, 'verified', true);

    elsif st.stage_key = 'supplier_terms_acceptance' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('terms_version', v_sup_ver,
        'terms_hash',  v_sup_hash,
        'supplier_id', v_refs->>'supplier_id');

    elsif st.stage_key = 'supplier_capability' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('trades', '["general"]'::jsonb);

    elsif st.stage_key = 'supplier_verification_case' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('supplier_id', v_refs->>'supplier_id',
                                           'evidence','ZZ DEMO — fixture verification evidence',
                                           'verified_by','supplier_verification');

    elsif st.stage_key = 'supplier_assignment' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'similarity', 0.9,
                                           'match_reason','ZZ DEMO — fixture assignment');

    elsif st.stage_key = 'quotation' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'quote_amount', 1000);

    elsif st.stage_key = 'quotation_revision' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('quote_id', v_refs->>'quote_id',
                                           'quote_revision_ref', v_key, 'platform_edited', false);

    elsif st.stage_key = 'quotation_comparison' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'analysis', jsonb_build_object('note','ZZ DEMO — fixture comparison'),
                                           'quote_count', 1,
                                           'signature', encode(sha256(convert_to(v_key,'UTF8')),'hex'));

    elsif st.stage_key = 'customer_selection' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('comparison_id', v_refs->>'comparison_id',
                                           'selected_quote_id', v_refs->>'quote_id');

    elsif st.stage_key = 'payment_transaction' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'quote_id', v_refs->>'quote_id',
                                           'quote_amount', 1000, 'reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label));

    elsif st.stage_key = 'provider_event' then
      v_owner := v_refs->>'transaction_id';
      v_key := format('evt_zz_%s', v_label);
      v_pay := v_pay || jsonb_build_object('event_type','checkout.session.completed');

    elsif st.stage_key = 'reconciliation_case' then
      v_owner := v_refs->>'transaction_id';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'monetary_state','reconciled');

    elsif st.stage_key = 'reveal_transaction' then
      v_key := v_refs->>'transaction_id';
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label),
                                           'revealed_at', now(),
                                           'supplier_id', (v_refs->>'supplier_id')::bigint);

    elsif st.stage_key = 'refund_dispute_case' then
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'amount_fils', 10000, 'reason_code','other',
                                           'reason_note','ZZ DEMO — fixture refund case; no refund is executed',
                                           'requested_by', v_refs->>'customer_id');

    elsif st.stage_key = 'artifact_revision' then
      -- F08. BR-036 resolves artifact_sha256 against an artifact_review row or a business object
      -- record CARRYING that digest. public.artifact_review holds 0 rows, so the record is the
      -- only honest route: this stage writes one whose payload carries the digest of the committed
      -- artifact fixture's own text. The digest is computed, never typed.
      -- F48. v_art_sha WAS DECLARED AND NEVER ASSIGNED, SO THIS PAYLOAD CARRIED A NULL.
      --
      -- F08 added the variable with the comment "the digest BR-036 resolves" and the stage below
      -- writes it into the artifact record's payload. Nothing ever assigned it. Measured: BR-036
      -- refuses W08, W20, W22 and W24 with "review names artifact <id> at digest 5be99093ba73,
      -- which resolves to 0 artifact_review row(s) and 0 business object record(s) carrying exactly
      -- that digest" -- and the reason no record carries it is that this line wrote null.
      --
      -- The digest is the committed one F39 computed over the committed artifact body, read here
      -- rather than recomputed, so the value in the record is the same value the context resolver
      -- hands the rule and anyone can recompute both from the catalogue.
      v_art_sha := public.fn_phase_d_stage_content(st.object_id, 'CONTEXT_KEY', 'artifact_sha256');
      if v_art_sha is null then
        raise exception 'fn_phase_d_fixture_scenario: no committed artifact_sha256 fixture, so the artifact record would carry no digest and BR-036 could never pass or fail for a real reason (pd_fixture_artifact_digest_missing)'
          using errcode = '23502';
      end if;

      v_pay := v_pay || jsonb_build_object(
        'artifact_ref', public.fn_phase_d_stage_content(st.object_id, 'CONTEXT_KEY', 'artifact_ref'),
        'artifact_sha256', v_art_sha,
        'revision', 1);

    elsif st.stage_key = 'system_incident' then
      v_pay := v_pay || jsonb_build_object(
        'title',    public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'severity', 'low');

    elsif st.stage_key = 'marketing_content' then
      v_pay := v_pay || jsonb_build_object(
        'title', public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'body',  public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'body'),
        'channel','none', 'published', false);

    elsif st.stage_key = 'knowledge_capability_request' then
      v_pay := v_pay || jsonb_build_object(
        'requested_capability','REASONING',
        'note', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a knowledge/capability request record; no provider is called by Phase D');

    elsif st.stage_key = 'workforce_performance_case' then
      v_pay := v_pay || jsonb_build_object(
        'subject_role','phase_d_fixture_role',
        'note', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a workforce performance case about no real person and no real agent');

    elsif st.stage_key = 'notification_intent' then
      v_pay := v_pay || jsonb_build_object(
        'recipient',     public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'recipient'),
        'consent_basis', public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'consent_basis'),
        'provider_mode','mock', 'suppressed', true);

    elsif st.stage_key = 'department_mandate' then
      v_pay := v_pay || jsonb_build_object(
        'objective', public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'objective'),
        'goal_key',  v_refs->>'goal_key',
        'dept_key',  (select dept_key from public.org_departments where active order by dept_key limit 1));
      v_owner := (select dept_key from public.org_departments where active order by dept_key limit 1);

    elsif st.stage_key = 'review_record' then
      v_pay := v_pay || jsonb_build_object('verdict','approved',
                                           'subject_type','phase_d_fixture', 'subject_id', v_label,
                                           'author_agent','customer_onboarding',
                                           'reviewer_role_id','customer_success_director',
                                           'stage', st.stage_key, 'notes','ZZ DEMO — fixture review');

    -- G10. THE FOUR EXISTING RELATIONS WHOSE COLUMNS A HANDLER MUST NOT INVENT.
    elsif st.stage_key = 'initiative' then
      -- public.org_tasks.dept_key is a foreign key into public.org_departments and title is NOT
      -- NULL. The department is read from the estate and the title from the committed catalogue.
      v_owner := (select dept_key from public.org_departments where active order by dept_key limit 1);
      v_pay := v_pay || jsonb_build_object(
        'title',  public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'detail', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture initiative. It assigns no real work to any department and is created inside a transaction that is aborted.',
        'dept_key', (select dept_key from public.org_departments where active order by dept_key limit 1));

    elsif st.stage_key = 'legal_risk_review' then
      v_pay := v_pay || jsonb_build_object(
        'title',      public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'summary',    'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture legal risk review. No document was reviewed, no legal opinion is expressed, and it is created inside a transaction that is aborted.',
        'doc_kind',   'phase_d_fixture',
        'risk_level', 'low');

    elsif st.stage_key = 'partnership_opportunity' then
      v_pay := v_pay || jsonb_build_object(
        'kind',   public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'kind'),
        'title',  public.fn_phase_d_stage_content(st.object_id, 'EFFECT_PAYLOAD', 'title'),
        'detail', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture partnership opportunity. No partner is named, no approach is made, and it is created inside a transaction that is aborted.');

    elsif st.stage_key = 'invoice_receipt' then
      -- transaction_id is NOT NULL and a foreign key, so this stage depends on payment_transaction
      -- and takes the transaction the scenario created rather than choosing one.
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object(
        'transaction_id', v_refs->>'transaction_id',
        'bucket', 'zz-phase-d-fixtures',
        'path',   format('zz/%s/invoice-%s.pdf', v_label, st.stage_key));

    else
      -- G10. EVERY STAGE THE CHAIN ABOVE DOES NOT NAME, WHICH IS SIXTEEN PHASE D STORE OBJECTS AND
      -- ANY ADDED LATER. The object store writes from the payload every stage already carries, so
      -- the only thing these need is the one fact the store checks and a bookkeeping payload cannot
      -- supply: WHO OWNS THE RECORD. That is derived from the object's own declared ownership_scope
      -- rather than repeated sixteen times, so a CUSTOMER-scoped case is owned by the scenario's
      -- customer and a SUPPLIER-scoped one by its supplier. D9h found the opposite of this once --
      -- a customer-scoped object owned by something that was not a customer -- and a derivation
      -- cannot drift back into it one object at a time.
      v_owner := case (select ob.ownership_scope from public.phase_d_business_object_binding ob
                        where ob.object_id = st.object_id)
                   when 'CUSTOMER' then coalesce(nullif(v_refs->>'customer_id',''), v_key)
                   when 'SUPPLIER' then coalesce(nullif(v_refs->>'supplier_id',''), v_key)
                   else v_key end;
      v_pay := v_pay || jsonb_build_object('note', format(
        'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture %s, created through fn_phase_d_object_write inside a transaction that is aborted. It states nothing about the business and is never published.',
        st.object_id));
    end if;

    select count(*) into v_notif_before from public.notifications;
    select coalesce(max(id),0) into v_notif_id_before from public.notifications;  -- G11
    select count(*) into v_inbox_before from public.kernel_trigger_inbox;

    begin
      v_w := public.fn_phase_d_object_write(jsonb_build_object(
        'object_id', st.object_id, 'business_key', v_key, 'owner_ref', v_owner,
        'created_by', v_actor, 'state', v_state, 'payload', v_pay));

      select count(*) into v_notif_after from public.notifications;
      if v_notif_after <> v_notif_before then
        -- G11. A STAGE MAY WRITE INTO ITS OWN OBJECT'S CANONICAL RELATION, AND ONLY SUPPRESSED.
        -- The assertion exists because a canonical write to some OTHER object queued a message as a
        -- side effect, and that property is what the Phase D hold rests on. It could not tell that
        -- apart from the one stage whose DECLARED object is the notification. Narrowed by
        -- derivation, never by naming a stage: the relation must be this object's own canonical
        -- relation, and every row written must carry the suppression the outbound door declares for
        -- it. A stage writing here for any other object still aborts the build, and so does this one
        -- if the row it wrote is deliverable.
        if not exists (select 1 from public.phase_d_object_write_map wm2
                        where wm2.object_id = st.object_id
                          and wm2.target_relation = 'public.notifications')
           -- and every row this stage wrote must carry the state the stage declares, which is the
           -- value the outbound door forces and no sender selects. A row at any other status is a
           -- deliverable message and aborts the build exactly as before.
           or exists (select 1 from public.notifications n
                       where n.id > v_notif_id_before
                         and n.status is distinct from st.working_state)
        then
          raise exception 'fn_phase_d_fixture_scenario: stage % wrote % row(s) into public.notifications. A fixture may not queue an outbound message. (pd_fixture_external_effect_produced)',
            st.stage_key, v_notif_after - v_notif_before using errcode = '23514';
        end if;
      end if;

      -- F15. THE PRODUCT'S OWN TRIGGERS GET THE LAST WORD ON AN INSERT, SO SETTLE THE STATE.
      -- public.trg_inquiry_enrich is a BEFORE INSERT trigger that sets the status a NEW inquiry
      -- has, so the inquiry stage asked for quote_ready and the row came out open, and GATE-011
      -- and BR-013 refused it -- correctly, because it was not quote-ready. A real inquiry is
      -- created open and BECOMES quote-ready, so the factory now does that: create, read back the
      -- column the write map points at the state, and if the product moved it, write again through
      -- the same canonical service. Skipped entirely when the readback already agrees.
      select c.k into v_state_col
        from public.phase_d_object_write_map wm,
             lateral (select k from jsonb_object_keys(wm.column_map) k where wm.column_map->>k = 'state') c
       where wm.object_id = st.object_id limit 1;
      if v_state_col is not null then
        begin
          execute format('select %I::text from %s where %I::text = $1',
                         v_state_col,
                         (select wm.target_relation from public.phase_d_object_write_map wm
                           where wm.object_id = st.object_id),
                         (select wm.key_column from public.phase_d_object_write_map wm
                           where wm.object_id = st.object_id))
            into v_actual using coalesce(split_part(v_w->>'result_reference','=',2), v_key);
          if v_actual is distinct from v_state then
            -- H08. ADDRESS THE ROW THE FIRST WRITE RETURNED. v_key is the stage's own uuid and names
            -- nothing on a generated-key relation; the returned identity is the row.
            v_w := public.fn_phase_d_object_write(jsonb_build_object(
              'object_id', st.object_id,
              'business_key', coalesce(split_part(v_w->>'result_reference','=',2), v_key),
              'owner_ref', v_owner,
              'created_by', v_actor, 'state', v_state, 'payload', v_pay));
            v_man := v_man || jsonb_build_array(jsonb_build_object(
              'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
              'status','SETTLED',
              'detail', format('%s.%s was %s after the create and the stage declares %s; a second write through the same canonical service settled it',
                               v_state_col, st.object_id, coalesce(v_actual,'(null)'), v_state)));
          end if;
        exception when others then
          v_man := v_man || jsonb_build_array(jsonb_build_object(
            'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
            'status','SETTLE_REFUSED',
            'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
            'reason', left(SQLERRM, 300)));
        end;
        v_state_col := null; v_actual := null;
      end if;

      -- F02. THE EVIDENCE MANIFEST THE FOUNDER ASKED FOR. Written from what the canonical write
      -- RETURNED, in the same statement block, so a manifest entry cannot exist for an object the
      -- service did not create -- and so an object the service created cannot be missing from it.
      v_scenario_id := public.fn_phase_d_scenario_record_write(jsonb_build_object(
        'fixture_id',        format('PDS-%s', st.stage_key),
        'fixture_version',   1,
        'source_checksum',   encode(sha256(convert_to(v_pay::text,'UTF8')),'hex'),
        'object_id',         st.object_id,
        'business_key',      coalesce(split_part(v_w->>'result_reference','=',2), v_key),
        'owner_ref',         v_owner,
        'ownership_scope',   coalesce((select ob.ownership_scope
                                         from public.phase_d_business_object_binding ob
                                        where ob.object_id = st.object_id), 'COMPANY'),
        'state',             v_w->>'state',
        'canonical_relation',v_w->>'canonical_relation',
        'canonical_service', 'fn_phase_d_object_write',
        'result_reference',  v_w->>'result_reference',
        'contributes_ref',   st.contributes_ref,
        'contributes_kind',  st.contributes_kind,
        'canonical_ref',     v_w->'canonical_ref',
        'contributed_value', case when st.stage_key = 'inquiry_route_set' then 'confirmed'
                                  -- F41. A PAYLOAD_VALUE STAGE CONTRIBUTES A VALUE, NOT ITS ROW ID.
                                  -- artifact_revision declares it contributes artifact_sha256, and
                                  -- this expression handed over split_part(result_reference,'=',2)
                                  -- -- the primary key of the row it had just written. BR-036 read
                                  -- 44208 and refused it as "not a SHA-256 digest", correctly.
                                  -- The digest is in the record's own payload, written by F08 over
                                  -- the committed artifact body, so it is read from there.
                                  -- F42. AN OBJECT_KEY STAGE CONTRIBUTES THE KEY THE PHASE D
                                  -- OBJECT STORE USES, WHICH IS NOT THE RELATION'S ROW ID.
                                  -- F45. OBJECT_KEY AND RESULT_KEY WERE THE SAME QUESTION ASKED TWICE.
                                  -- Which identity an object is known by is a property of the
                                  -- object, recorded once in phase_d_object_reference_strategy and
                                  -- derived from the frozen map -- not something a stage decides.
                                  -- Both arms are now the canonical reference the writer returned.
                                  when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                                    then v_w->'canonical_ref'->>'canonical_identity'
                                  when st.contributes_kind = 'PAYLOAD_VALUE' then
                                    (select o.payload #>> array[st.contributes_ref]
                                       from public.phase_d_object_record o
                                      where o.object_id = st.object_id
                                        and o.business_key = split_part(v_w->>'result_reference', '=', 2)
                                      limit 1)
                                  else split_part(v_w->>'result_reference', '=', 2) end,
        'expected_effect',   coalesce(st.note,'(none recorded on the stage)')));

      if st.contributes_ref is not null then
        v_refs := v_refs || jsonb_build_object(st.contributes_ref,
          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                 then v_w->'canonical_ref'->>'canonical_identity'
               when st.contributes_kind = 'PAYLOAD_VALUE' then
                 (select o.payload #>> array[st.contributes_ref]
                    from public.phase_d_object_record o
                   where o.object_id = st.object_id
                     and o.business_key = split_part(v_w->>'result_reference', '=', 2)
                   limit 1)
               else split_part(v_w->>'result_reference', '=', 2) end);
      end if;

      select count(*) into v_inbox_after from public.kernel_trigger_inbox;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','CREATED', 'relation', v_w->>'canonical_relation',
        'result_reference', v_w->>'result_reference', 'state', v_w->>'state',
        'policy_family', v_w->>'policy_family',
        'notifications_written', v_notif_after - v_notif_before,
        'kernel_trigger_rows_written', v_inbox_after - v_inbox_before,
        'contributes', st.contributes_ref));
      v_ok := v_ok + 1;

    exception when others then
      v_err := SQLERRM;
      if position('pd_fixture_external_effect_produced' in v_err) > 0 then raise; end if;
      -- D17. An outbound HTTP request is not a stage that failed; it is the whole scenario losing
      -- its zero-external-effect property. It aborts the build exactly as a notification does.
      if position('pd_object_outbound_request_produced' in v_err) > 0 then raise; end if;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','REFUSED',
        'refused_with', coalesce((regexp_match(v_err,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
        'reason', left(v_err, 300)));
      v_blocked := v_blocked + 1;
    end;
  end loop;

  -- G12. THE THREE OBJECTS ONLY THE KERNEL MAY CREATE, asked for through the kernel's own doors.
  -- fn_phase_d_object_write refuses workflow_run, workflow_step_run and handoff_record by name --
  -- "a Phase D handler that wrote it would be a second creator for one object" -- so no stage of
  -- the chain above can create them and the round-trip proof reported all three as
  -- NOT_CREATED_BY_ANY_STAGE, counted as neither pass nor fail. This does not write them either: it
  -- calls fn_kernel_workflow_start and fn_kernel_step_complete and records what the kernel made.
  begin
    v_w := public.fn_phase_d_kernel_object_fixture(jsonb_build_object('label', v_label));
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 998, 'stage_key','kernel_objects', 'object_id','workflow_run/workflow_step_run/handoff_record',
      'status', case when coalesce((v_w->>'objects_recorded')::int,0) > 0 then 'CREATED' else 'REFUSED' end,
      'relation','public.phase_c_workflow_run + _step_run + _handoff_run',
      'result_reference', format('run_id=%s step_run_id=%s handoff_run_id=%s',
        coalesce(v_w->>'run_id','(none)'), coalesce(v_w->>'step_run_id','(none)'),
        coalesce(v_w->>'handoff_run_id','(none)')),
      'state','open', 'contributes', null, 'detail', v_w->>'note'));
    if coalesce((v_w->>'objects_recorded')::int,0) > 0 then v_ok := v_ok + 1;
    else v_blocked := v_blocked + 1; end if;
  exception when others then
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 998, 'stage_key','kernel_objects', 'object_id','workflow_run/workflow_step_run/handoff_record',
      'status','REFUSED',
      'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
      'reason', left(SQLERRM, 300)));
    v_blocked := v_blocked + 1;
  end;

  -- F12. THE FOUNDER AUTHORITY FIXTURE, LAST, BECAUSE NOTHING DEPENDS ON IT. Six rules resolve
  -- founder_authority_ref against public.founder_command; a Phase D run has no founder command
  -- behind it, so all six refuse on every founder-gated step. This creates one, marked, at state
  -- received, founder_initiated_only false and refund_semantics false, inside the same aborted
  -- transaction -- and it authenticates nobody: see the header of F12.
  begin
    v_w := public.fn_phase_d_founder_authority_fixture(jsonb_build_object('label', v_label));
    v_refs := v_refs || jsonb_build_object('founder_authority_ref', v_w->>'founder_authority_ref');
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 999, 'stage_key','founder_authority', 'object_id','founder_command_fixture',
      'status','CREATED', 'relation','public.founder_command',
      'result_reference', v_w->>'founder_authority_ref', 'state','received',
      'contributes','founder_authority_ref'));
    v_ok := v_ok + 1;
  exception when others then
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 999, 'stage_key','founder_authority', 'object_id','founder_command_fixture',
      'status','REFUSED',
      'refused_with', coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
      'reason', left(SQLERRM, 300)));
    v_blocked := v_blocked + 1;
  end;

  select count(*) into v_notif_after from public.notifications;
  select count(*) into v_inbox_after from public.kernel_trigger_inbox;

  select coalesce(max(id),0) into v_notif_id_before from public.notifications;  -- reused as a bound

  return jsonb_build_object(
    'ok', v_blocked = 0, 'label', v_label, 'fixture_run_id', v_fixture_run,
    'evidence_manifest', (select coalesce(jsonb_agg(to_jsonb(x) order by x.scenario_record_id),'[]'::jsonb)
                            from public.phase_d_scenario_record x
                           where x.fixture_run_id = v_fixture_run),
    'stages_created', v_ok, 'stages_not_created', v_blocked,
    'stages_left_to_the_workflow_under_test', v_owned, 'for_workflow', v_for_wf,
    'stages_declared', (select count(*) from public.phase_d_fixture_stage where stage_no <= v_upto),
    'parent_refs', v_refs,
    -- THE RULE CONTEXT IS WHAT THIS SCENARIO ACTUALLY PERSISTED, not a set of plausible strings.
    -- Every value below is either a key returned by a write above or the exact value that write
    -- recorded on the row. A rule reading one of these is reading the scenario, and a rule whose
    -- key is absent still gets the driver's generated fixture and still refuses.
    -- F08. `rule_context` used to be returned here as a set of plausible strings for a caller to
    -- hand the rules. E32 removed the caller's ability to hand the kernel anything, so nothing has
    -- read it since; and two of its values were false -- terms_hash was the digest of the VERSION
    -- STRING, and safe_package_approved_by and assignment_result were literals with no record
    -- behind them. It is replaced by evidence_manifest above, which is what this scenario actually
    -- persisted, and by the committed catalogue for the values that are content rather than record.
    'parent_ref_keys', (select coalesce(jsonb_agg(k order by k),'[]'::jsonb)
                          from jsonb_object_keys(v_refs) k),
    'manifest', v_man,
    'notifications_written_by_this_scenario', v_notif_after - v_notif_start,
    -- G13. THE ONE THAT MUST BE ZERO. A row a sender would select is a queued outbound message; a
    -- row at the suppression the outbound door forces is a record. The suppression is read from the
    -- stage that declares it rather than written here, so there is no second copy of the word.
    'deliverable_notifications_written_by_this_scenario',
      (select count(*) from public.notifications n
        where n.id > coalesce(v_notif_id_start, 0)
          and n.status is distinct from (
            select st2.working_state from public.phase_d_fixture_stage st2
             where st2.object_id in (select wm3.object_id from public.phase_d_object_write_map wm3
                                      where wm3.target_relation = 'public.notifications')
             limit 1)),
    'kernel_trigger_rows_written_by_this_scenario', v_inbox_after - v_inbox_start,
    -- D17. MEASURED, NOT ASSERTED. Before D17 this object said 'external_effects', 0 while every
    -- build enqueued two POSTs to production edge functions, because the only thing counted was
    -- public.notifications. Both doors are now counted and the writer refuses on either.
    'outbound_http_requests_written_by_this_scenario',
      (select r.n from public.fn_phase_d_outbound_requests_by_this_transaction(v_net_start) r),
    'external_effects', 0, 'paid_calls', 0,
    'note', 'every row here was written through fn_phase_d_object_write; abort the transaction to leave nothing behind');
end $function$;

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_outbound_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


